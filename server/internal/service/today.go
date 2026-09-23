package service

import (
	"context"

	"github.com/remus-craciun/index/server/internal/db/sqlcgen"
	"github.com/remus-craciun/index/server/internal/timeutil"
)

// TodayItem is a task in the merged daily schedule, with learning context.
type TodayItem struct {
	Task
	Overdue        bool    `json:"overdue"`
	MilestoneTitle *string `json:"milestone_title"`
	PlanID         *string `json:"plan_id"`
	PlanTitle      *string `json:"plan_title"`
}

type Today struct {
	Date  string      `json:"date"`
	Items []TodayItem `json:"items"`
}

// Today merges ad-hoc and learning tasks for day: pending tasks due on or
// before it (overdue first, then learning, then ad-hoc), followed by tasks
// already completed or skipped that day.
func (s *Service) Today(ctx context.Context, userID, day string) (Today, error) {
	if _, err := timeutil.ParseDate(day); err != nil {
		return Today{}, invalid("%v", err)
	}
	rows, err := s.store.ListToday(ctx, sqlcgen.ListTodayParams{UserID: userID, Day: &day})
	if err != nil {
		return Today{}, err
	}
	items := make([]TodayItem, len(rows))
	for i, r := range rows {
		items[i] = TodayItem{
			Task: Task{
				ID: r.ID, MilestoneID: r.MilestoneID, RecurrenceID: r.RecurrenceID, Title: r.Title, Notes: r.Notes,
				ScheduledDate: r.ScheduledDate, StartTime: r.StartTime, EndTime: r.EndTime,
				EstimatedMinutes: r.EstimatedMinutes, ReminderMinutes: r.ReminderMinutes, Status: r.Status,
				CompletedAt: r.CompletedAt, CreatedAt: r.CreatedAt, UpdatedAt: r.UpdatedAt, DeletedAt: r.DeletedAt,
			},
			Overdue:        r.Overdue,
			MilestoneTitle: r.MilestoneTitle,
			PlanID:         r.PlanID,
			PlanTitle:      r.PlanTitle,
		}
	}
	return Today{Date: day, Items: items}, nil
}
