package scanner

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

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
	if len(xs) != 2 || xs[0].SourcePath != filepath.Join(dir, "movie.mp4") || xs[0].Status != jobs.Queued || xs[1].Status != jobs.Skipped || xs[1].Notes != "conflict" {
		t.Fatalf("jobs=%+v", xs)
	}
}

func TestWatcherQueuesAddedAndModifiedSettledFiles(t *testing.T) {
	dir := t.TempDir()
	store, err := storage.Open(filepath.Join(t.TempDir(), "db"))
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		defer close(done)
		(Scanner{Store: store, SettleTime: 20 * time.Millisecond}).Watch(ctx, []string{dir}, 10*time.Millisecond, func(_ Result, _ error) {})
	}()
	defer func() { cancel(); <-done }()
	source := filepath.Join(dir, "new.avi")
	if err := os.WriteFile(source, []byte("first"), 0600); err != nil {
		t.Fatal(err)
	}
	waitQueued := func() jobs.Job {
		deadline := time.Now().Add(3 * time.Second)
		for time.Now().Before(deadline) {
			list, _ := store.List(ctx, 10)
			if len(list) == 1 && list[0].Status == jobs.Queued {
				return list[0]
			}
			time.Sleep(10 * time.Millisecond)
		}
		t.Fatal("watcher did not queue input")
		return jobs.Job{}
	}
	first := waitQueued()
	_ = store.UpdateState(ctx, first.ID, jobs.Failed, "", "old input failed", "", "")
	if err := os.WriteFile(source, []byte("second version"), 0600); err != nil {
		t.Fatal(err)
	}
	second := waitQueued()
	if second.ID != first.ID || second.SourceSize != int64(len("second version")) || second.ErrorMessage != "" {
		t.Fatalf("modification did not refresh job: %+v", second)
	}
}
