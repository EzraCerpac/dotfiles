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

assert_not_contains() {
    local file="${1:?file required}"
    local pattern="${2:?pattern required}"
    if grep -Fq -- "$pattern" "$file"; then
        fail "unexpected '$pattern' in $file"
    fi
}

render_reconciler() {
    local output="${1:?output required}"
    shift
    chezmoi execute-template --init=false --source "$ROOT" "$@" \
        --file run_after_03-reconcile-tools.sh.tmpl >"$output"
}

make_stub_bin() {
    local bin="${1:?bin required}"
    mkdir -p "$bin"
    cat >"$bin/stub" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
name="$(basename "$0")"
printf '%s %s\n' "$name" "$*" >>"${CALL_LOG:?}"

case "$name:$*" in
    "brew:shellenv") echo ':' ;;
    "brew:bundle check"*) exit "${BREW_CHECK_CODE:-0}" ;;
    "brew:list felixkratz/formulae/sketchybar") exit 1 ;;
    "mise:install --dry-run-code") exit "${MISE_DRY_RUN_CODE:-0}" ;;
    "mise:exec uv -- uv tool install --upgrade keymap-drawer")
        ln -sf "$0" "${STUB_BIN:?}/keymap"
        ;;
    "npm:install --global @zed-industries/codex-acp")
        [[ "${NPM_FAIL:-0}" == 1 ]] && exit 1
        ln -sf "$0" "${STUB_BIN:?}/codex-acp"
        ;;
esac
STUB
    chmod +x "$bin/stub"
    local command_name
    for command_name in brew mise herdr keymap codex-acp curl npm; do
        ln -s stub "$bin/$command_name"
    done
}

seed_markers() {
    local script="${1:?script required}"
    local state="${2:?state required}"
    local name variable value
    mkdir -p "$state"
    while read -r name variable; do
        value="$(sed -n "s/^readonly ${variable}=\"\(.*\)\"$/\1/p" "$script")"
        printf '%s\n' "$value" >"$state/$name"
    done <<'EOF'
packages PACKAGES_FINGERPRINT
mise MISE_FINGERPRINT
herdr HERDR_FINGERPRINT
keymap-drawer KEYMAP_DRAWER_FINGERPRINT
codex-acp CODEX_ACP_FINGERPRINT
EOF
}

test_unchanged_state() (
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    render_reconciler "$tmp/reconcile"
    make_stub_bin "$tmp/bin"
    seed_markers "$tmp/reconcile" "$tmp/state"
    : >"$tmp/calls"

    HOME="$tmp/home" PATH="$tmp/bin:/usr/bin:/bin" STUB_BIN="$tmp/bin" \
        CALL_LOG="$tmp/calls" BREW_BIN="$tmp/bin/brew" \
        TOOL_RECONCILE_PATH="$tmp/bin:/usr/bin:/bin" \
        TOOL_RECONCILE_STATE_DIR="$tmp/state" bash "$tmp/reconcile" >/dev/null

    assert_not_contains "$tmp/calls" "brew bundle install"
    assert_not_contains "$tmp/calls" "mise install --yes"
    assert_not_contains "$tmp/calls" "npm install"
    pass "unchanged state skips installers"
)

test_selective_mise() (
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    render_reconciler "$tmp/reconcile"
    make_stub_bin "$tmp/bin"
    seed_markers "$tmp/reconcile" "$tmp/state"
    printf 'old\n' >"$tmp/state/mise"
    : >"$tmp/calls"

    HOME="$tmp/home" PATH="$tmp/bin:/usr/bin:/bin" STUB_BIN="$tmp/bin" \
        CALL_LOG="$tmp/calls" BREW_BIN="$tmp/bin/brew" MISE_DRY_RUN_CODE=1 \
        TOOL_RECONCILE_PATH="$tmp/bin:/usr/bin:/bin" \
        TOOL_RECONCILE_STATE_DIR="$tmp/state" bash "$tmp/reconcile" >/dev/null

    grep -Fq "mise install --yes" "$tmp/calls" || fail "mise adapter did not install"
    assert_not_contains "$tmp/calls" "brew bundle install"
    assert_not_contains "$tmp/calls" "npm install"
    pass "mise change invokes only mise installer"
)

test_missing_package() (
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    render_reconciler "$tmp/reconcile"
    make_stub_bin "$tmp/bin"
    seed_markers "$tmp/reconcile" "$tmp/state"
    : >"$tmp/calls"

    HOME="$tmp/home" PATH="$tmp/bin:/usr/bin:/bin" STUB_BIN="$tmp/bin" \
        CALL_LOG="$tmp/calls" BREW_BIN="$tmp/bin/brew" BREW_CHECK_CODE=1 \
        TOOL_RECONCILE_PATH="$tmp/bin:/usr/bin:/bin" \
        TOOL_RECONCILE_STATE_DIR="$tmp/state" bash "$tmp/reconcile" >/dev/null

    grep -Fq "brew bundle install" "$tmp/calls" || fail "package adapter did not install"
    assert_not_contains "$tmp/calls" "mise install --yes"
    assert_not_contains "$tmp/calls" "npm install"
    pass "missing package invokes only package installer"
)

test_changed_package_manifest() (
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    render_reconciler "$tmp/reconcile"
    make_stub_bin "$tmp/bin"
    seed_markers "$tmp/reconcile" "$tmp/state"
    printf 'old\n' >"$tmp/state/packages"
    : >"$tmp/calls"

    HOME="$tmp/home" PATH="$tmp/bin:/usr/bin:/bin" STUB_BIN="$tmp/bin" \
        CALL_LOG="$tmp/calls" BREW_BIN="$tmp/bin/brew" BREW_CHECK_CODE=0 \
        TOOL_RECONCILE_PATH="$tmp/bin:/usr/bin:/bin" \
        TOOL_RECONCILE_STATE_DIR="$tmp/state" bash "$tmp/reconcile" >/dev/null

    assert_not_contains "$tmp/calls" "brew bundle install"
    [[ "$(<"$tmp/state/packages")" != old ]] || fail "package fingerprint was not updated"
    assert_not_contains "$tmp/calls" "mise install --yes"
    assert_not_contains "$tmp/calls" "npm install"
    pass "changed package manifest checks presence before install"
)

test_missing_keymap_drawer() (
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    render_reconciler "$tmp/reconcile"
    make_stub_bin "$tmp/bin"
    seed_markers "$tmp/reconcile" "$tmp/state"
    rm "$tmp/bin/keymap"
    : >"$tmp/calls"

    HOME="$tmp/home" PATH="$tmp/bin:/usr/bin:/bin" STUB_BIN="$tmp/bin" \
        CALL_LOG="$tmp/calls" BREW_BIN="$tmp/bin/brew" \
        TOOL_RECONCILE_PATH="$tmp/bin:/usr/bin:/bin" \
        TOOL_RECONCILE_STATE_DIR="$tmp/state" bash "$tmp/reconcile" >/dev/null

    grep -Fq "mise exec uv -- uv tool install --upgrade keymap-drawer" "$tmp/calls" || \
        fail "keymap-drawer adapter did not install"
    assert_not_contains "$tmp/calls" "mise install --yes"
    assert_not_contains "$tmp/calls" "npm install"
    pass "missing keymap-drawer invokes only uv adapter"
)

test_failed_adapter_retries() (
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    render_reconciler "$tmp/reconcile"
    make_stub_bin "$tmp/bin"
    seed_markers "$tmp/reconcile" "$tmp/state"
    rm "$tmp/bin/codex-acp" "$tmp/state/codex-acp"
    : >"$tmp/calls"

    HOME="$tmp/home" PATH="$tmp/bin:/usr/bin:/bin" STUB_BIN="$tmp/bin" \
        CALL_LOG="$tmp/calls" BREW_BIN="$tmp/bin/brew" NPM_FAIL=1 \
        TOOL_RECONCILE_PATH="$tmp/bin:/usr/bin:/bin" \
        TOOL_RECONCILE_STATE_DIR="$tmp/state" bash "$tmp/reconcile" >/dev/null 2>&1

    [[ ! -e "$tmp/state/codex-acp" ]] || fail "failed adapter wrote fingerprint"
    grep -Fq "npm install --global @zed-industries/codex-acp" "$tmp/calls" || fail "npm adapter not called"
    pass "failed adapter leaves no fingerprint"
)

test_delftblue_skip() (
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    render_reconciler "$tmp/reconcile" --override-data '{"profile":"delftblue"}'
    make_stub_bin "$tmp/bin"
    : >"$tmp/calls"

    HOME="$tmp/home" PATH="$tmp/bin:/usr/bin:/bin" STUB_BIN="$tmp/bin" \
        CALL_LOG="$tmp/calls" BREW_BIN="$tmp/bin/brew" \
        TOOL_RECONCILE_PATH="$tmp/bin:/usr/bin:/bin" \
        TOOL_RECONCILE_STATE_DIR="$tmp/state" bash "$tmp/reconcile" >/dev/null

    [[ ! -e "$tmp/state" ]] || fail "DelftBlue created reconciliation state"
    [[ ! -s "$tmp/calls" ]] || fail "DelftBlue invoked an adapter"
    pass "DelftBlue skips workstation reconciliation"
)

test_brew_adopt_noninteractive() (
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT

    if HOME="$tmp/home" BREW_ADOPT_IGNORE_FILE="$tmp/ignored" \
        bash "$ROOT/dot_local/bin/executable_brew-adopt" </dev/null >"$tmp/out" 2>"$tmp/err"; then
        fail "brew-adopt accepted noninteractive input"
    fi
    grep -Fq "requires an interactive terminal" "$tmp/err" || fail "noninteractive guidance missing"
    [[ ! -e "$tmp/ignored" ]] || fail "noninteractive brew-adopt changed ignore state"
    pass "brew-adopt rejects noninteractive use without changes"
)

test_brew_adopt_interactive() (
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    mkdir -p "$tmp/bin" "$tmp/source/.chezmoidata"
    cp "$ROOT/.chezmoidata/packages.yaml" "$tmp/source/.chezmoidata/packages.yaml"

    cat >"$tmp/bin/brew" <<'BREW'
#!/usr/bin/env bash
case "$1 ${2:-} ${3:-}" in
    "leaves  ") printf 'atuin\nnewtool\n' ;;
    "info --json=v2 --formula")
        if [[ "$4" == atuin ]]; then
            echo '{"formulae":[{"name":"atuin","full_name":"atuin","tap":"homebrew/core"}]}'
        else
            echo '{"formulae":[{"name":"newtool","full_name":"example/tools/newtool","tap":"example/tools"}]}'
        fi
        ;;
    "list --cask --full-name") printf 'ignoredcask\nnewcask\n' ;;
    *) exit 1 ;;
esac
BREW
    cat >"$tmp/bin/chezmoi" <<'CHEZMOI'
#!/usr/bin/env bash
[[ "$1" == source-path ]] && printf '%s\n' "${TEST_SOURCE_DIR:?}"
CHEZMOI
    cat >"$tmp/bin/gum" <<'GUM'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${GUM_LOG:?}"
[[ "$*" == *newtool* ]]
GUM
    chmod +x "$tmp/bin/brew" "$tmp/bin/chezmoi" "$tmp/bin/gum"
    printf 'cask\tignoredcask\n' >"$tmp/ignored"
    : >"$tmp/gum-log"

    script -q /dev/null env \
        HOME="$tmp/home" \
        PATH="$tmp/bin:/usr/bin:/bin" \
        TEST_SOURCE_DIR="$tmp/source" \
        BREW_ADOPT_IGNORE_FILE="$tmp/ignored" \
        GUM_LOG="$tmp/gum-log" \
        bash "$ROOT/dot_local/bin/executable_brew-adopt" >/dev/null

    ruby -ryaml -e '
      darwin = YAML.load_file(ARGV.fetch(0)).fetch("packages").fetch("darwin")
      abort "formula missing" unless darwin.fetch("brews").include?("example/tools/newtool")
      abort "tap missing" unless darwin.fetch("taps").include?("example/tools")
    ' "$tmp/source/.chezmoidata/packages.yaml"
    grep -Fqx $'cask\tnewcask' "$tmp/ignored" || fail "declined cask was not ignored"
    assert_not_contains "$tmp/gum-log" "atuin"
    assert_not_contains "$tmp/gum-log" "ignoredcask"
    pass "brew-adopt records adopted and ignored packages"
)

test_brew_adopt_empty_discovery() (
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    mkdir -p "$tmp/bin" "$tmp/source/.chezmoidata"
    cp "$ROOT/.chezmoidata/packages.yaml" "$tmp/source/.chezmoidata/packages.yaml"

    cat >"$tmp/bin/brew" <<'BREW'
#!/usr/bin/env bash
exit 0
BREW
    cat >"$tmp/bin/chezmoi" <<'CHEZMOI'
#!/usr/bin/env bash
[[ "$1" == source-path ]] && printf '%s\n' "${TEST_SOURCE_DIR:?}"
CHEZMOI
    chmod +x "$tmp/bin/brew" "$tmp/bin/chezmoi"

    script -q /dev/null env \
        HOME="$tmp/home" \
        PATH="$tmp/bin:/usr/bin:/bin" \
        TEST_SOURCE_DIR="$tmp/source" \
        BREW_ADOPT_IGNORE_FILE="$tmp/ignored" \
        bash "$ROOT/dot_local/bin/executable_brew-adopt" >"$tmp/out"

    grep -Fq "No unmanaged Homebrew packages." "$tmp/out" || fail "empty discovery did not report success"
    pass "brew-adopt handles empty discovery"
)

test_unchanged_state
test_selective_mise
test_missing_package
test_changed_package_manifest
test_missing_keymap_drawer
test_failed_adapter_retries
test_delftblue_skip
test_brew_adopt_noninteractive
test_brew_adopt_interactive
test_brew_adopt_empty_discovery

echo "tool-management tests passed"
