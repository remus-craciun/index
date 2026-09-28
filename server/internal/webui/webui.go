// Package webui serves the Flutter web build embedded in the server binary.
package webui

import (
	"embed"
	"io"
	"io/fs"
	"mime"
	"net/http"
	"path"
	"strings"
)

//go:embed all:dist
var dist embed.FS

// Handler serves the embedded Flutter web app. A request for a path that is
// not a real file receives index.html, so client routes such as /today keep
// working after a refresh.
func Handler() http.Handler {
	sub, err := fs.Sub(dist, "dist")
	if err != nil {
		panic(err)
	}
	return spa{fsys: sub}
}

type spa struct {
	fsys fs.FS
}

func (s spa) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet && r.Method != http.MethodHead {
		w.Header().Set("Allow", "GET, HEAD")
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	// /api is the JSON API even when no route matched inside it.
	if r.URL.Path == "/api" || strings.HasPrefix(r.URL.Path, "/api/") {
		http.NotFound(w, r)
		return
	}

	name := strings.TrimPrefix(path.Clean("/"+r.URL.Path), "/")
	if name == "" || name == "." {
		s.serveIndex(w, r)
		return
	}

	f, err := s.fsys.Open(name)
	if err != nil {
		s.serveIndex(w, r)
		return
	}
	defer f.Close()

	stat, err := f.Stat()
	if err != nil || stat.IsDir() {
		s.serveIndex(w, r)
		return
	}
	rs, ok := f.(io.ReadSeeker)
	if !ok {
		s.serveIndex(w, r)
		return
	}
	if isShell(name) {
		w.Header().Set("Cache-Control", "no-cache")
	}
	if ct := mime.TypeByExtension(path.Ext(stat.Name())); ct == "" && path.Ext(stat.Name()) == ".wasm" {
		w.Header().Set("Content-Type", "application/wasm")
	}
	http.ServeContent(w, r, stat.Name(), stat.ModTime(), rs)
}

func (s spa) serveIndex(w http.ResponseWriter, r *http.Request) {
	f, err := s.fsys.Open("index.html")
	if err != nil {
		http.Error(w, "web UI is not built", http.StatusNotFound)
		return
	}
	defer f.Close()
	stat, err := f.Stat()
	if err != nil {
		http.Error(w, "web UI is not built", http.StatusNotFound)
		return
	}
	rs, ok := f.(io.ReadSeeker)
	if !ok {
		http.Error(w, "web UI is not built", http.StatusNotFound)
		return
	}
	w.Header().Set("Cache-Control", "no-cache")
	http.ServeContent(w, r, "index.html", stat.ModTime(), rs)
}

// isShell marks the files a new deploy must not leave cached under the old
// bytes. Flutter does not content-hash these names.
func isShell(name string) bool {
	switch path.Base(name) {
	case "index.html", "flutter.js", "flutter_bootstrap.js", "flutter_service_worker.js", "main.dart.js", "manifest.json", "version.json":
		return true
	default:
		return false
	}
}
