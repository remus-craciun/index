package logging

import (
	"bytes"
	"errors"
	"log/slog"
	"regexp"
	"testing"
)

func TestHandlerFormat(t *testing.T) {
	var buf bytes.Buffer
	log := slog.New(New(&buf, slog.LevelInfo)).With("svc", "api").WithGroup("req")
	log.Debug("hidden")
	log.Error("request failed", "err", errors.New("boom: bad thing"), "status", 500)

	want := regexp.MustCompile(`^\d{4}/\d\d/\d\d \d\d:\d\d:\d\d ERROR request failed svc=api req\.err="boom: bad thing" req\.status=500\n$`)
	if !want.Match(buf.Bytes()) {
		t.Fatalf("unexpected output: %q", buf.String())
	}
}
