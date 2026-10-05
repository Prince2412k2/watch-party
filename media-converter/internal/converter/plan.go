package converter

import (
	"fmt"
	"strings"

	"github.com/snuffkin/media-converter/internal/probe"
)

type StreamAction struct {
	InputIndex                  int
	Type, Codec, Mode, Language string
	Default, Forced             bool
	Channels                    int
	ToneMap                     bool
}
type ConversionPlan struct {
	Operation string
	Streams   []StreamAction
	Omissions []string
}

func Plan(m probe.Media, strict bool) (ConversionPlan, error) {
	p := ConversionPlan{Operation: "remux"}
	videos := 0
	audioTranscode := false
	videoTranscode := false
	for _, s := range m.Streams {
		a := StreamAction{InputIndex: s.Index, Type: s.CodecType, Codec: s.CodecName, Language: s.Tags.Language, Default: s.Disposition.Default == 1, Forced: s.Disposition.Forced == 1, Channels: s.Channels}
		switch s.CodecType {
		case "video":
			videos++
			a.Mode = "copy"
			// Only 8-bit 4:2:0 AVC is portable across our browser targets.
			a.ToneMap = oneOf(s.ColorTransfer, "smpte2084", "arib-std-b67")
			compatible := s.CodecName == "h264" && oneOf(s.PixFmt, "yuv420p", "yuvj420p") && !a.ToneMap
			if !compatible {
				a.Mode = "libx264"
				videoTranscode = true
			}
			p.Streams = append(p.Streams, a)
		case "audio":
			if s.CodecName == "aac" && (s.Profile == "" || s.Profile == "LC") {
				a.Mode = "copy"
			} else {
				a.Mode = "aac"
				audioTranscode = true
			}
			p.Streams = append(p.Streams, a)
		case "subtitle":
			if s.CodecName == "mov_text" {
				a.Mode = "copy"
				p.Streams = append(p.Streams, a)
			} else if oneOf(s.CodecName, "subrip", "ass", "ssa", "webvtt", "text") {
				a.Mode = "mov_text"
				p.Streams = append(p.Streams, a)
			} else {
				p.Omissions = append(p.Omissions, fmt.Sprintf("subtitle #%d (%s)", s.Index, s.CodecName))
			}
		case "attachment", "data":
			p.Omissions = append(p.Omissions, fmt.Sprintf("%s #%d (%s)", s.CodecType, s.Index, s.CodecName))
		}
	}
	if videos == 0 {
		return p, fmt.Errorf("input has no video stream")
	}
	if strict && len(p.Omissions) > 0 {
		return p, fmt.Errorf("strict mode rejects omitted streams: %s", strings.Join(p.Omissions, ", "))
	}
	if audioTranscode {
		p.Operation = "audio_transcode"
	}
	if videoTranscode {
		p.Operation = "video_transcode"
	}
	return p, nil
}
func oneOf(v string, xs ...string) bool {
	for _, x := range xs {
		if v == x {
			return true
		}
	}
	return false
}

// Validate every mapped stream before permitting source deletion, not only the
// first video. A missing audio track or unexpected codec is a failed output.
func ValidateStreams(plan ConversionPlan, out probe.Media) error {
	if len(plan.Streams) != len(out.Streams) {
		return fmt.Errorf("stream count changed: expected %d, got %d", len(plan.Streams), len(out.Streams))
	}
	for i, action := range plan.Streams {
		codec := action.Mode
		if codec == "copy" {
			codec = action.Codec
		}
		if codec == "libx264" {
			codec = "h264"
		}
		if out.Streams[i].CodecType != action.Type || out.Streams[i].CodecName != codec {
			return fmt.Errorf("stream %d expected %s/%s, got %s/%s", i, action.Type, codec, out.Streams[i].CodecType, out.Streams[i].CodecName)
		}
		if action.Type == "video" {
			stream := out.Streams[i]
			if !oneOf(stream.PixFmt, "yuv420p", "yuvj420p") {
				return fmt.Errorf("stream %d has incompatible pixel format %s", i, stream.PixFmt)
			}
			if oneOf(stream.ColorTransfer, "smpte2084", "arib-std-b67") {
				return fmt.Errorf("stream %d is still HDR after conversion", i)
			}
		}
		if action.Type == "audio" {
			stream := out.Streams[i]
			if stream.Profile != "" && stream.Profile != "LC" {
				return fmt.Errorf("stream %d has incompatible AAC profile %s", i, stream.Profile)
			}
			if action.Channels > 0 && stream.Channels != action.Channels {
				return fmt.Errorf("stream %d audio channel count changed: %d -> %d", i, action.Channels, stream.Channels)
			}
		}
	}
	return nil
}

func Args(input, output string, p ConversionPlan) []string {
	a := []string{"-hide_banner", "-nostdin", "-y", "-i", input}
	for _, s := range p.Streams {
		a = append(a, "-map", fmt.Sprintf("0:%d", s.InputIndex))
	}
	a = append(a, "-map_metadata", "0", "-map_chapters", "0", "-c", "copy")
	ai, si, vi := 0, 0, 0
	for _, s := range p.Streams {
		switch s.Type {
		case "video":
			a = append(a, fmt.Sprintf("-c:v:%d", vi), s.Mode)
			if s.Mode == "libx264" {
				a = append(a, fmt.Sprintf("-preset:v:%d", vi), "slow", fmt.Sprintf("-crf:v:%d", vi), "14", fmt.Sprintf("-pix_fmt:v:%d", vi), "yuv420p")
			}
			if s.ToneMap {
				a = append(a, fmt.Sprintf("-filter:v:%d", vi), "zscale=transfer=linear:npl=100,format=gbrpf32le,zscale=primaries=bt709,tonemap=tonemap=mobius:desat=0,zscale=transfer=bt709:matrix=bt709:range=limited:dither=error_diffusion,format=yuv420p",
					fmt.Sprintf("-x264-params:v:%d", vi), "colorprim=bt709:transfer=bt709:colormatrix=bt709", fmt.Sprintf("-color_primaries:v:%d", vi), "bt709", fmt.Sprintf("-color_trc:v:%d", vi), "bt709", fmt.Sprintf("-colorspace:v:%d", vi), "bt709", fmt.Sprintf("-color_range:v:%d", vi), "tv")
			}
			vi++
		case "audio":
			a = append(a, fmt.Sprintf("-c:a:%d", ai), s.Mode)
			if s.Mode == "aac" {
				bitrate := "320k"
				if s.Channels > 2 {
					bitrate = "640k"
				}
				a = append(a, fmt.Sprintf("-b:a:%d", ai), bitrate, fmt.Sprintf("-profile:a:%d", ai), "aac_low")
			}
			if s.Language != "" {
				a = append(a, fmt.Sprintf("-metadata:s:a:%d", ai), "language="+s.Language)
			}
			a = append(a, fmt.Sprintf("-disposition:a:%d", ai), disposition(s))
			ai++
		case "subtitle":
			a = append(a, fmt.Sprintf("-c:s:%d", si), s.Mode)
			if s.Language != "" {
				a = append(a, fmt.Sprintf("-metadata:s:s:%d", si), "language="+s.Language)
			}
			a = append(a, fmt.Sprintf("-disposition:s:%d", si), disposition(s))
			si++
		}
	}
	return append(a, "-movflags", "+faststart", "-progress", "pipe:1", "-loglevel", "warning", output)
}

func disposition(s StreamAction) string {
	if s.Default && s.Forced {
		return "default+forced"
	}
	if s.Default {
		return "default"
	}
	if s.Forced {
		return "forced"
	}
	return "0"
}
