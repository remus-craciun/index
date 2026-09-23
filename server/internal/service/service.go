// Package service holds the business logic behind the HTTP API. Every
// method is scoped to the authenticated user ID it is given.
package service

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/remus-craciun/index/server/internal/ai"
	"github.com/remus-craciun/index/server/internal/auth"
	"github.com/remus-craciun/index/server/internal/db"
	"github.com/remus-craciun/index/server/internal/timeutil"
)

var (
	ErrNotFound             = errors.New("not found")
	ErrRegistrationDisabled = errors.New("registration is disabled")
	ErrInvalidCredentials   = errors.New("invalid email or password")
	ErrUnauthorized         = errors.New("unauthorized")
	ErrAIDisabled           = errors.New("ai is not configured")
)

// ValidationError describes bad client input.
type ValidationError struct{ Msg string }

func (e *ValidationError) Error() string { return e.Msg }

func invalid(format string, args ...any) error {
	return &ValidationError{Msg: fmt.Sprintf(format, args...)}
}

type Service struct {
	store   *db.Store
	tokens  *auth.Issuer
	planner ai.Planner // nil when GEMINI_API_KEY is unset
	now     func() time.Time
}

func New(store *db.Store, tokens *auth.Issuer, planner ai.Planner) *Service {
	return &Service{store: store, tokens: tokens, planner: planner, now: time.Now}
}

func (s *Service) nowString() string { return timeutil.Format(s.now()) }

// newID returns id if the client supplied a valid UUID, or a fresh UUIDv7.
func newID(id *string) (string, error) {
	if id == nil || *id == "" {
		return uuid.Must(uuid.NewV7()).String(), nil
	}
	return validID(*id)
}

func validID(id string) (string, error) {
	u, err := uuid.Parse(id)
	if err != nil {
		return "", invalid("invalid id %q: want UUID", id)
	}
	return u.String(), nil
}

func requireTitle(title string) (string, error) {
	t := strings.TrimSpace(title)
	if t == "" {
		return "", invalid("title is required")
	}
	return t, nil
}

var (
	planStatuses       = []string{"active", "completed", "archived"}
	taskStatuses       = []string{"pending", "completed", "skipped"}
	recurrenceStatuses = []string{"active", "paused"}
	clockRe            = regexp.MustCompile(`^([01]\d|2[0-3]):[0-5]\d$`)
)

// checkTimeWindow validates optional HH:MM start/end times. An end time
// needs a start time and must be later than it.
func checkTimeWindow(start, end *string) error {
	for _, t := range []*string{start, end} {
		if t != nil && !clockRe.MatchString(*t) {
			return invalid("invalid time %q: want HH:MM (24h)", *t)
		}
	}
	if end != nil && (start == nil || *end <= *start) {
		return invalid("end_time must be after start_time")
	}
	return nil
}

func checkReminder(m *int64) error {
	if m != nil && (*m < 0 || *m > 7*24*60) {
		return invalid("reminder_minutes must be between 0 and 10080")
	}
	return nil
}

// completedAtFor keeps completed_at consistent with a status change.
func completedAtFor(status string, current *string, now string) *string {
	if status == "pending" {
		return nil
	}
	if current != nil {
		return current
	}
	return &now
}

func checkStatus(status string, allowed []string) error {
	for _, a := range allowed {
		if status == a {
			return nil
		}
	}
	return invalid("invalid status %q: want one of %s", status, strings.Join(allowed, ", "))
}

func checkMinutes(m *int64) error {
	if m != nil && (*m < 0 || *m > 24*60) {
		return invalid("estimated_minutes must be between 0 and 1440")
	}
	return nil
}

func wrapNotFound(err error) error {
	if db.IsNotFound(err) {
		return ErrNotFound
	}
	return err
}

// Ping checks that the database is reachable.
func (s *Service) Ping(ctx context.Context) error {
	var one int
	return s.store.DB.QueryRowContext(ctx, "SELECT 1").Scan(&one)
}
