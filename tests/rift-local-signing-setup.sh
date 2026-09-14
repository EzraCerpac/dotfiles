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
    local output="${1:?output required}" vars_json
    vars_json="$(python3 "$ROOT/tests/lib/tera.py" --read-vars "$ROOT/config.toml" \
        --var-key rift_signing_identity)"
    python3 "$ROOT/tests/lib/tera.py" \
        --source "$ROOT/templates/.local/bin/rift-local-signing-setup.tera" \
        --target "$output" --scratch "$(dirname "$output")" \
        --vars-json "$vars_json" >/dev/null
    chmod +x "$output"
    bash -n "$output"
}

make_fixture() {
    local tmp="${1:?temporary directory required}"

    mkdir -p "$tmp/bin" "$tmp/home"
    cat >"$tmp/bin/security" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '  1) 0123456789012345678901234567890123456789 "Rift Local Code Signing"\n'
printf '1 valid identities found\n'
EOF
    cat >"$tmp/bin/codesign" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${RIFT_TEST_TRUST_FAIL:-0}" == 1 && "$*" == *"-R="* ]]; then
    printf 'CSSMERR_TP_NOT_TRUSTED\n' >&2
    exit 1
fi
case "$*" in
    *"-d -r-"*) printf 'designated => anchor trusted\n' ;;
    *"--display"*)
        printf 'Identifier=%s\n' "${RIFT_TEST_PROBE_IDENTIFIER:-git.acsandmann.rift.signing-probe}"
        printf 'Authority=%s\n' "${RIFT_TEST_PROBE_AUTHORITY:-Rift Local Code Signing}"
        ;;
esac
EOF
    chmod +x "$tmp/bin"/*
}

run_helper() {
    local tmp="${1:?temporary directory required}"
    shift
    printf '\n' |
        env HOME="$tmp/home" TMPDIR="$tmp" PATH="$tmp/bin:/usr/bin:/bin" \
            RIFT_SECURITY_BIN="$tmp/bin/security" \
            RIFT_CODESIGN_BIN="$tmp/bin/codesign" \
            "$@"
}

test_trusted_probe() (
    local tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"
    make_fixture "$tmp"
    run_helper "$tmp" "$tmp/helper" >"$tmp/output"
    grep -Fq 'Validated Rift Local Code Signing' "$tmp/output" ||
        fail "trusted temporary probe was not accepted"
    pass "trusted signing setup probe accepted"
)

test_untrusted_probe() (
    local tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"
    make_fixture "$tmp"
    if RIFT_TEST_TRUST_FAIL=1 run_helper "$tmp" "$tmp/helper" >"$tmp/output" 2>&1; then
        fail "untrusted temporary probe was accepted"
    fi
    grep -Fq 'not trusted for code signing' "$tmp/output" ||
        fail "untrusted probe failure was not explained"
    pass "untrusted signing setup probe rejected"
)

test_probe_metadata() (
    local tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    render_helper "$tmp/helper"
    make_fixture "$tmp"
    if RIFT_TEST_PROBE_AUTHORITY=Wrong run_helper "$tmp" "$tmp/helper" >"$tmp/output" 2>&1; then
        fail "wrong probe Authority was accepted"
    fi
    if RIFT_TEST_PROBE_IDENTIFIER=wrong.id run_helper "$tmp" "$tmp/helper" >"$tmp/output" 2>&1; then
        fail "wrong probe Identifier was accepted"
    fi
    pass "signing probe Authority and Identifier are verified"
)

test_instructions() {
    local helper="$(mktemp)"
    trap 'rm -f "$helper"' RETURN
    render_helper "$helper"
    grep -Fq 'Rift Local Code Signing' "$helper" || fail "helper omits identity name"
    grep -Fq 'private key stays' "$helper" || fail "helper omits private-key warning"
    grep -Fq 'Always Trust' "$helper" || fail "helper omits certificate trust instructions"
    grep -Fq -- '--identifier' "$helper" || fail "helper omits stable probe identifier"
    ! grep -Eq 'security[^\n]*export|openssl[^\n]*pkcs' "$helper" ||
        fail "helper suggests exporting the private key"
    pass "signing setup explains stable identity and key safety"
}

test_trusted_probe
test_untrusted_probe
test_probe_metadata
test_instructions

echo "Rift local signing setup tests passed"
