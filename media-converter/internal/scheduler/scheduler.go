package scheduler

import (
	"context"
	"log/slog"
	"sync/atomic"
	"time"

	"github.com/robfig/cron/v3"
	"github.com/snuffkin/media-converter/internal/logging"
	"github.com/snuffkin/media-converter/internal/scanner"
)

type Scheduler struct{ cron *cron.Cron }

func Start(ctx context.Context, spec string, scan scanner.Scanner, roots []string, log *slog.Logger) (*Scheduler, error) {
	var running atomic.Bool
	c := cron.New(cron.WithLocation(scanLocation(ctx)), cron.WithChain(cron.SkipIfStillRunning(cron.DefaultLogger)))
	_, err := c.AddFunc(spec, func() {
		if !running.CompareAndSwap(false, true) {
			log.Warn("previous scan still running", logging.Event("SCAN"))
			return
		}
		defer running.Store(false)
		r, e := scan.Scan(ctx, roots, false)
		if e != nil {
			log.Error("scheduled scan failed", logging.Event("SCAN"), "error", e)
			return
		}
		log.Info("Library scan complete", logging.Event("SCAN"), "found", r.Found, "added", r.Added, "conflicts", r.Conflicts)
	})
	if err != nil {
		return nil, err
	}
	c.Start()
	go func() { <-ctx.Done(); <-c.Stop().Done() }()
	return &Scheduler{cron: c}, nil
}

type locationKey struct{}

func WithLocation(ctx context.Context, loc *time.Location) context.Context {
	return context.WithValue(ctx, locationKey{}, loc)
}
func scanLocation(ctx context.Context) *time.Location {
	if l, ok := ctx.Value(locationKey{}).(*time.Location); ok {
		return l
	}
	return time.UTC
}
