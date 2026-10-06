package service

import (
	"context"
	"fmt"
	"slices"
	"sort"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/remus-craciun/index/server/internal/ai"
	"github.com/remus-craciun/index/server/internal/db/sqlcgen"
	"github.com/remus-craciun/index/server/internal/timeutil"
)

// Change is one line of a revision preview.
type Change struct {
	Kind   string `json:"kind"`   // "plan", "milestone" or "task"
	Action string `json:"action"` // "added", "removed", "updated" or "moved"
	Title  string `json:"title"`
	Detail string `json:"detail,omitempty"`
}

// RevisionProposal is what a follow-up request would do to a plan. Nothing
// is stored until it is passed to ApplyRevision.
type RevisionProposal struct {
	Revision      ai.PlanRevision `json:"revision"`
	Summary       string          `json:"summary"`
	Changes       []Change        `json:"changes"`
	MinutesPerDay int             `json:"minutes_per_day"`
	Weekdays      int             `json:"weekdays"`
}

type ReviseInput struct {
	PlanID        string  `json:"plan_id"`
	Instruction   string  `json:"instruction"`
	Today         *string `json:"today"`
	MinutesPerDay *int    `json:"minutes_per_day"`
}

type ApplyRevisionInput struct {
	Revision      ai.PlanRevision `json:"revision"`
	StartDate     *string         `json:"start_date"`
	MinutesPerDay *int            `json:"minutes_per_day"`
}

// planState is a plan with its live milestones and tasks.
type planState struct {
	plan       sqlcgen.LearningPlan
	milestones []sqlcgen.Milestone
	tasks      []sqlcgen.Task
	mByID      map[string]sqlcgen.Milestone
	tByID      map[string]sqlcgen.Task
}

func loadPlanState(ctx context.Context, q *sqlcgen.Queries, userID, planID string) (planState, error) {
	p, err := q.GetPlan(ctx, sqlcgen.GetPlanParams{ID: planID, UserID: userID})
	if err != nil {
		return planState{}, wrapNotFound(err)
	}
	ms, err := q.ListMilestonesByPlan(ctx, sqlcgen.ListMilestonesByPlanParams{PlanID: planID, UserID: userID})
	if err != nil {
		return planState{}, err
	}
	ts, err := q.ListTasksByPlan(ctx, sqlcgen.ListTasksByPlanParams{PlanID: planID, UserID: userID})
	if err != nil {
		return planState{}, err
	}
	st := planState{plan: p, milestones: ms, tasks: ts, mByID: map[string]sqlcgen.Milestone{}, tByID: map[string]sqlcgen.Task{}}
	for _, m := range ms {
		st.mByID[m.ID] = m
	}
	for _, t := range ts {
		st.tByID[t.ID] = t
	}
	return st, nil
}

func (st planState) current() ai.CurrentPlan {
	out := ai.CurrentPlan{Title: st.plan.Title, Description: st.plan.Description}
	if st.plan.TargetDate != nil {
		out.TargetDate = *st.plan.TargetDate
	}
	for _, m := range st.milestones {
		cm := ai.CurrentMilestone{ID: m.ID, Title: m.Title, OrderIndex: int(m.OrderIndex)}
		for _, t := range st.tasks {
			if t.MilestoneID == nil || *t.MilestoneID != m.ID {
				continue
			}
			ct := ai.CurrentTask{ID: t.ID, Title: t.Title, Notes: t.Notes, Status: t.Status}
			if t.EstimatedMinutes != nil {
				ct.EstimatedMinutes = int(*t.EstimatedMinutes)
			}
			if t.ScheduledDate != nil {
				ct.ScheduledDate = *t.ScheduledDate
			}
			if t.StartTime != nil {
				ct.StartTime = *t.StartTime
			}
			if t.EndTime != nil {
				ct.EndTime = *t.EndTime
			}
			cm.Tasks = append(cm.Tasks, ct)
		}
		out.Milestones = append(out.Milestones, cm)
	}
	return out
}

// inferMinutesPerDay estimates the plan's daily budget as its busiest
// scheduled day. Plans are packed up to the budget, so the fullest day is a
// good estimate; averages are skewed by finished tasks and partial days. A
// day with a single task may hold one longer than the budget, so such days
// only count, by their median, when no day has more than one task.
func (st planState) inferMinutesPerDay() int {
	perDay, count := map[string]int64{}, map[string]int{}
	for _, t := range st.tasks {
		if t.ScheduledDate != nil && t.EstimatedMinutes != nil {
			perDay[*t.ScheduledDate] += *t.EstimatedMinutes
			count[*t.ScheduledDate]++
		}
	}
	busiest := int64(0)
	var singles []int64
	for d, m := range perDay {
		if count[d] > 1 {
			busiest = max(busiest, m)
		} else {
			singles = append(singles, m)
		}
	}
	if busiest == 0 && len(singles) > 0 {
		sort.Slice(singles, func(i, j int) bool { return singles[i] < singles[j] })
		busiest = singles[(len(singles)-1)/2]
	}
	if busiest == 0 {
		return defaultMinutesPerDay
	}
	return max(15, min(600, int(busiest)))
}

// Bounds for dates in a revision, counted from the start date. Dates outside
// them are ignored: a model may answer with a date from its training year.
const (
	maxPinDays        = 2 * 366
	maxRescheduleDays = 366
)

// reconcile turns a revision from the model (or a client) into one that is
// safe to apply to st from the given start date:
//   - IDs that don't belong to this plan, or appear twice, become new items;
//   - completed and skipped tasks can't be edited or removed: edits are
//     reverted, and dropped ones go back to their milestone (which is kept);
//   - titles are required, durations are clamped, milestones renumbered;
//   - schedule changes are normalised. Unreadable times and dates before the
//     start or too far ahead are dropped, so the task keeps its day or time.
func (st planState) reconcile(rev ai.PlanRevision, start time.Time) (ai.PlanRevision, error) {
	out := ai.PlanRevision{Title: strings.TrimSpace(rev.Title), Description: strings.TrimSpace(rev.Description)}
	if out.Title == "" {
		out.Title = st.plan.Title
	}
	if out.Description == "" {
		out.Description = st.plan.Description
	}
	if rev.Weekdays >= 1 && rev.Weekdays <= ai.AllWeekdays {
		out.Weekdays = rev.Weekdays
	}
	if rev.MinutesPerDay != nil {
		m := max(10, min(600, *rev.MinutesPerDay))
		out.MinutesPerDay = &m
	}
	if rev.RescheduleFrom != nil {
		// Re-spreading from a past day means from the start.
		if d, err := timeutil.ParseDate(strings.TrimSpace(*rev.RescheduleFrom)); err == nil && d.Before(start) {
			s := timeutil.FormatDate(start)
			out.RescheduleFrom = &s
		} else {
			out.RescheduleFrom = dateWithin(rev.RescheduleFrom, start, maxRescheduleDays)
		}
	}

	milestones := append([]ai.RevMilestone(nil), rev.Milestones...)
	sort.SliceStable(milestones, func(i, j int) bool { return milestones[i].OrderIndex < milestones[j].OrderIndex })

	seenM, seenT := map[string]bool{}, map[string]bool{}
	for _, m := range milestones {
		m.Title = strings.TrimSpace(m.Title)
		if m.Title == "" {
			continue
		}
		if _, ok := st.mByID[m.ID]; !ok || seenM[m.ID] {
			m.ID = ""
		} else {
			seenM[m.ID] = true
		}
		var tasks []ai.RevTask
		for _, t := range m.Tasks {
			t.Title, t.Notes = strings.TrimSpace(t.Title), strings.TrimSpace(t.Notes)
			if t.Title == "" {
				continue
			}
			if cur, ok := st.tByID[t.ID]; ok && !seenT[t.ID] {
				seenT[t.ID] = true
				if cur.Status != "pending" {
					t = lockedTask(cur)
				}
			} else {
				t.ID = ""
			}
			t.EstimatedMinutes = max(5, min(240, t.EstimatedMinutes))
			t.NewDate = dateWithin(t.NewDate, start, maxPinDays)
			t.NewStartTime = normalizeNewTime(t.NewStartTime)
			tasks = append(tasks, t)
		}
		m.Tasks = tasks
		out.Milestones = append(out.Milestones, m)
	}

	// Finished work the revision dropped goes back where it was.
	for _, t := range st.tasks {
		if seenT[t.ID] || t.Status == "pending" || t.MilestoneID == nil {
			continue
		}
		idx := -1
		for i, m := range out.Milestones {
			if m.ID == *t.MilestoneID {
				idx = i
			}
		}
		if idx < 0 {
			orig := st.mByID[*t.MilestoneID]
			out.Milestones = append(out.Milestones, ai.RevMilestone{ID: orig.ID, Title: orig.Title})
			seenM[orig.ID] = true
			idx = len(out.Milestones) - 1
		}
		out.Milestones[idx].Tasks = append(out.Milestones[idx].Tasks, lockedTask(t))
		seenT[t.ID] = true
	}
	if len(out.Milestones) == 0 {
		return ai.PlanRevision{}, fmt.Errorf("%w: revision has no milestones", ai.ErrBadOutput)
	}
	for i := range out.Milestones {
		out.Milestones[i].OrderIndex = i + 1
		if out.Milestones[i].Tasks == nil {
			out.Milestones[i].Tasks = []ai.RevTask{}
		}
	}
	return out, nil
}

func lockedTask(t sqlcgen.Task) ai.RevTask {
	rt := ai.RevTask{ID: t.ID, Title: t.Title, Notes: t.Notes}
	if t.EstimatedMinutes != nil {
		rt.EstimatedMinutes = int(*t.EstimatedMinutes)
	}
	return rt
}

// dateWithin returns s as a date if it is one, on or after start and at most
// days after it; otherwise nil.
func dateWithin(s *string, start time.Time, days int) *string {
	if s == nil {
		return nil
	}
	d, err := timeutil.ParseDate(strings.TrimSpace(*s))
	if err != nil || d.Before(start) || d.After(start.AddDate(0, 0, days)) {
		return nil
	}
	out := timeutil.FormatDate(d)
	return &out
}

// clearTime is the new_start_time value that removes a task's time.
const clearTime = "none"

// normalizeNewTime turns a model's time into HH:MM (24h) or [clearTime].
// Anything else, including "", is dropped: the task keeps its time.
func normalizeNewTime(s *string) *string {
	if s == nil {
		return nil
	}
	v := strings.ToUpper(strings.TrimSpace(*s))
	if v == "NONE" {
		c := clearTime
		return &c
	}
	for _, layout := range []string{"15:04", "15:04:05", "3:04PM", "3:04 PM", "3PM", "3 PM"} {
		if t, err := time.Parse(layout, v); err == nil {
			out := t.Format("15:04")
			return &out
		}
	}
	return nil
}

const minutesPerDayClock = 24 * 60

func clockMinutes(s string) int {
	t, _ := time.Parse("15:04", s)
	return t.Hour()*60 + t.Minute()
}

func clockString(m int) string { return fmt.Sprintf("%02d:%02d", m/60, m%60) }

// slot is where a task ends up: its day and optional time window.
type slot struct {
	date       *string
	start, end *string
}

// placement is what applying a revision does to the plan's schedule.
type placement struct {
	slots    [][]slot // per milestone and task of the revision
	repacked bool     // pending tasks were re-spread
	from     time.Time
	perDay   int
	weekdays int
}

// structural reports whether a revision adds, removes, resizes or reorders
// pending tasks, which re-spreads the plan just like it always has. Tasks the
// revision gives a new day are left out of the order check: they are placed
// by date, wherever the model listed them.
func (st planState) structural(rev ai.PlanRevision) bool {
	var before, after []string
	kept := 0
	for _, m := range rev.Milestones {
		for _, t := range m.Tasks {
			cur, ok := st.tByID[t.ID]
			if !ok {
				return true
			}
			if cur.Status != "pending" {
				continue
			}
			kept++
			if cur.MilestoneID == nil || *cur.MilestoneID != m.ID ||
				cur.EstimatedMinutes == nil || int(*cur.EstimatedMinutes) != t.EstimatedMinutes {
				return true
			}
			if t.NewDate == nil {
				after = append(after, t.ID)
			}
		}
	}
	pinned := map[string]bool{}
	for _, m := range rev.Milestones {
		for _, t := range m.Tasks {
			if t.NewDate != nil {
				pinned[t.ID] = true
			}
		}
	}
	pending := 0
	for _, t := range st.tasks {
		if t.Status != "pending" {
			continue
		}
		pending++
		if !pinned[t.ID] {
			before = append(before, t.ID)
		}
	}
	return kept != pending || !slices.Equal(before, after)
}

// place works out every task's day and time after a reconciled revision,
// starting at start with a daily budget of perDay minutes, on the plan's
// working days (the revision's, if it sets them). Preview and apply
// share it, so what the learner sees is what gets stored.
//
//   - A task with a new date goes on that day.
//   - Otherwise pending tasks keep their day, unless the revision changes the
//     timeline (reschedule_from, minutes_per_day, working days) or is structural: then they
//     are re-spread in plan order from the start (or reschedule_from), around
//     the tasks fixed to a day.
//   - A new start time gets an end time from the task's length (its current
//     window, or estimated_minutes), and tasks given a time on the same day
//     run one after another in plan order.
func (st planState) place(rev ai.PlanRevision, start time.Time, perDay int) placement {
	p := placement{from: start, perDay: perDay, weekdays: int(st.plan.Weekdays)}
	if rev.Weekdays != 0 {
		p.weekdays = rev.Weekdays
	}
	p.repacked = rev.RescheduleFrom != nil || rev.MinutesPerDay != nil ||
		p.weekdays != int(st.plan.Weekdays) || st.structural(rev)
	if rev.RescheduleFrom != nil {
		if d, err := timeutil.ParseDate(*rev.RescheduleFrom); err == nil && d.After(start) {
			p.from = d
		}
	}

	booked := map[string]int{}
	var auto []int
	p.slots = make([][]slot, len(rev.Milestones))
	for mi, m := range rev.Milestones {
		p.slots[mi] = make([]slot, len(m.Tasks))
		for ti, t := range m.Tasks {
			cur, existing := st.tByID[t.ID]
			s := &p.slots[mi][ti]
			if existing {
				s.date, s.start, s.end = cur.ScheduledDate, cur.StartTime, cur.EndTime
				if cur.Status != "pending" {
					continue
				}
			}
			switch {
			case t.NewDate != nil:
				s.date = t.NewDate
				booked[*t.NewDate] += t.EstimatedMinutes
			case p.repacked || !existing:
				auto = append(auto, t.EstimatedMinutes)
			}
		}
	}
	dates := ai.ScheduleAround(p.from, perDay, auto, p.weekdays, booked)

	type window struct{ start, end int }
	timed := map[string][]window{} // day -> windows given out by this revision
	next := 0
	for mi, m := range rev.Milestones {
		for ti, t := range m.Tasks {
			cur, existing := st.tByID[t.ID]
			if existing && cur.Status != "pending" {
				continue
			}
			s := &p.slots[mi][ti]
			if t.NewDate == nil && (p.repacked || !existing) {
				d := timeutil.FormatDate(dates[next])
				s.date = &d
				next++
			}

			resized := existing && (cur.EstimatedMinutes == nil || int(*cur.EstimatedMinutes) != t.EstimatedMinutes)
			length := t.EstimatedMinutes
			switch {
			case t.NewStartTime == nil:
				// Same time; a resized window follows the new length.
				if resized && s.start != nil && s.end != nil {
					s.end = endAfter(clockMinutes(*s.start), length)
				}
				continue
			case *t.NewStartTime == clearTime:
				s.start, s.end = nil, nil
				continue
			case !resized && s.start != nil && s.end != nil:
				length = clockMinutes(*s.end) - clockMinutes(*s.start)
			}

			at := clockMinutes(*t.NewStartTime)
			if s.date != nil {
				begin := at
				for moved := true; moved; {
					moved = false
					for _, w := range timed[*s.date] {
						if begin < w.end && w.start < begin+length {
							begin, moved = w.end, true
						}
					}
				}
				if begin+length <= minutesPerDayClock {
					at = begin
				}
				timed[*s.date] = append(timed[*s.date], window{at, at + length})
			}
			startStr := clockString(at)
			s.start, s.end = &startStr, endAfter(at, length)
		}
	}
	return p
}

// endAfter is the HH:MM end of a window, or nil if it would pass midnight.
func endAfter(start, length int) *string {
	if start+length >= minutesPerDayClock {
		return nil
	}
	e := clockString(start + length)
	return &e
}

func (st planState) diff(out ai.PlanRevision, p placement, keptM, keptT map[string]bool) []Change {
	var changes []Change
	if out.Title != st.plan.Title {
		changes = append(changes, Change{Kind: "plan", Action: "updated", Title: out.Title, Detail: "renamed from " + st.plan.Title})
	} else if out.Description != st.plan.Description {
		changes = append(changes, Change{Kind: "plan", Action: "updated", Title: out.Title, Detail: "new description"})
	}
	if c, ok := st.respreadChange(out, p); ok {
		changes = append(changes, c)
	}
	for mi, m := range out.Milestones {
		cur, existing := st.mByID[m.ID]
		switch {
		case !existing:
			changes = append(changes, Change{Kind: "milestone", Action: "added", Title: m.Title})
		case cur.Title != m.Title:
			changes = append(changes, Change{Kind: "milestone", Action: "updated", Title: m.Title, Detail: "renamed from " + cur.Title})
		}
		for ti, t := range m.Tasks {
			s := p.slots[mi][ti]
			ct, existingTask := st.tByID[t.ID]
			if !existingTask {
				parts := []string{"in " + m.Title}
				if t.NewDate != nil {
					parts = append(parts, "on "+formatDay(*s.date))
				}
				if s.start != nil {
					parts = append(parts, "at "+formatWindow(s.start, s.end))
				}
				changes = append(changes, Change{Kind: "task", Action: "added", Title: t.Title, Detail: strings.Join(parts, ", ")})
				continue
			}
			if ct.Status != "pending" {
				continue // locked; never reported as changed
			}
			var parts []string
			action := ""
			if ct.MilestoneID == nil || *ct.MilestoneID != m.ID {
				action = "moved"
				parts = append(parts, "to "+m.Title)
			}
			if ct.Title != t.Title {
				parts = append(parts, "renamed from "+ct.Title)
			}
			if ct.EstimatedMinutes == nil || int(*ct.EstimatedMinutes) != t.EstimatedMinutes {
				parts = append(parts, formatMinutes(t.EstimatedMinutes))
			}
			if action == "" && (len(parts) > 0 || ct.Notes != t.Notes) {
				action = "updated"
			}
			// Days changed by a re-spread are summed up in one plan line.
			if t.NewDate != nil && deref(s.date) != deref(ct.ScheduledDate) {
				parts = append(parts, "on "+formatDay(*s.date))
			}
			if deref(s.start) != deref(ct.StartTime) || deref(s.end) != deref(ct.EndTime) {
				if s.start == nil {
					parts = append(parts, "time removed")
				} else {
					parts = append(parts, "at "+formatWindow(s.start, s.end))
				}
			}
			if action == "" && len(parts) > 0 {
				action = "rescheduled"
			}
			if action != "" {
				changes = append(changes, Change{Kind: "task", Action: action, Title: t.Title, Detail: strings.Join(parts, ", ")})
			}
		}
	}
	for _, m := range st.milestones {
		if keptM[m.ID] {
			continue
		}
		n := 0
		for _, t := range st.tasks {
			if t.MilestoneID != nil && *t.MilestoneID == m.ID && !keptT[t.ID] {
				n++
			}
		}
		detail := ""
		if n > 0 {
			detail = fmt.Sprintf("with %d task%s", n, map[bool]string{true: "", false: "s"}[n == 1])
		}
		changes = append(changes, Change{Kind: "milestone", Action: "removed", Title: m.Title, Detail: detail})
	}
	for _, t := range st.tasks {
		if keptT[t.ID] {
			continue
		}
		if t.MilestoneID != nil && !keptM[*t.MilestoneID] {
			continue // reported with its milestone
		}
		changes = append(changes, Change{Kind: "task", Action: "removed", Title: t.Title})
	}
	return changes
}

// respreadChange sums up a re-spread in one line, if it moves any existing
// task to another day.
func (st planState) respreadChange(out ai.PlanRevision, p placement) (Change, bool) {
	if !p.repacked {
		return Change{}, false
	}
	moved, last := 0, ""
	for mi, m := range out.Milestones {
		for ti, t := range m.Tasks {
			cur, existing := st.tByID[t.ID]
			if existing && cur.Status != "pending" {
				continue
			}
			s := p.slots[mi][ti]
			last = max(last, deref(s.date))
			if existing && t.NewDate == nil && deref(s.date) != deref(cur.ScheduledDate) {
				moved++
			}
		}
	}
	if moved == 0 {
		return Change{}, false
	}
	detail := fmt.Sprintf("%d pending task%s re-spread from %s at up to %s a day",
		moved, map[bool]string{true: "", false: "s"}[moved == 1], formatDay(timeutil.FormatDate(p.from)), formatMinutes(p.perDay))
	if p.weekdays != ai.AllWeekdays {
		detail += " on " + ai.DescribeWeekdays(p.weekdays)
	}
	if last != "" {
		detail += ", ending " + formatDay(last)
		if target := deref(st.plan.TargetDate); target != "" && last > target {
			detail += ", after the target date " + formatDay(target)
		}
	}
	return Change{Kind: "plan", Action: "rescheduled", Title: out.Title, Detail: detail}, true
}

func formatDay(date string) string {
	d, err := timeutil.ParseDate(date)
	if err != nil {
		return date
	}
	return d.Format("Mon 2 Jan")
}

func formatWindow(start, end *string) string {
	if end == nil {
		return *start
	}
	return *start + "–" + *end
}

func formatMinutes(m int) string {
	switch {
	case m < 60:
		return fmt.Sprintf("%d min", m)
	case m%60 == 0:
		return fmt.Sprintf("%dh", m/60)
	default:
		return fmt.Sprintf("%dh %02dm", m/60, m%60)
	}
}

func deref(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

// kept lists the milestones and tasks of st that a reconciled revision keeps.
func kept(rev ai.PlanRevision) (keptM, keptT map[string]bool) {
	keptM, keptT = map[string]bool{}, map[string]bool{}
	for _, m := range rev.Milestones {
		if m.ID != "" {
			keptM[m.ID] = true
		}
		for _, t := range m.Tasks {
			if t.ID != "" {
				keptT[t.ID] = true
			}
		}
	}
	return keptM, keptT
}

// RevisePlan asks the model to apply a follow-up request to a plan and
// returns the reconciled result for preview. Nothing is stored.
func (s *Service) RevisePlan(ctx context.Context, userID string, in ReviseInput) (RevisionProposal, error) {
	if s.planner == nil {
		return RevisionProposal{}, ErrAIDisabled
	}
	instruction := strings.TrimSpace(in.Instruction)
	if instruction == "" {
		return RevisionProposal{}, invalid("instruction is required")
	}
	if len(instruction) > maxPromptLen {
		return RevisionProposal{}, invalid("instruction must be at most %d characters", maxPromptLen)
	}
	today := timeutil.FormatDate(s.now().UTC())
	if in.Today != nil {
		if _, err := timeutil.ParseDate(*in.Today); err != nil {
			return RevisionProposal{}, invalid("today: %v", err)
		}
		today = *in.Today
	}
	start, _ := timeutil.ParseDate(today)

	st, err := loadPlanState(ctx, s.store.Queries, userID, in.PlanID)
	if err != nil {
		return RevisionProposal{}, err
	}
	perDay := st.inferMinutesPerDay()
	if in.MinutesPerDay != nil {
		perDay = *in.MinutesPerDay
	}
	if perDay < 10 || perDay > 600 {
		return RevisionProposal{}, invalid("minutes_per_day must be between 10 and 600")
	}

	currentDays := int(st.plan.Weekdays)
	rev, err := s.planner.RevisePlan(ctx, ai.ReviseRequest{
		Instruction: instruction, Current: st.current(), Today: today, MinutesPerDay: perDay, Weekdays: currentDays,
	})
	if err != nil {
		return RevisionProposal{}, err
	}
	clean, err := st.reconcile(rev, start)
	if err != nil {
		return RevisionProposal{}, err
	}
	clean.Weekdays = ai.ResolveWeekdays(currentDays, instruction, rev.WorkingDays)
	if clean.MinutesPerDay != nil {
		perDay = *clean.MinutesPerDay
	}
	keptM, keptT := kept(clean)
	changes := st.diff(clean, st.place(clean, start, perDay), keptM, keptT)
	summary := strings.TrimSpace(rev.Summary)
	if summary == "" && len(changes) == 0 {
		summary = "No changes were needed."
	}
	if changes == nil {
		changes = []Change{}
	}
	return RevisionProposal{Revision: clean, Summary: summary, Changes: changes, MinutesPerDay: perDay, Weekdays: clean.Weekdays}, nil
}

// ApplyRevision stores a revision (normally a proposal from RevisePlan),
// placing tasks from the start date as described at [planState.place]. Rows
// that end up unchanged are not written, so they keep edits made elsewhere.
func (s *Service) ApplyRevision(ctx context.Context, userID, planID string, in ApplyRevisionInput) (PlanDetail, error) {
	startStr := timeutil.FormatDate(s.now().UTC())
	if in.StartDate != nil {
		startStr = *in.StartDate
	}
	start, err := timeutil.ParseDate(startStr)
	if err != nil {
		return PlanDetail{}, invalid("start_date: %v", err)
	}

	err = s.store.InWriteTx(ctx, func(q *sqlcgen.Queries, rev int64) error {
		st, err := loadPlanState(ctx, q, userID, planID)
		if err != nil {
			return err
		}
		plan, err := st.reconcile(in.Revision, start)
		if err != nil {
			return invalid("%v", err)
		}
		perDay := st.inferMinutesPerDay()
		switch {
		case plan.MinutesPerDay != nil:
			perDay = *plan.MinutesPerDay
		case in.MinutesPerDay != nil:
			perDay = *in.MinutesPerDay
		}
		if perDay < 10 || perDay > 600 {
			return invalid("minutes_per_day must be between 10 and 600")
		}
		placed := st.place(plan, start, perDay)
		now := s.nowString()

		if plan.Title != st.plan.Title || plan.Description != st.plan.Description || int64(placed.weekdays) != st.plan.Weekdays {
			if err := q.UpdatePlan(ctx, sqlcgen.UpdatePlanParams{
				ID: planID, UserID: userID, Title: plan.Title, Description: plan.Description,
				TargetDate: st.plan.TargetDate, Status: st.plan.Status, Weekdays: int64(placed.weekdays), UpdatedAt: now, ServerRev: rev,
			}); err != nil {
				return err
			}
		}

		// Milestones first, so new ones have IDs for their tasks.
		for i := range plan.Milestones {
			m := &plan.Milestones[i]
			if cur, ok := st.mByID[m.ID]; ok {
				if cur.Title == m.Title && int(cur.OrderIndex) == m.OrderIndex {
					continue
				}
				if err := q.UpdateMilestone(ctx, sqlcgen.UpdateMilestoneParams{
					ID: m.ID, UserID: userID, Title: m.Title, OrderIndex: int64(m.OrderIndex), Status: cur.Status,
					UpdatedAt: now, ServerRev: rev,
				}); err != nil {
					return err
				}
				continue
			}
			m.ID = uuid.Must(uuid.NewV7()).String()
			if err := q.InsertMilestone(ctx, sqlcgen.InsertMilestoneParams{
				ID: m.ID, PlanID: planID, UserID: userID, Title: m.Title, OrderIndex: int64(m.OrderIndex),
				Status: "active", CreatedAt: now, UpdatedAt: now, ServerRev: rev,
			}); err != nil {
				return err
			}
		}

		for mi, m := range plan.Milestones {
			milestoneID := m.ID
			for ti, t := range m.Tasks {
				sl := placed.slots[mi][ti]
				est := int64(t.EstimatedMinutes)
				cur, existing := st.tByID[t.ID]
				if !existing {
					if err := q.InsertTask(ctx, sqlcgen.InsertTaskParams{
						ID: uuid.Must(uuid.NewV7()).String(), UserID: userID, MilestoneID: &milestoneID,
						Title: t.Title, Notes: t.Notes, ScheduledDate: sl.date, StartTime: sl.start, EndTime: sl.end,
						EstimatedMinutes: &est, Status: "pending", CreatedAt: now, UpdatedAt: now, ServerRev: rev,
					}); err != nil {
						return err
					}
					continue
				}
				next := cur
				next.MilestoneID = &milestoneID
				if cur.Status == "pending" {
					next.Title, next.Notes, next.EstimatedMinutes = t.Title, t.Notes, &est
					next.ScheduledDate, next.StartTime, next.EndTime = sl.date, sl.start, sl.end
				}
				if sameTask(cur, next) {
					continue
				}
				if err := q.UpdateTask(ctx, updateTaskParams(next, now, rev)); err != nil {
					return err
				}
			}
		}

		// Remove what the revision left out: tasks first (they may have moved
		// out of a milestone that is going away), then milestones.
		keptM, keptT := kept(plan)
		for _, t := range st.tasks {
			if keptT[t.ID] {
				continue
			}
			if _, err := q.SoftDeleteTask(ctx, sqlcgen.SoftDeleteTaskParams{Now: &now, ServerRev: rev, ID: t.ID, UserID: userID}); err != nil {
				return err
			}
		}
		for _, m := range st.milestones {
			if keptM[m.ID] {
				continue
			}
			if _, err := q.SoftDeleteMilestone(ctx, sqlcgen.SoftDeleteMilestoneParams{Now: &now, ServerRev: rev, ID: m.ID, UserID: userID}); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		return PlanDetail{}, err
	}
	return s.GetPlan(ctx, userID, planID)
}

// sameTask reports whether a revision leaves the fields it can edit as they are.
func sameTask(a, b sqlcgen.Task) bool {
	eq := func(x, y *string) bool { return deref(x) == deref(y) && (x == nil) == (y == nil) }
	return eq(a.MilestoneID, b.MilestoneID) && a.Title == b.Title && a.Notes == b.Notes &&
		(a.EstimatedMinutes == nil) == (b.EstimatedMinutes == nil) &&
		(a.EstimatedMinutes == nil || *a.EstimatedMinutes == *b.EstimatedMinutes) &&
		eq(a.ScheduledDate, b.ScheduledDate) && eq(a.StartTime, b.StartTime) && eq(a.EndTime, b.EndTime)
}

func updateTaskParams(t sqlcgen.Task, now string, rev int64) sqlcgen.UpdateTaskParams {
	return sqlcgen.UpdateTaskParams{
		ID: t.ID, UserID: t.UserID, MilestoneID: t.MilestoneID, Title: t.Title, Notes: t.Notes,
		ScheduledDate: t.ScheduledDate, StartTime: t.StartTime, EndTime: t.EndTime,
		EstimatedMinutes: t.EstimatedMinutes, ReminderMinutes: t.ReminderMinutes, Status: t.Status,
		CompletedAt: t.CompletedAt, UpdatedAt: now, ServerRev: rev,
	}
}
