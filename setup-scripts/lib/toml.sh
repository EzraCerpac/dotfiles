#!/usr/bin/env bash
# TOML validation through mise, the setup's one TOML reader. Source this file.

# toml_check MISE_BIN FILE
#   Returns 0 when FILE is valid TOML, 1 when it is not, and 2 when mise cannot
#   run. mise reads FILE in an empty configuration directory, so an unrelated
#   setup problem cannot masquerade as invalid input. Nothing is printed: a
#   parse error quotes the offending line, and these files can hold secrets.
toml_check() {
    local mise_bin="${1-}" file="${2:?toml_check: file required}"
    local scratch status=0
    # An empty binary (a failed resolver) means mise cannot run, not a usage bug.
    [[ -n "$mise_bin" ]] || return 2
    if [[ "$mise_bin" == */* ]]; then
        [[ -x "$mise_bin" ]] || return 2
    else
        command -v "$mise_bin" >/dev/null 2>&1 || return 2
    fi
    # An executable that cannot launch (a missing interpreter or loader exits
    # 126/127) is unavailable too; only a running mise can call a file invalid.
    "$mise_bin" --version >/dev/null 2>&1 || return 2
    scratch="$(mktemp -d "${TMPDIR:-/tmp}/toml-check.XXXXXX")" || return 2
    MISE_CONFIG_DIR="$scratch" MISE_TRUSTED_CONFIG_PATHS="$scratch" MISE_ENV='' \
        "$mise_bin" --quiet --cd "$scratch" config get --file "$file" >/dev/null 2>&1 || status=1
    rm -rf "$scratch"
    return "$status"
}
