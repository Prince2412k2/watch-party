package storage

import (
	"context"
	"fmt"
	"github.com/snuffkin/media-converter/internal/jobs"
	"path/filepath"
	"testing"
)

func TestPromoteFifteenthWhileWorkerRuns(t *testing.T) {
	s, err := Open(filepath.Join(t.TempDir(), "jobs.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	ctx := context.Background()
	for i := 1; i <= 20; i++ {
		if _, err := s.Add(ctx, jobs.Job{SourcePath: fmt.Sprintf("%02d.mkv", i), Priority: i}); err != nil {
			t.Fatal(err)
		}
	}
	active, err := s.Claim(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if err := s.MoveToFront(ctx, 15); err != nil {
		t.Fatal(err)
	}
	next, err := s.Claim(ctx)
	if err != nil || next.ID != 15 {
		t.Fatalf("next=%+v err=%v", next, err)
	}
	stillActive, _ := s.Get(ctx, active.ID)
	if stillActive.Status != jobs.Probing {
		t.Fatal("promotion changed active work")
	}
	if err := s.MoveToFront(ctx, active.ID); err == nil {
		t.Fatal("cannot promote running work")
	}
}

func TestModifiedInputRequeuesButUnchangedFailureDoesNot(t *testing.T) {
	s, err := Open(filepath.Join(t.TempDir(), "jobs.db"))
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	ctx := context.Background()
	j := jobs.Job{SourcePath: "movie.mkv", SourceSize: 100, SourceMtime: 1}
	if _, err := s.Add(ctx, j); err != nil {
		t.Fatal(err)
	}
	claimed, _ := s.Claim(ctx)
	_ = s.UpdateState(ctx, claimed.ID, jobs.Failed, "", "bad input", "", "")
	if changed, err := s.Add(ctx, j); changed || err != nil {
		t.Fatalf("unchanged input retried: %v %v", changed, err)
	}
	j.SourceMtime = 2
	if changed, err := s.Add(ctx, j); !changed || err != nil {
		t.Fatalf("modified input not queued: %v %v", changed, err)
	}
	got, _ := s.Get(ctx, claimed.ID)
	if got.Status != jobs.Queued || got.ErrorMessage != "" {
		t.Fatalf("modified state=%+v", got)
	}
}
