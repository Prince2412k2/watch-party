package media

import "testing"

func TestPaths(t *testing.T) {
	target, temp, err := Paths("/movies/Dune/movie.mkv")
	if err != nil {
		t.Fatal(err)
	}
	if target != "/movies/Dune/movie.mp4" {
		t.Fatalf("target=%q", target)
	}
	if temp != "/movies/Dune/.movie.media-converter.tmp.mp4" {
		t.Fatalf("temp=%q", temp)
	}
}

func TestPathsNeverConvertsItsOwnOutputs(t *testing.T) {
	for _, path := range []string{".movie.media-converter.tmp.mp4", "subtitle.srt", ".partial.mkv"} {
		if _, _, err := Paths(path); err == nil {
			t.Fatalf("accepted %s", path)
		}
	}
	for _, path := range []string{"movie.avi", "movie.webm", "movie.MKV", "movie.mp4"} {
		target, _, err := Paths(path)
		if err != nil || target != "movie.mp4" {
			t.Fatalf("path=%s target=%s err=%v", path, target, err)
		}
	}
}
