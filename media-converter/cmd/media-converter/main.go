package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/snuffkin/media-converter/internal/config"
	"github.com/snuffkin/media-converter/internal/hooks"
	"github.com/snuffkin/media-converter/internal/logging"
	"github.com/snuffkin/media-converter/internal/scanner"
	"github.com/snuffkin/media-converter/internal/scheduler"
	"github.com/snuffkin/media-converter/internal/storage"
	"github.com/snuffkin/media-converter/internal/tui"
	"github.com/snuffkin/media-converter/internal/worker"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "media-converter:", err)
		os.Exit(1)
	}
}
func run() error {
	args := os.Args[1:]
	cmd := "serve"
	if len(args) > 0 {
		cmd = args[0]
		args = args[1:]
	}
	if cmd == "help" || cmd == "--help" || cmd == "-h" {
		usage()
		return nil
	}
	if err := dropPrivileges(); err != nil {
		return err
	}
	cfg, err := config.Load()
	if err != nil {
		return err
	}
	store, err := storage.Open(filepath.Join(cfg.DataDir, "media-converter.db"))
	if err != nil {
		return fmt.Errorf("open database: %w", err)
	}
	defer store.Close()
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	scan := scanner.Scanner{Store: store, Priority: cfg.Priority, Excludes: cfg.ExcludePatterns, IncludeSamples: cfg.IncludeSamples}
	switch cmd {
	case "serve":
		log := logging.New(cfg.LogLevel, strings.EqualFold(os.Getenv("LOG_FORMAT"), "json"))
		recovered, e := store.Recover(ctx)
		if e != nil {
			return e
		}
		for _, j := range recovered {
			_ = os.Remove(j.TempPath)
		}
		if len(recovered) > 0 {
			log.Warn("Recovered interrupted jobs", logging.Event("RECOVER"), "count", len(recovered))
		}
		sctx := scheduler.WithLocation(ctx, cfg.Timezone)
		if _, e = scheduler.Start(sctx, cfg.Schedule, scan, []string{cfg.MoviesDir, cfg.TVDir}, log); e != nil {
			return fmt.Errorf("schedule: %w", e)
		}
		n := hooks.New(hooks.Config{SonarrURL: cfg.SonarrURL, SonarrKey: cfg.SonarrAPIKey, RadarrURL: cfg.RadarrURL, RadarrKey: cfg.RadarrAPIKey, JellyfinURL: cfg.JellyfinURL, JellyfinKey: cfg.JellyfinKey})
		log.Info("Worker started", logging.Event("START"), "schedule", cfg.Schedule, "workers", cfg.MaxConcurrent)
		worker.New(cfg, store, log, n).Run(ctx)
		return nil
	case "scan":
		fs := flag.NewFlagSet("scan", flag.ContinueOnError)
		dry := fs.Bool("dry-run", false, "queue dry-run jobs")
		if e := fs.Parse(args); e != nil {
			return e
		}
		r, e := scan.Scan(ctx, []string{cfg.MoviesDir, cfg.TVDir}, *dry)
		if e != nil {
			return e
		}
		fmt.Printf("found=%d added=%d existing=%d conflicts=%d excluded=%d\n", r.Found, r.Added, r.Existing, r.Conflicts, r.Excluded)
		return nil
	case "convert":
		fs := flag.NewFlagSet("convert", flag.ContinueOnError)
		dry := fs.Bool("dry-run", false, "probe and plan only")
		priority := fs.Int("priority", cfg.Priority, "queue priority")
		if e := fs.Parse(args); e != nil {
			return e
		}
		if fs.NArg() != 1 {
			return fmt.Errorf("usage: media-converter convert [--dry-run] [--priority N] PATH")
		}
		scan.Priority = *priority
		r, e := scan.Scan(ctx, []string{fs.Arg(0)}, *dry)
		if e != nil {
			return e
		}
		fmt.Printf("found=%d added=%d existing=%d conflicts=%d\n", r.Found, r.Added, r.Existing, r.Conflicts)
		return nil
	case "status":
		counts, e := store.Counts(ctx)
		if e != nil {
			return e
		}
		b, _ := json.MarshalIndent(map[string]any{"paused": store.Paused(ctx), "jobs": counts}, "", "  ")
		fmt.Println(string(b))
		return nil
	case "queue":
		xs, e := store.List(ctx, 500)
		if e != nil {
			return e
		}
		for _, j := range xs {
			fmt.Printf("%-6d P%-3d %-20s %6.1f%% %-16s %s\n", j.ID, j.Priority, j.Status, j.Progress, j.OperationType, j.SourcePath)
		}
		return nil
	case "retry", "cancel":
		if len(args) != 1 {
			return fmt.Errorf("usage: media-converter %s JOB_ID", cmd)
		}
		id, e := strconv.ParseInt(args[0], 10, 64)
		if e != nil {
			return e
		}
		if cmd == "retry" {
			e = store.Retry(ctx, id)
		} else {
			e = store.Cancel(ctx, id)
		}
		return e
	case "priority":
		if len(args) != 2 {
			return fmt.Errorf("usage: media-converter priority JOB_ID PRIORITY")
		}
		id, e := strconv.ParseInt(args[0], 10, 64)
		if e != nil {
			return e
		}
		p, e := strconv.Atoi(args[1])
		if e != nil {
			return e
		}
		if p < 0 {
			return fmt.Errorf("priority must be non-negative")
		}
		return store.Priority(ctx, id, p)
	case "resolve":
		if len(args) != 2 || args[1] != "archive-target" {
			return fmt.Errorf("usage: media-converter resolve JOB_ID archive-target")
		}
		id, e := strconv.ParseInt(args[0], 10, 64)
		if e != nil {
			return e
		}
		j, e := store.Get(ctx, id)
		if e != nil {
			return e
		}
		if j.Status != "skipped" || j.Notes != "conflict" {
			return fmt.Errorf("job %d is not a target conflict", id)
		}
		backup := j.TargetPath + ".media-converter.conflict-" + time.Now().Format("20060102-150405")
		if e = os.Rename(j.TargetPath, backup); e != nil {
			return fmt.Errorf("archive target: %w", e)
		}
		if e = store.Retry(ctx, id); e != nil {
			return e
		}
		fmt.Println("archived existing target to", backup)
		return nil
	case "pause":
		return store.SetPaused(ctx, true)
	case "resume":
		return store.SetPaused(ctx, false)
	case "tui":
		return tui.Run(store, cfg)
	default:
		return fmt.Errorf("unknown command %q", cmd)
	}
}
func dropPrivileges() error {
	if os.Geteuid() != 0 || os.Getenv("PUID") == "" || os.Getenv("PGID") == "" {
		return nil
	}
	uid, err := strconv.Atoi(os.Getenv("PUID"))
	if err != nil {
		return fmt.Errorf("invalid PUID: %w", err)
	}
	gid, err := strconv.Atoi(os.Getenv("PGID"))
	if err != nil {
		return fmt.Errorf("invalid PGID: %w", err)
	}
	if err = syscall.Setgroups([]int{gid}); err != nil {
		return fmt.Errorf("set groups: %w", err)
	}
	if err = syscall.Setgid(gid); err != nil {
		return fmt.Errorf("set PGID: %w", err)
	}
	if err = syscall.Setuid(uid); err != nil {
		return fmt.Errorf("set PUID: %w", err)
	}
	return nil
}
func usage() {
	fmt.Print(`media-converter [serve]
media-converter scan [--dry-run]
media-converter convert [--dry-run] [--priority N] PATH
media-converter status | queue | tui
media-converter retry JOB_ID | cancel JOB_ID | priority JOB_ID PRIORITY
media-converter resolve JOB_ID archive-target
media-converter pause | resume
`)
}
