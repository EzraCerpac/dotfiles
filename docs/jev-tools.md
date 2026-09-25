# Jev tools on this Mac

Perch is a workstation mise tool. Sift and Unclutter are local source builds
loaded into Orion. Each extension has its own settings and local API-key copy.

## Private key

Run `mise -C ~/.config/mise run jev:save-key` once and paste the key into the
hidden prompt. This writes `~/.config/jev/api-key` with mode `0600` in a `0700`
directory and saves an age-encrypted copy at `encrypted/jev-api-key.age`.
The save task checks that the encrypted copy decrypts to the same value.

`mise -C ~/.config/mise run jev:restore-key` restores that copy using the existing
age identity. It refuses to replace a different local key. Normal `setup:secrets`
also restores Jev when its encrypted file is present. Plaintext keys do not
belong in source, shell startup files, or project `.env` files.

## Perch

From the repository to check:

```sh
perch doctor
perch scan --paths src/example.ts
perch scan --since origin/main
perch issues
perch check <issue-id>
```

The `~/.local/bin/perch` launcher preserves the current directory and loads the
private key into the child process. An explicit `PERCH_API_KEY` takes precedence;
the launcher also supplies the `TYPESAFE_API_KEY` alias required by release 0.3.3.
The global Codex skill uses this launcher. No automatic hooks or CI gates are added.

Scans send selected source and related context to TypeSafe. Prefer a named file
or a change range. Findings are suggestions to inspect, not established defects.
Exit code 3 means findings crossed the reporting threshold; 1 and 2 mean failure.

## Orion

Sift runs on `www.google.com/search`, using its default ranking settings.
Its notification offers **Show original** to undo the ranking and **Re-apply**
to restore it. Configure the key through **Tools → Extensions → Sift → Options**.

Unclutter uses **TypeSafe AI** and **Manual** analysis. Use **Analyze page** on a
public page, **Pause** to restore it, and **Resume** to apply its saved rules.
Saved rules apply on later visits without another paid analysis. The extension
is visual cleanup; it does not reject cookie consent or block tracking requests.

Both extensions keep their working key in local extension storage, which is not
encrypted by the extension and is separate from the age-encrypted backup.

## Builds and updates

Source checkouts live at `~/Projects/Tools/sift` and `~/Projects/Tools/unclutter`.
Run:

```sh
mise -C ~/.config/mise run jev:sift-build
mise -C ~/.config/mise run jev:unclutter-build
# Alternate build if Orion cannot run the Chromium build:
mise -C ~/.config/mise run jev:unclutter-firefox-build
```

Sift uses the mise-managed Node runtime. Unclutter uses mise Bun 1.4.2 because
the older installed Bun versions cannot read its version-2 lockfile.
Rebuild tasks use locked dependencies and leave source revisions unchanged.
After rebuilding, use Orion's **Tools → Extensions → Manage Extensions → Reload
from Disk**, then refresh the test page. Keep the same extension installation so
its settings survive. Preserve local compatibility commits when updating upstream.

Perch updates through the normal `dots up` workflow. Its npm entry has a scoped
`allow_low_downloads` exception because the requested package was newer than the
configured minimum age at installation; the npm repository matched the requested
upstream repository. Other package protections remain as configured.

## Installation checks (2026-09-21)

- Perch 0.3.3 resolves through the private launcher in a fresh Fish shell.
  `perch doctor` passed. A live scan of Sift's public `src/rank/plan.ts` read
  10 methods, reported no issues, and reported a cost of $0.0022.
- The key save checked its encrypted round-trip. Restore also decrypted and
  compared it with the local copy. The local directory/file modes are 0700/0600.
- Sift's Chromium build reordered eight results on `www.google.com`.
  **Show original**, **Re-apply**, and persistence after reload passed.
- Unclutter's Chromium build retains TypeSafe AI, its saved key, and Manual
  settings, but reports the public page unavailable despite website permission
  and Compatibility Mode being off. The Firefox-format fallback was installed
  and tested on `example.com` with an explicit Allow permission; it has the same
  failure. The fallback is disabled and the original Chromium copy is enabled.
  Orion labels both disk installs as Chrome. The original extension ID ends in
  `ee51ce0bf6498403f0b4db1be0673e43`; the fallback ends in
  `57a58a7362c9b9bc2e29b826c2a78cf3`.
  Live cleanup, pause/resume, saved-rule reuse, and coexistence checks remain open.
  A temporary connection-error probe was removed from source after Orion UI
  automation timed out during reload. No compatibility patch was adopted.
  The clean Chromium output was rebuilt; reload that copy from disk after Orion
  becomes responsive before doing further tests.
- Sift's complete check passed (55 tests). Unclutter's typecheck, lint, 21 tests,
  and both builds passed. Its upstream formatter crashes on the configured
  `printWidth`; the full aggregate check therefore does not pass.
