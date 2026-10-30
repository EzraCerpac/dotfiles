// Package launcher implements the interactive command chooser. It only returns
// argv; the caller owns execution and any interactive subprocess prompts.
package launcher

import (
	"errors"
	"fmt"
	"os"
	"strings"

	tea "charm.land/bubbletea/v2"
	"charm.land/lipgloss/v2"
	"github.com/charmbracelet/x/ansi"
)

var ErrCancelled = errors.New("menu cancelled")

type item struct {
	name, label, description string
	prefix                   []string
}
type group struct {
	name  string
	items []item
}

var groups = []group{
	{"Inspect", []item{{"status", "Status", "Inspect machine setup", nil}, {"reports", "Reports", "Browse saved reports", nil}, {"last", "Last update report", "Open the saved update report", []string{"up", "--last"}}}},
	{"Maintain", []item{{"up", "Update", "Sync configuration and update tools", nil}, {"sync", "Sync", "Fetch source and apply configuration", nil}, {"apply", "Apply files", "Apply all or selected dotfiles", nil}}},
	{"Software", []item{{"add", "Add", "Install and record software", nil}, {"remove", "Remove", "Remove declarations and optionally uninstall", nil}}},
	{"Settings", []item{{"backup", "Backup", "Publish encrypted settings snapshots", nil}, {"restore", "Restore", "Restore private settings", nil}, {"atuin-login", "Atuin login", "Finish Atuin enrollment", nil}, {"atuin-bundle", "Atuin bundle", "Prepare an encrypted Atuin bundle", nil}}},
	{"Setup", []item{{"bootstrap", "Bootstrap", "Install the full declared setup", nil}, {"remote", "Remote bootstrap", "Bootstrap a machine over SSH", nil}, {"bundle-create", "Create bundle", "Encrypt private bootstrap inputs", []string{"bundle", "create"}}, {"bundle-check", "Check bundle", "Validate an encrypted bundle", []string{"bundle", "check"}}}},
	{"Development", []item{{"test", "Test", "Run repository test suites", nil}, {"publish", "Publish", "Review source and open or update a PR", nil}}},
	{"Advanced", []item{{"plan", "Plan", "Preview the declared setup", nil}, {"houseatlas-check", "HouseAtlas check", "Binding unavailable; no request is sent", []string{"up", "houseatlas", "check"}}, {"houseatlas-apply", "HouseAtlas apply", "Binding unavailable; no request is sent", []string{"up", "houseatlas", "apply"}}, {"houseatlas-status", "HouseAtlas status", "Binding unavailable; no request is sent", []string{"up", "houseatlas", "status"}}}},
}

type field struct {
	label, flag, value, help string
	choices                  []string
	required                 bool
	positional               bool
	multiple                 bool
	values                   []string
}
type form struct {
	item     item
	fields   []field
	advanced []string
	selected int
	editing  bool
	buffer   string
	err      string
}

func text(label, flag, help string, required bool) field {
	return field{label: label, flag: flag, help: help, required: required}
}
func choice(label, flag, help string, choices ...string) field {
	return field{label: label, flag: flag, help: help, choices: choices, value: choices[0]}
}
func positional(label, help string, required bool) field {
	f := text(label, "", help, required)
	f.positional = true
	return f
}
func formFor(it item) form {
	f := form{item: it}
	switch it.name {
	case "up":
		f.fields = []field{choice("Mac App Store", "--mas", "Include App Store updates", "off", "on"), choice("Output", "", "Dashboard is the default", "dashboard", "plain", "verbose"), choice("Close automatically", "--no-wait", "Close when update completes", "off", "on")}
	case "sync":
		f.fields = []field{choice("Source only", "--source-only", "Fetch and advance without applying", "off", "on")}
	case "apply":
		f.fields = []field{positional("Target", "Optional; empty applies all. Add further targets as argument tokens.", false)}
	case "add", "remove":
		f.fields = []field{positional("Tool or package", "One request; add further requests as argument tokens", true), choice("Destination", "", "Default uses the selected profile", "current", "base", "workstation", "nas", "path"), text("Destination path", "--path", "Required only when destination is path", false)}
		f.fields[0].label = "Tools or packages"
		f.fields[0].help = "Enter adds a target; Backspace removes the last"
		f.fields[0].multiple = true
		if it.name == "remove" {
			f.fields[1].help = "Default searches active configurations"
		}
		if it.name == "add" {
			f.fields = append(f.fields, text("GitHub release asset", "--asset", "Optional; requires exactly one GitHub URL", false))
		} else {
			f.fields = append(f.fields, choice("Keep installed", "--keep-installed", "Remove declaration only", "off", "on"), choice("Dry run", "--dry-run", "Preview removal", "off", "on"))
		}
	case "restore":
		f.fields = []field{choice("Initialize history", "--initialize-history", "Preserves an unconnected history store in a sibling backup", "off", "on")}
	case "atuin-login":
		f.fields = []field{choice("Browser login", "--browser", "Use native browser login", "off", "on"), text("Identity path", "--identity", "Optional age identity file path", false)}
	case "atuin-bundle":
		f.fields = []field{text("Recipient", "--recipient", "Public age recipient; add further --recipient tokens below", true)}
	case "bootstrap":
		f.fields = []field{text("Bundle path", "--bundle", "Optional encrypted bootstrap bundle", false), text("Identity path", "--identity", "Optional age identity file path", false), text("Restore machine", "--restore", "Optional machine identity", false)}
	case "remote":
		f.fields = []field{positional("SSH host", "Existing SSH host", true), choice("Profile", "--profile", "Required remote machine role", "choose", "workstation", "nas"), choice("Dry run", "--dry-run", "Preview remote bootstrap", "off", "on"), text("SSH identity file", "--identity-file", "Optional SSH identity path", false), text("SSH port", "--port", "Optional port", false), text("Connect timeout", "--connect-timeout", "Optional timeout", false), text("GitHub relay repository", "--github-relay-repo", "Optional relay repository", false), choice("Read-only relay", "--github-relay-read-only", "Use a read-only GitHub relay", "off", "on")}
	case "bundle-create":
		f.fields = []field{text("Input path", "--input", "Private JSON input; or select live inputs", false), choice("Use live inputs", "--from-live", "Read existing private inputs", "off", "on"), text("Output path", "--output", "Encrypted bundle destination", true), text("Recipient", "--recipient", "Public age recipient", true)}
	case "bundle-check":
		f.fields = []field{text("Bundle path", "--bundle", "Encrypted bundle", true), text("Identity path", "--identity", "Age identity file path", true)}
	case "test":
		f.fields = []field{choice("Python", "python", "Select test suites; none runs all", "off", "on"), choice("Node", "node", "", "off", "on"), choice("Shell", "shell", "", "off", "on"), choice("Lua", "lua", "", "off", "on")}
	case "publish":
		f.fields = []field{choice("Scope", "", "Current change by default", "current", "all", "bookmark"), text("Bookmark", "--bookmark", "Required when scope is bookmark", false)}
	}
	if len(f.fields) == 0 {
		f.selected = 1
	}
	return f
}
func (f form) args() ([]string, error) {
	out := append([]string(nil), f.item.prefix...)
	if len(out) == 0 {
		out = []string{f.item.name}
	}
	for _, x := range f.fields {
		if x.required && strings.TrimSpace(x.value) == "" && len(x.values) == 0 {
			return nil, fmt.Errorf("%s is required", x.label)
		}
		if x.multiple {
			if x.value != "" {
				out = append(out, x.value)
			}
			out = append(out, x.values...)
			continue
		}
		if len(x.choices) > 0 {
			switch x.label {
			case "Output":
				if x.value != "dashboard" {
					out = append(out, "--"+x.value)
				}
			case "Destination":
				switch x.value {
				case "base":
					out = append(out, "--base")
				case "workstation", "nas":
					out = append(out, "--profile", x.value)
				case "path":
					if f.fields[2].value == "" {
						return nil, errors.New("Destination path is required")
					}
					out = append(out, "--path", f.fields[2].value)
				}
			case "Profile":
				if x.value == "choose" {
					return nil, errors.New("Profile is required")
				}
				out = append(out, x.flag, x.value)
			case "Scope":
				switch x.value {
				case "all":
					out = append(out, "--all")
				case "bookmark":
					if f.fields[1].value == "" {
						return nil, errors.New("Bookmark is required")
					}
					out = append(out, "--bookmark", f.fields[1].value)
				}
			default:
				if x.value == "on" {
					out = append(out, x.flag)
				}
			}
			continue
		}
		if x.label == "Destination path" || x.label == "Bookmark" {
			continue
		}
		if x.value != "" {
			if !x.positional {
				out = append(out, x.flag)
			}
			out = append(out, x.value)
		}
	}
	if f.item.name == "bundle-create" {
		if (f.fields[0].value != "") == (f.fields[1].value == "on") {
			return nil, errors.New("Choose input path or live inputs")
		}
	}
	out = append(out, f.advanced...)
	return out, nil
}

// Session preserves selection while the caller runs commands between menus.
type Session struct {
	group, child int
	expanded     bool
	selected     map[int]int
}

func NewSession() *Session                { return &Session{selected: map[int]int{}} }
func Run(args []string) ([]string, error) { return NewSession().Run(args) }
func (s *Session) Run(args []string) ([]string, error) {
	if s.selected == nil {
		s.selected = map[int]int{}
	}
	m := model{s: s, width: 80, height: 24}
	if len(args) > 0 {
		for _, g := range groups {
			for _, it := range g.items {
				if it.name == args[0] {
					m.form = formFor(it)
					m.page = "form"
					break
				}
			}
		}
	}
	tty, err := os.OpenFile("/dev/tty", os.O_RDWR, 0)
	if err != nil {
		return nil, err
	}
	defer tty.Close()
	p := tea.NewProgram(m, tea.WithInput(tty), tea.WithOutput(tty))
	result, err := p.Run()
	if err != nil {
		return nil, err
	}
	finished := result.(model)
	if finished.result == nil {
		return nil, ErrCancelled
	}
	return finished.result, nil
}

type model struct {
	s               *Session
	page            string
	form            form
	width, height   int
	search, query   string
	searching, help bool
	result          []string
}

func (m model) Init() tea.Cmd { return nil }
func (m model) visible() []int {
	var a []int
	for i, it := range groups[m.s.group].items {
		if strings.Contains(strings.ToLower(it.label+" "+it.name+" "+it.description), strings.ToLower(m.query)) {
			a = append(a, i)
		}
	}
	return a
}
func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch v := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = v.Width, v.Height
	case tea.KeyPressMsg:
		k := v.String()
		if k == "ctrl+c" {
			return m, tea.Quit
		}
		if m.searching {
			switch k {
			case "enter":
				m.searching = false
			case "esc":
				m.searching = false
				m.query = m.search
			case "backspace":
				r := []rune(m.query)
				if len(r) > 0 {
					m.query = string(r[:len(r)-1])
				}
			default:
				if v.Text != "" {
					m.query += v.Text
				}
			}
			m.s.child = 0
			return m, nil
		}
		if m.page == "form" && m.form.editing {
			switch k {
			case "enter":
				if m.form.selected < len(m.form.fields) {
					if m.form.fields[m.form.selected].multiple {
						if m.form.buffer != "" {
							m.form.fields[m.form.selected].values = append(m.form.fields[m.form.selected].values, m.form.buffer)
						}
					} else {
						m.form.fields[m.form.selected].value = m.form.buffer
					}
				} else if m.form.buffer != "" {
					m.form.advanced = append(m.form.advanced, m.form.buffer)
				}
				m.form.editing = false
				m.form.err = ""
			case "esc":
				m.form.editing = false
			case "backspace":
				r := []rune(m.form.buffer)
				if len(r) > 0 {
					m.form.buffer = string(r[:len(r)-1])
				}
			default:
				if v.Text != "" {
					m.form.buffer += v.Text
				}
			}
			return m, nil
		}
		if k == "?" {
			m.help = !m.help
			return m, nil
		}
		if k == "q" {
			return m, tea.Quit
		}
		if m.page == "form" {
			n := len(m.form.fields)
			switch k {
			case "esc", "left":
				m.page = ""
				m.form.err = ""
			case "up", "k":
				m.form.selected = max(0, m.form.selected-1)
			case "down", "j":
				m.form.selected = min(n+1, m.form.selected+1)
			case "backspace":
				if m.form.selected < n && m.form.fields[m.form.selected].multiple && len(m.form.fields[m.form.selected].values) > 0 {
					f := &m.form.fields[m.form.selected]
					f.values = f.values[:len(f.values)-1]
				} else if m.form.selected == n && len(m.form.advanced) > 0 {
					m.form.advanced = m.form.advanced[:len(m.form.advanced)-1]
				}
			case "enter", "space", "right":
				if m.form.selected == n+1 {
					args, err := m.form.args()
					if err != nil {
						m.form.err = err.Error()
					} else {
						m.result = args
						return m, tea.Quit
					}
				} else if m.form.selected == n {
					m.form.editing = true
					m.form.buffer = ""
				} else {
					f := &m.form.fields[m.form.selected]
					if len(f.choices) > 0 {
						idx := 0
						for i, c := range f.choices {
							if c == f.value {
								idx = i
							}
						}
						f.value = f.choices[(idx+1)%len(f.choices)]
					} else {
						m.form.editing = true
						m.form.buffer = f.value
						if f.multiple {
							m.form.buffer = ""
						}
					}
				}
			}
			return m, nil
		}
		switch k {
		case "/":
			if m.s.expanded {
				m.search = m.query
				m.searching = true
			}
		case "up", "k":
			if m.s.expanded {
				m.s.child = max(0, m.s.child-1)
			} else {
				m.s.group = max(0, m.s.group-1)
			}
		case "down", "j":
			if m.s.expanded {
				m.s.child = min(max(0, len(m.visible())-1), m.s.child+1)
			} else {
				m.s.group = min(len(groups)-1, m.s.group+1)
			}
		case "left", "esc":
			if m.s.expanded {
				m.s.selected[m.s.group] = m.s.child
				m.s.expanded = false
				m.query = ""
			} else {
				return m, tea.Quit
			}
		case "enter", "space", "right":
			if !m.s.expanded {
				m.s.expanded = true
				m.s.child = min(m.s.selected[m.s.group], len(m.visible())-1)
			} else if a := m.visible(); len(a) > 0 {
				m.form = formFor(groups[m.s.group].items[a[m.s.child]])
				m.page = "form"
			}
		}
	}
	return m, nil
}
func (m model) View() tea.View {
	var lines []string
	add := func(v string) { lines = append(lines, v) }
	compact := m.height < 20 || m.width < 70
	if m.page == "form" {
		f := m.form
		add("DOTS · " + f.item.label)
		if !compact {
			add(f.item.description)
			add("")
		}
		var rows []string
		for _, x := range f.fields {
			value := x.value
			if x.multiple && len(x.values) > 0 {
				value = strings.Join(x.values, ", ")
			}
			if value == "" {
				value = "(empty)"
			}
			rows = append(rows, x.label+": "+value)
		}
		rows = append(rows, fmt.Sprintf("Advanced argument tokens: %v", f.advanced), "Run")
		var tail []string
		if f.editing {
			tail = append(tail, "Edit: "+f.buffer+"_", "Enter save · Esc cancel")
		} else {
			if f.err != "" {
				tail = append(tail, "Error: "+f.err)
			}
			if !compact && f.selected < len(f.fields) && f.fields[f.selected].help != "" {
				tail = append(tail, f.fields[f.selected].help)
			}
			if !compact && f.selected == len(f.fields) {
				tail = append(tail, "Enter adds one literal argv token; Backspace removes the last.")
			}
			if args, err := f.args(); err == nil {
				tail = append(tail, "Command: dots "+quoteArgs(args))
			}
			if compact {
				tail = append(tail, "↑↓ select · Enter open · ← back · ?")
			} else {
				tail = append(tail, "↑↓ select · Enter edit/toggle/run · Left back · ? help · q quit")
			}
		}
		capacity := max(1, m.height-len(lines)-len(tail))
		start, end := window(f.selected, len(rows), capacity)
		for i := start; i < end; i++ {
			prefix := "  "
			if i == f.selected {
				prefix = "> "
			}
			add(prefix + rows[i])
		}
		lines = append(lines, tail...)
	} else {
		add("DOTS · machine setup")
		if !compact {
			add("")
		}
		// Reserve the footer and a row for each group. The selected child remains visible.
		capacity := max(1, m.height-len(lines)-len(groups)-1)
		for gi, g := range groups {
			prefix := "  "
			if gi == m.s.group {
				prefix = "> "
			}
			label := "› " + g.name
			if m.s.expanded && gi == m.s.group {
				label = "⌄ " + g.name
			}
			if m.s.expanded && gi == m.s.group {
				a := m.visible()
				if len(a) > capacity {
					label += fmt.Sprintf(" (%d/%d)", m.s.child+1, len(a))
				}
			}
			add(prefix + label)
			if m.s.expanded && gi == m.s.group {
				a := m.visible()
				start, end := window(m.s.child, len(a), capacity)
				for i := start; i < end; i++ {
					it := g.items[a[i]]
					prefix := "    "
					if i == m.s.child {
						prefix = "  > "
					}
					description := ""
					if !compact {
						description = " — " + it.description
					}
					add(prefix + it.label + description)
				}
				if len(a) == 0 {
					add("    No matches")
				}
			}
		}
		if m.searching {
			add("Search: " + m.query + "_")
		} else if m.query != "" {
			add("Filter: " + m.query)
		}
		if m.searching {
			add("Enter apply · Esc cancel")
		} else if compact {
			add("↑↓ select · Enter open · ← back · ?")
		} else {
			add("↑↓ select · Enter/Space/Right open · Left back · / search · ? help · q quit")
		}
	}
	if m.help {
		lines = append(lines, "Choose a command, review options, then Run. Advanced arguments are literal tokens.")
	}
	title := lipgloss.NewStyle().Foreground(lipgloss.Color("#8BE9FD")).Bold(true)
	focus := lipgloss.NewStyle().Foreground(lipgloss.Color("#D7E5FF")).Bold(true)
	muted := lipgloss.NewStyle().Foreground(lipgloss.Color("#8892A0"))
	for i, line := range lines {
		line = ansi.Truncate(line, max(1, m.width), "…")
		switch {
		case i == 0:
			line = title.Render(line)
		case strings.HasPrefix(line, "> ") || strings.HasPrefix(line, "  > "):
			line = focus.Render(line)
		case i == len(lines)-1:
			line = muted.Render(line)
		}
		lines[i] = line
	}
	return tea.NewView(strings.Join(lines, "\n"))
}

func window(selected, total, capacity int) (int, int) {
	if total <= capacity {
		return 0, total
	}
	start := max(0, selected-capacity+1)
	start = min(start, total-capacity)
	return start, start + capacity
}
func quoteArgs(args []string) string {
	s := make([]string, len(args))
	for i, a := range args {
		s[i] = fmt.Sprintf("%q", a)
	}
	return strings.Join(s, " ")
}
