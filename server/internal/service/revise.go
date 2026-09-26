package service

import (
	"context"
	"fmt"
	"sort"
	"strings"

	"github.com/google/uuid"

	"github.com/remus-craciun/index/server/internal/ai"
	"github.com/remus-craciun/index/server/internal/db/sqlcgen"
	"github.com/remus-craciun/index/server/internal/timeutil"
)

// Change is one line of a revision preview.
type Change struct {
	Kind   string `json:"kind"`   // "plan", "milestone" or "task"
	Action string `json:"action"` // "added", "removed", "updated" or "moved"
	Title  string `json:"title"`
	Detail string `json:"detail,omitempty"`
}

// RevisionProposal is what a follow-up request would do to a plan. Nothing
// is stored until it is passed to ApplyRevision.
type RevisionProposal struct {
	Revision      ai.PlanRevision `json:"revision"`
	Summary       string          `json:"summary"`
	Changes       []Change        `json:"changes"`
	MinutesPerDay int             `json:"minutes_per_day"`
}

type ReviseInput struct {
	PlanID        string  `json:"plan_id"`
	Instruction   string  `json:"instruction"`
	Today         *string `json:"today"`
	MinutesPerDay *int    `json:"minutes_per_day"`
}

type ApplyRevisionInput struct {
	Revision      ai.PlanRevision `json:"revision"`
	StartDate     *string         `json:"start_date"`
	MinutesPerDay *int            `json:"minutes_per_day"`
}

// planState is a plan with its live milestones and tasks.
type planState struct {
	plan       sqlcgen.LearningPlan
	milestones []sqlcgen.Milestone
	tasks      []sqlcgen.Task
	mByID      map[string]sqlcgen.Milestone
	tByID      map[string]sqlcgen.Task
}

func loadPlanState(ctx context.Context, q *sqlcgen.Queries, userID, planID string) (planState, error) {
	p, err := q.GetPlan(ctx, sqlcgen.GetPlanParams{ID: planID, UserID: userID})
	if err != nil {
		return planState{}, wrapNotFound(err)
	}
	ms, err := q.ListMilestonesByPlan(ctx, sqlcgen.ListMilestonesByPlanParams{PlanID: planID, UserID: userID})
	if err != nil {
		return planState{}, err
	}
	ts, err := q.ListTasksByPlan(ctx, sqlcgen.ListTasksByPlanParams{PlanID: planID, UserID: userID})
	if err != nil {
		return planState{}, err
	}
	st := planState{plan: p, milestones: ms, tasks: ts, mByID: map[string]sqlcgen.Milestone{}, tByID: map[string]sqlcgen.Task{}}
	for _, m := range ms {
		st.mByID[m.ID] = m
	}
	for _, t := range ts {
		st.tByID[t.ID] = t
	}
	return st, nil
}

func (st planState) current() ai.CurrentPlan {
	out := ai.CurrentPlan{Title: st.plan.Title, Description: st.plan.Description}
	if st.plan.TargetDate != nil {
		out.TargetDate = *st.plan.TargetDate
	}
	for _, m := range st.milestones {
		cm := ai.CurrentMilestone{ID: m.ID, Title: m.Title, OrderIndex: int(m.OrderIndex)}
		for _, t := range st.tasks {
			if t.MilestoneID == nil || *t.MilestoneID != m.ID {
				continue
			}
			ct := ai.CurrentTask{ID: t.ID, Title: t.Title, Notes: t.Notes, Status: t.Status}
			if t.EstimatedMinutes != nil {
				ct.EstimatedMinutes = int(*t.EstimatedMinutes)
			}
			if t.ScheduledDate != nil {
				ct.ScheduledDate = *t.ScheduledDate
			}
			cm.Tasks = append(cm.Tasks, ct)
		}
		out.Milestones = append(out.Milestones, cm)
	}
	return out
}

// inferMinutesPerDay estimates the plan's daily budget as its busiest
// scheduled day. Plans are packed up to the budget, so the fullest day is a
// good estimate; averages are skewed by finished tasks and partial days.
func (st planState) inferMinutesPerDay() int {
	perDay := map[string]int64{}
	for _, t := range st.tasks {
		if t.ScheduledDate != nil && t.EstimatedMinutes != nil {
			perDay[*t.ScheduledDate] += *t.EstimatedMinutes
		}
	}
	busiest := int64(0)
	for _, m := range perDay {
		busiest = max(busiest, m)
	}
	if busiest == 0 {
		return defaultMinutesPerDay
	}
	return max(15, min(600, int(busiest)))
}

// reconcile turns a revision from the model (or a client) into one that is
// safe to apply to st, and lists what it changes:
//   - IDs that don't belong to this plan, or appear twice, become new items;
//   - completed and skipped tasks can't be edited or removed: edits are
//     reverted, and dropped ones go back to their milestone (which is kept);
//   - titles are required, durations are clamped, milestones renumbered.
func (st planState) reconcile(rev ai.PlanRevision) (ai.PlanRevision, []Change, error) {
	out := ai.PlanRevision{Title: strings.TrimSpace(rev.Title), Description: strings.TrimSpace(rev.Description)}
	if out.Title == "" {
		out.Title = st.plan.Title
	}
	if out.Description == "" {
		out.Description = st.plan.Description
	}

	milestones := append([]ai.RevMilestone(nil), rev.Milestones...)
	sort.SliceStable(milestones, func(i, j int) bool { return milestones[i].OrderIndex < milestones[j].OrderIndex })

	seenM, seenT := map[string]bool{}, map[string]bool{}
	for _, m := range milestones {
		m.Title = strings.TrimSpace(m.Title)
		if m.Title == "" {
			continue
		}
		if _, ok := st.mByID[m.ID]; !ok || seenM[m.ID] {
			m.ID = ""
		} else {
			seenM[m.ID] = true
		}
		var tasks []ai.RevTask
		for _, t := range m.Tasks {
			t.Title, t.Notes = strings.TrimSpace(t.Title), strings.TrimSpace(t.Notes)
			if t.Title == "" {
				continue
			}
			if cur, ok := st.tByID[t.ID]; ok && !seenT[t.ID] {
				seenT[t.ID] = true
				if cur.Status != "pending" {
					t = lockedTask(cur)
				}
			} else {
				t.ID = ""
			}
			t.EstimatedMinutes = max(5, min(240, t.EstimatedMinutes))
			tasks = append(tasks, t)
		}
		m.Tasks = tasks
		out.Milestones = append(out.Milestones, m)
	}

	// Finished work the revision dropped goes back where it was.
	for _, t := range st.tasks {
		if seenT[t.ID] || t.Status == "pending" || t.MilestoneID == nil {
			continue
		}
		idx := -1
		for i, m := range out.Milestones {
			if m.ID == *t.MilestoneID {
				idx = i
			}
		}
		if idx < 0 {
			orig := st.mByID[*t.MilestoneID]
			out.Milestones = append(out.Milestones, ai.RevMilestone{ID: orig.ID, Title: orig.Title})
			seenM[orig.ID] = true
			idx = len(out.Milestones) - 1
		}
		out.Milestones[idx].Tasks = append(out.Milestones[idx].Tasks, lockedTask(t))
		seenT[t.ID] = true
	}
	if len(out.Milestones) == 0 {
		return ai.PlanRevision{}, nil, fmt.Errorf("%w: revision has no milestones", ai.ErrBadOutput)
	}
	for i := range out.Milestones {
		out.Milestones[i].OrderIndex = i + 1
		if out.Milestones[i].Tasks == nil {
			out.Milestones[i].Tasks = []ai.RevTask{}
		}
	}
	return out, st.diff(out, seenM, seenT), nil
}

func lockedTask(t sqlcgen.Task) ai.RevTask {
	rt := ai.RevTask{ID: t.ID, Title: t.Title, Notes: t.Notes}
	if t.EstimatedMinutes != nil {
		rt.EstimatedMinutes = int(*t.EstimatedMinutes)
	}
	return rt
}

func (st planState) diff(out ai.PlanRevision, keptM, keptT map[string]bool) []Change {
	var changes []Change
	if out.Title != st.plan.Title {
		changes = append(changes, Change{Kind: "plan", Action: "updated", Title: out.Title, Detail: "renamed from " + st.plan.Title})
	} else if out.Description != st.plan.Description {
		changes = append(changes, Change{Kind: "plan", Action: "updated", Title: out.Title, Detail: "new description"})
	}
	for _, m := range out.Milestones {
		cur, existing := st.mByID[m.ID]
		switch {
		case !existing:
			changes = append(changes, Change{Kind: "milestone", Action: "added", Title: m.Title})
		case cur.Title != m.Title:
			changes = append(changes, Change{Kind: "milestone", Action: "updated", Title: m.Title, Detail: "renamed from " + cur.Title})
		}
		for _, t := range m.Tasks {
			ct, existingTask := st.tByID[t.ID]
			switch {
			case !existingTask:
				changes = append(changes, Change{Kind: "task", Action: "added", Title: t.Title, Detail: "in " + m.Title})
			case ct.Status != "pending":
				// Locked; never reported as changed.
			case ct.MilestoneID == nil || *ct.MilestoneID != m.ID:
				changes = append(changes, Change{Kind: "task", Action: "moved", Title: t.Title, Detail: "to " + m.Title})
			case ct.Title != t.Title:
				changes = append(changes, Change{Kind: "task", Action: "updated", Title: t.Title, Detail: "renamed from " + ct.Title})
			case ct.Notes != t.Notes || ct.EstimatedMinutes == nil || int(*ct.EstimatedMinutes) != t.EstimatedMinutes:
				changes = append(changes, Change{Kind: "task", Action: "updated", Title: t.Title})
			}
		}
	}
	for _, m := range st.milestones {
		if keptM[m.ID] {
			continue
		}
		n := 0
		for _, t := range st.tasks {
			if t.MilestoneID != nil && *t.MilestoneID == m.ID && !keptT[t.ID] {
				n++
			}
		}
		detail := ""
		if n > 0 {
			detail = fmt.Sprintf("with %d task%s", n, map[bool]string{true: "", false: "s"}[n == 1])
		}
		changes = append(changes, Change{Kind: "milestone", Action: "removed", Title: m.Title, Detail: detail})
	}
	for _, t := range st.tasks {
		if keptT[t.ID] {
			continue
		}
		if t.MilestoneID != nil && !keptM[*t.MilestoneID] {
			continue // reported with its milestone
		}
		changes = append(changes, Change{Kind: "task", Action: "removed", Title: t.Title})
	}
	return changes
}

// RevisePlan asks the model to apply a follow-up request to a plan and
// returns the reconciled result for preview. Nothing is stored.
func (s *Service) RevisePlan(ctx context.Context, userID string, in ReviseInput) (RevisionProposal, error) {
	if s.planner == nil {
		return RevisionProposal{}, ErrAIDisabled
	}
	instruction := strings.TrimSpace(in.Instruction)
	if instruction == "" {
		return RevisionProposal{}, invalid("instruction is required")
	}
	if len(instruction) > maxPromptLen {
		return RevisionProposal{}, invalid("instruction must be at most %d characters", maxPromptLen)
	}
	today := timeutil.FormatDate(s.now().UTC())
	if in.Today != nil {
		if _, err := timeutil.ParseDate(*in.Today); err != nil {
			return RevisionProposal{}, invalid("today: %v", err)
		}
		today = *in.Today
	}

	st, err := loadPlanState(ctx, s.store.Queries, userID, in.PlanID)
	if err != nil {
		return RevisionProposal{}, err
	}
	perDay := st.inferMinutesPerDay()
	if in.MinutesPerDay != nil {
		perDay = *in.MinutesPerDay
	}
	if perDay < 10 || perDay > 600 {
		return RevisionProposal{}, invalid("minutes_per_day must be between 10 and 600")
	}

	rev, err := s.planner.RevisePlan(ctx, ai.ReviseRequest{
		Instruction: instruction, Current: st.current(), Today: today, MinutesPerDay: perDay,
	})
	if err != nil {
		return RevisionProposal{}, err
	}
	clean, changes, err := st.reconcile(rev)
	if err != nil {
		return RevisionProposal{}, err
	}
	summary := strings.TrimSpace(rev.Summary)
	if summary == "" && len(changes) == 0 {
		summary = "No changes were needed."
	}
	if changes == nil {
		changes = []Change{}
	}
	return RevisionProposal{Revision: clean, Summary: summary, Changes: changes, MinutesPerDay: perDay}, nil
}

// ApplyRevision stores a revision (normally a proposal from RevisePlan) and
// re-spreads the plan's pending tasks over days from the start date.
func (s *Service) ApplyRevision(ctx context.Context, userID, planID string, in ApplyRevisionInput) (PlanDetail, error) {
	startStr := timeutil.FormatDate(s.now().UTC())
	if in.StartDate != nil {
		startStr = *in.StartDate
	}
	start, err := timeutil.ParseDate(startStr)
	if err != nil {
		return PlanDetail{}, invalid("start_date: %v", err)
	}

	err = s.store.InWriteTx(ctx, func(q *sqlcgen.Queries, rev int64) error {
		st, err := loadPlanState(ctx, q, userID, planID)
		if err != nil {
			return err
		}
		perDay := st.inferMinutesPerDay()
		if in.MinutesPerDay != nil {
			perDay = *in.MinutesPerDay
		}
		if perDay < 10 || perDay > 600 {
			return invalid("minutes_per_day must be between 10 and 600")
		}
		plan, _, err := st.reconcile(in.Revision)
		if err != nil {
			return invalid("%v", err)
		}
		now := s.nowString()

		if err := q.UpdatePlan(ctx, sqlcgen.UpdatePlanParams{
			ID: planID, UserID: userID, Title: plan.Title, Description: plan.Description,
			TargetDate: st.plan.TargetDate, Status: st.plan.Status, UpdatedAt: now, ServerRev: rev,
		}); err != nil {
			return err
		}

		// Milestones first, so new ones have IDs for their tasks.
		keptM := map[string]bool{}
		for i := range plan.Milestones {
			m := &plan.Milestones[i]
			if cur, ok := st.mByID[m.ID]; ok {
				keptM[m.ID] = true
				if err := q.UpdateMilestone(ctx, sqlcgen.UpdateMilestoneParams{
					ID: m.ID, UserID: userID, Title: m.Title, OrderIndex: int64(m.OrderIndex), Status: cur.Status,
					UpdatedAt: now, ServerRev: rev,
				}); err != nil {
					return err
				}
				continue
			}
			m.ID = uuid.Must(uuid.NewV7()).String()
			if err := q.InsertMilestone(ctx, sqlcgen.InsertMilestoneParams{
				ID: m.ID, PlanID: planID, UserID: userID, Title: m.Title, OrderIndex: int64(m.OrderIndex),
				Status: "active", CreatedAt: now, UpdatedAt: now, ServerRev: rev,
			}); err != nil {
				return err
			}
		}

		// Pending tasks, in plan order, get fresh dates.
		var minutes []int
		for _, m := range plan.Milestones {
			for _, t := range m.Tasks {
				if cur, ok := st.tByID[t.ID]; !ok || cur.Status == "pending" {
					minutes = append(minutes, t.EstimatedMinutes)
				}
			}
		}
		dates := ai.Schedule(start, perDay, minutes, ai.AllWeekdays)

		keptT := map[string]bool{}
		next := 0
		for _, m := range plan.Milestones {
			milestoneID := m.ID
			for _, t := range m.Tasks {
				est := int64(t.EstimatedMinutes)
				cur, existing := st.tByID[t.ID]
				if existing && cur.Status != "pending" {
					keptT[t.ID] = true
					if cur.MilestoneID == nil || *cur.MilestoneID != milestoneID {
						cur.MilestoneID = &milestoneID
						if err := q.UpdateTask(ctx, updateTaskParams(cur, now, rev)); err != nil {
							return err
						}
					}
					continue
				}
				date := timeutil.FormatDate(dates[next])
				next++
				if existing {
					keptT[t.ID] = true
					cur.MilestoneID, cur.Title, cur.Notes = &milestoneID, t.Title, t.Notes
					cur.EstimatedMinutes, cur.ScheduledDate = &est, &date
					if err := q.UpdateTask(ctx, updateTaskParams(cur, now, rev)); err != nil {
						return err
					}
					continue
				}
				if err := q.InsertTask(ctx, sqlcgen.InsertTaskParams{
					ID: uuid.Must(uuid.NewV7()).String(), UserID: userID, MilestoneID: &milestoneID,
					Title: t.Title, Notes: t.Notes, ScheduledDate: &date, EstimatedMinutes: &est,
					Status: "pending", CreatedAt: now, UpdatedAt: now, ServerRev: rev,
				}); err != nil {
					return err
				}
			}
		}

		// Remove what the revision left out: tasks first (they may have moved
		// out of a milestone that is going away), then milestones.
		for _, t := range st.tasks {
			if keptT[t.ID] {
				continue
			}
			if _, err := q.SoftDeleteTask(ctx, sqlcgen.SoftDeleteTaskParams{Now: &now, ServerRev: rev, ID: t.ID, UserID: userID}); err != nil {
				return err
			}
		}
		for _, m := range st.milestones {
			if keptM[m.ID] {
				continue
			}
			if _, err := q.SoftDeleteMilestone(ctx, sqlcgen.SoftDeleteMilestoneParams{Now: &now, ServerRev: rev, ID: m.ID, UserID: userID}); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		return PlanDetail{}, err
	}
	return s.GetPlan(ctx, userID, planID)
}

func updateTaskParams(t sqlcgen.Task, now string, rev int64) sqlcgen.UpdateTaskParams {
	return sqlcgen.UpdateTaskParams{
		ID: t.ID, UserID: t.UserID, MilestoneID: t.MilestoneID, Title: t.Title, Notes: t.Notes,
		ScheduledDate: t.ScheduledDate, StartTime: t.StartTime, EndTime: t.EndTime,
		EstimatedMinutes: t.EstimatedMinutes, ReminderMinutes: t.ReminderMinutes, Status: t.Status,
		CompletedAt: t.CompletedAt, UpdatedAt: now, ServerRev: rev,
	}
}
