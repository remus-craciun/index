package service

import (
	"context"
	"net/mail"
	"strings"

	"github.com/google/uuid"

	"github.com/remus-craciun/index/server/internal/auth"
	"github.com/remus-craciun/index/server/internal/db"
	"github.com/remus-craciun/index/server/internal/db/sqlcgen"
)

const minPasswordLen = 8

// HasUser reports whether the single account has been registered.
func (s *Service) HasUser(ctx context.Context) (bool, error) {
	n, err := s.store.CountUsers(ctx)
	return n > 0, err
}

// Register creates the one and only account. It fails with
// ErrRegistrationDisabled once any user exists.
func (s *Service) Register(ctx context.Context, email, password string) (auth.Tokens, error) {
	email = strings.TrimSpace(email)
	if _, err := mail.ParseAddress(email); err != nil {
		return auth.Tokens{}, invalid("invalid email")
	}
	if len(password) < minPasswordLen {
		return auth.Tokens{}, invalid("password must be at least %d characters", minPasswordLen)
	}
	hash, err := auth.HashPassword(password)
	if err != nil {
		return auth.Tokens{}, err
	}

	id := uuid.Must(uuid.NewV7()).String()
	err = s.store.InTx(ctx, func(q *sqlcgen.Queries) error {
		n, err := q.CountUsers(ctx)
		if err != nil {
			return err
		}
		if n > 0 {
			return ErrRegistrationDisabled
		}
		return q.CreateUser(ctx, sqlcgen.CreateUserParams{
			ID: id, Email: email, HashedPassword: hash, CreatedAt: s.nowString(),
		})
	})
	if err != nil {
		return auth.Tokens{}, err
	}
	return s.tokens.Issue(id)
}

// Login verifies credentials and issues tokens.
func (s *Service) Login(ctx context.Context, email, password string) (auth.Tokens, error) {
	u, err := s.store.GetUserByEmail(ctx, strings.TrimSpace(email))
	if err != nil && !db.IsNotFound(err) {
		return auth.Tokens{}, err
	}
	if !auth.CheckPassword(u.HashedPassword, password) {
		return auth.Tokens{}, ErrInvalidCredentials
	}
	return s.tokens.Issue(u.ID)
}

// Refresh exchanges a valid refresh token for a new token pair.
func (s *Service) Refresh(ctx context.Context, refreshToken string) (auth.Tokens, error) {
	userID, err := s.tokens.VerifyRefresh(refreshToken)
	if err != nil {
		return auth.Tokens{}, ErrUnauthorized
	}
	if _, err := s.store.GetUserByID(ctx, userID); err != nil {
		if db.IsNotFound(err) {
			return auth.Tokens{}, ErrUnauthorized
		}
		return auth.Tokens{}, err
	}
	return s.tokens.Issue(userID)
}
