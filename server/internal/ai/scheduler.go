package ai

import "time"

// Schedule assigns a calendar day to each task duration, in order, starting
// at start and packing up to minutesPerDay per day. A task longer than the
// budget gets a day to itself. Returned dates align with minutes.
func Schedule(start time.Time, minutesPerDay int, minutes []int) []time.Time {
	if minutesPerDay <= 0 {
		minutesPerDay = 60
	}
	out := make([]time.Time, len(minutes))
	day, used := start, 0
	for i, m := range minutes {
		if used > 0 && used+m > minutesPerDay {
			day, used = day.AddDate(0, 0, 1), 0
		}
		out[i] = day
		used += m
	}
	return out
}
