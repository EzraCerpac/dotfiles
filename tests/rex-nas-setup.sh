#!/bin/sh
set -eu
repo=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
export HOME="$tmp/home" TEST_LOG="$tmp/systemctl.log"
mkdir -p "$HOME" "$tmp/bin"
real_node=$(command -v node)
cat > "$tmp/bin/uname" <<'MOCK'
#!/bin/sh
echo Linux
MOCK
cat > "$tmp/bin/hostname" <<'MOCK'
#!/bin/sh
echo CerpacNAS
MOCK
cat > "$tmp/bin/curl" <<'MOCK'
#!/bin/sh
printf '%s\n' '{"commit":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","artifacts":[{"filename":"rex-linux-amd64.tar.gz","sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}]}'
MOCK
cat > "$tmp/bin/systemctl" <<'MOCK'
#!/bin/sh
printf '%s\n' "$*" >> "$TEST_LOG"
case "$*" in *is-active*) exit 1 ;; esac
MOCK
ln -s "$real_node" "$tmp/bin/node"
chmod +x "$tmp/bin/uname" "$tmp/bin/hostname" "$tmp/bin/curl" "$tmp/bin/systemctl"
export PATH="$tmp/bin:$PATH"
sh "$repo/setup-scripts/install/rex-nas-setup.sh" --update-existing
[ ! -e "$TEST_LOG" ]
base="$HOME/.local/opt/rex"
mkdir -p "$base/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" "$HOME/.config/systemd/user"
printf '#!/bin/sh\nexit 0\n' > "$base/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/rex"
chmod +x "$base/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/rex"
ln -s "$base/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/rex" "$base/current"
touch "$HOME/.config/systemd/user/rex-nas.service"
sh "$repo/setup-scripts/install/rex-nas-setup.sh" --update-existing
if grep -E ' (start|restart|enable) ' "$TEST_LOG"; then exit 1; fi
: > "$TEST_LOG"
sh "$repo/setup-scripts/install/rex-nas-setup.sh" --update-existing
if grep -E ' (start|restart|enable|daemon-reload) ' "$TEST_LOG"; then exit 1; fi
echo 'Rex NAS setup fixtures passed'
