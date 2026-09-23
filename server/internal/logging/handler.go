// Package logging provides a human-readable slog handler.
package logging

import (
	"context"
	"fmt"
	"io"
	"log/slog"
	"strconv"
	"strings"
	"sync"
)

// Handler writes one line per record in the form
//
//	2006/01/02 15:04:05 INFO  message key=value key2="quoted value"
//
// matching the timestamp style of chi's request logger.
type Handler struct {
	mu     *sync.Mutex
	w      io.Writer
	level  slog.Leveler
	prefix string // pre-rendered attrs from WithAttrs
	group  string // dotted group prefix from WithGroup
}

// New returns a Handler writing to w at or above level.
func New(w io.Writer, level slog.Leveler) *Handler {
	return &Handler{mu: &sync.Mutex{}, w: w, level: level}
}

func (h *Handler) Enabled(_ context.Context, l slog.Level) bool { return l >= h.level.Level() }

func (h *Handler) Handle(_ context.Context, r slog.Record) error {
	var b strings.Builder
	b.WriteString(r.Time.Format("2006/01/02 15:04:05"))
	fmt.Fprintf(&b, " %-5s ", r.Level.String())
	b.WriteString(r.Message)
	b.WriteString(h.prefix)
	r.Attrs(func(a slog.Attr) bool {
		writeAttr(&b, h.group, a)
		return true
	})
	b.WriteByte('\n')

	h.mu.Lock()
	defer h.mu.Unlock()
	_, err := io.WriteString(h.w, b.String())
	return err
}

func (h *Handler) WithAttrs(attrs []slog.Attr) slog.Handler {
	var b strings.Builder
	for _, a := range attrs {
		writeAttr(&b, h.group, a)
	}
	h2 := *h
	h2.prefix += b.String()
	return &h2
}

func (h *Handler) WithGroup(name string) slog.Handler {
	if name == "" {
		return h
	}
	h2 := *h
	h2.group += name + "."
	return &h2
}

func writeAttr(b *strings.Builder, group string, a slog.Attr) {
	a.Value = a.Value.Resolve()
	if a.Equal(slog.Attr{}) {
		return
	}
	if a.Value.Kind() == slog.KindGroup {
		g := group
		if a.Key != "" {
			g += a.Key + "."
		}
		for _, ga := range a.Value.Group() {
			writeAttr(b, g, ga)
		}
		return
	}
	b.WriteByte(' ')
	b.WriteString(group + a.Key)
	b.WriteByte('=')
	s := a.Value.String()
	if s == "" || strings.ContainsAny(s, " \t\n\"=") {
		s = strconv.Quote(s)
	}
	b.WriteString(s)
}
