package converter

import (
	"context"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/snuffkin/media-converter/internal/probe"
)

func TestRealBrowserOutputs(t *testing.T) {
	ffmpeg, err := exec.LookPath("ffmpeg")
	if err != nil {
		t.Skip("ffmpeg not installed")
	}
	ffprobe, err := exec.LookPath("ffprobe")
	if err != nil {
		t.Skip("ffprobe not installed")
	}
	run := func(args ...string) []byte {
		t.Helper()
		output, err := exec.Command(ffmpeg, args...).CombinedOutput()
		if err != nil {
			t.Fatalf("ffmpeg: %v\n%s", err, output)
		}
		return output
	}
	for _, kind := range []string{"copy", "sdr", "pq", "hlg"} {
		t.Run(kind, func(t *testing.T) {
			dir := t.TempDir()
			input, output := filepath.Join(dir, "input.mkv"), filepath.Join(dir, "output.mp4")
			args := []string{"-v", "error", "-f", "lavfi", "-i", "testsrc2=size=128x96:rate=24", "-f", "lavfi", "-i", "sine=frequency=440", "-t", "1", "-threads", "1"}
			switch kind {
			case "copy":
				args = append(args, "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac")
			case "sdr":
				args = append(args, "-c:v", "mpeg4", "-c:a", "flac")
			default:
				transfer := "smpte2084"
				if kind == "hlg" {
					transfer = "arib-std-b67"
				}
				args = append(args, "-c:v", "libx264", "-pix_fmt", "yuv420p10le", "-x264-params", "colorprim=bt2020:transfer="+transfer+":colormatrix=bt2020nc", "-color_trc", transfer, "-color_primaries", "bt2020", "-colorspace", "bt2020nc", "-c:a", "flac")
			}
			run(append(args, input)...)
			prober := probe.Prober{Binary: ffprobe}
			source, err := prober.Probe(context.Background(), input)
			if err != nil {
				t.Fatal(err)
			}
			if kind == "pq" || kind == "hlg" {
				video, _ := source.FirstVideo()
				if !oneOf(video.ColorTransfer, "smpte2084", "arib-std-b67") {
					t.Fatalf("fixture lacks HDR metadata: %+v", video)
				}
			}
			plan, err := Plan(source, true)
			if err != nil {
				t.Fatal(err)
			}
			run(Args(input, output, plan)...)
			converted, err := prober.Probe(context.Background(), output)
			if err != nil {
				t.Fatal(err)
			}
			if err := ValidateStreams(plan, converted); err != nil {
				t.Fatal(err)
			}
			video, _ := converted.FirstVideo()
			if video.CodecName != "h264" || video.PixFmt != "yuv420p" || video.Width != 128 || video.Height != 96 || converted.Streams[1].CodecName != "aac" {
				t.Fatalf("bad output: %+v", converted)
			}
			if kind == "pq" || kind == "hlg" {
				if video.ColorTransfer != "bt709" {
					t.Fatalf("not SDR: %+v", video)
				}
			}
			run("-v", "error", "-i", output, "-f", "null", "-")
			if kind == "copy" {
				hash := func(path string) string {
					return string(run("-v", "error", "-i", path, "-map", "0:v:0", "-c", "copy", "-f", "hash", "-"))
				}
				if strings.TrimSpace(hash(input)) != strings.TrimSpace(hash(output)) {
					t.Fatal("compatible video changed")
				}
			}
		})
	}
}
