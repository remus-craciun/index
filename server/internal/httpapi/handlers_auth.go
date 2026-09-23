package httpapi

import "net/http"

type credentials struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

func (a *api) authStatus(w http.ResponseWriter, r *http.Request) {
	has, err := a.svc.HasUser(r.Context())
	if err != nil {
		a.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"has_user": has})
}

func (a *api) register(w http.ResponseWriter, r *http.Request) {
	var in credentials
	if err := decodeJSON(w, r, defaultBodyLimit, &in); err != nil {
		a.fail(w, r, err)
		return
	}
	tokens, err := a.svc.Register(r.Context(), in.Email, in.Password)
	if err != nil {
		a.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusCreated, tokens)
}

func (a *api) login(w http.ResponseWriter, r *http.Request) {
	var in credentials
	if err := decodeJSON(w, r, defaultBodyLimit, &in); err != nil {
		a.fail(w, r, err)
		return
	}
	tokens, err := a.svc.Login(r.Context(), in.Email, in.Password)
	if err != nil {
		a.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, tokens)
}

func (a *api) refresh(w http.ResponseWriter, r *http.Request) {
	var in struct {
		RefreshToken string `json:"refresh_token"`
	}
	if err := decodeJSON(w, r, defaultBodyLimit, &in); err != nil {
		a.fail(w, r, err)
		return
	}
	tokens, err := a.svc.Refresh(r.Context(), in.RefreshToken)
	if err != nil {
		a.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, tokens)
}

func (a *api) logout(w http.ResponseWriter, r *http.Request) {
	var in struct {
		RefreshToken string `json:"refresh_token"`
	}
	if err := decodeJSON(w, r, defaultBodyLimit, &in); err != nil {
		a.fail(w, r, err)
		return
	}
	if err := a.svc.Logout(r.Context(), in.RefreshToken); err != nil {
		a.fail(w, r, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
