package launcher

import (
	"reflect"
	"strings"
	"testing"

	tea "charm.land/bubbletea/v2"
)

func find(name string) item {
	for _, g := range groups {
		for _, it := range g.items {
			if it.name == name {
				return it
			}
		}
	}
	panic(name)
}
func TestFormsBuildLiteralArgsAndValidate(t *testing.T) {
	f := formFor(find("add"))
	if _, err := f.args(); err == nil {
		t.Fatal("empty target accepted")
	}
	f.fields[0].value = "name with spaces;$(touch nope)"
	f.fields[1].value = "nas"
	f.advanced = []string{"another tool"}
	got, err := f.args()
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"add", "name with spaces;$(touch nope)", "--profile", "nas", "another tool"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("%q != %q", got, want)
	}
	f = formFor(find("remote"))
	f.fields[0].value = "host"
	if _, err := f.args(); err == nil {
		t.Fatal("missing profile accepted")
	}
	f.fields[1].value = "nas"
	got, err = f.args()
	if err != nil || !reflect.DeepEqual(got, []string{"remote", "host", "--profile", "nas"}) {
		t.Fatalf("%q %v", got, err)
	}
	f = formFor(find("bundle-create"))
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
	m := model{s: NewSession(), page: "form", form: formFor(find("remote")), width: 80, height: 24}
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
	m := model{s: NewSession(), page: "form", form: formFor(find("add")), width: 100, height: 30}
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
