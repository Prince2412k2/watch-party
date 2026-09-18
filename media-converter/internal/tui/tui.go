package tui

import (
	"context"
	"fmt"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"github.com/snuffkin/media-converter/internal/config"
	"github.com/snuffkin/media-converter/internal/jobs"
	"github.com/snuffkin/media-converter/internal/scanner"
	"github.com/snuffkin/media-converter/internal/storage"
)

type tick time.Time
type loaded struct {
	jobs   []jobs.Job
	paused bool
	err    error
}
type actionErr error
type Model struct {
	store                  *storage.Store
	cfg                    config.Config
	scanner                scanner.Scanner
	items                  []jobs.Job
	cursor, width, height  int
	paused, dry, inputMode bool
	input                  textinput.Model
	message                string
}

var (
	accent     = lipgloss.Color("#D6FF5F")
	muted      = lipgloss.Color("#78808F")
	danger     = lipgloss.Color("#FF6B6B")
	panel      = lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).BorderForeground(lipgloss.Color("#3B4352")).Padding(0, 1)
	titleStyle = lipgloss.NewStyle().Bold(true).Foreground(accent)
	mutedStyle = lipgloss.NewStyle().Foreground(muted)
)

func New(s *storage.Store, c config.Config) Model {
	in := textinput.New()
	in.Placeholder = "file or directory path"
	in.CharLimit = 1024
	return Model{store: s, cfg: c, scanner: scanner.Scanner{Store: s, Priority: c.Priority, Excludes: c.ExcludePatterns, IncludeSamples: c.IncludeSamples}, input: in}
}
func Run(s *storage.Store, c config.Config) error {
	_, e := tea.NewProgram(New(s, c), tea.WithAltScreen()).Run()
	return e
}
func (m Model) Init() tea.Cmd { return tea.Batch(m.load(), nextTick()) }
func nextTick() tea.Cmd       { return tea.Tick(time.Second, func(t time.Time) tea.Msg { return tick(t) }) }
func (m Model) load() tea.Cmd {
	return func() tea.Msg {
		xs, e := m.store.List(context.Background(), 300)
		return loaded{jobs: xs, paused: m.store.Paused(context.Background()), err: e}
	}
}
func (m Model) scanCmd(paths []string) tea.Cmd {
	return func() tea.Msg {
		r, e := m.scanner.Scan(context.Background(), paths, m.dry)
		if e != nil {
			return actionErr(e)
		}
		return actionErr(fmt.Errorf("scan: %d found, %d added, %d conflicts", r.Found, r.Added, r.Conflicts))
	}
}
func (m Model) selected() (jobs.Job, bool) {
	if m.cursor >= 0 && m.cursor < len(m.items) {
		return m.items[m.cursor], true
	}
	return jobs.Job{}, false
}
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	if m.inputMode {
		switch x := msg.(type) {
		case tea.KeyMsg:
			switch x.String() {
			case "esc":
				m.inputMode = false
				m.input.Blur()
				return m, nil
			case "enter":
				path := strings.TrimSpace(m.input.Value())
				m.inputMode = false
				m.input.Blur()
				m.input.SetValue("")
				if path != "" {
					return m, m.scanCmd([]string{path})
				}
			}
		}
		var cmd tea.Cmd
		m.input, cmd = m.input.Update(msg)
		return m, cmd
	}
	switch x := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = x.Width
		m.height = x.Height
	case tick:
		return m, tea.Batch(m.load(), nextTick())
	case loaded:
		m.items = x.jobs
		m.paused = x.paused
		if x.err != nil {
			m.message = x.err.Error()
		}
		if m.cursor >= len(m.items) {
			m.cursor = max(0, len(m.items)-1)
		}
	case actionErr:
		m.message = x.Error()
		return m, m.load()
	case tea.KeyMsg:
		switch x.String() {
		case "q", "ctrl+c":
			return m, tea.Quit
		case "up", "k":
			if m.cursor > 0 {
				m.cursor--
			}
		case "down", "j":
			if m.cursor < len(m.items)-1 {
				m.cursor++
			}
		case "s":
			return m, m.scanCmd([]string{m.cfg.MoviesDir, m.cfg.TVDir})
		case "a":
			m.inputMode = true
			m.input.Focus()
			return m, textinput.Blink
		case "d":
			m.dry = !m.dry
			m.message = fmt.Sprintf("manual dry-run: %t", m.dry)
		case "p":
			m.paused = !m.paused
			_ = m.store.SetPaused(context.Background(), m.paused)
		case "c":
			if j, ok := m.selected(); ok {
				_ = m.store.Cancel(context.Background(), j.ID)
			}
		case "r":
			if j, ok := m.selected(); ok {
				_ = m.store.Retry(context.Background(), j.ID)
			}
		case "+", "=":
			if j, ok := m.selected(); ok {
				_ = m.store.Priority(context.Background(), j.ID, max(0, j.Priority-10))
			}
		case "-":
			if j, ok := m.selected(); ok {
				_ = m.store.Priority(context.Background(), j.ID, j.Priority+10)
			}
		}
	}
	return m, nil
}
func (m Model) View() string {
	w := m.width
	if w < 72 {
		w = 72
	}
	state := "RUNNING"
	if m.paused {
		state = "PAUSED"
	}
	header := titleStyle.Render("MEDIA CONVERTER") + "  " + mutedStyle.Render("SAFE REMUX QUEUE") + strings.Repeat(" ", max(1, w-45-len(state))) + state
	active := "No active conversion"
	for _, j := range m.items {
		if j.Status == jobs.Remuxing || j.Status == jobs.TranscodingAudio || j.Status == jobs.Validating || j.Status == jobs.Probing {
			barw := max(10, min(42, w-28))
			filled := int(j.Progress / 100 * float64(barw))
			bar := lipgloss.NewStyle().Foreground(accent).Render(strings.Repeat("█", filled)) + mutedStyle.Render(strings.Repeat("░", barw-filled))
			active = fmt.Sprintf("%s\n%s\n%-18s %s %5.1f%%  %s  ETA %s\n%s → %s", filepath.Base(j.SourcePath), mutedStyle.Render(j.SourcePath), strings.ToUpper(j.OperationType), bar, j.Progress, j.FFmpegSpeed, eta(j), formatBytes(j.SourceSize), formatBytes(j.TargetSize))
			break
		}
	}
	activeBox := panel.Width(w - 4).Render(titleStyle.Render("ACTIVE JOB") + "\n\n" + active)
	rows := []string{titleStyle.Render(fmt.Sprintf("%-5s %-5s %-20s %-16s %s", "ID", "PRI", "STATUS", "OPERATION", "SOURCE"))}
	maxRows := max(4, m.height-14)
	for i, j := range m.items {
		if i >= maxRows {
			break
		}
		mark := " "
		style := lipgloss.NewStyle()
		if i == m.cursor {
			mark = "›"
			style = style.Foreground(accent)
		}
		status := j.Status
		if j.ErrorMessage != "" && (j.Status == jobs.Failed || j.Status == jobs.Skipped) {
			status = lipgloss.NewStyle().Foreground(danger).Render(status)
		}
		row := fmt.Sprintf("%s %-4d P%-4d %-20s %-16s %s", mark, j.ID, j.Priority, status, j.OperationType, filepath.Base(j.SourcePath))
		rows = append(rows, style.Render(truncate(row, w-8)))
	}
	queue := panel.Width(w - 4).Render(strings.Join(rows, "\n"))
	help := "q quit  s scan  a add path  p pause/resume  +/- priority  c cancel  r retry  d dry-run"
	if m.inputMode {
		help = "ADD  " + m.input.View() + "   enter queue  esc cancel"
	}
	footer := mutedStyle.Render(help)
	if m.message != "" {
		footer += "\n" + truncate(m.message, w-2)
	}
	return header + "\n" + activeBox + "\n" + queue + "\n" + footer
}
func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	if n < 2 {
		return s[:n]
	}
	return s[:n-1] + "…"
}
func eta(j jobs.Job) string {
	speed, err := strconv.ParseFloat(strings.TrimSuffix(j.FFmpegSpeed, "x"), 64)
	if err != nil || speed <= 0 || j.Duration <= 0 {
		return "--:--"
	}
	seconds := j.Duration * (1 - j.Progress/100) / speed
	return (time.Duration(seconds) * time.Second).Round(time.Second).String()
}
func formatBytes(n int64) string {
	if n <= 0 {
		return "--"
	}
	units := []string{"B", "KB", "MB", "GB", "TB"}
	value := float64(n)
	i := 0
	for value >= 1024 && i < len(units)-1 {
		value /= 1024
		i++
	}
	return fmt.Sprintf("%.1f %s", value, units[i])
}
