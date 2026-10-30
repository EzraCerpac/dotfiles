package ui

import (
	"fmt"
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

func press(m Model, key tea.KeyPressMsg) Model {
	updated, _ := m.Update(key)
	return updated.(Model)
}

func TestStageLifecycleAndSelection(t *testing.T) {
	m := NewModel(t.TempDir(), false)
	m = send(m, Event{V: 1, Kind: "run_start", ID: "r1", Host: "Mac", Profile: "workstation"})
	m = send(m, Event{V: 1, Kind: "stage_start", ID: "brew", Group: "Packages", Label: "Homebrew formulae"})
	m = send(m, Event{V: 1, Kind: "change", Stage: "brew", Item: "ripgrep", Before: "14", After: "15"})
	m = send(m, Event{V: 1, Kind: "stage_end", ID: "brew", Status: "ok", Summary: "Updated one formula"})
	m = send(m, Event{V: 1, Kind: "stage_start", ID: "tools", Group: "Tools", Label: "CLI tools"})
	if len(m.Stages) != 2 || m.Selected != -1 || m.SelectedGroup != 0 || m.CurrentMain != 1 || m.Stages[0].Status != "ok" || len(m.Stages[0].Changes) != 1 {
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
	m = send(m, Event{V: 1, Kind: "stage_start", ID: "a", Group: "Tools"})
	m.selectGroup(m.groupIndex("Tools"))
	m.expandSelectedGroup()
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
	m = press(m, tea.KeyPressMsg{Code: tea.KeyDown})
	m = press(m, tea.KeyPressMsg{Code: tea.KeyEnter})
	content := m.View().Content
	if !strings.Contains(content, "AREA") || !strings.Contains(content, "▾ Packages") || !strings.Contains(content, "Homebrew formulae") {
		t.Fatalf("expanded area missing its child: %s", content)
	}
	m = press(m, tea.KeyPressMsg{Code: 't'})
	content = m.View().Content
	if !strings.Contains(content, "Captured terminal output") || strings.Contains(content, "AREA  ▾ Packages") {
		t.Fatal("terminal view did not replace overview")
	}
}

func TestManualTerminalRequestAndReturn(t *testing.T) {
	m := NewModel(t.TempDir(), false)
	m.intents = make(chan string, 2)
	m = send(m, Event{V: 1, Kind: "run_start", ID: "run"})
	m = send(m, Event{V: 1, Kind: "stage_start", ID: "tools", Group: "Tools", Label: "CLI tools"})
	m.selectGroup(m.groupIndex("Tools"))
	m.expandSelectedGroup()
	for range 2 {
		m = press(m, tea.KeyPressMsg{Code: 't'})
	}
	if !m.TerminalRequested || m.RawLog || len(m.intents) != 1 || <-m.intents != "terminal_request" {
		t.Fatal("running t should request one manual terminal takeover")
	}
	m = send(m, Event{V: 1, Kind: "terminal_end"})
	if m.TerminalRequested {
		t.Fatal("terminal_end should allow another request")
	}
	m = send(m, Event{V: 1, Kind: "run_end"})
	m = press(m, tea.KeyPressMsg{Code: 't'})
	if !m.RawLog {
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
	if m.Selected != -1 || m.SelectedGroup != 0 || m.CurrentMain != 0 || m.AppStoreIndex != 1 {
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

func TestHierarchicalAreaNavigationKeepsSelectionAndOpensChildDetails(t *testing.T) {
	m := NewModel(t.TempDir(), false)
	m = send(m, Event{V: 1, Kind: "run_start", ID: "run"})
	m = send(m, Event{V: 1, Kind: "stage_start", ID: "formulas", Group: "Packages", Label: "Homebrew formulae"})
	m = send(m, Event{V: 1, Kind: "stage_start", ID: "casks", Group: "Packages", Label: "Homebrew casks"})
	if m.SelectedGroup != 0 || m.Selected != -1 || m.CurrentMain != 1 {
		t.Fatalf("progress moved tree selection: area=%d child=%d current=%d", m.SelectedGroup, m.Selected, m.CurrentMain)
	}
	if !strings.Contains(m.View().Content, "› >") || !strings.Contains(m.View().Content, "Source & settings") {
		t.Fatal("collapsed view does not visibly mark the selected area")
	}

	m = press(m, tea.KeyPressMsg{Code: tea.KeyDown})
	if m.SelectedGroup != 1 || m.ExpandedGroup != -1 || m.Selected != 0 {
		t.Fatalf("down did not select Packages: area=%d expanded=%d child=%d", m.SelectedGroup, m.ExpandedGroup, m.Selected)
	}
	if !strings.Contains(m.View().Content, "› >") {
		t.Fatal("selected Packages area is not visibly marked")
	}
	m = send(m, Event{V: 1, Kind: "stage_start", ID: "tools", Group: "Tools", Label: "CLI tools"})
	if m.SelectedGroup != 1 || m.Selected != 0 || m.CurrentMain != 2 {
		t.Fatalf("new stage stole the selected area or child: area=%d child=%d current=%d", m.SelectedGroup, m.Selected, m.CurrentMain)
	}
	m = press(m, tea.KeyPressMsg{Code: tea.KeySpace})
	if m.ExpandedGroup != 1 || !strings.Contains(m.View().Content, "AREA") || !strings.Contains(m.View().Content, "Packages") || !strings.Contains(m.View().Content, "Homebrew formulae") {
		t.Fatal("Space did not expand the selected area with its child steps")
	}
	m = press(m, tea.KeyPressMsg{Code: tea.KeyDown})
	if m.Selected != 1 || !strings.Contains(m.View().Content, "›") || !strings.Contains(m.View().Content, "Homebrew casks") {
		t.Fatal("down did not move the visible child selection")
	}
	m = press(m, tea.KeyPressMsg{Code: tea.KeyLeft})
	if m.ExpandedGroup != -1 || m.SelectedGroup != 1 {
		t.Fatal("Left did not return to the selected parent area")
	}
	m = press(m, tea.KeyPressMsg{Code: tea.KeyEnter})
	if m.ExpandedGroup != 1 {
		t.Fatal("Enter did not open the selected area")
	}
	m = press(m, tea.KeyPressMsg{Code: tea.KeyLeft})
	m = press(m, tea.KeyPressMsg{Code: tea.KeyRight})
	if m.ExpandedGroup != 1 {
		t.Fatal("Right did not open the selected area")
	}
	m = press(m, tea.KeyPressMsg{Code: tea.KeyEnter})
	if !m.DetailFocus || !strings.Contains(m.View().Content, "STAGE DETAILS") || !strings.Contains(m.View().Content, "Homebrew casks") {
		t.Fatal("Enter did not open details for the selected child")
	}
	m = press(m, tea.KeyPressMsg{Code: tea.KeyLeft})
	if m.DetailFocus || m.ExpandedGroup != 1 || m.Selected != 1 {
		t.Fatal("Left from details did not return to the selected child")
	}
}

func TestSpaceCollapseFromDetailsRestoresAreaOverview(t *testing.T) {
	m := NewModel(t.TempDir(), false)
	m = send(m, Event{V: 1, Kind: "stage_start", ID: "tools", Group: "Tools", Label: "CLI tools"})
	m = send(m, Event{V: 1, Kind: "change", Stage: "tools", Item: "ripgrep", Before: "14", After: "15"})
	m = send(m, Event{V: 1, Kind: "stage_end", ID: "tools", Status: "ok", Summary: "Updated one tool"})
	m.selectGroup(m.groupIndex("Tools"))
	m.expandSelectedGroup()
	m = press(m, tea.KeyPressMsg{Code: tea.KeyEnter})
	if !m.DetailFocus || !strings.Contains(m.View().Content, "STAGE DETAILS") {
		t.Fatal("test did not enter the child detail view")
	}
	m = press(m, tea.KeyPressMsg{Code: tea.KeySpace})
	view := m.View().Content
	if m.ExpandedGroup >= 0 || m.DetailFocus || !strings.Contains(view, "CHANGES  1") || strings.Contains(view, "STAGE DETAILS") || strings.Contains(view, "Updated one tool") {
		t.Fatalf("Space left stale child details in the collapsed overview: %s", view)
	}
}

func TestLargeExpandedAreaKeepsSelectedChildAndFooterVisible(t *testing.T) {
	root := t.TempDir()
	lastLog := filepath.Join(root, "managed-app-24.log")
	if err := os.WriteFile(lastLog, []byte("last managed app output\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	m := NewModel(root, false)
	m = send(m, Event{V: 1, Kind: "run_start", ID: "run"})
	for i := range 25 {
		id := fmt.Sprintf("app-%02d", i)
		m = send(m, Event{V: 1, Kind: "stage_start", ID: id, Group: "Managed apps/local builds", Label: fmt.Sprintf("Managed app %02d", i)})
		end := Event{V: 1, Kind: "stage_end", ID: id, Status: "ok", Summary: "completed"}
		if i == 24 {
			end.LogPath = lastLog
		}
		m = send(m, end)
	}
	m = send(m, Event{V: 1, Kind: "run_end", ExitCode: 0})
	m.selectGroup(m.groupIndex("Managed apps/local builds"))
	m.expandSelectedGroup()
	for range 24 {
		m = press(m, tea.KeyPressMsg{Code: tea.KeyDown})
	}
	view := m.View().Content
	if !strings.Contains(view, "25/25") || !strings.Contains(view, "Managed app 24") || strings.Contains(view, "Managed app 00") {
		t.Fatal("expanded area did not scroll the selected last child into view")
	}
	lastChildLine := ""
	for _, line := range strings.Split(view, "\n") {
		if strings.Contains(line, "Managed app 24") && strings.Contains(line, "›") {
			lastChildLine = line
		}
	}
	if !strings.Contains(lastChildLine, "›") || !strings.Contains(view, "earlier update steps") || !strings.Contains(view, "↑↓ items") || !strings.Contains(view, "Finished") {
		t.Fatalf("selected child, scroll context, or finished footer is not visible: child=%q earlier=%t help=%t finished=%t", lastChildLine, strings.Contains(view, "earlier update steps"), strings.Contains(view, "↑↓ items"), strings.Contains(view, "Finished"))
	}
	if rows := len(strings.Split(view, "\n")); rows > m.Height {
		t.Fatalf("expanded area used %d rows in a %d-row terminal", rows, m.Height)
	}
	m = press(m, tea.KeyPressMsg{Code: tea.KeyEnter})
	if !m.DetailFocus || !strings.Contains(m.lastLog, "Managed apps/local builds") || !strings.Contains(m.lastLog, "Managed app 24") {
		t.Fatal("details did not use the selected last child")
	}
	m = press(m, tea.KeyPressMsg{Code: tea.KeyLeft})
	m = press(m, tea.KeyPressMsg{Code: 'l'})
	if !m.ShowLog || !strings.Contains(m.lastLog, "last managed app output") {
		t.Fatal("logs did not use the selected last child")
	}
}

func TestMiddleChildDetailsReserveHeadingRowInLongArea(t *testing.T) {
	m := NewModel(t.TempDir(), false)
	m = send(m, Event{V: 1, Kind: "run_start", ID: "run"})
	for i := range 25 {
		id := fmt.Sprintf("app-%02d", i)
		m = send(m, Event{V: 1, Kind: "stage_start", ID: id, Group: "Managed apps/local builds", Label: fmt.Sprintf("Managed app %02d", i)})
		m = send(m, Event{V: 1, Kind: "stage_end", ID: id, Status: "ok", Summary: "completed"})
	}
	m = send(m, Event{V: 1, Kind: "run_end", ExitCode: 0})
	m.selectGroup(m.groupIndex("Managed apps/local builds"))
	m.expandSelectedGroup()
	for range 17 {
		m = press(m, tea.KeyPressMsg{Code: tea.KeyDown})
	}
	m = press(m, tea.KeyPressMsg{Code: tea.KeyEnter})
	view := m.View().Content
	if !m.DetailFocus || !strings.Contains(view, "earlier update steps") || !strings.Contains(view, "later update steps") || !strings.Contains(view, "STAGE DETAILS") || !strings.Contains(view, "Finished") {
		t.Fatal("middle child detail view is missing the list window, heading, or footer")
	}
	if rows := len(strings.Split(view, "\n")); rows > m.Height {
		t.Fatalf("middle child detail view used %d rows in a %d-row terminal: %s", rows, m.Height, view)
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
	for range 4 {
		m = press(m, tea.KeyPressMsg{Code: tea.KeyDown})
	}
	m = press(m, tea.KeyPressMsg{Code: tea.KeyEnter})
	m = press(m, tea.KeyPressMsg{Code: tea.KeyEnter})
	if !m.DetailFocus || !strings.Contains(m.View().Content, "STAGE DETAILS") {
		t.Fatal("Enter did not open stage details")
	}
	m = press(m, tea.KeyPressMsg{Code: tea.KeyEscape})
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
