package httpapi

import (
	"net/http"

	"github.com/remus-craciun/index/server/internal/auth"
	"github.com/remus-craciun/index/server/internal/service"
)

const syncBodyLimit = 16 << 20 // 16 MiB

func (a *api) sync(w http.ResponseWriter, r *http.Request) {
	var in service.SyncRequest
	if err := decodeJSON(w, r, syncBodyLimit, &in); err != nil {
		a.fail(w, r, err)
		return
	}
	resp, err := a.svc.Sync(r.Context(), auth.UserID(r.Context()), in)
	if err != nil {
		a.fail(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, resp)
}
