package converter

import (
	"strings"
	"testing"

	"github.com/snuffkin/media-converter/internal/probe"
)

func TestPlanCopiesCompatibleAndTranscodesOnlyDTS(t *testing.T) {
	m := probe.Media{Streams: []probe.Stream{{Index: 0, CodecType: "video", CodecName: "h264"}, {Index: 1, CodecType: "audio", CodecName: "aac"}, {Index: 2, CodecType: "audio", CodecName: "dts"}, {Index: 3, CodecType: "subtitle", CodecName: "subrip"}, {Index: 4, CodecType: "attachment", CodecName: "ttf"}}}
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
	for _, want := range []string{"-c:v:0 libx264", "-crf:v:0 18", "-preset:v:0 veryfast", "-pix_fmt:v:0 yuv420p"} {
		if !strings.Contains(args, want) {
			t.Errorf("missing %q: %s", want, args)
		}
	}
}

func TestPlanPreservesHEVCHDRAndLosslessAudio(t *testing.T) {
	p, err := Plan(probe.Media{Streams: []probe.Stream{{CodecType: "video", CodecName: "hevc", ColorTransfer: "smpte2084"}, {CodecType: "audio", CodecName: "flac"}}}, true)
	if err != nil || p.Streams[0].Mode != "copy" || p.Streams[1].Mode != "alac" {
		t.Fatalf("plan=%+v err=%v", p, err)
	}
	if !strings.Contains(strings.Join(Args("in.mkv", "out.mp4", p), " "), "-tag:v:0 hvc1") {
		t.Fatal("HEVC must be tagged for Apple playback")
	}
}

func TestPlanDoesNotSilentlyReencodeUnsupportedHDR(t *testing.T) {
	_, err := Plan(probe.Media{Streams: []probe.Stream{{CodecType: "video", CodecName: "av1", ColorTransfer: "smpte2084"}}}, true)
	if err == nil {
		t.Fatal("HDR conversion needs an explicit tone-map policy")
	}
}

func TestPlanDoesNotTruncate32BitLosslessAudio(t *testing.T) {
	_, err := Plan(probe.Media{Streams: []probe.Stream{{CodecType: "video", CodecName: "h264"}, {CodecType: "audio", CodecName: "pcm_s32le"}}}, true)
	if err == nil {
		t.Fatal("32-bit source must not silently become 24-bit ALAC")
	}
}

func TestPlanStrictRejectsOmission(t *testing.T) {
	_, err := Plan(probe.Media{Streams: []probe.Stream{{CodecType: "video", CodecName: "hevc"}, {CodecType: "subtitle", CodecName: "hdmv_pgs_subtitle"}}}, true)
	if err == nil {
		t.Fatal("expected strict-mode error")
	}
}
