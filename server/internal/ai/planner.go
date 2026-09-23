// Package ai turns free-form goals into structured learning plans using an
// LLM constrained to a JSON schema.
package ai

import (
	"context"
	"errors"
	"fmt"
	"sort"
	"strings"
)

// ErrUnavailable wraps failures talking to the model provider.
var ErrUnavailable = errors.New("ai provider unavailable")

// ErrBadOutput means the model returned JSON that failed validation.
var ErrBadOutput = errors.New("ai returned an unusable plan")

const (
	minTaskMinutes = 5
	maxTaskMinutes = 240
)

type TaskDraft struct {
	Title            string `json:"title"`
	EstimatedMinutes int    `json:"estimated_minutes"`
	Notes            string `json:"notes"`
}

type MilestoneDraft struct {
	Title      string      `json:"title"`
	OrderIndex int         `json:"order_index"`
	Tasks      []TaskDraft `json:"tasks"`
}

type PlanDraft struct {
	Title       string           `json:"title"`
	Description string           `json:"description"`
	Milestones  []MilestoneDraft `json:"milestones"`
}

type DecomposeRequest struct {
	Prompt        string
	StartDate     string // YYYY-MM-DD
	TargetDate    string // YYYY-MM-DD, optional
	MinutesPerDay int
}

type BreakdownRequest struct {
	TaskTitle        string
	TaskNotes        string
	EstimatedMinutes int
	PlanTitle        string // optional context
	MilestoneTitle   string // optional context
}

// Planner produces plan and task drafts. Implementations must return drafts
// that have passed Validate / ValidateTasks.
type Planner interface {
	DecomposePlan(ctx context.Context, req DecomposeRequest) (PlanDraft, error)
	BreakdownTask(ctx context.Context, req BreakdownRequest) ([]TaskDraft, error)
	// RevisePlan applies a follow-up request to an existing plan. The result
	// is validated and reconciled with the current plan by the caller.
	RevisePlan(ctx context.Context, req ReviseRequest) (PlanRevision, error)
}

// Validate normalises a plan draft in place: trims text, orders milestones
// by order_index and renumbers them 1..n, and clamps task durations.
func (p *PlanDraft) Validate() error {
	p.Title = strings.TrimSpace(p.Title)
	p.Description = strings.TrimSpace(p.Description)
	if p.Title == "" {
		return fmt.Errorf("%w: missing title", ErrBadOutput)
	}
	if len(p.Milestones) == 0 {
		return fmt.Errorf("%w: no milestones", ErrBadOutput)
	}
	sort.SliceStable(p.Milestones, func(i, j int) bool {
		return p.Milestones[i].OrderIndex < p.Milestones[j].OrderIndex
	})
	for i := range p.Milestones {
		m := &p.Milestones[i]
		m.OrderIndex = i + 1
		m.Title = strings.TrimSpace(m.Title)
		if m.Title == "" {
			return fmt.Errorf("%w: milestone %d has no title", ErrBadOutput, i+1)
		}
		tasks, err := ValidateTasks(m.Tasks)
		if err != nil {
			return fmt.Errorf("milestone %q: %w", m.Title, err)
		}
		m.Tasks = tasks
	}
	return nil
}

// ValidateTasks trims and clamps task drafts, rejecting an empty list.
func ValidateTasks(tasks []TaskDraft) ([]TaskDraft, error) {
	if len(tasks) == 0 {
		return nil, fmt.Errorf("%w: no tasks", ErrBadOutput)
	}
	for i := range tasks {
		t := &tasks[i]
		t.Title = strings.TrimSpace(t.Title)
		t.Notes = strings.TrimSpace(t.Notes)
		if t.Title == "" {
			return nil, fmt.Errorf("%w: task %d has no title", ErrBadOutput, i+1)
		}
		t.EstimatedMinutes = max(minTaskMinutes, min(maxTaskMinutes, t.EstimatedMinutes))
	}
	return tasks, nil
}
