package ai

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"google.golang.org/genai"
)

const callTimeout = 60 * time.Second

const decomposeInstruction = `You are an expert curriculum designer. Turn the learner's goal into a
practical, progressive learning plan.

Rules:
- Split the plan into sequential milestones (phases), numbered from 1 via order_index.
- Each milestone contains small, concrete, bite-sized tasks a learner can finish in one sitting
  (typically 15-90 minutes). Prefer doing and building over passive reading.
- Tasks are listed in the order they should be done.
- Use notes for key points, suggested resources or what "done" looks like.
- Respect the time budget given: the sum of estimated_minutes should roughly fill, and not exceed,
  the available minutes.
- Keep titles short. Write in the same language as the goal.`

const breakdownInstruction = `You are a productivity coach. Break the given task into 2-8 smaller,
sequential, concrete subtasks that together complete it. Each subtask should be doable in one
sitting. Keep the total time close to the original estimate when one is given. Write in the same
language as the task.`

// Gemini is a Planner backed by the Gemini API with structured output.
type Gemini struct {
	client *genai.Client
	model  string
}

// NewGemini creates a Gemini planner for the given API key and model name.
func NewGemini(ctx context.Context, apiKey, model string) (*Gemini, error) {
	c, err := genai.NewClient(ctx, &genai.ClientConfig{APIKey: apiKey, Backend: genai.BackendGeminiAPI})
	if err != nil {
		return nil, err
	}
	return &Gemini{client: c, model: model}, nil
}

func (g *Gemini) DecomposePlan(ctx context.Context, req DecomposeRequest) (PlanDraft, error) {
	var b strings.Builder
	fmt.Fprintf(&b, "Goal: %s\n", req.Prompt)
	fmt.Fprintf(&b, "Start date: %s\n", req.StartDate)
	fmt.Fprintf(&b, "Daily time budget: %d minutes\n", req.MinutesPerDay)
	if req.TargetDate != "" {
		fmt.Fprintf(&b, "Target completion date: %s\n", req.TargetDate)
		if start, err := time.Parse(time.DateOnly, req.StartDate); err == nil {
			if end, err := time.Parse(time.DateOnly, req.TargetDate); err == nil {
				days := int(end.Sub(start).Hours()/24) + 1
				fmt.Fprintf(&b, "Available days: %d (about %d minutes in total)\n", days, days*req.MinutesPerDay)
			}
		}
	}

	var draft PlanDraft
	if err := g.generate(ctx, decomposeInstruction, b.String(), planSchema, &draft); err != nil {
		return PlanDraft{}, err
	}
	if err := draft.Validate(); err != nil {
		return PlanDraft{}, err
	}
	return draft, nil
}

func (g *Gemini) BreakdownTask(ctx context.Context, req BreakdownRequest) ([]TaskDraft, error) {
	var b strings.Builder
	fmt.Fprintf(&b, "Task: %s\n", req.TaskTitle)
	if req.TaskNotes != "" {
		fmt.Fprintf(&b, "Notes: %s\n", req.TaskNotes)
	}
	if req.EstimatedMinutes > 0 {
		fmt.Fprintf(&b, "Original estimate: %d minutes\n", req.EstimatedMinutes)
	}
	if req.PlanTitle != "" {
		fmt.Fprintf(&b, "Part of learning plan: %s\n", req.PlanTitle)
	}
	if req.MilestoneTitle != "" {
		fmt.Fprintf(&b, "Milestone: %s\n", req.MilestoneTitle)
	}

	var out struct {
		Subtasks []TaskDraft `json:"subtasks"`
	}
	if err := g.generate(ctx, breakdownInstruction, b.String(), breakdownSchema, &out); err != nil {
		return nil, err
	}
	return ValidateTasks(out.Subtasks)
}

func (g *Gemini) generate(ctx context.Context, instruction, prompt string, schema *genai.Schema, dst any) error {
	ctx, cancel := context.WithTimeout(ctx, callTimeout)
	defer cancel()

	resp, err := g.client.Models.GenerateContent(ctx, g.model, genai.Text(prompt), &genai.GenerateContentConfig{
		SystemInstruction: genai.NewContentFromText(instruction, genai.RoleUser),
		ResponseMIMEType:  "application/json",
		ResponseSchema:    schema,
	})
	if err != nil {
		return fmt.Errorf("%w: %v", ErrUnavailable, err)
	}
	text := resp.Text()
	if text == "" {
		return fmt.Errorf("%w: empty response", ErrBadOutput)
	}
	if err := json.Unmarshal([]byte(text), dst); err != nil {
		return fmt.Errorf("%w: %v", ErrBadOutput, err)
	}
	return nil
}
