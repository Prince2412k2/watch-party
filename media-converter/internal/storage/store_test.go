package storage

import (
	"context"
	"path/filepath"
	"testing"

	"github.com/snuffkin/media-converter/internal/jobs"
)

func testStore(t *testing.T) *Store {
	t.Helper()
	s, err := Open(filepath.Join(t.TempDir(), "test.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = s.Close() })
	return s
}
func add(t *testing.T, s *Store, path string, priority int) {
	t.Helper()
	ok, err := s.Add(context.Background(), jobs.Job{SourcePath: path, TargetPath: path + ".mp4", TempPath: path + ".tmp", Priority: priority})
	if err != nil || !ok {
		t.Fatalf("add: %v %v", ok, err)
	}
}

func TestPriorityClaimOrderingAndDuplicate(t *testing.T) {
	s := testStore(t)
	add(t, s, "normal.mkv", 50)
	add(t, s, "urgent.mkv", 10)
	ok, err := s.Add(context.Background(), jobs.Job{SourcePath: "normal.mkv", TargetPath: "x", TempPath: "y", Priority: 0})
	if err != nil || ok {
		t.Fatalf("duplicate inserted: %v %v", ok, err)
	}
	j, err := s.Claim(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if j.SourcePath != "urgent.mkv" {
		t.Fatalf("claimed %s", j.SourcePath)
	}
}

func TestPriorityChangeTakesEffect(t *testing.T) {
	s := testStore(t)
	add(t, s, "a.mkv", 50)
	add(t, s, "b.mkv", 80)
	xs, _ := s.List(context.Background(), 10)
	var id int64
	for _, j := range xs {
		if j.SourcePath == "b.mkv" {
			id = j.ID
		}
	}
	if err := s.Priority(context.Background(), id, 1); err != nil {
		t.Fatal(err)
	}
	j, err := s.Claim(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if j.SourcePath != "b.mkv" {
		t.Fatalf("claimed %s", j.SourcePath)
	}
}

func TestRestartRecovery(t *testing.T) {
	s := testStore(t)
	add(t, s, "a.mkv", 50)
	j, err := s.Claim(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	_ = s.UpdateState(context.Background(), j.ID, jobs.Remuxing, "remux", "", "", "")
	recovered, err := s.Recover(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if len(recovered) != 1 {
		t.Fatalf("recovered=%d", len(recovered))
	}
	got, _ := s.Get(context.Background(), j.ID)
	if got.Status != jobs.Queued {
		t.Fatalf("status=%s", got.Status)
	}
}
