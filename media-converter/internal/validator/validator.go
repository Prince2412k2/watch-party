package validator

import (
	"context"
	"fmt"
	"math"
	"os"
	"os/exec"

	"github.com/snuffkin/media-converter/internal/probe"
)

func Validate(ctx context.Context, prober probe.Prober, ffmpeg, output string, source probe.Media, copiedVideo, deep bool) (probe.Media, error) {
	st, err := os.Stat(output)
	if err != nil {
		return probe.Media{}, err
	}
	if st.Size() < 4096 {
		return probe.Media{}, fmt.Errorf("output is unreasonably small: %d bytes", st.Size())
	}
	out, err := prober.Probe(ctx, output)
	if err != nil {
		return out, err
	}
	sv, sok := source.FirstVideo()
	ov, ook := out.FirstVideo()
	if !ook {
		return out, fmt.Errorf("output has no video stream")
	}
	if !sok {
		return out, fmt.Errorf("source has no video stream")
	}
	if !DurationMatches(source.Duration(), out.Duration()) {
		return out, fmt.Errorf("duration mismatch: source %.2fs output %.2fs", source.Duration(), out.Duration())
	}
	if sv.Width != ov.Width || sv.Height != ov.Height {
		return out, fmt.Errorf("resolution mismatch: %dx%d -> %dx%d", sv.Width, sv.Height, ov.Width, ov.Height)
	}
	if copiedVideo && sv.CodecName != ov.CodecName {
		return out, fmt.Errorf("video codec changed: %s -> %s", sv.CodecName, ov.CodecName)
	}
	if deep {
		if b, e := exec.CommandContext(ctx, ffmpeg, "-v", "error", "-i", output, "-f", "null", "-").CombinedOutput(); e != nil {
			return out, fmt.Errorf("deep validation failed: %w: %s", e, string(b))
		}
	}
	return out, nil
}

func DurationMatches(source, output float64) bool {
	if source <= 0 {
		return true
	}
	return math.Abs(source-output) <= math.Max(2, source*0.01)
}
