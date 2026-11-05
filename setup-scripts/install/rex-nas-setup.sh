#!/bin/sh
# Configure only the personal Rex server. Updating never restarts a running server.
set -eu
mode=${1:---setup}
case "$mode" in --setup|--update-existing) ;; *) echo "Usage: $0 [--setup|--update-existing]" >&2; exit 2 ;; esac
[ "$#" -le 1 ] || { echo "Too many arguments" >&2; exit 2; }

case "$(uname -s):$(hostname -s | tr '[:upper:]' '[:lower:]')" in
  Linux:cerpacnas)
    base="$HOME/.local/opt/rex"
    state="$HOME/.local/state/rex-nas"
    unit="$HOME/.config/systemd/user/rex-nas.service"
    if [ "$mode" = --update-existing ] && { [ ! -L "$base/current" ] || [ ! -f "$unit" ]; }; then
      echo 'Rex NAS service is not provisioned; skipping update.'
      exit 0
    fi
    mkdir -p "$base" "$state" "$(dirname "$unit")"
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT HUP INT TERM
    curl -fsSL --connect-timeout 15 --max-time 300 https://blob.superlogical.com/api/releases/rex/snapshot > "$tmp/release.json"
    node - "$tmp/release.json" > "$tmp/release" <<'JS'
const fs = require('fs');
const release = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const commit = release.commit;
const artifacts = release.artifacts.filter(a => a.filename === 'rex-linux-amd64.tar.gz');
if (!/^[0-9a-f]{40}$/.test(commit) || artifacts.length !== 1 || !/^[0-9a-f]{64}$/.test(artifacts[0].sha256)) {
  throw new Error('Invalid Rex release metadata');
}
console.log(commit, artifacts[0].sha256);
JS
    read -r commit checksum < "$tmp/release"
    if [ ! -x "$base/$commit/rex" ]; then
      curl -fsSL --connect-timeout 15 --max-time 300 "https://blob.superlogical.com/download/rex/snapshot/$commit/rex-linux-amd64.tar.gz" > "$tmp/rex.tar.gz"
      printf '%s  %s\n' "$checksum" "$tmp/rex.tar.gz" | sha256sum -c -
      [ "$(tar -tzf "$tmp/rex.tar.gz")" = rex ] || { echo 'Unexpected archive contents' >&2; exit 1; }
      mkdir -p "$base/$commit"
      tar -xzf "$tmp/rex.tar.gz" -C "$base/$commit"
      "$base/$commit/rex" version
    fi
    previous=$(readlink "$base/current" || true)
    ln -sfn "$base/$commit/rex" "$base/current"
    cat > "$tmp/rex-nas.service" <<UNIT
[Unit]
Description=Personal Rex server (CerpacNAS)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=HOME=$HOME
Environment=SHELL=$HOME/.local/bin/fish
Environment=PATH=$HOME/.local/bin:$HOME/.local/share/mise/shims:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=$base/current server run --tailscale --tailscale-hostname rex-cerpacnas --state-dir $state
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
UNIT
    changed=0
    if ! cmp -s "$tmp/rex-nas.service" "$unit"; then
      cp "$tmp/rex-nas.service" "$unit"
      systemctl --user daemon-reload
      changed=1
    fi
    if [ "$mode" = --setup ]; then
      systemctl --user enable rex-nas.service
    fi
    if systemctl --user is-active --quiet rex-nas.service; then
      running_pid=$(systemctl --user show rex-nas.service --property MainPID --value)
      running_binary=
      case "$running_pid" in ''|*[!0-9]*) ;; *) running_binary=$(readlink "/proc/$running_pid/exe" || true) ;; esac
      if [ "$previous" != "$base/$commit/rex" ] || [ "$changed" = 1 ] || { [ -n "$running_binary" ] && [ "$running_binary" != "$base/$commit/rex" ]; }; then
        echo 'Rex update staged; restart rex-nas.service explicitly when sessions may be interrupted.'
      fi
    elif [ "$mode" = --setup ]; then
      systemctl --user start rex-nas.service
    else
      echo 'Rex service is stopped; update staged without starting it.'
    fi
    ;;
  Darwin:driehuisnas)
    if [ "$mode" = --setup ]; then
      sh "$(dirname "$0")/rex-macos-install.sh"
    fi
    plist="$(dirname "$0")/../../resources/rex/com.ezra.rex-nas.plist"
    if [ -f /Library/LaunchDaemons/com.ezra.rex-nas.plist ] && ! cmp -s "$plist" /Library/LaunchDaemons/com.ezra.rex-nas.plist; then
      echo 'Rex daemon configuration changed; apply and restart explicitly when sessions may be interrupted.'
    fi
    echo 'Use rex:install-daemon for initial boot registration on DriehuisNAS.'
    echo 'Running servers are never restarted by this setup helper.'
    ;;
  *) echo 'Rex NAS setup is restricted to the selected NAS hosts.' >&2; exit 1 ;;
esac
