# Presentation and showcase modes

On macOS, `present on` enters Presentation Mode: it runs the Presentation Mode
Shortcut, keeps the Mac awake, stops Time Machine and selected launch agents,
quits selected apps, and terminates matching development processes. Apps and dev
servers must be relaunched manually afterward. `present off` restores stopped
launch agents, stops its awake timer, and leaves Presentation Mode.

To present a running demo, explicitly select its server or launcher PID and URL:

```sh
present showcase --pid 12345 --url https://demo.localhost --dry-run
present showcase --pid 12345 --url https://demo.localhost
```

Use the actual PID of your server or the `npm`, `pnpm`, or `uvicorn` launcher.
Showcase keeps that PID, its descendants, and its launcher ancestors. Selecting a
launcher keeps all of its child processes. Matching dev launcher ancestors also
keep their whole subtree, including sibling helpers: a supervisor can otherwise
stop the demo when a helper exits. Unrelated server trees can still be stopped. It also
keeps any listed app or launch agent containing a protected PID, so closing a
launcher cannot indirectly stop the demo. It never starts a demo for you.

The URL is checked with curl before cleanup and afterward. Each request has a
five-second deadline and needs an HTTP response below 400 with valid TLS. Supply
the URL you intend to show, including a health endpoint if appropriate. For a
Portless demo, use its existing named URL. The PID and URL are explicit selections;
`present` does not infer which process serves the URL.

An initial readiness failure exits before changing presentation state. A failure
after cleanup exits nonzero and leaves Presentation Mode active; use `present off`
to restore stopped agents. The selected PID must remain alive during cleanup. A
server that exits or replaces its launcher must be selected again with its current
PID. Process inspection protects the observed tree; it cannot freeze processes or
prevent a server from exiting independently.

`--dry-run` checks readiness and prints the planned cleanup, without running the
Shortcut, quitting apps, signaling processes, or writing presentation state.
`present status` shows the selected demo PID and URL while showcase is active.
`present doctor` retains its ordinary Shortcut, resource, and backup preflight
checks. Leave either presentation mode with `present off` before entering again.

The isolated regression tests use fake macOS commands and HTTP responses, and
intercept Bash's signal builtin:

```sh
uv run --no-project python -m unittest discover -s tests -p test_present.py
```
