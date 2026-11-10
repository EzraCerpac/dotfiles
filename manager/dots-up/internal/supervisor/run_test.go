package supervisor

import (
	"encoding/json"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/EzraCerpac/dotfiles/manager/dots-up/internal/ui"
)

func TestDashboardFailureContinuesOneUpdaterRun(t *testing.T) {
	oldInteractive, oldSize := hasInteractiveTerminal, currentTerminalSize
	oldStart, oldDashboard := startUpdaterBackend, runDashboard
	defer func() {
		hasInteractiveTerminal, currentTerminalSize = oldInteractive, oldSize
		startUpdaterBackend, runDashboard = oldStart, oldDashboard
	}()

	hasInteractiveTerminal = func() bool { return true }
	currentTerminalSize = func() (int, int) { return 100, 30 }
	starts := 0
	startUpdaterBackend = func(Options, *runFiles, bool) (*backend, *os.File, io.Reader, error) {
		starts++
		eventR, eventW, err := os.Pipe()
		if err != nil {
			return nil, nil, nil, err
		}
		cmd := exec.Command("sh", "-c", "sleep 0.05")
		if err := cmd.Start(); err != nil {
			_ = eventR.Close()
			_ = eventW.Close()
			return nil, nil, nil, err
		}
		go func() {
			defer eventW.Close()
			for _, event := range []ui.Event{
				{V: 1, Kind: "run_start", Profile: "nas", Host: "fixture"},
				{V: 1, Kind: "stage_start", ID: "tools", Group: "Tools", Label: "Mise tools"},
				{V: 1, Kind: "stage_end", ID: "tools", Status: "ok", Summary: "completed"},
				{V: 1, Kind: "run_end", ExitCode: 0},
			} {
				if err := json.NewEncoder(eventW).Encode(event); err != nil {
					return
				}
			}
		}()
		return &backend{command: cmd, pty: true}, eventR, nil, nil
	}
	runDashboard = func(<-chan ui.Event, io.Writer, string, bool) error {
		return errors.New("injected renderer failure")
	}

	state := filepath.Join(t.TempDir(), "state")
	if code := Run(Options{Root: t.TempDir(), StateDir: state}); code != 0 {
		t.Fatalf("run returned %d after renderer failure", code)
	}
	if starts != 1 {
		t.Fatalf("backend started %d times after renderer failure, want exactly once", starts)
	}
	report, _, err := latestReport(state)
	if err != nil {
		t.Fatal(err)
	}
	if report.ExitCode != 0 || len(report.Events) < 4 {
		t.Fatalf("updater did not complete and save its report after renderer failure: %+v", report)
	}
}

func TestUpdaterCommandRunsManagerFromHome(t *testing.T) {
	t.Setenv("DOTS_UP_RUNNER", "")
	t.Setenv("DOTS_MISE_BIN", "/fixture/mise")
	if _, err := updaterCommand(Options{Root: "/fixture/config", Command: "status"}); err == nil {
		t.Fatal("a command started without a manager directory")
	}
	up, err := updaterCommand(Options{Root: "/fixture/config", Home: "/fixture/manager", Args: []string{"--plain"}})
	if err != nil {
		t.Fatal(err)
	}
	if got := strings.Join(up.Args, " "); got != "bash /fixture/manager/bin/dots --backend up --plain" {
		t.Fatalf("up runs %q", got)
	}
	status, err := updaterCommand(Options{Root: "/fixture/config", Home: "/fixture/manager", Command: "status"})
	if err != nil {
		t.Fatal(err)
	}
	if got := strings.Join(status.Args, " "); got != "bash /fixture/manager/lib/dots-command-backend /fixture/mise /fixture/config status" {
		t.Fatalf("status runs %q", got)
	}
}

// A dots script from before DOTS_HOME runs the newest renderer for `dots up`
// with only --root. The renderer must keep using that script's updater task.
func TestUpdaterCommandWithoutHomeUsesLegacySetupTask(t *testing.T) {
	t.Setenv("DOTS_UP_RUNNER", "")
	t.Setenv("DOTS_MISE_BIN", "/fixture/mise")
	for _, command := range []string{"", "up"} {
		up, err := updaterCommand(Options{Root: "/fixture/config", Command: command, Args: []string{"--plain"}})
		if err != nil {
			t.Fatal(err)
		}
		if got := strings.Join(up.Args, " "); got != "/fixture/mise -C /fixture/config run setup:update --plain" {
			t.Fatalf("legacy up (%q) runs %q", command, got)
		}
	}
}
