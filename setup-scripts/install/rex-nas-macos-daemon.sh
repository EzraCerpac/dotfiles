#!/bin/sh
# Initial boot registration only. Run interactively as the server account.
set -eu
[ "$(uname -s):$(hostname -s | tr '[:upper:]' '[:lower:]'):$(id -un)" = Darwin:driehuisnas:server ] || {
  echo 'Run as server on DriehuisNAS.' >&2; exit 1;
}
root=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
target=/Library/LaunchDaemons/com.ezra.rex-nas.plist
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
plist="$tmp/com.ezra.rex-nas.plist"
sh "$root/setup-scripts/install/rex-nas-macos-plist.sh" "$plist"
if [ -e "$target" ] || [ -L "$target" ]; then
  # Compare effective values, not the source template's XML formatting.
  if ! plutil -convert xml1 -o "$tmp/existing.plist" "$target" || ! cmp -s "$plist" "$tmp/existing.plist"; then
    echo 'Daemon configuration changed; apply and restart explicitly when sessions may be interrupted.'
  fi
  exit 0
fi
rex=$(plutil -extract ProgramArguments.0 raw -o - "$plist")
if "$rex" --autostart=false whoami >/dev/null 2>&1; then
  echo 'A personal Rex server is already running. Stop it explicitly before initial boot registration.' >&2
  exit 1
fi
# Link a root-owned copy atomically so a daemon appearing meanwhile is preserved.
sudo install -o root -g wheel -m 0644 "$plist" "$tmp/registered.plist"
if ! sudo /bin/link "$tmp/registered.plist" "$target"; then
  echo 'Daemon was not registered; existing definitions are never replaced.' >&2
  exit 1
fi
sudo launchctl bootstrap system "$target"
