package tui

import (
	"context"
	"fmt"
	"path/filepath"
	"sort"
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
type actionResult struct {
	text string
	err  error
}

type viewTab int

const (
	tabLibrary viewTab = iota
	tabQueue
	tabHistory
)

type browseLevel int

const (
	levelRoot browseLevel = iota
	levelMovies
	levelMovieFiles
	levelShows
	levelSeasons
	levelEpisodes
	levelDetail
)

type navState struct {
	level          browseLevel
	group, season  string
	cursor, offset int
	detailID       int64
}
type row struct {
	key, title, meta, status string
	records                  []mediaRecord
	jobID                    int64
	leaf                     bool
}

type Model struct {
	store                            *storage.Store
	cfg                              config.Config
	scanner                          scanner.Scanner
	items                            []jobs.Job
	records                          []mediaRecord
	tab                              viewTab
	level                            browseLevel
	group, season                    string
	detailID                         int64
	stack                            []navState
	selected                         map[int64]bool
	cursor, offset, width, height    int
	paused, dry, inputMode, showHelp bool
	input                            textinput.Model
	message                          string
}

var (
	ink        = lipgloss.Color("#E8EDF2")
	muted      = lipgloss.Color("#738091")
	line       = lipgloss.Color("#27313D")
	accent     = lipgloss.Color("#6EE7D8")
	accentDark = lipgloss.Color("#102F31")
	warn       = lipgloss.Color("#F2C66D")
	danger     = lipgloss.Color("#FF7B7B")
	success    = lipgloss.Color("#80D99B")
	titleStyle = lipgloss.NewStyle().Bold(true).Foreground(ink)
	mutedStyle = lipgloss.NewStyle().Foreground(muted)
)

func New(s *storage.Store, c config.Config) Model {
	in := textinput.New()
	in.Placeholder = "file or directory path"
	in.CharLimit = 1024
	in.Prompt = "> "
	in.PromptStyle = lipgloss.NewStyle().Foreground(accent)
	in.TextStyle = lipgloss.NewStyle().Foreground(ink)
	return Model{store: s, cfg: c, scanner: scanner.Scanner{Store: s, Priority: c.Priority, Excludes: c.ExcludePatterns, IncludeSamples: c.IncludeSamples}, selected: map[int64]bool{}, input: in}
}

func Run(s *storage.Store, c config.Config) error {
	_, err := tea.NewProgram(New(s, c), tea.WithAltScreen(), tea.WithMouseCellMotion()).Run()
	return err
}
func (m Model) Init() tea.Cmd { return tea.Batch(m.load(), nextTick()) }
func nextTick() tea.Cmd       { return tea.Tick(time.Second, func(t time.Time) tea.Msg { return tick(t) }) }
func (m Model) load() tea.Cmd {
	return func() tea.Msg {
		xs, err := m.store.List(context.Background(), 10000)
		return loaded{xs, m.store.Paused(context.Background()), err}
	}
}
func (m Model) scanCmd(paths []string) tea.Cmd {
	dry := m.dry
	return func() tea.Msg {
		r, err := m.scanner.Scan(context.Background(), paths, dry)
		return actionResult{fmt.Sprintf("Scan complete · %d found · %d added · %d conflicts", r.Found, r.Added, r.Conflicts), err}
	}
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	if m.inputMode {
		return m.updateInput(msg)
	}
	switch x := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = x.Width, x.Height
		m.clampSelection()
	case tick:
		return m, tea.Batch(m.load(), nextTick())
	case loaded:
		m.items = x.jobs
		m.records = buildRecords(x.jobs, m.cfg.MoviesDir, m.cfg.TVDir)
		m.paused = x.paused
		m.pruneSelection()
		if x.err != nil {
			m.message = x.err.Error()
		}
		m.clampSelection()
	case actionResult:
		if x.err != nil {
			m.message = x.err.Error()
		} else {
			m.message = x.text
		}
		return m, m.load()
	case tea.MouseMsg:
		switch x.Button {
		case tea.MouseButtonWheelUp:
			m.move(-3)
		case tea.MouseButtonWheelDown:
			m.move(3)
		}
	case tea.KeyMsg:
		key := x.String()
		switch key {
		case "q", "ctrl+c":
			return m, tea.Quit
		case "up", "k":
			m.move(-1)
		case "down", "j":
			m.move(1)
		case "pgup", "ctrl+u":
			m.move(-m.visibleRows())
		case "pgdown", "ctrl+d":
			m.move(m.visibleRows())
		case "home", "g":
			m.cursor = 0
			m.offset = 0
		case "end", "G":
			if m.level == levelDetail {
				m.offset = max(0, len(m.detailLines(max(24, m.width)))-m.detailVisibleRows())
			} else {
				rows := m.rows()
				if len(rows) > 0 {
					m.cursor = len(rows) - 1
				}
				m.ensureVisible()
			}
		case "enter", "right", "l":
			m.open()
		case "left", "h", "backspace", "esc":
			m.back()
		case "tab":
			m.setTab((m.tab + 1) % 3)
		case "shift+tab":
			m.setTab((m.tab + 2) % 3)
		case "1":
			m.setTab(tabLibrary)
		case "2":
			m.setTab(tabQueue)
		case "3":
			m.setTab(tabHistory)
		case "s":
			return m, m.scanCmd([]string{m.cfg.MoviesDir, m.cfg.TVDir})
		case "a":
			m.inputMode = true
			m.input.Focus()
			return m, textinput.Blink
		case "d":
			m.dry = !m.dry
			m.message = fmt.Sprintf("Manual dry-run %s", onOff(m.dry))
		case "p":
			m.paused = !m.paused
			return m, m.settingCmd(m.paused)
		case " ":
			m.toggleSelection()
		case "c":
			return m, m.jobsCmd("cancel", m.selectedJobs())
		case "r":
			return m, m.jobsCmd("retry", m.selectedJobs())
		case "+", "=", "shift+up":
			return m, m.reorderCmd(-1)
		case "-", "shift+down":
			return m, m.reorderCmd(1)
		case "?":
			m.showHelp = !m.showHelp
		}
	}
	return m, nil
}

func (m Model) updateInput(msg tea.Msg) (tea.Model, tea.Cmd) {
	if key, ok := msg.(tea.KeyMsg); ok {
		switch key.String() {
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
			return m, nil
		}
	}
	var cmd tea.Cmd
	m.input, cmd = m.input.Update(msg)
	return m, cmd
}
func (m Model) settingCmd(paused bool) tea.Cmd {
	return func() tea.Msg {
		err := m.store.SetPaused(context.Background(), paused)
		return actionResult{"Worker " + map[bool]string{true: "paused", false: "resumed"}[paused], err}
	}
}
func (m Model) jobsCmd(action string, selected []jobs.Job) tea.Cmd {
	return func() tea.Msg {
		if len(selected) == 0 {
			return actionResult{"Nothing selected", nil}
		}
		changed := 0
		for _, job := range selected {
			var err error
			switch action {
			case "cancel":
				if jobs.Active(job.Status) {
					err = m.store.Cancel(context.Background(), job.ID)
				} else {
					continue
				}
			case "retry":
				if terminalRetry(job.Status) {
					err = m.store.Retry(context.Background(), job.ID)
				} else {
					continue
				}
			}
			if err != nil {
				return actionResult{"", err}
			}
			changed++
		}
		if changed == 0 {
			return actionResult{"No eligible jobs in selection", nil}
		}
		return actionResult{fmt.Sprintf("Updated %d job%s", changed, plural(changed)), nil}
	}
}

func (m Model) reorderCmd(direction int) tea.Cmd {
	ids := m.reorderIDs()
	label := "up"
	if direction > 0 {
		label = "down"
	}
	return func() tea.Msg {
		if len(ids) == 0 {
			return actionResult{"Select a queued item first", nil}
		}
		err := m.store.Reorder(context.Background(), ids, direction)
		return actionResult{fmt.Sprintf("Moved %d job%s %s", len(ids), plural(len(ids)), label), err}
	}
}
func (m *Model) toggleSelection() {
	if m.tab != tabQueue || m.level == levelDetail {
		return
	}
	rows := m.rows()
	if m.cursor < 0 || m.cursor >= len(rows) || rows[m.cursor].status != jobs.Queued {
		return
	}
	if m.selected == nil {
		m.selected = map[int64]bool{}
	}
	id := rows[m.cursor].jobID
	if m.selected[id] {
		delete(m.selected, id)
	} else {
		m.selected[id] = true
	}
}
func (m *Model) pruneSelection() {
	queued := map[int64]bool{}
	for _, job := range m.items {
		if job.Status == jobs.Queued {
			queued[job.ID] = true
		}
	}
	for id := range m.selected {
		if !queued[id] {
			delete(m.selected, id)
		}
	}
}
func (m Model) reorderIDs() []int64 {
	if m.tab != tabQueue {
		return nil
	}
	if len(m.selected) > 0 {
		ids := make([]int64, 0, len(m.selected))
		for _, job := range m.items {
			if job.Status == jobs.Queued && m.selected[job.ID] {
				ids = append(ids, job.ID)
			}
		}
		return ids
	}
	rows := m.rows()
	if m.cursor >= 0 && m.cursor < len(rows) && rows[m.cursor].status == jobs.Queued {
		return []int64{rows[m.cursor].jobID}
	}
	return nil
}

func (m *Model) setTab(tab viewTab) {
	m.tab = tab
	m.level = levelRoot
	m.group = ""
	m.season = ""
	m.detailID = 0
	m.stack = nil
	m.cursor = 0
	m.offset = 0
}
func (m *Model) move(delta int) {
	if m.level == levelDetail {
		maxOffset := max(0, len(m.detailLines(max(24, m.width)))-m.detailVisibleRows())
		m.offset = min(max(0, m.offset+delta), maxOffset)
		return
	}
	rows := m.rows()
	if len(rows) == 0 {
		return
	}
	m.cursor = min(max(0, m.cursor+delta), len(rows)-1)
	m.ensureVisible()
}
func (m *Model) ensureVisible() {
	visible := m.visibleRows()
	if m.cursor < m.offset {
		m.offset = m.cursor
	}
	if m.cursor >= m.offset+visible {
		m.offset = m.cursor - visible + 1
	}
	m.offset = max(0, m.offset)
}
func (m *Model) clampSelection() {
	rows := m.rows()
	if len(rows) == 0 {
		m.cursor = 0
		m.offset = 0
		return
	}
	m.cursor = min(m.cursor, len(rows)-1)
	m.ensureVisible()
}
func (m Model) visibleRows() int {
	reserved := 8
	if m.activeJob() != nil {
		reserved += 3
	}
	if m.showHelp {
		reserved += 5
	}
	if m.message != "" {
		reserved++
	}
	height := max(3, m.height-reserved)
	if m.mobile() {
		height = max(2, height/2)
	}
	return height
}
func (m Model) detailVisibleRows() int {
	reserved := 7
	if m.activeJob() != nil {
		reserved += 3
	}
	if m.message != "" {
		reserved++
	}
	return max(3, m.height-reserved)
}
func (m Model) mobile() bool { return m.width < 64 }

func (m *Model) open() {
	if m.level == levelDetail {
		return
	}
	rows := m.rows()
	if m.cursor < 0 || m.cursor >= len(rows) {
		return
	}
	selected := rows[m.cursor]
	m.stack = append(m.stack, navState{m.level, m.group, m.season, m.cursor, m.offset, m.detailID})
	switch {
	case m.tab != tabLibrary:
		m.level = levelDetail
		m.detailID = selected.jobID
	case m.level == levelRoot && selected.key == "movies":
		m.level = levelMovies
	case m.level == levelRoot && selected.key == "shows":
		m.level = levelShows
	case m.level == levelMovies:
		m.level = levelMovieFiles
		m.group = selected.key
	case m.level == levelShows:
		m.level = levelSeasons
		m.group = selected.key
	case m.level == levelSeasons:
		m.level = levelEpisodes
		m.season = selected.key
	case m.level == levelMovieFiles || m.level == levelEpisodes:
		m.level = levelDetail
		m.detailID = selected.jobID
	default:
		m.stack = m.stack[:len(m.stack)-1]
		return
	}
	m.cursor = 0
	m.offset = 0
}
func (m *Model) back() {
	if len(m.stack) == 0 {
		return
	}
	last := m.stack[len(m.stack)-1]
	m.stack = m.stack[:len(m.stack)-1]
	m.level = last.level
	m.group = last.group
	m.season = last.season
	m.cursor = last.cursor
	m.offset = last.offset
	m.detailID = last.detailID
	m.clampSelection()
}

func (m Model) rows() []row {
	if m.level == levelDetail {
		return nil
	}
	if m.tab == tabQueue {
		return m.jobRows(func(j jobs.Job) bool { return jobs.Active(j.Status) })
	}
	if m.tab == tabHistory {
		return m.jobRows(func(j jobs.Job) bool { return !jobs.Active(j.Status) })
	}
	switch m.level {
	case levelRoot:
		movies := filterRecords(m.records, func(r mediaRecord) bool { return r.kind == kindMovie })
		shows := filterRecords(m.records, func(r mediaRecord) bool { return r.kind == kindTV })
		return []row{{key: "movies", title: "Movies", meta: aggregateMeta(movies), status: "group", records: movies}, {key: "shows", title: "TV Shows", meta: aggregateMeta(shows), status: "group", records: shows}}
	case levelMovies:
		return groupedRows(filterRecords(m.records, func(r mediaRecord) bool { return r.kind == kindMovie }), func(r mediaRecord) string { return r.group })
	case levelShows:
		return groupedRows(filterRecords(m.records, func(r mediaRecord) bool { return r.kind == kindTV }), func(r mediaRecord) string { return r.group })
	case levelSeasons:
		recs := filterRecords(m.records, func(r mediaRecord) bool { return r.kind == kindTV && r.group == m.group })
		rows := groupedRows(recs, func(r mediaRecord) string { return r.season })
		sort.SliceStable(rows, func(i, j int) bool { return seasonOrder(rows[i].records) < seasonOrder(rows[j].records) })
		return rows
	case levelMovieFiles:
		recs := filterRecords(m.records, func(r mediaRecord) bool { return r.kind == kindMovie && r.group == m.group })
		sortRecords(recs)
		return recordRows(recs)
	case levelEpisodes:
		recs := filterRecords(m.records, func(r mediaRecord) bool { return r.kind == kindTV && r.group == m.group && r.season == m.season })
		sortRecords(recs)
		return recordRows(recs)
	}
	return nil
}
func (m Model) jobRows(keep func(jobs.Job) bool) []row {
	var out []row
	for _, job := range m.items {
		if keep(job) {
			out = append(out, row{key: strconv.FormatInt(job.ID, 10), title: trimMediaExtension(filepath.Base(job.SourcePath)), meta: jobMeta(job), status: job.Status, jobID: job.ID, leaf: true})
		}
	}
	return out
}
func groupedRows(records []mediaRecord, key func(mediaRecord) string) []row {
	groups := map[string][]mediaRecord{}
	for _, r := range records {
		groups[key(r)] = append(groups[key(r)], r)
	}
	keys := make([]string, 0, len(groups))
	for k := range groups {
		keys = append(keys, k)
	}
	sort.Slice(keys, func(i, j int) bool { return naturalLess(keys[i], keys[j]) })
	out := make([]row, 0, len(keys))
	for _, k := range keys {
		out = append(out, row{key: k, title: k, meta: aggregateMeta(groups[k]), status: "group", records: groups[k]})
	}
	return out
}
func recordRows(records []mediaRecord) []row {
	out := make([]row, 0, len(records))
	for _, r := range records {
		out = append(out, row{key: strconv.FormatInt(r.job.ID, 10), title: r.title, meta: jobMeta(r.job), status: r.job.Status, records: []mediaRecord{r}, jobID: r.job.ID, leaf: true})
	}
	return out
}
func filterRecords(in []mediaRecord, keep func(mediaRecord) bool) []mediaRecord {
	out := make([]mediaRecord, 0)
	for _, r := range in {
		if keep(r) {
			out = append(out, r)
		}
	}
	return out
}
func seasonOrder(records []mediaRecord) int {
	if len(records) == 0 {
		return 1 << 30
	}
	n := records[0].seasonNumber
	if n == 1<<30 {
		if records[0].season == "Specials" {
			return 1 << 29
		}
		return 1 << 30
	}
	return n
}

func (m Model) selectedJobs() []jobs.Job {
	if m.level == levelDetail {
		if j := m.detailJob(); j != nil {
			return []jobs.Job{*j}
		}
		return nil
	}
	if m.tab == tabQueue && len(m.selected) > 0 {
		out := make([]jobs.Job, 0, len(m.selected))
		for _, job := range m.items {
			if m.selected[job.ID] {
				out = append(out, job)
			}
		}
		return out
	}
	rows := m.rows()
	if m.cursor < 0 || m.cursor >= len(rows) {
		return nil
	}
	if len(rows[m.cursor].records) > 0 {
		out := make([]jobs.Job, 0, len(rows[m.cursor].records))
		for _, r := range rows[m.cursor].records {
			out = append(out, r.job)
		}
		return out
	}
	if rows[m.cursor].jobID != 0 {
		for _, j := range m.items {
			if j.ID == rows[m.cursor].jobID {
				return []jobs.Job{j}
			}
		}
	}
	return nil
}
func (m Model) detailJob() *jobs.Job {
	for i := range m.items {
		if m.items[i].ID == m.detailID {
			return &m.items[i]
		}
	}
	return nil
}
func (m Model) activeJob() *jobs.Job {
	for i := range m.items {
		switch m.items[i].Status {
		case jobs.Probing, jobs.Remuxing, jobs.TranscodingAudio, jobs.TranscodingVideo, jobs.Validating:
			return &m.items[i]
		}
	}
	return nil
}
func (m Model) queuePosition(id int64) int {
	position := 0
	for _, job := range m.items {
		if job.Status != jobs.Queued {
			continue
		}
		position++
		if job.ID == id {
			return position
		}
	}
	return 0
}

func (m Model) View() string {
	w := max(24, m.width)
	if m.height == 0 {
		w = 80
	}
	sections := []string{m.renderHeader(w), m.renderTabs(w)}
	if active := m.activeJob(); active != nil {
		sections = append(sections, m.renderActive(*active, w))
	}
	sections = append(sections, m.renderCrumb(w))
	if m.showHelp {
		sections = append(sections, m.renderHelp(w))
	} else if m.level == levelDetail {
		sections = append(sections, m.renderDetail(w))
	} else {
		sections = append(sections, m.renderList(w))
	}
	sections = append(sections, m.renderFooter(w))
	return strings.Join(sections, "\n")
}
func (m Model) renderHeader(w int) string {
	state := "LIVE"
	color := success
	if m.paused {
		state = "PAUSED"
		color = warn
	}
	brand := "REMUX"
	if !m.mobile() {
		brand += " media worker"
	}
	left := lipgloss.NewStyle().Bold(true).Foreground(accent).Render(brand)
	right := lipgloss.NewStyle().Bold(true).Foreground(color).Render("● " + state)
	return left + strings.Repeat(" ", max(1, w-lipgloss.Width(left)-lipgloss.Width(right))) + right
}
func (m Model) renderTabs(w int) string {
	names := []string{"1 Library", "2 Queue", "3 History"}
	padding := 1
	if m.mobile() {
		names = []string{"1 LIB", "2 QUEUE", "3 HIST"}
		padding = 0
	}
	parts := make([]string, 3)
	for i, name := range names {
		style := lipgloss.NewStyle().Foreground(muted).Padding(0, padding)
		if int(m.tab) == i {
			style = style.Foreground(ink).Background(accentDark).Bold(true)
		}
		parts[i] = style.Render(name)
	}
	return strings.Join(parts, "  ")
}
func (m Model) renderActive(j jobs.Job, w int) string {
	barW := max(8, w-9)
	filled := min(barW, max(0, int(j.Progress/100*float64(barW))))
	bar := lipgloss.NewStyle().Foreground(accent).Render(strings.Repeat("━", filled)) + lipgloss.NewStyle().Foreground(line).Render(strings.Repeat("━", barW-filled))
	name := trimMediaExtension(filepath.Base(j.SourcePath))
	lineOne := lipgloss.NewStyle().Foreground(accent).Bold(true).Render("NOW") + "  " + truncateVisual(name, max(8, w-6))
	lineTwo := bar + fmt.Sprintf(" %5.1f%%", j.Progress)
	lineThree := mutedStyle.Render(truncateVisual(fmt.Sprintf("%s · ETA %s · %s → %s", empty(j.FFmpegSpeed, "--"), eta(j), formatBytes(j.SourceSize), formatBytes(j.TargetSize)), w))
	return lineOne + "\n" + lineTwo + "\n" + lineThree
}
func (m Model) renderCrumb(w int) string {
	crumb := "Library"
	if m.tab == tabQueue {
		crumb = "Queue"
		if len(m.selected) > 0 {
			crumb += fmt.Sprintf(" · %d selected", len(m.selected))
		}
	} else if m.tab == tabHistory {
		crumb = "History"
	} else {
		switch m.level {
		case levelMovies:
			crumb += " / Movies"
		case levelMovieFiles:
			crumb += " / Movies / " + m.group
		case levelShows:
			crumb += " / TV Shows"
		case levelSeasons:
			crumb += " / TV Shows / " + m.group
		case levelEpisodes:
			crumb += " / TV Shows / " + m.group + " / " + m.season
		case levelDetail:
			crumb = m.detailCrumb()
		}
	}
	if m.level == levelDetail && m.tab != tabLibrary {
		crumb = tabName(m.tab) + " / Job"
	}
	return titleStyle.Render(truncateVisual(crumb, w)) + "\n" + lipgloss.NewStyle().Foreground(line).Render(strings.Repeat("─", w))
}
func (m Model) detailCrumb() string {
	if len(m.stack) == 0 {
		return "Library / Job"
	}
	p := m.stack[len(m.stack)-1]
	if p.level == levelEpisodes {
		return "Library / TV Shows / " + p.group + " / " + p.season + " / Episode"
	}
	return "Library / Movies / " + p.group + " / File"
}
func (m Model) renderList(w int) string {
	rows := m.rows()
	if len(rows) == 0 {
		return mutedStyle.Render("Nothing here yet. Press s to scan your libraries.")
	}
	visible := m.visibleRows()
	start := min(m.offset, len(rows))
	end := min(len(rows), start+visible)
	out := make([]string, 0, (end-start)*2)
	for i := start; i < end; i++ {
		out = append(out, m.renderRow(rows[i], i == m.cursor, w))
	}
	if len(rows) > visible {
		out = append(out, mutedStyle.Render(fmt.Sprintf("%d–%d of %d", start+1, end, len(rows))))
	}
	return strings.Join(out, "\n")
}
func (m Model) renderRow(r row, selected bool, w int) string {
	marker := "  "
	if selected {
		marker = "› "
	}
	arrow := "  "
	if !r.leaf {
		arrow = "› "
	}
	status := statusGlyph(r.status)
	choice := ""
	if m.tab == tabQueue {
		choice = "    "
		if r.status == jobs.Queued {
			choice = "[ ] "
			if m.selected[r.jobID] {
				choice = "[✓] "
			}
		}
	}
	if m.mobile() {
		titleW := max(8, w-6-lipgloss.Width(choice))
		first := marker + choice + status + truncateVisual(r.title, titleW)
		second := "    " + truncateVisual(r.meta, max(8, w-7)) + strings.Repeat(" ", max(1, w-6-lipgloss.Width(truncateVisual(r.meta, max(8, w-7))))-lipgloss.Width(arrow)) + arrow
		if selected {
			return lipgloss.NewStyle().Foreground(ink).Background(accentDark).Width(w).Render(first + "\n" + second)
		}
		return first + "\n" + mutedStyle.Render(second)
	}
	metaW := min(42, max(18, w/3))
	titleW := max(12, w-metaW-9-lipgloss.Width(choice))
	text := marker + choice + status + padRight(truncateVisual(r.title, titleW), titleW) + "  " + padRight(truncateVisual(r.meta, metaW), metaW) + arrow
	if selected {
		return lipgloss.NewStyle().Foreground(ink).Background(accentDark).Width(w).Render(text)
	}
	return text
}
func (m Model) renderDetail(w int) string {
	lines := m.detailLines(w)
	start := min(m.offset, max(0, len(lines)-1))
	end := min(len(lines), start+m.detailVisibleRows())
	if start >= end {
		return ""
	}
	return strings.Join(lines[start:end], "\n")
}
func (m Model) detailLines(w int) []string {
	j := m.detailJob()
	if j == nil {
		return []string{mutedStyle.Render("Job no longer exists")}
	}
	label := func(k, v string) string { return mutedStyle.Render(padRight(k, 12)) + truncateVisual(v, max(8, w-13)) }
	lines := []string{lipgloss.NewStyle().Bold(true).Foreground(ink).Render(trimMediaExtension(filepath.Base(j.SourcePath))), "", label("Status", strings.ReplaceAll(j.Status, "_", " ")), label("Operation", empty(j.OperationType, "not planned"))}
	if j.Status == jobs.Queued {
		lines = append(lines, label("Queue order", fmt.Sprintf("#%d", m.queuePosition(j.ID))))
	}
	lines = append(lines, label("Progress", fmt.Sprintf("%.1f%% · %s · ETA %s", j.Progress, empty(j.FFmpegSpeed, "--"), eta(*j))), label("Size", formatBytes(j.SourceSize)+" → "+formatBytes(j.TargetSize)), label("Video", empty(j.VideoCodec, "--")), label("Audio", empty(j.AudioCodecs, "--")), "", mutedStyle.Render(truncateVisual(j.SourcePath, w)))
	if j.ErrorMessage != "" {
		lines = append(lines, "", lipgloss.NewStyle().Foreground(danger).Render(truncateVisual(j.ErrorMessage, w)))
	}
	return lines
}
func (m Model) renderHelp(w int) string {
	help := []string{"NAVIGATE   ↑/↓ or j/k · enter/right open · left/esc back · pgup/pgdn scroll", "VIEWS      tab cycle · 1 library · 2 queue · 3 history", "QUEUE      space select · + move up · - move down", "ACTIONS    s scan · a add path · p pause · c cancel · r retry", "OTHER      d dry-run · ? close help · q quit"}
	if m.mobile() {
		help = []string{"↑↓ move   ↵ open   ← back", "tab views   pgup/pgdn scroll", "space select   +/- reorder", "s scan   a add   p pause", "c cancel   r retry", "? close help   q quit"}
	}
	for i := range help {
		help[i] = truncateVisual(help[i], w)
	}
	return strings.Join(help, "\n")
}
func (m Model) renderFooter(w int) string {
	if m.inputMode {
		return truncateVisual("ADD PATH  "+m.input.View(), w) + "\n" + mutedStyle.Render("enter queue · esc cancel")
	}
	hint := "↑↓ move  ↵ open  ← back  tab views  ? help"
	if m.tab == tabQueue {
		hint = "↑↓ move  space select  + up  - down  ? help"
	}
	if !m.mobile() {
		hint = "↑↓/jk move  enter open  esc back  tab views  s scan  a add  p pause  ? help  q quit"
		if m.tab == tabQueue {
			hint = "↑↓/jk move  space select  + up  - down  c cancel  enter details  ? help"
		}
	}
	footer := mutedStyle.Render(truncateVisual(hint, w))
	if m.message != "" {
		footer += "\n" + lipgloss.NewStyle().Foreground(warn).Render(truncateVisual(m.message, w))
	}
	return footer
}

func aggregateMeta(records []mediaRecord) string {
	if len(records) == 0 {
		return "empty"
	}
	counts := map[string]int{}
	for _, r := range records {
		counts[r.job.Status]++
	}
	parts := []string{fmt.Sprintf("%d file%s", len(records), plural(len(records)))}
	for _, state := range []string{jobs.Remuxing, jobs.TranscodingAudio, jobs.Validating, jobs.Queued, jobs.Failed, jobs.Completed, jobs.Skipped} {
		if n := counts[state]; n > 0 {
			parts = append(parts, fmt.Sprintf("%d %s", n, shortStatus(state)))
		}
	}
	return strings.Join(parts, " · ")
}
func jobMeta(j jobs.Job) string {
	parts := []string{shortStatus(j.Status)}
	if j.OperationType != "" {
		parts = append(parts, strings.ReplaceAll(j.OperationType, "_", " "))
	}
	if j.Progress > 0 && j.Progress < 100 {
		parts = append(parts, fmt.Sprintf("%.0f%%", j.Progress))
	}
	return strings.Join(parts, " · ")
}
func shortStatus(s string) string {
	switch s {
	case jobs.TranscodingAudio:
		return "audio"
	case jobs.RequiresTranscode:
		return "needs transcode"
	}
	return strings.ReplaceAll(s, "_", " ")
}
func statusGlyph(status string) string {
	style := lipgloss.NewStyle().Foreground(muted)
	glyph := "○ "
	switch status {
	case "group":
		glyph = "◇ "
		style = style.Foreground(accent)
	case jobs.Completed:
		glyph = "● "
		style = style.Foreground(success)
	case jobs.Failed, jobs.RequiresTranscode:
		glyph = "! "
		style = style.Foreground(danger)
	case jobs.Remuxing, jobs.TranscodingAudio, jobs.TranscodingVideo, jobs.Validating, jobs.Probing:
		glyph = "◆ "
		style = style.Foreground(accent)
	case jobs.Queued:
		glyph = "◷ "
		style = style.Foreground(warn)
	}
	return style.Render(glyph)
}
func terminalRetry(status string) bool {
	switch status {
	case jobs.Failed, jobs.Cancelled, jobs.Skipped, jobs.RequiresTranscode:
		return true
	}
	return false
}
func tabName(t viewTab) string {
	if t == tabQueue {
		return "Queue"
	}
	if t == tabHistory {
		return "History"
	}
	return "Library"
}
func plural(n int) string {
	if n == 1 {
		return ""
	}
	return "s"
}
func onOff(v bool) string {
	if v {
		return "on"
	}
	return "off"
}
func empty(v, fallback string) string {
	if v == "" {
		return fallback
	}
	return v
}
func padRight(s string, w int) string { return s + strings.Repeat(" ", max(0, w-lipgloss.Width(s))) }
func truncateVisual(s string, w int) string {
	if w <= 0 {
		return ""
	}
	if lipgloss.Width(s) <= w {
		return s
	}
	r := []rune(s)
	for len(r) > 0 && lipgloss.Width(string(r))+1 > w {
		r = r[:len(r)-1]
	}
	return string(r) + "…"
}
func eta(j jobs.Job) string {
	speed, err := strconv.ParseFloat(strings.TrimSuffix(j.FFmpegSpeed, "x"), 64)
	if err != nil || speed <= 0 || j.Duration <= 0 {
		return "--"
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
