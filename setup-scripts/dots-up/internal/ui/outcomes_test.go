package ui

import (
	"fmt"
	"strings"
	"testing"

	tea "charm.land/bubbletea/v2"
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
