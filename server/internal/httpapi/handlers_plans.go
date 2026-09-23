package httpapi

import (
	"net/http"

	"github.com/go-chi/chi/v5"

	"github.com/remus-craciun/index/server/internal/auth"
	"github.com/remus-craciun/index/server/internal/service"
)

func (a *api) listPlans(w http.ResponseWriter, r *http.Request) {
	plans, err := a.svc.ListPlans(r.Context(), auth.UserID(r.Context()))
	if err != nil {
		a.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"plans": plans})
}

func (a *api) getPlan(w http.ResponseWriter, r *http.Request) {
	plan, err := a.svc.GetPlan(r.Context(), auth.UserID(r.Context()), chi.URLParam(r, "id"))
	if err != nil {
		a.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, plan)
}

func (a *api) createPlan(w http.ResponseWriter, r *http.Request) {
	var in service.PlanInput
	if err := decodeJSON(w, r, defaultBodyLimit, &in); err != nil {
		a.fail(w, r, err)
		return
	}
	plan, err := a.svc.CreatePlan(r.Context(), auth.UserID(r.Context()), in)
	if err != nil {
		a.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, plan)
}

func (a *api) updatePlan(w http.ResponseWriter, r *http.Request) {
	var in service.PlanPatch
	if err := decodeJSON(w, r, defaultBodyLimit, &in); err != nil {
		a.fail(w, r, err)
		return
	}
	plan, err := a.svc.UpdatePlan(r.Context(), auth.UserID(r.Context()), chi.URLParam(r, "id"), in)
	if err != nil {
		a.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, plan)
}

func (a *api) deletePlan(w http.ResponseWriter, r *http.Request) {
	if err := a.svc.DeletePlan(r.Context(), auth.UserID(r.Context()), chi.URLParam(r, "id")); err != nil {
		a.fail(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (a *api) createMilestone(w http.ResponseWriter, r *http.Request) {
	var in service.MilestoneInput
	if err := decodeJSON(w, r, defaultBodyLimit, &in); err != nil {
		a.fail(w, r, err)
		return
	}
	m, err := a.svc.CreateMilestone(r.Context(), auth.UserID(r.Context()), chi.URLParam(r, "id"), in)
	if err != nil {
		a.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, m)
}

func (a *api) updateMilestone(w http.ResponseWriter, r *http.Request) {
	var in service.MilestonePatch
	if err := decodeJSON(w, r, defaultBodyLimit, &in); err != nil {
		a.fail(w, r, err)
		return
	}
	m, err := a.svc.UpdateMilestone(r.Context(), auth.UserID(r.Context()), chi.URLParam(r, "id"), in)
	if err != nil {
		a.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, m)
}

func (a *api) deleteMilestone(w http.ResponseWriter, r *http.Request) {
	if err := a.svc.DeleteMilestone(r.Context(), auth.UserID(r.Context()), chi.URLParam(r, "id")); err != nil {
		a.fail(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (a *api) applyRevision(w http.ResponseWriter, r *http.Request) {
	var in service.ApplyRevisionInput
	if err := decodeJSON(w, r, defaultBodyLimit, &in); err != nil {
		a.fail(w, r, err)
		return
	}
	plan, err := a.svc.ApplyRevision(r.Context(), auth.UserID(r.Context()), chi.URLParam(r, "id"), in)
	if err != nil {
		a.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, plan)
}
