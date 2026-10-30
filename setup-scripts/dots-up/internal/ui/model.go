package ui

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"charm.land/bubbles/v2/viewport"
	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
	"github.com/charmbracelet/x/ansi"
)

var (
	accent = lipgloss.NewStyle().Foreground(lipgloss.Color("#8BE9FD")).Bold(true)
	muted  = lipgloss.NewStyle().Foreground(lipgloss.Color("#8892A0"))
	good   = lipgloss.NewStyle().Foreground(lipgloss.Color("#89D185"))
	warn   = lipgloss.NewStyle().Foreground(lipgloss.Color("#F7C66F"))
	bad    = lipgloss.NewStyle().Foreground(lipgloss.Color("#F48A8A"))
	focus  = lipgloss.NewStyle().Foreground(lipgloss.Color("#D7E5FF")).Bold(true)
)

type Change struct{ Item, Before, After string }
type Stage struct {
	ID, Group, Label, Terminal, Status, Summary, Action, LogPath string
	Changes                                                      []Change
}

type Model struct {
	RunID, Profile, Host                                                     string
	Stages                                                                   []Stage
	Notices                                                                  []Event
	Selected                                                                 int
	CurrentMain                                                              int
	AppStoreIndex                                                            int
	Width, Height                                                            int
	ExitCode                                                                 int
	DurationMS                                                               int64
	Running, Finished, ShowLog, RawLog, Help, DetailFocus, NoWait, Searching bool
	SearchQuery                                                              string
	AppliedSearch                                                            string
	StartedAt                                                                time.Time
	Elapsed                                                                  time.Duration
	CancelRequested                                                          bool
	TerminalRequested                                                        bool
	intents                                                                  chan string
	StateDir                                                                 string
	viewport                                                                 viewport.Model
	lastLog                                                                  string
	lastLogStage                                                             string
}

func NewModel(stateDir string, noWait bool) Model {
	vp := viewport.New(viewport.WithWidth(80), viewport.WithHeight(12))
	vp.SoftWrap = true
	return Model{StateDir: stateDir, NoWait: noWait, Width: 100, Height: 30, CurrentMain: -1, AppStoreIndex: -1, viewport: vp}
}

func (m Model) Init() tea.Cmd { return tick() }

type tickMsg time.Time

func tick() tea.Cmd {
	return tea.Tick(350*time.Millisecond, func(t time.Time) tea.Msg { return tickMsg(t) })
}

func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch v := msg.(type) {
	case Event:
		m.apply(v)
		if v.Kind == "run_end" && (m.NoWait || m.CancelRequested) {
			return m, tea.Quit
		}
		return m, nil
	case tea.WindowSizeMsg:
		m.Width, m.Height = max(1, v.Width), max(1, v.Height)
		m.resize()
	case tea.KeyPressMsg:
		if m.Searching {
			switch v.String() {
			case "enter":
				m.Searching = false
				m.AppliedSearch = m.SearchQuery
				m.refreshDetail()
			case "esc":
				m.Searching = false
				m.SearchQuery = m.AppliedSearch
				m.refreshDetail()
			case "backspace":
				runes := []rune(m.SearchQuery)
				if len(runes) > 0 {
					m.SearchQuery = string(runes[:len(runes)-1])
				}
			default:
				if v.Text != "" {
					m.SearchQuery += v.Text
				}
			}
			return m, nil
		}
		switch v.String() {
		case "q":
			if m.Finished {
				return m, tea.Quit
			}
		case "ctrl+c":
			if m.Finished {
				return m, tea.Quit
			}
			if !m.CancelRequested {
				m.CancelRequested = true
				if m.intents != nil {
					select {
					case m.intents <- "cancel":
					default:
					}
				}
			}
		case "enter":
			m.DetailFocus = true
			m.ShowLog = false
			m.refreshDetail()
		case "esc":
			m.DetailFocus, m.ShowLog, m.RawLog = false, false, false
			m.refreshDetail()
		case "up", "k":
			if m.DetailFocus || m.RawLog {
				m.viewport.ScrollUp(1)
			} else if m.Selected > 0 {
				m.Selected--
				m.refreshDetail()
			}
		case "down", "j":
			if m.DetailFocus || m.RawLog {
				m.viewport.ScrollDown(1)
			} else if m.Selected+1 < len(m.Stages) {
				m.Selected++
				m.refreshDetail()
			}
		case "pgup":
			m.viewport.HalfPageUp()
		case "pgdown":
			m.viewport.HalfPageDown()
		case "tab":
			m.DetailFocus = !m.DetailFocus
			if !m.DetailFocus {
				m.ShowLog = false
			}
			m.refreshDetail()
		case "a":
			if m.AppStoreIndex >= 0 {
				m.Selected = m.AppStoreIndex
				m.ShowLog = true
				m.DetailFocus = true
				m.RawLog = false
				m.refreshDetail()
			}
		case "l":
			m.RawLog = false
			m.ShowLog = !m.ShowLog
			m.DetailFocus = m.ShowLog
			m.refreshDetail()
		case "t":
			if m.Running {
				if !m.TerminalRequested {
					m.TerminalRequested = true
					if m.intents != nil {
						select {
						case m.intents <- "terminal_request":
						default:
						}
					}
				}
				break
			}
			fallthrough
		case "r":
			m.RawLog = !m.RawLog
			m.ShowLog = m.RawLog
			m.DetailFocus = m.RawLog
			m.refreshDetail()
		case "s", "/":
			m.ShowLog = true
			m.DetailFocus = true
			m.Searching = true
			m.SearchQuery = ""
			m.AppliedSearch = ""
			m.refreshDetail()
		case "?":
			m.Help = !m.Help
		}
	case tickMsg:
		if m.Running && !m.StartedAt.IsZero() {
			m.Elapsed = time.Since(m.StartedAt)
		}
		if m.ShowLog && m.Selected < len(m.Stages) {
			m.refreshDetail()
		}
		return m, tick()
	}
	return m, nil
}

func (m *Model) apply(e Event) {
	e.Label, e.Group, e.Summary, e.Action = cleanLine(e.Label), cleanLine(e.Group), cleanLine(e.Summary), cleanLine(e.Action)
	e.Item, e.Before, e.After = cleanLine(e.Item), cleanLine(e.Before), cleanLine(e.After)
	switch e.Kind {
	case "run_start":
		m.RunID, m.Profile, m.Host, m.Running = e.ID, e.Profile, e.Host, true
		m.StartedAt = time.Now()
	case "stage_start":
		m.Stages = append(m.Stages, Stage{ID: e.ID, Group: e.Group, Label: e.Label, Terminal: e.Terminal, Status: "running", LogPath: safeLogPath(m.StateDir, e.LogPath)})
		m.Selected = len(m.Stages) - 1
		m.CurrentMain = m.Selected
	case "app_store_start":
		status := e.Status
		if status == "" {
			status = "running"
		}
		m.Stages = append(m.Stages, Stage{ID: e.ID, Group: e.Group, Label: e.Label, Status: status, LogPath: safeLogPath(m.StateDir, e.LogPath)})
		m.AppStoreIndex = len(m.Stages) - 1
		if m.CurrentMain < 0 {
			m.Selected = m.AppStoreIndex
		}
	case "app_store_end":
		if i := m.stageIndex(e.ID); i >= 0 {
			s := &m.Stages[i]
			s.Status, s.Summary, s.Action = e.Status, e.Summary, e.Action
			if p := safeLogPath(m.StateDir, e.LogPath); p != "" {
				s.LogPath = p
			}
		}
	case "stage_end":
		if i := m.stageIndex(e.ID); i >= 0 {
			s := &m.Stages[i]
			s.Status, s.Summary, s.Action = e.Status, e.Summary, e.Action
			if p := safeLogPath(m.StateDir, e.LogPath); p != "" {
				s.LogPath = p
			}
		}
	case "change":
		if i := m.stageIndex(e.Stage); i >= 0 {
			m.Stages[i].Changes = append(m.Stages[i].Changes, Change{e.Item, e.Before, e.After})
		}
	case "notice":
		m.Notices = append(m.Notices, e)
	case "terminal_end":
		m.TerminalRequested = false
	case "run_end":
		m.Running, m.Finished, m.ExitCode, m.DurationMS = false, true, e.ExitCode, e.DurationMS
		if e.DurationMS > 0 {
			m.Elapsed = time.Duration(e.DurationMS) * time.Millisecond
		}
	}
	m.resize()
	m.refreshDetail()
}

func (m Model) stageIndex(id string) int {
	for i := range m.Stages {
		if m.Stages[i].ID == id {
			return i
		}
	}
	return -1
}

func safeLogPath(root, path string) string {
	if root == "" || !filepath.IsAbs(path) {
		return ""
	}
	rel, err := filepath.Rel(root, path)
	if err != nil || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {
		return ""
	}
	return path
}

func cleanLine(s string) string { return strings.Join(strings.Fields(sanitizeLog(s)), " ") }

func sanitizeLog(s string) string {
	s = ansi.Strip(s)
	return strings.Map(func(r rune) rune {
		if r == '\r' {
			return '\n'
		}
		if r < 32 && r != '\n' && r != '\t' {
			return -1
		}
		if r == 127 {
			return -1
		}
		return r
	}, s)
}

func readTail(path string) string {
	f, err := os.Open(path)
	if err != nil {
		return "Log unavailable yet."
	}
	defer f.Close()
	stat, err := f.Stat()
	if err != nil {
		return "Log unavailable yet."
	}
	const limit int64 = 128 * 1024
	start := max(int64(0), stat.Size()-limit)
	if _, err := f.Seek(start, 0); err != nil {
		return "Log unavailable yet."
	}
	body, err := io.ReadAll(io.LimitReader(f, limit))
	if err != nil {
		return "Log unavailable yet."
	}
	text := sanitizeLog(string(body))
	if start > 0 {
		if i := strings.IndexByte(text, '\n'); i >= 0 {
			text = text[i+1:]
		}
		text = "… earlier output omitted …\n" + text
	}
	if text == "" {
		return "Waiting for output…"
	}
	return text
}

// Search scans the complete stage log while keeping the rendered result bounded.
func searchLog(path, query string) string {
	f, err := os.Open(path)
	if err != nil {
		return "Log unavailable yet."
	}
	defer f.Close()
	scanner := bufio.NewScanner(f)
	scanner.Buffer(make([]byte, 64*1024), 4*1024*1024)
	var matches []string
	count := 0
	for scanner.Scan() {
		line := sanitizeLog(scanner.Text())
		if strings.Contains(strings.ToLower(line), strings.ToLower(query)) {
			count++
			if len(matches) < 200 {
				matches = append(matches, line)
			}
		}
	}
	if err := scanner.Err(); err != nil {
		return fmt.Sprintf("Log search stopped: %v", err)
	}
	if count == 0 {
		return fmt.Sprintf("No matches for %q", query)
	}
	if count > len(matches) {
		matches = append(matches, "… additional matches omitted …")
	}
	return fmt.Sprintf("%d matches for %q\n\n%s", count, query, strings.Join(matches, "\n"))
}

func (m Model) overview() bool { return !m.DetailFocus && !m.ShowLog && !m.RawLog }

type issue struct {
	text, action string
	notice       bool
}

func (m Model) issues() []issue {
	var result []issue
	seen := make(map[string]bool)
	for _, s := range m.Stages {
		if s.Status != "attention" && s.Status != "failed" {
			continue
		}
		prefix := "!"
		if s.Status == "failed" {
			prefix = "×"
		}
		text := s.Label
		if s.Summary != "" {
			text += " — " + s.Summary
		}
		result = append(result, issue{text: prefix + " " + text, action: s.Action})
		if s.Summary != "" {
			seen[strings.ToLower(s.Summary)] = true
		}
	}
	for _, n := range m.Notices {
		if n.Severity != "attention" && n.Severity != "error" {
			continue
		}
		key := strings.ToLower(n.Summary)
		if seen[key] {
			continue
		}
		if n.Stage != "" {
			if i := m.stageIndex(n.Stage); i >= 0 && (m.Stages[i].Status == "attention" || m.Stages[i].Status == "failed") {
				continue
			}
		}
		seen[key] = true
		prefix := "!"
		if n.Severity == "error" {
			prefix = "×"
		}
		result = append(result, issue{text: prefix + " " + n.Summary, action: n.Action, notice: true})
	}
	return result
}

func (m Model) overviewContent() string {
	var b strings.Builder
	issues := m.issues()
	fmt.Fprintf(&b, "NEEDS ATTENTION  %d\n", len(issues))
	if len(issues) == 0 {
		b.WriteString("  None\n")
	}
	for _, item := range issues {
		b.WriteString(item.text + "\n")
		if item.action != "" {
			b.WriteString("    Next: " + item.action + "\n")
		}
	}
	changes := 0
	for _, stage := range m.Stages {
		changes += len(stage.Changes)
	}
	fmt.Fprintf(&b, "\nCHANGES  %d\n", changes)
	if changes == 0 {
		b.WriteString("  No verified changes yet.\n")
	}
	for _, stage := range m.Stages {
		for _, c := range stage.Changes {
			fmt.Fprintf(&b, "  %s · %s  %s → %s\n", stage.Label, c.Item, c.Before, c.After)
		}
	}
	return strings.TrimRight(b.String(), "\n")
}

func (m *Model) refreshDetail() {
	content := m.overviewContent()
	if !m.overview() {
		content = "Select a stage to see details."
		if m.Selected < len(m.Stages) {
			s := m.Stages[m.Selected]
			if m.ShowLog {
				if s.LogPath != "" {
					if m.AppliedSearch != "" {
						content = searchLog(s.LogPath, m.AppliedSearch)
					} else {
						content = readTail(s.LogPath)
					}
				} else {
					content = "Log path will be available when this stage completes."
				}
			} else {
				var b strings.Builder
				fmt.Fprintf(&b, "%s  ·  %s\n\n", s.Group, s.Label)
				if s.Summary != "" {
					fmt.Fprintf(&b, "%s\n", s.Summary)
				}
				if s.Action != "" {
					fmt.Fprintf(&b, "Next: %s\n", s.Action)
				}
				for _, c := range s.Changes {
					fmt.Fprintf(&b, "\n%s  %s → %s", c.Item, c.Before, c.After)
				}
				if s.Summary == "" && len(s.Changes) == 0 {
					b.WriteString("Working…")
				}
				content = b.String()
			}
		}
	}
	if content != m.lastLog || m.lastLogStage != fmt.Sprint(m.Selected, m.ShowLog, m.RawLog, m.DetailFocus, m.AppliedSearch) {
		m.viewport.SetContent(content)
		m.viewport.GotoTop()
		m.lastLog = content
		m.lastLogStage = fmt.Sprint(m.Selected, m.ShowLog, m.RawLog, m.DetailFocus, m.AppliedSearch)
	}
	m.resize()
}

func (m *Model) resize() {
	m.viewport.SetWidth(max(1, m.Width-4))
	available := m.Height - 16
	if m.AppStoreIndex >= 0 {
		available--
	}
	if m.RawLog {
		available = m.Height - 5
	}
	if m.overview() {
		available++
	}
	lines := strings.Count(m.lastLog, "\n") + 1
	m.viewport.SetHeight(max(1, min(available, lines)))
}

func statusGlyph(s string) string {
	switch s {
	case "ok":
		return good.Render("✓")
	case "attention":
		return warn.Render("!")
	case "failed":
		return bad.Render("×")
	case "skipped":
		return muted.Render("–")
	default:
		return accent.Render("◉")
	}
}

var groupOrder = []string{
	"Source & settings", "Packages", "Tools", "Managed apps/local builds", "Editor plugins", "Final checks",
}

func (m Model) View() tea.View {
	width := max(1, m.Width)
	issues := m.issues()
	ok, attention, failed := 0, 0, 0
	for _, s := range m.Stages {
		switch s.Status {
		case "ok":
			ok++
		case "attention":
			attention++
		case "failed":
			failed++
		}
	}
	for _, item := range issues {
		if item.notice {
			attention++
		}
	}
	status := "Running"
	if m.Finished {
		if m.ExitCode != 0 || attention > 0 || failed > 0 {
			status = "Needs attention"
		} else {
			status = "Complete"
		}
	}
	if m.Width < 55 || m.Height < 18 {
		line := "Waiting for stages…"
		if m.CurrentMain >= 0 {
			line = m.Stages[m.CurrentMain].Label + " · " + m.Stages[m.CurrentMain].Status
		}
		if m.AppStoreIndex >= 0 {
			line += " | App Store: " + m.Stages[m.AppStoreIndex].Status
		}
		clip := func(s string) string {
			r := []rune(s)
			if len(r) > width {
				return string(r[:width])
			}
			return s
		}
		v := tea.NewView(clip("DOTS UP · "+status) + "\n" + clip(line) + "\n" + clip(fmt.Sprintf("%d attention · %d failed · %d changes", attention, failed, m.changeCount())) + "\n" + clip("Resize for details · q closes when done"))
		v.AltScreen = true
		return v
	}
	var b strings.Builder
	fmt.Fprintf(&b, "%s  %s\n", accent.Render("DOTS  /  UP"), muted.Render(strings.TrimSpace(m.Host+"  "+m.Profile)))
	fmt.Fprintf(&b, "%s  ·  %d complete  ·  %d attention  ·  %d failed  ·  %s\n", status, ok, attention, failed, m.Elapsed.Truncate(time.Second))
	b.WriteString(muted.Render(strings.Repeat("─", max(1, width-2))) + "\n")
	if m.RawLog {
		label := "Captured terminal output"
		if m.Selected < len(m.Stages) {
			label += "  ·  " + m.Stages[m.Selected].Label
		}
		b.WriteString(accent.Render(label) + "\n")
		b.WriteString(m.viewport.View() + "\n")
		b.WriteString(muted.Render("Esc overview  ·  ↑↓ scroll  ·  s search") + "\n")
	} else {
		for _, group := range groupOrder {
			count, completed, problem, active := 0, 0, "", false
			selected := false
			for i, stage := range m.Stages {
				if stage.Group != group {
					continue
				}
				count++
				if stage.Status == "ok" || stage.Status == "skipped" {
					completed++
				}
				if stage.Status == "failed" {
					problem = "failed"
				} else if stage.Status == "attention" && problem != "failed" {
					problem = "attention"
				}
				if stage.Status == "running" {
					active = true
				}
				if i == m.Selected {
					selected = true
				}
			}
			label := "pending"
			glyph := muted.Render("○")
			if problem != "" {
				label = problem
				glyph = warn.Render("!")
				if problem == "failed" {
					glyph = bad.Render("×")
				}
			} else if active {
				label = "running"
				glyph = accent.Render("◉")
			} else if count > 0 && count == completed {
				label = "complete"
				glyph = good.Render("✓")
			}
			line := fmt.Sprintf("%s  %-27s %d/%d  %s", glyph, group, completed, count, label)
			if selected {
				line = focus.Render("› " + line)
			} else {
				line = "  " + line
			}
			b.WriteString(line + "\n")
		}
		b.WriteString(muted.Render(strings.Repeat("─", max(1, width-2))) + "\n")
		if m.CurrentMain >= 0 {
			s := m.Stages[m.CurrentMain]
			fmt.Fprintf(&b, "NOW  %s  %s\n", statusGlyph(s.Status), s.Label)
		} else {
			b.WriteString(muted.Render("NOW  Waiting for main update…") + "\n")
		}
		if m.AppStoreIndex >= 0 {
			s := m.Stages[m.AppStoreIndex]
			fmt.Fprintf(&b, "APP STORE  %s  %s  ·  %s\n", statusGlyph(s.Status), s.Label, s.Status)
		}
		if m.Selected < len(m.Stages) {
			s := m.Stages[m.Selected]
			fmt.Fprintf(&b, "SELECTED  %s  %s\n", statusGlyph(s.Status), s.Label)
		}
		if m.overview() {
			b.WriteString(m.viewport.View() + "\n")
		} else {
			if m.ShowLog {
				b.WriteString(accent.Render("STAGE LOG") + "\n")
			} else {
				b.WriteString(accent.Render("STAGE DETAILS") + "\n")
			}
			b.WriteString(m.viewport.View() + "\n")
		}
		if m.Help {
			b.WriteString("↑↓ stage  Enter details  Esc overview  l logs  t terminal  a App Store  PgUp/Dn scroll  q close\n")
		} else {
			b.WriteString(muted.Render("↑↓ stage  Enter details  l logs  t terminal  a App Store  ? keys") + "\n")
		}
	}
	if m.Searching {
		b.WriteString(accent.Render("Search: "+m.SearchQuery+"▌") + "\n")
	}
	if m.Finished {
		b.WriteString(accent.Render("Finished  ·  q to close") + "\n")
	}
	v := tea.NewView(b.String())
	v.AltScreen = true
	return v
}

func (m Model) changeCount() int {
	count := 0
	for _, stage := range m.Stages {
		count += len(stage.Changes)
	}
	return count
}
