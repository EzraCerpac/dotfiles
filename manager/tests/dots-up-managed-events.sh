#!/usr/bin/env bash
# Homebrew exception helpers report verified installs and upgrades, and nothing
# else, through the stage's DOTS_CHANGES file.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
source "$root/lib/brew-exception.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export DOTS_CHANGES="$tmp/changes" FIXTURE="$tmp"
: > "$DOTS_CHANGES"
cat > "$tmp/brew" <<'BREW'
#!/usr/bin/env bash
case "$1" in
 list)
   [[ -f "$FIXTURE/version" ]] || exit 1
   if [[ "$2" == --versions ]]; then printf 'memo %s\n' "$(cat "$FIXTURE/version")"; fi ;;
 install) [[ ! -f "$FIXTURE/fail" ]] || exit 8; printf 1 > "$FIXTURE/version" ;;
 outdated) [[ -f "$FIXTURE/outdated" ]] && echo memo; exit 0 ;;
 upgrade) [[ ! -f "$FIXTURE/fail" ]] || exit 8; printf 2 > "$FIXTURE/version" ;;
esac
BREW
chmod +x "$tmp/brew"
uname() { printf Darwin; }
find_real_brew() { printf '%s' "$tmp/brew"; }
expect() {
    local wanted
    wanted="$(printf '%b' "$1")"
    [[ "$(cat "$DOTS_CHANGES")" == "$wanted" ]] || {
        printf 'unexpected DOTS_CHANGES:\n%s\nwanted:\n%s\n' "$(cat "$DOTS_CHANGES")" "$wanted" >&2
        exit 1
    }
}
update_brew_formula_exception antoniorodr/memo/memo
update_brew_formula_exception antoniorodr/memo/memo
: > "$tmp/outdated"
update_brew_formula_exception antoniorodr/memo/memo
update_brew_formula_exception antoniorodr/memo/memo
: > "$tmp/fail"
if update_brew_formula_exception antoniorodr/memo/memo; then exit 1; fi
expect 'brew-formula:antoniorodr/memo/memo\tnot installed\t1\nbrew-formula:antoniorodr/memo/memo\t1\t2'
rm -f "$tmp/version" "$tmp/outdated" "$tmp/fail"
: > "$DOTS_CHANGES"
update_brew_cask_exception brooklyn
: > "$tmp/outdated"
update_brew_cask_exception brooklyn
expect 'brew-cask:brooklyn\tnot installed\t1\nbrew-cask:brooklyn\t1\t2'
# Without a DOTS_CHANGES file (bootstrap, a direct run) nothing is reported.
rm -f "$tmp/version" "$tmp/outdated"
unset DOTS_CHANGES
update_brew_cask_exception brooklyn
printf 'managed event fixture passed\n'
