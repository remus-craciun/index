package service

import (
	"bytes"
	"encoding/json"

	"github.com/remus-craciun/index/server/internal/db/sqlcgen"
)

// Plan, Milestone and Task are the wire representations of the syncable
// entities. The same shapes are used by REST responses and /sync.

type Plan struct {
	ID          string  `json:"id"`
	Title       string  `json:"title"`
	Description string  `json:"description"`
	TargetDate  *string `json:"target_date"`
	Status      string  `json:"status"`
	CreatedAt   string  `json:"created_at"`
	UpdatedAt   string  `json:"updated_at"`
	DeletedAt   *string `json:"deleted_at"`
}

type Milestone struct {
	ID         string  `json:"id"`
	PlanID     string  `json:"plan_id"`
	Title      string  `json:"title"`
	OrderIndex int64   `json:"order_index"`
	Status     string  `json:"status"`
	CreatedAt  string  `json:"created_at"`
	UpdatedAt  string  `json:"updated_at"`
	DeletedAt  *string `json:"deleted_at"`
}

type Task struct {
	ID               string  `json:"id"`
	MilestoneID      *string `json:"milestone_id"`
	RecurrenceID     *string `json:"recurrence_id"`
	Title            string  `json:"title"`
	Notes            string  `json:"notes"`
	ScheduledDate    *string `json:"scheduled_date"`
	StartTime        *string `json:"start_time"`
	EndTime          *string `json:"end_time"`
	EstimatedMinutes *int64  `json:"estimated_minutes"`
	ReminderMinutes  *int64  `json:"reminder_minutes"`
	Status           string  `json:"status"`
	CompletedAt      *string `json:"completed_at"`
	CreatedAt        string  `json:"created_at"`
	UpdatedAt        string  `json:"updated_at"`
	DeletedAt        *string `json:"deleted_at"`
}

// Recurrence is a repeating-task rule. Clients generate the occurrences.
type Recurrence struct {
	ID               string  `json:"id"`
	Title            string  `json:"title"`
	Notes            string  `json:"notes"`
	Frequency        string  `json:"frequency"`       // "daily", "weekly" or "monthly"
	RepeatInterval   int64   `json:"repeat_interval"` // every N days/weeks/months
	Weekdays         int64   `json:"weekdays"`        // bitmask, Monday = 1 ... Sunday = 64
	MonthDay         *int64  `json:"month_day"`       // 1-31 for monthly; clamped to the month's last day
	StartTime        *string `json:"start_time"`
	EndTime          *string `json:"end_time"`
	EstimatedMinutes *int64  `json:"estimated_minutes"`
	ReminderMinutes  *int64  `json:"reminder_minutes"`
	StartDate        string  `json:"start_date"`
	EndDate          *string `json:"end_date"`
	Status           string  `json:"status"`
	CreatedAt        string  `json:"created_at"`
	UpdatedAt        string  `json:"updated_at"`
	DeletedAt        *string `json:"deleted_at"`
}

// PlanDetail is a plan with its milestones and their tasks.
type PlanDetail struct {
	Plan
	Milestones []MilestoneDetail `json:"milestones"`
}

type MilestoneDetail struct {
	Milestone
	Tasks []Task `json:"tasks"`
}

// Optional distinguishes an absent JSON field (Set=false) from an explicit
// null (Set=true, Value=nil) in PATCH bodies.
type Optional[T any] struct {
	Set   bool
	Value *T
}

func (o *Optional[T]) UnmarshalJSON(b []byte) error {
	o.Set = true
	if bytes.Equal(bytes.TrimSpace(b), []byte("null")) {
		o.Value = nil
		return nil
	}
	var v T
	if err := json.Unmarshal(b, &v); err != nil {
		return err
	}
	o.Value = &v
	return nil
}

func (o Optional[T]) apply(dst **T) {
	if o.Set {
		*dst = o.Value
	}
}

func planFromRow(r sqlcgen.LearningPlan) Plan {
	return Plan{
		ID: r.ID, Title: r.Title, Description: r.Description, TargetDate: r.TargetDate,
		Status: r.Status, CreatedAt: r.CreatedAt, UpdatedAt: r.UpdatedAt, DeletedAt: r.DeletedAt,
	}
}

func milestoneFromRow(r sqlcgen.Milestone) Milestone {
	return Milestone{
		ID: r.ID, PlanID: r.PlanID, Title: r.Title, OrderIndex: r.OrderIndex,
		Status: r.Status, CreatedAt: r.CreatedAt, UpdatedAt: r.UpdatedAt, DeletedAt: r.DeletedAt,
	}
}

func taskFromRow(r sqlcgen.Task) Task {
	return Task{
		ID: r.ID, MilestoneID: r.MilestoneID, RecurrenceID: r.RecurrenceID, Title: r.Title, Notes: r.Notes,
		ScheduledDate: r.ScheduledDate, StartTime: r.StartTime, EndTime: r.EndTime,
		EstimatedMinutes: r.EstimatedMinutes, ReminderMinutes: r.ReminderMinutes, Status: r.Status,
		CompletedAt: r.CompletedAt, CreatedAt: r.CreatedAt, UpdatedAt: r.UpdatedAt, DeletedAt: r.DeletedAt,
	}
}

func recurrenceFromRow(r sqlcgen.Recurrence) Recurrence {
	return Recurrence{
		ID: r.ID, Title: r.Title, Notes: r.Notes, Frequency: r.Frequency, RepeatInterval: r.RepeatInterval,
		Weekdays: r.Weekdays, MonthDay: r.MonthDay, StartTime: r.StartTime, EndTime: r.EndTime,
		EstimatedMinutes: r.EstimatedMinutes, ReminderMinutes: r.ReminderMinutes, StartDate: r.StartDate,
		EndDate: r.EndDate, Status: r.Status, CreatedAt: r.CreatedAt, UpdatedAt: r.UpdatedAt, DeletedAt: r.DeletedAt,
	}
}

func mapRows[R, T any](rows []R, f func(R) T) []T {
	out := make([]T, len(rows))
	for i, r := range rows {
		out[i] = f(r)
	}
	return out
}
