package main

import (
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestDirectCommandsHonorSelectedRootAndHomeOverAmbient(t *testing.T) {
	source, err := os.ReadFile(filepath.Join("..", "..", "..", "bin", "dots"))
	if err != nil {
		t.Fatal(err)
	}
	for _, ambient := range []string{"unset", "conflicting"} {
		for _, command := range []string{"plan", "sync"} {
			t.Run(command+"/"+ambient, func(t *testing.T) {
				base, err := filepath.EvalSymlinks(t.TempDir())
				if err != nil {
					t.Fatal(err)
				}
				selected := filepath.Join(base, "selected")
				other := filepath.Join(base, "ambient")
				for _, root := range []string{selected, other} {
					if err := os.MkdirAll(root, 0700); err != nil {
						t.Fatal(err)
					}
					if err := os.WriteFile(filepath.Join(root, "config.toml"), []byte("# fixture\n"), 0600); err != nil {
						t.Fatal(err)
					}
				}
				// The manager lives apart from both configurations.
				home := filepath.Join(base, "manager")
				otherHome := filepath.Join(base, "ambient-manager")
				if err := os.MkdirAll(filepath.Join(home, "bin"), 0700); err != nil {
					t.Fatal(err)
				}
				if err := os.WriteFile(filepath.Join(home, "bin", "dots"), source, 0700); err != nil {
					t.Fatal(err)
				}
				log := filepath.Join(base, "mise-args")
				mise := filepath.Join(base, "mise")
				if err := os.WriteFile(mise, []byte("#!/bin/sh\nprintf '%s\\n' \"$MISE_CONFIG_DIR\" \"$@\" >\"$DIRECT_TEST_LOG\"\n"), 0700); err != nil {
					t.Fatal(err)
				}
				t.Setenv("DOTS_MISE_BIN", mise)
				t.Setenv("DIRECT_TEST_LOG", log)
				t.Setenv("HOME", base)
				t.Setenv("DOTS_ROOT", other)
				t.Setenv("DOTS_HOME", otherHome)
				if ambient == "unset" {
					for _, key := range []string{"DOTS_ROOT", "DOTS_HOME"} {
						if err := os.Unsetenv(key); err != nil {
							t.Fatal(err)
						}
					}
				}
				args := []string{"--root", selected, "--home", home, "--command", command, "--"}
				if command == "sync" {
					args = append(args, "--source-only")
				}
				if code := run(args); code != 0 {
					t.Fatalf("direct command exited %d", code)
				}
				output, err := os.ReadFile(log)
				if err != nil {
					t.Fatal(err)
				}
				lines := strings.Split(strings.TrimSpace(string(output)), "\n")
				if len(lines) < 3 || lines[0] != selected || lines[1] != "-C" || lines[2] != selected {
					t.Fatalf("selected root lost to ambient root: %q", output)
				}
				if command == "plan" && strings.Join(lines[3:], " ") != "bootstrap plan" {
					t.Fatalf("unexpected plan invocation: %q", output)
				}
				if command == "sync" && !strings.Contains(string(output), home+"/lib/source-repo.mjs\nsync\n"+selected+"\n--source-only") {
					t.Fatalf("unexpected source-only invocation: %q", output)
				}
			})
		}
	}
}

func TestCapabilitiesReportsHomeAwareProtocol(t *testing.T) {
	stdout := os.Stdout
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	os.Stdout = w
	code := run([]string{"--capabilities"})
	os.Stdout = stdout
	_ = w.Close()
	output, err := io.ReadAll(r)
	if err != nil {
		t.Fatal(err)
	}
	if code != 0 || strings.TrimSpace(string(output)) != "dots-shared-cli/2" {
		t.Fatalf("capabilities = %q (exit %d)", output, code)
	}
}
