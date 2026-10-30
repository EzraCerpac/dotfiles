package main

import (
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"

	"github.com/EzraCerpac/dotfiles/setup-scripts/dots-up/internal/supervisor"
)

func main() { os.Exit(run(os.Args[1:])) }

func run(args []string) int {
	fs := flag.NewFlagSet("dots-up", flag.ContinueOnError)
	fs.SetOutput(os.Stderr)
	var opts supervisor.Options
	fs.StringVar(&opts.Root, "root", defaultRoot(), "setup repository root")
	fs.BoolVar(&opts.MAS, "mas", false, "include Mac App Store updates")
	fs.BoolVar(&opts.Plain, "plain", false, "show concise scrolling progress")
	fs.BoolVar(&opts.Verbose, "verbose", false, "show full subprocess output")
	fs.BoolVar(&opts.NoWait, "no-wait", false, "close the dashboard when updates finish")
	fs.BoolVar(&opts.Last, "last", false, "reopen the latest saved report without updating")
	fs.Usage = func() {
		fmt.Fprintln(fs.Output(), "Usage: dots-up [--mas] [--plain | --verbose] [--no-wait] [--last]")
		fmt.Fprintln(fs.Output(), "Run the focused dots up dashboard, or show concise output when no interactive terminal is available.")
		fmt.Fprintln(fs.Output(), "  --mas       include Mac App Store updates on macOS workstations")
		fmt.Fprintln(fs.Output(), "  --plain     show concise scrolling progress and the completed report")
		fmt.Fprintln(fs.Output(), "  --verbose   show full subprocess output for diagnosis")
		fmt.Fprintln(fs.Output(), "  --no-wait   exit automatically when an interactive run finishes")
		fmt.Fprintln(fs.Output(), "  --last      reopen the latest saved report without running updates")
	}
	if err := fs.Parse(args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return 0
		}
		return 2
	}
	if fs.NArg() != 0 {
		fmt.Fprintf(os.Stderr, "dots-up: unexpected argument %q\n", fs.Arg(0))
		return 2
	}
	if opts.Plain && opts.Verbose {
		fmt.Fprintln(os.Stderr, "dots-up: --plain and --verbose cannot be combined")
		return 2
	}
	if opts.Last && opts.MAS {
		fmt.Fprintln(os.Stderr, "dots-up: --last cannot be combined with --mas")
		return 2
	}
	if opts.Last {
		return supervisor.ShowLast(opts)
	}
	if !filepath.IsAbs(opts.Root) {
		root, err := filepath.Abs(opts.Root)
		if err != nil {
			fmt.Fprintf(os.Stderr, "dots-up: setup root: %v\n", err)
			return 2
		}
		opts.Root = root
	}
	return supervisor.Run(opts)
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
