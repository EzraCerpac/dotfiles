# Drop the generated history declarations

The files kept in encrypted settings history are declared in `config.workstation.toml` and `config.nas.toml`,
as `mode = "track"` entries with one `{ profile = "host-<machine-id>" }` variant per machine.
Machines enrolled earlier also have the same entries in their ignored `config.host-<machine-id>.toml`,
written by the old `enroll-history`.
The two copies are identical, and the local one takes precedence, so nothing has to happen on any machine:
the history stream (`home@host-<machine-id>/…`), branch, keys and checkpoints stay the same either way.
This optional cleanup removes the generated local copies, once per machine, by hand.

Run the blocks in order and read each check before continuing.
The blocks are POSIX `sh`; start `sh` and paste each one, or feed it on standard input (`ssh HOST sh < block.sh`).
Run `dots up` first, so the checkout has the shared entries.

## 1. Check the machine

```sh
cd ~/.config/mise || exit 1
id=$(mise config get --file config.local.toml env.SETUP_MACHINE_ID); role=$(mise config get --file config.local.toml env.SETUP_PROFILE)
echo "id=$id role=$role branch=$(mise config get --file config.local.toml history.origin.branch)"
grep -c "profile = \"host-$id\"" "config.$role.toml"
ls "config.host-$id.toml"
```

Check: `branch=host-<id>`, a count that is not 0, and the file name.
A count of 0 means the shared entries do not name this machine yet:
add `{ profile = "host-<id>" }` to the variants of each file it keeps in `config.<role>.toml`, through a reviewed change, and start again.
No `config.host-<id>.toml` means there is nothing to clean up.

## 2. Record the current state

```sh
cd ~/.config/mise || exit 1
id=$(mise config get --file config.local.toml env.SETUP_MACHINE_ID)
H=${MISE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/mise}/history
B=$H/declarations-$(date +%Y%m%d%H%M%S); mkdir -m 700 "$B" || exit 1
cp -p "config.host-$id.toml" "$B/"
git --git-dir="$H/repo.git" rev-parse HEAD > "$B/HEAD"
mise dot paths --json | jq -S '[.entries[] | {path, mode, variant, files}] | sort' > "$B/before.json"
echo "$B"; cat "$B/HEAD"; jq -r '.[] | "\(.variant) \(.path)"' "$B/before.json"
```

Check: it prints the backup directory, the history commit, and every tracked file with variant `host-<id>`.

## 3. Remove the generated entries and compare

The old `enroll-history` wrote a header comment and, per file, a `[dotfiles."~/PATH"]` table holding exactly
`mode = "track"`, `encrypt = true` and `variants = [{ profile = "host-<id>" }]`.
This block removes those and keeps everything else, such as `[tools]`; it deletes the file only when nothing else is left.

```sh
cd ~/.config/mise || exit 1
id=$(mise config get --file config.local.toml env.SETUP_MACHINE_ID); f=config.host-$id.toml
H=${MISE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/mise}/history; B=$(ls -d "$H"/declarations-* | tail -n 1); echo "$B"
awk -v id="$id" '
  function flush() { if (n && !generated) printf "%s", kept; kept = ""; n = 0 }
  /^\[/ { flush(); if ($0 ~ /^\[dotfiles\./) { n = 1; generated = 1; kept = $0 "\n"; next } }
  n { kept = kept $0 "\n"
      if ($0 != "" && $0 != "mode = \"track\"" && $0 != "encrypt = true" &&
          $0 != "variants = [{ profile = \"host-" id "\" }]") generated = 0
      next }
  $0 == "# Encrypted exact-file history entries for host-" id "." { next }
  { print }
  END { flush() }' "$B/$f" > "$f.new" || exit 1
if grep -q '[^[:space:]]' "$f.new"; then chmod 644 "$f.new" && mv "$f.new" "$f"; echo "kept:"; cat "$f"; else rm "$f.new" "$f"; echo "removed $f"; fi
mise dot paths --json | jq -S '[.entries[] | {path, mode, variant, files}] | sort' > "$B/after.json"
diff "$B/before.json" "$B/after.json" && echo "same tracked files"
mise dot paths
```

Check: `removed config.host-<id>.toml`, or `kept:` followed only by settings that are not generated history entries;
`same tracked files`; and `mise dot paths` names `config.<role>.toml` for every entry this machine had in its local file.
Any `diff` output means the shared entries differ from the generated ones: run [Undo](#undo).

## 4. Confirm the history is unchanged

```sh
cd ~/.config/mise || exit 1
id=$(mise config get --file config.local.toml env.SETUP_MACHINE_ID)
H=${MISE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/mise}/history; B=$(ls -d "$H"/declarations-* | tail -n 1); echo "$B"
mise dot save
git --git-dir="$H/repo.git" diff --stat "$(cat "$B/HEAD")" HEAD
git --git-dir="$H/repo.git" ls-tree -r --name-only HEAD | grep -v -e '^\.mise-history/' -e "^home@host-$id/" || echo "only host-$id streams"
mise dot rollback --to latest --all --dry-run
mise config get --file config.local.toml history.origin.branch
```

Check: the save reports `no file changes` or only edits made since the last checkpoint,
the diffstat lists no added or removed file under another stream,
`only host-<id> streams`, the dry run says every path already matches (so this machine still decrypts its checkpoint),
and the branch is still `host-<id>`.
Publish as usual with `dots backup`.
Delete the backup directory after a week of normal backups.

## Undo

```sh
cd ~/.config/mise || exit 1
id=$(mise config get --file config.local.toml env.SETUP_MACHINE_ID)
H=${MISE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/mise}/history; B=$(ls -d "$H"/declarations-* | tail -n 1); echo "$B"
cp -p "$B/config.host-$id.toml" .
mise dot paths --json | jq -S '[.entries[] | {path, mode, variant, files}] | sort' | diff "$B/before.json" - && echo "restored"
```

Check: `restored`, and `mise dot paths` names `config.host-<id>.toml` again for the generated entries.
The undo copies the whole file back, including anything step 3 kept.
History needs no undo: no step rewrites a checkpoint, the branch or a key.
