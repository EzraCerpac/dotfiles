package supervisor

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
	"github.com/EzraCerpac/dotfiles/setup-scripts/dots-up/internal/commands"
	"github.com/charmbracelet/x/ansi"
)

type savedReport struct {
	report Report
	dir    string
}
type reportBrowser struct {
	rows                    []savedReport
	selected, width, height int
	open                    bool
}

func (m reportBrowser) Init() tea.Cmd { return nil }
func (m reportBrowser) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch v := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = v.Width, v.Height
	case tea.KeyPressMsg:
		switch v.String() {
		case "q", "esc", "ctrl+c":
			return m, tea.Quit
		case "up", "k":
			m.selected = max(0, m.selected-1)
		case "down", "j":
			m.selected = min(len(m.rows)-1, m.selected+1)
		case "enter":
			m.open = true
			return m, tea.Quit
		}
	}
	return m, nil
}
func (m reportBrowser) View() tea.View {
	var b strings.Builder
	b.WriteString(lipgloss.NewStyle().Foreground(lipgloss.Color("#8BE9FD")).Bold(true).Render("DOTS  /  REPORTS") + "\n\n")
	start := max(0, m.selected-max(1, m.height-7)/2)
	end := min(len(m.rows), start+max(1, m.height-7))
	for i := start; i < end; i++ {
		r := m.rows[i]
		mark := "  "
		if i == m.selected {
			mark = "› "
		}
		name := r.report.Command
		if name == "" {
			name = "up"
		}
		line := fmt.Sprintf("%s%-14s %s  exit %d", mark, name, r.report.StartedAt.Local().Format("2006-01-02 15:04:05"), r.report.ExitCode)
		if m.width > 0 && len(line) > m.width {
			line = ansi.Truncate(line, m.width, "")
		}
		if i == m.selected {
			line = lipgloss.NewStyle().Foreground(lipgloss.Color("#D7E5FF")).Bold(true).Render(line)
		}
		b.WriteString(line + "\n")
	}
	b.WriteString("\n↑/↓ select · enter inspect · esc back")
	v := tea.NewView(b.String())
	v.AltScreen = true
	return v
}

func BrowseReports(opts Options) int {
	if len(opts.Args) > 1 {
		fmt.Fprintln(os.Stderr, "Usage: dots reports [COMMAND]")
		return 2
	}
	var names []string
	if len(opts.Args) == 1 {
		name := commands.Canonical(opts.Args[0])
		if _, ok := commands.Lookup(name); !ok || name == "reports" {
			fmt.Fprintln(os.Stderr, "dots: unknown report command")
			return 2
		}
		names = []string{name}
	} else {
		for _, s := range commands.All() {
			if s.Name != "reports" && s.Name != "houseatlas" && s.Name != "plan" {
				names = append(names, s.Name)
			}
		}
	}
	var rows []savedReport
	for _, name := range names {
		root := commandStateDir(name)
		if opts.StateDir != "" && len(names) == 1 {
			root = opts.StateDir
		}
		entries, _ := os.ReadDir(root)
		for _, entry := range entries {
			if !entry.IsDir() {
				continue
			}
			dir := filepath.Join(root, entry.Name())
			if _, err := os.Stat(filepath.Join(dir, ".active")); err == nil {
				continue
			}
			data, err := os.ReadFile(filepath.Join(dir, "report.json"))
			if err != nil {
				continue
			}
			var r Report
			if json.Unmarshal(data, &r) != nil || r.Version != 1 || r.FinishedAt.IsZero() {
				continue
			}
			if r.Command == "" {
				r.Command = name
			}
			rows = append(rows, savedReport{r, dir})
		}
	}
	sort.Slice(rows, func(i, j int) bool { return rows[i].report.StartedAt.After(rows[j].report.StartedAt) })
	if len(rows) == 0 {
		fmt.Println("No completed dots reports are available.")
		return 0
	}
	if !interactiveTerminal() || opts.Plain || opts.Verbose {
		for _, r := range rows {
			fmt.Printf("dots %s · %s · exit %d\n%s\n", r.report.Command, r.report.StartedAt.Local().Format("2006-01-02 15:04:05"), r.report.ExitCode, r.dir)
		}
		return 0
	}
	for {
		tty, err := os.OpenFile("/dev/tty", os.O_RDWR, 0)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		result, err := tea.NewProgram(reportBrowser{rows: rows, height: 30, width: 100}, tea.WithInput(tty), tea.WithOutput(tty)).Run()
		_ = tty.Close()
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		m := result.(reportBrowser)
		if !m.open {
			return 0
		}
		r := rows[m.selected]
		if err := uiRun(replayEvents(r.report), filepath.Dir(r.dir), opts.NoWait, nil); err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
	}
}
