package auth

import (
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

var secret = []byte("0123456789abcdef0123456789abcdef")

func TestRefreshTokensNeverExpireByDefault(t *testing.T) {
	iss := NewIssuer(secret, 15*time.Minute, 0)
	toks, err := iss.Issue("user-1", "session-1")
	if err != nil {
		t.Fatal(err)
	}

	var c claims
	if _, _, err := jwt.NewParser().ParseUnverified(toks.RefreshToken, &c); err != nil {
		t.Fatal(err)
	}
	if c.ExpiresAt != nil {
		t.Fatalf("refresh token has an expiry: %v", c.ExpiresAt)
	}

	// Ten years later: access token is long dead, refresh token still valid.
	iss.now = func() time.Time { return time.Now().AddDate(10, 0, 0) }
	if _, err := iss.VerifyAccess(toks.AccessToken); err == nil {
		t.Fatal("access token should expire")
	}
	user, sid, err := iss.VerifyRefresh(toks.RefreshToken)
	if err != nil || user != "user-1" || sid != "session-1" {
		t.Fatalf("refresh after 10 years: user=%q sid=%q err=%v", user, sid, err)
	}
}

func TestTokenTypesAndOptionalExpiry(t *testing.T) {
	iss := NewIssuer(secret, time.Minute, time.Hour)
	toks, _ := iss.Issue("u", "s")
	if _, _, err := iss.VerifyRefresh(toks.AccessToken); err == nil {
		t.Fatal("access token accepted as refresh token")
	}
	if _, err := iss.VerifyAccess(toks.RefreshToken); err == nil {
		t.Fatal("refresh token accepted as access token")
	}
	iss.now = func() time.Time { return time.Now().Add(2 * time.Hour) }
	if _, _, err := iss.VerifyRefresh(toks.RefreshToken); err == nil {
		t.Fatal("REFRESH_TTL set: refresh token should expire")
	}
	other := NewIssuer([]byte("another-secret-another-secret-xx"), time.Minute, 0)
	if _, _, err := other.VerifyRefresh(toks.RefreshToken); err == nil {
		t.Fatal("token signed with a different secret accepted")
	}
}
