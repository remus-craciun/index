package ai

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"google.golang.org/genai"
)

// RevTask is a task in a revised plan. ID is set for an existing task that
// is kept (possibly edited or moved) and empty for a new one.
type RevTask struct {
	ID               string `json:"id,omitempty"`
	Title            string `json:"title"`
	EstimatedMinutes int    `json:"estimated_minutes"`
	Notes            string `json:"notes"`
}

// RevMilestone is a milestone in a revised plan; ID as for [RevTask].
type RevMilestone struct {
	ID         string    `json:"id,omitempty"`
	Title      string    `json:"title"`
	OrderIndex int       `json:"order_index"`
	Tasks      []RevTask `json:"tasks"`
}

// PlanRevision is the whole plan as it should look after a follow-up
// request. Anything existing that it leaves out is to be removed.
type PlanRevision struct {
	Title       string         `json:"title"`
	Description string         `json:"description"`
	Summary     string         `json:"summary,omitempty"`
	Milestones  []RevMilestone `json:"milestones"`
}

// CurrentTask / CurrentMilestone / CurrentPlan describe the plan as it is,
// as input for [Planner.RevisePlan].
type CurrentTask struct {
	ID               string `json:"id"`
	Title            string `json:"title"`
	EstimatedMinutes int    `json:"estimated_minutes"`
	Notes            string `json:"notes"`
	Status           string `json:"status"`
	ScheduledDate    string `json:"scheduled_date,omitempty"`
}

type CurrentMilestone struct {
	ID         string        `json:"id"`
	Title      string        `json:"title"`
	OrderIndex int           `json:"order_index"`
	Tasks      []CurrentTask `json:"tasks"`
}

type CurrentPlan struct {
	Title       string             `json:"title"`
	Description string             `json:"description"`
	TargetDate  string             `json:"target_date,omitempty"`
	Milestones  []CurrentMilestone `json:"milestones"`
}

type ReviseRequest struct {
	Instruction   string
	Current       CurrentPlan
	Today         string // YYYY-MM-DD
	MinutesPerDay int
}

const reviseInstruction = `You are an expert curriculum designer editing an existing learning plan
according to the learner's request.

Rules:
- Return the complete plan as it should look after the change, in the same structure.
- Keep the "id" of every milestone and task you keep, including ones you edit or move to another
  milestone. Omit "id" for new milestones and tasks. Anything you leave out is deleted.
- Tasks with status "completed" or "skipped" are history: include them unchanged, with their id,
  in their milestone.
- Change only what the request asks for (and what it directly implies). Do not rewrite unrelated
  parts of the plan.
- Keep tasks small and concrete (typically 15-90 minutes), in the order they should be done.
- "summary": one to three short sentences telling the learner what you changed.
- Write in the same language as the plan.`

var revisionTaskSchema = &genai.Schema{
	Type: genai.TypeObject,
	Properties: map[string]*genai.Schema{
		"id":                {Type: genai.TypeString, Description: "ID of an existing task; omit for a new task."},
		"title":             {Type: genai.TypeString},
		"estimated_minutes": {Type: genai.TypeInteger, Minimum: ptr(float64(minTaskMinutes)), Maximum: ptr(float64(maxTaskMinutes))},
		"notes":             {Type: genai.TypeString},
	},
	Required:         []string{"title", "estimated_minutes", "notes"},
	PropertyOrdering: []string{"id", "title", "estimated_minutes", "notes"},
}

var revisionSchema = &genai.Schema{
	Type: genai.TypeObject,
	Properties: map[string]*genai.Schema{
		"summary":     {Type: genai.TypeString, Description: "What changed, for the learner."},
		"title":       {Type: genai.TypeString},
		"description": {Type: genai.TypeString},
		"milestones": {
			Type:     genai.TypeArray,
			MinItems: ptr[int64](1),
			Items: &genai.Schema{
				Type: genai.TypeObject,
				Properties: map[string]*genai.Schema{
					"id":          {Type: genai.TypeString, Description: "ID of an existing milestone; omit for a new one."},
					"title":       {Type: genai.TypeString},
					"order_index": {Type: genai.TypeInteger, Minimum: ptr(1.0)},
					"tasks":       {Type: genai.TypeArray, Items: revisionTaskSchema},
				},
				Required:         []string{"title", "order_index", "tasks"},
				PropertyOrdering: []string{"id", "title", "order_index", "tasks"},
			},
		},
	},
	Required:         []string{"summary", "title", "description", "milestones"},
	PropertyOrdering: []string{"summary", "title", "description", "milestones"},
}

func (g *Gemini) RevisePlan(ctx context.Context, req ReviseRequest) (PlanRevision, error) {
	current, err := json.MarshalIndent(req.Current, "", "  ")
	if err != nil {
		return PlanRevision{}, err
	}
	var b strings.Builder
	fmt.Fprintf(&b, "Request: %s\n\n", req.Instruction)
	fmt.Fprintf(&b, "Today: %s\n", req.Today)
	fmt.Fprintf(&b, "Daily time budget: %d minutes\n\n", req.MinutesPerDay)
	fmt.Fprintf(&b, "Current plan:\n%s\n", current)

	var out PlanRevision
	if err := g.generate(ctx, reviseInstruction, b.String(), revisionSchema, &out); err != nil {
		return PlanRevision{}, err
	}
	if len(out.Milestones) == 0 {
		return PlanRevision{}, fmt.Errorf("%w: no milestones", ErrBadOutput)
	}
	return out, nil
}
