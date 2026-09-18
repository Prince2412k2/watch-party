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

func TestPlanUnsupportedVideoRequiresTranscode(t *testing.T) {
	_, err := Plan(probe.Media{Streams: []probe.Stream{{CodecType: "video", CodecName: "vp9"}}}, false)
	if err == nil || !strings.Contains(err.Error(), "requires transcoding") {
		t.Fatalf("error=%v", err)
	}
}

func TestPlanStrictRejectsOmission(t *testing.T) {
	_, err := Plan(probe.Media{Streams: []probe.Stream{{CodecType: "video", CodecName: "hevc"}, {CodecType: "subtitle", CodecName: "hdmv_pgs_subtitle"}}}, true)
	if err == nil {
		t.Fatal("expected strict-mode error")
	}
}
