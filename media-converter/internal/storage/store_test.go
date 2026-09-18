package storage

import (
	"context"
	"database/sql"
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

func TestReorderMovesStableSelection(t *testing.T) {
	s := testStore(t)
	for _, name := range []string{"one.mkv", "two.mkv", "three.mkv", "four.mkv", "five.mkv"} {
		add(t, s, name, 50)
	}
	xs, err := s.List(context.Background(), 10)
	if err != nil {
		t.Fatal(err)
	}
	ids := map[string]int64{}
	for _, j := range xs {
		ids[j.SourcePath] = j.ID
	}
	if err = s.Reorder(context.Background(), []int64{ids["two.mkv"], ids["three.mkv"]}, 1); err != nil {
		t.Fatal(err)
	}
	assertQueueOrder(t, s, "one.mkv", "four.mkv", "two.mkv", "three.mkv", "five.mkv")
	if err = s.Reorder(context.Background(), []int64{ids["two.mkv"], ids["three.mkv"]}, -1); err != nil {
		t.Fatal(err)
	}
	assertQueueOrder(t, s, "one.mkv", "two.mkv", "three.mkv", "four.mkv", "five.mkv")
}

func TestMigrationAddsQueueOrderToExistingDatabase(t *testing.T) {
	path := filepath.Join(t.TempDir(), "old.db")
	db, err := sql.Open("sqlite", path)
	if err != nil {
		t.Fatal(err)
	}
	_, err = db.Exec(`CREATE TABLE jobs (id INTEGER PRIMARY KEY, status TEXT NOT NULL, priority INTEGER NOT NULL, created_at DATETIME NOT NULL); INSERT INTO jobs VALUES (7,'queued',50,CURRENT_TIMESTAMP)`)
	if err != nil {
		t.Fatal(err)
	}
	_ = db.Close()
	s, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	var order int
	if err = s.db.QueryRow(`SELECT queue_order FROM jobs WHERE id=7`).Scan(&order); err != nil {
		t.Fatal(err)
	}
	if order != 7 {
		t.Fatalf("queue_order=%d", order)
	}
}

func assertQueueOrder(t *testing.T, s *Store, want ...string) {
	t.Helper()
	xs, err := s.List(context.Background(), len(want))
	if err != nil {
		t.Fatal(err)
	}
	got := make([]string, 0, len(xs))
	for _, j := range xs {
		if j.Status == jobs.Queued {
			got = append(got, j.SourcePath)
		}
	}
	if len(got) != len(want) {
		t.Fatalf("queue length=%d want=%d", len(got), len(want))
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("queue order=%v want=%v", got, want)
		}
	}
}
