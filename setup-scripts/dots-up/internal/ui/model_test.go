package ui

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	tea "charm.land/bubbletea/v2"
)

func send(m Model, e Event) Model {
	updated, _ := m.Update(e)
	return updated.(Model)
}

func TestStageLifecycleAndSelection(t *testing.T) {
	m := NewModel(t.TempDir(), false)
	m = send(m, Event{V: 1, Kind: "run_start", ID: "r1", Host: "Mac", Profile: "workstation"})
	m = send(m, Event{V: 1, Kind: "stage_start", ID: "brew", Group: "Packages", Label: "Homebrew formulae"})
	m = send(m, Event{V: 1, Kind: "change", Stage: "brew", Item: "ripgrep", Before: "14", After: "15"})
	m = send(m, Event{V: 1, Kind: "stage_end", ID: "brew", Status: "ok", Summary: "Updated one formula"})
	m = send(m, Event{V: 1, Kind: "stage_start", ID: "tools", Group: "Tools", Label: "CLI tools"})
	if len(m.Stages) != 2 || m.Selected != 1 || m.Stages[0].Status != "ok" || len(m.Stages[0].Changes) != 1 {
		t.Fatalf("unexpected stage state: %#v", m)
	}
	m = send(m, Event{V: 1, Kind: "run_end", ExitCode: 0, DurationMS: 1200})
	if !m.Finished || m.Running || !strings.Contains(m.View().Content, "Complete") {
		t.Fatal("completed run was not shown")
	}
}

func TestHoldUntilExitAndNoWait(t *testing.T) {
	for _, noWait := range []bool{false, true} {
		m := NewModel(t.TempDir(), noWait)
		_, cmd := m.Update(tea.KeyPressMsg{Code: 'q'})
		if cmd != nil {
			t.Fatal("quit should not stop an active run")
		}
		updated, cmd := m.Update(Event{V: 1, Kind: "run_end"})
		if noWait && cmd == nil {
			t.Fatal("no-wait should quit on run_end")
		}
		if !noWait && cmd != nil {
			t.Fatal("completed dashboard should hold")
		}
		_, cmd = updated.Update(tea.KeyPressMsg{Code: 'q'})
		if cmd == nil {
			t.Fatal("quit should close a completed run")
		}
	}
}

func TestLogPathStaysWithinRunState(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "stage.log")
	if err := os.WriteFile(path, []byte("hello\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	m := NewModel(root, false)
	m = send(m, Event{V: 1, Kind: "stage_start", ID: "a"})
	m = send(m, Event{V: 1, Kind: "stage_end", ID: "a", Status: "ok", LogPath: path})
	if m.Stages[0].LogPath != path {
		t.Fatal("in-scope log path rejected")
	}
	m.ShowLog = true
	m.refreshDetail()
	if !strings.Contains(m.lastLog, "hello") {
		t.Fatal("log content not loaded")
	}
	m = send(m, Event{V: 1, Kind: "stage_end", ID: "a", LogPath: filepath.Join(root, "..", "outside.log")})
	if m.Stages[0].LogPath != path {
		t.Fatal("out-of-scope log path accepted")
	}
}

func TestCancelIsSentOnce(t *testing.T) {
	m := NewModel(t.TempDir(), false)
	m.intents = make(chan string, 2)
	for range 2 {
		updated, _ := m.Update(tea.KeyPressMsg(tea.Key{Code: 'c', Mod: tea.ModCtrl}))
		m = updated.(Model)
	}
	if len(m.intents) != 1 || <-m.intents != "cancel" {
		t.Fatal("active ctrl+c should request one cancellation")
	}
}

func TestSearchReadsFullLogAndStripsTerminalControls(t *testing.T) {
	path := filepath.Join(t.TempDir(), "large.log")
	body := "target first\n" + strings.Repeat("filler line\n", 15000) + "\x1b[31mtarget second\x1b[0m\n"
	if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	result := searchLog(path, "target")
	if !strings.Contains(result, "2 matches") || !strings.Contains(result, "target first") || !strings.Contains(result, "target second") || strings.Contains(result, "\x1b") {
		t.Fatalf("bad full-log search: %q", result)
	}
}

func TestSmallTerminalUsesActualSize(t *testing.T) {
	m := NewModel(t.TempDir(), false)
	updated, _ := m.Update(tea.WindowSizeMsg{Width: 25, Height: 8})
	m = updated.(Model)
	if m.Width != 25 || m.Height != 8 {
		t.Fatalf("size was padded: %dx%d", m.Width, m.Height)
	}
	for _, line := range strings.Split(m.View().Content, "\n") {
		if len([]rune(line)) > 25 {
			t.Fatalf("small view overflows: %q", line)
		}
	}
}

func TestOverviewAndTerminalViews(t *testing.T) {
	m := NewModel(t.TempDir(), false)
	m = send(m, Event{V: 1, Kind: "stage_start", ID: "brew", Group: "Packages", Label: "Homebrew formulae"})
	content := m.View().Content
	for _, group := range groupOrder {
		if !strings.Contains(content, group) {
			t.Fatalf("overview missing group %q", group)
		}
	}
	updated, _ := m.Update(tea.KeyPressMsg{Code: 't'})
	m = updated.(Model)
	content = m.View().Content
	if !strings.Contains(content, "Captured terminal output") || strings.Contains(content, "Source & settings") {
		t.Fatal("terminal view did not replace overview")
	}
}

func TestManualTerminalRequestAndReturn(t *testing.T) {
	m := NewModel(t.TempDir(), false)
	m.intents = make(chan string, 2)
	m = send(m, Event{V: 1, Kind: "run_start", ID: "run"})
	for range 2 {
		updated, _ := m.Update(tea.KeyPressMsg{Code: 't'})
		m = updated.(Model)
	}
	if !m.TerminalRequested || m.RawLog || len(m.intents) != 1 || <-m.intents != "terminal_request" {
		t.Fatal("running t should request one manual terminal takeover")
	}
	m = send(m, Event{V: 1, Kind: "terminal_end"})
	if m.TerminalRequested {
		t.Fatal("terminal_end should allow another request")
	}
	m = send(m, Event{V: 1, Kind: "run_end"})
	updated, _ := m.Update(tea.KeyPressMsg{Code: 't'})
	if !updated.(Model).RawLog {
		t.Fatal("finished t should open captured log view")
	}
}

func TestConcurrentAppStoreDoesNotReplaceMainStage(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "app-store.log")
	if err := os.WriteFile(path, []byte("App Store update in progress\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	m := NewModel(root, false)
	m = send(m, Event{V: 1, Kind: "run_start", ID: "run"})
	m = send(m, Event{V: 1, Kind: "stage_start", ID: "brew", Group: "Packages", Label: "Homebrew casks"})
	m = send(m, Event{V: 1, Kind: "app_store_start", ID: "mac-app-store", Group: "Packages", Label: "Mac App Store", Status: "running", LogPath: path})
	if m.Selected != 0 || m.CurrentMain != 0 || m.AppStoreIndex != 1 {
		t.Fatalf("App Store displaced main stage: selected=%d main=%d app=%d", m.Selected, m.CurrentMain, m.AppStoreIndex)
	}
	view := m.View().Content
	if !strings.Contains(view, "NOW") || !strings.Contains(view, "APP STORE") {
		t.Fatal("concurrent status lines missing")
	}
	updated, _ := m.Update(tea.KeyPressMsg{Code: 'a'})
	m = updated.(Model)
	if m.Selected != 1 || !m.ShowLog || !strings.Contains(m.lastLog, "App Store update in progress") {
		t.Fatal("App Store captured log not selectable")
	}
	m = send(m, Event{V: 1, Kind: "app_store_end", ID: "mac-app-store", Status: "ok", Summary: "Updated one app", LogPath: path})
	if m.Stages[1].Status != "ok" || m.CurrentMain != 0 {
		t.Fatal("App Store end changed main stage")
	}
}

func TestOverviewPrioritizesAttentionAndVerifiedChanges(t *testing.T) {
	m := NewModel(t.TempDir(), false)
	m = send(m, Event{V: 1, Kind: "run_start", ID: "run", Host: "Mac", Profile: "workstation"})
	m = send(m, Event{V: 1, Kind: "stage_start", ID: "tools", Group: "Tools", Label: "CLI tools"})
	m = send(m, Event{V: 1, Kind: "change", Stage: "tools", Item: "ripgrep", Before: "14.1", After: "15.0"})
	m = send(m, Event{V: 1, Kind: "stage_end", ID: "tools", Status: "ok", Summary: "completed"})
	m = send(m, Event{V: 1, Kind: "stage_start", ID: "plugins", Group: "Editor plugins", Label: "Editor plugins"})
	m = send(m, Event{V: 1, Kind: "stage_end", ID: "plugins", Status: "failed", Summary: "Plugin update failed", Action: "Run dots up again after fixing the plugin source"})
	m = send(m, Event{V: 1, Kind: "notice", Severity: "attention", Summary: "Source sync deferred; local changes preserved"})
	m = send(m, Event{V: 1, Kind: "stage_start", ID: "final", Group: "Final checks", Label: "Settings checkpoint"})
	m = send(m, Event{V: 1, Kind: "stage_end", ID: "final", Status: "ok", Summary: "completed"})
	m = send(m, Event{V: 1, Kind: "run_end", ExitCode: 1, DurationMS: 2000})
	content := m.View().Content
	for _, wanted := range []string{"Needs attention", "1 attention", "1 failed", "NEEDS ATTENTION  2", "Source sync deferred", "Plugin update failed", "Next: Run dots up again", "CHANGES  1", "ripgrep  14.1 → 15.0", "Editor plugins", "failed"} {
		if !strings.Contains(content, wanted) {
			t.Fatalf("overview missing %q", wanted)
		}
	}
	if strings.Contains(content, "STAGE DETAILS") || strings.Contains(content, "Final checks  ·  Settings checkpoint") {
		t.Fatal("default overview shows last stage details")
	}
	if strings.Contains(content, "\n\n\n\n") {
		t.Fatal("overview has a large blank gap")
	}
	if rows := len(strings.Split(content, "\n")); rows > 30 {
		t.Fatalf("overview exceeds 30 rows: %d", rows)
	}
	updated, _ := m.Update(tea.KeyPressMsg{Code: tea.KeyEnter})
	m = updated.(Model)
	if !m.DetailFocus || !strings.Contains(m.View().Content, "STAGE DETAILS") {
		t.Fatal("Enter did not open stage details")
	}
	updated, _ = m.Update(tea.KeyPressMsg{Code: tea.KeyEscape})
	m = updated.(Model)
	if !m.overview() || !strings.Contains(m.View().Content, "CHANGES  1") {
		t.Fatal("Esc did not return to overview")
	}
}

func TestNoticeAndStageAttentionDeduplication(t *testing.T) {
	m := NewModel(t.TempDir(), false)
	m = send(m, Event{V: 1, Kind: "stage_start", ID: "plugins", Group: "Editor plugins", Label: "Editor plugins"})
	m = send(m, Event{V: 1, Kind: "stage_end", ID: "plugins", Status: "failed", Summary: "Plugin update failed"})
	m = send(m, Event{V: 1, Kind: "notice", Stage: "plugins", Severity: "error", Summary: "Plugin update failed"})
	m = send(m, Event{V: 1, Kind: "run_end", ExitCode: 1})
	content := m.View().Content
	if !strings.Contains(content, "0 attention  ·  1 failed") || !strings.Contains(content, "NEEDS ATTENTION  1") {
		t.Fatal("duplicate failure notice inflated attention count")
	}
}

func TestNoticeOnlyMarksSuccessfulRunForAttention(t *testing.T) {
	m := NewModel(t.TempDir(), false)
	m = send(m, Event{V: 1, Kind: "notice", Severity: "attention", Summary: "Source sync deferred"})
	m = send(m, Event{V: 1, Kind: "run_end", ExitCode: 0})
	view := m.View().Content
	if !strings.Contains(view, "Needs attention") || !strings.Contains(view, "1 attention") {
		t.Fatal("notice-only run was shown as complete")
	}
}
