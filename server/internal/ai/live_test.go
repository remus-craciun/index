//go:build live

package ai

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"regexp"
	"testing"
)

// Live eval of the revise prompt against the real model. It costs API calls,
// so it only runs with the build tag:
//
//	set -a; source .env; set +a; go test -tags live -run TestLiveRevise -v ./internal/ai/

var scheduleText = regexp.MustCompile(`(?i)\b\d{1,2}(:\d{2})?\s?(am|pm)\b|\b\d{1,2}:\d{2}\b`)

func TestLiveRevise(t *testing.T) {
	g, err := NewGemini(context.Background(), os.Getenv("GEMINI_API_KEY"), os.Getenv("GEMINI_MODEL"))
	if err != nil {
		t.Fatal(err)
	}
	cur := CurrentPlan{
		Title: "Learn Go", Description: "Go basics to concurrency", TargetDate: "2026-10-12",
		Milestones: []CurrentMilestone{
			{ID: "m1", Title: "Foundations", OrderIndex: 1, Tasks: []CurrentTask{
				{ID: "t1", Title: "Syntax tour", EstimatedMinutes: 30, Status: "completed", ScheduledDate: "2026-10-05"},
				{ID: "t2", Title: "Maps and slices", EstimatedMinutes: 30, Status: "pending", ScheduledDate: "2026-10-06"},
				{ID: "t3", Title: "Structs and methods", EstimatedMinutes: 30, Status: "pending", ScheduledDate: "2026-10-06", StartTime: "18:00", EndTime: "18:30"},
			}},
			{ID: "m2", Title: "Concurrency", OrderIndex: 2, Tasks: []CurrentTask{
				{ID: "t4", Title: "Goroutines", EstimatedMinutes: 60, Status: "pending", ScheduledDate: "2026-10-07"},
				{ID: "t5", Title: "Channels", EstimatedMinutes: 60, Status: "pending", ScheduledDate: "2026-10-08"},
			}},
		},
	}
	s := func(p *string) string {
		if p == nil {
			return "null"
		}
		return *p
	}
	// want maps task id -> "new_date new_start_time" for tasks that must
	// change; every other task must have both null. plan is
	// "reschedule_from" ("" = don't check).
	cases := []struct {
		name, request string
		want          map[string]string
		reschedule    string
		est           map[string]int
	}{
		{"time", "Move the Goroutines task to 9am", map[string]string{"t4": "null 09:00"}, "null", nil},
		{"all evening", "I want to do all my tasks at 7pm", map[string]string{"t2": "null 19:00", "t3": "null 19:00", "t4": "null 19:00", "t5": "null 19:00"}, "null", nil},
		{"weekday", "Move Maps and slices to Friday", map[string]string{"t2": "2026-10-09 null"}, "null", nil},
		{"day and time", "Do Goroutines tomorrow evening", map[string]string{"t4": "2026-10-07 19:00"}, "null", nil},
		{"clear time", "Structs doesn't need a fixed time", map[string]string{"t3": "null none"}, "null", nil},
		{"push back", "Push everything back a week", map[string]string{}, "2026-10-13", nil},
		{"skip today", "I can't study today", map[string]string{}, "2026-10-07", nil},
		{"duration", "Make Channels take 2 hours", map[string]string{}, "null", map[string]int{"t5": 120}},
		{"romanian", "Mută Goroutines la ora 10 dimineața", map[string]string{"t4": "null 10:00"}, "null", nil},
		{"weekends off", "I can't study on weekends", nil, "", nil},
		{"unsupported", "Remind me 15 minutes before each task", map[string]string{}, "null", nil},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			rev, err := g.RevisePlan(context.Background(), ReviseRequest{Instruction: tc.request, Current: cur, Today: "2026-10-06", MinutesPerDay: 60, Weekdays: AllWeekdays})
			if err != nil {
				t.Fatal(err)
			}
			b, _ := json.Marshal(rev)
			t.Logf("%s\n%s", tc.request, b)
			days := ResolveWeekdays(AllWeekdays, tc.request, rev.WorkingDays)
			if want := map[bool]int{true: Workdays, false: AllWeekdays}[tc.name == "weekends off"]; days != want {
				t.Errorf("working days %v -> %d, want %d", rev.WorkingDays, days, want)
			}
			if tc.reschedule != "" && s(rev.RescheduleFrom) != tc.reschedule {
				t.Errorf("reschedule_from = %s, want %s", s(rev.RescheduleFrom), tc.reschedule)
			}
			for _, m := range rev.Milestones {
				for _, task := range m.Tasks {
					if scheduleText.MatchString(task.Title + " " + task.Notes) {
						t.Errorf("%s: schedule written into text: %q / %q", task.ID, task.Title, task.Notes)
					}
					if want, ok := tc.est[task.ID]; ok && task.EstimatedMinutes != want {
						t.Errorf("%s: estimated_minutes %d, want %d", task.ID, task.EstimatedMinutes, want)
					}
					if tc.want == nil {
						continue
					}
					got := fmt.Sprintf("%s %s", s(task.NewDate), s(task.NewStartTime))
					want := tc.want[task.ID]
					if want == "" {
						want = "null null"
					}
					if got != want {
						t.Errorf("%s: got %q, want %q", task.ID, got, want)
					}
				}
			}
			if rev.Summary == "" {
				t.Error("empty summary")
			}
		})
	}
}
