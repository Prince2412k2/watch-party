package worker

import (
	"context"
	"github.com/snuffkin/media-converter/internal/config"
	"github.com/snuffkin/media-converter/internal/hooks"
	"github.com/snuffkin/media-converter/internal/jobs"
	"github.com/snuffkin/media-converter/internal/media"
	"github.com/snuffkin/media-converter/internal/probe"
	"github.com/snuffkin/media-converter/internal/storage"
	"io"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

func TestRealPreconversionAndInPlaceNormalization(t *testing.T) {
	ffmpeg, err := exec.LookPath("ffmpeg")
	if err != nil {
		t.Skip("ffmpeg not installed")
	}
	ffprobe, err := exec.LookPath("ffprobe")
	if err != nil {
		t.Skip("ffprobe not installed")
	}
	for _, extension := range []string{"avi", "mkv", "mp4"} {
		t.Run(extension, func(t *testing.T) {
			dir := t.TempDir()
			source := filepath.Join(dir, "film."+extension)
			audio := "pcm_s16le"
			if extension == "mp4" {
				audio = "aac"
			}
			cmd := exec.Command(ffmpeg, "-v", "error", "-f", "lavfi", "-i", "testsrc=size=128x96:rate=10", "-f", "lavfi", "-i", "sine=frequency=440", "-t", "2", "-c:v", "mpeg4", "-q:v", "3", "-threads", "1", "-c:a", audio, source)
			if output, err := cmd.CombinedOutput(); err != nil {
				t.Fatalf("fixture: %v %s", err, output)
			}
			target, temp, _ := media.Paths(source)
			store, err := storage.Open(filepath.Join(dir, "jobs.db"))
			if err != nil {
				t.Fatal(err)
			}
			defer store.Close()
			st, _ := os.Stat(source)
			ctx := context.Background()
			_, err = store.Add(ctx, jobs.Job{SourcePath: source, TargetPath: target, TempPath: temp, SourceSize: st.Size(), SourceMtime: st.ModTime().UnixNano()})
			if err != nil {
				t.Fatal(err)
			}
			job, err := store.Claim(ctx)
			if err != nil {
				t.Fatal(err)
			}
			pool := New(config.Config{FFmpeg: ffmpeg, FFprobe: ffprobe, Strict: true, DeleteOriginal: true}, store, slog.New(slog.NewTextHandler(io.Discard, nil)), hooks.New(hooks.Config{}))
			pool.process(ctx, job)
			got, _ := store.Get(ctx, job.ID)
			if got.Status != jobs.Completed {
				t.Fatalf("job failed: %+v", got)
			}
			out, err := (probe.Prober{Binary: ffprobe}).Probe(ctx, target)
			if err != nil {
				t.Fatal(err)
			}
			video, _ := out.FirstVideo()
			if video.CodecName != "h264" || video.Width != 128 || video.Height != 96 {
				t.Fatalf("bad output: %+v", out)
			}
			if extension != "mp4" && out.Streams[1].CodecName != "aac" {
				t.Fatal("PCM was not converted to browser-compatible AAC")
			}
			if extension != "mp4" {
				if _, err := os.Stat(source); !os.IsNotExist(err) {
					t.Fatal("validated source was not removed")
				}
			}
		})
	}
}
