package worker

import (
	"bufio"
	"bytes"
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/snuffkin/media-converter/internal/config"
	"github.com/snuffkin/media-converter/internal/converter"
	"github.com/snuffkin/media-converter/internal/hooks"
	"github.com/snuffkin/media-converter/internal/jobs"
	"github.com/snuffkin/media-converter/internal/logging"
	"github.com/snuffkin/media-converter/internal/probe"
	"github.com/snuffkin/media-converter/internal/storage"
	"github.com/snuffkin/media-converter/internal/validator"
)

type Pool struct {
	cfg      config.Config
	store    *storage.Store
	log      *slog.Logger
	prober   probe.Prober
	notifier *hooks.Notifier
	wg       sync.WaitGroup
}

func New(cfg config.Config, s *storage.Store, l *slog.Logger, n *hooks.Notifier) *Pool {
	return &Pool{cfg: cfg, store: s, log: l, prober: probe.Prober{Binary: cfg.FFprobe}, notifier: n}
}
func (p *Pool) Run(ctx context.Context) {
	for i := 0; i < p.cfg.MaxConcurrent; i++ {
		p.wg.Add(1)
		go func() { defer p.wg.Done(); p.loop(ctx) }()
	}
	<-ctx.Done()
	p.wg.Wait()
}
func (p *Pool) loop(ctx context.Context) {
	for {
		if ctx.Err() != nil {
			return
		}
		if p.store.Paused(ctx) {
			sleep(ctx, time.Second)
			continue
		}
		j, e := p.store.Claim(ctx)
		if storage.IsNotFound(e) {
			sleep(ctx, time.Second)
			continue
		}
		if e != nil {
			p.log.Error("claim job", "error", e)
			sleep(ctx, time.Second)
			continue
		}
		p.process(ctx, j)
	}
}
func sleep(ctx context.Context, d time.Duration) {
	select {
	case <-ctx.Done():
	case <-time.After(d):
	}
}

func (p *Pool) process(parent context.Context, j jobs.Job) {
	ctx, cancel := context.WithCancel(parent)
	defer cancel()
	initial, err := os.Stat(j.SourcePath)
	if err != nil {
		p.fail(ctx, j, err, "")
		return
	}
	inPlace := j.SourcePath == j.TargetPath
	if j.SourceMtime != 0 && (initial.Size() != j.SourceSize || initial.ModTime().UnixNano() != j.SourceMtime) {
		p.fail(ctx, j, fmt.Errorf("source changed before conversion; waiting for rescan"), "")
		return
	}
	title := strings.TrimSuffix(filepath.Base(j.SourcePath), filepath.Ext(j.SourcePath))
	p.log.Info(title, logging.Event("PROBE"), "job", j.ID)
	if _, e := os.Stat(j.TargetPath); e == nil && !inPlace {
		_ = p.store.UpdateState(ctx, j.ID, jobs.Skipped, "", "target MP4 already exists", "conflict", "")
		return
	}
	_ = os.Remove(j.TempPath)
	src, err := p.prober.Probe(ctx, j.SourcePath)
	if err != nil {
		p.fail(ctx, j, err, "")
		return
	}
	video, audio, subs := codecSummary(src)
	_ = p.store.SetProbe(ctx, j.ID, video, audio, subs, src.Duration())
	plan, err := converter.Plan(src, p.cfg.Strict)
	if err != nil {
		status := jobs.Failed
		if strings.Contains(err.Error(), "requires transcoding") {
			status = jobs.RequiresTranscode
		}
		_ = p.store.UpdateState(ctx, j.ID, status, "", err.Error(), "", "")
		p.log.Warn(title, logging.Event("SKIP"), "error", err)
		return
	}
	if len(plan.Omissions) > 0 {
		p.log.Warn(title, logging.Event("STREAM"), "omitted", strings.Join(plan.Omissions, ", "))
	}
	copyOnly := len(plan.Omissions) == 0
	for _, stream := range plan.Streams {
		if stream.Mode != "copy" {
			copyOnly = false
		}
	}
	for _, stream := range src.Streams {
		if stream.CodecName == "hevc" && stream.CodecTag != "" && stream.CodecTag != "hvc1" {
			copyOnly = false
		}
	}
	if inPlace && copyOnly {
		_ = p.store.UpdateState(ctx, j.ID, jobs.Skipped, "remux", "", "already compatible MP4", "")
		return
	}
	if j.DryRun || p.cfg.DryRun {
		_ = p.store.UpdateState(ctx, j.ID, jobs.Skipped, plan.Operation, "", "dry run: would process; omitted: "+strings.Join(plan.Omissions, ", "), "")
		return
	}
	if err = checkSpace(j.TargetPath, j.SourceSize, p.cfg.MinFreeSpaceGB); err != nil {
		_ = p.store.UpdateState(ctx, j.ID, jobs.Failed, plan.Operation, err.Error(), "", "")
		p.log.Warn(title, logging.Event("SPACE"), "error", err)
		return
	}
	status := jobs.Remuxing
	if plan.Operation == "audio_transcode" {
		status = jobs.TranscodingAudio
	}
	if plan.Operation == "video_transcode" {
		status = jobs.TranscodingVideo
	}
	_ = p.store.UpdateState(ctx, j.ID, status, plan.Operation, "", strings.Join(plan.Omissions, ", "), "")
	p.log.Info(title, logging.Event(strings.ToUpper(plan.Operation)), "job", j.ID)
	stderr, err := p.execute(ctx, j, src.Duration(), converter.Args(j.SourcePath, j.TempPath, plan))
	if err != nil {
		if p.store.CancelRequested(context.Background(), j.ID) || parent.Err() != nil {
			_ = p.store.UpdateState(context.Background(), j.ID, jobs.Cancelled, plan.Operation, "cancelled", "", stderr)
		} else {
			p.fail(context.Background(), j, err, stderr)
		}
		_ = os.Remove(j.TempPath)
		return
	}
	_ = p.store.UpdateState(ctx, j.ID, jobs.Validating, plan.Operation, "", "", "")
	p.log.Info(title, logging.Event("VALIDATE"), "job", j.ID)
	out, err := validator.Validate(ctx, p.prober, p.cfg.FFmpeg, j.TempPath, src, plan.Operation != "video_transcode", p.cfg.DeepValidation)
	if err == nil {
		err = converter.ValidateStreams(plan, out)
	}
	if err != nil {
		_ = os.Remove(j.TempPath)
		p.fail(ctx, j, fmt.Errorf("validation: %w", err), stderr)
		return
	}
	current, statErr := os.Stat(j.SourcePath)
	if statErr != nil || !os.SameFile(initial, current) || initial.Size() != current.Size() || !initial.ModTime().Equal(current.ModTime()) {
		_ = os.Remove(j.TempPath)
		p.fail(ctx, j, fmt.Errorf("source changed during conversion; output discarded and source preserved"), "")
		return
	}
	if p.store.CancelRequested(ctx, j.ID) || ctx.Err() != nil {
		_ = os.Remove(j.TempPath)
		_ = p.store.UpdateState(context.Background(), j.ID, jobs.Cancelled, plan.Operation, "cancelled before publication", "", "")
		return
	}
	if err = inheritMetadata(j.SourcePath, j.TempPath); err != nil {
		p.log.Warn(title, "metadata", err)
	}
	if _, err = os.Stat(j.TargetPath); err == nil && !inPlace {
		_ = os.Remove(j.TempPath)
		_ = p.store.UpdateState(ctx, j.ID, jobs.Skipped, plan.Operation, "target appeared during conversion", "conflict", stderr)
		return
	}
	// Normal conversions publish without overwriting. An incompatible MP4 is
	// atomically replaced only after validating its complete normalized output.
	if inPlace {
		if !p.cfg.DeleteOriginal || len(plan.Omissions) > 0 {
			backup := filepath.Join(filepath.Dir(j.SourcePath), "."+filepath.Base(j.SourcePath)+".media-converter.original-"+strconv.FormatInt(time.Now().UnixNano(), 10)+".mp4")
			if err = os.Link(j.SourcePath, backup); err != nil {
				_ = os.Remove(j.TempPath)
				p.fail(ctx, j, fmt.Errorf("preserve original MP4: %w", err), stderr)
				return
			}
			_ = p.store.UpdateState(ctx, j.ID, jobs.Validating, plan.Operation, "", "original retained: "+backup, "")
		}
		err = os.Rename(j.TempPath, j.TargetPath)
	} else {
		err = os.Link(j.TempPath, j.TargetPath)
	}
	if err != nil {
		_ = os.Remove(j.TempPath)
		p.fail(ctx, j, fmt.Errorf("publish output: %w", err), stderr)
		return
	}
	_ = os.Remove(j.TempPath)
	st, err := os.Stat(j.TargetPath)
	if err != nil {
		p.fail(ctx, j, fmt.Errorf("stat published output: %w", err), stderr)
		return
	}
	if !inPlace && p.cfg.DeleteOriginal && len(plan.Omissions) == 0 {
		latest, statErr := os.Stat(j.SourcePath)
		if statErr != nil || !os.SameFile(initial, latest) || initial.Size() != latest.Size() || !initial.ModTime().Equal(latest.ModTime()) {
			p.fail(ctx, j, fmt.Errorf("output valid but source changed before cleanup; source preserved"), stderr)
			return
		}
		if err = os.Remove(j.SourcePath); err != nil {
			p.fail(ctx, j, fmt.Errorf("output valid but source cleanup failed: %w", err), stderr)
			return
		}
		p.log.Info("Removed validated source", logging.Event("CLEANUP"), "job", j.ID)
	}
	_ = p.store.Finish(ctx, j.ID, st.Size())
	p.log.Info(title, logging.Event("DONE"), "source_bytes", j.SourceSize, "target_bytes", st.Size())
	for _, e := range p.notifier.RefreshPath(ctx, j.SourcePath) {
		p.log.Warn("library refresh failed", "error", e)
	}
	p.notifier.QueueJellyfinRefresh()
}
func (p *Pool) fail(ctx context.Context, j jobs.Job, e error, stderr string) {
	_ = p.store.UpdateState(ctx, j.ID, jobs.Failed, "", e.Error(), "", stderr)
	p.log.Error(filepath.Base(j.SourcePath), logging.Event("FAILED"), "job", j.ID, "error", e)
}
func (p *Pool) execute(ctx context.Context, j jobs.Job, duration float64, args []string) (string, error) {
	cmd := exec.Command(p.cfg.FFmpeg, args...)
	stdout, e := cmd.StdoutPipe()
	if e != nil {
		return "", e
	}
	rw := &limitedWriter{max: 256 * 1024}
	cmd.Stderr = rw
	if e = cmd.Start(); e != nil {
		return "", e
	}
	done := make(chan struct{})
	var stopOnce sync.Once
	stopProcess := func() {
		stopOnce.Do(func() {
			if cmd.Process == nil {
				return
			}
			_ = cmd.Process.Signal(syscall.SIGTERM)
			go func() {
				select {
				case <-done:
				case <-time.After(5 * time.Second):
					_ = cmd.Process.Kill()
				}
			}()
		})
	}
	go func() {
		select {
		case <-ctx.Done():
			stopProcess()
		case <-done:
			return
		}
	}()
	go func() {
		t := time.NewTicker(time.Second)
		defer t.Stop()
		for {
			select {
			case <-done:
				return
			case <-t.C:
				if p.store.CancelRequested(context.Background(), j.ID) {
					stopProcess()
					return
				}
			}
		}
	}()
	scan := bufio.NewScanner(stdout)
	vals := map[string]string{}
	for scan.Scan() {
		line := scan.Text()
		k, v, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		vals[k] = v
		if k == "progress" {
			outUS, _ := strconv.ParseFloat(vals["out_time_us"], 64)
			if outUS == 0 {
				outUS, _ = strconv.ParseFloat(vals["out_time_ms"], 64)
			}
			pct := 0.0
			if duration > 0 {
				pct = outUS / 1e6 / duration * 100
				if pct > 99.9 {
					pct = 99.9
				}
			}
			size, _ := strconv.ParseInt(vals["total_size"], 10, 64)
			_ = p.store.Progress(context.Background(), j.ID, pct, vals["speed"], size)
		}
	}
	e = cmd.Wait()
	close(done)
	if e != nil {
		return rw.String(), fmt.Errorf("ffmpeg: %w", e)
	}
	return rw.String(), scan.Err()
}

type limitedWriter struct {
	b   bytes.Buffer
	max int
}

func (w *limitedWriter) Write(data []byte) (int, error) {
	n := len(data)
	if w.b.Len() < w.max {
		left := w.max - w.b.Len()
		_, _ = w.b.Write(data[:min(len(data), left)])
	}
	return n, nil
}
func (w *limitedWriter) String() string { return w.b.String() }
func checkSpace(path string, source int64, marginGB float64) error {
	var st syscall.Statfs_t
	if e := syscall.Statfs(filepath.Dir(path), &st); e != nil {
		return e
	}
	free := int64(st.Bavail) * int64(st.Bsize)
	need := source + int64(marginGB*1024*1024*1024)
	if free < need {
		return fmt.Errorf("insufficient disk space: %.1f GiB free, %.1f GiB required", float64(free)/(1<<30), float64(need)/(1<<30))
	}
	return nil
}
func inheritMetadata(src, dst string) error {
	st, e := os.Stat(src)
	if e != nil {
		return e
	}
	if e = os.Chmod(dst, st.Mode().Perm()); e != nil {
		return e
	}
	_ = os.Chtimes(dst, st.ModTime(), st.ModTime())
	if sys, ok := st.Sys().(*syscall.Stat_t); ok {
		if e = os.Chown(dst, int(sys.Uid), int(sys.Gid)); e != nil && !errors.Is(e, syscall.EPERM) {
			return e
		}
	}
	return nil
}
func codecSummary(m probe.Media) (string, string, string) {
	var v, a, s []string
	for _, x := range m.Streams {
		switch x.CodecType {
		case "video":
			v = append(v, x.CodecName)
		case "audio":
			a = append(a, x.CodecName)
		case "subtitle":
			s = append(s, x.CodecName)
		}
	}
	return strings.Join(v, ","), strings.Join(a, ","), strings.Join(s, ",")
}
