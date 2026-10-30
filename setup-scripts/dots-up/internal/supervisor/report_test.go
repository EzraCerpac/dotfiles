package supervisor

import (
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/EzraCerpac/dotfiles/setup-scripts/dots-up/internal/ui"
)

func TestRunReportsArePrivateAndRetentionPreservesActiveRun(t *testing.T) {
	root := t.TempDir()
	base := time.Date(2026, 10, 30, 12, 0, 0, 0, time.UTC)
	mode := func(path string) os.FileMode {
		t.Helper()
		info, err := os.Stat(path)
		if err != nil {
			t.Fatal(err)
		}
		return info.Mode().Perm()
	}
	assertMode := func(path string, want os.FileMode) {
		t.Helper()
		if got := mode(path); got != want {
			t.Fatalf("%s mode = %04o, want %04o", path, got, want)
		}
	}

	var first string
	for i := 0; i < 10; i++ {
		started := base.Add(time.Duration(i) * time.Second)
		files, err := newRunFiles(started, root)
		if err != nil {
			t.Fatal(err)
		}
		if i == 0 {
			first = files.runDir
			assertMode(root, 0o700)
			assertMode(files.runDir, 0o700)
			assertMode(filepath.Join(files.runDir, "stages"), 0o700)
			assertMode(filepath.Join(files.runDir, ".active"), 0o600)
			assertMode(filepath.Join(files.runDir, "events.jsonl"), 0o600)
		}
		if err := files.record(ui.Event{V: 1, Kind: "run_start"}); err != nil {
			t.Fatal(err)
		}
		if err := files.finish(0, "nas", "fixture", started.Add(time.Second)); err != nil {
			t.Fatal(err)
		}
		assertMode(filepath.Join(files.runDir, "report.json"), 0o600)
	}

	active, err := newRunFiles(base.Add(10*time.Second), root)
	if err != nil {
		t.Fatal(err)
	}
	latest, err := newRunFiles(base.Add(11*time.Second), root)
	if err != nil {
		t.Fatal(err)
	}
	if err := latest.finish(0, "nas", "fixture", base.Add(12*time.Second)); err != nil {
		t.Fatal(err)
	}

	entries, err := os.ReadDir(root)
	if err != nil {
		t.Fatal(err)
	}
	completed := 0
	for _, entry := range entries {
		path := filepath.Join(root, entry.Name())
		if _, err := os.Stat(filepath.Join(path, ".active")); err == nil {
			if path != active.runDir {
				t.Fatalf("unexpected active run %s", path)
			}
			continue
		}
		if _, err := os.Stat(filepath.Join(path, "report.json")); err == nil {
			completed++
		}
	}
	if completed != 10 {
		t.Fatalf("retained %d completed reports, want 10", completed)
	}
	if _, err := os.Stat(first); !os.IsNotExist(err) {
		t.Fatalf("oldest report still exists or could not be checked: %v", err)
	}
	if _, err := os.Stat(filepath.Join(active.runDir, ".active")); err != nil {
		t.Fatalf("active report was pruned: %v", err)
	}
	if err := active.eventLog.Close(); err != nil {
		t.Fatal(err)
	}
}
