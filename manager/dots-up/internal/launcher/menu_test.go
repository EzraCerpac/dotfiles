package launcher

import (
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	tea "charm.land/bubbletea/v2"
)

func find(name string) item {
	for _, g := range builtinGroups {
		for _, it := range g.items {
			if it.name == name {
				return it
			}
		}
	}
	panic(name)
}

var profiles = []string{"laptop", "server"}

func TestFormsBuildLiteralArgsAndValidate(t *testing.T) {
	f := formFor(find("add"), profiles)
	if _, err := f.args(); err == nil {
		t.Fatal("empty target accepted")
	}
	f.fields[0].value = "name with spaces;$(touch nope)"
	f.fields[1].value = "server"
	f.advanced = []string{"another tool"}
	got, err := f.args()
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"add", "name with spaces;$(touch nope)", "--profile", "server", "another tool"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("%q != %q", got, want)
	}
	f = formFor(find("remote"), profiles)
	f.fields[0].value = "host"
	if _, err := f.args(); err == nil {
		t.Fatal("missing profile accepted")
	}
	f.fields[1].value = "server"
	got, err = f.args()
	if err != nil || !reflect.DeepEqual(got, []string{"remote", "host", "--profile", "server"}) {
		t.Fatalf("%q %v", got, err)
	}
	f = formFor(find("bundle-create"), profiles)
	f.fields[2].value = "out"
	f.fields[3].value = "age1recipient"
	if _, err := f.args(); err == nil {
		t.Fatal("missing input accepted")
	}
	f.fields[1].value = "on"
	if _, err := f.args(); err != nil {
		t.Fatal(err)
	}
}
func key(s string) tea.KeyPressMsg { return tea.KeyPressMsg{Code: []rune(s)[0], Text: s} }
func TestMenuRequiresExplicitRunAndRestoresSelection(t *testing.T) {
	s := NewSession()
	m := model{s: s, width: 80, height: 24}
	a, _ := m.Update(tea.KeyPressMsg{Code: tea.KeyEnter})
	m = a.(model)
	if !s.expanded || m.result != nil {
		t.Fatal("opening group ran command")
	}
	a, _ = m.Update(tea.KeyPressMsg{Code: tea.KeyEnter})
	m = a.(model)
	if m.page != "form" || m.result != nil {
		t.Fatal("opening item ran command")
	}
	a, _ = m.Update(tea.KeyPressMsg{Code: tea.KeyEnter})
	m = a.(model)
	if !reflect.DeepEqual(m.result, []string{"status"}) {
		t.Fatalf("run: %q", m.result)
	}
}
func TestEditDoesNotTreatQAsQuit(t *testing.T) {
	m := model{s: NewSession(), page: "form", form: formFor(find("remote"), profiles), width: 80, height: 24}
	m.form.editing = true
	a, cmd := m.Update(key("q"))
	m = a.(model)
	if cmd != nil || m.form.buffer != "q" {
		t.Fatal("text input was treated as a shortcut")
	}
	if !strings.Contains(m.View().Content, "Edit: q") {
		t.Fatal("missing edited value")
	}
}

func TestGuidedTargetsAreSeparateTokens(t *testing.T) {
	m := model{s: NewSession(), page: "form", form: formFor(find("add"), profiles), width: 100, height: 30}
	for _, value := range []string{"qkl first tool", "second tool"} {
		m.form.editing = true
		m.form.buffer = value
		next, _ := m.Update(tea.KeyPressMsg{Code: tea.KeyEnter})
		m = next.(model)
	}
	m.form.advanced = []string{"--asset", "file with spaces.zip"}
	got, err := m.form.args()
	want := []string{"add", "qkl first tool", "second tool", "--asset", "file with spaces.zip"}
	if err != nil || !reflect.DeepEqual(got, want) {
		t.Fatalf("%q, %v", got, err)
	}
	next, _ := m.Update(tea.KeyPressMsg{Code: tea.KeyBackspace})
	m = next.(model)
	if len(m.form.fields[0].values) != 1 {
		t.Fatal("backspace did not remove last target")
	}
}

func TestProfilesComeFromTheConfiguration(t *testing.T) {
	f := formFor(find("add"), []string{"desk", "box"})
	if got := f.fields[1].choices; !reflect.DeepEqual(got, []string{"current", "base", "desk", "box", "path"}) {
		t.Fatalf("destinations: %q", got)
	}
	f.fields[0].value = "tool"
	f.fields[1].value = "box"
	if got, err := f.args(); err != nil || !reflect.DeepEqual(got, []string{"add", "tool", "--profile", "box"}) {
		t.Fatalf("%q %v", got, err)
	}
	// Without known profiles the remote profile is typed and still required.
	f = formFor(find("remote"), nil)
	f.fields[0].value = "host"
	if _, err := f.args(); err == nil {
		t.Fatal("missing typed profile accepted")
	}
	f.fields[1].value = "desk"
	if got, err := f.args(); err != nil || !reflect.DeepEqual(got, []string{"remote", "host", "--profile", "desk"}) {
		t.Fatalf("%q %v", got, err)
	}
}

func TestConfigurationCommandsFollowTheBuiltins(t *testing.T) {
	s := &Session{Commands: []string{"hello", "deploy"}, selected: map[int]int{}}
	groups := s.groups()
	last := groups[len(groups)-1]
	if len(groups) != len(builtinGroups)+1 || last.name != "Configuration" || last.items[0].name != "hello" || last.items[1].name != "deploy" {
		t.Fatalf("groups: %+v", last)
	}
	if !s.IsCommand("deploy") || s.IsCommand("status") {
		t.Fatal("IsCommand")
	}
	s.group = len(groups) - 1
	s.expanded = true
	m := model{s: s, width: 80, height: 40}
	if !strings.Contains(m.View().Content, "hello — dots/commands/hello") {
		t.Fatal("configuration command not shown")
	}
	next, _ := m.Update(tea.KeyPressMsg{Code: tea.KeyEnter})
	m = next.(model)
	m.form.advanced = []string{"two words"}
	if got, err := m.form.args(); err != nil || !reflect.DeepEqual(got, []string{"hello", "two words"}) {
		t.Fatalf("%q %v", got, err)
	}
	if (&Session{}).groups()[len(builtinGroups)-1].name != builtinGroups[len(builtinGroups)-1].name {
		t.Fatal("a session without commands changed the built-in groups")
	}
}

func TestDiscoverAsksTheManager(t *testing.T) {
	home := t.TempDir()
	script := "#!/usr/bin/env bash\n[[ \"$1\" == internal && \"$DOTS_ROOT\" == /config ]] || exit 9\ncase \"$2\" in profiles) printf 'desk\\nbox\\n' ;; commands) printf 'hello\\n' ;; esac\n"
	if err := os.MkdirAll(filepath.Join(home, "bin"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(home, "bin", "dots"), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	s := Discover(home, "/config")
	if !reflect.DeepEqual(s.Profiles, []string{"desk", "box"}) || !reflect.DeepEqual(s.Commands, []string{"hello"}) {
		t.Fatalf("%q %q", s.Profiles, s.Commands)
	}
	if s := Discover("", "/config"); s.Profiles != nil || s.Commands != nil {
		t.Fatal("listing without a manager")
	}
}
