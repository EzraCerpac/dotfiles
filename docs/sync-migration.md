# Convert a live checkout for stateless sync

`dots sync` works on one shape only: `~/.config/mise` is a plain Git checkout with `HEAD` on `dev`
(see [the sync guide](../manager/docs/sync.md#checkout-shape)).
It stops with a message when it finds `.jj`, `.git/dots-dev.json`, a detached `HEAD`, or another branch.
Convert each existing machine once, by hand, over SSH.
Steps 1 to 6 change no tracked file in the checkout, only Git refs, the Git index, the legacy state and one ignored local file;
the sync in step 7 then updates files as usual.

Run the blocks in order and read each check before continuing.
Every block starts from scratch, so each can be its own `ssh HOST '...'` command.
Make sure no other agent is editing `~/.config/mise` meanwhile, and that the stateless sync is merged into `main` (step 7 runs it from `origin/main`).

## 0. Check the tools

```sh
cd ~/.config/mise || exit 1
command -v mise || ls ~/.local/bin/mise
git --version; git merge-tree --write-tree -X theirs HEAD HEAD >/dev/null && echo "git ok"
mise exec -- gitleaks version
```

Check: `git ok` and a gitleaks version.
If `mise` is not on `PATH`, use `~/.local/bin/mise` in every block.
If Git fails the check (it needs 2.43 or newer), put a newer Git first on `PATH` before going on.

## 1. Record the current state

```sh
cd ~/.config/mise || exit 1
B=.git/dots-legacy-$(date +%Y%m%d%H%M%S); mkdir "$B" || exit 1
git rev-parse HEAD > "$B/HEAD"
git symbolic-ref -q HEAD > "$B/HEAD-ref" || :
git rev-parse --verify -q refs/heads/dev > "$B/dev" || :
git config --get-regexp '^branch\.dev\.' > "$B/dev-config" || :
cp -p .git/index "$B/index"
git for-each-ref --format='%(objectname) %(refname)' refs/dots > "$B/refs"
while read -r id ref; do git update-ref "refs/dots-legacy/${B#.git/dots-legacy-}/${ref#refs/dots/}" "$id"; done < "$B/refs"
[ ! -f config.local.toml ] || cp -p config.local.toml "$B/"
echo "$B"; cat "$B/HEAD" "$B/dev" "$B/refs"
```

Check: it prints the backup directory, `HEAD`, `dev` (if any) and any `refs/dots/queue` or `refs/dots/capture`.

## 2. Find the commit the files are based on

The old sync recorded it in `.git/dots-dev.json`: `capture` is its last snapshot of the files, `applied` the last commit it checked out.
JJ may have moved `HEAD` since without changing files, so prefer those to `HEAD`.

```sh
cd ~/.config/mise || exit 1; B=$(ls -d .git/dots-legacy-* | tail -n 1)
base=
for key in capture applied; do
  [ -n "$base" ] || base=$(sed -n "s/.*\"$key\":\"\([0-9a-f]\{40\}\)\".*/\1/p" .git/dots-dev.json 2>/dev/null)
done
base=${base:-$(cat "$B/HEAD")}; echo "$base" > "$B/base"; echo "base $base"
git diff --stat "$base"
git status --short --untracked-files=all | grep '^??' || :
```

Check: the diffstat and the `??` lines list only edits made on this machine since the last sync.
If they also show other machines' recent changes as deletions or reverts, the base is wrong:
compare `git diff --stat` against `applied` and `HEAD` (from `$B/HEAD`), and write the one that lists only local edits to `"$B/base"`.

## 3. Publish queued work

The base and any queued or captured commits must be on `origin/dev`, so that sync can find the base in history.

```sh
cd ~/.config/mise || exit 1; B=$(ls -d .git/dots-legacy-* | tail -n 1)
git fetch -q origin dev main
for id in $(cut -d' ' -f1 "$B/refs") $(cat "$B/dev") $(cat "$B/base"); do
  git merge-base --is-ancestor "$id" origin/dev && echo "published $id" || echo "NOT published $id"
done
```

Check: every line says `published`.
Otherwise merge the missing commits into `dev` in a scratch worktree, scan and push.
Put the `NOT published` IDs into `ids`:

```sh
cd ~/.config/mise || exit 1
ids="PASTE THE NOT PUBLISHED IDS"
wt=$(mktemp -d)/dev; git worktree add -q --detach "$wt" origin/dev
ok=1; for id in $ids; do git -C "$wt" merge -q --no-edit -X ours "$id" || { ok=0; break; }; done
if [ "$ok" = 1 ] && mise exec -- gitleaks git --no-banner --redact --config "$PWD/.gitleaks.toml" \
     --log-opts="--diff-merges=first-parent origin/dev..HEAD" "$wt"; then
  git -C "$wt" push -q origin HEAD:dev && git fetch -q origin dev && echo "pushed"
else
  git -C "$wt" merge --abort 2>/dev/null; echo "STOPPED: merge conflict or gitleaks finding"
fi
git worktree remove --force "$wt"; rmdir "$(dirname "$wt")"
```

`-X ours` keeps the published side of a conflicting hunk, as sync does.
Rerun the check block until every line says `published`.
On `STOPPED`, stop and ask.

## 4. Leave JJ and the old sync state

Moving `.jj` aside keeps its full history for recovery.

```sh
cd ~/.config/mise || exit 1; B=$(ls -d .git/dots-legacy-* | tail -n 1)
[ ! -d .jj ] || mv .jj "$B/jj"
[ ! -f .git/dots-dev.json ] || mv .git/dots-dev.json "$B/"
while read -r id ref; do git update-ref -d "$ref" "$id"; done < "$B/refs"
ls -a | grep -x .jj; git for-each-ref refs/dots
```

Check: the last line prints nothing.

## 5. Put HEAD on dev without touching files

```sh
cd ~/.config/mise || exit 1; B=$(ls -d .git/dots-legacy-* | tail -n 1)
git update-ref refs/heads/dev origin/dev
git symbolic-ref HEAD refs/heads/dev
git branch -q --set-upstream-to=origin/dev dev
git read-tree "$(cat "$B/base")"
git status --short --branch | head -n 1
git diff --stat
```

Check: the branch line reads `## dev...origin/dev`, and `git diff --stat` lists the same tracked edits as step 2.
`git status` also shows staged changes: those are other machines' work that the sync applies. Leave them alone.

## 6. Drop the archived Herdr entry from the local config

Herdr is archived, so its template no longer exists, and a `[dotfiles.herdr]` block left in the ignored `config.local.toml` would make sync reject the merged configuration.

```sh
cd ~/.config/mise || exit 1; B=$(ls -d .git/dots-legacy-* | tail -n 1)
f=config.local.toml
if [ -f "$f" ] && grep -q '^\[dotfiles\.herdr\][[:space:]]*$' "$f"; then
  awk '/^\[dotfiles\.herdr\][[:space:]]*$/ { skip = 1; next } skip && /^[[:space:]]*\[/ { skip = 0 } !skip' "$f" > "$f.new" &&
    chmod 600 "$f.new" && mv "$f.new" "$f" && echo "removed [dotfiles.herdr]"
fi
grep -n -i herdr "$f" || echo "no herdr entry"
[ ! -f "$B/$f" ] || diff "$B/$f" "$f" || :
```

Check: `no herdr entry`, and the `diff` shows only the removed block.

## 7. Sync once with the new manager

The manager in the checkout is still the old one until this sync updates the files, so run the new code from a scratch worktree of `origin/main`:

```sh
cd ~/.config/mise || exit 1
git fetch -q origin main
wt=$(mktemp -d)/main; git worktree add -q --detach "$wt" origin/main
mise exec -- node "$wt/manager/lib/source-repo.mjs" sync "$PWD"
git worktree remove --force "$wt"; rmdir "$(dirname "$wt")"
git status --short --branch | head -n 3
```

Check: one `dots sync:` block that ends in `pushed …` or `nothing to push`.
Its `dev moved outside sync …` line is expected: it means the base from step 2 was used.
Any `CONFLICT` lines name versions that lost to the published side; recover them with the printed `git show` command if they mattered.
`git status` is clean apart from files reported `NOT SHARED`.
From now on run `dots up` or `dots sync` as usual.
Delete the backup (`.git/dots-legacy-*`) and `refs/dots-legacy/*` after a week of normal syncs.

## Undo

Before step 7 no tracked file has changed, so this restores the old setup exactly, including the JJ working copy and `config.local.toml`:

```sh
cd ~/.config/mise || exit 1; B=$(ls -d .git/dots-legacy-* | tail -n 1); echo "$B"
[ ! -d "$B/jj" ] || mv "$B/jj" .jj
[ ! -f "$B/dots-dev.json" ] || mv "$B/dots-dev.json" .git/
[ ! -f "$B/config.local.toml" ] || cp -p "$B/config.local.toml" config.local.toml
while read -r id ref; do git update-ref "$ref" "$id"; done < "$B/refs"
if [ -s "$B/HEAD-ref" ]; then git symbolic-ref HEAD "$(cat "$B/HEAD-ref")"; else git update-ref --no-deref HEAD "$(cat "$B/HEAD")"; fi
if [ -s "$B/dev" ]; then git update-ref refs/heads/dev "$(cat "$B/dev")"; else git update-ref -d refs/heads/dev; fi
git config --remove-section branch.dev 2>/dev/null
while read -r key value; do git config "$key" "$value"; done < "$B/dev-config"
cp -p "$B/index" .git/index
git status --short --branch | head -n 3
```

Check: `git status` shows the same detached `HEAD` and edits as before step 1, and `jj st` shows the same working copy.
Commits pushed in step 3 stay on `origin/dev`; the old sync merges them like any other machine's work.
After step 7 the files have advanced to the merged `dev`: undo the refs as above only if you also want the old sync back, and expect it to see the new files as local edits.
