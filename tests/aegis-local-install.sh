#!/usr/bin/env bash

set -euo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    echo "not ok - $*" >&2
    exit 1
}

pass() {
    echo "ok - $*"
}

render_helper() {
    local output="${1:?output required}"
    chezmoi execute-template --init=false --source "$ROOT" \
        --file dot_local/bin/executable_aegis-local-install.tmpl >"$output"
    chmod +x "$output"
}

make_fixture() {
    local tmp="${1:?temporary directory required}"
    local bin="$tmp/bin"
    local source="$tmp/source"

    mkdir -p "$bin" "$source/.jj" "$source/Aegis.xcodeproj" \
        "$tmp/home" "$tmp/Applications/Aegis.app/Contents"
    : >"$source/Aegis.xcodeproj/project.pbxproj"
    : >"$tmp/Applications/Aegis.app/Contents/Info.plist"

    cat >"$bin/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
    *"status --porcelain"*)
        if [[ "${AEGIS_TEST_DIRTY:-0}" == 1 ]]; then
            printf ' M Aegis/App.swift\n'
        fi
        ;;
    *"rev-parse HEAD"*) printf '%s\n' "${AEGIS_TEST_REVISION:?}"
        ;;
    *) exit 1 ;;
esac
EOF
    cat >"$bin/jj" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    cat >"$bin/xcodebuild" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'xcodebuild %s\n' "$*" >>"${AEGIS_TEST_CALLS:?}"
for arg in "$@"; do
    case "$arg" in
        CONFIGURATION_BUILD_DIR=*) products_dir="${arg#*=}" ;;
    esac
done
mkdir -p "${products_dir:?}/Aegis.app/Contents"
: >"${products_dir}/Aegis.app/Contents/Info.plist"
EOF
    cat >"$bin/plistbuddy" <<'EOF'
#!/usr/bin/env bash
case "$2" in
    *CFBundleIdentifier*) printf '%s\n' "${AEGIS_TEST_BUNDLE_ID:-Aegis.Aegis}" ;;
    *CFBundleShortVersionString*) printf '%s\n' "${AEGIS_TEST_VERSION:-1.1.0}" ;;
    *) exit 1 ;;
esac
EOF
    cat >"$bin/codesign" <<'EOF'
#!/usr/bin/env bash
printf 'codesign %s\n' "$*" >>"${AEGIS_TEST_CALLS:?}"
[[ "${AEGIS_TEST_SIGNATURE_FAIL:-0}" != 1 ]]
EOF
    cat >"$bin/defaults" <<'EOF'
#!/usr/bin/env bash
printf 'defaults %s\n' "$*" >>"${AEGIS_TEST_CALLS:?}"
EOF
    cat >"$bin/osascript" <<'EOF'
#!/usr/bin/env bash
printf 'osascript %s\n' "$*" >>"${AEGIS_TEST_CALLS:?}"
EOF
    cat >"$bin/open" <<'EOF'
#!/usr/bin/env bash
printf 'open %s\n' "$*" >>"${AEGIS_TEST_CALLS:?}"
EOF
    cat >"$bin/mv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'mv %s\n' "$*" >>"${AEGIS_TEST_CALLS:?}"
if [[ "${AEGIS_TEST_REPLACE_FAIL:-0}" == 1 && "$1" == *Products/* ]]; then
    exit 1
fi
/bin/mv "$@"
EOF
    chmod +x "$bin"/*
}

run_helper() {
    local tmp="${1:?temporary directory required}"
    local revision="${AEGIS_RUN_REVISION:-f5aedb2fa8f5c47199a67c35903023306cb4c504}"
    local dirty="${AEGIS_RUN_DIRTY:-0}"
    shift
    env \
        HOME="$tmp/home" \
        PATH="$tmp/bin:/usr/bin:/bin" \
        AEGIS_SOURCE_DIR="$tmp/source" \
        AEGIS_APPLICATIONS_DIR="$tmp/Applications" \
        AEGIS_STATE_DIR="$tmp/state" \
        AEGIS_TEST_REVISION="$revision" \
        AEGIS_TEST_DIRTY="$dirty" \
        AEGIS_TEST_CALLS="$tmp/calls" \
        AEGIS_GIT_BIN="$tmp/bin/git" \
        AEGIS_JJ_BIN="$tmp/bin/jj" \
        AEGIS_XCODEBUILD_BIN="$tmp/bin/xcodebuild" \
        AEGIS_PLIST_BUDDY_BIN="$tmp/bin/plistbuddy" \
        AEGIS_CODESIGN_BIN="$tmp/bin/codesign" \
        AEGIS_DEFAULTS_BIN="$tmp/bin/defaults" \
        AEGIS_OSASCRIPT_BIN="$tmp/bin/osascript" \
        AEGIS_OPEN_BIN="$tmp/bin/open" \
        AEGIS_MV_BIN="$tmp/bin/mv" \
        "$@"
}

test_wrong_revision() (
    local tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"
    make_fixture "$tmp"
    : >"$tmp/calls"
    if AEGIS_RUN_REVISION=deadbeef run_helper "$tmp" "$tmp/helper"; then
        fail "wrong source revision was accepted"
    fi
    [[ ! -s "$tmp/calls" ]] || fail "build started before revision check"
    pass "wrong source revision rejected"
)

test_dirty_checkout() (
    local tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"
    make_fixture "$tmp"
    : >"$tmp/calls"
    if AEGIS_RUN_DIRTY=1 run_helper "$tmp" "$tmp/helper"; then
        fail "dirty source checkout was accepted"
    fi
    [[ ! -s "$tmp/calls" ]] || fail "build started before dirty checkout check"
    pass "dirty source checkout rejected"
)

test_invalid_bundle() (
    local tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"
    make_fixture "$tmp"
    : >"$tmp/calls"
    if AEGIS_TEST_SIGNATURE_FAIL=1 run_helper "$tmp" "$tmp/helper"; then
        fail "invalid built bundle was accepted"
    fi
    [[ -f "$tmp/Applications/Aegis.app/Contents/Info.plist" ]] || fail "old app disappeared after invalid build"
    pass "invalid built bundle rejected"
)

test_failed_replacement_rolls_back() (
    local tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"
    make_fixture "$tmp"
    printf 'old app\n' >"$tmp/Applications/Aegis.app/old-marker"
    : >"$tmp/calls"
    if AEGIS_TEST_REPLACE_FAIL=1 run_helper "$tmp" "$tmp/helper"; then
        fail "failed replacement was accepted"
    fi
    grep -Fqx 'old app' "$tmp/Applications/Aegis.app/old-marker" || fail "old app was not restored"
    pass "failed replacement rolls back"
)

test_successful_install() (
    local tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"
    make_fixture "$tmp"
    : >"$tmp/calls"
    run_helper "$tmp" "$tmp/helper" >/dev/null
    grep -Fq 'xcodebuild ' "$tmp/calls" || fail "Release build was not invoked"
    grep -Fq 'CODE_SIGN_IDENTITY=-' "$tmp/calls" || fail "build was not ad hoc signed"
    grep -Fq 'defaults write Aegis.Aegis SUEnableAutomaticChecks -bool false' "$tmp/calls" || \
        fail "Sparkle automatic checks were not disabled"
    grep -Fq 'defaults write Aegis.Aegis SUAutomaticallyUpdate -bool false' "$tmp/calls" || \
        fail "Sparkle automatic updates were not disabled"
    grep -Fq 'codesign --force --deep --sign - --timestamp=none' "$tmp/calls" || \
        fail "nested Aegis code was not re-signed for the ad-hoc app"
    grep -Fq 'osascript ' "$tmp/calls" || fail "Aegis was not quit before replacement"
    grep -Fq 'open ' "$tmp/calls" || fail "Aegis was not relaunched"
    grep -Fqx 'revision=f5aedb2fa8f5c47199a67c35903023306cb4c504' "$tmp/state/receipt" || \
        fail "installed revision receipt is wrong"
    [[ -d "$tmp/Applications/Aegis.app" ]] || fail "Aegis app was not installed"
    pass "successful install records receipt and relaunches"
)

test_wrong_revision
test_dirty_checkout
test_invalid_bundle
test_failed_replacement_rolls_back
test_successful_install

echo "Aegis local installer tests passed"
