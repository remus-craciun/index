package service

import (
	"context"
	"fmt"
	"strings"

	"github.com/remus-craciun/index/server/internal/ai"
	"github.com/remus-craciun/index/server/internal/db"
	"github.com/remus-craciun/index/server/internal/db/sqlcgen"
	"github.com/remus-craciun/index/server/internal/timeutil"
)

const maxSyncRows = 5000

type Changes struct {
	LearningPlans []Plan       `json:"learning_plans"`
	Milestones    []Milestone  `json:"milestones"`
	Recurrences   []Recurrence `json:"recurrences"`
	Tasks         []Task       `json:"tasks"`
}

func (c Changes) len() int {
	return len(c.LearningPlans) + len(c.Milestones) + len(c.Recurrences) + len(c.Tasks)
}

type SyncRequest struct {
	// Cursor is the value returned by the previous sync; 0 pulls everything.
	Cursor  int64   `json:"cursor"`
	Changes Changes `json:"changes"`
}

type SyncResponse struct {
	// Cursor must be sent with the next sync.
	Cursor int64 `json:"cursor"`
	// Reset is true when the client's cursor was ahead of the server (for
	// example after a server restore) and a full snapshot was returned.
	// The client should replace its local state with Changes.
	Reset   bool    `json:"reset"`
	Changes Changes `json:"changes"`
}

// Sync applies the client's changes with last-write-wins on updated_at and
// returns every row changed since the client's cursor, plus the server's
// copy of any pushed row that lost the conflict.
func (s *Service) Sync(ctx context.Context, userID string, req SyncRequest) (SyncResponse, error) {
	if req.Cursor < 0 {
		return SyncResponse{}, invalid("cursor must be >= 0")
	}
	if n := req.Changes.len(); n > maxSyncRows {
		return SyncResponse{}, invalid("too many changes in one sync (%d > %d); split into batches", n, maxSyncRows)
	}
	in, err := normalizeChanges(req.Changes)
	if err != nil {
		return SyncResponse{}, err
	}

	var resp SyncResponse
	err = s.store.InTx(ctx, func(q *sqlcgen.Queries) error {
		cursor := req.Cursor
		current, err := q.CurrentRev(ctx)
		if err != nil {
			return err
		}
		if cursor > current {
			cursor, resp.Reset = 0, true
		}

		var lost Changes
		if in.len() > 0 {
			rev, err := q.BumpRev(ctx)
			if err != nil {
				return err
			}
			if lost, err = applyChanges(ctx, q, userID, rev, in); err != nil {
				return err
			}
		}

		pulled, err := pullChanges(ctx, q, userID, cursor)
		if err != nil {
			return err
		}
		// Rows that lost LWW and are not newer than the cursor would
		// otherwise never reach the client; send the server's copy.
		pulled.LearningPlans = append(pulled.LearningPlans, lost.LearningPlans...)
		pulled.Milestones = append(pulled.Milestones, lost.Milestones...)
		pulled.Recurrences = append(pulled.Recurrences, lost.Recurrences...)
		pulled.Tasks = append(pulled.Tasks, lost.Tasks...)
		resp.Changes = pulled

		resp.Cursor, err = q.CurrentRev(ctx)
		return err
	})
	if err != nil {
		if db.IsConstraint(err) {
			return SyncResponse{}, invalid("sync rejected by a database constraint: %v", err)
		}
		return SyncResponse{}, err
	}
	// Drop lost rows the pull already covered (server_rev > cursor).
	resp.Changes = dedupe(resp.Changes)
	return resp, nil
}

func applyChanges(ctx context.Context, q *sqlcgen.Queries, userID string, rev int64, c Changes) (Changes, error) {
	var lost Changes
	for _, p := range c.LearningPlans {
		n, err := q.UpsertPlanLWW(ctx, sqlcgen.UpsertPlanLWWParams{
			ID: p.ID, UserID: userID, Title: p.Title, Description: p.Description, TargetDate: p.TargetDate,
			Status: p.Status, Weekdays: ai.AllWeekdays, CreatedAt: p.CreatedAt, UpdatedAt: p.UpdatedAt, DeletedAt: p.DeletedAt, ServerRev: rev,
		})
		if err != nil {
			return lost, fmt.Errorf("plan %s: %w", p.ID, err)
		}
		if n == 0 {
			if row, err := q.GetPlanIncludingDeleted(ctx, sqlcgen.GetPlanIncludingDeletedParams{ID: p.ID, UserID: userID}); err == nil {
				lost.LearningPlans = append(lost.LearningPlans, planFromRow(row))
			}
		}
	}
	for _, m := range c.Milestones {
		if _, err := q.GetPlanIncludingDeleted(ctx, sqlcgen.GetPlanIncludingDeletedParams{ID: m.PlanID, UserID: userID}); err != nil {
			if db.IsNotFound(err) {
				return lost, invalid("milestone %s references unknown plan %s", m.ID, m.PlanID)
			}
			return lost, err
		}
		n, err := q.UpsertMilestoneLWW(ctx, sqlcgen.UpsertMilestoneLWWParams{
			ID: m.ID, PlanID: m.PlanID, UserID: userID, Title: m.Title, OrderIndex: m.OrderIndex, Status: m.Status,
			CreatedAt: m.CreatedAt, UpdatedAt: m.UpdatedAt, DeletedAt: m.DeletedAt, ServerRev: rev,
		})
		if err != nil {
			return lost, fmt.Errorf("milestone %s: %w", m.ID, err)
		}
		if n == 0 {
			if row, err := q.GetMilestoneIncludingDeleted(ctx, sqlcgen.GetMilestoneIncludingDeletedParams{ID: m.ID, UserID: userID}); err == nil {
				lost.Milestones = append(lost.Milestones, milestoneFromRow(row))
			}
		}
	}
	for _, r := range c.Recurrences {
		n, err := q.UpsertRecurrenceLWW(ctx, sqlcgen.UpsertRecurrenceLWWParams{
			ID: r.ID, UserID: userID, Title: r.Title, Notes: r.Notes, Frequency: r.Frequency,
			RepeatInterval: r.RepeatInterval, Weekdays: r.Weekdays, MonthDay: r.MonthDay, StartTime: r.StartTime,
			EndTime: r.EndTime, EstimatedMinutes: r.EstimatedMinutes, ReminderMinutes: r.ReminderMinutes,
			StartDate: r.StartDate, EndDate: r.EndDate, Status: r.Status, CreatedAt: r.CreatedAt,
			UpdatedAt: r.UpdatedAt, DeletedAt: r.DeletedAt, ServerRev: rev,
		})
		if err != nil {
			return lost, fmt.Errorf("recurrence %s: %w", r.ID, err)
		}
		if n == 0 {
			if row, err := q.GetRecurrenceIncludingDeleted(ctx, sqlcgen.GetRecurrenceIncludingDeletedParams{ID: r.ID, UserID: userID}); err == nil {
				lost.Recurrences = append(lost.Recurrences, recurrenceFromRow(row))
			}
		}
	}
	for _, t := range c.Tasks {
		if t.RecurrenceID != nil {
			if _, err := q.GetRecurrenceIncludingDeleted(ctx, sqlcgen.GetRecurrenceIncludingDeletedParams{ID: *t.RecurrenceID, UserID: userID}); err != nil {
				if db.IsNotFound(err) {
					return lost, invalid("task %s references unknown recurrence %s", t.ID, *t.RecurrenceID)
				}
				return lost, err
			}
		}
		if t.MilestoneID != nil {
			if _, err := q.GetMilestoneIncludingDeleted(ctx, sqlcgen.GetMilestoneIncludingDeletedParams{ID: *t.MilestoneID, UserID: userID}); err != nil {
				if db.IsNotFound(err) {
					return lost, invalid("task %s references unknown milestone %s", t.ID, *t.MilestoneID)
				}
				return lost, err
			}
		}
		n, err := q.UpsertTaskLWW(ctx, sqlcgen.UpsertTaskLWWParams{
			ID: t.ID, UserID: userID, MilestoneID: t.MilestoneID, RecurrenceID: t.RecurrenceID, Title: t.Title,
			Notes: t.Notes, ScheduledDate: t.ScheduledDate, StartTime: t.StartTime, EndTime: t.EndTime,
			EstimatedMinutes: t.EstimatedMinutes, ReminderMinutes: t.ReminderMinutes, Status: t.Status,
			CompletedAt: t.CompletedAt, CreatedAt: t.CreatedAt, UpdatedAt: t.UpdatedAt, DeletedAt: t.DeletedAt,
			ServerRev: rev,
		})
		if err != nil {
			return lost, fmt.Errorf("task %s: %w", t.ID, err)
		}
		if n == 0 {
			if row, err := q.GetTaskIncludingDeleted(ctx, sqlcgen.GetTaskIncludingDeletedParams{ID: t.ID, UserID: userID}); err == nil {
				lost.Tasks = append(lost.Tasks, taskFromRow(row))
			}
		}
	}
	return lost, nil
}

func pullChanges(ctx context.Context, q *sqlcgen.Queries, userID string, cursor int64) (Changes, error) {
	plans, err := q.ListPlansChangedSince(ctx, sqlcgen.ListPlansChangedSinceParams{UserID: userID, Cursor: cursor})
	if err != nil {
		return Changes{}, err
	}
	milestones, err := q.ListMilestonesChangedSince(ctx, sqlcgen.ListMilestonesChangedSinceParams{UserID: userID, Cursor: cursor})
	if err != nil {
		return Changes{}, err
	}
	recurrences, err := q.ListRecurrencesChangedSince(ctx, sqlcgen.ListRecurrencesChangedSinceParams{UserID: userID, Cursor: cursor})
	if err != nil {
		return Changes{}, err
	}
	tasks, err := q.ListTasksChangedSince(ctx, sqlcgen.ListTasksChangedSinceParams{UserID: userID, Cursor: cursor})
	if err != nil {
		return Changes{}, err
	}
	return Changes{
		LearningPlans: mapRows(plans, planFromRow),
		Milestones:    mapRows(milestones, milestoneFromRow),
		Recurrences:   mapRows(recurrences, recurrenceFromRow),
		Tasks:         mapRows(tasks, taskFromRow),
	}, nil
}

func dedupe(c Changes) Changes {
	return Changes{
		LearningPlans: dedupeByID(c.LearningPlans, func(p Plan) string { return p.ID }),
		Milestones:    dedupeByID(c.Milestones, func(m Milestone) string { return m.ID }),
		Recurrences:   dedupeByID(c.Recurrences, func(r Recurrence) string { return r.ID }),
		Tasks:         dedupeByID(c.Tasks, func(t Task) string { return t.ID }),
	}
}

func dedupeByID[T any](rows []T, id func(T) string) []T {
	seen := make(map[string]bool, len(rows))
	out := make([]T, 0, len(rows))
	for _, r := range rows {
		if k := id(r); !seen[k] {
			seen[k] = true
			out = append(out, r)
		}
	}
	return out
}

// normalizeChanges validates pushed rows and canonicalises their IDs and
// timestamps so SQL string comparison implements last-write-wins.
func normalizeChanges(c Changes) (Changes, error) {
	for i := range c.LearningPlans {
		p := &c.LearningPlans[i]
		if err := normalizeCommon(&p.ID, &p.Title, &p.CreatedAt, &p.UpdatedAt, &p.DeletedAt); err != nil {
			return c, invalid("learning_plans[%d]: %v", i, err)
		}
		p.Description = strings.TrimSpace(p.Description)
		if err := timeutil.ValidateDatePtr(p.TargetDate); err != nil {
			return c, invalid("learning_plans[%d]: %v", i, err)
		}
		if err := checkStatus(p.Status, planStatuses); err != nil {
			return c, invalid("learning_plans[%d]: %v", i, err)
		}
	}
	for i := range c.Milestones {
		m := &c.Milestones[i]
		if err := normalizeCommon(&m.ID, &m.Title, &m.CreatedAt, &m.UpdatedAt, &m.DeletedAt); err != nil {
			return c, invalid("milestones[%d]: %v", i, err)
		}
		var err error
		if m.PlanID, err = validID(m.PlanID); err != nil {
			return c, invalid("milestones[%d]: plan_id: %v", i, err)
		}
		if err := checkStatus(m.Status, planStatuses); err != nil {
			return c, invalid("milestones[%d]: %v", i, err)
		}
	}
	for i := range c.Recurrences {
		r := &c.Recurrences[i]
		if err := normalizeCommon(&r.ID, &r.Title, &r.CreatedAt, &r.UpdatedAt, &r.DeletedAt); err != nil {
			return c, invalid("recurrences[%d]: %v", i, err)
		}
		r.Notes = strings.TrimSpace(r.Notes)
		// Clients predating intervals omit these; they mean weekly, every week.
		if r.Frequency == "" {
			r.Frequency = "weekly"
		}
		if r.RepeatInterval == 0 {
			r.RepeatInterval = 1
		}
		switch r.Frequency {
		case "daily", "weekly":
			r.MonthDay = nil
		case "monthly":
			if r.MonthDay == nil || *r.MonthDay < 1 || *r.MonthDay > 31 {
				return c, invalid("recurrences[%d]: monthly recurrences need month_day between 1 and 31", i)
			}
		default:
			return c, invalid("recurrences[%d]: frequency must be daily, weekly or monthly", i)
		}
		if r.RepeatInterval < 1 || r.RepeatInterval > 365 {
			return c, invalid("recurrences[%d]: repeat_interval must be between 1 and 365", i)
		}
		if r.Weekdays < 1 || r.Weekdays > 127 {
			return c, invalid("recurrences[%d]: weekdays must be a bitmask between 1 and 127", i)
		}
		if _, err := timeutil.ParseDate(r.StartDate); err != nil {
			return c, invalid("recurrences[%d]: start_date: %v", i, err)
		}
		if err := timeutil.ValidateDatePtr(r.EndDate); err != nil {
			return c, invalid("recurrences[%d]: end_date: %v", i, err)
		}
		if r.EndDate != nil && *r.EndDate < r.StartDate {
			return c, invalid("recurrences[%d]: end_date must not be before start_date", i)
		}
		if err := checkTimeWindow(r.StartTime, r.EndTime); err != nil {
			return c, invalid("recurrences[%d]: %v", i, err)
		}
		if err := checkMinutes(r.EstimatedMinutes); err != nil {
			return c, invalid("recurrences[%d]: %v", i, err)
		}
		if err := checkReminder(r.ReminderMinutes); err != nil {
			return c, invalid("recurrences[%d]: %v", i, err)
		}
		if err := checkStatus(r.Status, recurrenceStatuses); err != nil {
			return c, invalid("recurrences[%d]: %v", i, err)
		}
	}
	for i := range c.Tasks {
		t := &c.Tasks[i]
		if err := normalizeCommon(&t.ID, &t.Title, &t.CreatedAt, &t.UpdatedAt, &t.DeletedAt); err != nil {
			return c, invalid("tasks[%d]: %v", i, err)
		}
		if t.RecurrenceID != nil {
			id, err := validID(*t.RecurrenceID)
			if err != nil {
				return c, invalid("tasks[%d]: recurrence_id: %v", i, err)
			}
			t.RecurrenceID = &id
		}
		if err := checkTimeWindow(t.StartTime, t.EndTime); err != nil {
			return c, invalid("tasks[%d]: %v", i, err)
		}
		if err := checkReminder(t.ReminderMinutes); err != nil {
			return c, invalid("tasks[%d]: %v", i, err)
		}
		var err error
		if t.CompletedAt, err = timeutil.NormalizePtr(t.CompletedAt); err != nil {
			return c, invalid("tasks[%d]: completed_at: %v", i, err)
		}
		if t.MilestoneID != nil {
			id, err := validID(*t.MilestoneID)
			if err != nil {
				return c, invalid("tasks[%d]: milestone_id: %v", i, err)
			}
			t.MilestoneID = &id
		}
		t.Notes = strings.TrimSpace(t.Notes)
		if err := timeutil.ValidateDatePtr(t.ScheduledDate); err != nil {
			return c, invalid("tasks[%d]: %v", i, err)
		}
		if err := checkMinutes(t.EstimatedMinutes); err != nil {
			return c, invalid("tasks[%d]: %v", i, err)
		}
		if err := checkStatus(t.Status, taskStatuses); err != nil {
			return c, invalid("tasks[%d]: %v", i, err)
		}
	}
	return c, nil
}

func normalizeCommon(id, title, createdAt, updatedAt *string, deletedAt **string) error {
	var err error
	if *id, err = validID(*id); err != nil {
		return err
	}
	if *title, err = requireTitle(*title); err != nil {
		return err
	}
	if *createdAt, err = timeutil.Normalize(*createdAt); err != nil {
		return fmt.Errorf("created_at: %w", err)
	}
	if *updatedAt, err = timeutil.Normalize(*updatedAt); err != nil {
		return fmt.Errorf("updated_at: %w", err)
	}
	if *deletedAt, err = timeutil.NormalizePtr(*deletedAt); err != nil {
		return fmt.Errorf("deleted_at: %w", err)
	}
	return nil
}
