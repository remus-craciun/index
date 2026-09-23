package httpapi

import (
	"net/http"

	"github.com/remus-craciun/index/server/internal/auth"
	"github.com/remus-craciun/index/server/internal/service"
)

func (a *api) decomposePlan(w http.ResponseWriter, r *http.Request) {
	var in service.DecomposeInput
	if err := decodeJSON(w, r, defaultBodyLimit, &in); err != nil {
		a.fail(w, r, err)
		return
	}
	plan, err := a.svc.DecomposePlan(r.Context(), auth.UserID(r.Context()), in)
	if err != nil {
		a.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, plan)
}

func (a *api) breakdownTask(w http.ResponseWriter, r *http.Request) {
	var in service.BreakdownInput
	if err := decodeJSON(w, r, defaultBodyLimit, &in); err != nil {
		a.fail(w, r, err)
		return
	}
	tasks, err := a.svc.BreakdownTask(r.Context(), auth.UserID(r.Context()), in)
	if err != nil {
		a.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"replaced_task_id": in.TaskID, "tasks": tasks})
}

func (a *api) revisePlan(w http.ResponseWriter, r *http.Request) {
	var in service.ReviseInput
	if err := decodeJSON(w, r, defaultBodyLimit, &in); err != nil {
		a.fail(w, r, err)
		return
	}
	proposal, err := a.svc.RevisePlan(r.Context(), auth.UserID(r.Context()), in)
	if err != nil {
		a.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, proposal)
}
