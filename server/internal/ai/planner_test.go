package ai

import (
	"errors"
	"strings"
	"testing"
	"time"
)

func TestSchedulePacksDailyBudget(t *testing.T) {
	start := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	got := Schedule(start, 60, []int{30, 30, 30, 90, 10, 50, 5})
	want := []int{0, 0, 1, 2, 3, 3, 4} // day offsets
	for i, d := range got {
		if off := int(d.Sub(start).Hours() / 24); off != want[i] {
			t.Errorf("task %d: day offset %d, want %d", i, off, want[i])
		}
	}
}

func TestValidateNormalisesDraft(t *testing.T) {
	p := PlanDraft{
		Title: "  Go  ",
		Milestones: []MilestoneDraft{
			{Title: "second", OrderIndex: 7, Tasks: []TaskDraft{{Title: "b", EstimatedMinutes: 1000}}},
			{Title: "first", OrderIndex: 2, Tasks: []TaskDraft{{Title: "a", EstimatedMinutes: 0}}},
		},
	}
	if err := p.Validate(); err != nil {
		t.Fatal(err)
	}
	if p.Title != "Go" || p.Milestones[0].Title != "first" || p.Milestones[0].OrderIndex != 1 || p.Milestones[1].OrderIndex != 2 {
		t.Fatalf("unexpected normalisation: %+v", p)
	}
	if p.Milestones[0].Tasks[0].EstimatedMinutes != minTaskMinutes || p.Milestones[1].Tasks[0].EstimatedMinutes != maxTaskMinutes {
		t.Fatalf("minutes not clamped: %+v", p)
	}

	empty := PlanDraft{Title: "x", Milestones: []MilestoneDraft{{Title: "m"}}}
	if err := empty.Validate(); !errors.Is(err, ErrBadOutput) {
		t.Fatalf("want ErrBadOutput for milestone without tasks, got %v", err)
	}
}

func TestScheduleAroundSkipsBookedDays(t *testing.T) {
	start := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	booked := map[string]int{"2026-01-01": 30, "2026-01-02": 60}
	got := ScheduleAround(start, 60, []int{30, 30, 30}, booked)
	want := []int{0, 2, 2} // fills Jan 1 up to the budget, skips the full Jan 2
	for i, d := range got {
		if off := int(d.Sub(start).Hours() / 24); off != want[i] {
			t.Errorf("task %d: day offset %d, want %d", i, off, want[i])
		}
	}
}

func TestRevisePromptHasCalendar(t *testing.T) {
	p, err := revisePrompt(ReviseRequest{Instruction: "move X to Friday", Today: "2026-10-06", MinutesPerDay: 60})
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"Today: 2026-10-06 (Tuesday)", "Fri 2026-10-09", "Learner's request: move X to Friday"} {
		if !strings.Contains(p, want) {
			t.Errorf("prompt lacks %q:\n%s", want, p)
		}
	}
	if !strings.HasSuffix(strings.TrimSpace(p), "move X to Friday") {
		t.Errorf("request should come last:\n%s", p)
	}
}
