package worker

import (
	"context"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"testing"

	"github.com/snuffkin/media-converter/internal/config"
	"github.com/snuffkin/media-converter/internal/hooks"
	"github.com/snuffkin/media-converter/internal/jobs"
	"github.com/snuffkin/media-converter/internal/media"
	"github.com/snuffkin/media-converter/internal/storage"
)

func TestValidatedOutputPublishedBeforeSourceDeletion(t *testing.T) {
	p, store, source, target := integrationPool(t, false)
	j, err := store.Claim(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	p.process(context.Background(), j)
	if _, err := os.Stat(source); !os.IsNotExist(err) {
		t.Fatalf("source should be deleted after validation: %v", err)
	}
	if st, err := os.Stat(target); err != nil || st.Size() < 4096 {
		t.Fatalf("target not published: %v size=%v", err, size(st))
	}
	got, _ := store.Get(context.Background(), j.ID)
	if got.Status != jobs.Completed {
		t.Fatalf("status=%s error=%s", got.Status, got.ErrorMessage)
	}
}

func TestValidationFailureRetainsSource(t *testing.T) {
	p, store, source, target := integrationPool(t, true)
	j, err := store.Claim(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	p.process(context.Background(), j)
	if _, err := os.Stat(source); err != nil {
		t.Fatalf("source was not retained: %v", err)
	}
	if _, err := os.Stat(target); !os.IsNotExist(err) {
		t.Fatalf("target should not exist: %v", err)
	}
	if _, temp, _ := media.Paths(source); temp != "" {
		if _, err := os.Stat(temp); !os.IsNotExist(err) {
			t.Fatalf("temp should be removed: %v", err)
		}
	}
	got, _ := store.Get(context.Background(), j.ID)
	if got.Status != jobs.Failed {
		t.Fatalf("status=%s", got.Status)
	}
}

func integrationPool(t *testing.T, invalidOutput bool) (*Pool, *storage.Store, string, string) {
	t.Helper()
	dir := t.TempDir()
	source := filepath.Join(dir, "movie.mkv")
	target, temp, _ := media.Paths(source)
	if err := os.WriteFile(source, make([]byte, 8192), 0o640); err != nil {
		t.Fatal(err)
	}
	probeScript := `#!/bin/sh
last=""
for arg in "$@"; do last="$arg"; done
case "$last" in
  *.tmp.mp4) `
	if invalidOutput {
		probeScript += `streams='[]'`
	} else {
		probeScript += `streams='[{"index":0,"codec_type":"video","codec_name":"h264","width":1920,"height":1080}]'`
	}
	probeScript += ` ;;
  *) streams='[{"index":0,"codec_type":"video","codec_name":"h264","width":1920,"height":1080}]' ;;
esac
printf '{"streams":%s,"format":{"duration":"10.0","size":"8192"}}\n' "$streams"
`
	ffmpegScript := `#!/bin/sh
last=""
for arg in "$@"; do last="$arg"; done
dd if=/dev/zero of="$last" bs=8192 count=1 2>/dev/null
printf 'out_time_us=10000000\nspeed=10x\ntotal_size=8192\nprogress=end\n'
`
	probePath := filepath.Join(dir, "ffprobe")
	ffmpegPath := filepath.Join(dir, "ffmpeg")
	if err := os.WriteFile(probePath, []byte(probeScript), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(ffmpegPath, []byte(ffmpegScript), 0o755); err != nil {
		t.Fatal(err)
	}
	store, err := storage.Open(filepath.Join(dir, "jobs.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = store.Close() })
	if ok, err := store.Add(context.Background(), jobs.Job{SourcePath: source, TargetPath: target, TempPath: temp, Priority: 50, SourceSize: 8192}); err != nil || !ok {
		t.Fatalf("add=%v err=%v", ok, err)
	}
	cfg := config.Config{FFmpeg: ffmpegPath, FFprobe: probePath, DeleteOriginal: true, MinFreeSpaceGB: 0}
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	notifier := hooks.New(hooks.Config{})
	return New(cfg, store, logger, notifier), store, source, target
}

func size(st os.FileInfo) int64 {
	if st == nil {
		return 0
	}
	return st.Size()
}
