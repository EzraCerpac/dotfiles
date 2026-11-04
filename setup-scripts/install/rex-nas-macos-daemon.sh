#!/bin/sh
# Initial boot registration only. Run interactively as the server account.
set -eu
[ "$(uname -s):$(hostname -s | tr '[:upper:]' '[:lower:]'):$(id -un)" = Darwin:driehuisnas:server ] || {
  echo 'Run as server on DriehuisNAS.' >&2; exit 1;
}
root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
plist="$root/resources/rex/com.ezra.rex-nas.plist"
target=/Library/LaunchDaemons/com.ezra.rex-nas.plist
app="$HOME/Applications/Rex Beta.app"
plutil -lint "$plist"
codesign --verify --deep --strict "$app"
if [ -e "$target" ]; then
  if ! cmp -s "$plist" "$target"; then
    echo 'Daemon configuration changed; apply and restart explicitly when sessions may be interrupted.'
  fi
  exit 0
fi
if "$app/Contents/Helpers/Rex Server.rex/Contents/MacOS/rex" --autostart=false whoami >/dev/null 2>&1; then
  echo 'A personal Rex server is already running. Stop it explicitly before initial boot registration.' >&2
  exit 1
fi
sudo install -o root -g wheel -m 0644 "$plist" "$target"
sudo launchctl bootstrap system "$target"
