# Testing the setup

`tests/run` checks this configuration; the `dots` manager is tested in [its own repository](https://github.com/EzraCerpac/dots).

```sh
dots test              # or: tests/run, or: mise -C ~/.config/mise run setup:test
dots test python node  # only the named suites: python, node
```

`tests/run` covers the secret-scan and gitignore guards, dotfile declarations, docs links, shell syntax of the configuration's scripts, the native dotfile fixtures for the agent instruction files and dotfile groups, JJ merge handling, and that `dots/README.md` is the template the pinned [dots release](dots-release.md) ships.
Behavior outside the suite is checked by running the setup, not by tests.

The runner isolates the run from your personal Git and JJ configuration, so signing, pagers and default-branch settings cannot change fixture behavior.
Tests use real tools when they are installed and skip, with a reason, when they are not.
The shared lookups live in `tests/lib/prereq.py` and `tests/lib/prereq.mjs`; mise resolves as `SETUP_TEST_MISE`, then `PATH`, then `~/.local/bin/mise`.

## Continuous integration

`.github/workflows/test.yml` runs on Ubuntu and macOS for every pull request and push to `main`, and nightly.
The `test` job installs the test tools, including the dots release `config.toml` pins, and runs `tests/run` in the checkout.
Tools in this setup track their latest releases, so the nightly run is a canary: it reports an upstream change that breaks the setup before `dots up` meets it on a real machine.
