package webui

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestHandlerServesAppAndFallsBack(t *testing.T) {
	h := Handler()

	index := get(t, h, "/")
	if index.code != http.StatusOK || !strings.Contains(index.body, "flutter_bootstrap.js") {
		t.Fatalf("GET /: status %d, body %q", index.code, index.body)
	}
	if !strings.Contains(index.contentType, "text/html") {
		t.Fatalf("GET / content-type %q", index.contentType)
	}
	if index.cache != "no-cache" {
		t.Fatalf("GET / cache-control %q", index.cache)
	}

	today := get(t, h, "/today")
	if today.code != http.StatusOK || today.body != index.body {
		t.Fatalf("GET /today did not fall back to index.html: status %d", today.code)
	}

	plan := get(t, h, "/plans/abc")
	if plan.body != index.body {
		t.Fatal("GET /plans/abc did not fall back to index.html")
	}

	missing := get(t, h, "/assets/missing.js")
	if missing.body != index.body {
		t.Fatal("missing file did not fall back to index.html")
	}

	icon := get(t, h, "/favicon.png")
	if icon.code != http.StatusOK || !strings.Contains(icon.contentType, "image/png") || len(icon.body) == 0 {
		t.Fatalf("favicon: status %d, type %q, %d bytes", icon.code, icon.contentType, len(icon.body))
	}

	wasm := get(t, h, "/sqlite3.wasm")
	if wasm.code != http.StatusOK || !strings.Contains(wasm.contentType, "application/wasm") {
		t.Fatalf("sqlite3.wasm: status %d, type %q", wasm.code, wasm.contentType)
	}

	api := get(t, h, "/api/v1/no-such")
	if api.code != http.StatusNotFound || strings.Contains(api.body, "flutter_bootstrap.js") {
		t.Fatalf("GET /api/v1/no-such served the web app: %d %q", api.code, api.body)
	}

	req := httptest.NewRequest(http.MethodPost, "/today", nil)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("POST /today: status %d", rec.Code)
	}
}

type response struct {
	code        int
	body        string
	contentType string
	cache       string
}

func get(t *testing.T, h http.Handler, path string) response {
	t.Helper()
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
	body, err := io.ReadAll(rec.Body)
	if err != nil {
		t.Fatal(err)
	}
	return response{
		code:        rec.Code,
		body:        string(body),
		contentType: rec.Header().Get("Content-Type"),
		cache:       rec.Header().Get("Cache-Control"),
	}
}
