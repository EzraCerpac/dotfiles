#!/usr/bin/env bash
# dots up turns stage snapshots and DOTS_CHANGES reports into change events
# with an installed, updated, removed or changed action.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd -P)"
command -v jq >/dev/null || exit 77
source "$root/lib/dots-up-events.sh"
setup_mise() {
    if [[ "$1" == ls ]]; then cat "$tmp/tools.json"; else [[ "$1" == exec && "$2" == -- ]]; shift 2; "$@"; fi
}
resolve_mise_bin() { printf '%s' "$tmp/mise"; }
eval "$(sed -n '/^snapshot_stage() {/,/^if dots_up_event_sink_enabled &&/p' "$root/tasks/update" | sed '$d')"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export DOTS_UP_EVENT_FD=3
exec 3>"$tmp/events"
emit_event() { dots_up_emit_event "$1"; }
event_json() { dots_up_event_json "$@"; }
emit_snapshot_changes test '[{"item":"old","value":"1"},{"item":"removed","value":"a"},{"item":"same","value":"s"}]' '[{"item":"old","value":"2"},{"item":"new","value":"b"},{"item":"same","value":"s"}]'
jq -s -e 'length == 3 and ([.[] | select(.item == "new" and .action == "installed" and .before == "not installed" and .after == "b")] | length == 1) and ([.[] | select(.item == "old" and .action == "updated" and .before == "1" and .after == "2")] | length == 1) and ([.[] | select(.item == "removed" and .action == "removed" and .before == "a" and .after == "not installed")] | length == 1)' "$tmp/events" >/dev/null
printf '%s' '{"a":[{"active":true,"installed":false,"version":"1"}],"b":[{"active":true,"installed":true,"version":"2"}]}' > "$tmp/tools.json"
[[ "$(snapshot_stage Tools 'newly declared mise tools')" == '[{"item":"b","value":"2"}]' ]]
# The standalone mise stage compares mise's own version, not the tool list.
printf '#!/usr/bin/env bash\necho "2026.11.0 macos-arm64"\n' > "$tmp/mise"; chmod +x "$tmp/mise"
[[ "$(snapshot_stage Tools 'standalone mise')" == '[{"item":"mise","value":"2026.11.0 macos-arm64"}]' ]]
printf '#!/usr/bin/env bash\nexit 1\n' > "$tmp/mise"
if snapshot_stage Tools 'standalone mise' >/dev/null; then exit 1; fi
# Hook and installer exception reports share the same actions.
exec 3>"$tmp/events"
printf 'pkg-new\tnot installed\t1\npkg-old\t1\t2\npkg-gone\t3\t\nrebuilt\t4\t4\n' > "$tmp/changes"
emit_reported_changes reports "$tmp/changes" >/dev/null
jq -s -e '[.[] | [.stage, .item, .action, .before, .after]] == [
    ["reports", "pkg-new", "installed", "not installed", "1"],
    ["reports", "pkg-old", "updated", "1", "2"],
    ["reports", "pkg-gone", "removed", "3", ""],
    ["reports", "rebuilt", "changed", "4", "4"]]' "$tmp/events" >/dev/null
printf 'snapshot fixture passed\n'
