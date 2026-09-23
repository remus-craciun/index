package httpapi

import (
	"context"
	"net/http"
	"time"

	"github.com/remus-craciun/index/server/internal/timeutil"
)

type healthResponse struct {
	Status   string `json:"status"`   // "ok" or "unavailable"
	Database string `json:"database"` // "ok" or "unavailable"
	Time     string `json:"time"`     // server clock, UTC
}

// health reports whether the service and its database are usable. It is
// public so the mobile app can validate a server address before login.
func (a *api) health(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()

	resp := healthResponse{Status: "ok", Database: "ok", Time: timeutil.Now()}
	status := http.StatusOK
	if err := a.svc.Ping(ctx); err != nil {
		a.log.Error("health check: database unavailable", "err", err)
		resp.Status, resp.Database = "unavailable", "unavailable"
		status = http.StatusServiceUnavailable
	}
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, status, resp)
}
