package scanner

import (
	"context"
	"os"
	"path/filepath"
	"testing"

	"github.com/snuffkin/media-converter/internal/jobs"
	"github.com/snuffkin/media-converter/internal/storage"
)

func TestConflictAndSampleExclusion(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "movie.mkv")
	if err := os.WriteFile(src, []byte("mkv"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "movie.mp4"), []byte("mp4"), 0o600); err != nil {
		t.Fatal(err)
	}
	_ = os.WriteFile(filepath.Join(dir, "clip.sample.mkv"), []byte("mkv"), 0o600)
	s, err := storage.Open(filepath.Join(t.TempDir(), "db"))
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	r, err := (Scanner{Store: s, Priority: 50}).Scan(context.Background(), []string{dir}, false)
	if err != nil {
		t.Fatal(err)
	}
	if r.Conflicts != 1 || r.Excluded != 1 {
		t.Fatalf("result=%+v", r)
	}
	xs, _ := s.List(context.Background(), 10)
	if len(xs) != 1 || xs[0].Status != jobs.Skipped || xs[0].Notes != "conflict" {
		t.Fatalf("jobs=%+v", xs)
	}
}
