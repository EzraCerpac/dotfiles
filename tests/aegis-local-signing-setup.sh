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

render_wizard() {
    local output="${1:?output required}"
    chezmoi execute-template --init=false --source "$ROOT" \
        --file dot_local/bin/executable_aegis-local-signing-setup.tmpl >"$output"
    chmod +x "$output"
}

make_fixture() {
    local tmp="${1:?temporary directory required}"

    mkdir -p "$tmp/bin" "$tmp/home"
    cat >"$tmp/bin/security" <<'EOF'
#!/usr/bin/env bash
printf '  1) 0123456789012345678901234567890123456789 "Aegis Local Code Signing"\n'
printf '1 valid identities found\n'
EOF
    cat >"$tmp/bin/codesign" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"-R="* ]] && [[ "${AEGIS_TEST_TRUST_FAIL:-0}" == 1 ]]; then
    printf 'CSSMERR_TP_NOT_TRUSTED\n' >&2
    exit 1
fi
case "$*" in
    *"-d -r-"*) printf 'designated => anchor trusted\n' ;;
esac
EOF
    cat >"$tmp/bin/open" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$tmp/bin"/*
}

run_wizard() {
    local tmp="${1:?temporary directory required}"
    shift
    printf '\n\n' |
        env HOME="$tmp/home" TMPDIR="$tmp" PATH="$tmp/bin:/usr/bin:/bin" \
            AEGIS_SECURITY_BIN="$tmp/bin/security" \
            AEGIS_CODESIGN_BIN="$tmp/bin/codesign" \
            "$@"
}

test_trusted_probe() (
    local tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    render_wizard "$tmp/wizard"
    make_fixture "$tmp"
    run_wizard "$tmp" "$tmp/wizard" >"$tmp/output"
    grep -Fq 'Certificate trust validated with a temporary signed probe.' "$tmp/output" || \
        fail "trusted temporary probe was not accepted"
    pass "trusted signing setup probe accepted"
)

test_untrusted_probe() (
    local tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    render_wizard "$tmp/wizard"
    make_fixture "$tmp"
    if AEGIS_TEST_TRUST_FAIL=1 run_wizard "$tmp" "$tmp/wizard" >"$tmp/output" 2>&1; then
        fail "untrusted temporary probe was accepted"
    fi
    grep -Fq 'certificate is not trusted for code signing' "$tmp/output" || \
        fail "untrusted probe failure was not explained"
    pass "untrusted signing setup probe rejected"
)

test_instructions() {
    local wizard="$(mktemp)"
    trap 'rm -f "$wizard"' RETURN
    render_wizard "$wizard"
    grep -Fq 'Always Trust' "$wizard" || fail "wizard omits certificate trust instructions"
    grep -Fq 'temporary trust probe' "$wizard" || fail "wizard omits temporary probe"
    pass "signing setup explains certificate trust"
}

test_trusted_probe
test_untrusted_probe
test_instructions

echo "Aegis local signing setup tests passed"
