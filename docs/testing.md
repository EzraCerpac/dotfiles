# Testing the setup

This repository has two test suites.
The configuration's suite checks this setup; the manager's suite checks `dots` itself and runs from `manager/` alone.

```sh
dots test              # the configuration suite; or: tests/run, or: mise -C ~/.config/mise run setup:test
dots test python node  # only the named suites: python, node
manager/tests/run      # the manager suite (same interface)
```

`tests/run` covers the secret-scan and gitignore guards, dotfile declarations, docs links, shell syntax of the configuration's scripts, the native dotfile fixtures for the agent instruction files and dotfile groups, and JJ merge handling.
`manager/tests/run` covers the `dots` contract (hooks, commands, installer exceptions, settings, `dots init`), `DOTS_HOME` resolution, bootstrap completion hooks, source sync and publication, native encrypted history, the manager's shell syntax and its own docs links.
It uses only `manager/` and the fixture configuration in `manager/tests/fixtures/config`; see [the manager README](../manager/README.md#development).
Behavior outside these suites is checked by running the setup, not by tests.

Both runners isolate the run from your personal Git and JJ configuration, so signing, pagers and default-branch settings cannot change fixture behavior.
Tests use real tools when they are installed and skip, with a reason, when they are not.
The shared lookups live in `tests/lib/prereq.py` and `tests/lib/prereq.mjs`, with a copy under `manager/tests/lib/`; mise resolves as `SETUP_TEST_MISE`, then `PATH`, then `~/.local/bin/mise`.

## Continuous integration

`.github/workflows/test.yml` runs on Ubuntu and macOS for every pull request and push to `main`, and nightly.
The `test` job runs `tests/run` in the checkout.
The `manager` job copies `manager/` to an empty directory and runs `tests/run` and the `dots-up` Go checks there, so a hidden dependency on this configuration fails CI.
Tools in this setup track their latest releases, so the nightly run is a canary: it reports an upstream change that breaks the setup before `dots up` meets it on a real machine.
