package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"

	"github.com/go-chi/chi/v5/middleware"

	"github.com/remus-craciun/index/server/internal/ai"
	"github.com/remus-craciun/index/server/internal/db"
	"github.com/remus-craciun/index/server/internal/service"
)

const defaultBodyLimit = 1 << 20 // 1 MiB

type errorBody struct {
	Error struct {
		Code    string `json:"code"`
		Message string `json:"message"`
	} `json:"error"`
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if v != nil {
		_ = json.NewEncoder(w).Encode(v)
	}
}

func writeError(w http.ResponseWriter, status int, code, msg string) {
	var b errorBody
	b.Error.Code, b.Error.Message = code, msg
	writeJSON(w, status, b)
}

// decodeJSON reads a size-limited JSON body into dst, rejecting unknown
// fields and trailing data.
func decodeJSON(w http.ResponseWriter, r *http.Request, limit int64, dst any) error {
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, limit))
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		var maxErr *http.MaxBytesError
		if errors.As(err, &maxErr) {
			return &service.ValidationError{Msg: fmt.Sprintf("request body exceeds %d bytes", limit)}
		}
		return &service.ValidationError{Msg: "invalid JSON body: " + err.Error()}
	}
	if dec.More() {
		return &service.ValidationError{Msg: "invalid JSON body: trailing data"}
	}
	return nil
}

func (a *api) fail(w http.ResponseWriter, r *http.Request, err error) {
	var ve *service.ValidationError
	switch {
	case errors.As(err, &ve):
		writeError(w, http.StatusBadRequest, "validation_error", ve.Msg)
	case errors.Is(err, service.ErrNotFound):
		writeError(w, http.StatusNotFound, "not_found", "resource not found")
	case errors.Is(err, service.ErrRegistrationDisabled):
		writeError(w, http.StatusForbidden, "registration_disabled", err.Error())
	case errors.Is(err, service.ErrInvalidCredentials):
		writeError(w, http.StatusUnauthorized, "invalid_credentials", err.Error())
	case errors.Is(err, service.ErrUnauthorized):
		writeError(w, http.StatusUnauthorized, "unauthorized", "missing or invalid token")
	case errors.Is(err, service.ErrAIDisabled):
		writeError(w, http.StatusServiceUnavailable, "ai_disabled", "AI features are not configured on this server")
	case errors.Is(err, ai.ErrUnavailable):
		a.log.Warn("ai call failed", "err", err, "request_id", middleware.GetReqID(r.Context()))
		writeError(w, http.StatusBadGateway, "ai_unavailable", "the AI provider could not be reached; try again")
	case errors.Is(err, ai.ErrBadOutput):
		a.log.Warn("ai output rejected", "err", err, "request_id", middleware.GetReqID(r.Context()))
		writeError(w, http.StatusBadGateway, "ai_bad_output", "the AI returned an unusable result; try again")
	case errors.Is(err, context.DeadlineExceeded):
		writeError(w, http.StatusGatewayTimeout, "timeout", "request timed out")
	case db.IsConstraint(err):
		writeError(w, http.StatusConflict, "conflict", "request conflicts with existing data")
	default:
		a.log.Error("request failed", "err", err, "method", r.Method, "path", r.URL.Path,
			"request_id", middleware.GetReqID(r.Context()))
		writeError(w, http.StatusInternalServerError, "internal", "internal server error")
	}
}

func (a *api) unauthorized(w http.ResponseWriter, r *http.Request) {
	a.fail(w, r, service.ErrUnauthorized)
}
