// Package auth issues and verifies JWT bearer tokens and hashes passwords.
package auth

import (
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

const (
	issuer      = "index"
	typeAccess  = "access"
	typeRefresh = "refresh"
)

var ErrInvalidToken = errors.New("invalid token")

type claims struct {
	Type string `json:"typ"`
	// SessionID ties a refresh token to a server-side session, so logging out
	// can revoke it. Refresh tokens issued before sessions existed lack it.
	SessionID string `json:"sid,omitempty"`
	jwt.RegisteredClaims
}

// Tokens is the pair returned on login, registration and refresh.
type Tokens struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
	TokenType    string `json:"token_type"`
	ExpiresIn    int64  `json:"expires_in"`
}

// Issuer signs and verifies HS256 tokens.
type Issuer struct {
	secret    []byte
	accessTTL time.Duration
	// refreshTTL of 0 means refresh tokens never expire; they stay valid
	// until their session is revoked (logout).
	refreshTTL time.Duration
	now        func() time.Time
}

func NewIssuer(secret []byte, accessTTL, refreshTTL time.Duration) *Issuer {
	return &Issuer{secret: secret, accessTTL: accessTTL, refreshTTL: refreshTTL, now: time.Now}
}

// Issue creates a fresh access/refresh pair for userID in session sessionID.
func (i *Issuer) Issue(userID, sessionID string) (Tokens, error) {
	access, err := i.sign(claims{Type: typeAccess}, userID, i.accessTTL)
	if err != nil {
		return Tokens{}, err
	}
	refresh, err := i.sign(claims{Type: typeRefresh, SessionID: sessionID}, userID, i.refreshTTL)
	if err != nil {
		return Tokens{}, err
	}
	return Tokens{
		AccessToken:  access,
		RefreshToken: refresh,
		TokenType:    "Bearer",
		ExpiresIn:    int64(i.accessTTL.Seconds()),
	}, nil
}

// VerifyAccess returns the user ID in a valid access token.
func (i *Issuer) VerifyAccess(token string) (string, error) {
	c, err := i.verify(token, typeAccess, true)
	return c.Subject, err
}

// VerifyRefresh returns the user and session IDs in a valid refresh token.
// The session ID is empty for tokens issued before sessions existed. The
// caller must still check that the session hasn't been revoked.
func (i *Issuer) VerifyRefresh(token string) (userID, sessionID string, err error) {
	c, err := i.verify(token, typeRefresh, false)
	return c.Subject, c.SessionID, err
}

func (i *Issuer) sign(c claims, userID string, ttl time.Duration) (string, error) {
	now := i.now()
	c.RegisteredClaims = jwt.RegisteredClaims{
		Issuer:   issuer,
		Subject:  userID,
		IssuedAt: jwt.NewNumericDate(now),
	}
	if ttl > 0 {
		c.ExpiresAt = jwt.NewNumericDate(now.Add(ttl))
	}
	return jwt.NewWithClaims(jwt.SigningMethodHS256, c).SignedString(i.secret)
}

func (i *Issuer) verify(token, typ string, requireExpiry bool) (claims, error) {
	var c claims
	opts := []jwt.ParserOption{
		jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
		jwt.WithIssuer(issuer),
		jwt.WithTimeFunc(i.now),
	}
	if requireExpiry {
		opts = append(opts, jwt.WithExpirationRequired())
	}
	_, err := jwt.ParseWithClaims(token, &c, func(*jwt.Token) (any, error) { return i.secret, nil }, opts...)
	if err != nil || c.Type != typ || c.Subject == "" {
		return claims{}, ErrInvalidToken
	}
	return c, nil
}
