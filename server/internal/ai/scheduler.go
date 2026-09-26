package ai

import "time"

// Schedule assigns a calendar day to each task duration, in order, starting
// at start (or the next allowed weekday) and packing up to minutesPerDay per
// day. weekdays is a bitmask, Monday = 1 … Sunday = 64; 0 or values outside
// 1–127 mean every day. A task longer than the budget gets a day to itself.
// Returned dates align with minutes.
func Schedule(start time.Time, minutesPerDay int, minutes []int, weekdays int) []time.Time {
	if minutesPerDay <= 0 {
		minutesPerDay = 60
	}
	weekdays = normalizeWeekdays(weekdays)
	out := make([]time.Time, len(minutes))
	day, used := nextAllowed(start, weekdays), 0
	for i, m := range minutes {
		if used > 0 && used+m > minutesPerDay {
			day, used = nextAllowed(day.AddDate(0, 0, 1), weekdays), 0
		}
		out[i] = day
		used += m
	}
	return out
}

func nextAllowed(day time.Time, weekdays int) time.Time {
	for !allows(weekdays, day) {
		day = day.AddDate(0, 0, 1)
	}
	return day
}
