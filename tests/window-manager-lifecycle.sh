#!/usr/bin/env bash

set -euo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly EXPECTED_AEGIS_SHA256="$(chezmoi execute-template --init=false --source "$ROOT" \
    '{{ .packages.darwin.managed_apps.aegis.sha256 }}')"

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

test_aegis_checksum_install() (
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
read -r checksum archive
[[ "${SHASUM_FAIL:-0}" != 1 && "$checksum" == "${AEGIS_TEST_EXPECTED_SHA256:?}" && "$archive" == *Aegis.app.zip ]]
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
    chmod +x "$tmp/bin"/*

    if SHASUM_FAIL=1 HOME="$tmp/home" PATH="$tmp/bin:/usr/bin:/bin" CALL_LOG="$tmp/calls" \
        TOOL_RECONCILE_LIB_ONLY=1 AEGIS_APPLICATIONS_DIR="$tmp/Applications" \
        AEGIS_TEST_EXPECTED_SHA256="$EXPECTED_AEGIS_SHA256" \
        AEGIS_CURL_BIN=curl AEGIS_SHASUM_BIN=shasum AEGIS_UNZIP_BIN=unzip \
        AEGIS_PLIST_BUDDY_BIN=plistbuddy AEGIS_CODESIGN_BIN=codesign \
        bash -c 'source "$1"; reconcile_aegis' _ "$script"; then
        fail "Aegis reconciliation accepted a checksum failure"
    fi
    [[ ! -e "$tmp/Applications/Aegis.app" ]] || fail "checksum failure installed Aegis"
    : >"$tmp/calls"

    HOME="$tmp/home" PATH="$tmp/bin:/usr/bin:/bin" CALL_LOG="$tmp/calls" \
        TOOL_RECONCILE_LIB_ONLY=1 AEGIS_TEST_EXPECTED_SHA256="$EXPECTED_AEGIS_SHA256" \
        AEGIS_APPLICATIONS_DIR="$tmp/Applications" AEGIS_CURL_BIN=curl \
        AEGIS_SHASUM_BIN=shasum AEGIS_UNZIP_BIN=unzip \
        AEGIS_PLIST_BUDDY_BIN=plistbuddy AEGIS_CODESIGN_BIN=codesign \
        bash -c 'source "$1"; reconcile_aegis' _ "$script"

    [[ -d "$tmp/Applications/Aegis.app" ]] || fail "Aegis app was not installed"
    grep -Fq 'codesign --verify --deep --strict --verbose=2' "$tmp/calls" || fail "Aegis signature was not checked"
    pass "Aegis pinned checksum and signature are verified before install"
)

test_target_removal_gate() (
    local tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT

    chezmoi execute-template --init=false --source "$ROOT" --file .chezmoiremove.tmpl >"$tmp/rendered"
    grep -Fqx '.config/aerospace/bin/wezterm-smart-focus' "$tmp/rendered" || fail "existing target cleanup was lost"
    if grep -Eq '^\.config/(aerospace|sketchybar|svim)$' "$tmp/rendered"; then
        fail "Chezmoi target cleanup removes managed window-manager configs"
    fi
    pass "target cleanup protects managed window-manager configs"
)

test_aegis_checksum_install
test_target_removal_gate

echo "window-manager lifecycle tests passed"
