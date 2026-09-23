// Package timeutil defines the canonical text encodings for timestamps and
// dates stored in SQLite and exchanged over the API.
package timeutil

import (
	"fmt"
	"time"
)

// Layout is fixed-width UTC with millisecond precision, so lexical order of
// stored strings equals chronological order.
const Layout = "2006-01-02T15:04:05.000Z"

// DateLayout is the calendar date encoding.
const DateLayout = "2006-01-02"

// Format renders t in the canonical layout.
func Format(t time.Time) string { return t.UTC().Format(Layout) }

// Now returns the current time in the canonical layout.
func Now() string { return Format(time.Now()) }

// Normalize parses any RFC 3339 timestamp and re-renders it canonically.
func Normalize(s string) (string, error) {
	t, err := time.Parse(time.RFC3339Nano, s)
	if err != nil {
		return "", fmt.Errorf("invalid timestamp %q: want RFC 3339", s)
	}
	return Format(t), nil
}

// NormalizePtr is Normalize for optional values.
func NormalizePtr(s *string) (*string, error) {
	if s == nil {
		return nil, nil
	}
	n, err := Normalize(*s)
	if err != nil {
		return nil, err
	}
	return &n, nil
}

// ParseDate parses a YYYY-MM-DD date.
func ParseDate(s string) (time.Time, error) {
	t, err := time.Parse(DateLayout, s)
	if err != nil {
		return time.Time{}, fmt.Errorf("invalid date %q: want YYYY-MM-DD", s)
	}
	return t, nil
}

// ValidateDatePtr checks an optional date.
func ValidateDatePtr(s *string) error {
	if s == nil {
		return nil
	}
	_, err := ParseDate(*s)
	return err
}

// FormatDate renders the date part of t.
func FormatDate(t time.Time) string { return t.Format(DateLayout) }
