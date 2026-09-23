package service

import (
	"context"
	"strings"

	"github.com/remus-craciun/index/server/internal/db/sqlcgen"
	"github.com/remus-craciun/index/server/internal/timeutil"
)

type TaskInput struct {
	ID               *string `json:"id"`
	MilestoneID      *string `json:"milestone_id"`
	Title            string  `json:"title"`
	Notes            string  `json:"notes"`
	ScheduledDate    *string `json:"scheduled_date"`
	StartTime        *string `json:"start_time"`
	EndTime          *string `json:"end_time"`
	EstimatedMinutes *int64  `json:"estimated_minutes"`
	ReminderMinutes  *int64  `json:"reminder_minutes"`
	Status           *string `json:"status"`
}

type TaskPatch struct {
	MilestoneID      Optional[string] `json:"milestone_id"`
	Title            *string          `json:"title"`
	Notes            *string          `json:"notes"`
	ScheduledDate    Optional[string] `json:"scheduled_date"`
	StartTime        Optional[string] `json:"start_time"`
	EndTime          Optional[string] `json:"end_time"`
	EstimatedMinutes Optional[int64]  `json:"estimated_minutes"`
	ReminderMinutes  Optional[int64]  `json:"reminder_minutes"`
	Status           *string          `json:"status"`
}

type TaskFilter struct {
	ScheduledDate *string
	Status        *string
	MilestoneID   *string
	AdhocOnly     bool
}

func (s *Service) ListTasks(ctx context.Context, userID string, f TaskFilter) ([]Task, error) {
	if err := timeutil.ValidateDatePtr(f.ScheduledDate); err != nil {
		return nil, invalid("%v", err)
	}
	if f.Status != nil {
		if err := checkStatus(*f.Status, taskStatuses); err != nil {
			return nil, err
		}
	}
	rows, err := s.store.ListTasks(ctx, sqlcgen.ListTasksParams{
		UserID: userID, ScheduledDate: f.ScheduledDate, Status: f.Status,
		MilestoneID: f.MilestoneID, AdhocOnly: f.AdhocOnly,
	})
	if err != nil {
		return nil, err
	}
	return mapRows(rows, taskFromRow), nil
}

func (s *Service) CreateTask(ctx context.Context, userID string, in TaskInput) (Task, error) {
	id, err := newID(in.ID)
	if err != nil {
		return Task{}, err
	}
	title, err := requireTitle(in.Title)
	if err != nil {
		return Task{}, err
	}
	if err := timeutil.ValidateDatePtr(in.ScheduledDate); err != nil {
		return Task{}, invalid("%v", err)
	}
	if err := checkMinutes(in.EstimatedMinutes); err != nil {
		return Task{}, err
	}
	if err := checkTimeWindow(in.StartTime, in.EndTime); err != nil {
		return Task{}, err
	}
	if err := checkReminder(in.ReminderMinutes); err != nil {
		return Task{}, err
	}
	status := "pending"
	if in.Status != nil {
		status = *in.Status
	}
	if err := checkStatus(status, taskStatuses); err != nil {
		return Task{}, err
	}

	var out Task
	err = s.store.InWriteTx(ctx, func(q *sqlcgen.Queries, rev int64) error {
		if err := checkMilestoneOwned(ctx, q, userID, in.MilestoneID); err != nil {
			return err
		}
		now := s.nowString()
		if err := q.InsertTask(ctx, sqlcgen.InsertTaskParams{
			ID: id, UserID: userID, MilestoneID: in.MilestoneID, Title: title, Notes: strings.TrimSpace(in.Notes),
			ScheduledDate: in.ScheduledDate, StartTime: in.StartTime, EndTime: in.EndTime,
			EstimatedMinutes: in.EstimatedMinutes, ReminderMinutes: in.ReminderMinutes, Status: status,
			CompletedAt: completedAtFor(status, nil, now), CreatedAt: now, UpdatedAt: now, ServerRev: rev,
		}); err != nil {
			return err
		}
		t, err := q.GetTask(ctx, sqlcgen.GetTaskParams{ID: id, UserID: userID})
		out = taskFromRow(t)
		return err
	})
	return out, err
}

func (s *Service) UpdateTask(ctx context.Context, userID, id string, in TaskPatch) (Task, error) {
	var out Task
	err := s.store.InWriteTx(ctx, func(q *sqlcgen.Queries, rev int64) error {
		t, err := q.GetTask(ctx, sqlcgen.GetTaskParams{ID: id, UserID: userID})
		if err != nil {
			return wrapNotFound(err)
		}
		if in.MilestoneID.Set {
			if err := checkMilestoneOwned(ctx, q, userID, in.MilestoneID.Value); err != nil {
				return err
			}
			t.MilestoneID = in.MilestoneID.Value
		}
		if in.Title != nil {
			if t.Title, err = requireTitle(*in.Title); err != nil {
				return err
			}
		}
		if in.Notes != nil {
			t.Notes = strings.TrimSpace(*in.Notes)
		}
		in.ScheduledDate.apply(&t.ScheduledDate)
		if err := timeutil.ValidateDatePtr(t.ScheduledDate); err != nil {
			return invalid("%v", err)
		}
		in.EstimatedMinutes.apply(&t.EstimatedMinutes)
		if err := checkMinutes(t.EstimatedMinutes); err != nil {
			return err
		}
		in.StartTime.apply(&t.StartTime)
		in.EndTime.apply(&t.EndTime)
		if err := checkTimeWindow(t.StartTime, t.EndTime); err != nil {
			return err
		}
		in.ReminderMinutes.apply(&t.ReminderMinutes)
		if err := checkReminder(t.ReminderMinutes); err != nil {
			return err
		}
		if in.Status != nil {
			t.Status = *in.Status
		}
		if err := checkStatus(t.Status, taskStatuses); err != nil {
			return err
		}
		t.UpdatedAt = s.nowString()
		t.CompletedAt = completedAtFor(t.Status, t.CompletedAt, t.UpdatedAt)
		if err := q.UpdateTask(ctx, sqlcgen.UpdateTaskParams{
			ID: id, UserID: userID, MilestoneID: t.MilestoneID, Title: t.Title, Notes: t.Notes,
			ScheduledDate: t.ScheduledDate, StartTime: t.StartTime, EndTime: t.EndTime,
			EstimatedMinutes: t.EstimatedMinutes, ReminderMinutes: t.ReminderMinutes, Status: t.Status,
			CompletedAt: t.CompletedAt, UpdatedAt: t.UpdatedAt, ServerRev: rev,
		}); err != nil {
			return err
		}
		out = taskFromRow(t)
		return nil
	})
	return out, err
}

func (s *Service) DeleteTask(ctx context.Context, userID, id string) error {
	return s.store.InWriteTx(ctx, func(q *sqlcgen.Queries, rev int64) error {
		now := s.nowString()
		n, err := q.SoftDeleteTask(ctx, sqlcgen.SoftDeleteTaskParams{Now: &now, ServerRev: rev, ID: id, UserID: userID})
		if err != nil {
			return err
		}
		if n == 0 {
			return ErrNotFound
		}
		return nil
	})
}

func checkMilestoneOwned(ctx context.Context, q *sqlcgen.Queries, userID string, milestoneID *string) error {
	if milestoneID == nil {
		return nil
	}
	if _, err := q.GetMilestone(ctx, sqlcgen.GetMilestoneParams{ID: *milestoneID, UserID: userID}); err != nil {
		if wrapNotFound(err) == ErrNotFound {
			return invalid("milestone %q not found", *milestoneID)
		}
		return err
	}
	return nil
}
