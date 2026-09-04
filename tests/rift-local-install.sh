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
printf '#!/bin/sh\nif [ "$1" = config ]; then printf "config-check %%s\\n" "$4" >>"${RIFT_TEST_CALLS:?}"; exit "${RIFT_TEST_CONFIG_FAIL:-0}"; fi\nexit 0\n' >"$r/rift"
printf '#!/bin/sh\nif [ "$1" = query ]; then exit "${RIFT_TEST_CLI_READY_FAIL:-0}"; fi\nexit 0\n' >"$r/rift-cli"; chmod +x "$r/rift" "$r/rift-cli"
for name in rift rift-cli; do printf '# revision=%s\n' "${RIFT_TEST_REVISION:?}" >>"$r/$name"; done
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
 print)
   if [[ -f "${RIFT_TEST_RUNNING:?}" ]]; then printf 'state = running\npid = 123\n'
   elif [[ -f "${RIFT_TEST_LOADED:?}" ]]; then printf 'state = loaded\n'
   else exit 1; fi ;;
 bootout) rm -f "${RIFT_TEST_RUNNING:?}" "${RIFT_TEST_LOADED:?}"; [[ "${RIFT_TEST_BOOTOUT_FAIL:-0}" != 1 ]] ;;
 bootstrap)
   if [[ "${RIFT_TEST_MUTATE_LIVE:-0}" == 1 && ! -e "${RIFT_TEST_MUTATE_LIVE_MARKER:?}" ]]; then
     : >"${RIFT_TEST_MUTATE_LIVE_MARKER}"
     printf 'candidate config\n' >"${RIFT_CONFIG_PATH:?}"
     if [[ "${RIFT_TEST_DIRECTORY_COLLISION:-0}" == 1 ]]; then rm -f "$RIFT_CONFIG_PATH"; mkdir "$RIFT_CONFIG_PATH"; fi
     mkdir -p "$(dirname "${RIFT_LAYOUT_PATH:?}")"
     printf 'candidate layout\n' >"$RIFT_LAYOUT_PATH"
     printf 'candidate launch agent\n' >"${RIFT_LAUNCH_AGENT_PATH:?}"
   fi
   : >"${RIFT_TEST_LOADED:?}"
   [[ "${RIFT_TEST_BOOTSTRAP_FAIL:-0}" != 1 ]] || exit 1
   if [[ "${RIFT_TEST_BOOTSTRAP_FAIL_ONCE:-0}" == 1 && ! -e "${RIFT_TEST_BOOTSTRAP_FAIL_MARKER:?}" ]]; then : >"${RIFT_TEST_BOOTSTRAP_FAIL_MARKER}"; exit 1; fi
   [[ "${RIFT_TEST_EXIT_AFTER_BOOTSTRAP:-0}" != 1 ]] && : >"${RIFT_TEST_RUNNING:?}" ;;
 kill) rm -f "${RIFT_TEST_RUNNING:?}" ;;
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
if [[ "${!#}" == "$RIFT_STATE_DIR/active/"* ]]; then
    [[ ! -f "${RIFT_TEST_RUNNING:?}" ]] || { echo 'replaced a running binary' >&2; exit 1; }
    if [[ "${RIFT_TEST_ACTIVE_RENAME_FAIL_ONCE:-0}" == 1 && "${!#}" == "$RIFT_STATE_DIR/active/rift-cli" && ! -e "$RIFT_STATE_DIR/rename-failed" ]]; then
        : >"$RIFT_STATE_DIR/rename-failed"
        exit 1
    fi
fi
/bin/mv "$@" || exit 1
if [[ "${RIFT_TEST_ACTIVE_SIGNAL_ONCE:-0}" == 1 && "${!#}" == "$RIFT_STATE_DIR/active/rift" && ! -e "$RIFT_STATE_DIR/signal-sent" ]]; then
    : >"$RIFT_STATE_DIR/signal-sent"
    kill -TERM "$PPID"
fi
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
        RIFT_CONFIG_PATH="$tmp/home/.config/rift/config.toml" RIFT_LAYOUT_PATH="$tmp/home/.rift/layout.ron" \
        RIFT_LAUNCH_AGENT_PATH="$tmp/home/Library/LaunchAgents/git.acsandmann.rift.plist" \
        RIFT_TRACKED_CONFIG_PATH="${RIFT_RUN_TRACKED_CONFIG_PATH:-$tmp/home/.config/rift/config.toml}" \
        RIFT_TRACKED_LAUNCH_AGENT_PATH="${RIFT_RUN_TRACKED_LAUNCH_AGENT_PATH:-$tmp/home/Library/LaunchAgents/git.acsandmann.rift.plist}" \
        RIFT_INSTALL_TESTING=1 RIFT_TEST_EXPECTED_REVISION="$expected_revision" RIFT_TEST_REVISION="${RIFT_TEST_REVISION:-$REVISION}" \
        RIFT_TEST_CALLS="$tmp/calls" RIFT_TEST_RUNNING="$tmp/running" RIFT_TEST_LOADED="$tmp/loaded" RIFT_JJ_BIN="$jj_bin" RIFT_CARGO_BIN="$tmp/bin/cargo" \
        RIFT_SECURITY_BIN="$tmp/bin/security" RIFT_CODESIGN_BIN="$tmp/bin/codesign" RIFT_LIPO_BIN="$tmp/bin/lipo" RIFT_LAUNCHCTL_BIN="$tmp/bin/launchctl" \
        RIFT_MV_BIN="$tmp/bin/mv" RIFT_PUBLISH_MV_BIN="$tmp/bin/publish-mv" RIFT_MKTEMP_BIN="$tmp/bin/mktemp" RIFT_SLEEP_BIN="$tmp/bin/sleep" \
        RIFT_CP_BIN="$tmp/bin/cp" RIFT_TEST_POINTER_FAIL_MARKER="$tmp/pointer-failed" RIFT_TEST_BOOTSTRAP_FAIL_MARKER="$tmp/bootstrap-failed" \
        RIFT_TEST_MUTATE_LIVE_MARKER="$tmp/mutate-live" "$@"
}

stage() { local tmp="$1"; run_helper "$tmp" "$tmp/helper"; }
activate() { local tmp="$1"; run_helper "$tmp" "$tmp/helper" --activate; }

test_stage_is_inert() (
    local tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"; make_fixture "$tmp"; : >"$tmp/calls"
    stage "$tmp" >/dev/null
    [[ -x "$tmp/state/releases/$REVISION/rift" ]] || fail "candidate was not staged"
    [[ ! -e "$tmp/state/current" && ! -e "$tmp/state/active" ]] || fail "stage changed active installation"
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
    [[ "$(readlink "$tmp/home/.local/bin/rift")" == "$tmp/state/active/rift" ]] || fail "rift does not use the permanent path"
    [[ -d "$tmp/state/active" && ! -L "$tmp/state/active" ]] || fail "active is not a real directory"
    cmp -s "$tmp/state/active/rift" "$tmp/state/releases/$REVISION/rift" || fail "active bytes differ from release"
    grep -Fqx "revision=$REVISION" "$tmp/state/receipt" || fail "receipt not written"
    grep -Fq 'launchctl bootstrap ' "$tmp/calls" || fail "activation did not bootstrap"
    ! grep -Fq 'launchctl bootout ' "$tmp/calls" || fail "first activation booted out absent service"
    pass "first activation swaps pointer and starts once"
)

test_failed_activation_restores_homebrew() (
    local tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"; make_fixture "$tmp"; stage "$tmp" >/dev/null; : >"$tmp/calls"
    if RIFT_TEST_BOOTSTRAP_FAIL=1 activate "$tmp"; then fail "failed bootstrap accepted"; fi
    [[ ! -e "$tmp/state/current" && ! -e "$tmp/state/active" ]] || fail "failed first activation did not restore absence"
    [[ ! -e "$tmp/state/receipt" ]] || fail "failed first activation left receipt"
    grep -Fq 'launchctl bootout ' "$tmp/calls" || fail "failed activation did not restore stopped state"
    pass "first activation failure restores Homebrew and stopped service"
)

test_local_upgrade_and_receipt_rollback() (
    local tmp="$(mktemp -d)" old="fedcba9876543210fedcba9876543210fedcba98"; trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"; make_fixture "$tmp"; stage "$tmp" >/dev/null; activate "$tmp" >/dev/null
    mv "$tmp/state/releases/$REVISION" "$tmp/state/releases/$old"; rm -f "$tmp/state/current"; ln -s "$tmp/state/releases/$old" "$tmp/state/current"; printf 'revision=%s\n' "$old" >"$tmp/state/receipt"; : >"$tmp/running"; : >"$tmp/calls"
    if RIFT_TEST_BOOTSTRAP_FAIL_ONCE=1 activate "$tmp"; then fail "upgrade bootstrap failure accepted"; fi
    [[ "$(readlink "$tmp/state/current")" == "$tmp/state/releases/$old" ]] || fail "failed upgrade did not restore old release"
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
    [[ ! -e "$tmp/home/.local/bin/rift" ]] || fail "absent stable link was recreated"
    pass "partial bootout failure restores the prior service once"
)

test_loaded_homebrew_without_stable_links_rolls_back() (
    local tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"; make_fixture "$tmp"; stage "$tmp" >/dev/null
    mkdir -p "$tmp/state"; ln -s "$tmp/brew" "$tmp/state/current"; : >"$tmp/running"; : >"$tmp/calls"
    if RIFT_TEST_BOOTSTRAP_FAIL_ONCE=1 activate "$tmp"; then fail "failed replacement accepted"; fi
    [[ "$(readlink "$tmp/state/current")" == "$tmp/brew" ]] || fail "previous Homebrew pointer was not restored"
    [[ ! -e "$tmp/home/.local/bin/rift" ]] || fail "absent Homebrew stable link was recreated"
    [[ -f "$tmp/running" ]] || fail "previous Homebrew service was not running again"
    pass "loaded Homebrew service restores through stable links"
)

test_candidate_exit_and_receipt_failure_roll_back() (
    local tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"; make_fixture "$tmp"; stage "$tmp" >/dev/null; : >"$tmp/calls"
    if RIFT_TEST_EXIT_AFTER_BOOTSTRAP=1 activate "$tmp"; then fail "exited candidate was accepted"; fi
    [[ ! -e "$tmp/state/current" ]] || fail "exited candidate did not restore absent pointer"
    ! grep -Fq 'revision=' "$tmp/state/receipt" 2>/dev/null || fail "exited candidate wrote receipt"
    : >"$tmp/calls"
    if RIFT_TEST_RECEIPT_MKTEMP_FAIL=1 activate "$tmp"; then fail "receipt failure was accepted"; fi
    [[ ! -e "$tmp/state/current" ]] || fail "receipt failure did not restore absent pointer"
    [[ ! -e "$tmp/state/receipt" ]] || fail "receipt failure left a receipt"
    grep -Fq 'launchctl bootout ' "$tmp/calls" || fail "receipt failure did not stop failed candidate"
    pass "candidate exit and receipt failure roll back fully"
)

test_candidate_mach_readiness_failure_rolls_back() (
    local tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"; make_fixture "$tmp"; stage "$tmp" >/dev/null; : >"$tmp/calls"
    if RIFT_TEST_CLI_READY_FAIL=1 activate "$tmp"; then fail "unqueryable candidate was accepted"; fi
    [[ ! -e "$tmp/state/current" ]] || fail "unqueryable candidate did not restore absent pointer"
    [[ ! -e "$tmp/state/receipt" ]] || fail "unqueryable candidate wrote a receipt"
    grep -Fq 'launchctl bootout ' "$tmp/calls" || fail "unqueryable candidate was not stopped"
    pass "activation requires the candidate Mach endpoint"
)

test_transaction_restores_bytes_and_absence() (
    local tmp="$(mktemp -d)" tracked; tracked="$tmp/tracked"; trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"; make_fixture "$tmp"; stage "$tmp" >/dev/null
    mkdir -p "$tracked" "$tmp/home/.rift" "$tmp/state"
    printf 'old config bytes\n' >"$tmp/home/.config/rift/config.toml"
    printf 'old schema-2 layout bytes\n' >"$tmp/home/.rift/layout.ron"
    printf 'old launch agent bytes\n' >"$tmp/home/Library/LaunchAgents/git.acsandmann.rift.plist"
    printf 'old receipt bytes\n' >"$tmp/state/receipt"
    printf 'tracked config bytes\n' >"$tracked/config.toml"
    printf 'tracked launch agent bytes\n' >"$tracked/rift.plist"
    mkdir -p "$tmp/state"; ln -s "$tmp/brew" "$tmp/state/current"
    ln -s "$tmp/state/current/rift" "$tmp/home/.local/bin/rift"
    ln -s "$tmp/state/current/rift-cli" "$tmp/home/.local/bin/rift-cli"
    cp "$tmp/home/.config/rift/config.toml" "$tmp/old-config"
    cp "$tmp/home/.rift/layout.ron" "$tmp/old-layout"
    cp "$tmp/home/Library/LaunchAgents/git.acsandmann.rift.plist" "$tmp/old-plist"
    cp "$tmp/state/receipt" "$tmp/old-receipt"
    : >"$tmp/running"; : >"$tmp/calls"
    if RIFT_RUN_TRACKED_CONFIG_PATH="$tracked/config.toml" RIFT_RUN_TRACKED_LAUNCH_AGENT_PATH="$tracked/rift.plist" \
        RIFT_TEST_MUTATE_LIVE=1 RIFT_TEST_BOOTSTRAP_FAIL_ONCE=1 activate "$tmp"; then
        fail "byte-for-byte rollback was accepted"
    fi
    cmp -s "$tmp/old-config" "$tmp/home/.config/rift/config.toml" || fail "config bytes changed after rollback"
    cmp -s "$tmp/old-layout" "$tmp/home/.rift/layout.ron" || fail "schema-2 layout bytes changed after rollback"
    cmp -s "$tmp/old-plist" "$tmp/home/Library/LaunchAgents/git.acsandmann.rift.plist" || fail "LaunchAgent bytes changed after rollback"
    cmp -s "$tmp/old-receipt" "$tmp/state/receipt" || fail "receipt bytes changed after rollback"
    [[ "$(readlink "$tmp/state/current")" == "$tmp/brew" ]] || fail "old pointer was not restored"
    [[ "$(readlink "$tmp/home/.local/bin/rift")" == "$tmp/state/current/rift" ]] || fail "old stable link was not restored"
    pass "failed activation restores config, schema-2 layout, LaunchAgent, receipt, and links byte-for-byte"

    rm -f "$tmp/state/current" "$tmp/home/.local/bin/rift" "$tmp/home/.local/bin/rift-cli" \
        "$tmp/home/.config/rift/config.toml" "$tmp/home/.rift/layout.ron" \
        "$tmp/home/Library/LaunchAgents/git.acsandmann.rift.plist" "$tmp/state/receipt" \
        "$tmp/running" "$tmp/mutate-live" "$tmp/bootstrap-failed"
    : >"$tmp/calls"
    if RIFT_RUN_TRACKED_CONFIG_PATH="$tracked/config.toml" RIFT_RUN_TRACKED_LAUNCH_AGENT_PATH="$tracked/rift.plist" \
        RIFT_TEST_MUTATE_LIVE=1 RIFT_TEST_BOOTSTRAP_FAIL_ONCE=1 activate "$tmp"; then
        fail "absence rollback was accepted"
    fi
    [[ ! -e "$tmp/state/current" ]] || fail "absent pointer was recreated"
    [[ ! -e "$tmp/home/.local/bin/rift" && ! -e "$tmp/home/.local/bin/rift-cli" ]] || fail "absent stable links were recreated"
    [[ ! -e "$tmp/home/.config/rift/config.toml" ]] || fail "absent config was recreated"
    [[ ! -e "$tmp/home/.rift/layout.ron" ]] || fail "absent layout was recreated"
    [[ ! -e "$tmp/home/Library/LaunchAgents/git.acsandmann.rift.plist" ]] || fail "absent LaunchAgent was recreated"
    [[ ! -e "$tmp/state/receipt" ]] || fail "absent receipt was recreated"
    pass "failed activation restores missing managed paths to absence"
)

test_successful_activation_installs_tracked_assets() (
    local tmp="$(mktemp -d)" tracked; tracked="$tmp/tracked"; trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"; make_fixture "$tmp"; stage "$tmp" >/dev/null
    mkdir -p "$tracked"
    printf 'tracked config bytes\n' >"$tracked/config.toml"
    printf 'tracked launch agent bytes\n' >"$tracked/rift.plist"
    if RIFT_RUN_TRACKED_CONFIG_PATH="$tracked/config.toml" RIFT_RUN_TRACKED_LAUNCH_AGENT_PATH="$tracked/rift.plist" activate "$tmp" >/dev/null; then :; else
        fail "successful tracked activation failed"
    fi
    cmp -s "$tracked/config.toml" "$tmp/home/.config/rift/config.toml" || fail "tracked config was not installed exactly"
    cmp -s "$tracked/rift.plist" "$tmp/home/Library/LaunchAgents/git.acsandmann.rift.plist" || fail "tracked LaunchAgent was not installed exactly"
    grep -Fqx "config-check $tracked/config.toml" "$tmp/calls" || fail "config check did not use tracked config"
    pass "successful activation installs and checks tracked config and LaunchAgent"
)

test_loaded_but_stopped_service_is_restored() (
    local tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"; make_fixture "$tmp"; stage "$tmp" >/dev/null
    mkdir -p "$tmp/state"; ln -s "$tmp/brew" "$tmp/state/current"; : >"$tmp/loaded"; : >"$tmp/calls"
    if RIFT_TEST_BOOTSTRAP_FAIL_ONCE=1 activate "$tmp"; then fail "loaded-but-stopped failure was accepted"; fi
    [[ -f "$tmp/loaded" && ! -e "$tmp/running" ]] || fail "loaded-but-stopped state was not restored"
    grep -Fq 'launchctl kill SIGTERM ' "$tmp/calls" || fail "stopped loaded service was not terminated after bootstrap"
    pass "loaded-but-stopped service state is restored exactly"
)

test_rollback_failure_retains_snapshot() (
    local tmp="$(mktemp -d)" output; trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"; make_fixture "$tmp"; stage "$tmp" >/dev/null; : >"$tmp/calls"
    if output="$(RIFT_TEST_DIRECTORY_COLLISION=1 RIFT_TEST_MUTATE_LIVE=1 RIFT_TEST_BOOTSTRAP_FAIL_ONCE=1 activate "$tmp" 2>&1)"; then
        fail "rollback failure was accepted"
    fi
    grep -Fq 'activation snapshot retained for manual recovery:' <<<"$output" || fail "rollback failure was not reported"
    find "$tmp/state" -maxdepth 1 -type d -name '.activation.*' -print -quit | grep -q . || fail "failed rollback discarded activation snapshot"
    pass "rollback failure is reported and activation snapshot is retained"
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
    [[ ! -e "$tmp/state/current" ]] || fail "signal did not restore absent pointer"
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
    grep -Fq '/chezmoi/dot_config/rift/config.toml' "$helper" || \
        fail "production activation does not read the tracked Rift config"
    ! grep -Eq 'brew[[:space:]]+(install|upgrade|services)' "$helper" || fail "installer mutates Homebrew"
    pass "installer keeps immutable production pin and no Homebrew mutation"
}

# Revisions produce different executable bytes in the fake cargo build.
test_fixed_path_across_changed_revisions() (
    local tmp="$(mktemp -d)" next="abcdef0123456789abcdef0123456789abcdef01" name old_inode
    trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"; make_fixture "$tmp"; activate "$tmp" >/dev/null
    old_inode="$(ls -di "$tmp/state/active" | awk '{ print $1 }')"
    RIFT_RUN_EXPECTED_REVISION="$next" RIFT_TEST_REVISION="$next" activate "$tmp" >/dev/null
    [[ "$(ls -di "$tmp/state/active" | awk '{ print $1 }')" == "$old_inode" ]] || fail "active directory was replaced"
    for name in rift rift-cli; do
        [[ ! -L "$tmp/state/active/$name" ]] || fail "active binary is a symlink"
        [[ "$(readlink "$tmp/home/.local/bin/$name")" == "$tmp/state/active/$name" ]] || fail "command path changed"
        cmp -s "$tmp/state/active/$name" "$tmp/state/releases/$next/$name" || fail "new bytes were not installed"
        ! cmp -s "$tmp/state/active/$name" "$tmp/state/releases/$REVISION/$name" || fail "test did not change executable bytes"
    done
    [[ "$(readlink "$tmp/state/current")" == "$tmp/state/releases/$next" ]] || fail "release metadata did not advance"
    [[ -f "$tmp/running" ]] || fail "updated service is not running"
    pass "changed builds keep the same real executable paths and retain both releases"
)

test_active_upgrade_failure_restores_both_binaries() (
    local tmp="$(mktemp -d)" next="abcdef0123456789abcdef0123456789abcdef01" mode name
    trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"; make_fixture "$tmp"; activate "$tmp" >/dev/null
    cp "$tmp/state/receipt" "$tmp/old-receipt"
    for mode in RIFT_TEST_BOOTSTRAP_FAIL_ONCE RIFT_TEST_ACTIVE_RENAME_FAIL_ONCE RIFT_TEST_ACTIVE_SIGNAL_ONCE; do
        if (export "$mode=1"; RIFT_RUN_EXPECTED_REVISION="$next" RIFT_TEST_REVISION="$next" activate "$tmp"); then
            fail "$mode was accepted"
        fi
        for name in rift rift-cli; do
            cmp -s "$tmp/state/active/$name" "$tmp/state/releases/$REVISION/$name" || fail "$mode did not restore $name"
        done
        cmp -s "$tmp/state/receipt" "$tmp/old-receipt" || fail "$mode changed receipt"
        [[ "$(readlink "$tmp/state/current")" == "$tmp/state/releases/$REVISION" ]] || fail "$mode changed release metadata"
        [[ -f "$tmp/running" ]] || fail "$mode did not restart previous service"
    done
    pass "bootstrap failure, partial replacement, and interruption restore both old binaries before restart"
)

test_versioned_link_migrates_to_active() (
    local tmp="$(mktemp -d)" name
    trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"; make_fixture "$tmp"; stage "$tmp" >/dev/null
    ln -s "$tmp/state/releases/$REVISION" "$tmp/state/current"
    for name in rift rift-cli; do ln -s "$tmp/state/current/$name" "$tmp/home/.local/bin/$name"; done
    : >"$tmp/running"
    if RIFT_TEST_BOOTSTRAP_FAIL_ONCE=1 activate "$tmp"; then fail "failed migration accepted"; fi
    [[ ! -e "$tmp/state/active" ]] || fail "failed migration left active directory"
    [[ "$(readlink "$tmp/home/.local/bin/rift")" == "$tmp/state/current/rift" ]] || fail "failed migration did not restore legacy link"
    [[ -f "$tmp/running" ]] || fail "failed migration did not restore service"
    activate "$tmp" >/dev/null
    [[ "$(readlink "$tmp/home/.local/bin/rift")" == "$tmp/state/active/rift" ]] || fail "migration kept versioned execution path"
    pass "versioned installations migrate to the permanent path with rollback"
)

test_active_symlinks_rejected_before_stop() (
    local tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"; make_fixture "$tmp"; stage "$tmp" >/dev/null
    ln -s "$tmp/state/releases/$REVISION" "$tmp/state/active"
    : >"$tmp/running"; : >"$tmp/calls"
    if activate "$tmp"; then fail "active directory symlink accepted"; fi
    ! grep -Fq 'launchctl bootout ' "$tmp/calls" || fail "invalid active path stopped service"
    rm "$tmp/state/active"; mkdir "$tmp/state/active"
    ln -s "$tmp/state/releases/$REVISION/rift" "$tmp/state/active/rift"
    if activate "$tmp"; then fail "active executable symlink accepted"; fi
    ! grep -Fq 'launchctl bootout ' "$tmp/calls" || fail "invalid executable path stopped service"
    pass "active directory and executable symlinks fail before stopping Rift"
)

test_fixed_path_across_changed_revisions
test_active_upgrade_failure_restores_both_binaries
test_versioned_link_migrates_to_active
test_active_symlinks_rejected_before_stop

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
test_candidate_mach_readiness_failure_rolls_back
test_transaction_restores_bytes_and_absence
test_successful_activation_installs_tracked_assets
test_loaded_but_stopped_service_is_restored
test_rollback_failure_retains_snapshot
test_receipt_snapshot_failure_is_inert
test_signal_rolls_back_candidate
test_config_failure_before_stop
test_template_contract
echo "Rift local installer tests passed"
