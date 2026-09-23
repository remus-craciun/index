package httpapi

import (
	"net/http"
	"time"

	"github.com/go-chi/chi/v5"

	"github.com/remus-craciun/index/server/internal/auth"
	"github.com/remus-craciun/index/server/internal/service"
	"github.com/remus-craciun/index/server/internal/timeutil"
)

func queryPtr(r *http.Request, key string) *string {
	if v := r.URL.Query().Get(key); v != "" {
		return &v
	}
	return nil
}

func (a *api) listTasks(w http.ResponseWriter, r *http.Request) {
	tasks, err := a.svc.ListTasks(r.Context(), auth.UserID(r.Context()), service.TaskFilter{
		ScheduledDate: queryPtr(r, "date"),
		Status:        queryPtr(r, "status"),
		MilestoneID:   queryPtr(r, "milestone_id"),
		AdhocOnly:     r.URL.Query().Get("adhoc") == "true",
	})
	if err != nil {
		a.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"tasks": tasks})
}

func (a *api) createTask(w http.ResponseWriter, r *http.Request) {
	var in service.TaskInput
	if err := decodeJSON(w, r, defaultBodyLimit, &in); err != nil {
		a.fail(w, r, err)
		return
	}
	t, err := a.svc.CreateTask(r.Context(), auth.UserID(r.Context()), in)
	if err != nil {
		a.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, t)
}

func (a *api) updateTask(w http.ResponseWriter, r *http.Request) {
	var in service.TaskPatch
	if err := decodeJSON(w, r, defaultBodyLimit, &in); err != nil {
		a.fail(w, r, err)
		return
	}
	t, err := a.svc.UpdateTask(r.Context(), auth.UserID(r.Context()), chi.URLParam(r, "id"), in)
	if err != nil {
		a.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, t)
}

func (a *api) deleteTask(w http.ResponseWriter, r *http.Request) {
	if err := a.svc.DeleteTask(r.Context(), auth.UserID(r.Context()), chi.URLParam(r, "id")); err != nil {
		a.fail(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// today serves the merged schedule. Clients should pass their local date;
// the server's UTC date is only a fallback.
func (a *api) today(w http.ResponseWriter, r *http.Request) {
	day := r.URL.Query().Get("date")
	if day == "" {
		day = timeutil.FormatDate(time.Now().UTC())
	}
	t, err := a.svc.Today(r.Context(), auth.UserID(r.Context()), day)
	if err != nil {
		a.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, t)
}
