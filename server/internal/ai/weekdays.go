package ai

import (
	"strings"
	"time"
)

// Weekday bitmask shared with clients: Monday = 1, Tuesday = 2, … Sunday = 64.
const (
	AllWeekdays = 127
	Workdays    = 31
)

var weekdayNames = [...]string{"Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"}

// normalizeWeekdays returns mask, or every day when mask is empty or out of range.
func normalizeWeekdays(mask int) int {
	if mask < 1 || mask > AllWeekdays {
		return AllWeekdays
	}
	return mask
}

// weekdayBit is the bit for t's weekday in the Monday-based mask.
func weekdayBit(t time.Time) int {
	wd := int(t.Weekday()) // Sunday = 0 … Saturday = 6
	if wd == 0 {
		wd = 7
	}
	return 1 << (wd - 1)
}

func allows(mask int, t time.Time) bool {
	return mask&weekdayBit(t) != 0
}

// describeWeekdays names the days in mask, Monday first.
func describeWeekdays(mask int) string {
	mask = normalizeWeekdays(mask)
	if mask == AllWeekdays {
		return "every day"
	}
	var parts []string
	for i := range weekdayNames {
		if mask&(1<<i) != 0 {
			parts = append(parts, weekdayNames[i])
		}
	}
	return strings.Join(parts, ", ")
}

// ResolveWeekdays keeps current unless instruction changes which days the
// learner can work. A model-supplied list wins when the instruction does
// change them; otherwise a few direct phrases are parsed, and if neither
// yields a mask the current days stay.
func ResolveWeekdays(current int, instruction string, modelDays []string) int {
	current = normalizeWeekdays(current)
	if !mentionsAvailability(instruction) {
		return current
	}
	if mask, ok := weekdaysFromNames(modelDays); ok {
		return mask
	}
	if mask, ok := parseWeekdayChange(current, instruction); ok {
		return mask
	}
	return current
}

func mentionsAvailability(instruction string) bool {
	s := strings.ToLower(instruction)
	if strings.Contains(s, "weekend") || strings.Contains(s, "weekday") || strings.Contains(s, "every day") {
		return true
	}
	if mentionedDays(s) == 0 {
		return false
	}
	for _, cue := range []string{"only", "just", "add", "also", "include", "drop", "remove", "without", "except", "skip", "available", "instead", "switch"} {
		if containsWord(s, cue) {
			return true
		}
	}
	return strings.Contains(s, "work on") || strings.Contains(s, "n't") || strings.Contains(s, "no longer")
}

func weekdaysFromNames(names []string) (int, bool) {
	if len(names) == 0 {
		return 0, false
	}
	mask := 0
	for _, name := range names {
		bit, ok := dayBit[strings.ToLower(strings.TrimSpace(name))]
		if !ok {
			return 0, false
		}
		mask |= bit
	}
	if mask < 1 || mask > AllWeekdays {
		return 0, false
	}
	return mask, true
}

func parseWeekdayChange(current int, instruction string) (int, bool) {
	s := strings.ToLower(instruction)
	current = normalizeWeekdays(current)
	days := mentionedDays(s)
	switch {
	case strings.Contains(s, "every day"):
		return AllWeekdays, true
	case strings.Contains(s, "weekend") && days == 0:
		return 96, true
	case strings.Contains(s, "weekday") && days == 0:
		return Workdays, true
	case days == 0:
		return 0, false
	case containsWord(s, "only") || containsWord(s, "just"):
		return days, true
	case containsWord(s, "add") || containsWord(s, "also") || containsWord(s, "include"):
		return current | days, true
	case containsWord(s, "drop") || containsWord(s, "remove") || containsWord(s, "without") || containsWord(s, "except") || containsWord(s, "skip"):
		next := current &^ days
		if next == 0 {
			return 0, false
		}
		return next, true
	default:
		return days, true
	}
}

func mentionedDays(s string) int {
	mask := 0
	// Longer names first so "thursday" is not also counted via a shorter token.
	for _, name := range []string{
		"mondays", "tuesdays", "wednesdays", "thursdays", "fridays", "saturdays", "sundays",
		"monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
		"mon", "tue", "wed", "thu", "fri", "sat", "sun",
	} {
		if containsWord(s, name) {
			mask |= dayBit[name]
		}
	}
	return mask
}

func containsWord(s, word string) bool {
	for i := 0; i+len(word) <= len(s); {
		j := strings.Index(s[i:], word)
		if j < 0 {
			return false
		}
		j += i
		beforeOK := j == 0 || !isWordByte(s[j-1])
		after := j + len(word)
		afterOK := after == len(s) || !isWordByte(s[after])
		if beforeOK && afterOK {
			return true
		}
		i = j + 1
	}
	return false
}

func isWordByte(b byte) bool {
	return b >= 'a' && b <= 'z' || b >= '0' && b <= '9'
}

var dayBit = map[string]int{
	"monday": 1, "mondays": 1, "mon": 1,
	"tuesday": 2, "tuesdays": 2, "tue": 2,
	"wednesday": 4, "wednesdays": 4, "wed": 4,
	"thursday": 8, "thursdays": 8, "thu": 8,
	"friday": 16, "fridays": 16, "fri": 16,
	"saturday": 32, "saturdays": 32, "sat": 32,
	"sunday": 64, "sundays": 64, "sun": 64,
}

// countAvailableDays counts days from start through end (inclusive) that mask allows.
func countAvailableDays(start, end time.Time, mask int) int {
	mask = normalizeWeekdays(mask)
	n := 0
	for d := start; !d.After(end); d = d.AddDate(0, 0, 1) {
		if allows(mask, d) {
			n++
		}
	}
	return n
}
