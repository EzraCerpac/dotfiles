#!/usr/bin/env bash

set -euo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    printf 'not ok - %s\n' "$*" >&2
    exit 1
}

pass() {
    printf 'ok - %s\n' "$*"
}

render() {
    local template="${1:?template required}"
    local output="${2:?output required}"
    chezmoi execute-template --init=false --source "$ROOT" --file "$template" >"$output"
    chmod +x "$output"
}

test_aegis_and_rift_reconciliation() (
    local tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    local script="$tmp/reconcile"

    render run_after_03-reconcile-tools.sh.tmpl "$script"
    mkdir -p "$tmp/bin" "$tmp/home"
    : >"$tmp/calls"

    cat >"$tmp/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >>"${CALL_LOG:?}"
: >"${@: -2:1}"
EOF
    cat >"$tmp/bin/shasum" <<'EOF'
#!/usr/bin/env bash
printf 'shasum %s\n' "$*" >>"${CALL_LOG:?}"
cat >/dev/null
[[ "${SHASUM_FAIL:-0}" != 1 ]]
EOF
    cat >"$tmp/bin/unzip" <<'EOF'
#!/usr/bin/env bash
printf 'unzip %s\n' "$*" >>"${CALL_LOG:?}"
target="${@: -1}"
mkdir -p "$target/Aegis.app/Contents"
: >"$target/Aegis.app/Contents/Info.plist"
EOF
    cat >"$tmp/bin/plistbuddy" <<'EOF'
#!/usr/bin/env bash
case "$2" in
    *CFBundleIdentifier*) printf '%s\n' Aegis.Aegis ;;
    *CFBundleShortVersionString*) printf '%s\n' 1.1.0 ;;
esac
EOF
    cat >"$tmp/bin/codesign" <<'EOF'
#!/usr/bin/env bash
printf 'codesign %s\n' "$*" >>"${CALL_LOG:?}"
EOF
    cat >"$tmp/bin/rift" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$tmp/bin/launchctl" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    print) [[ -f "${RIFT_RUNNING:?}" ]] ;;
    bootstrap) printf 'launchctl %s\n' "$*" >>"${CALL_LOG:?}"; : >"${RIFT_RUNNING:?}" ;;
    bootout) printf 'launchctl %s\n' "$*" >>"${CALL_LOG:?}"; rm -f "${RIFT_RUNNING:?}" ;;
    enable) printf 'launchctl %s\n' "$*" >>"${CALL_LOG:?}" ;;
esac
EOF
    chmod +x "$tmp/bin"/*

    mkdir -p "$tmp/home/Library/LaunchAgents"
    render Library/LaunchAgents/git.acsandmann.rift.plist.tmpl \
        "$tmp/home/Library/LaunchAgents/git.acsandmann.rift.plist"

    HOME="$tmp/home" PATH="$tmp/bin:/usr/bin:/bin" CALL_LOG="$tmp/calls" \
        RIFT_RUNNING="$tmp/rift-running" TOOL_RECONCILE_LIB_ONLY=1 \
        RIFT_BIN=rift RIFT_LAUNCHCTL_BIN=launchctl \
        bash -c 'source "$1"; reconcile_rift_service' _ "$script"

    [[ ! -s "$tmp/calls" ]] || fail "staged Rift service was installed or started"
    [[ -f "$tmp/home/Library/LaunchAgents/git.acsandmann.rift.plist" ]] || fail "managed Rift launch agent is missing"

    if SHASUM_FAIL=1 HOME="$tmp/home" PATH="$tmp/bin:/usr/bin:/bin" CALL_LOG="$tmp/calls" \
        TOOL_RECONCILE_LIB_ONLY=1 AEGIS_APPLICATIONS_DIR="$tmp/Applications" \
        AEGIS_CURL_BIN=curl AEGIS_SHASUM_BIN=shasum AEGIS_UNZIP_BIN=unzip \
        AEGIS_PLIST_BUDDY_BIN=plistbuddy AEGIS_CODESIGN_BIN=codesign \
        bash -c 'source "$1"; reconcile_aegis' _ "$script"; then
        fail "Aegis reconciliation accepted a checksum failure"
    fi
    [[ ! -e "$tmp/Applications/Aegis.app" ]] || fail "checksum failure installed Aegis"
    : >"$tmp/calls"

    HOME="$tmp/home" PATH="$tmp/bin:/usr/bin:/bin" CALL_LOG="$tmp/calls" \
        RIFT_RUNNING="$tmp/rift-running" TOOL_RECONCILE_LIB_ONLY=1 \
        AEGIS_APPLICATIONS_DIR="$tmp/Applications" AEGIS_CURL_BIN=curl \
        AEGIS_SHASUM_BIN=shasum AEGIS_UNZIP_BIN=unzip \
        AEGIS_PLIST_BUDDY_BIN=plistbuddy AEGIS_CODESIGN_BIN=codesign \
        RIFT_BIN=rift RIFT_LAUNCHCTL_BIN=launchctl \
        bash -c 'source "$1"; reconcile_aegis; reconcile_rift_service' _ "$script"

    [[ -d "$tmp/Applications/Aegis.app" ]] || fail "Aegis app was not installed"
    ! grep -Fq 'launchctl ' "$tmp/calls" || fail "ordinary reconcile mutated the Rift service"
    if grep -Fq '<key>KeepAlive</key>' "$tmp/home/Library/LaunchAgents/git.acsandmann.rift.plist"; then
        fail "Rift launch agent still has KeepAlive"
    fi
    grep -Fq 'codesign --verify --deep --strict --verbose=2' "$tmp/calls" || fail "Aegis signature was not checked"
    pass "Aegis pin and Rift service reconciliation"
)

test_legacy_migration() (
    local tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    local script="$tmp/migrate"

    render run_after_04-migrate-window-manager.sh.tmpl "$script"
    mkdir -p "$tmp/bin" "$tmp/home/.config/aerospace" "$tmp/home/.config/sketchybar" \
        "$tmp/home/.config/svim" "$tmp/Applications/Aegis.app/Contents" "$tmp/Applications/boringNotch.app"
    : >"$tmp/calls"
    : >"$tmp/Applications/Aegis.app/Contents/Info.plist"

    cat >"$tmp/bin/rift" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat >"$tmp/bin/brew" <<'EOF'
#!/usr/bin/env bash
printf 'brew %s\n' "$*" >>"${CALL_LOG:?}"
case "$1 $2 ${3:-}" in
    'list --cask aerospace'|'list --cask alt-tab'|'list --cask font-sketchybar-app-font'|'list --formula sketchybar') exit 0 ;;
esac
exit 0
EOF
    cat >"$tmp/bin/osascript" <<'EOF'
#!/usr/bin/env bash
printf 'osascript %s\n' "$*" >>"${CALL_LOG:?}"
EOF
    cat >"$tmp/bin/plistbuddy" <<'EOF'
#!/usr/bin/env bash
case "$2" in
    *CFBundleIdentifier*) printf '%s\n' Aegis.Aegis ;;
    *CFBundleShortVersionString*) printf '%s\n' 1.1.0 ;;
esac
EOF
    cat >"$tmp/bin/codesign" <<'EOF'
#!/usr/bin/env bash
[[ "${CODESIGN_FAIL:-0}" != 1 ]]
EOF
    cat >"$tmp/bin/launchctl" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == print ]]
EOF
    cat >"$tmp/bin/pgrep" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == "-x Aegis" ]]
EOF
    chmod +x "$tmp/bin"/*

    HOME="$tmp/home" PATH="$tmp/bin:/usr/bin:/bin" CALL_LOG="$tmp/calls" \
        WINDOW_MANAGER_APPLICATIONS_DIR="$tmp/Applications" \
        WINDOW_MANAGER_BREW_BIN="$tmp/bin/brew" \
        WINDOW_MANAGER_OSASCRIPT_BIN="$tmp/bin/osascript" \
        WINDOW_MANAGER_PLIST_BUDDY_BIN="$tmp/bin/plistbuddy" \
        WINDOW_MANAGER_CODESIGN_BIN="$tmp/bin/codesign" \
        WINDOW_MANAGER_LAUNCHCTL_BIN="$tmp/bin/launchctl" \
        WINDOW_MANAGER_PGREP_BIN="$tmp/bin/pgrep" \
        bash "$script" >/dev/null 2>&1
    [[ ! -s "$tmp/calls" ]] || fail "migration ran without explicit approval"
    [[ -d "$tmp/Applications/boringNotch.app" ]] || fail "unapproved migration moved BoringNotch"
    [[ -d "$tmp/home/.config/aerospace" ]] || fail "unapproved migration removed AeroSpace config"

    if CODESIGN_FAIL=1 HOME="$tmp/home" PATH="$tmp/bin:/usr/bin:/bin" CALL_LOG="$tmp/calls" \
        WINDOW_MANAGER_MIGRATION_APPROVED=1 \
        WINDOW_MANAGER_APPLICATIONS_DIR="$tmp/Applications" \
        WINDOW_MANAGER_BREW_BIN="$tmp/bin/brew" \
        WINDOW_MANAGER_OSASCRIPT_BIN="$tmp/bin/osascript" \
        WINDOW_MANAGER_PLIST_BUDDY_BIN="$tmp/bin/plistbuddy" \
        WINDOW_MANAGER_CODESIGN_BIN="$tmp/bin/codesign" \
        WINDOW_MANAGER_LAUNCHCTL_BIN="$tmp/bin/launchctl" \
        WINDOW_MANAGER_PGREP_BIN="$tmp/bin/pgrep" \
        bash "$script" >/dev/null 2>&1; then
        fail "migration accepted an invalid Aegis app"
    fi
    [[ ! -s "$tmp/calls" ]] || fail "migration ran before Aegis verification"
    [[ -d "$tmp/Applications/boringNotch.app" ]] || fail "unverified Aegis migration moved BoringNotch"
    [[ -d "$tmp/home/.config/aerospace" ]] || fail "unverified migration removed AeroSpace config"

    if HOME="$tmp/home" PATH="$tmp/bin:/usr/bin:/bin" CALL_LOG="$tmp/calls" \
        WINDOW_MANAGER_MIGRATION_APPROVED=1 \
        WINDOW_MANAGER_APPLICATIONS_DIR="$tmp/Applications" \
        WINDOW_MANAGER_BREW_BIN="$tmp/bin/missing-brew" \
        WINDOW_MANAGER_OSASCRIPT_BIN="$tmp/bin/osascript" \
        WINDOW_MANAGER_PLIST_BUDDY_BIN="$tmp/bin/plistbuddy" \
        WINDOW_MANAGER_CODESIGN_BIN="$tmp/bin/codesign" \
        WINDOW_MANAGER_LAUNCHCTL_BIN="$tmp/bin/launchctl" \
        WINDOW_MANAGER_PGREP_BIN="$tmp/bin/pgrep" \
        bash "$script" >/dev/null 2>&1; then
        fail "migration completed without Homebrew"
    fi
    [[ ! -e "$tmp/home/.local/state/chezmoi/rift-aegis-window-manager-migration-v1" ]] || fail "missing Homebrew wrote migration marker"
    [[ -d "$tmp/Applications/boringNotch.app" ]] || fail "missing Homebrew moved BoringNotch"
    [[ -d "$tmp/home/.config/aerospace" ]] || fail "missing Homebrew removed AeroSpace config"

    HOME="$tmp/home" PATH="$tmp/bin:/usr/bin:/bin" CALL_LOG="$tmp/calls" \
        WINDOW_MANAGER_MIGRATION_APPROVED=1 \
        WINDOW_MANAGER_APPLICATIONS_DIR="$tmp/Applications" \
        WINDOW_MANAGER_BREW_BIN="$tmp/bin/brew" \
        WINDOW_MANAGER_OSASCRIPT_BIN="$tmp/bin/osascript" \
        WINDOW_MANAGER_PLIST_BUDDY_BIN="$tmp/bin/plistbuddy" \
        WINDOW_MANAGER_CODESIGN_BIN="$tmp/bin/codesign" \
        WINDOW_MANAGER_LAUNCHCTL_BIN="$tmp/bin/launchctl" \
        WINDOW_MANAGER_PGREP_BIN="$tmp/bin/pgrep" \
        bash "$script"

    [[ -f "$tmp/home/.local/state/chezmoi/rift-aegis-window-manager-migration-v1" ]] || fail "migration marker missing"
    [[ -d "$tmp/Applications/boringNotch.app" ]] || fail "BoringNotch was removed during migration"
    [[ ! -e "$tmp/home/.Trash/boringNotch.app" ]] || fail "migration moved BoringNotch to Trash"
    [[ ! -e "$tmp/home/.config/aerospace" ]] || fail "AeroSpace target config remains"
    [[ ! -e "$tmp/home/.config/sketchybar" ]] || fail "SketchyBar target config remains"
    [[ ! -e "$tmp/home/.config/svim" ]] || fail "SVIM target config remains"
    grep -Fq 'brew uninstall --cask aerospace' "$tmp/calls" || fail "AeroSpace was not uninstalled"
    grep -Fq 'brew uninstall --cask alt-tab' "$tmp/calls" || fail "AltTab was not uninstalled"
    grep -Fq 'brew services stop sketchybar' "$tmp/calls" || fail "SketchyBar service was not stopped"
    grep -Fq 'brew uninstall sketchybar' "$tmp/calls" || fail "SketchyBar was not uninstalled"

    : >"$tmp/calls"
    HOME="$tmp/home" PATH="$tmp/bin:/usr/bin:/bin" CALL_LOG="$tmp/calls" \
        WINDOW_MANAGER_MIGRATION_APPROVED=1 \
        WINDOW_MANAGER_APPLICATIONS_DIR="$tmp/Applications" \
        WINDOW_MANAGER_BREW_BIN="$tmp/bin/brew" \
        WINDOW_MANAGER_OSASCRIPT_BIN="$tmp/bin/osascript" \
        WINDOW_MANAGER_PLIST_BUDDY_BIN="$tmp/bin/plistbuddy" \
        WINDOW_MANAGER_CODESIGN_BIN="$tmp/bin/codesign" \
        WINDOW_MANAGER_LAUNCHCTL_BIN="$tmp/bin/launchctl" \
        WINDOW_MANAGER_PGREP_BIN="$tmp/bin/pgrep" \
        bash "$script"
    [[ ! -s "$tmp/calls" ]] || fail "migration repeated after its marker"
    pass "legacy migration is one-time and preserves BoringNotch settings"
)

test_target_removal_gate() (
    local tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT

    chezmoi execute-template --init=false --source "$ROOT" --file .chezmoiremove.tmpl >"$tmp/rendered"
    grep -Fqx '.config/aerospace/bin/wezterm-smart-focus' "$tmp/rendered" || fail "existing target cleanup was lost"
    if grep -Eq '^\.config/(aerospace|sketchybar|svim)$' "$tmp/rendered"; then
        fail "Chezmoi removes legacy configs before migration preflight"
    fi
    pass "legacy config removal stays inside the cutover script"
)

test_aegis_and_rift_reconciliation
test_legacy_migration
test_target_removal_gate

echo "window-manager lifecycle tests passed"
