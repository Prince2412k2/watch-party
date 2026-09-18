package tui

import (
	"fmt"
	"path/filepath"
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/snuffkin/media-converter/internal/config"
	"github.com/snuffkin/media-converter/internal/jobs"
)

func TestTVHierarchyUsesNaturalSeasonAndEpisodeOrder(t *testing.T) {
	cfg := config.Config{MoviesDir: "/media/movies", TVDir: "/media/tv"}
	paths := []string{
		"/media/tv/Example Show/Season 10/Example.Show.S10E01.mkv",
		"/media/tv/Example Show/Season 2/Example.Show.S02E10.mkv",
		"/media/tv/Example Show/Season 1/Example.Show.S01E02.mkv",
		"/media/tv/Example Show/Season 2/Example.Show.S02E02.mkv",
		"/media/tv/Example Show/Season 2/Example.Show.S02E01.mkv",
	}
	items := make([]jobs.Job, len(paths))
	for i, path := range paths {
		items[i] = jobs.Job{ID: int64(i + 1), SourcePath: path, Status: jobs.Queued}
	}
	m := Model{cfg: cfg, items: items, records: buildRecords(items, cfg.MoviesDir, cfg.TVDir), tab: tabLibrary, level: levelSeasons, group: "Example Show"}
	if got := titles(m.rows()); got != "Season 1,Season 2,Season 10" {
		t.Fatalf("season order: %s", got)
	}
	m.level = levelEpisodes
	m.season = "Season 2"
	if got := titles(m.rows()); got != "Example.Show.S02E01,Example.Show.S02E02,Example.Show.S02E10" {
		t.Fatalf("episode order: %s", got)
	}
}

func TestMoviesGroupByMovieDirectory(t *testing.T) {
	items := []jobs.Job{{SourcePath: "/media/movies/Dune (2021)/Dune.2021.mkv"}, {SourcePath: "/media/movies/Alien (1979)/Alien.mkv"}}
	m := Model{cfg: config.Config{MoviesDir: "/media/movies", TVDir: "/media/tv"}, items: items, records: buildRecords(items, "/media/movies", "/media/tv"), level: levelMovies}
	if got := titles(m.rows()); got != "Alien (1979),Dune (2021)" {
		t.Fatalf("movie order: %s", got)
	}
}

func TestNarrowViewportScrollsAndStaysWithinWidth(t *testing.T) {
	items := make([]jobs.Job, 30)
	for i := range items {
		items[i] = jobs.Job{ID: int64(i + 1), SourcePath: filepath.Join("/media/tv/Show/Season 1", fmt.Sprintf("Show.S01E%02d.mkv", i+1)), Status: jobs.Queued, Priority: 50}
	}
	m := Model{cfg: config.Config{MoviesDir: "/media/movies", TVDir: "/media/tv"}, items: items, records: buildRecords(items, "/media/movies", "/media/tv"), tab: tabLibrary, level: levelEpisodes, group: "Show", season: "Season 1", width: 40, height: 16}
	for range 12 {
		next, _ := m.Update(tea.KeyMsg{Type: tea.KeyDown})
		m = next.(Model)
	}
	if m.offset == 0 {
		t.Fatal("viewport did not scroll")
	}
	if m.cursor != 12 {
		t.Fatalf("cursor=%d", m.cursor)
	}
	rendered := strings.Split(m.View(), "\n")
	if len(rendered) > m.height {
		t.Fatalf("rendered %d lines into %d-row terminal", len(rendered), m.height)
	}
	for _, line := range rendered {
		if width := lipgloss.Width(line); width > 40 {
			t.Fatalf("line width %d exceeds terminal: %q", width, line)
		}
	}
}

func TestNarrowActiveJobAndDetailsStayScrollable(t *testing.T) {
	item := jobs.Job{ID: 7, SourcePath: "/media/tv/A Very Long Show Name/Season 1/A.Very.Long.Show.Name.S01E01.mkv", Status: jobs.Remuxing, OperationType: "audio_transcode", Priority: 50, Progress: 42, FFmpegSpeed: "4.2x", Duration: 3600, SourceSize: 3 << 30, TargetSize: 1 << 30, VideoCodec: "h264", AudioCodecs: "dts,aac", SubtitleCodecs: "subrip,hdmv_pgs_subtitle", ErrorMessage: strings.Repeat("validation detail ", 8)}
	m := Model{items: []jobs.Job{item}, detailID: item.ID, level: levelDetail, width: 32, height: 12}
	before := m.offset
	next, _ := m.Update(tea.KeyMsg{Type: tea.KeyPgDown})
	m = next.(Model)
	if m.offset <= before {
		t.Fatal("detail page did not scroll")
	}
	rendered := strings.Split(m.View(), "\n")
	if len(rendered) > m.height {
		t.Fatalf("rendered %d lines into %d-row terminal", len(rendered), m.height)
	}
	for _, line := range rendered {
		if width := lipgloss.Width(line); width > 32 {
			t.Fatalf("line width %d exceeds terminal: %q", width, line)
		}
	}
}

func TestQueueSelectionAndFocusedReorderIDs(t *testing.T) {
	items := []jobs.Job{{ID: 1, SourcePath: "/media/tv/Show/Season 1/E01.mkv", Status: jobs.Queued}, {ID: 2, SourcePath: "/media/tv/Show/Season 1/E02.mkv", Status: jobs.Queued}, {ID: 3, SourcePath: "/media/tv/Show/Season 1/E03.mkv", Status: jobs.Queued}}
	m := Model{items: items, tab: tabQueue, selected: map[int64]bool{}, width: 40, height: 16}
	if got := m.reorderIDs(); len(got) != 1 || got[0] != 1 {
		t.Fatalf("focused reorder ids=%v", got)
	}
	m.toggleSelection()
	m.move(1)
	m.toggleSelection()
	got := m.reorderIDs()
	if len(got) != 2 || got[0] != 1 || got[1] != 2 {
		t.Fatalf("selected reorder ids=%v", got)
	}
	view := m.View()
	if !strings.Contains(view, "[✓]") {
		t.Fatalf("selected marker missing:\n%s", view)
	}
}

func titles(rows []row) string {
	out := make([]string, len(rows))
	for i, row := range rows {
		out[i] = row.title
	}
	return strings.Join(out, ",")
}
