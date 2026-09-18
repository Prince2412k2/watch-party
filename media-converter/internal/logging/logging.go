package logging

import (
	"context"
	"fmt"
	"io"
	"log/slog"
	"os"
	"strings"
	"sync"
)

type prettyHandler struct {
	out   io.Writer
	level slog.Level
	mu    *sync.Mutex
	attrs []slog.Attr
}

func New(level string, json bool) *slog.Logger {
	var l slog.Level
	switch strings.ToLower(level) {
	case "debug":
		l = slog.LevelDebug
	case "warn":
		l = slog.LevelWarn
	case "error":
		l = slog.LevelError
	default:
		l = slog.LevelInfo
	}
	if json {
		return slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: l}))
	}
	return slog.New(&prettyHandler{out: os.Stdout, level: l, mu: &sync.Mutex{}})
}
func (h *prettyHandler) Enabled(_ context.Context, l slog.Level) bool { return l >= h.level }
func (h *prettyHandler) Handle(_ context.Context, r slog.Record) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	label := "INFO"
	if r.Level >= slog.LevelError {
		label = "ERROR"
	} else if r.Level >= slog.LevelWarn {
		label = "WARN"
	} else if r.Level <= slog.LevelDebug {
		label = "DEBUG"
	}
	if a := firstAttr(r, "event"); a != "" {
		label = strings.ToUpper(a)
	}
	_, _ = fmt.Fprintf(h.out, "%s  %-9s %s", r.Time.Format("15:04:05"), label, r.Message)
	for _, a := range h.attrs {
		if a.Key != "event" {
			_, _ = fmt.Fprintf(h.out, "  %s=%v", a.Key, a.Value.Any())
		}
	}
	r.Attrs(func(a slog.Attr) bool {
		if a.Key != "event" {
			_, _ = fmt.Fprintf(h.out, "  %s=%v", a.Key, a.Value.Any())
		}
		return true
	})
	_, err := fmt.Fprintln(h.out)
	return err
}
func firstAttr(r slog.Record, key string) string {
	out := ""
	r.Attrs(func(a slog.Attr) bool {
		if a.Key == key {
			out = a.Value.String()
			return false
		}
		return true
	})
	return out
}
func (h *prettyHandler) WithAttrs(a []slog.Attr) slog.Handler {
	n := *h
	n.attrs = append(append([]slog.Attr{}, h.attrs...), a...)
	return &n
}
func (h *prettyHandler) WithGroup(string) slog.Handler { return h }
func Event(name string) slog.Attr                      { return slog.String("event", name) }
