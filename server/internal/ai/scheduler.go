package ai

import "time"

// Schedule assigns a calendar day to each task duration, in order, starting
// at start and packing up to minutesPerDay per day. A task longer than the
// budget gets a day to itself. Returned dates align with minutes.
func Schedule(start time.Time, minutesPerDay int, minutes []int) []time.Time {
	return ScheduleAround(start, minutesPerDay, minutes, nil)
}

// ScheduleAround is [Schedule] on days that already hold booked minutes
// (tasks fixed to a day), keyed by YYYY-MM-DD. A full day is skipped.
func ScheduleAround(start time.Time, minutesPerDay int, minutes []int, booked map[string]int) []time.Time {
	if minutesPerDay <= 0 {
		minutesPerDay = 60
	}
	out := make([]time.Time, len(minutes))
	day := start
	used := booked[day.Format(time.DateOnly)]
	for i, m := range minutes {
		for used > 0 && used+m > minutesPerDay {
			day = day.AddDate(0, 0, 1)
			used = booked[day.Format(time.DateOnly)]
		}
		out[i] = day
		used += m
	}
	return out
}
