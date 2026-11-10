package ui

import (
	"fmt"
	"strings"
	"testing"

	tea "charm.land/bubbletea/v2"
	"github.com/charmbracelet/x/ansi"
)

func TestActionFormattingIncludesChangesWithoutVersions(t *testing.T) {
	for _, test := range []struct{ action, before, after, want string }{
		{"", "not installed", "2", "installed  tool  2"},
		{"", "1", "2", "updated  tool  1 → 2"},
		{"", "1", "not installed", "removed  tool  1"},
		{"changed", "", "", "changed  tool"},
	} {
		if got := ChangeLine(test.action, "tool", test.before, test.after); got != test.want {
			t.Errorf("got %q, want %q", got, test.want)
		}
	}
}

func TestEveryOutcomeRemainsReachableInLongReports(t *testing.T) {
	m := NewModel(t.TempDir(), false)
	m.Width, m.Height = 80, 18
	m = send(m, Event{Kind: "stage_start", ID: "tools", Group: "Tools"})
	for i := range 200 {
		m = send(m, Event{Kind: "change", Stage: "tools", Item: fmt.Sprintf("tool-%03d", i), Action: "changed"})
	}
	m = send(m, Event{Kind: "run_end"})
	for range 40 {
		m = press(m, tea.KeyPressMsg{Code: tea.KeyPgDown})
	}
	if !strings.Contains(m.View().Content, "tool-199") {
		t.Fatal("last item inaccessible in overview")
	}
	m.selectGroup(m.groupIndex("Tools"))
	m = press(m, tea.KeyPressMsg{Code: tea.KeyEnter})
	for range 199 {
		m = press(m, tea.KeyPressMsg{Code: tea.KeyDown})
	}
	view := m.View().Content
	if !strings.Contains(view, "tool-199") || !strings.Contains(view, "back") || strings.Contains(view, "tool-000") {
		t.Fatalf("area did not scroll through full list: %s", view)
	}
	if len(strings.Split(view, "\n")) > m.Height {
		t.Fatal("scroll hid footer below terminal")
	}
}

func TestAttentionRowFollowsLastArea(t *testing.T) {
	m := NewModel(t.TempDir(), false)
	m.apply(Event{Kind: "notice", Severity: "attention", Summary: "Review source changes"})
	m.selectGroup(len(m.groups()) - 1)
	m = press(m, tea.KeyPressMsg{Code: tea.KeyDown})
	if m.SelectedGroup != -1 {
		t.Fatal("Down after last area did not select attention")
	}
	m = press(m, tea.KeyPressMsg{Code: tea.KeyEnter})
	if !m.AttentionExpanded || !strings.Contains(m.View().Content, "Review source changes") {
		t.Fatal("attention did not open")
	}
	m = press(m, tea.KeyPressMsg{Code: tea.KeyLeft})
	m = press(m, tea.KeyPressMsg{Code: tea.KeyUp})
	if m.SelectedGroup != len(m.groups())-1 {
		t.Fatal("Up from attention did not return to last area")
	}
}

func TestFinishedReportDoesNotClaimUnfinishedStepIsRunning(t *testing.T) {
	m := NewModel(t.TempDir(), false)
	m.apply(Event{Kind: "item_upsert", ID: "source:validate", Group: "Source", Label: "Validate source", Status: "unknown", Summary: "running"})
	m.apply(Event{Kind: "run_end"})
	if m.Stages[0].Status != "unknown" || m.Stages[0].Summary != "Outcome unknown" {
		t.Fatalf("stale running result: %+v", m.Stages[0])
	}
}

func TestExpandedAreaWrapsCompleteRevisionTransitions(t *testing.T) {
	const before = "0123456789abcdef0123456789abcdef01234567"
	const after = "fedcba9876543210fedcba9876543210fedcba98"
	for _, size := range [][2]int{{80, 18}, {32, 8}} {
		t.Run(fmt.Sprintf("%dx%d", size[0], size[1]), func(t *testing.T) {
			m := NewModel(t.TempDir(), false)
			m.Width, m.Height = size[0], size[1]
			m.apply(Event{Kind: "stage_start", ID: "source", Group: "Source & settings"})
			m.apply(Event{Kind: "change", Stage: "source", Item: "Configuration source", Before: before, After: after})
			m.apply(Event{Kind: "stage_end", ID: "source", Status: "ok"})
			m.apply(Event{Kind: "run_end"})
			m.selectGroup(m.groupIndex("Source & settings"))
			m = press(m, tea.KeyPressMsg{Code: tea.KeyEnter})
			var rows []string
			for {
				view := ansi.Strip(m.View().Content)
				lines := strings.Split(view, "\n")
				if len(lines) > m.Height {
					t.Fatalf("wrapped area exceeds terminal: %s", view)
				}
				for _, line := range lines {
					if ansi.StringWidth(line) > m.Width {
						t.Fatalf("wrapped line exceeds terminal: %q", line)
					}
				}
				if m.viewport.AtBottom() {
					for _, line := range lines[3 : 3+m.viewport.Height()] {
						rows = append(rows, strings.TrimRight(line, " "))
					}
					break
				}
				rows = append(rows, strings.TrimRight(lines[3], " "))
				m = press(m, tea.KeyPressMsg{Code: tea.KeyDown})
			}
			content := strings.Join(rows, "")
			if !strings.Contains(content, before) || !strings.Contains(content, after) || strings.Contains(content, "…") {
				t.Fatalf("vertical scrolling lost revision text: %s", content)
			}
		})
	}
}
