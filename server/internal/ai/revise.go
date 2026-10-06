package ai

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"google.golang.org/genai"
)

// RevTask is a task in a revised plan. ID is set for an existing task that
// is kept (possibly edited or moved) and empty for a new one.
//
// NewDate and NewStartTime are changes, not state: nil leaves the task's day
// or time as it is (a new task gets a day from the scheduler and no time).
// NewStartTime "none" removes the time. End times are derived by the server.
type RevTask struct {
	ID               string  `json:"id,omitempty"`
	Title            string  `json:"title"`
	EstimatedMinutes int     `json:"estimated_minutes"`
	NewDate          *string `json:"new_date,omitempty"`
	NewStartTime     *string `json:"new_start_time,omitempty"`
	Notes            string  `json:"notes"`
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
//
// RescheduleFrom and MinutesPerDay are whole-plan timing changes: either one
// makes the server re-spread pending tasks that have no NewDate, from
// RescheduleFrom (or the start date) at MinutesPerDay (or the current pace).
type PlanRevision struct {
	Title          string         `json:"title"`
	Description    string         `json:"description"`
	MinutesPerDay  *int           `json:"minutes_per_day,omitempty"`
	RescheduleFrom *string        `json:"reschedule_from,omitempty"`
	Milestones     []RevMilestone `json:"milestones"`
	Summary        string         `json:"summary,omitempty"`
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
	StartTime        string `json:"start_time,omitempty"`
	EndTime          string `json:"end_time,omitempty"`
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
	Today         string // YYYY-MM-DD, the learner's local date
	MinutesPerDay int
}

// calendarDays is how far ahead the prompt lists dates with their weekdays,
// so the model looks up "Friday" or "next Monday" instead of computing it.
const calendarDays = 21

const reviseInstruction = `You edit an existing learning plan according to the learner's request.
Return the whole plan as it should look after the change; the app compares it with the current plan.

Plan structure
- Return every milestone and task you keep, in the order they should be done. Keep the "id" of
  every milestone and task you keep, including ones you edit or move to another milestone. Omit "id"
  for new milestones and tasks. Anything you leave out is deleted.
- Tasks with status "completed" or "skipped" are history: include them unchanged, with their id, in
  their milestone, with new_date and new_start_time null.
- Change only what the request asks for. Copy the title, notes and estimated_minutes of every other
  task exactly.
- New tasks are small and concrete, usually 15-90 minutes. When the learner asks for a specific
  duration, use it (5-240 minutes; for more than 240, use 240 and say so in the summary).
- Write titles, notes and the summary in the same language as the plan.

Scheduling
Current tasks show their day (scheduled_date) and, if set, their time of day (start_time, end_time;
24-hour local time). You don't copy these; you state only what changes:
- new_date: null keeps the task on its day. A date ("YYYY-MM-DD") moves the task to that day. Use it
  when the request is about particular tasks ("move X to Friday", "do Y tomorrow").
- new_start_time: null keeps the task's time of day. "HH:MM" sets it: "9am" = "09:00", "7pm" =
  "19:00", "half past six in the evening" = "18:30"; without a clock time, morning = "09:00",
  afternoon = "14:00", evening = "19:00". "none" removes the time. The app sets end times from
  estimated_minutes; for a range like "9 to 11", use "09:00" and 120 minutes.
- When several tasks on one day get the same start time, the app runs them one after another in plan
  order, so just give the requested time.
- Take dates from the calendar below the plan; don't calculate weekdays. A weekday name means its
  next occurrence after today. Never use a date before today.
- reschedule_from: null keeps every task without a new_date on its current day. Set it for requests
  about the whole timeline; the app then re-spreads all pending tasks that have no new_date, in plan
  order, day by day from that date: "push everything back a week" = the date 7 days after today,
  "skip today" or "not today" = tomorrow, "start next Monday" = that Monday, "catch me up" or
  "reschedule everything" = today.
- minutes_per_day: null keeps the daily time budget. A number changes it ("only 30 minutes a day",
  "make it lighter", "spread it over more weeks" = less than now); the app then re-spreads pending
  tasks.
- When you add, remove, reorder or resize pending tasks, the app re-spreads the tasks without a
  new_date by itself; don't set dates just to make room.
- Never write dates, weekdays or times of day into titles or notes: only these fields schedule
  anything. If a task's notes say when to do it, remove that text when you schedule the task.
- The target date is for information; you can't change it.

Summary
- Fill it in last: one to three short sentences telling the learner what you changed. Describe only
  changes that are in your output, naming days ("Fri 9 Oct") and times ("19:00"). Don't mention
  field names.
- If part of the request can't be done with these fields (for example repeating days off like "no
  tasks on weekends", reminders, the target date, or anything about the current time of day), change
  nothing for that part and say plainly that it wasn't done.`

var revisionTaskSchema = &genai.Schema{
	Type: genai.TypeObject,
	Properties: map[string]*genai.Schema{
		"id":                {Type: genai.TypeString, Description: "ID of an existing task; omit for a new task."},
		"title":             {Type: genai.TypeString},
		"estimated_minutes": {Type: genai.TypeInteger, Minimum: ptr(float64(minTaskMinutes)), Maximum: ptr(float64(maxTaskMinutes))},
		"new_date": {Type: genai.TypeString, Nullable: ptr(true),
			Description: "YYYY-MM-DD to move the task to that day; null keeps its day."},
		"new_start_time": {Type: genai.TypeString, Nullable: ptr(true),
			Description: "HH:MM (24-hour) to set the time of day, \"none\" to remove it; null keeps it."},
		"notes": {Type: genai.TypeString},
	},
	Required:         []string{"title", "estimated_minutes", "new_date", "new_start_time", "notes"},
	PropertyOrdering: []string{"id", "title", "estimated_minutes", "new_date", "new_start_time", "notes"},
}

var revisionSchema = &genai.Schema{
	Type: genai.TypeObject,
	Properties: map[string]*genai.Schema{
		"title":       {Type: genai.TypeString},
		"description": {Type: genai.TypeString},
		"minutes_per_day": {Type: genai.TypeInteger, Nullable: ptr(true), Minimum: ptr(10.0), Maximum: ptr(600.0),
			Description: "New daily time budget in minutes; null keeps it."},
		"reschedule_from": {Type: genai.TypeString, Nullable: ptr(true),
			Description: "YYYY-MM-DD to re-spread pending tasks from that day; null keeps their days."},
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
		"summary": {Type: genai.TypeString, Description: "What changed, for the learner. Written last."},
	},
	Required:         []string{"title", "description", "minutes_per_day", "reschedule_from", "milestones", "summary"},
	PropertyOrdering: []string{"title", "description", "minutes_per_day", "reschedule_from", "milestones", "summary"},
}

// revisePrompt lays out the request: the plan first, then the dates the
// model needs, then the learner's request last so it is read in full context.
func revisePrompt(req ReviseRequest) (string, error) {
	current, err := json.MarshalIndent(req.Current, "", "  ")
	if err != nil {
		return "", err
	}
	var b strings.Builder
	fmt.Fprintf(&b, "Current plan:\n%s\n\n", current)
	if today, err := time.Parse(time.DateOnly, req.Today); err == nil {
		fmt.Fprintf(&b, "Today: %s (%s)\n", req.Today, today.Weekday())
		b.WriteString("Calendar:")
		for i := range calendarDays {
			d := today.AddDate(0, 0, i)
			sep := ","
			if i == 0 {
				sep = ""
			}
			fmt.Fprintf(&b, "%s %s %s", sep, d.Format("Mon"), d.Format(time.DateOnly))
		}
		b.WriteString("\n")
	} else {
		fmt.Fprintf(&b, "Today: %s\n", req.Today)
	}
	fmt.Fprintf(&b, "Daily time budget: %d minutes\n\n", req.MinutesPerDay)
	fmt.Fprintf(&b, "Learner's request: %s\n", req.Instruction)
	return b.String(), nil
}

func (g *Gemini) RevisePlan(ctx context.Context, req ReviseRequest) (PlanRevision, error) {
	prompt, err := revisePrompt(req)
	if err != nil {
		return PlanRevision{}, err
	}
	var out PlanRevision
	if err := g.generate(ctx, reviseInstruction, prompt, revisionSchema, &out); err != nil {
		return PlanRevision{}, err
	}
	if len(out.Milestones) == 0 {
		return PlanRevision{}, fmt.Errorf("%w: no milestones", ErrBadOutput)
	}
	return out, nil
}
