#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
command -v jq >/dev/null || exit 77
source "$root/setup-scripts/lib/dots-up-events.sh"
setup_mise() {
    if [[ "$1" == ls ]]; then cat "$tmp/tools.json"; else [[ "$1" == exec && "$2" == -- ]]; shift 2; "$@"; fi
}
eval "$(sed -n '/^snapshot_stage() {/,/^if dots_up_event_sink_enabled &&/p' "$root/setup-scripts/setup/update" | sed '$d')"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export DOTS_UP_EVENT_FD=3
exec 3>"$tmp/events"
emit_event() { dots_up_emit_event "$1"; }
emit_snapshot_changes test '[{"item":"old","value":"1"},{"item":"removed","value":"a"},{"item":"same","value":"s"}]' '[{"item":"old","value":"2"},{"item":"new","value":"b"},{"item":"same","value":"s"}]'
jq -s -e 'length == 3 and ([.[] | select(.item == "new" and .action == "installed" and .before == "not installed" and .after == "b")] | length == 1) and ([.[] | select(.item == "old" and .action == "updated" and .before == "1" and .after == "2")] | length == 1) and ([.[] | select(.item == "removed" and .action == "removed" and .before == "a" and .after == "not installed")] | length == 1)' "$tmp/events" >/dev/null
printf '%s' '{"a":[{"active":true,"installed":false,"version":"1"}],"b":[{"active":true,"installed":true,"version":"2"}]}' > "$tmp/tools.json"
[[ "$(snapshot_stage Tools 'newly declared mise tools')" == '[{"item":"b","value":"2"}]' ]]
export JW_INSTALL_DIR="$tmp/bin"; mkdir -p "$tmp/bin" "$tmp/ver"; printf '%040d\n' 1 > "$tmp/ver/source-commit"; touch "$tmp/ver/jw"; ln -s "$tmp/ver/jw" "$tmp/bin/jw"
[[ "$(snapshot_stage 'Managed apps/local builds' 'jw main source' | jq -r '.[0].value')" == "$(printf '%040d' 1)" ]]
rm "$tmp/ver/source-commit"
if snapshot_stage 'Managed apps/local builds' 'jw main source' >/dev/null; then exit 1; fi
rm "$tmp/bin/jw"
[[ "$(snapshot_stage 'Managed apps/local builds' 'jw main source')" == '[]' ]]
printf 'snapshot fixture passed\n'
