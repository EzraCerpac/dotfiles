# Testing the setup

Run every suite from the setup checkout:

```sh
dots test                # or: tests/run, or: mise -C ~/.config/mise run setup:test
dots test python shell   # only the named suites: python, node, shell, lua
```

`tests/run` runs the Python `unittest` suite, the Node `node:test` files, the
shell tests under `tests/`, and the Neovim Lua tests. It isolates the run from
your personal Git and JJ configuration, so signing, pagers and default-branch
settings cannot change fixture behavior.

Tests use real tools when they are installed and skip, with a reason, when
they are not. A shell test signals a skip by exiting with status 77. The
shared lookups live in `tests/lib/prereq.py` and `tests/lib/prereq.mjs`; mise
resolves as `SETUP_TEST_MISE`, then `PATH`, then `~/.local/bin/mise`.

The Typst guard's headless test needs Neovim's `typst` tree-sitter parser,
which the workstation's nvim-treesitter already installs.

`tests/linux-bootstrap.sh` is excluded: it needs Docker and performs a full
workstation installation. See [Linux bootstrap tests](linux-tests.md).

## Continuous integration

`.github/workflows/test.yml` runs `tests/run` on Ubuntu and macOS for every
pull request and push to `main`, and nightly. Tools in this setup track their
latest releases, so the nightly run is a canary: it reports an upstream change
that breaks the setup before `dots up` meets it on a real machine.
