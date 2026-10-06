package service

import (
	"context"
	"strings"

	"github.com/remus-craciun/index/server/internal/db/sqlcgen"
	"github.com/remus-craciun/index/server/internal/timeutil"
)

type PlanInput struct {
	ID          *string `json:"id"`
	Title       string  `json:"title"`
	Description string  `json:"description"`
	TargetDate  *string `json:"target_date"`
	Status      *string `json:"status"`
}

type PlanPatch struct {
	Title       *string          `json:"title"`
	Description *string          `json:"description"`
	TargetDate  Optional[string] `json:"target_date"`
	Status      *string          `json:"status"`
}

func (s *Service) ListPlans(ctx context.Context, userID string) ([]Plan, error) {
	rows, err := s.store.ListPlans(ctx, userID)
	if err != nil {
		return nil, err
	}
	return mapRows(rows, planFromRow), nil
}

// GetPlan returns a plan with its milestones and tasks.
func (s *Service) GetPlan(ctx context.Context, userID, id string) (PlanDetail, error) {
	var out PlanDetail
	err := s.store.InTx(ctx, func(q *sqlcgen.Queries) error {
		p, err := q.GetPlan(ctx, sqlcgen.GetPlanParams{ID: id, UserID: userID})
		if err != nil {
			return wrapNotFound(err)
		}
		ms, err := q.ListMilestonesByPlan(ctx, sqlcgen.ListMilestonesByPlanParams{PlanID: id, UserID: userID})
		if err != nil {
			return err
		}
		ts, err := q.ListTasksByPlan(ctx, sqlcgen.ListTasksByPlanParams{PlanID: id, UserID: userID})
		if err != nil {
			return err
		}
		out = buildPlanDetail(p, ms, ts)
		return nil
	})
	return out, err
}

func buildPlanDetail(p sqlcgen.LearningPlan, ms []sqlcgen.Milestone, ts []sqlcgen.Task) PlanDetail {
	byMilestone := map[string][]Task{}
	for _, t := range ts {
		if t.MilestoneID != nil {
			byMilestone[*t.MilestoneID] = append(byMilestone[*t.MilestoneID], taskFromRow(t))
		}
	}
	d := PlanDetail{Plan: planFromRow(p), Milestones: make([]MilestoneDetail, len(ms))}
	for i, m := range ms {
		tasks := byMilestone[m.ID]
		if tasks == nil {
			tasks = []Task{}
		}
		d.Milestones[i] = MilestoneDetail{Milestone: milestoneFromRow(m), Tasks: tasks}
	}
	return d
}

func (s *Service) CreatePlan(ctx context.Context, userID string, in PlanInput) (Plan, error) {
	id, err := newID(in.ID)
	if err != nil {
		return Plan{}, err
	}
	title, err := requireTitle(in.Title)
	if err != nil {
		return Plan{}, err
	}
	if err := timeutil.ValidateDatePtr(in.TargetDate); err != nil {
		return Plan{}, invalid("%v", err)
	}
	status := "active"
	if in.Status != nil {
		status = *in.Status
	}
	if err := checkStatus(status, planStatuses); err != nil {
		return Plan{}, err
	}

	var out Plan
	err = s.store.InWriteTx(ctx, func(q *sqlcgen.Queries, rev int64) error {
		now := s.nowString()
		if err := q.InsertPlan(ctx, sqlcgen.InsertPlanParams{
			ID: id, UserID: userID, Title: title, Description: strings.TrimSpace(in.Description),
			TargetDate: in.TargetDate, Status: status, Weekdays: 127, CreatedAt: now, UpdatedAt: now, ServerRev: rev,
		}); err != nil {
			return err
		}
		p, err := q.GetPlan(ctx, sqlcgen.GetPlanParams{ID: id, UserID: userID})
		out = planFromRow(p)
		return err
	})
	return out, err
}

func (s *Service) UpdatePlan(ctx context.Context, userID, id string, in PlanPatch) (Plan, error) {
	var out Plan
	err := s.store.InWriteTx(ctx, func(q *sqlcgen.Queries, rev int64) error {
		p, err := q.GetPlan(ctx, sqlcgen.GetPlanParams{ID: id, UserID: userID})
		if err != nil {
			return wrapNotFound(err)
		}
		if in.Title != nil {
			if p.Title, err = requireTitle(*in.Title); err != nil {
				return err
			}
		}
		if in.Description != nil {
			p.Description = strings.TrimSpace(*in.Description)
		}
		in.TargetDate.apply(&p.TargetDate)
		if err := timeutil.ValidateDatePtr(p.TargetDate); err != nil {
			return invalid("%v", err)
		}
		if in.Status != nil {
			p.Status = *in.Status
		}
		if err := checkStatus(p.Status, planStatuses); err != nil {
			return err
		}
		p.UpdatedAt = s.nowString()
		if err := q.UpdatePlan(ctx, sqlcgen.UpdatePlanParams{
			ID: id, UserID: userID, Title: p.Title, Description: p.Description, TargetDate: p.TargetDate,
			Status: p.Status, Weekdays: p.Weekdays, UpdatedAt: p.UpdatedAt, ServerRev: rev,
		}); err != nil {
			return err
		}
		out = planFromRow(p)
		return nil
	})
	return out, err
}

// DeletePlan soft-deletes a plan together with its milestones and tasks.
func (s *Service) DeletePlan(ctx context.Context, userID, id string) error {
	return s.store.InWriteTx(ctx, func(q *sqlcgen.Queries, rev int64) error {
		now := s.nowString()
		n, err := q.SoftDeletePlan(ctx, sqlcgen.SoftDeletePlanParams{Now: &now, ServerRev: rev, ID: id, UserID: userID})
		if err != nil {
			return err
		}
		if n == 0 {
			return ErrNotFound
		}
		if err := q.SoftDeleteTasksByPlan(ctx, sqlcgen.SoftDeleteTasksByPlanParams{Now: &now, ServerRev: rev, UserID: userID, PlanID: id}); err != nil {
			return err
		}
		return q.SoftDeleteMilestonesByPlan(ctx, sqlcgen.SoftDeleteMilestonesByPlanParams{Now: &now, ServerRev: rev, UserID: userID, PlanID: id})
	})
}

type MilestoneInput struct {
	ID         *string `json:"id"`
	Title      string  `json:"title"`
	OrderIndex *int64  `json:"order_index"`
	Status     *string `json:"status"`
}

type MilestonePatch struct {
	Title      *string `json:"title"`
	OrderIndex *int64  `json:"order_index"`
	Status     *string `json:"status"`
}

// CreateMilestone adds a milestone to a plan. Without order_index it is
// appended after the existing ones.
func (s *Service) CreateMilestone(ctx context.Context, userID, planID string, in MilestoneInput) (Milestone, error) {
	id, err := newID(in.ID)
	if err != nil {
		return Milestone{}, err
	}
	title, err := requireTitle(in.Title)
	if err != nil {
		return Milestone{}, err
	}
	status := "active"
	if in.Status != nil {
		status = *in.Status
	}
	if err := checkStatus(status, planStatuses); err != nil {
		return Milestone{}, err
	}

	var out Milestone
	err = s.store.InWriteTx(ctx, func(q *sqlcgen.Queries, rev int64) error {
		if _, err := q.GetPlan(ctx, sqlcgen.GetPlanParams{ID: planID, UserID: userID}); err != nil {
			return wrapNotFound(err)
		}
		order := int64(1)
		if in.OrderIndex != nil {
			order = *in.OrderIndex
		} else {
			existing, err := q.ListMilestonesByPlan(ctx, sqlcgen.ListMilestonesByPlanParams{PlanID: planID, UserID: userID})
			if err != nil {
				return err
			}
			for _, m := range existing {
				order = max(order, m.OrderIndex+1)
			}
		}
		now := s.nowString()
		if err := q.InsertMilestone(ctx, sqlcgen.InsertMilestoneParams{
			ID: id, PlanID: planID, UserID: userID, Title: title, OrderIndex: order, Status: status,
			CreatedAt: now, UpdatedAt: now, ServerRev: rev,
		}); err != nil {
			return err
		}
		m, err := q.GetMilestone(ctx, sqlcgen.GetMilestoneParams{ID: id, UserID: userID})
		out = milestoneFromRow(m)
		return err
	})
	return out, err
}

func (s *Service) UpdateMilestone(ctx context.Context, userID, id string, in MilestonePatch) (Milestone, error) {
	var out Milestone
	err := s.store.InWriteTx(ctx, func(q *sqlcgen.Queries, rev int64) error {
		m, err := q.GetMilestone(ctx, sqlcgen.GetMilestoneParams{ID: id, UserID: userID})
		if err != nil {
			return wrapNotFound(err)
		}
		if in.Title != nil {
			if m.Title, err = requireTitle(*in.Title); err != nil {
				return err
			}
		}
		if in.OrderIndex != nil {
			m.OrderIndex = *in.OrderIndex
		}
		if in.Status != nil {
			m.Status = *in.Status
		}
		if err := checkStatus(m.Status, planStatuses); err != nil {
			return err
		}
		m.UpdatedAt = s.nowString()
		if err := q.UpdateMilestone(ctx, sqlcgen.UpdateMilestoneParams{
			ID: id, UserID: userID, Title: m.Title, OrderIndex: m.OrderIndex, Status: m.Status,
			UpdatedAt: m.UpdatedAt, ServerRev: rev,
		}); err != nil {
			return err
		}
		out = milestoneFromRow(m)
		return nil
	})
	return out, err
}

// DeleteMilestone soft-deletes a milestone and its tasks.
func (s *Service) DeleteMilestone(ctx context.Context, userID, id string) error {
	return s.store.InWriteTx(ctx, func(q *sqlcgen.Queries, rev int64) error {
		now := s.nowString()
		n, err := q.SoftDeleteMilestone(ctx, sqlcgen.SoftDeleteMilestoneParams{Now: &now, ServerRev: rev, ID: id, UserID: userID})
		if err != nil {
			return err
		}
		if n == 0 {
			return ErrNotFound
		}
		return q.SoftDeleteTasksByMilestone(ctx, sqlcgen.SoftDeleteTasksByMilestoneParams{Now: &now, ServerRev: rev, MilestoneID: &id, UserID: userID})
	})
}
