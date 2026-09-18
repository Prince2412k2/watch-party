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
	for _, s := range m.Streams {
		a := StreamAction{InputIndex: s.Index, Type: s.CodecType, Codec: s.CodecName, Language: s.Tags.Language, Default: s.Disposition.Default == 1, Forced: s.Disposition.Forced == 1}
		switch s.CodecType {
		case "video":
			videos++
			if !oneOf(s.CodecName, "h264", "hevc", "av1", "mpeg4") {
				return p, fmt.Errorf("video codec %s requires transcoding", s.CodecName)
			}
			a.Mode = "copy"
			p.Streams = append(p.Streams, a)
		case "audio":
			if oneOf(s.CodecName, "aac", "ac3", "eac3", "alac", "mp3") {
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

func Args(input, output string, p ConversionPlan) []string {
	a := []string{"-hide_banner", "-nostdin", "-y", "-i", input}
	for _, s := range p.Streams {
		a = append(a, "-map", fmt.Sprintf("0:%d", s.InputIndex))
	}
	a = append(a, "-map_metadata", "0", "-map_chapters", "0", "-c", "copy")
	ai, si := 0, 0
	for _, s := range p.Streams {
		switch s.Type {
		case "audio":
			a = append(a, fmt.Sprintf("-c:a:%d", ai), s.Mode)
			if s.Language != "" {
				a = append(a, fmt.Sprintf("-metadata:s:a:%d", ai), "language="+s.Language)
			}
			ai++
		case "subtitle":
			a = append(a, fmt.Sprintf("-c:s:%d", si), s.Mode)
			if s.Language != "" {
				a = append(a, fmt.Sprintf("-metadata:s:s:%d", si), "language="+s.Language)
			}
			if s.Forced {
				a = append(a, fmt.Sprintf("-disposition:s:%d", si), "forced")
			}
			si++
		}
	}
	return append(a, "-movflags", "+faststart", "-progress", "pipe:1", "-loglevel", "warning", output)
}
