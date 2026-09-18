package probe

import (
	"encoding/json"
	"testing"
)

func TestFFprobeJSONMapping(t *testing.T) {
	data := []byte(`{"streams":[{"index":2,"codec_type":"video","codec_name":"hevc","width":3840,"height":2160,"tags":{"language":"eng"},"disposition":{"default":1,"forced":0}}],"format":{"duration":"12.5","size":"1234"}}`)
	var media Media
	if err := json.Unmarshal(data, &media); err != nil {
		t.Fatal(err)
	}
	if len(media.Streams) != 1 {
		t.Fatalf("streams=%d", len(media.Streams))
	}
	s := media.Streams[0]
	if s.Index != 2 || s.CodecType != "video" || s.CodecName != "hevc" || s.Width != 3840 || s.Tags.Language != "eng" || s.Disposition.Default != 1 {
		t.Fatalf("stream=%+v", s)
	}
	if media.Duration() != 12.5 {
		t.Fatalf("duration=%v", media.Duration())
	}
}
