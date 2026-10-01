#!/usr/bin/env bash
set -euo pipefail
umask 077
# shellcheck source=setup-scripts/local/capd-common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/capd-common.sh"

[[ $# -eq 1 ]] || { setup_error 'usage: local:capd-install -- /absolute/path/to/stage'; exit 2; }
stage="$(cd -- "$1" && pwd -P)"
require_file "$stage/BUILD-INFO"
capd_validate_app "$stage/capd.app"
app=/Applications/capd.app
data="$HOME/Library/Application Support/capd"
cli="$HOME/.local/bin/capd"
agent_plist="$HOME/Library/LaunchAgents/dev.jxd.capd.agent.plist"
agent="gui/$(id -u)/dev.jxd.capd.agent"
domain=dev.jxd.capd
for directory in "$app" "$data"; do
    [[ ! -L "$directory" && ( ! -e "$directory" || -d "$directory" ) ]] || {
        setup_error "refusing non-directory or symlink: $directory"; exit 1;
    }
done
[[ ! -e "$cli" || -L "$cli" ]] || { setup_error "CLI path has an unmanaged regular file: $cli"; exit 1; }
[[ -d /Applications && -w /Applications ]] || { setup_error '/Applications must be writable'; exit 1; }
app_running=0
agent_loaded=0
pgrep -x CapdApp >/dev/null && app_running=1
/bin/launchctl print "$agent" >/dev/null 2>&1 && agent_loaded=1
if (( agent_loaded )); then
    require_file "$agent_plist"
    [[ "$(/usr/bin/plutil -extract ProgramArguments.0 raw -o - "$agent_plist")" == "$app/Contents/MacOS/capd-agent" ]] || {
        setup_error 'loaded agent uses another installation; reconcile it first'; exit 1;
    }
fi
backup_root="${CAPD_BACKUP_ROOT:-${HOME}/.local/state/capd/backups}"
mkdir -p "$backup_root" "$(dirname "$cli")"
backup="$(mktemp -d "$backup_root/$(date -u +%Y%m%dT%H%M%SZ).XXXXXX")"
had_app=0
had_data=0
had_cli=0
had_preferences=0
[[ -d "$app" ]] && had_app=1
[[ -d "$data" ]] && had_data=1
[[ -L "$cli" ]] && { cp -P "$cli" "$backup/capd-cli"; had_cli=1; }
[[ ! -f "$agent_plist" ]] || cp -p "$agent_plist" "$backup/agent.plist"
stopped=0
swapped=0
snapshot=0

stop_capd() {
    if pgrep -x CapdApp >/dev/null; then
        /usr/bin/osascript -e 'tell application id "dev.jxd.capd" to quit' >/dev/null 2>&1 || true
    fi
    if /bin/launchctl print "$agent" >/dev/null 2>&1; then
        /bin/launchctl bootout "$agent" || return 1
    fi
    # Both writers must exit before copying SQLite's database and WAL together.
    local attempt
    for attempt in {1..50}; do
        if ! pgrep -x CapdApp >/dev/null && ! pgrep -x capd-agent >/dev/null; then return 0; fi
        sleep 0.1
    done
    setup_error 'capd processes did not stop; preserving the current installation'
    return 1
}

restart_previous_state() {
    if (( agent_loaded )); then
        /bin/launchctl print "$agent" >/dev/null 2>&1 || /bin/launchctl bootstrap "gui/$(id -u)" "$agent_plist" || return 1
        /bin/launchctl kickstart "$agent" || return 1
    fi
    # The app also installs its agent on launch; load it first to avoid a race.
    if (( app_running )); then /usr/bin/open "$app" || return 1; fi
}

finish() {
    local result=$? rollback_failed=0
    trap - EXIT INT TERM
    set +e
    if (( result != 0 )); then
        if (( swapped )); then
            if stop_capd; then
                [[ ! -e "$app" ]] || mv "$app" "$backup/failed-app" || rollback_failed=1
                # Never nest the old bundle inside a failed app we could not move.
                if (( had_app && rollback_failed == 0 )); then mv "$backup/previous-app" "$app" || rollback_failed=1; fi
                [[ ! -e "$cli" && ! -L "$cli" ]] || rm -f "$cli" || rollback_failed=1
                if (( had_cli )); then cp -P "$backup/capd-cli" "$cli" || rollback_failed=1; fi
                if [[ -f "$backup/agent.plist" ]]; then cp -p "$backup/agent.plist" "$agent_plist" || rollback_failed=1; fi
                if (( snapshot )); then
                    [[ ! -d "$data" ]] || mv "$data" "$backup/failed-data" || rollback_failed=1
                    if (( had_data )); then
                        # Do not merge a backup into data that could not be evacuated.
                        if [[ ! -e "$data" && ! -L "$data" ]]; then
                            /usr/bin/ditto "$backup/data" "$data" || rollback_failed=1
                        else
                            rollback_failed=1
                        fi
                    fi
                    if (( had_preferences )); then
                        /usr/bin/defaults import "$domain" "$backup/preferences.plist" || rollback_failed=1
                    else
                        /usr/bin/defaults delete "$domain" >/dev/null 2>&1 || true
                    fi
                fi
            else
                rollback_failed=1
            fi
        fi
        if (( stopped && rollback_failed == 0 )); then restart_previous_state || rollback_failed=1; fi
        setup_error "install failed; backups retained at $backup"
        (( rollback_failed == 0 )) || setup_error 'automatic rollback needs attention; inspect backup before restarting capd'
    fi
    exit "$result"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

stopped=1
stop_capd
if (( had_data )); then /usr/bin/ditto "$data" "$backup/data"; fi
if /usr/bin/defaults read "$domain" >/dev/null 2>&1 || [[ -f "$HOME/Library/Preferences/$domain.plist" ]]; then
    /usr/bin/defaults export "$domain" "$backup/preferences.plist"
    had_preferences=1
fi
snapshot=1
printf 'app_running=%s\nagent_loaded=%s\nstage=%s\n' "$app_running" "$agent_loaded" "$stage" > "$backup/INSTALL-INFO"
if (( had_app )); then mv "$app" "$backup/previous-app"; fi
swapped=1
/usr/bin/ditto "$stage/capd.app" "$app"
capd_validate_app "$app"
ln -sfn "$app/Contents/MacOS/capd" "$cli"
"$cli" --version
restart_previous_state
if (( app_running )); then
    # shellcheck disable=SC2034
    for attempt in {1..50}; do pgrep -x CapdApp >/dev/null && break; sleep 0.1; done
    app_pid="$(pgrep -x CapdApp | head -n 1)"
    # A launch request can succeed before the process crashes during startup.
    # Require the launched process to survive the next three seconds.
    # shellcheck disable=SC2034
    for attempt in {1..30}; do
        sleep 0.1
        kill -0 "$app_pid" 2>/dev/null || { setup_error 'capd app exited during startup'; exit 1; }
    done
fi
if (( agent_loaded )); then
    /bin/launchctl print "$agent" >/dev/null
    # shellcheck disable=SC2034
    for attempt in {1..50}; do pgrep -x capd-agent >/dev/null && break; sleep 0.1; done
    pgrep -x capd-agent >/dev/null
fi
printf 'Installed capd from %s\nBackup retained at %s\n' "$stage" "$backup"
