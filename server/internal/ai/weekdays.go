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
