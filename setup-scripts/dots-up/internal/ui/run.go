package ui

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"

	tea "charm.land/bubbletea/v2"
)

// Run displays the dashboard on the controlling terminal. The caller owns the
// update process and sends version 1 events; Run only renders and acknowledges
// terminal handoffs. It returns after dismissal, in no-wait mode, or after
// cancellation completes.
func Run(events <-chan Event, control io.Writer, stateDir string, noWait bool) error {
	tty, err := os.OpenFile("/dev/tty", os.O_RDWR, 0)
	if err != nil {
		return fmt.Errorf("open dashboard terminal: %w", err)
	}
	defer tty.Close()
	model := NewModel(stateDir, noWait)
	model.intents = make(chan string, 4)
	p := tea.NewProgram(model, tea.WithInput(tty), tea.WithOutput(tty))
	type result struct{ err error }
	done := make(chan result, 1)
	go func() { _, err := p.Run(); done <- result{err} }()
	encoder := json.NewEncoder(control)
	discardTerminalRequests := func() error {
		for {
			select {
			case intent := <-model.intents:
				if intent != "terminal_request" {
					if err := encoder.Encode(controlRecord{V: 1, Kind: intent}); err != nil {
						return err
					}
				}
			default:
				return nil
			}
		}
	}
	var handoffID string
	command := "up"
	var released, manual, sawEnd bool
	defer func() {
		if released {
			_ = p.RestoreTerminal()
		}
		p.Quit()
	}()
	for {
		select {
		case outcome := <-done:
			return outcome.err
		case intent := <-model.intents:
			if intent == "terminal_request" {
				if released {
					// Discard requests queued before a manual or automatic release.
					// The matching end event will allow another manual request.
					continue
				}
				if err := p.ReleaseTerminal(); err != nil {
					return fmt.Errorf("release dashboard for manual terminal: %w", err)
				}
				released, manual = true, true
				fmt.Fprintf(tty, "\nTerminal view — ← / Esc / q return to the dashboard; dots %s keeps running (Ctrl+] also works).\n\n", command)
				if err := encoder.Encode(controlRecord{V: 1, Kind: "terminal_ready"}); err != nil {
					return err
				}
				continue
			}
			if err := encoder.Encode(controlRecord{V: 1, Kind: intent}); err != nil {
				return err
			}
		case e, open := <-events:
			if !open {
				events = nil
				if !sawEnd {
					p.Send(Event{V: 1, Kind: "notice", Severity: "error", Summary: "Update event stream closed before completion."})
					p.Send(Event{V: 1, Kind: "run_end", ExitCode: 1})
				}
				continue
			}
			if e.V != 1 {
				return fmt.Errorf("unsupported dashboard event version %d", e.V)
			}
			if e.Kind == "run_end" {
				sawEnd = true
			}
			if e.Kind == "run_start" && e.Command != "" {
				command = cleanLine(e.Command)
			}
			switch {
			case e.Kind == "stage_start" && e.Terminal == "handoff":
				if released && !manual {
					return errors.New("nested terminal handoff")
				}
				p.Send(e)
				// Earlier model updates have now completed. Drop their pending
				// requests so none can reopen a manual view after this prompt ends.
				if err := discardTerminalRequests(); err != nil {
					return err
				}
				if !released {
					if err := p.ReleaseTerminal(); err != nil {
						return fmt.Errorf("release dashboard terminal: %w", err)
					}
				}
				released, manual, handoffID = true, false, e.ID
				fmt.Fprintf(tty, "\n%s — terminal input is now available for this step.\n", e.Label)
				if err := encoder.Encode(controlRecord{V: 1, Kind: "handoff_ready", ID: e.ID}); err != nil {
					return err
				}
			case e.Kind == "terminal_end":
				if !released || !manual {
					return errors.New("unexpected manual terminal end")
				}
				if err := p.RestoreTerminal(); err != nil {
					return fmt.Errorf("restore dashboard after manual terminal: %w", err)
				}
				released, manual = false, false
				p.Send(e)
				if err := encoder.Encode(controlRecord{V: 1, Kind: "terminal_ack"}); err != nil {
					return err
				}
			case e.Kind == "handoff_end":
				if !released || manual || e.ID != handoffID {
					return fmt.Errorf("unexpected terminal handoff end %q", e.ID)
				}
				if err := p.RestoreTerminal(); err != nil {
					return fmt.Errorf("restore dashboard terminal: %w", err)
				}
				released, handoffID = false, ""
				p.Send(e)
				if err := encoder.Encode(controlRecord{V: 1, Kind: "handoff_ack", ID: e.ID}); err != nil {
					return err
				}
			default:
				p.Send(e)
			}
		}
	}
}
