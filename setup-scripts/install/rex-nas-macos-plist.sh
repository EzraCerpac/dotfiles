#!/bin/sh
# Render the NAS definition without changing the app or any registered service.
set -eu
[ "$#" = 1 ] || { echo "Usage: $0 output-plist" >&2; exit 2; }
root=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
app=
for candidate in "$HOME/Applications/Rex Beta.app" '/Applications/Rex Beta.app'; do
  if [ -e "$candidate" ] || [ -L "$candidate" ]; then
    app=$candidate
    break
  fi
done
[ -n "$app" ] || { echo 'Install the signed Rex Beta app before registering the daemon.' >&2; exit 1; }
rex="$app/Contents/Helpers/Rex Server.rex/Contents/MacOS/rex"
[ -d "$app" ] && [ -f "$rex" ] && [ -x "$rex" ] || {
  echo "Rex app has no executable server helper at $rex." >&2; exit 1;
}
requirement='=anchor apple generic and certificate leaf[subject.OU] = "AG92C3PT77" and identifier "com.superlogical.rex"'
codesign --verify --deep --strict -R "$requirement" "$app"
# Replace explicitly: some plutil versions insert for -replace on array indices.
plutil -remove ProgramArguments.0 -o "$1" "$root/resources/rex/com.ezra.rex-nas.plist"
plutil -insert ProgramArguments.0 -string "$rex" "$1"
plutil -lint "$1"
