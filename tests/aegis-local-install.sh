#!/usr/bin/env bash

set -euo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly EXPECTED_REVISION="$(awk -F '"' '/^aegis_local_revision = / { print $2; exit }' "$ROOT/config.toml")"

[[ "$EXPECTED_REVISION" =~ ^[[:xdigit:]]{40}$ ]] || {
    echo "not ok - rendered Aegis revision pin is missing or invalid" >&2
    exit 1
}

fail() {
    echo "not ok - $*" >&2
    exit 1
}

pass() {
    echo "ok - $*"
}

render_helper() {
    local output="${1:?output required}"
    local vars_json
    vars_json="$(python3 "$ROOT/tests/lib/tera.py" --read-vars "$ROOT/config.toml" \
        --var-key aegis_bundle_id --var-key aegis_local_revision --var-key aegis_sha256 \
        --var-key aegis_signing_identity --var-key aegis_url --var-key aegis_version)"
    python3 "$ROOT/tests/lib/tera.py" \
        --source "$ROOT/templates/.local/bin/aegis-local-install.tera" \
        --target "$output" --scratch "$(dirname "$output")" \
        --vars-json "$vars_json" >/dev/null
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
    *"rev-parse --show-toplevel"*)
        [[ "${AEGIS_TEST_COLOCATED:-1}" == 1 ]] || exit 128
        printf '%s\n' "$AEGIS_SOURCE_DIR"
        ;;
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
set -euo pipefail
case "$*" in
    *" status") exit 0 ;;
    *"diff --summary -r @"*)
        if [[ "${AEGIS_TEST_JJ_DIRTY:-0}" == 1 ]]; then
            printf 'M Aegis/App.swift\n'
        fi
        ;;
    *"log --no-graph -r @ -T parents.len()"*)
        printf '%s' "${AEGIS_TEST_PARENT_COUNT:-1}"
        ;;
    *"log --no-graph -r @- -T commit_id"*)
        printf '%s' "${AEGIS_TEST_PARENT_REVISION:-${AEGIS_TEST_REVISION:?}}"
        ;;
    *) exit 1 ;;
esac
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
if [[ "${AEGIS_TEST_DEFAULTS_FAIL:-0}" == 1 ]]; then
    exit 1
fi
EOF
    cat >"$bin/osascript" <<'EOF'
#!/usr/bin/env bash
printf 'osascript %s\n' "$*" >>"${AEGIS_TEST_CALLS:?}"
EOF
    cat >"$bin/open" <<'EOF'
#!/usr/bin/env bash
printf 'open %s\n' "$*" >>"${AEGIS_TEST_CALLS:?}"
if [[ "${AEGIS_TEST_OPEN_FAIL:-0}" == 1 ]]; then
    exit 1
fi
EOF
    cat >"$bin/mv" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'mv %s\n' "$*" >>"${AEGIS_TEST_CALLS:?}"
if [[ "${AEGIS_TEST_REPLACE_FAIL:-0}" == 1 && "$1" == *Products/* ]]; then
    exit 1
fi
if [[ "${AEGIS_TEST_RECEIPT_FAIL:-0}" == 1 && "$2" == *receipt ]]; then
    exit 1
fi
/bin/mv "$@"
EOF
    chmod +x "$bin"/*
}

run_helper() {
    local tmp="${1:?temporary directory required}"
    local revision="${AEGIS_RUN_REVISION:-$EXPECTED_REVISION}"
    local dirty="${AEGIS_RUN_DIRTY:-0}"
    local jj_dirty="${AEGIS_RUN_JJ_DIRTY:-0}"
    local colocated="${AEGIS_RUN_COLOCATED:-1}"
    local parent_revision="${AEGIS_RUN_PARENT_REVISION:-$EXPECTED_REVISION}"
    local parent_count="${AEGIS_RUN_PARENT_COUNT:-1}"
    shift
    env \
        HOME="$tmp/home" \
        PATH="$tmp/bin:/usr/bin:/bin" \
        AEGIS_SOURCE_DIR="$tmp/source" \
        AEGIS_APPLICATIONS_DIR="$tmp/Applications" \
        AEGIS_STATE_DIR="$tmp/state" \
        AEGIS_TEST_REVISION="$revision" \
        AEGIS_TEST_DIRTY="$dirty" \
        AEGIS_TEST_JJ_DIRTY="$jj_dirty" \
        AEGIS_TEST_COLOCATED="$colocated" \
        AEGIS_TEST_PARENT_REVISION="$parent_revision" \
        AEGIS_TEST_PARENT_COUNT="$parent_count" \
        AEGIS_TEST_DEFAULTS_FAIL="${AEGIS_TEST_DEFAULTS_FAIL:-0}" \
        AEGIS_TEST_RECEIPT_FAIL="${AEGIS_TEST_RECEIPT_FAIL:-0}" \
        AEGIS_TEST_OPEN_FAIL="${AEGIS_TEST_OPEN_FAIL:-0}" \
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

test_dirty_jj_working_copy() (
    local tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"
    make_fixture "$tmp"
    : >"$tmp/calls"
    if AEGIS_RUN_COLOCATED=0 AEGIS_RUN_JJ_DIRTY=1 run_helper "$tmp" "$tmp/helper"; then
        fail "dirty JJ working copy was accepted"
    fi
    [[ ! -s "$tmp/calls" ]] || fail "build started before JJ working copy check"
    pass "dirty JJ working copy rejected"
)

test_wrong_jj_parent() (
    local tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"
    make_fixture "$tmp"
    : >"$tmp/calls"
    if AEGIS_RUN_COLOCATED=0 AEGIS_RUN_PARENT_REVISION=deadbeef run_helper "$tmp" "$tmp/helper"; then
        fail "wrong JJ parent revision was accepted"
    fi
    [[ ! -s "$tmp/calls" ]] || fail "build started before JJ parent revision check"
    pass "wrong JJ parent revision rejected"
)

test_merge_working_copy() (
    local tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"
    make_fixture "$tmp"
    : >"$tmp/calls"
    if AEGIS_RUN_COLOCATED=0 AEGIS_RUN_PARENT_COUNT=2 run_helper "$tmp" "$tmp/helper"; then
        fail "merge JJ working copy was accepted"
    fi
    [[ ! -s "$tmp/calls" ]] || fail "build started before JJ parent count check"
    pass "merge JJ working copy rejected"
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

test_defaults_failure_rolls_back() (
    local tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"
    make_fixture "$tmp"
    printf 'old app\n' >"$tmp/Applications/Aegis.app/old-marker"
    : >"$tmp/calls"
    if AEGIS_TEST_DEFAULTS_FAIL=1 run_helper "$tmp" "$tmp/helper"; then
        fail "defaults failure was accepted"
    fi
    grep -Fqx 'old app' "$tmp/Applications/Aegis.app/old-marker" || fail "old app was not restored after defaults failure"
    pass "defaults failure rolls back"
)

test_receipt_failure_rolls_back() (
    local tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"
    make_fixture "$tmp"
    printf 'old app\n' >"$tmp/Applications/Aegis.app/old-marker"
    : >"$tmp/calls"
    if AEGIS_TEST_RECEIPT_FAIL=1 run_helper "$tmp" "$tmp/helper"; then
        fail "receipt failure was accepted"
    fi
    grep -Fqx 'old app' "$tmp/Applications/Aegis.app/old-marker" || fail "old app was not restored after receipt failure"
    pass "receipt failure rolls back"
)

test_relaunch_failure_rolls_back() (
    local tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"
    make_fixture "$tmp"
    printf 'old app\n' >"$tmp/Applications/Aegis.app/old-marker"
    : >"$tmp/calls"
    if AEGIS_TEST_OPEN_FAIL=1 run_helper "$tmp" "$tmp/helper"; then
        fail "relaunch failure was accepted"
    fi
    grep -Fqx 'old app' "$tmp/Applications/Aegis.app/old-marker" || fail "old app was not restored after relaunch failure"
    pass "relaunch failure rolls back"
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
    grep -Fqx "revision=$EXPECTED_REVISION" "$tmp/state/receipt" || \
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

test_successful_secondary_jj_workspace() (
    local tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"
    make_fixture "$tmp"
    : >"$tmp/calls"
    AEGIS_RUN_COLOCATED=0 run_helper "$tmp" "$tmp/helper" >/dev/null
    grep -Fqx "revision=$EXPECTED_REVISION" "$tmp/state/receipt" || \
        fail "secondary JJ workspace receipt has the wrong revision"
    [[ -d "$tmp/Applications/Aegis.app" ]] || fail "Aegis app was not installed from secondary JJ workspace"
    pass "secondary JJ workspace installs without a Git checkout"
)

test_wrong_revision
test_dirty_checkout
test_dirty_jj_working_copy
test_wrong_jj_parent
test_merge_working_copy
test_missing_identity
test_duplicate_identity
test_invalid_bundle
test_cdhash_requirement
test_untrusted_requirement
test_failed_replacement_rolls_back
test_defaults_failure_rolls_back
test_receipt_failure_rolls_back
test_relaunch_failure_rolls_back
test_successful_install
test_successful_secondary_jj_workspace

echo "Aegis local installer tests passed"
