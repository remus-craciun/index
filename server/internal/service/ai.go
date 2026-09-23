package service

import (
	"context"
	"strings"

	"github.com/google/uuid"

	"github.com/remus-craciun/index/server/internal/ai"
	"github.com/remus-craciun/index/server/internal/db/sqlcgen"
	"github.com/remus-craciun/index/server/internal/timeutil"
)

const (
	maxPromptLen         = 2000
	defaultMinutesPerDay = 60
)

type DecomposeInput struct {
	Prompt        string  `json:"prompt"`
	StartDate     *string `json:"start_date"`
	TargetDate    *string `json:"target_date"`
	MinutesPerDay *int    `json:"minutes_per_day"`
}

// DecomposePlan asks the planner for a curriculum, schedules its tasks
// across days from the start date and persists the whole plan.
func (s *Service) DecomposePlan(ctx context.Context, userID string, in DecomposeInput) (PlanDetail, error) {
	if s.planner == nil {
		return PlanDetail{}, ErrAIDisabled
	}
	prompt := strings.TrimSpace(in.Prompt)
	if prompt == "" {
		return PlanDetail{}, invalid("prompt is required")
	}
	if len(prompt) > maxPromptLen {
		return PlanDetail{}, invalid("prompt must be at most %d characters", maxPromptLen)
	}
	startStr := timeutil.FormatDate(s.now().UTC())
	if in.StartDate != nil {
		startStr = *in.StartDate
	}
	start, err := timeutil.ParseDate(startStr)
	if err != nil {
		return PlanDetail{}, invalid("start_date: %v", err)
	}
	var target string
	if in.TargetDate != nil {
		t, err := timeutil.ParseDate(*in.TargetDate)
		if err != nil {
			return PlanDetail{}, invalid("target_date: %v", err)
		}
		if t.Before(start) {
			return PlanDetail{}, invalid("target_date must not be before start_date")
		}
		target = *in.TargetDate
	}
	perDay := defaultMinutesPerDay
	if in.MinutesPerDay != nil {
		perDay = *in.MinutesPerDay
	}
	if perDay < 10 || perDay > 600 {
		return PlanDetail{}, invalid("minutes_per_day must be between 10 and 600")
	}

	draft, err := s.planner.DecomposePlan(ctx, ai.DecomposeRequest{
		Prompt: prompt, StartDate: startStr, TargetDate: target, MinutesPerDay: perDay,
	})
	if err != nil {
		return PlanDetail{}, err
	}

	var minutes []int
	for _, m := range draft.Milestones {
		for _, t := range m.Tasks {
			minutes = append(minutes, t.EstimatedMinutes)
		}
	}
	dates := ai.Schedule(start, perDay, minutes)
	if target == "" && len(dates) > 0 {
		target = timeutil.FormatDate(dates[len(dates)-1])
	}

	planID := uuid.Must(uuid.NewV7()).String()
	err = s.store.InWriteTx(ctx, func(q *sqlcgen.Queries, rev int64) error {
		now := s.nowString()
		if err := q.InsertPlan(ctx, sqlcgen.InsertPlanParams{
			ID: planID, UserID: userID, Title: draft.Title, Description: draft.Description,
			TargetDate: &target, Status: "active", CreatedAt: now, UpdatedAt: now, ServerRev: rev,
		}); err != nil {
			return err
		}
		i := 0
		for _, m := range draft.Milestones {
			milestoneID := uuid.Must(uuid.NewV7()).String()
			if err := q.InsertMilestone(ctx, sqlcgen.InsertMilestoneParams{
				ID: milestoneID, PlanID: planID, UserID: userID, Title: m.Title, OrderIndex: int64(m.OrderIndex),
				Status: "active", CreatedAt: now, UpdatedAt: now, ServerRev: rev,
			}); err != nil {
				return err
			}
			for _, t := range m.Tasks {
				date := timeutil.FormatDate(dates[i])
				est := int64(t.EstimatedMinutes)
				i++
				if err := q.InsertTask(ctx, sqlcgen.InsertTaskParams{
					ID: uuid.Must(uuid.NewV7()).String(), UserID: userID, MilestoneID: &milestoneID,
					Title: t.Title, Notes: t.Notes, ScheduledDate: &date, EstimatedMinutes: &est,
					Status: "pending", CreatedAt: now, UpdatedAt: now, ServerRev: rev,
				}); err != nil {
					return err
				}
			}
		}
		return nil
	})
	if err != nil {
		return PlanDetail{}, err
	}
	return s.GetPlan(ctx, userID, planID)
}

type BreakdownInput struct {
	TaskID string `json:"task_id"`
}

// BreakdownTask replaces a task with AI-generated subtasks that inherit its
// milestone and scheduled date. The original task is soft-deleted.
func (s *Service) BreakdownTask(ctx context.Context, userID string, in BreakdownInput) ([]Task, error) {
	if s.planner == nil {
		return nil, ErrAIDisabled
	}
	task, err := s.store.GetTask(ctx, sqlcgen.GetTaskParams{ID: in.TaskID, UserID: userID})
	if err != nil {
		return nil, wrapNotFound(err)
	}
	req := ai.BreakdownRequest{TaskTitle: task.Title, TaskNotes: task.Notes}
	if task.EstimatedMinutes != nil {
		req.EstimatedMinutes = int(*task.EstimatedMinutes)
	}
	if task.MilestoneID != nil {
		if m, err := s.store.GetMilestone(ctx, sqlcgen.GetMilestoneParams{ID: *task.MilestoneID, UserID: userID}); err == nil {
			req.MilestoneTitle = m.Title
			if p, err := s.store.GetPlan(ctx, sqlcgen.GetPlanParams{ID: m.PlanID, UserID: userID}); err == nil {
				req.PlanTitle = p.Title
			}
		}
	}

	drafts, err := s.planner.BreakdownTask(ctx, req)
	if err != nil {
		return nil, err
	}

	out := make([]Task, 0, len(drafts))
	err = s.store.InWriteTx(ctx, func(q *sqlcgen.Queries, rev int64) error {
		now := s.nowString()
		// The model call is slow; make sure the task was not deleted meanwhile.
		n, err := q.SoftDeleteTask(ctx, sqlcgen.SoftDeleteTaskParams{Now: &now, ServerRev: rev, ID: task.ID, UserID: userID})
		if err != nil {
			return err
		}
		if n == 0 {
			return ErrNotFound
		}
		for _, d := range drafts {
			id := uuid.Must(uuid.NewV7()).String()
			est := int64(d.EstimatedMinutes)
			if err := q.InsertTask(ctx, sqlcgen.InsertTaskParams{
				ID: id, UserID: userID, MilestoneID: task.MilestoneID, Title: d.Title, Notes: d.Notes,
				ScheduledDate: task.ScheduledDate, EstimatedMinutes: &est, Status: "pending",
				CreatedAt: now, UpdatedAt: now, ServerRev: rev,
			}); err != nil {
				return err
			}
			t, err := q.GetTask(ctx, sqlcgen.GetTaskParams{ID: id, UserID: userID})
			if err != nil {
				return err
			}
			out = append(out, taskFromRow(t))
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return out, nil
}
