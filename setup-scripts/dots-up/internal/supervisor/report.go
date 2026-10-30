package supervisor

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/EzraCerpac/dotfiles/setup-scripts/dots-up/internal/ui"
)

type Report struct {
	Version    int        `json:"version"`
	ID         string     `json:"id"`
	Profile    string     `json:"profile,omitempty"`
	Host       string     `json:"host,omitempty"`
	StartedAt  time.Time  `json:"started_at"`
	FinishedAt time.Time  `json:"finished_at"`
	ExitCode   int        `json:"exit_code"`
	Events     []ui.Event `json:"events"`
}

type runFiles struct {
	stateDir string
	runDir   string
	eventLog *os.File
	report   Report
}

func stateDir() string {
	if path := os.Getenv("DOTS_UP_STATE_DIR"); path != "" {
		return path
	}
	base := os.Getenv("XDG_STATE_HOME")
	if base == "" {
		base = filepath.Join(os.Getenv("HOME"), ".local", "state")
	}
	return filepath.Join(base, "dots", "up")
}

func newRunFiles(now time.Time, stateRoot string) (*runFiles, error) {
	if stateRoot == "" {
		stateRoot = stateDir()
	}
	if !filepath.IsAbs(stateRoot) {
		return nil, fmt.Errorf("state directory must be absolute: %s", stateRoot)
	}
	if err := os.MkdirAll(stateRoot, 0o700); err != nil {
		return nil, fmt.Errorf("create update state directory: %w", err)
	}
	if err := os.Chmod(stateRoot, 0o700); err != nil {
		return nil, fmt.Errorf("secure update state directory: %w", err)
	}
	id := fmt.Sprintf("%s-%d", now.UTC().Format("20060102T150405Z"), os.Getpid())
	runDir := filepath.Join(stateRoot, id)
	if err := os.Mkdir(runDir, 0o700); err != nil {
		return nil, fmt.Errorf("create update report directory: %w", err)
	}
	if err := os.Mkdir(filepath.Join(runDir, "stages"), 0o700); err != nil {
		return nil, fmt.Errorf("create stage log directory: %w", err)
	}
	active, err := os.OpenFile(filepath.Join(runDir, ".active"), os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
	if err != nil {
		return nil, fmt.Errorf("mark active update report: %w", err)
	}
	_ = active.Close()
	events, err := os.OpenFile(filepath.Join(runDir, "events.jsonl"), os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
	if err != nil {
		return nil, fmt.Errorf("create update event log: %w", err)
	}
	return &runFiles{
		stateDir: stateRoot,
		runDir:   runDir,
		eventLog: events,
		report:   Report{Version: 1, ID: id, StartedAt: now.UTC(), Events: make([]ui.Event, 0, 64)},
	}, nil
}

func (r *runFiles) logPath(id string) string {
	id = safeID(id)
	if id == "" {
		id = "stage"
	}
	return filepath.Join(r.runDir, "stages", id+".log")
}

func safeID(s string) string {
	var b strings.Builder
	for _, r := range s {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '-' || r == '_' {
			b.WriteRune(r)
		}
	}
	return b.String()
}

func (r *runFiles) record(e ui.Event) error {
	if e.LogPath != "" && !inside(r.runDir, e.LogPath) {
		return errors.New("event log path escapes the update report directory")
	}
	if err := json.NewEncoder(r.eventLog).Encode(e); err != nil {
		return fmt.Errorf("write update event log: %w", err)
	}
	r.report.Events = append(r.report.Events, e)
	return nil
}

func (r *runFiles) finish(code int, profile, host string, now time.Time) error {
	r.report.Profile = profile
	r.report.Host = host
	r.report.ExitCode = code
	r.report.FinishedAt = now.UTC()
	if err := r.eventLog.Sync(); err != nil {
		return fmt.Errorf("sync update event log: %w", err)
	}
	if err := r.eventLog.Close(); err != nil {
		return fmt.Errorf("close update event log: %w", err)
	}
	path := filepath.Join(r.runDir, "report.json")
	data, err := json.MarshalIndent(r.report, "", "  ")
	if err != nil {
		return fmt.Errorf("encode update report: %w", err)
	}
	if err := writePrivate(path, data); err != nil {
		return fmt.Errorf("write update report: %w", err)
	}
	if err := os.Remove(filepath.Join(r.runDir, ".active")); err != nil && !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("mark update report complete: %w", err)
	}
	return pruneReports(r.stateDir, 10)
}

func writePrivate(path string, data []byte) error {
	tmp, err := os.CreateTemp(filepath.Dir(path), ".report-*.tmp")
	if err != nil {
		return err
	}
	name := tmp.Name()
	defer os.Remove(name)
	if err := tmp.Chmod(0o600); err != nil {
		_ = tmp.Close()
		return err
	}
	if _, err := tmp.Write(data); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Sync(); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(name, path)
}

func inside(root, path string) bool {
	if !filepath.IsAbs(path) {
		return false
	}
	rel, err := filepath.Rel(root, path)
	return err == nil && rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))
}

func pruneReports(root string, keep int) error {
	entries, err := os.ReadDir(root)
	if err != nil {
		return err
	}
	type saved struct {
		path string
		when time.Time
	}
	completed := make([]saved, 0, len(entries))
	for _, entry := range entries {
		if !entry.IsDir() || entry.Type()&os.ModeSymlink != 0 {
			continue
		}
		path := filepath.Join(root, entry.Name())
		if _, err := os.Stat(filepath.Join(path, ".active")); err == nil {
			continue
		}
		report, err := readReport(path)
		if err != nil || report.FinishedAt.IsZero() {
			continue
		}
		completed = append(completed, saved{path: path, when: report.FinishedAt})
	}
	sort.Slice(completed, func(i, j int) bool { return completed[i].when.After(completed[j].when) })
	for _, item := range completed[min(keep, len(completed)):] {
		if err := os.RemoveAll(item.path); err != nil {
			return fmt.Errorf("remove old update report %s: %w", filepath.Base(item.path), err)
		}
	}
	return nil
}

func readReport(dir string) (Report, error) {
	var report Report
	data, err := os.ReadFile(filepath.Join(dir, "report.json"))
	if err != nil {
		return report, err
	}
	if err := json.Unmarshal(data, &report); err != nil {
		return report, err
	}
	if report.Version != 1 || report.ID == "" || report.FinishedAt.IsZero() {
		return Report{}, errors.New("invalid update report")
	}
	return report, nil
}

func latestReport(root string) (Report, string, error) {
	entries, err := os.ReadDir(root)
	if err != nil {
		return Report{}, "", err
	}
	var best Report
	bestDir := ""
	for _, entry := range entries {
		if !entry.IsDir() || entry.Type()&os.ModeSymlink != 0 {
			continue
		}
		dir := filepath.Join(root, entry.Name())
		if _, err := os.Stat(filepath.Join(dir, ".active")); err == nil {
			continue
		}
		report, err := readReport(dir)
		if err == nil && report.FinishedAt.After(best.FinishedAt) {
			best, bestDir = report, dir
		}
	}
	if bestDir == "" {
		return Report{}, "", os.ErrNotExist
	}
	return best, bestDir, nil
}

func replayEvents(report Report) <-chan ui.Event {
	out := make(chan ui.Event, len(report.Events)+1)
	for _, event := range report.Events {
		// Reports replay history only; no updater exists to receive a handoff.
		if event.Kind == "stage_start" && event.Terminal == "handoff" {
			event.Terminal = "hidden"
		}
		out <- event
	}
	if len(report.Events) == 0 || report.Events[len(report.Events)-1].Kind != "run_end" {
		out <- ui.Event{V: 1, Kind: "run_end", ExitCode: report.ExitCode, DurationMS: report.FinishedAt.Sub(report.StartedAt).Milliseconds()}
	}
	close(out)
	return out
}

func summary(report Report, dir string) string {
	changes, attention, failures := 0, 0, 0
	for _, e := range report.Events {
		switch e.Kind {
		case "change":
			changes++
		case "notice":
			if e.Severity == "attention" || e.Severity == "error" {
				attention++
			}
		case "stage_end":
			if e.Status == "failed" {
				failures++
			}
		}
	}
	var result string
	switch {
	case report.ExitCode != 0:
		result = fmt.Sprintf("Update failed (exit %d)", report.ExitCode)
	case failures > 0 || attention > 0:
		result = fmt.Sprintf("Update completed with %d failure(s) and %d item(s) needing attention", failures, attention)
	case changes > 0:
		result = fmt.Sprintf("Update completed; %d verified change(s)", changes)
	default:
		result = "Update completed; no verified changes were reported"
	}
	return fmt.Sprintf("%s\nReport: %s", result, dir)
}

func ShowLast(opts Options) int {
	root := opts.StateDir
	if root == "" {
		root = stateDir()
	}
	report, dir, err := latestReport(root)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			fmt.Fprintln(os.Stderr, "dots up: no completed update report is available yet")
		} else {
			fmt.Fprintf(os.Stderr, "dots up: read latest report: %v\n", err)
		}
		return 1
	}
	if interactiveTerminal() && !opts.Plain && !opts.Verbose {
		err := uiRun(replayEvents(report), root, opts.NoWait, nil)
		if err != nil {
			fmt.Fprintf(os.Stderr, "dots up: dashboard unavailable: %v\n", err)
		}
	}
	fmt.Println(summary(report, dir))
	if opts.Plain || opts.Verbose || !interactiveTerminal() {
		printReportHighlights(os.Stdout, report)
	}
	return report.ExitCode
}

func printReportHighlights(w io.Writer, report Report) {
	for _, e := range report.Events {
		switch e.Kind {
		case "change":
			if e.Before != "" && e.After != "" {
				fmt.Fprintf(w, "  %s  %s → %s\n", e.Item, e.Before, e.After)
			}
		case "notice":
			if e.Severity == "attention" || e.Severity == "error" {
				fmt.Fprintf(w, "  Attention: %s\n", e.Summary)
			}
		case "stage_end":
			if e.Status == "failed" {
				fmt.Fprintf(w, "  Failed: %s — %s\n", e.Label, e.Summary)
			}
		}
	}
	for _, e := range report.Events {
		if e.LogPath != "" {
			fmt.Fprintf(w, "Logs: %s\n", filepath.Dir(e.LogPath))
			return
		}
	}
}

func tailFile(path string, maxBytes int64) string {
	f, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer f.Close()
	st, err := f.Stat()
	if err != nil {
		return ""
	}
	start := max(int64(0), st.Size()-maxBytes)
	if _, err := f.Seek(start, io.SeekStart); err != nil {
		return ""
	}
	s := bufio.NewScanner(f)
	s.Buffer(make([]byte, 4096), int(maxBytes))
	var lines []string
	for s.Scan() {
		lines = append(lines, s.Text())
	}
	if start > 0 && len(lines) > 0 {
		lines[0] = "… earlier output omitted … " + lines[0]
	}
	return strings.Join(lines, "\n")
}
