package scanner

import (
	"context"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	"github.com/snuffkin/media-converter/internal/jobs"
	"github.com/snuffkin/media-converter/internal/media"
	"github.com/snuffkin/media-converter/internal/storage"
)

type Scanner struct {
	Store          *storage.Store
	Priority       int
	Excludes       []string
	IncludeSamples bool
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
			if !strings.EqualFold(filepath.Ext(name), ".mkv") {
				return nil
			}
			if !s.IncludeSamples && strings.HasSuffix(strings.ToLower(name), ".sample.mkv") {
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
			target, temp, e := media.Paths(path)
			if e != nil {
				return e
			}
			if _, e = os.Stat(target); e == nil {
				result.Conflicts++
				added, addErr := s.Store.Add(ctx, jobs.Job{SourcePath: path, TargetPath: target, TempPath: temp, Status: jobs.Skipped, Priority: s.Priority, SourceSize: fileSize(path), DryRun: dry, ErrorMessage: "target MP4 already exists", Notes: "conflict"})
				if addErr != nil {
					return addErr
				}
				if !added {
					return s.Store.MarkConflict(ctx, path)
				}
				return nil
			} else if !os.IsNotExist(e) {
				return e
			}
			added, e := s.Store.Add(ctx, jobs.Job{SourcePath: path, TargetPath: target, TempPath: temp, Priority: s.Priority, SourceSize: fileSize(path), DryRun: dry})
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
