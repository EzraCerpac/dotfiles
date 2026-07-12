#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKTREE_OPENCODE="${ROOT}/dot_local/bin/executable_worktree-opencode"
PRDIFF_REVIEW="${ROOT}/dot_local/bin/executable_prdiff-review"
GITLOGUE_SELECT="${ROOT}/dot_local/bin/executable_gitlogue-select"

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "${TEST_ROOT}"' EXIT

FAKE_BIN="${TEST_ROOT}/bin"
CALLS="${TEST_ROOT}/calls"
FZF_QUEUE="${TEST_ROOT}/fzf-queue"
mkdir -p "${FAKE_BIN}"
: >"${CALLS}"
: >"${FZF_QUEUE}"

export CALLS FZF_QUEUE
export PATH="${FAKE_BIN}:/usr/bin:/bin"

cat >"${FAKE_BIN}/wt" <<'EOF'
#!/usr/bin/env bash
printf 'wt' >>"${CALLS}"
printf ' <%s>' "$@" >>"${CALLS}"
printf '\n' >>"${CALLS}"
exit "${WT_FAIL:-0}"
EOF

cat >"${FAKE_BIN}/opencode" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat >"${FAKE_BIN}/gh" <<'EOF'
#!/usr/bin/env bash
printf 'gh' >>"${CALLS}"
printf ' <%s>' "$@" >>"${CALLS}"
printf '\n' >>"${CALLS}"
if [[ -n "${GH_FAIL:-}" ]]; then
    exit "${GH_FAIL}"
fi
printf 'rendered diff\n'
EOF

cat >"${FAKE_BIN}/diffnav" <<'EOF'
#!/usr/bin/env bash
input="$(cat)"
printf 'diffnav <%s>' "$input" >>"${CALLS}"
printf ' <%s>' "$@" >>"${CALLS}"
printf '\n' >>"${CALLS}"
exit "${DIFFNAV_FAIL:-0}"
EOF

cat >"${FAKE_BIN}/git" <<'EOF'
#!/usr/bin/env bash
if [[ -n "${GIT_FAIL:-}" ]]; then
    printf 'git: simulated failure\n' >&2
    exit "${GIT_FAIL}"
fi
case "$*" in
    *"--format=%an"*) printf 'Ada\nGrace\nAda\n' ;;
    *) printf 'abc123 First commit\ndef456 Second commit\n' ;;
esac
EOF

cat >"${FAKE_BIN}/fzf" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
if [[ "${FZF_CANCEL:-0}" == 1 ]]; then
    exit 130
fi
response="$(head -n 1 "${FZF_QUEUE}")"
tail -n +2 "${FZF_QUEUE}" >"${FZF_QUEUE}.next"
mv "${FZF_QUEUE}.next" "${FZF_QUEUE}"
if [[ "${response}" == __CANCEL__ ]]; then
    exit 130
fi
printf '%s\n' "${response}"
EOF

cat >"${FAKE_BIN}/gitlogue" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == theme && "${2:-}" == list ]]; then
    printf 'Available themes:\n  - tokyo\n  - nord\n'
    exit 0
fi
printf 'gitlogue' >>"${CALLS}"
if [[ $# -gt 0 ]]; then
    printf ' <%s>' "$@" >>"${CALLS}"
fi
printf '\n' >>"${CALLS}"
exit "${GITLOGUE_FAIL:-0}"
EOF

chmod +x "${FAKE_BIN}"/*

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_calls() {
    local expected="$1"
    local actual
    actual="$(cat "${CALLS}")"
    [[ "${actual}" == "${expected}" ]] || fail "expected calls [${expected}], got [${actual}]"
}

reset_case() {
    : >"${CALLS}"
    : >"${FZF_QUEUE}"
    unset DIFFNAV_FAIL FZF_CANCEL GH_FAIL GIT_FAIL GITLOGUE_FAIL WT_FAIL
}

run_worktree_opencode() {
    bash "${WORKTREE_OPENCODE}" "$@"
}

run_prdiff_review() {
    bash "${PRDIFF_REVIEW}" "$@"
}

run_gitlogue_select() {
    bash "${GITLOGUE_SELECT}" "$@"
}

reset_case
if run_worktree_opencode >"${TEST_ROOT}/stdout" 2>"${TEST_ROOT}/stderr"; then
    fail "worktree-opencode accepted missing branch"
fi
grep -q '^usage: worktree-opencode <branch> \[prompt\.\.\.\]$' "${TEST_ROOT}/stderr" || fail "missing usage error"

reset_case
if run_worktree_opencode '' >"${TEST_ROOT}/stdout" 2>"${TEST_ROOT}/stderr"; then
    fail "worktree-opencode accepted empty branch"
fi

reset_case
run_worktree_opencode feature/demo
assert_calls 'wt <switch> <--create> <feature/demo> <--execute> <opencode>'

reset_case
run_worktree_opencode feature/demo 'fix issue 42' 'keep tests narrow'
assert_calls 'wt <switch> <--create> <feature/demo> <--execute> <opencode> <--> <fix issue 42> <keep tests narrow>'

reset_case
run_worktree_opencode feature/demo --dangerously-skip-permissions
assert_calls 'wt <switch> <--create> <feature/demo> <--execute> <opencode> <--> <--dangerously-skip-permissions>'

reset_case
export WT_FAIL=9
set +e
run_worktree_opencode feature/demo
status=$?
set -e
[[ ${status} -eq 9 ]] || fail "worktree-opencode returned ${status}, expected 9"

reset_case
run_prdiff_review 42 --color=always
assert_calls $'gh <pr> <diff> <42> <--color=always>\ndiffnav <rendered diff> <--side-by-side>'

reset_case
export GH_FAIL=7
set +e
run_prdiff_review 42
status=$?
set -e
[[ ${status} -eq 7 ]] || fail "prdiff-review returned ${status}, expected 7"

reset_case
export DIFFNAV_FAIL=6
set +e
run_prdiff_review 42
status=$?
set -e
[[ ${status} -eq 6 ]] || fail "prdiff-review returned ${status}, expected 6"

reset_case
printf 'abc123 First commit\n' >"${FZF_QUEUE}"
run_gitlogue_select browse --author Ada
assert_calls 'gitlogue <--commit> <abc123>'

reset_case
printf '\033[31mabc123\033[0m First commit\n' >"${FZF_QUEUE}"
run_gitlogue_select browse
assert_calls 'gitlogue <--commit> <abc123>'

reset_case
export FZF_CANCEL=1
run_gitlogue_select browse
assert_calls ''

reset_case
printf 'abc123 First commit\n' >"${FZF_QUEUE}"
export GIT_FAIL=8
set +e
run_gitlogue_select browse 2>"${TEST_ROOT}/stderr"
status=$?
set -e
[[ ${status} -eq 8 ]] || fail "gitlogue-select returned ${status}, expected 8"
assert_calls ''

reset_case
printf 'abc123 First commit\n' >"${FZF_QUEUE}"
export GIT_FAIL=1
set +e
run_gitlogue_select browse 2>"${TEST_ROOT}/stderr"
status=$?
set -e
[[ ${status} -eq 1 ]] || fail "gitlogue-select returned ${status}, expected Git status 1"
grep -q '^git: simulated failure$' "${TEST_ROOT}/stderr" || fail "git failure message missing"
assert_calls ''

reset_case
printf 'abc123 First commit\n' >"${FZF_QUEUE}"
export GITLOGUE_FAIL=5
set +e
run_gitlogue_select browse
status=$?
set -e
[[ ${status} -eq 5 ]] || fail "gitlogue-select returned ${status}, expected 5"

run_menu_case() {
    local responses="$1"
    local expected="$2"
    reset_case
    printf '%s\n' "${responses}" >"${FZF_QUEUE}"
    run_gitlogue_select menu
    assert_calls "${expected}"
}

run_menu_case 'Random commits' 'gitlogue'
run_menu_case $'Specific commit\nabc123 First commit' 'gitlogue <--commit> <abc123>'
run_menu_case $'By author\nGrace Hopper' 'gitlogue <--author> <Grace Hopper>'
run_menu_case $'By date range\n1 week ago' 'gitlogue <--after> <1 week ago>'
run_menu_case $'Theme selection\ntokyo' 'gitlogue <--theme> <tokyo>'

reset_case
export FZF_CANCEL=1
run_gitlogue_select menu
assert_calls ''

reset_case
printf '%s\n' 'Specific commit' '__CANCEL__' >"${FZF_QUEUE}"
run_gitlogue_select menu
assert_calls ''

reset_case
if run_gitlogue_select >"${TEST_ROOT}/stdout" 2>"${TEST_ROOT}/stderr"; then
    fail "gitlogue-select accepted missing mode"
fi

reset_case
if run_gitlogue_select unknown >"${TEST_ROOT}/stdout" 2>"${TEST_ROOT}/stderr"; then
    fail "gitlogue-select accepted unknown mode"
fi

reset_case
if run_gitlogue_select menu extra >"${TEST_ROOT}/stdout" 2>"${TEST_ROOT}/stderr"; then
    fail "gitlogue-select menu accepted arguments"
fi

printf 'shell workflow tests passed\n'
