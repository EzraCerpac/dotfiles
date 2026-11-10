package supervisor

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/EzraCerpac/dotfiles/setup-scripts/dots-up/internal/ui"
	"github.com/charmbracelet/x/term"
	"github.com/creack/pty"
	"golang.org/x/sys/unix"
)

const handoffFixtureInput = "q\x1b[D\x1b\x1d\n"

func TestManualToAutomaticHandoffWithPTY(t *testing.T) {
	for _, scenario := range []string{"manual active", "manual ready arrives late", "renderer fails"} {
		t.Run(scenario, func(t *testing.T) {
			oldInteractive, oldSize := hasInteractiveTerminal, currentTerminalSize
			oldStart, oldDashboard := startUpdaterBackend, runDashboard
			t.Cleanup(func() {
				hasInteractiveTerminal, currentTerminalSize = oldInteractive, oldSize
				startUpdaterBackend, runDashboard = oldStart, oldDashboard
			})
			hasInteractiveTerminal = func() bool { return true }
			currentTerminalSize = func() (int, int) { return 100, 30 }
			terminal, tty, err := pty.Open()
			if err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { _ = terminal.Close(); _ = tty.Close() })
			dir := t.TempDir()
			starts := 0
			startUpdaterBackend = func(Options, *runFiles, bool) (*backend, *os.File, io.Reader, error) {
				starts++
				eventR, eventW, err := os.Pipe()
				if err != nil {
					return nil, nil, nil, err
				}
				ackR, ackW, err := os.Pipe()
				if err != nil {
					return nil, nil, nil, err
				}
				cmd := exec.Command(os.Args[0], "-test.run=^TestHandoffFixtureProcess$")
				cmd.Env = append(os.Environ(), "DOTS_HANDOFF_FIXTURE="+dir)
				cmd.ExtraFiles = []*os.File{eventW, ackR}
				master, err := pty.StartWithSize(cmd, &pty.Winsize{Cols: 100, Rows: 30})
				_ = eventW.Close()
				_ = ackR.Close()
				if err != nil {
					return nil, nil, nil, err
				}
				return &backend{command: cmd, master: master, tty: tty, ack: ackW, pty: true, processGroup: true}, eventR, master, nil
			}
			manualReady := make(chan struct{})
			outputDone := make(chan string, 1)
			go func() {
				var output strings.Builder
				buf := make([]byte, 4096)
				manualSeen, promptSeen := false, false
				for {
					n, err := terminal.Read(buf)
					output.Write(buf[:n])
					if !manualSeen && strings.Contains(output.String(), "dots add keeps running") {
						manualSeen = true
						close(manualReady)
					}
					if !promptSeen && strings.Contains(output.String(), "fixture prompt ready") {
						promptSeen = true
						_, _ = io.WriteString(terminal, handoffFixtureInput)
					}
					if err != nil {
						outputDone <- output.String()
						return
					}
				}
			}()
			returned := false
			runDashboard = func(events <-chan ui.Event, control io.Writer, _ string, _ bool) error {
				encoder := json.NewEncoder(control)
				for event := range events {
					switch {
					case event.Kind == "stage_start" && event.ID == "prepare":
						if scenario != "manual ready arrives late" {
							_ = encoder.Encode(controlRecord{V: 1, Kind: "terminal_ready"})
							select {
							case <-manualReady:
							case <-time.After(3 * time.Second):
								return errors.New("manual terminal did not start")
							}
						}
						if err := os.WriteFile(filepath.Join(dir, "start"), nil, 0o600); err != nil {
							return err
						}
					case event.Kind == "stage_start" && event.ID == "prompt":
						if scenario == "renderer fails" {
							return errors.New("injected renderer failure during handover")
						}
						// A stale manual-ready record must not steal the automatic
						// prompt, and duplicate readiness must not ACK it twice.
						for _, record := range []controlRecord{
							{V: 1, Kind: "terminal_ready"},
							{V: 1, Kind: "handoff_ready", ID: event.ID},
							{V: 1, Kind: "handoff_ready", ID: event.ID},
						} {
							if err := encoder.Encode(record); err != nil {
								return err
							}
						}
					case event.Kind == "terminal_end":
						return errors.New("automatic prompt resumed the manual view")
					case event.Kind == "handoff_end":
						returned = true
						if err := encoder.Encode(controlRecord{V: 1, Kind: "handoff_ack", ID: event.ID}); err != nil {
							return err
						}
					}
				}
				return nil
			}
			if code := Run(Options{Root: t.TempDir(), StateDir: filepath.Join(dir, "state"), Command: "add"}); code != 0 {
				t.Fatalf("handover exited with code %d", code)
			}
			if starts != 1 {
				t.Fatalf("started %d backends, want one", starts)
			}
			if scenario != "renderer fails" && !returned {
				t.Fatal("automatic prompt did not restore the dashboard")
			}
			input, err := os.ReadFile(filepath.Join(dir, "input"))
			if err != nil || string(input) != handoffFixtureInput {
				t.Fatalf("prompt input = %q, err = %v", input, err)
			}
			output := <-outputDone
			if scenario != "manual ready arrives late" {
				footerEnd := strings.Index(output, "\x1b[r\x1b[30;1H\x1b[2K")
				prompt := strings.Index(output, "fixture prompt ready")
				if footerEnd < 0 || prompt < footerEnd {
					t.Fatal("manual footer and scrolling margins were not cleared before the prompt")
				}
			}
		})
	}
}

func TestHandoffFixtureProcess(t *testing.T) {
	dir := os.Getenv("DOTS_HANDOFF_FIXTURE")
	if dir == "" {
		return
	}
	if _, err := term.MakeRaw(os.Stdin.Fd()); err != nil {
		os.Exit(2)
	}
	events := json.NewEncoder(os.NewFile(3, "events"))
	_ = events.Encode(ui.Event{V: 1, Kind: "run_start"})
	_ = events.Encode(ui.Event{V: 1, Kind: "stage_start", ID: "prepare"})
	deadline := time.Now().Add(3 * time.Second)
	for {
		if _, err := os.Stat(filepath.Join(dir, "start")); err == nil {
			break
		}
		if time.Now().After(deadline) {
			os.Exit(3)
		}
		time.Sleep(time.Millisecond)
	}
	_ = events.Encode(ui.Event{V: 1, Kind: "stage_start", ID: "prompt", Terminal: "handoff"})
	if !fixtureReadable(4, 3*time.Second) {
		os.Exit(4)
	}
	ackFile := os.NewFile(4, "ack")
	ack := make([]byte, len("go:prompt\n"))
	if _, err := io.ReadFull(ackFile, ack); err != nil || string(ack) != "go:prompt\n" {
		os.Exit(5)
	}
	fmt.Print("fixture prompt ready\r\n")
	var input []byte
	for len(input) < len(handoffFixtureInput) {
		if !fixtureReadable(0, 3*time.Second) {
			os.Exit(6)
		}
		buf := make([]byte, 256)
		n, err := unix.Read(0, buf)
		if err != nil {
			os.Exit(7)
		}
		input = append(input, buf[:n]...)
	}
	if fixtureReadable(4, 100*time.Millisecond) {
		os.Exit(8) // Duplicate ACK would allow a later prompt to run prematurely.
	}
	_ = ackFile.Close()
	if err := os.WriteFile(filepath.Join(dir, "input"), input, 0o600); err != nil {
		os.Exit(9)
	}
	_ = events.Encode(ui.Event{V: 1, Kind: "stage_end", ID: "prompt", Status: "ok"})
	_ = events.Encode(ui.Event{V: 1, Kind: "run_end", ExitCode: 0})
	os.Exit(0)
}

func fixtureReadable(fd int, wait time.Duration) bool {
	var readable unix.FdSet
	readable.Set(fd)
	timeout := unix.NsecToTimeval(int64(wait))
	n, err := unix.Select(fd+1, &readable, nil, nil, &timeout)
	return err == nil && n > 0
}
