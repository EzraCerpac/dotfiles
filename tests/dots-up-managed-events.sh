#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
command -v jq >/dev/null || exit 77
source "$root/setup-scripts/lib/brew-exception.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export DOTS_UP_EVENT_FD=3 DOTS_UP_STAGE_ID=installer-exception-test FIXTURE="$tmp"
exec 3>"$tmp/events"
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
update_brew_formula_exception antoniorodr/memo/memo
update_brew_formula_exception antoniorodr/memo/memo
: > "$tmp/outdated"
update_brew_formula_exception antoniorodr/memo/memo
update_brew_formula_exception antoniorodr/memo/memo
: > "$tmp/fail"
if update_brew_formula_exception antoniorodr/memo/memo; then exit 1; fi
jq -s -e 'length == 2 and .[0].action == "installed" and .[0].after == "1" and .[1].action == "updated" and .[1].before == "1" and .[1].after == "2" and all(.[]; .stage == "installer-exception-test")' "$tmp/events" >/dev/null
rm -f "$tmp/version" "$tmp/outdated" "$tmp/fail"
exec 3>"$tmp/events"
update_brew_cask_exception brooklyn
: > "$tmp/outdated"
update_brew_cask_exception brooklyn
jq -s -e 'length == 2 and .[0].item == "brew-cask:brooklyn" and .[0].action == "installed" and .[1].action == "updated" and .[1].before == "1" and .[1].after == "2"' "$tmp/events" >/dev/null
printf 'managed event fixture passed\n' 
