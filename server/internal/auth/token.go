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
	secret     []byte
	accessTTL  time.Duration
	refreshTTL time.Duration
	now        func() time.Time
}

func NewIssuer(secret []byte, accessTTL, refreshTTL time.Duration) *Issuer {
	return &Issuer{secret: secret, accessTTL: accessTTL, refreshTTL: refreshTTL, now: time.Now}
}

// Issue creates a fresh access/refresh pair for userID.
func (i *Issuer) Issue(userID string) (Tokens, error) {
	access, err := i.sign(userID, typeAccess, i.accessTTL)
	if err != nil {
		return Tokens{}, err
	}
	refresh, err := i.sign(userID, typeRefresh, i.refreshTTL)
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
func (i *Issuer) VerifyAccess(token string) (string, error) { return i.verify(token, typeAccess) }

// VerifyRefresh returns the user ID in a valid refresh token.
func (i *Issuer) VerifyRefresh(token string) (string, error) { return i.verify(token, typeRefresh) }

func (i *Issuer) sign(userID, typ string, ttl time.Duration) (string, error) {
	now := i.now()
	c := claims{
		Type: typ,
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    issuer,
			Subject:   userID,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(ttl)),
		},
	}
	return jwt.NewWithClaims(jwt.SigningMethodHS256, c).SignedString(i.secret)
}

func (i *Issuer) verify(token, typ string) (string, error) {
	var c claims
	_, err := jwt.ParseWithClaims(token, &c,
		func(*jwt.Token) (any, error) { return i.secret, nil },
		jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}),
		jwt.WithIssuer(issuer),
		jwt.WithExpirationRequired(),
		jwt.WithTimeFunc(i.now),
	)
	if err != nil || c.Type != typ || c.Subject == "" {
		return "", ErrInvalidToken
	}
	return c.Subject, nil
}
