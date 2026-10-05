package converter

import (
	"strings"
	"testing"

	"github.com/snuffkin/media-converter/internal/probe"
)

func TestPlanCopiesCompatibleAndTranscodesOnlyDTS(t *testing.T) {
	m := probe.Media{Streams: []probe.Stream{{Index: 0, CodecType: "video", CodecName: "h264", PixFmt: "yuv420p"}, {Index: 1, CodecType: "audio", CodecName: "aac"}, {Index: 2, CodecType: "audio", CodecName: "dts"}, {Index: 3, CodecType: "subtitle", CodecName: "subrip"}, {Index: 4, CodecType: "attachment", CodecName: "ttf"}}}
	p, err := Plan(m, false)
	if err != nil {
		t.Fatal(err)
	}
	if p.Operation != "audio_transcode" {
		t.Fatalf("operation=%s", p.Operation)
	}
	if p.Streams[1].Mode != "copy" || p.Streams[2].Mode != "aac" || p.Streams[3].Mode != "mov_text" {
		t.Fatalf("unexpected plan: %#v", p)
	}
	if len(p.Omissions) != 1 {
		t.Fatalf("omissions=%v", p.Omissions)
	}
	args := strings.Join(Args("in.mkv", "out.mp4", p), " ")
	for _, want := range []string{"-map 0:0", "-c:a:0 copy", "-c:a:1 aac", "-c:s:0 mov_text", "-progress pipe:1"} {
		if !strings.Contains(args, want) {
			t.Errorf("args missing %q: %s", want, args)
		}
	}
}

func TestPlanUnsupportedSDRVideoEncodesCompatibleMP4(t *testing.T) {
	p, err := Plan(probe.Media{Streams: []probe.Stream{{CodecType: "video", CodecName: "vp9"}}}, false)
	if err != nil || p.Operation != "video_transcode" {
		t.Fatalf("plan=%+v error=%v", p, err)
	}
	args := strings.Join(Args("in.webm", "out.mp4", p), " ")
	for _, want := range []string{"-c:v:0 libx264", "-crf:v:0 14", "-preset:v:0 slow", "-pix_fmt:v:0 yuv420p"} {
		if !strings.Contains(args, want) {
			t.Errorf("missing %q: %s", want, args)
		}
	}
}

func TestPlanBrowserCodecs(t *testing.T) {
	for _, codec := range []string{"hevc", "av1", "vp9", "mpeg4"} {
		p, err := Plan(probe.Media{Streams: []probe.Stream{{CodecType: "video", CodecName: codec, PixFmt: "yuv420p"}}}, true)
		if err != nil || p.Streams[0].Mode != "libx264" {
			t.Fatalf("%s: %+v %v", codec, p, err)
		}
	}
	for _, codec := range []string{"ac3", "eac3", "alac", "flac", "pcm_s32le", "mp3", "dts"} {
		p, err := Plan(probe.Media{Streams: []probe.Stream{{CodecType: "video", CodecName: "h264", PixFmt: "yuv420p"}, {CodecType: "audio", CodecName: codec, Channels: 6}}}, true)
		if err != nil || p.Streams[1].Mode != "aac" {
			t.Fatalf("%s: %+v %v", codec, p, err)
		}
		if !strings.Contains(strings.Join(Args("in.mkv", "out.mp4", p), " "), "-b:a:0 640k") {
			t.Fatal("multichannel bitrate missing")
		}
	}
}
func TestPlanToneMapsHDR(t *testing.T) {
	for _, transfer := range []string{"smpte2084", "arib-std-b67"} {
		p, err := Plan(probe.Media{Streams: []probe.Stream{{CodecType: "video", CodecName: "hevc", PixFmt: "yuv420p10le", ColorTransfer: transfer}}}, true)
		if err != nil || !p.Streams[0].ToneMap || p.Streams[0].Mode != "libx264" {
			t.Fatalf("%+v %v", p, err)
		}
		args := strings.Join(Args("in.mkv", "out.mp4", p), " ")
		for _, want := range []string{"tonemap=tonemap=mobius", "-color_trc:v:0 bt709", "-color_primaries:v:0 bt709", "-pix_fmt:v:0 yuv420p"} {
			if !strings.Contains(args, want) {
				t.Errorf("missing %s", want)
			}
		}
	}
}
func TestPlanHighBitDepthAndHEAACAreNotCopied(t *testing.T) {
	p, err := Plan(probe.Media{Streams: []probe.Stream{{CodecType: "video", CodecName: "h264", PixFmt: "yuv420p10le"}, {CodecType: "audio", CodecName: "aac", Profile: "HE-AAC"}}}, true)
	if err != nil || p.Streams[0].Mode != "libx264" || p.Streams[1].Mode != "aac" {
		t.Fatalf("%+v %v", p, err)
	}
}

func TestPlanStrictRejectsOmission(t *testing.T) {
	_, err := Plan(probe.Media{Streams: []probe.Stream{{CodecType: "video", CodecName: "hevc"}, {CodecType: "subtitle", CodecName: "hdmv_pgs_subtitle"}}}, true)
	if err == nil {
		t.Fatal("expected strict-mode error")
	}
}

func TestValidationRejectsNonBrowserOrIncompleteOutput(t *testing.T) {
	plan := ConversionPlan{Streams: []StreamAction{{Type: "video", Mode: "libx264"}, {Type: "audio", Mode: "aac", Channels: 6}}}
	good := probe.Media{Streams: []probe.Stream{{CodecType: "video", CodecName: "h264", PixFmt: "yuv420p"}, {CodecType: "audio", CodecName: "aac", Profile: "LC", Channels: 6}}}
	if err := ValidateStreams(plan, good); err != nil {
		t.Fatal(err)
	}
	for _, mutation := range []func(*probe.Media){
		func(m *probe.Media) { m.Streams[0].PixFmt = "yuv420p10le" },
		func(m *probe.Media) { m.Streams[0].PixFmt = "" },
		func(m *probe.Media) { m.Streams[0].ColorTransfer = "smpte2084" },
		func(m *probe.Media) { m.Streams[1].Channels = 2 },
		func(m *probe.Media) { m.Streams[1].Profile = "HE-AAC" },
	} {
		bad := probe.Media{Streams: append([]probe.Stream(nil), good.Streams...)}
		mutation(&bad)
		if err := ValidateStreams(plan, bad); err == nil {
			t.Fatalf("accepted incompatible output: %+v", bad)
		}
	}
}
