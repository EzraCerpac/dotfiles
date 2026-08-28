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
    cat >"$bin/security" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${AEGIS_TEST_IDENTITIES:-1}" == 2 ]]; then
    printf '  1) 0123456789012345678901234567890123456789 "Aegis Local Code Signing"\n'
    printf '  2) ABCDEFABCDEFABCDEFABCDEFABCDEFABCDEFABCD "Aegis Local Code Signing"\n'
elif [[ "${AEGIS_TEST_IDENTITIES:-1}" == 1 ]]; then
    printf '  1) 0123456789012345678901234567890123456789 "Aegis Local Code Signing"\n'
fi
printf '%s valid identities found\n' "${AEGIS_TEST_IDENTITIES:-1}"
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
if [[ "${AEGIS_TEST_SIGNATURE_FAIL:-0}" == 1 ]]; then
    exit 1
fi
if [[ "$*" == *"-R="* ]] && [[ "${AEGIS_TEST_TRUST_FAIL:-0}" == 1 ]]; then
    printf 'errSecInternalComponent: CSSMERR_TP_NOT_TRUSTED\n' >&2
    exit 1
fi
case "$*" in
    *"--display"*) printf 'Authority=Aegis Local Code Signing\n' ;;
    *"-d -r-"*)
        printf 'Executable=%s\n' "${*: -1}"
        if [[ "${AEGIS_TEST_CDHASH_REQUIREMENT:-0}" == 1 ]]; then
            printf 'designated => cdhash H"0123456789ABCDEF"\n'
        else
            printf 'designated => anchor trusted\n'
        fi
        ;;
esac
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
    local revision="${AEGIS_RUN_REVISION:-7bb650069363b0c12fa0d4ece19c8b84e93fc8fc}"
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
        AEGIS_SECURITY_BIN="$tmp/bin/security" \
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

test_missing_identity() (
    local tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"
    make_fixture "$tmp"
    : >"$tmp/calls"
    if AEGIS_TEST_IDENTITIES=0 run_helper "$tmp" "$tmp/helper"; then
        fail "missing signing identity was accepted"
    fi
    [[ ! -s "$tmp/calls" ]] || fail "build started without a signing identity"
    pass "missing signing identity rejected"
)

test_duplicate_identity() (
    local tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"
    make_fixture "$tmp"
    : >"$tmp/calls"
    if AEGIS_TEST_IDENTITIES=2 run_helper "$tmp" "$tmp/helper"; then
        fail "duplicate signing identity was accepted"
    fi
    [[ ! -s "$tmp/calls" ]] || fail "build started with duplicate identities"
    pass "duplicate signing identity rejected"
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

test_cdhash_requirement() (
    local tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"
    make_fixture "$tmp"
    : >"$tmp/calls"
    if AEGIS_TEST_CDHASH_REQUIREMENT=1 run_helper "$tmp" "$tmp/helper"; then
        fail "CDHash-only designated requirement was accepted"
    fi
    [[ -f "$tmp/Applications/Aegis.app/Contents/Info.plist" ]] || fail "old app disappeared after CDHash rejection"
    pass "CDHash-only designated requirement rejected"
)

test_untrusted_requirement() (
    local tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"
    make_fixture "$tmp"
    printf 'old app\n' >"$tmp/Applications/Aegis.app/old-marker"
    : >"$tmp/calls"
    if AEGIS_TEST_TRUST_FAIL=1 run_helper "$tmp" "$tmp/helper" >"$tmp/output" 2>&1; then
        fail "untrusted designated requirement was accepted"
    fi
    grep -Fq 'not trusted' "$tmp/output" || fail "untrusted requirement failure was not explained"
    [[ -f "$tmp/Applications/Aegis.app/old-marker" ]] || fail "old app was moved before trust validation"
    ! grep -Fq 'osascript ' "$tmp/calls" || fail "Aegis was quit before trust validation"
    pass "untrusted designated requirement rejected before replacement"
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
    local expected_requirement_hash=""
    trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"
    make_fixture "$tmp"
    : >"$tmp/calls"
    run_helper "$tmp" "$tmp/helper" >/dev/null
    grep -Fq 'xcodebuild ' "$tmp/calls" || fail "Release build was not invoked"
    grep -Fq 'CODE_SIGN_IDENTITY=0123456789012345678901234567890123456789' "$tmp/calls" || \
        fail "build did not use the configured signing identity"
    ! grep -Fq 'CODE_SIGN_IDENTITY=-' "$tmp/calls" || fail "build fell back to ad hoc signing"
    grep -Fq 'defaults write Aegis.Aegis SUEnableAutomaticChecks -bool false' "$tmp/calls" || \
        fail "Sparkle automatic checks were not disabled"
    grep -Fq 'defaults write Aegis.Aegis SUAutomaticallyUpdate -bool false' "$tmp/calls" || \
        fail "Sparkle automatic updates were not disabled"
    grep -Fq 'codesign --force --deep --sign 0123456789012345678901234567890123456789 --timestamp=none' "$tmp/calls" || \
        fail "nested Aegis code was not re-signed with the configured signing identity"
    grep -Fq 'codesign -v -R=anchor trusted' "$tmp/calls" || \
        fail "certificate designated requirement was not evaluated for trust"
    grep -Fq 'osascript ' "$tmp/calls" || fail "Aegis was not quit before replacement"
    grep -Fq 'open ' "$tmp/calls" || fail "Aegis was not relaunched"
    grep -Fqx 'revision=7bb650069363b0c12fa0d4ece19c8b84e93fc8fc' "$tmp/state/receipt" || \
        fail "installed revision receipt is wrong"
    [[ -d "$tmp/Applications/Aegis.app" ]] || fail "Aegis app was not installed"
    grep -Fqx 'signing_identity=Aegis Local Code Signing' "$tmp/state/receipt" || \
        fail "signing identity was not recorded"
    grep -Fqx 'signing_identity_hash=0123456789012345678901234567890123456789' "$tmp/state/receipt" || \
        fail "signing identity hash was not recorded"
    expected_requirement_hash="$(printf 'designated => anchor trusted' | shasum -a 256 | awk '{ print $1 }')"
    grep -Fqx "designated_requirement_sha256=$expected_requirement_hash" "$tmp/state/receipt" || \
        fail "designated requirement digest was not normalized"
    pass "successful install records receipt and relaunches"
)

test_wrong_revision
test_dirty_checkout
test_missing_identity
test_duplicate_identity
test_invalid_bundle
test_cdhash_requirement
test_untrusted_requirement
test_failed_replacement_rolls_back
test_successful_install

echo "Aegis local installer tests passed"
