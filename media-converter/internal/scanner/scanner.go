package scanner

import (
	"context"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/snuffkin/media-converter/internal/jobs"
	"github.com/snuffkin/media-converter/internal/media"
	"github.com/snuffkin/media-converter/internal/storage"
)

type Scanner struct {
	Store          *storage.Store
	Priority       int
	Excludes       []string
	IncludeSamples bool
	SettleTime     time.Duration
	ready          func(string, fs.FileInfo) bool
}
type Result struct{ Found, Added, Existing, Excluded, Conflicts int }

func (s Scanner) Scan(ctx context.Context, roots []string, dry bool) (Result, error) {
	var result Result
	for _, root := range roots {
		if root == "" {
			continue
		}
		err := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if ctx.Err() != nil {
				return ctx.Err()
			}
			name := d.Name()
			if d.IsDir() {
				if path != root && excludedDir(name, s.Excludes) {
					result.Excluded++
					return filepath.SkipDir
				}
				return nil
			}
			if !d.Type().IsRegular() || !media.Eligible(path) {
				return nil
			}
			if !s.IncludeSamples && strings.HasSuffix(strings.ToLower(strings.TrimSuffix(name, filepath.Ext(name))), ".sample") {
				result.Excluded++
				return nil
			}
			for _, p := range s.Excludes {
				if ok, _ := filepath.Match(p, name); ok {
					result.Excluded++
					return nil
				}
			}
			result.Found++
			info, e := d.Info()
			if e != nil {
				return e
			}
			if s.SettleTime > 0 && time.Since(info.ModTime()) < s.SettleTime {
				return nil
			}
			if s.ready != nil && !s.ready(path, info) {
				return nil
			}
			target, temp, e := media.Paths(path)
			if e != nil {
				return e
			}
			if _, e = os.Stat(target); e == nil && target != path {
				result.Conflicts++
				added, addErr := s.Store.Add(ctx, jobs.Job{SourcePath: path, TargetPath: target, TempPath: temp, Status: jobs.Skipped, Priority: s.Priority, SourceSize: info.Size(), SourceMtime: info.ModTime().UnixNano(), DryRun: dry, ErrorMessage: "target MP4 already exists", Notes: "conflict"})
				if addErr != nil {
					return addErr
				}
				if !added {
					return s.Store.MarkConflict(ctx, path)
				}
				return nil
			} else if e != nil && !os.IsNotExist(e) {
				return e
			}
			added, e := s.Store.Add(ctx, jobs.Job{SourcePath: path, TargetPath: target, TempPath: temp, Priority: s.Priority, SourceSize: info.Size(), SourceMtime: info.ModTime().UnixNano(), DryRun: dry})
			if added {
				result.Added++
			} else {
				result.Existing++
			}
			return e
		})
		if err != nil && !os.IsNotExist(err) {
			return result, err
		}
	}
	return result, nil
}

// Polling also works across Docker bind mounts and libraries imported by rename.
// Source size + mtime deduplicates unchanged files and requeues changed inputs.
func (s Scanner) Watch(ctx context.Context, roots []string, interval time.Duration, report func(Result, error)) {
	type observation struct {
		size, mtime int64
		since       time.Time
	}
	observations := map[string]observation{}
	seen := map[string]bool{}
	s.ready = func(path string, info fs.FileInfo) bool {
		seen[path] = true
		previous, ok := observations[path]
		if !ok || previous.size != info.Size() || previous.mtime != info.ModTime().UnixNano() {
			observations[path] = observation{info.Size(), info.ModTime().UnixNano(), time.Now()}
			return false
		}
		return time.Since(previous.since) >= s.SettleTime
	}
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		clear(seen)
		r, err := s.Scan(ctx, roots, false)
		if err == nil {
			for path := range observations {
				if !seen[path] {
					delete(observations, path)
				}
			}
		}
		report(r, err)
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}
func excludedDir(n string, patterns []string) bool {
	switch strings.ToLower(n) {
	case "@eadir", ".recycle", ".trash", "lost+found":
		return true
	}
	for _, p := range patterns {
		if ok, _ := filepath.Match(p, n); ok {
			return true
		}
	}
	return false
}
func fileSize(p string) int64 {
	st, e := os.Stat(p)
	if e != nil {
		return 0
	}
	return st.Size()
}
