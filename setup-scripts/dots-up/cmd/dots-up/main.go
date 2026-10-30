package main

import (
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/EzraCerpac/dotfiles/setup-scripts/dots-up/internal/commands"
	"github.com/EzraCerpac/dotfiles/setup-scripts/dots-up/internal/launcher"
	"github.com/EzraCerpac/dotfiles/setup-scripts/dots-up/internal/supervisor"
	"github.com/charmbracelet/x/term"
)

func main() { os.Exit(run(os.Args[1:])) }

func run(args []string) int {
	fs := flag.NewFlagSet("dots-up", flag.ContinueOnError)
	fs.SetOutput(os.Stderr)
	var opts supervisor.Options
	var capabilities bool
	fs.StringVar(&opts.Root, "root", defaultRoot(), "setup repository root")
	fs.StringVar(&opts.Command, "command", "", "dots command; omitted means up")
	fs.BoolVar(&capabilities, "capabilities", false, "print frontend protocol")
	fs.BoolVar(&opts.MAS, "mas", false, "include Mac App Store updates")
	fs.BoolVar(&opts.Plain, "plain", false, "show concise scrolling progress")
	fs.BoolVar(&opts.Verbose, "verbose", false, "show full subprocess output")
	fs.BoolVar(&opts.NoWait, "no-wait", false, "close when the command finishes")
	fs.BoolVar(&opts.Last, "last", false, "reopen the latest saved report")
	fs.Usage = func() {
		fmt.Fprintln(fs.Output(), "Usage: dots-up [--mas] [--plain | --verbose] [--no-wait] [--last]\n       dots-up --command COMMAND [display flags] -- [ARGS...]\nInteractive dots commands share a dashboard; noninteractive runs show concise progress.")
	}
	if err := fs.Parse(args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return 0
		}
		return 2
	}
	if capabilities {
		fmt.Println("dots-shared-cli/1")
		return 0
	}
	if opts.Plain && opts.Verbose {
		fmt.Fprintln(os.Stderr, "dots-up: --plain and --verbose cannot be combined")
		return 2
	}
	if opts.Last && opts.MAS {
		fmt.Fprintln(os.Stderr, "dots-up: --last cannot be combined with --mas")
		return 2
	}
	if opts.Command == "" && fs.NArg() != 0 {
		fmt.Fprintf(os.Stderr, "dots-up: unexpected argument %q\n", fs.Arg(0))
		return 2
	}
	opts.Args = fs.Args()
	root, err := filepath.Abs(opts.Root)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	opts.Root = root
	if opts.Command == "menu" {
		if !term.IsTerminal(os.Stdin.Fd()) || !term.IsTerminal(os.Stdout.Fd()) {
			fs.Usage()
			return 0
		}
		session := &launcher.Session{}
		for {
			selected, err := session.Run(nil)
			if errors.Is(err, launcher.ErrCancelled) {
				return 0
			}
			if err != nil {
				fmt.Fprintln(os.Stderr, err)
				return 1
			}
			if len(selected) == 0 {
				continue
			}
			selectedOpts := opts
			selectedOpts.Command = selected[0]
			selectedOpts.Args = selected[1:]
			code := execute(selectedOpts)
			if code != 0 {
				fmt.Fprintf(os.Stderr, "dots %s exited with status %d\n", selectedOpts.Command, code)
			}
		}
	}
	return execute(opts)
}

func execute(opts supervisor.Options) int {
	if opts.Command == "" {
		opts.Command = "up"
	}
	opts.Command = commands.Canonical(opts.Command)
	spec, ok := commands.Lookup(opts.Command)
	if !ok {
		fmt.Fprintf(os.Stderr, "dots: unknown command %q\n", opts.Command)
		return 2
	}
	// Keep update suffix display flags and reports compatible with the old CLI.
	if opts.Command == "up" {
		var backendArgs []string
		for _, a := range opts.Args {
			switch a {
			case "--plain":
				opts.Plain = true
			case "--verbose":
				opts.Verbose = true
			case "--no-wait":
				opts.NoWait = true
			case "--last":
				opts.Last = true
			case "--mas":
				opts.MAS = true
			default:
				backendArgs = append(backendArgs, a)
			}
		}
		opts.Args = backendArgs
	}
	if opts.Plain && opts.Verbose {
		fmt.Fprintln(os.Stderr, "dots: --plain and --verbose cannot be combined")
		return 2
	}
	if opts.Command == "reports" {
		return supervisor.BrowseReports(opts)
	}
	if opts.Last {
		if len(opts.Args) > 0 || opts.MAS {
			fmt.Fprintln(os.Stderr, "dots: --last does not accept operation arguments")
			return 2
		}
		return supervisor.ShowLast(opts)
	}
	// Plan, source-only synchronization and the unavailable HouseAtlas binding retain
	// their original direct routes. None starts an update supervisor.
	if opts.Command == "plan" || (opts.Command == "sync" && len(opts.Args) == 1 && opts.Args[0] == "--source-only") || (opts.Command == "up" && len(opts.Args) > 0 && opts.Args[0] == "houseatlas") {
		return directBackend(opts)
	}
	opts.Sensitive = spec.Sensitive
	opts.Concise = spec.Mode == "concise"
	return supervisor.Run(opts)
}

func directBackend(opts supervisor.Options) int {
	args := []string{filepath.Join(opts.Root, "dotfiles", ".local", "bin", "dots"), "--backend", opts.Command}
	args = append(args, opts.Args...)
	cmd := exec.Command("bash", args...)
	cmd.Env = append(os.Environ(), "DOTS_ROOT="+opts.Root)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		var e *exec.ExitError
		if errors.As(err, &e) {
			return e.ExitCode()
		}
		fmt.Fprintln(os.Stderr, err)
		return 127
	}
	return 0
}
func defaultRoot() string {
	if root := os.Getenv("MISE_CONFIG_DIR"); root != "" {
		return root
	}
	if root := os.Getenv("DOTS_ROOT"); root != "" {
		return root
	}
	configHome := os.Getenv("XDG_CONFIG_HOME")
	if configHome == "" {
		configHome = filepath.Join(os.Getenv("HOME"), ".config")
	}
	return filepath.Join(configHome, "mise")
}
