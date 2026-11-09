# Testing the setup

Run every suite from the setup checkout:

```sh
dots test              # or: tests/run, or: mise -C ~/.config/mise run setup:test
dots test python node  # only the named suites: python, node
```

`tests/run` runs the Python `unittest` suite and the Node `node:test` files
under `tests/`. It isolates the run from your personal Git and JJ
configuration, so signing, pagers and default-branch settings cannot change
fixture behavior.

The suite is deliberately small: it covers the secret-scan and gitignore
guards, dotfile declarations, docs links, shell and TOML syntax, the native
dotfiles and history flows, JJ merge handling, and source and publication
sync. Behavior outside that is checked by running the setup, not by tests.

Tests use real tools when they are installed and skip, with a reason, when
they are not. The shared lookups live in `tests/lib/prereq.py` and
`tests/lib/prereq.mjs`; mise resolves as `SETUP_TEST_MISE`, then `PATH`, then
`~/.local/bin/mise`.

## Continuous integration

`.github/workflows/test.yml` runs `tests/run` on Ubuntu and macOS for every
pull request and push to `main`, and nightly. Tools in this setup track their
latest releases, so the nightly run is a canary: it reports an upstream change
that breaks the setup before `dots up` meets it on a real machine.
