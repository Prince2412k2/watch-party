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

func TestPathsRejectsNonMKV(t *testing.T) {
	if _, _, err := Paths("movie.avi"); err == nil {
		t.Fatal("expected error")
	}
}
