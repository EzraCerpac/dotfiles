# Review guidelines

For anyone reviewing a pull request here, human or automated.

## What this repository promises

- It is public. No keys, tokens, app state or machine-local files
  (`miserc.toml`, `config.local.toml`, `config.host-*.toml`) are ever committed.
- It is one person's machine configuration for two roles, `workstation` and
  `nas`. Host exceptions, services, system software and app data are kept.
- Updates never prune packages or restart services (Capd on macOS is the one
  documented exception).
- The `dots` manager is not here: it lives in EzraCerpac/dots, and this
  repository changes it only by moving the release pinned in `config.toml`.
- A tracked history file is never saved unless it is declared `encrypt = true`.
- `main` is reviewed; every machine syncs the shared `dev` branch, which merges
  `main`. A merged pull request reaches every machine on its next `dots up`.

A change that breaks one of these is worth a comment at any size.

## Facts to check claims against

- mise is 2026.11.8 or newer on every machine (`min_version` in `config.toml`).
  Do not raise behaviour of older releases. Before claiming a mise command
  behaves a certain way, run it or say the claim is unverified.
- CI installs every tool the tests use (`.github/workflows/test.yml`).
- One person runs everything here, on their own machines. Procedures under
  `docs/` are run by hand, once per machine, with a backup taken first.

## Not worth raising

- Skipping a test when a tool CI always installs is missing.
- Locks or repeated checks for races between two concurrent runs by the same
  user, or inside a documented manual procedure, unless data can be lost.
- Automating a one-off migration: documented manual steps are preferred.
- Style, naming and comment wording.
- Added abstraction, options or fallbacks the behaviour does not need: flag
  them as unnecessary, do not ask for more.
