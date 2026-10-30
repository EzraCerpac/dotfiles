package supervisor

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/EzraCerpac/dotfiles/setup-scripts/dots-up/internal/ui"
	"github.com/charmbracelet/x/ansi"
	"github.com/charmbracelet/x/term"
	"github.com/creack/pty"
	"golang.org/x/sys/unix"
)

type Options struct {
	Root, StateDir              string
	Command                     string
	Args                        []string
	Sensitive                   bool
	Concise                     bool
	MAS, Plain, Verbose, NoWait bool
	Last                        bool
}

type controlRecord struct {
	V    int    `json:"v"`
	Kind string `json:"kind"`
	ID   string `json:"id,omitempty"`
}

type backend struct {
	command        *exec.Cmd
	master         *os.File
	tty            *os.File
	ack            *os.File
	streamNonce    string
	pty            bool
	processGroup   bool
	directTerminal bool
}

type relayState struct {
	active    atomic.Bool
	manual    atomic.Bool
	inputSent atomic.Bool
	inputMu   sync.Mutex
}

var (
	hasInteractiveTerminal = interactiveTerminal
	currentTerminalSize    = terminalSize
	startUpdaterBackend    = startBackend
	runDashboard           = ui.Run
)

func Run(opts Options) int {
	if opts.Command == "" {
		opts.Command = "up"
	}
	if opts.StateDir == "" {
		opts.StateDir = commandStateDir(opts.Command)
	}
	started := time.Now()
	files, err := newRunFiles(started, opts.StateDir)
	if err != nil {
		fmt.Fprintf(os.Stderr, "dots up: reports unavailable: %v\nContinuing without saved logs.\n", err)
	}
	if files != nil {
		files.report.Command = opts.Command
		defer func() {
			if files.eventLog != nil {
				_ = files.eventLog.Close()
			}
		}()
	}

	stateRoot := stateDir()
	if opts.StateDir != "" {
		stateRoot = opts.StateDir
	}
	interactive := hasInteractiveTerminal()
	dashboard := interactive && !opts.Plain && !opts.Verbose && !opts.Concise
	if dashboard {
		width, height := currentTerminalSize()
		if width < 64 || height < 16 {
			dashboard = false
		}
	}
	plain := !dashboard
	if opts.Verbose {
		plain = true
	}
	if interactive && !dashboard && !opts.Verbose && !opts.Plain && !opts.Concise {
		fmt.Fprintln(os.Stderr, "dots up: terminal is too small for the dashboard; using concise output")
	}

	backend, eventReader, outputReader, err := startUpdaterBackend(opts, files, interactive)
	if err != nil {
		fmt.Fprintf(os.Stderr, "dots up: start updater: %v\n", err)
		return 127
	}
	if dashboard && !backend.pty {
		dashboard, plain = false, true
		fmt.Fprintln(os.Stderr, "dots up: pseudoterminal unavailable; using concise terminal output")
	}
	var originalTerminalState *term.State
	if backend.tty != nil {
		originalTerminalState, _ = term.GetState(backend.tty.Fd())
	}
	var events chan ui.Event
	var uiDone chan error
	var controlReader *io.PipeReader
	var controlWriter *io.PipeWriter
	controls := make(chan controlRecord, 16)
	if dashboard {
		events = make(chan ui.Event, 512)
		controlReader, controlWriter = io.Pipe()
		uiDone = make(chan error, 1)
		go func() {
			err := runDashboard(events, controlWriter, stateRoot, opts.NoWait)
			_ = controlWriter.Close()
			uiDone <- err
		}()
		go readControls(controlReader, controls)
	}
	dashboardStarted := dashboard
	defer func() {
		if originalTerminalState != nil && backend.tty != nil {
			_ = term.Restore(backend.tty.Fd(), originalTerminalState)
		}
		if backend.master != nil {
			_ = backend.master.Close()
		}
		if backend.tty != nil {
			_ = backend.tty.Close()
		}
		if backend.ack != nil {
			_ = backend.ack.Close()
		}
	}()

	backendEvents := make(chan ui.Event, 32)
	eventErr := make(chan error, 1)
	if backend.streamNonce == "" {
		go readEvents(eventReader, backendEvents, eventErr)
	} else {
		_ = eventReader.Close()
		close(backendEvents)
	}
	backendOutput := make(chan outputRecord, 32)
	if outputReader == nil {
		close(backendOutput)
	} else {
		go readOutput(outputReader, backend.streamNonce, backendOutput)
	}
	waitCh := make(chan error, 1)
	go func() { waitCh <- backend.command.Wait() }()

	var stageLog *os.File
	var stageID, profile, host string
	var runEndSeen, childFinished, outputFinished bool
	eventFinished := backend.streamNonce != ""
	var exitCode int
	var waitErr error
	var backendError error
	var pendingHandoff string
	var relayKind string
	var terminalState *term.State
	var deferredStageEnd *ui.Event
	var restoreKind, restoreID string
	var restorePending bool
	var deferredUIEvents []ui.Event
	var cancelRequested bool
	var uiAlive = dashboard

	var eventInput <-chan ui.Event
	if backend.streamNonce == "" {
		eventInput = backendEvents
	}
	var outputInput <-chan outputRecord = backendOutput
	var uiInput <-chan error = uiDone
	var uiExited bool
	var uiErr error
	manualEnd := make(chan struct{}, 1)
	var inputStart chan struct{}
	var signals = make(chan os.Signal, 1)
	signal.Notify(signals, os.Interrupt, syscall.SIGTERM, syscall.SIGWINCH)
	defer signal.Stop(signals)
	var relay relayState
	if backend.pty && backend.tty != nil && backend.master != nil {
		inputStart = make(chan struct{}, 1)
		go relayTerminalInput(backend.tty, backend.master, &relay, inputStart, manualEnd)
	}

	var globalLog *os.File
	if !opts.Sensitive {
		globalLog = openLog(files, "backend.log")
	}
	defer func() {
		if globalLog != nil {
			_ = globalLog.Close()
		}
		if stageLog != nil {
			_ = stageLog.Close()
		}
		if controlReader != nil {
			_ = controlReader.Close()
		}
	}()

	deliver := func(e ui.Event) {
		if uiAlive && events != nil {
			select {
			case events <- e:
			default:
				uiAlive, dashboard, plain = false, false, true
				fmt.Fprintln(os.Stderr, "dots up: dashboard stopped responding; continuing in concise mode")
			}
		}
		if plain && !opts.Verbose {
			printProgress(e)
		}
	}
	emit := func(e ui.Event) {
		if e.V == 0 {
			e.V = 1
		}
		if e.Kind == "run_start" {
			e.Command = opts.Command
		}
		if opts.Sensitive {
			e.LogPath = ""
		}
		if files != nil {
			if err := files.record(e); err != nil {
				fmt.Fprintf(os.Stderr, "dots up: report log: %v\n", err)
			}
		}
		if restorePending && e.Kind != "handoff_end" && e.Kind != "terminal_end" {
			deferredUIEvents = append(deferredUIEvents, e)
			return
		}
		deliver(e)
	}
	startRelay := func(kind string) error {
		if !backend.pty || backend.tty == nil {
			return errors.New("terminal handoff needs an interactive pseudoterminal")
		}
		state, err := term.MakeRaw(backend.tty.Fd())
		if err != nil {
			return fmt.Errorf("enable terminal input: %w", err)
		}
		terminalState = state
		relay.manual.Store(kind == "manual")
		relay.inputSent.Store(false)
		relay.active.Store(true)
		select {
		case inputStart <- struct{}{}:
		default:
		}
		relayKind = kind
		return nil
	}
	stopRelay := func() error {
		relay.active.Store(false)
		relay.inputMu.Lock()
		relay.inputMu.Unlock()
		if terminalState == nil || backend.tty == nil {
			return nil
		}
		err := term.Restore(backend.tty.Fd(), terminalState)
		terminalState = nil
		return err
	}
	ackChild := func(id string) error {
		if backend.ack == nil {
			return nil
		}
		if _, err := io.WriteString(backend.ack, "go:"+id+"\n"); err != nil {
			return fmt.Errorf("acknowledge terminal handoff: %w", err)
		}
		return nil
	}
	finishStage := func(e ui.Event) {
		if stageLog != nil && stageID == e.ID {
			_ = stageLog.Sync()
			_ = stageLog.Close()
			stageLog = nil
		}
		if e.LogPath == "" && files != nil {
			e.LogPath = files.logPath(e.ID)
		}
		emit(e)
		stageID = ""
	}
	beginRestore := func(kind, id string, endEvent ui.Event, finishStageAfter bool) {
		if endEvent.Kind != "" {
			deferredStageEnd = &endEvent
		}
		restoreKind, restoreID = kind, id
		restorePending = true
		eventInput = nil
		if backend.streamNonce != "" {
			outputInput = nil
		}
		if kind == "auto" {
			emit(ui.Event{V: 1, Kind: "handoff_end", ID: id})
		} else {
			emit(ui.Event{V: 1, Kind: "terminal_end"})
		}
		if !finishStageAfter {
			deferredStageEnd = nil
		}
	}
	finishRestore := func() {
		if deferredStageEnd != nil {
			finishStage(*deferredStageEnd)
			deferredStageEnd = nil
		}
		restoreKind, restoreID, restorePending = "", "", false
		if backend.streamNonce == "" {
			eventInput = backendEvents
		} else if !outputFinished {
			outputInput = backendOutput
		}
		for _, e := range deferredUIEvents {
			deliver(e)
		}
		deferredUIEvents = nil
	}
	handleEvent := func(e ui.Event) {
		if e.V != 1 {
			backendError = fmt.Errorf("unsupported updater event version %d", e.V)
			return
		}
		switch e.Kind {
		case "run_start":
			profile, host = e.Profile, e.Host
			emit(e)
		case "stage_start":
			if stageLog != nil {
				_ = stageLog.Close()
				stageLog = nil
			}
			stageID = e.ID
			if files != nil && !opts.Sensitive {
				e.LogPath = files.logPath(e.ID)
				stageLog = openStageLog(e.LogPath)
			}
			emit(e)
			if e.Terminal == "handoff" && backend.pty {
				pendingHandoff = e.ID
				if !dashboard {
					if err := startRelay("auto"); err != nil {
						backendError = err
						cancelRequested = true
						cancelBackend(backend)
					} else if err := ackChild(e.ID); err != nil {
						backendError = err
					}
				}
			}
		case "stage_end":
			if e.LogPath == "" && files != nil {
				e.LogPath = files.logPath(e.ID)
			}
			if pendingHandoff == e.ID {
				if relayKind == "auto" {
					if err := stopRelay(); err != nil {
						backendError = err
					}
				}
				pendingHandoff, relayKind = "", ""
				if dashboard {
					beginRestore("auto", e.ID, e, true)
					return
				}
			}
			if relayKind == "manual" {
				if err := stopRelay(); err != nil {
					backendError = err
				}
				relayKind, pendingHandoff = "", ""
				beginRestore("manual", "manual", e, true)
				return
			}
			finishStage(e)
		case "run_end":
			runEndSeen, exitCode = true, e.ExitCode
			emit(e)
		default:
			if (e.Kind == "app_store_start" || e.Kind == "app_store_end") && e.LogPath != "" && files != nil && !inside(files.runDir, e.LogPath) {
				e.LogPath = ""
			}
			emit(e)
		}
	}
	finishExitedHandoff := func() {
		if !childFinished || !outputFinished || pendingHandoff == "" {
			return
		}
		id := pendingHandoff
		if relayKind != "" {
			if err := stopRelay(); err != nil {
				backendError = err
			}
		}
		pendingHandoff, relayKind = "", ""
		if id == "manual" {
			if dashboard {
				beginRestore("manual", "manual", ui.Event{}, false)
			}
			return
		}
		status := "attention"
		summaryText := "Updater exited before this step reported a result."
		if exitCode != 0 {
			status = "failed"
			summaryText = fmt.Sprintf("Updater exited with code %d before this step reported a result.", exitCode)
		}
		end := ui.Event{V: 1, Kind: "stage_end", ID: id, Status: status, ExitCode: exitCode, Summary: summaryText, Action: "Review the stage log and rerun dots up."}
		if dashboard {
			beginRestore("auto", id, end, true)
		} else {
			finishStage(end)
		}
	}

	for !(childFinished && eventFinished && outputFinished && !restorePending) {
		select {
		case e, ok := <-eventInput:
			if !ok {
				eventFinished = true
				eventInput = nil
				continue
			}
			handleEvent(e)
		case control := <-controls:
			switch control.Kind {
			case "cancel":
				if !cancelRequested && !childFinished {
					cancelRequested = true
					cancelBackend(backend)
				}
			case "handoff_ready":
				if dashboard && pendingHandoff == control.ID && relayKind == "" {
					if err := startRelay("auto"); err != nil {
						backendError = err
						cancelRequested = true
						cancelBackend(backend)
					} else if err := ackChild(control.ID); err != nil {
						backendError = err
					}
				}
			case "handoff_ack":
				if restorePending && restoreKind == "auto" && restoreID == control.ID {
					finishRestore()
				}
			case "terminal_request":
				// The UI releases the terminal before sending terminal_ready.
			case "terminal_ready":
				if dashboard && backend.pty && relayKind == "" {
					if err := startRelay("manual"); err != nil {
						backendError = err
					} else {
						pendingHandoff = "manual"
					}
				}
			case "terminal_ack":
				if restorePending && restoreKind == "manual" {
					finishRestore()
				}
			}
		case item, ok := <-outputInput:
			if !ok {
				outputFinished = true
				outputInput = nil
				finishExitedHandoff()
				continue
			}
			if item.err != nil {
				backendError = item.err
			}
			if item.event != nil {
				handleEvent(*item.event)
				continue
			}
			b := item.bytes
			clean := cleanTerminalOutput(b)
			if relayKind != "" && backend.tty != nil {
				_, _ = backend.tty.Write(b)
				// Before the first keypress, prompts and diagnostic text are useful.
				// Once input begins, stop logging PTY output so terminal echo cannot
				// persist anything the user typed.
				if !relay.inputSent.Load() {
					writeLog(stageLog, globalLog, clean)
				}
				continue
			}
			writeLog(stageLog, globalLog, clean)
			if opts.Verbose && len(b) > 0 {
				_, _ = os.Stdout.Write(b)
			}
		case err := <-eventErr:
			if err != nil {
				backendError = err
			}
		case err := <-waitCh:
			waitCh = nil
			childFinished, waitErr = true, err
			if err != nil {
				exitCode = childExitCode(err)
			}
			if cancelRequested {
				exitCode = 130
				if opts.Command == "remote" {
					emit(ui.Event{V: 1, Kind: "notice", Severity: "attention", Summary: "Remote execution status is unknown after local cancellation; inspect the host before retrying.", Action: "Check the remote host before retrying; local cancellation does not confirm remote termination."})
				}
			}
			if relayKind != "" {
				_ = stopRelay()
			}
			if backend.ack != nil {
				_ = backend.ack.Close()
				backend.ack = nil
			}
			finishExitedHandoff()
		case err := <-uiInput:
			uiInput = nil
			uiExited, uiErr = true, err
			if err != nil || !childFinished {
				if dashboard {
					fmt.Fprintf(os.Stderr, "dots up: dashboard unavailable (%v); continuing in concise mode\n", err)
				}
				uiAlive, dashboard, plain = false, false, true
				if restorePending {
					finishRestore()
				}
				if relayKind == "manual" {
					_ = stopRelay()
					relayKind, pendingHandoff = "", ""
				}
				if pendingHandoff != "" && relayKind == "" && backend.pty {
					if err := startRelay("auto"); err == nil {
						relayKind = "auto"
						_ = ackChild(pendingHandoff)
					}
				}
			}
		case sig := <-signals:
			if sig == syscall.SIGWINCH && backend.pty && backend.tty != nil && backend.master != nil {
				_ = pty.InheritSize(backend.tty, backend.master)
				continue
			}
			if !childFinished {
				cancelRequested = true
				cancelBackend(backend)
			}
		case <-manualEnd:
			if relayKind == "manual" && dashboard {
				if err := stopRelay(); err != nil {
					backendError = err
				}
				relayKind, pendingHandoff = "", ""
				beginRestore("manual", "manual", ui.Event{}, false)
			}
		}
	}

	if terminalState != nil {
		_ = stopRelay()
	}
	if stageLog != nil {
		_ = stageLog.Sync()
		_ = stageLog.Close()
	}
	if waitErr != nil && exitCode == 0 {
		exitCode = childExitCode(waitErr)
	}
	if backendError != nil && exitCode == 0 {
		exitCode = 1
	}
	if !runEndSeen {
		emit(ui.Event{V: 1, Kind: "run_end", ExitCode: exitCode, DurationMS: time.Since(started).Milliseconds()})
	}
	if files != nil {
		_ = files.finish(exitCode, profile, host, time.Now())
	}
	if events != nil {
		close(events)
	}
	if uiDone != nil && !uiExited {
		uiErr = <-uiDone
		uiExited = true
	}
	if uiErr != nil {
		fmt.Fprintf(os.Stderr, "dots up: dashboard ended with an error: %v\n", uiErr)
	}
	if plain && !opts.Verbose {
		if files != nil {
			fmt.Println(summary(files.report, files.runDir))
			printReportHighlights(os.Stdout, files.report)
		} else {
			fmt.Printf("Update completed with exit code %d.\n", exitCode)
		}
	} else if dashboardStarted && files != nil {
		fmt.Println(summary(files.report, files.runDir))
		printReportHighlights(os.Stdout, files.report)
	}
	if backendError != nil {
		fmt.Fprintf(os.Stderr, "dots up: supervisor warning: %v\n", backendError)
	}
	return exitCode
}

func startBackend(opts Options, files *runFiles, interactive bool) (*backend, *os.File, io.Reader, error) {
	eventR, eventW, err := os.Pipe()
	if err != nil {
		return nil, nil, nil, err
	}
	ackR, ackW, err := os.Pipe()
	if err != nil {
		_ = eventR.Close()
		_ = eventW.Close()
		return nil, nil, nil, err
	}
	cmd, err := updaterCommand(opts)
	if err != nil {
		return nil, nil, nil, err
	}
	if opts.MAS {
		cmd.Args = append(cmd.Args, "--mas")
	}
	childEnv := append([]string(nil), os.Environ()...)
	childEnv = setEnv(childEnv, "DOTS_UP_EVENT_FD", "3")
	childEnv = setEnv(childEnv, "DOTS_UP_ACK_FD", "")
	childEnv = setEnv(childEnv, "DOTS_UP_RUN_STARTED", "")
	childEnv = setEnv(childEnv, "DOTS_UP_RUN_DIR", "")
	childEnv = setEnv(childEnv, "DOTS_UP_PLAIN", "")
	childEnv = setEnv(childEnv, "DOTS_UP_VERBOSE", "")
	if opts.Plain || !interactive {
		childEnv = setEnv(childEnv, "DOTS_UP_PLAIN", "1")
	}
	if opts.Verbose {
		childEnv = setEnv(childEnv, "DOTS_UP_VERBOSE", "1")
	}
	if files != nil {
		childEnv = setEnv(childEnv, "DOTS_UP_RUN_DIR", files.runDir)
	}

	var tty *os.File
	ptyMode := interactive
	if ptyMode {
		tty, err = os.OpenFile("/dev/tty", os.O_RDWR, 0)
		if err != nil || !term.IsTerminal(tty.Fd()) {
			ptyMode = false
			if tty != nil {
				_ = tty.Close()
				tty = nil
			}
		}
	}
	streamNonce := ""
	if ptyMode {
		streamNonce, err = newStreamNonce()
		if err != nil {
			_ = eventR.Close()
			_ = eventW.Close()
			_ = ackR.Close()
			_ = ackW.Close()
			if tty != nil {
				_ = tty.Close()
			}
			return nil, nil, nil, err
		}
		childEnv = setEnv(childEnv, "DOTS_UP_STREAM_NONCE", streamNonce)
		childEnv = setEnv(childEnv, "DOTS_UP_EVENT_FD", "")
	}
	cmd.ExtraFiles = []*os.File{eventW}
	if ptyMode {
		childEnv = setEnv(childEnv, "DOTS_UP_ACK_FD", "4")
		cmd.ExtraFiles = []*os.File{eventW, ackR}
		cmd.Env = childEnv
		width, height := terminalSize()
		master, startErr := pty.StartWithSize(cmd, &pty.Winsize{Cols: uint16(max(1, width)), Rows: uint16(max(1, height))})
		if startErr == nil {
			_ = pty.InheritSize(tty, master)
			_ = eventW.Close()
			_ = ackR.Close()
			return &backend{command: cmd, master: master, tty: tty, ack: ackW, streamNonce: streamNonce, pty: true, processGroup: true}, eventR, master, nil
		}
		// Keep maintenance available even when the host cannot allocate a PTY.
		fmt.Fprintf(os.Stderr, "dots up: pseudoterminal unavailable (%v); using the current terminal directly\n", startErr)
		_ = tty.Close()
		tty = nil
		childEnv = setEnv(childEnv, "DOTS_UP_STREAM_NONCE", "")
		childEnv = setEnv(childEnv, "DOTS_UP_EVENT_FD", "3")
		cmd.ExtraFiles = []*os.File{eventW}
		cmd.Env = setEnv(childEnv, "DOTS_UP_ACK_FD", "")
		cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
		cmd.SysProcAttr = nil
		if err := cmd.Start(); err != nil {
			_ = eventR.Close()
			_ = eventW.Close()
			_ = ackR.Close()
			_ = ackW.Close()
			return nil, nil, nil, err
		}
		_ = eventW.Close()
		_ = ackR.Close()
		_ = ackW.Close()
		return &backend{command: cmd, directTerminal: true}, eventR, nil, nil
	}

	streamNonce, err = newStreamNonce()
	if err != nil {
		_ = eventR.Close()
		_ = eventW.Close()
		_ = ackR.Close()
		_ = ackW.Close()
		return nil, nil, nil, err
	}
	childEnv = setEnv(childEnv, "DOTS_UP_STREAM_NONCE", streamNonce)
	childEnv = setEnv(childEnv, "DOTS_UP_EVENT_FD", "")
	childEnv = setEnv(childEnv, "DOTS_UP_ACK_FD", "")
	cmd.Env = childEnv
	cmd.ExtraFiles = nil
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	var outputR, outputW *os.File
	outputR, outputW, err = os.Pipe()
	if err != nil {
		_ = eventR.Close()
		_ = eventW.Close()
		_ = ackR.Close()
		_ = ackW.Close()
		return nil, nil, nil, err
	}
	cmd.Stdin = nil
	if interactive {
		cmd.Stdin = os.Stdin
	}
	cmd.Stdout, cmd.Stderr = outputW, outputW
	if err := cmd.Start(); err != nil {
		_ = eventR.Close()
		_ = eventW.Close()
		_ = ackR.Close()
		_ = ackW.Close()
		_ = outputR.Close()
		_ = outputW.Close()
		return nil, nil, nil, err
	}
	_ = eventW.Close()
	_ = ackR.Close()
	_ = ackW.Close()
	_ = outputW.Close()
	return &backend{command: cmd, streamNonce: streamNonce, processGroup: true}, eventR, outputR, nil
}

func updaterCommand(opts Options) (*exec.Cmd, error) {
	if runner := os.Getenv("DOTS_UP_RUNNER"); runner != "" {
		if !filepath.IsAbs(runner) {
			return nil, fmt.Errorf("DOTS_UP_RUNNER must be absolute: %s", runner)
		}
		cmd := exec.Command(runner)
		if opts.Command != "" && opts.Command != "up" {
			cmd.Args = append(cmd.Args, opts.Command)
		}
		cmd.Args = append(cmd.Args, opts.Args...)
		return cmd, nil
	}
	mise := os.Getenv("DOTS_MISE_BIN")
	if mise == "" {
		candidate := filepath.Join(os.Getenv("HOME"), ".local", "bin", "mise")
		if _, err := os.Stat(candidate); err == nil {
			mise = candidate
		} else {
			var err error
			mise, err = exec.LookPath("mise")
			if err != nil {
				return nil, errors.New("mise executable was not found")
			}
		}
	}
	if opts.Command == "" || opts.Command == "up" {
		cmd := exec.Command(mise, "-C", opts.Root, "run", "setup:update")
		cmd.Args = append(cmd.Args, opts.Args...)
		return cmd, nil
	}
	args := []string{filepath.Join(opts.Root, "setup-scripts", "lib", "dots-command-backend"), mise, opts.Root, opts.Command}
	args = append(args, opts.Args...)
	return exec.Command("bash", args...), nil
}

func setEnv(env []string, key, value string) []string {
	out := env[:0]
	prefix := key + "="
	for _, entry := range env {
		if !strings.HasPrefix(entry, prefix) {
			out = append(out, entry)
		}
	}
	if value != "" {
		out = append(out, prefix+value)
	}
	return out
}

func readEvents(r *os.File, out chan<- ui.Event, errorsOut chan<- error) {
	defer close(out)
	defer r.Close()
	scanner := bufio.NewScanner(r)
	scanner.Buffer(make([]byte, 4096), 1024*1024)
	for scanner.Scan() {
		line := bytes.TrimSpace(scanner.Bytes())
		if len(line) == 0 {
			continue
		}
		var event ui.Event
		if err := json.Unmarshal(line, &event); err != nil {
			errorsOut <- fmt.Errorf("invalid updater event: %w", err)
			continue
		}
		out <- event
	}
	if err := scanner.Err(); err != nil {
		errorsOut <- fmt.Errorf("read updater events: %w", err)
	}
}

func readControls(r *io.PipeReader, out chan<- controlRecord) {
	defer r.Close()
	scanner := bufio.NewScanner(r)
	scanner.Buffer(make([]byte, 1024), 64*1024)
	for scanner.Scan() {
		var control controlRecord
		if json.Unmarshal(scanner.Bytes(), &control) == nil && control.V == 1 {
			out <- control
		}
	}
}

func readOutput(r io.Reader, nonce string, out chan<- outputRecord) {
	defer close(out)
	if closer, ok := r.(io.Closer); ok {
		defer closer.Close()
	}
	var decoder *eventStreamDecoder
	if nonce != "" {
		var err error
		decoder, err = newEventStreamDecoder(nonce)
		if err != nil {
			out <- outputRecord{err: err}
			return
		}
	}
	send := func(records []outputRecord) {
		for _, record := range records {
			out <- record
		}
	}
	buf := make([]byte, 32*1024)
	for {
		n, err := r.Read(buf)
		if n > 0 {
			if decoder == nil {
				out <- outputRecord{bytes: append([]byte(nil), buf[:n]...)}
			} else {
				send(decoder.feed(buf[:n]))
			}
		}
		if err != nil {
			if decoder != nil {
				send(decoder.flush())
			}
			return
		}
	}
}

func openLog(files *runFiles, name string) *os.File {
	if files == nil {
		return nil
	}
	f, err := os.OpenFile(filepath.Join(files.runDir, name), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		return nil
	}
	return f
}

func openStageLog(path string) *os.File {
	if path == "" {
		return nil
	}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if err != nil {
		return nil
	}
	return f
}

func writeLog(stage, global *os.File, data []byte) {
	if len(data) == 0 {
		return
	}
	if stage != nil {
		_, _ = stage.Write(data)
	} else if global != nil {
		_, _ = global.Write(data)
	}
}

func cleanTerminalOutput(data []byte) []byte {
	clean := ansi.Strip(string(data))
	clean = strings.ReplaceAll(clean, "\r\n", "\n")
	clean = strings.ReplaceAll(clean, "\r", "\n")
	return []byte(clean)
}

func printProgress(e ui.Event) {
	switch e.Kind {
	case "run_start":
		name := e.Command
		if name == "" {
			name = "up"
		}
		fmt.Printf("dots %s · %s · %s\n", name, e.Profile, e.Host)
	case "stage_start":
		fmt.Printf("→ %s\n", e.Label)
	case "stage_end":
		glyph := "✓"
		if e.Status == "failed" {
			glyph = "×"
		} else if e.Status == "attention" {
			glyph = "!"
		}
		fmt.Printf("%s %s", glyph, e.Label)
		if e.Summary != "" {
			fmt.Printf(" — %s", e.Summary)
		}
		fmt.Println()
	case "notice":
		fmt.Printf("Attention: %s\n", e.Summary)
	case "change":
		if e.Before != "" && e.After != "" {
			fmt.Printf("Change: %s %s → %s\n", e.Item, e.Before, e.After)
		}
	case "app_store_start":
		fmt.Println("Mac App Store updates · running in the background")
	case "app_store_end":
		fmt.Printf("Mac App Store updates · %s\n", e.Summary)
	}
}

func interactiveTerminal() bool {
	if os.Getenv("CI") != "" || os.Getenv("TERM") == "dumb" {
		return false
	}
	f, err := os.OpenFile("/dev/tty", os.O_RDWR, 0)
	if err != nil {
		return false
	}
	defer f.Close()
	return term.IsTerminal(f.Fd()) && term.IsTerminal(os.Stdin.Fd()) && term.IsTerminal(os.Stdout.Fd())
}

func terminalSize() (int, int) {
	f, err := os.OpenFile("/dev/tty", os.O_RDWR, 0)
	if err != nil {
		return 0, 0
	}
	defer f.Close()
	w, h, err := term.GetSize(f.Fd())
	if err != nil {
		return 0, 0
	}
	return w, h
}

func relayTerminalInput(tty, master *os.File, state *relayState, start <-chan struct{}, manualEnd chan<- struct{}) {
	buf := make([]byte, 256)
	for {
		select {
		case <-start:
		case <-time.After(80 * time.Millisecond):
			continue
		}
		manualReturn := false
		for {
			// Quiesce any in-flight terminal read before the dashboard restores terminal state.
			state.inputMu.Lock()
			if !state.active.Load() {
				state.inputMu.Unlock()
				break
			}
			fd := int(tty.Fd())
			var readable unix.FdSet
			readable.Set(fd)
			timeout := unix.NsecToTimeval(int64(100 * time.Millisecond))
			ready, err := unix.Select(fd+1, &readable, nil, nil, &timeout)
			if !state.active.Load() || err != nil || ready == 0 || !readable.IsSet(fd) {
				state.inputMu.Unlock()
				continue
			}
			n, err := unix.Read(fd, buf)
			if err != nil || n == 0 {
				state.inputMu.Unlock()
				continue
			}
			data := buf[:n]
			if state.manual.Load() {
				forwarding := make([]byte, 0, len(data))
				returned := false
				for _, b := range data {
					if b == 0x1d { // Ctrl+] returns to the dashboard.
						returned = true
						break
					}
					forwarding = append(forwarding, b)
				}
				data = forwarding
				if returned {
					state.active.Store(false)
					manualReturn = true
				}
			}
			if len(data) > 0 {
				state.inputSent.Store(true)
				_, _ = master.Write(data)
			}
			state.inputMu.Unlock()
			if manualReturn {
				select {
				case manualEnd <- struct{}{}:
				default:
				}
				break
			}
		}
	}
}

func cancelBackend(b *backend) {
	if b == nil || b.command == nil || b.command.Process == nil {
		return
	}
	cmd := b.command
	pid := cmd.Process.Pid
	kill := func(signal syscall.Signal) error {
		if b.processGroup {
			return syscall.Kill(-pid, signal)
		}
		return cmd.Process.Signal(signal)
	}
	_ = kill(syscall.SIGINT)
	go func() {
		time.Sleep(150 * time.Millisecond)
		if b.processGroup {
			if syscall.Kill(-pid, 0) != nil {
				return
			}
		} else if cmd.ProcessState != nil && cmd.ProcessState.Exited() {
			return
		}
		_ = kill(syscall.SIGTERM)
		time.Sleep(500 * time.Millisecond)
		_ = kill(syscall.SIGKILL)
	}()
}

func childExitCode(err error) int {
	if err == nil {
		return 0
	}
	var exit *exec.ExitError
	if errors.As(err, &exit) {
		if status, ok := exit.Sys().(syscall.WaitStatus); ok {
			if status.Signaled() {
				return 128 + int(status.Signal())
			}
			return status.ExitStatus()
		}
	}
	return 1
}

func uiRun(events <-chan ui.Event, stateRoot string, noWait bool, control io.Writer) error {
	if control == nil {
		control = io.Discard
	}
	return ui.Run(events, control, stateRoot, noWait)
}
