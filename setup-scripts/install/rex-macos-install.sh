#!/bin/sh
# First install only. Existing apps and running Rex servers are never replaced.
set -eu
[ "$(uname -s)" = Darwin ] || { echo 'Rex macOS installer requires macOS.' >&2; exit 1; }
for app in "$HOME/Applications/Rex Beta.app" '/Applications/Rex Beta.app'; do
  if [ -e "$app" ]; then
    echo "Rex app already exists at $app; leaving it unchanged."
    exit 0
  fi
done
major=$(sw_vers -productVersion | cut -d. -f1)
case "$major" in ''|*[!0-9]*) echo 'Cannot determine macOS version.' >&2; exit 1 ;; esac
[ "$major" -ge 15 ] || { echo 'Rex requires macOS 15 or newer.' >&2; exit 1; }
case "$(uname -m)" in x86_64|arm64) ;; *) echo 'Unsupported Mac architecture.' >&2; exit 1 ;; esac
mkdir -p "$HOME/Applications"
tmp=$(mktemp -d "$HOME/Applications/.rex-install.XXXXXX")
mounted=0
cleanup() {
  if [ "$mounted" = 1 ] && ! hdiutil detach "$tmp/mount" >/dev/null; then
    echo "Could not detach task image at $tmp/mount; retained $tmp." >&2
    return
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT HUP INT TERM
mkdir "$tmp/mount"
curl -fsSL --connect-timeout 15 --max-time 300 \
  https://blob.superlogical.com/public/rex-app/preview/Rex-0.1.0-1758.dmg -o "$tmp/rex.dmg"
hdiutil attach -readonly -nobrowse -mountpoint "$tmp/mount" "$tmp/rex.dmg" >/dev/null
mounted=1
source_app="$tmp/mount/Rex Beta.app"
requirement='=anchor apple generic and certificate leaf[subject.OU] = "AG92C3PT77" and identifier "com.superlogical.rex"'
codesign --verify --deep --strict -R "$requirement" "$source_app"
ditto "$source_app" "$tmp/Rex Beta.app"
codesign --verify --deep --strict -R "$requirement" "$tmp/Rex Beta.app"
if [ -e "$HOME/Applications/Rex Beta.app" ] || [ -e '/Applications/Rex Beta.app' ]; then
  echo 'Rex appeared during installation; leaving the existing app unchanged.'
  exit 0
fi
mv -n "$tmp/Rex Beta.app" "$HOME/Applications/Rex Beta.app"
[ ! -e "$tmp/Rex Beta.app" ] || { echo 'Rex appeared during installation; leaving it unchanged.' >&2; exit 1; }
echo "Installed signed Rex Beta app at $HOME/Applications/Rex Beta.app."
