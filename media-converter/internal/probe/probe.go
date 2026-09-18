package probe

import (
	"context"
	"encoding/json"
	"fmt"
	"os/exec"
	"strconv"
)

type Disposition struct {
	Default int `json:"default"`
	Forced  int `json:"forced"`
}
type Tags struct {
	Language string `json:"language"`
	Title    string `json:"title"`
}
type Stream struct {
	Index                int `json:"index"`
	CodecType, CodecName string
	Width, Height        int
	Channels             int
	ChannelLayout        string `json:"channel_layout"`
	Tags                 Tags
	Disposition          Disposition
}

func (s *Stream) UnmarshalJSON(b []byte) error {
	type raw Stream
	var x struct {
		raw
		CodecType string `json:"codec_type"`
		CodecName string `json:"codec_name"`
	}
	if err := json.Unmarshal(b, &x); err != nil {
		return err
	}
	*s = Stream(x.raw)
	s.CodecType = x.CodecType
	s.CodecName = x.CodecName
	return nil
}

type Format struct {
	Duration string `json:"duration"`
	Size     string `json:"size"`
}
type Media struct {
	Streams []Stream `json:"streams"`
	Format  Format   `json:"format"`
}

func (m Media) Duration() float64 { v, _ := strconv.ParseFloat(m.Format.Duration, 64); return v }

type Prober struct{ Binary string }

func (p Prober) Probe(ctx context.Context, path string) (Media, error) {
	cmd := exec.CommandContext(ctx, p.Binary, "-v", "error", "-show_format", "-show_streams", "-of", "json", path)
	b, err := cmd.Output()
	if err != nil {
		return Media{}, fmt.Errorf("ffprobe %s: %w", path, err)
	}
	var m Media
	if err = json.Unmarshal(b, &m); err != nil {
		return Media{}, fmt.Errorf("parse ffprobe output: %w", err)
	}
	return m, nil
}
func (m Media) FirstVideo() (Stream, bool) {
	for _, s := range m.Streams {
		if s.CodecType == "video" {
			return s, true
		}
	}
	return Stream{}, false
}
