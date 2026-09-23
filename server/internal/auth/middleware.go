package auth

import (
	"context"
	"net/http"
	"strings"
)

type ctxKey struct{}

// UserID returns the authenticated user ID placed in ctx by Middleware.
func UserID(ctx context.Context) string {
	id, _ := ctx.Value(ctxKey{}).(string)
	return id
}

// WithUserID returns a context carrying userID.
func WithUserID(ctx context.Context, userID string) context.Context {
	return context.WithValue(ctx, ctxKey{}, userID)
}

// Middleware rejects requests without a valid Bearer access token. onFail
// writes the error response.
func (i *Issuer) Middleware(onFail func(http.ResponseWriter, *http.Request)) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			h := r.Header.Get("Authorization")
			token, ok := strings.CutPrefix(h, "Bearer ")
			if !ok {
				onFail(w, r)
				return
			}
			userID, err := i.VerifyAccess(strings.TrimSpace(token))
			if err != nil {
				onFail(w, r)
				return
			}
			next.ServeHTTP(w, r.WithContext(WithUserID(r.Context(), userID)))
		})
	}
}
