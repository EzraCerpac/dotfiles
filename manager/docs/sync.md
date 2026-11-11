# Sync

`dots sync`, and `dots up` before its updates, share a configuration between machines through Git.
This guide covers how a run works, what its output means and what to do about each attention line.
The code is [`lib/source-repo.mjs`](../lib/source-repo.mjs) (checks, locking, output) and [`lib/source-dev.mjs`](../lib/source-dev.mjs) (the run itself).

## dev and main

The configuration repository has two shared branches on `origin`.

- `dev` is what every machine runs. Sync commits local edits onto it and pushes them without force.
- `main` changes only through reviewed pull requests. Every sync merges it into `dev`, so a merged pull request reaches each machine on its next `dots up`.

The live checkout (`DOTS_ROOT`) is a plain Git checkout with `HEAD` on `dev`.
Git refs and the files on disk are the only sync state: unpushed work is exactly `origin/dev..dev`.
Machine-local files (`miserc.toml`, `config.local.toml`, `config.host-*.toml`, mise lockfiles, `locks/`, `.setup-state/`) never enter the repository.

## One run

1. Runs `mise bootstrap dotfiles save`, so copied dotfiles flow back into the configuration.
2. Commits every tracked or unignored public file onto `dev` as `Save local setup (HOST)`.
   Machine-local files are always left out.
3. Scans that commit with gitleaks. A flagged file stays on disk, unshared; the rest is shared.
   A flagged commit already in `origin/dev..dev` blocks the push. Without gitleaks nothing is shared or pushed.
4. Fetches `dev` and `main`, or continues offline.
5. Merges local work with `origin/dev`, then with `origin/main`, without touching the live files.
   On a conflicting hunk the published side wins: `main` over `dev`, `dev` over local work.
   Binary, file-type and delete conflicts take the published file whole.
   Both parents stay in history, so the losing version remains recoverable.
6. Validates the merged configuration with this machine's local files; an invalid result is neither pushed nor applied.
7. Pushes without force, merging and retrying up to three times when `origin/dev` moved meanwhile.
8. Moves the live files from the local commit to the merged one with a two-tree checkout, which refuses to overwrite a file edited during the run, then runs `mise bootstrap dotfiles apply`.

Commits pushed straight to `origin/dev` from a task worktree are fine: the next sync merges them.
A `dev` moved with plumbing in another worktree of the live checkout is merged too, not reverted.

## The outcome block

Every run prints one block.
Its first line has three parts:

```text
dots sync: shared 2 files · pulled dev +1, main +0 · pushed 3f2a9c1
```

| Part | Values |
| --- | --- |
| Local work | `shared N files` (pushed), `saved N files locally` (committed, not pushed), `no local changes` |
| Incoming | `pulled dev +N, main +M` (applied), `fetched dev +N, main +M (not applied)`, `offline` |
| Push | `pushed COMMIT`, `nothing to push`, `not pushed` |

Indented lines follow.
Upper-case lines need attention; `dots up` repeats them in its final summary and reports the sync stage as needing attention.
Lower-case lines are information.

| Line | Meaning and what to do |
| --- | --- |
| `CONFLICT kept published: PATH  (yours: git show COMMIT:PATH)` | Both sides changed the same hunk; the published version is on disk. If yours mattered, recover it with the printed command, edit the file and sync again. `(yours: deleted in COMMIT)` means you had deleted it. |
| `NOT SHARED (gitleaks RULE): PATH:LINE` | gitleaks flagged a new edit. The file stays on disk and out of `dev`. Remove the secret, or add a reviewed allowlist entry to `.gitleaks.toml` or `.gitleaksignore` for a false positive. |
| `NOT SHARED: REASON; local edits kept on disk, nothing pushed` | The scan could not run (for example gitleaks is not installed). Install or fix gitleaks and sync again. |
| `NOT PUSHED (gitleaks RULE): commit COMMIT PATH:LINE; remove it from local history` | An unpushed commit on `dev` contains a finding, so nothing is pushed. Rewrite that commit out of `origin/dev..dev` by hand (it was never published), then sync again. |
| `NOT PUSHED: REASON` | The scan of unpushed commits could not run. Fix gitleaks and sync again. |
| `NOT PUSHED: origin/dev kept moving; retried next run` | Three pushes in a row lost a race. Nothing to do; the next run retries. |
| `OFFLINE: N commits unpushed, retried next run` | `origin` was unreachable. Local work is committed and applied; the next run pushes it. |
| `INVALID merged config: ERROR; nothing pushed or applied` | The merged configuration fails mise's checks with this machine's local files. Fix the error (locally or upstream) and sync again; local work is already committed on `dev`. |
| `LATE EDIT: PATH not updated; rerun` | A file changed while the run was updating files, so the run left it alone. Run sync again. |
| `NOT APPLIED: the Git index is locked (.git/index.lock); files not updated, rerun` | Another Git command held the index, so the run left the files and `dev` alone; anything it pushed arrives on the next run. Run sync again once that command finishes; remove a lock left by a crashed Git command by hand. |
| `NOT RECORDED: dev moved during sync; files updated, rerun` | Another process moved `dev` during the run. Run sync again. |
| `SAVE FAILED: mise bootstrap dotfiles save (exit N); copied dotfiles not captured` | Copied dotfiles were not saved back. Run `mise bootstrap dotfiles save` to see why. |
| `APPLY FAILED: mise bootstrap dotfiles apply (exit N)` | The configuration advanced but dotfiles were not applied. Run `dots apply` to see why. |
| `changed on disk: STAT` | Files the run updated. |
| `dev moved outside sync (now COMMIT), or the index was staged to match COMMIT; ...` | The Git index matched an older commit, so local files were treated as based on it and merged onto `dev`. Nothing on disk is lost, but a revert staged by hand is undone; commit such a revert instead. |

A run can also end with a single line instead:

| Line | Meaning and what to do |
| --- | --- |
| `dots sync: stopped · PROBLEM. Sync needs a plain Git checkout on dev; ...` | The checkout is missing, has a foreign `origin`, or has the wrong shape (see [checkout shape](#checkout-shape)). |
| `dots sync: skipped · a Git operation is in progress (NAME); ...` | Finish or abort the merge, rebase, cherry-pick, revert or bisect, then sync again. |
| `dots sync: skipped · another source operation is running ...` | Another sync or publish holds the lock. A lock left by a dead process on this host is reclaimed on the next run. |
| `dots sync: skipped · GIT cannot merge-tree -X; install Git 2.43 or newer` | See [requirements](#requirements). |
| `dots sync: failed · ERROR` | An unexpected error. Read it, fix the cause and sync again. |

Every run exits 0; the printed outcome, not the exit status, says how it ended.
`dots up` reports `stopped`, `skipped` and `failed` lines as needing attention and continues with its other stages whatever the sync outcome.

## Requirements

- Git 2.43 or newer. Sync merges with `git merge-tree --write-tree -X theirs`; `merge-tree` gained `--write-tree` in 2.38 and `-X` only in 2.43.0 (its release notes: "git merge-tree learned to take strategy backend specific options via the -X option"). Git 2.39.5 rejects `-X` with `unknown switch`; Git 2.56 accepts it. Sync checks this itself and skips with a message on an older Git.
- gitleaks, for every share and push.
- `origin` pointing at the GitHub repository named in `[vars] dots_source_repo`, with `main` and `dev` branches.
- A `.gitignore` that ignores the machine-local files and a `.gitleaks.toml`; `dots init` writes both. Sync refuses a merged configuration whose ignore rules would expose a local file.

## Checkout shape

Sync works on one shape only: a plain Git checkout at the repository root, with `HEAD` on `dev` and at least one commit.
It stops on a detached `HEAD`, another branch, a JJ workspace (`.jj`) or state from an older sync (`.git/dots-dev.json`).
`dots bootstrap` moves a fresh clone that is still on `main`, with no edits, to `dev`.
Anything else is converted once, by hand, so that local edits and unpushed work are kept; the configuration repository may document the exact steps for its machines.

The live checkout does not support JJ.
When Git `HEAD` follows `dev` and another worktree moves `dev`, JJ re-parents its working copy onto the new commit without changing files and records the difference as a revert, which sync could not tell apart from a real local edit.

## Pull requests into main

Reviewed changes reach `main` through a pull request from a task branch or a JJ workspace, never from the live checkout.
To extract a change made on `dev`, create a task branch from `origin/main`, copy or cherry-pick only that change, and review its diff against `main`.
Do not move `dev` by hand or merge it wholesale into `main`.
`dots publish` runs in a colocated JJ workspace of the configuration repository: it scans the outgoing commits with gitleaks, asks for confirmation, pushes a bookmark and opens or updates the pull request.
No command force-pushes, rebases a task, or writes conflict markers into live files.
