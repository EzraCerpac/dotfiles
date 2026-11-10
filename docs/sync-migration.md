# Convert a live checkout for stateless sync

`dots sync` works on one shape only: `~/.config/mise` is a plain Git checkout with `HEAD` on `dev`.
It stops with a message pointing here when it finds `.jj`, `.git/dots-dev.json`, a detached `HEAD`, or another branch.
Convert each existing machine once, by hand, over SSH.
The steps below change no file in the checkout, only Git refs, the Git index and the legacy state; the final sync then updates files as usual.

Run every block from the live checkout, in order, and look at each check before continuing.
Make sure no other agent is editing `~/.config/mise` meanwhile.

## 1. Record the current state

```sh
cd ~/.config/mise
stamp=$(date +%Y%m%d%H%M%S); B=.git/dots-legacy-$stamp; mkdir "$B"
git rev-parse HEAD > "$B/HEAD"
git rev-parse --verify -q refs/heads/dev > "$B/dev" || : > "$B/dev"
git for-each-ref --format='%(objectname) %(refname)' refs/dots > "$B/refs"
while read -r id ref; do git update-ref "refs/dots-legacy/$stamp/${ref#refs/dots/}" "$id"; done < "$B/refs"
echo "$B"; cat "$B/HEAD" "$B/dev" "$B/refs"
```

Check: the backup directory exists and lists `HEAD`, `dev` and any `refs/dots/queue` or `refs/dots/capture`.

## 2. Find the commit the files are based on

The old sync recorded it as `applied` in `.git/dots-dev.json`.
JJ may have moved `HEAD` since without changing files, so prefer `applied` when it exists.

```sh
base=$(sed -n 's/.*"applied":"\([0-9a-f]\{40\}\)".*/\1/p' .git/dots-dev.json 2>/dev/null)
base=${base:-$(cat "$B/HEAD")}; echo "$base" > "$B/base"
git diff --stat "$base"
```

Check: the diffstat lists only edits made on this machine.
If it also shows other machines' recent changes as deletions or reverts, the base is wrong: try `git diff --stat "$(cat "$B/HEAD")"` and use whichever lists only local edits.

## 3. Publish queued work

```sh
git fetch origin dev main
for ref in refs/dots/queue refs/dots/capture; do
  id=$(git rev-parse --verify -q "$ref") || continue
  git merge-base --is-ancestor "$id" origin/dev && echo "$ref published" || echo "$ref NOT published: $id"
done
git merge-base --is-ancestor "$base" origin/dev && echo "base published" || echo "base NOT published"
```

Check: every line says `published`.
For each commit that is not, merge it into `dev` in a scratch worktree (`-X ours` keeps the published side on conflicts, as sync does), scan, and push:

```sh
wt=$(mktemp -d)/dev; git worktree add --detach "$wt" origin/dev
git -C "$wt" merge --no-edit -X ours <COMMIT>
gitleaks git --no-banner --redact --config .gitleaks.toml --log-opts="--diff-merges=first-parent origin/dev..HEAD" "$wt"
git -C "$wt" push origin HEAD:dev && git fetch origin dev
git worktree remove --force "$wt"
```

Rerun the check block until every line says `published`.
Stop and ask if gitleaks reports a finding.

## 4. Leave JJ and the old sync state

The live checkout no longer supports JJ (see [why](../README.md#sync-dev-and-main)).
Moving `.jj` aside keeps its full history for recovery.

```sh
[ -d .jj ] && mv .jj "$B/jj"
[ -f .git/dots-dev.json ] && mv .git/dots-dev.json "$B/"
while read -r id ref; do git update-ref -d "$ref" "$id"; done < "$B/refs"
```

Check: `ls -a` shows no `.jj`, and `git for-each-ref refs/dots` prints nothing.

## 5. Put HEAD on dev without touching files

```sh
git update-ref refs/heads/dev origin/dev
git symbolic-ref HEAD refs/heads/dev
git branch -q --set-upstream-to=origin/dev dev
git read-tree "$base"
git status --short --branch | head
git diff --stat
```

Check: the branch line reads `## dev...origin/dev`, and `git diff --stat` matches step 2 except that new files now show as `??`.
Staged changes in `git status` are other machines' work that the next sync applies; leave them alone.

## 6. Sync once with the new manager

The manager in the checkout is still the old one until this first sync updates the files, so run the new code from a scratch worktree of `origin/dev`:

```sh
wt=$(mktemp -d)/dev; git worktree add --detach "$wt" origin/dev
mise exec -- node "$wt/manager/lib/source-repo.mjs" sync "$PWD"
git worktree remove --force "$wt"
git status --short --branch | head -3
```

Check: one `dots sync:` block that ends in `pushed …` or `nothing to push`, any `CONFLICT` lines are expected losers, and `git status` is clean apart from files reported `NOT SHARED`.
From now on run `dots up` or `dots sync` as usual.
Delete `$B` (`.git/dots-legacy-*`) and `refs/dots-legacy/*` after a week of normal syncs.

## Undo

Before step 6 nothing on disk has changed, so undoing restores the old setup exactly:

```sh
cd ~/.config/mise; B=.git/dots-legacy-<stamp>
[ -d "$B/jj" ] && mv "$B/jj" .jj
[ -f "$B/dots-dev.json" ] && mv "$B/dots-dev.json" .git/
while read -r id ref; do git update-ref "$ref" "$id"; done < "$B/refs"
[ -s "$B/dev" ] && git update-ref refs/heads/dev "$(cat "$B/dev")"
git update-ref --no-deref HEAD "$(cat "$B/HEAD")"
git read-tree "$(cat "$B/base")"
```

After step 6 the files have advanced to the merged `dev`; undo the refs as above only if you also want the old sync back, and expect it to see the new files as local edits.
Work pushed in step 3 or 6 stays on `origin/dev`.
