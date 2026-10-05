// Package web exposes the converter's control plane on the private service
// network. Watchparty authenticates the browser and proxies administrator calls.
package web

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/snuffkin/media-converter/internal/config"
	"github.com/snuffkin/media-converter/internal/jobs"
	"github.com/snuffkin/media-converter/internal/scanner"
	"github.com/snuffkin/media-converter/internal/storage"
)

func Handler(cfg config.Config, store *storage.Store, scan scanner.Scanner) http.Handler {
	var scanMu sync.Mutex
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Cache-Control", "no-store")
		fail := func(code int, err string) {
			w.WriteHeader(code)
			_ = json.NewEncoder(w).Encode(map[string]string{"error": err})
		}
		if cfg.APIKey == "" || !strings.HasPrefix(r.Header.Get("Authorization"), "Bearer ") || subtle.ConstantTimeCompare([]byte(strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")), []byte(cfg.APIKey)) != 1 {
			fail(http.StatusUnauthorized, "converter authentication required")
			return
		}
		ctx := r.Context()
		if r.Method == "GET" && r.URL.Path == "/api/state" {
			list, err := store.List(ctx, 2000)
			if err != nil {
				fail(500, err.Error())
				return
			}
			if list == nil {
				list = []jobs.Job{}
			}
			counts, err := store.Counts(ctx)
			if err != nil {
				fail(500, err.Error())
				return
			}
			_ = json.NewEncoder(w).Encode(map[string]any{"jobs": list, "counts": counts, "paused": store.Paused(ctx), "policy": map[string]any{
				"output": "MP4", "video": "Copy H.264 / HEVC; other SDR video → H.264 CRF 18", "audio": "Copy compatible tracks; lossless → ALAC; other audio → AAC",
				"workers": cfg.MaxConcurrent, "watchSeconds": cfg.WatchInterval.Seconds(), "settleSeconds": cfg.SettleTime.Seconds(), "strict": cfg.Strict, "deleteOriginal": cfg.DeleteOriginal,
			}})
			return
		}
		if r.Method != "POST" {
			fail(405, "method not allowed")
			return
		}
		var err error
		switch r.URL.Path {
		case "/api/scan":
			if !scanMu.TryLock() {
				fail(409, "a scan is already running")
				return
			}
			defer scanMu.Unlock()
			result, scanErr := scan.Scan(ctx, []string{cfg.MoviesDir, cfg.TVDir}, false)
			if scanErr != nil {
				fail(500, scanErr.Error())
				return
			}
			_ = json.NewEncoder(w).Encode(result)
			return
		case "/api/pause":
			err = store.SetPaused(ctx, true)
		case "/api/resume":
			err = store.SetPaused(ctx, false)
		default:
			parts := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
			if len(parts) != 4 || parts[0] != "api" || parts[1] != "jobs" {
				fail(404, "not found")
				return
			}
			id, parseErr := strconv.ParseInt(parts[2], 10, 64)
			if parseErr != nil || id < 1 {
				fail(400, "invalid job id")
				return
			}
			switch parts[3] {
			case "next":
				err = store.MoveToFront(ctx, id)
			case "up":
				err = store.Reorder(ctx, []int64{id}, -1)
			case "down":
				err = store.Reorder(ctx, []int64{id}, 1)
			case "retry":
				err = store.Retry(ctx, id)
			case "cancel":
				err = store.Cancel(ctx, id)
			default:
				fail(404, "unknown action")
				return
			}
		}
		if err != nil {
			fail(409, err.Error())
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]bool{"ok": true})
	})
}

func Serve(ctx context.Context, cfg config.Config, handler http.Handler) error {
	server := &http.Server{Addr: cfg.HTTPAddr, Handler: handler, ReadHeaderTimeout: 5 * time.Second, IdleTimeout: 60 * time.Second}
	go func() {
		<-ctx.Done()
		shutdown, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = server.Shutdown(shutdown)
	}()
	err := server.ListenAndServe()
	if errors.Is(err, http.ErrServerClosed) {
		return nil
	}
	return err
}
