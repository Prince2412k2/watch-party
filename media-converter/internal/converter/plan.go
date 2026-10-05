package converter

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/snuffkin/media-converter/internal/probe"
)

type StreamAction struct {
	InputIndex                  int
	Type, Codec, Mode, Language string
	Default, Forced             bool
	Channels                    int
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
			// Keep HEVC (including HDR) bit-for-bit. AVC High 10 and other
			// video codecs need a compatible 8-bit AVC rendition for iOS.
			compatible := (s.CodecName == "h264" && (s.PixFmt == "" || oneOf(s.PixFmt, "yuv420p", "yuvj420p"))) || (s.CodecName == "hevc" && (s.PixFmt == "" || oneOf(s.PixFmt, "yuv420p", "yuv420p10le")))
			if !compatible {
				if oneOf(s.ColorTransfer, "smpte2084", "arib-std-b67") {
					return p, fmt.Errorf("HDR %s requires a tone-mapping policy; source preserved", s.CodecName)
				}
				a.Mode = "libx264"
				videoTranscode = true
			}
			p.Streams = append(p.Streams, a)
		case "audio":
			bits, _ := strconv.Atoi(s.BitsPerRawSample)
			if s.CodecName == "pcm_s32le" || (s.CodecName == "flac" && bits > 24) {
				return p, fmt.Errorf("audio #%d exceeds ALAC's 24-bit preservation policy; source preserved", s.Index)
			}
			if oneOf(s.CodecName, "aac", "ac3", "eac3", "alac", "mp3") {
				a.Mode = "copy"
			} else if oneOf(s.CodecName, "flac", "pcm_s16le", "pcm_s24le") {
				a.Mode = "alac" // Preserve lossless audio losslessly in MP4.
				audioTranscode = true
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
				a = append(a, fmt.Sprintf("-preset:v:%d", vi), "veryfast", fmt.Sprintf("-crf:v:%d", vi), "18", fmt.Sprintf("-pix_fmt:v:%d", vi), "yuv420p")
			} else if s.Codec == "hevc" {
				a = append(a, fmt.Sprintf("-tag:v:%d", vi), "hvc1")
			}
			vi++
		case "audio":
			a = append(a, fmt.Sprintf("-c:a:%d", ai), s.Mode)
			if s.Mode == "aac" {
				bitrate := "256k"
				if s.Channels > 2 {
					bitrate = "512k"
				}
				a = append(a, fmt.Sprintf("-b:a:%d", ai), bitrate)
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
