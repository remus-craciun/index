package ai

import (
	"errors"
	"strings"
	"testing"
	"time"
)

func TestSchedulePacksDailyBudget(t *testing.T) {
	start := time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)
	got := Schedule(start, 60, []int{30, 30, 30, 90, 10, 50, 5}, AllWeekdays)
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

func TestScheduleSkipsUnavailableWeekdays(t *testing.T) {
	start := time.Date(2026, 1, 3, 0, 0, 0, 0, time.UTC) // Saturday
	got := Schedule(start, 60, []int{30, 30, 30}, Workdays)
	want := []string{"2026-01-05", "2026-01-05", "2026-01-06"}
	for i, d := range got {
		if got := d.Format(time.DateOnly); got != want[i] {
			t.Errorf("task %d: %s, want %s", i, got, want[i])
		}
	}
}

func TestDecomposePromptNamesWorkingDays(t *testing.T) {
	// Monday 2026-03-02 through Sunday 2026-03-08, Wednesdays only: one day.
	got := decomposePrompt(DecomposeRequest{
		Prompt: "Learn Go", StartDate: "2026-03-02", TargetDate: "2026-03-08",
		MinutesPerDay: 60, Weekdays: 4,
	})
	for _, want := range []string{
		"Days the learner can work: Wednesday",
		"Available days: 1 (about 60 minutes in total)",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("prompt missing %q:\n%s", want, got)
		}
	}
}
