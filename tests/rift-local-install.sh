#!/usr/bin/env bash

set -euo pipefail

readonly ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REVISION="0123456789abcdef0123456789abcdef01234567"

fail() { echo "not ok - $*" >&2; exit 1; }
pass() { echo "ok - $*"; }

render_helper() {
    chezmoi execute-template --init=false --source "$ROOT" --file dot_local/bin/executable_rift-local-install.tmpl >"$1"
    chmod +x "$1"; bash -n "$1"
}

make_fixture() {
    local tmp="$1" bin="$1/bin" release="$1/source/target/aarch64-apple-darwin/release"
    mkdir -p "$bin" "$tmp/source/.jj" "$release" "$tmp/home/.local/bin" "$tmp/home/.config/rift" "$tmp/home/Library/LaunchAgents" "$tmp/brew"
    : >"$tmp/source/Cargo.toml"; : >"$tmp/home/.config/rift/config.toml"; : >"$tmp/home/Library/LaunchAgents/git.acsandmann.rift.plist"
    printf '#!/bin/sh\nexit 0\n' >"$tmp/brew/rift"; cp "$tmp/brew/rift" "$tmp/brew/rift-cli"; chmod +x "$tmp/brew"/*
    cat >"$bin/jj" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"log -r @ --no-graph"*) printf '%s\n' "${RIFT_TEST_JJ_EMPTY:-true}" ;;
  *"log -r @- --no-graph"*) printf '%s\n' "${RIFT_TEST_REVISION:?}" ;;
  *) exit 1 ;;
esac
EOF
cat >"$bin/cargo" <<'EOF'
#!/usr/bin/env bash
printf 'cargo %s\n' "$*" >>"${RIFT_TEST_CALLS:?}"
[[ "${RIFT_TEST_BUILD_FAIL:-0}" == 0 ]] || exit 1
r="${RIFT_SOURCE_DIR}/target/aarch64-apple-darwin/release"; mkdir -p "$r"
printf '#!/bin/sh\nif [ "$1" = config ]; then exit "${RIFT_TEST_CONFIG_FAIL:-0}"; fi\nexit 0\n' >"$r/rift"
printf '#!/bin/sh\nexit 0\n' >"$r/rift-cli"; chmod +x "$r/rift" "$r/rift-cli"
EOF
    cat >"$bin/security" <<'EOF'
#!/usr/bin/env bash
case "${RIFT_TEST_IDENTITIES:-one}" in
 one) printf '  1) 0123456789012345678901234567890123456789 "Rift Local Code Signing"\n' ;;
 duplicate) printf '  1) 0123456789012345678901234567890123456789 "Rift Local Code Signing"\n  2) 1123456789012345678901234567890123456789 "Rift Local Code Signing"\n' ;;
esac
EOF
cat >"$bin/lipo" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == -archs ]]; printf '%s\n' "${RIFT_TEST_ARCH:-arm64}"
EOF
cat >"$bin/codesign" <<'EOF'
#!/usr/bin/env bash
printf 'codesign %s\n' "$*" >>"${RIFT_TEST_CALLS:?}"
[[ "${RIFT_TEST_SIGNATURE_FAIL:-0}" != 1 || "$*" != *--verify* ]] || exit 1
[[ "${RIFT_TEST_TRUST_FAIL:-0}" != 1 || "$*" != *-R=* ]] || exit 1
case "$*" in
  *--display*) case "$*" in *rift-cli*) id=git.acsandmann.rift-cli;; *) id=git.acsandmann.rift;; esac; printf 'Identifier=%s\nAuthority=Rift Local Code Signing\n' "$id" ;;
  *'-d -r-'*) printf 'designated => anchor trusted\n' ;;
esac
EOF
    cat >"$bin/launchctl" <<'EOF'
#!/usr/bin/env bash
printf 'launchctl %s\n' "$*" >>"${RIFT_TEST_CALLS:?}"
case "$1" in
 print) [[ -f "${RIFT_TEST_RUNNING:?}" ]] && printf 'state = running\npid = 123\n' ;;
 bootout) rm -f "${RIFT_TEST_RUNNING:?}"; [[ "${RIFT_TEST_BOOTOUT_FAIL:-0}" != 1 ]] ;;
 bootstrap)
   [[ "${RIFT_TEST_BOOTSTRAP_FAIL:-0}" != 1 ]] || exit 1
   if [[ "${RIFT_TEST_BOOTSTRAP_FAIL_ONCE:-0}" == 1 && ! -e "${RIFT_TEST_BOOTSTRAP_FAIL_MARKER:?}" ]]; then : >"${RIFT_TEST_BOOTSTRAP_FAIL_MARKER}"; exit 1; fi
   [[ "${RIFT_TEST_EXIT_AFTER_BOOTSTRAP:-0}" != 1 ]] && : >"${RIFT_TEST_RUNNING:?}" ;;
 *) exit 1 ;;
esac
EOF
    cat >"$bin/mv" <<'EOF'
#!/usr/bin/env bash
printf 'mv %s\n' "$*" >>"${RIFT_TEST_CALLS:?}"
if [[ "${RIFT_TEST_POINTER_FAIL_ONCE:-0}" == 1 && "$*" == *current.new* && ! -e "${RIFT_TEST_POINTER_FAIL_MARKER:?}" ]]; then
    : >"${RIFT_TEST_POINTER_FAIL_MARKER}"
    exit 1
fi
/bin/mv "$@"
EOF
    cat >"$bin/publish-mv" <<'EOF'
#!/usr/bin/env bash
[[ "${RIFT_TEST_PUBLISH_FAIL:-0}" != 1 ]] || exit 1
/bin/mv "$@"
EOF
    cat >"$bin/mktemp" <<'EOF'
#!/usr/bin/env bash
if [[ "${RIFT_TEST_RECEIPT_MKTEMP_FAIL:-0}" == 1 && "$*" == *.receipt.* ]]; then exit 1; fi
/usr/bin/mktemp "$@"
EOF
    cat >"$bin/sleep" <<'EOF'
#!/usr/bin/env bash
printf 'sleep %s\n' "$*" >>"${RIFT_TEST_CALLS:?}"
if [[ "${RIFT_TEST_SIGNAL_DURING_SETTLE:-0}" == 1 ]]; then kill -TERM "$PPID"; fi
EOF
    cat >"$bin/cp" <<'EOF'
#!/usr/bin/env bash
if [[ "${RIFT_TEST_RECEIPT_COPY_FAIL:-0}" == 1 && "$*" == *"/receipt"* ]]; then exit 1; fi
/bin/cp "$@"
EOF
    chmod +x "$bin"/*
}

run_helper() {
    local tmp="$1"; shift
    local expected_revision="${RIFT_RUN_EXPECTED_REVISION:-$REVISION}"
    local jj_bin="${RIFT_RUN_JJ_BIN:-$tmp/bin/jj}"
    env HOME="$tmp/home" PATH="$tmp/bin:/usr/bin:/bin" RIFT_SOURCE_DIR="$tmp/source" RIFT_BIN_DIR="$tmp/home/.local/bin" \
        RIFT_STATE_DIR="$tmp/state" RIFT_RELEASES_DIR="$tmp/state/releases" RIFT_CURRENT_LINK="$tmp/state/current" RIFT_HOMEBREW_BIN_DIR="$tmp/brew" \
        RIFT_CONFIG_PATH="$tmp/home/.config/rift/config.toml" RIFT_LAUNCH_AGENT_PATH="$tmp/home/Library/LaunchAgents/git.acsandmann.rift.plist" \
        RIFT_INSTALL_TESTING=1 RIFT_TEST_EXPECTED_REVISION="$expected_revision" RIFT_TEST_REVISION="${RIFT_TEST_REVISION:-$REVISION}" \
        RIFT_TEST_CALLS="$tmp/calls" RIFT_TEST_RUNNING="$tmp/running" RIFT_JJ_BIN="$jj_bin" RIFT_CARGO_BIN="$tmp/bin/cargo" \
        RIFT_SECURITY_BIN="$tmp/bin/security" RIFT_CODESIGN_BIN="$tmp/bin/codesign" RIFT_LIPO_BIN="$tmp/bin/lipo" RIFT_LAUNCHCTL_BIN="$tmp/bin/launchctl" \
        RIFT_MV_BIN="$tmp/bin/mv" RIFT_PUBLISH_MV_BIN="$tmp/bin/publish-mv" RIFT_MKTEMP_BIN="$tmp/bin/mktemp" RIFT_SLEEP_BIN="$tmp/bin/sleep" \
        RIFT_CP_BIN="$tmp/bin/cp" RIFT_TEST_POINTER_FAIL_MARKER="$tmp/pointer-failed" RIFT_TEST_BOOTSTRAP_FAIL_MARKER="$tmp/bootstrap-failed" "$@"
}

stage() { local tmp="$1"; run_helper "$tmp" "$tmp/helper"; }
activate() { local tmp="$1"; run_helper "$tmp" "$tmp/helper" --activate; }

test_stage_is_inert() (
    local tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"; make_fixture "$tmp"; : >"$tmp/calls"
    stage "$tmp" >/dev/null
    [[ -x "$tmp/state/releases/$REVISION/rift" ]] || fail "candidate was not staged"
    [[ ! -e "$tmp/state/current" ]] || fail "stage changed current pointer"
    [[ ! -e "$tmp/home/.local/bin/rift" ]] || fail "stage changed stable binary"
    ! grep -Fq launchctl "$tmp/calls" || fail "stage called launchctl"
    ! grep -Fq brew "$tmp/calls" || fail "stage invoked Homebrew"
    pass "stage verifies a release without live mutation"
)

test_jj_guards() (
    local tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"; make_fixture "$tmp"; : >"$tmp/calls"
    if RIFT_TEST_JJ_EMPTY=false run_helper "$tmp" "$tmp/helper"; then fail "JJ-dirty Git-clean checkout accepted"; fi
    ! grep -Fq cargo "$tmp/calls" || fail "build preceded JJ cleanliness check"
    if RIFT_TEST_REVISION=deadbeef run_helper "$tmp" "$tmp/helper"; then fail "wrong JJ parent accepted"; fi
    pass "JJ empty child and pinned parent are required"
)

test_real_jj_empty_child() (
    local tmp="$(mktemp -d)" real_jj parent_revision
    trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"; make_fixture "$tmp"; : >"$tmp/calls"
    real_jj="$(command -v jj)"
    rm -rf "$tmp/source/.jj"
    "$real_jj" git init "$tmp/source" >/dev/null
    "$real_jj" -R "$tmp/source" describe -m base >/dev/null
    "$real_jj" -R "$tmp/source" new >/dev/null
    parent_revision="$("$real_jj" -R "$tmp/source" log -r @- --no-graph -T 'commit_id ++ "\n"')"
    RIFT_RUN_JJ_BIN="$real_jj" RIFT_RUN_EXPECTED_REVISION="$parent_revision" stage "$tmp" >/dev/null
    [[ -x "$tmp/state/releases/$parent_revision/rift" ]] || fail "real-JJ empty child was not accepted"
    pass "real JJ empty child and parent revision are parsed exactly"
)

test_identity_guards() (
    local tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"; make_fixture "$tmp"; : >"$tmp/calls"
    if RIFT_TEST_IDENTITIES=none run_helper "$tmp" "$tmp/helper"; then fail "missing identity accepted"; fi
    if RIFT_TEST_IDENTITIES=duplicate run_helper "$tmp" "$tmp/helper"; then fail "duplicate identity accepted"; fi
    pass "signing identity must be unique"
)

test_stage_failure_guards() (
    local tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"; make_fixture "$tmp"; : >"$tmp/calls"
    if RIFT_TEST_BUILD_FAIL=1 stage "$tmp"; then fail "failed build was accepted"; fi
    [[ ! -e "$tmp/state/current" ]] || fail "build failure changed current pointer"
    ! find "$tmp/state/releases" -maxdepth 1 -name '.staging.*' -print -quit | grep -q . ||
        fail "build failure left a staging directory"
    if RIFT_TEST_ARCH=x86_64 stage "$tmp"; then fail "wrong architecture was accepted"; fi
    if RIFT_TEST_SIGNATURE_FAIL=1 stage "$tmp"; then fail "invalid signature was accepted"; fi
    if RIFT_TEST_TRUST_FAIL=1 stage "$tmp"; then fail "untrusted identity was accepted"; fi
    if RIFT_TEST_PUBLISH_FAIL=1 stage "$tmp"; then fail "publish failure was accepted"; fi
    [[ ! -e "$tmp/state/current" ]] || fail "stage failure changed current pointer"
    pass "build, signature, architecture, trust, and publish failures stay staged"
)

test_first_activation_and_rollback() (
    local tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"; make_fixture "$tmp"; : >"$tmp/calls"
    stage "$tmp" >/dev/null; : >"$tmp/calls"
    activate "$tmp" >/dev/null
    [[ "$(readlink "$tmp/state/current")" == "$tmp/state/releases/$REVISION" ]] || fail "candidate was not made current"
    [[ "$(readlink "$tmp/home/.local/bin/rift")" == "$tmp/state/current/rift" ]] || fail "stable rift link is not indirect"
    grep -Fqx "revision=$REVISION" "$tmp/state/receipt" || fail "receipt not written"
    grep -Fq 'launchctl bootstrap ' "$tmp/calls" || fail "activation did not bootstrap"
    ! grep -Fq 'launchctl bootout ' "$tmp/calls" || fail "first activation booted out absent service"
    pass "first activation swaps pointer and starts once"
)

test_failed_activation_restores_homebrew() (
    local tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"; make_fixture "$tmp"; stage "$tmp" >/dev/null; : >"$tmp/calls"
    if RIFT_TEST_BOOTSTRAP_FAIL=1 activate "$tmp"; then fail "failed bootstrap accepted"; fi
    [[ "$(readlink "$tmp/state/current")" == "$tmp/brew" ]] || fail "failed first activation did not restore Homebrew pointer"
    [[ ! -e "$tmp/state/receipt" ]] || fail "failed first activation left receipt"
    grep -Fq 'launchctl bootout ' "$tmp/calls" || fail "failed activation did not restore stopped state"
    pass "first activation failure restores Homebrew and stopped service"
)

test_local_upgrade_and_receipt_rollback() (
    local tmp="$(mktemp -d)" old="fedcba9876543210fedcba9876543210fedcba98"; trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"; make_fixture "$tmp"; stage "$tmp" >/dev/null; activate "$tmp" >/dev/null
    mv "$tmp/state/releases/$REVISION" "$tmp/state/releases/$old"; rm -f "$tmp/state/current"; ln -s "$tmp/state/releases/$old" "$tmp/state/current"; printf 'revision=%s\n' "$old" >"$tmp/state/receipt"; : >"$tmp/running"; : >"$tmp/calls"
    if RIFT_TEST_BOOTSTRAP_FAIL=1 activate "$tmp"; then fail "upgrade bootstrap failure accepted"; fi
    [[ "$(readlink "$tmp/state/current")" == "$(cd "$tmp/state/releases/$old" && pwd -P)" ]] || fail "failed upgrade did not restore old release"
    grep -Fqx "revision=$old" "$tmp/state/receipt" || fail "failed upgrade did not restore receipt"
    grep -Fq 'launchctl bootout ' "$tmp/calls" || fail "loaded service was not stopped"
    grep -Fq 'launchctl bootstrap ' "$tmp/calls" || fail "old service was not restored"
    [[ "$(grep -n 'launchctl bootout ' "$tmp/calls" | head -n1 | cut -d: -f1)" -lt "$(grep -n 'launchctl bootstrap ' "$tmp/calls" | head -n1 | cut -d: -f1)" ]] ||
        fail "activation did not stop before restarting"
    pass "failed local upgrade restores release, receipt, and service"
)

test_failure_after_stop_restores_previous_state() (
    local tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"; make_fixture "$tmp"; stage "$tmp" >/dev/null
    mkdir -p "$tmp/state"; ln -s "$tmp/brew" "$tmp/state/current"; : >"$tmp/running"; : >"$tmp/calls"
    if RIFT_TEST_POINTER_FAIL_ONCE=1 activate "$tmp"; then fail "pointer-swap failure was accepted"; fi
    [[ "$(readlink "$tmp/state/current")" == "$tmp/brew" ]] || fail "pointer-swap failure did not restore fallback"
    [[ -f "$tmp/running" ]] || fail "pointer-swap failure did not restore prior service"
    pass "failure after stop restores pointer and prior service"
)

test_invalid_current_pointer_falls_back_safely() (
    local tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"; make_fixture "$tmp"; stage "$tmp" >/dev/null
    mkdir -p "$tmp/state/outside"; cp "$tmp/state/releases/$REVISION/rift" "$tmp/state/outside/rift"; cp "$tmp/state/releases/$REVISION/rift-cli" "$tmp/state/outside/rift-cli"
    ln -s "$tmp/state/releases/../outside" "$tmp/state/current"; : >"$tmp/calls"
    if RIFT_TEST_BOOTSTRAP_FAIL=1 activate "$tmp"; then fail "invalid current pointer activation succeeded"; fi
    [[ "$(readlink "$tmp/state/current")" == "$tmp/brew" ]] || fail "escaped current target was trusted"
    rm -f "$tmp/state/current"; mkdir "$tmp/state/current"
    if activate "$tmp"; then fail "non-link current path was accepted"; fi
    [[ -d "$tmp/state/current" && ! -L "$tmp/state/current" ]] || fail "non-link current path was replaced"
    pass "invalid current pointers fall back or fail without replacement"
)

test_partial_bootout_failure_restores_service() (
    local tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"; make_fixture "$tmp"; stage "$tmp" >/dev/null
    mkdir -p "$tmp/state"; ln -s "$tmp/brew" "$tmp/state/current"; : >"$tmp/running"; : >"$tmp/calls"
    if RIFT_TEST_BOOTOUT_FAIL=1 activate "$tmp"; then fail "partial bootout failure was accepted"; fi
    [[ "$(readlink "$tmp/state/current")" == "$tmp/brew" ]] || fail "partial bootout changed current pointer"
    [[ -f "$tmp/running" ]] || fail "partially stopped service was not restored"
    [[ "$(readlink "$tmp/home/.local/bin/rift")" == "$tmp/state/current/rift" ]] || fail "restored service lacks stable link"
    pass "partial bootout failure restores the prior service once"
)

test_loaded_homebrew_without_stable_links_rolls_back() (
    local tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"; make_fixture "$tmp"; stage "$tmp" >/dev/null
    mkdir -p "$tmp/state"; ln -s "$tmp/brew" "$tmp/state/current"; : >"$tmp/running"; : >"$tmp/calls"
    if RIFT_TEST_BOOTSTRAP_FAIL_ONCE=1 activate "$tmp"; then fail "failed replacement accepted"; fi
    [[ "$(readlink "$tmp/state/current")" == "$tmp/brew" ]] || fail "previous Homebrew pointer was not restored"
    [[ "$(readlink "$tmp/home/.local/bin/rift")" == "$tmp/state/current/rift" ]] || fail "restored Homebrew lacks stable rift link"
    [[ -f "$tmp/running" ]] || fail "previous Homebrew service was not running again"
    pass "loaded Homebrew service restores through stable links"
)

test_candidate_exit_and_receipt_failure_roll_back() (
    local tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"; make_fixture "$tmp"; stage "$tmp" >/dev/null; : >"$tmp/calls"
    if RIFT_TEST_EXIT_AFTER_BOOTSTRAP=1 activate "$tmp"; then fail "exited candidate was accepted"; fi
    [[ "$(readlink "$tmp/state/current")" == "$tmp/brew" ]] || fail "exited candidate did not restore fallback"
    ! grep -Fq 'revision=' "$tmp/state/receipt" 2>/dev/null || fail "exited candidate wrote receipt"
    : >"$tmp/calls"
    if RIFT_TEST_RECEIPT_MKTEMP_FAIL=1 activate "$tmp"; then fail "receipt failure was accepted"; fi
    [[ "$(readlink "$tmp/state/current")" == "$tmp/brew" ]] || fail "receipt failure did not restore fallback"
    [[ ! -e "$tmp/state/receipt" ]] || fail "receipt failure left a receipt"
    grep -Fq 'launchctl bootout ' "$tmp/calls" || fail "receipt failure did not stop failed candidate"
    pass "candidate exit and receipt failure roll back fully"
)

test_receipt_snapshot_failure_is_inert() (
    local tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"; make_fixture "$tmp"; stage "$tmp" >/dev/null
    mkdir -p "$tmp/state"; printf 'revision=old\n' >"$tmp/state/receipt"; : >"$tmp/calls"
    if RIFT_TEST_RECEIPT_COPY_FAIL=1 activate "$tmp"; then fail "receipt snapshot failure was accepted"; fi
    [[ ! -e "$tmp/state/current" ]] || fail "receipt snapshot failure changed current pointer"
    ! grep -Eq 'launchctl (bootout|bootstrap)' "$tmp/calls" || fail "receipt snapshot failure changed service"
    grep -Fqx 'revision=old' "$tmp/state/receipt" || fail "receipt snapshot failure changed receipt"
    pass "receipt snapshot failure aborts before activation"
)

test_signal_rolls_back_candidate() (
    local tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"; make_fixture "$tmp"; stage "$tmp" >/dev/null; : >"$tmp/calls"
    if RIFT_TEST_SIGNAL_DURING_SETTLE=1 activate "$tmp"; then fail "interrupted activation was accepted"; fi
    [[ "$(readlink "$tmp/state/current")" == "$tmp/brew" ]] || fail "signal did not restore fallback pointer"
    [[ ! -f "$tmp/running" ]] || fail "signal left candidate service running"
    [[ ! -e "$tmp/state/receipt" ]] || fail "signal wrote a receipt"
    pass "INT or TERM during activation restores state"
)

test_config_failure_before_stop() (
    local tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"; make_fixture "$tmp"; stage "$tmp" >/dev/null; : >"$tmp/running"; : >"$tmp/calls"
    if RIFT_TEST_CONFIG_FAIL=1 activate "$tmp"; then fail "invalid candidate config accepted"; fi
    ! grep -Fq launchctl "$tmp/calls" || fail "config failure stopped the service"
    pass "offline config check runs before service stop"
)

test_template_contract() {
    local helper="$(mktemp)"; trap 'rm -f "$helper"' RETURN; render_helper "$helper"
    grep -Fq 'RIFT_INSTALL_TESTING' "$helper" || fail "test-only pin seam missing"
    grep -Fq 'current' "$helper" || fail "current pointer missing"
    local rendered_pin package_pin
    rendered_pin="$(sed -n 's/^readonly RIFT_CONFIGURED_REVISION="\([^"]*\)"/\1/p' "$helper")"
    package_pin="$(awk '$1 == "rift:" { in_rift = 1; next } in_rift && $1 == "local_revision:" { print $2; exit }' "$ROOT/.chezmoidata/packages.yaml")"
    [[ "$package_pin" =~ ^[[:xdigit:]]{40}$ ]] || fail "package Rift pin is not a 40-hex revision"
    [[ "$rendered_pin" =~ ^[[:xdigit:]]{40}$ ]] || fail "rendered production pin is not a 40-hex revision"
    [[ "$rendered_pin" == "$package_pin" ]] || fail "rendered production pin differs from package pin"
    ! grep -Eq 'brew[[:space:]]+(install|upgrade|services)' "$helper" || fail "installer mutates Homebrew"
    pass "installer keeps immutable production pin and no Homebrew mutation"
}

test_stage_is_inert
test_jj_guards
test_real_jj_empty_child
test_identity_guards
test_stage_failure_guards
test_first_activation_and_rollback
test_failed_activation_restores_homebrew
test_local_upgrade_and_receipt_rollback
test_failure_after_stop_restores_previous_state
test_invalid_current_pointer_falls_back_safely
test_partial_bootout_failure_restores_service
test_loaded_homebrew_without_stable_links_rolls_back
test_candidate_exit_and_receipt_failure_roll_back
test_receipt_snapshot_failure_is_inert
test_signal_rolls_back_candidate
test_config_failure_before_stop
test_template_contract
echo "Rift local installer tests passed"
