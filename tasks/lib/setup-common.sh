#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/mise-bin.sh"

setup_error() {
    printf 'setup: %s\n' "$*" >&2
}

setup_init() {
    local script_path="${BASH_SOURCE[1]}"
    local script_dir
    script_dir="$(cd "$(dirname "$script_path")" && pwd -P)" || return 1

    if [[ -n "${SETUP_CONFIG_ROOT:-}" && -d "$SETUP_CONFIG_ROOT" ]]; then
        # Explicit override exists for disposable task fixtures. Normal runs
        # always use the checkout that contains this script, even if the
        # caller's global MISE_CONFIG_DIR points elsewhere.
        SETUP_ROOT="$(cd "$SETUP_CONFIG_ROOT" && pwd -P)" || return 1
    else
        SETUP_ROOT="$(cd "$script_dir/../.." && pwd -P)" || return 1
    fi

    SETUP_PROFILE="${SETUP_PROFILE:-}"
    case "$SETUP_PROFILE" in
        workstation|nas) ;;
        *) setup_error "SETUP_PROFILE must be workstation or nas"; return 2 ;;
    esac

    SETUP_MACHINE_ID="${SETUP_MACHINE_ID:-}"
    if [[ -n "$SETUP_MACHINE_ID" && ! "$SETUP_MACHINE_ID" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
        setup_error "SETUP_MACHINE_ID must contain lowercase letters, digits, and hyphens"; return 2
    fi

    SETUP_ENVIRONMENTS="$SETUP_PROFILE"
    if [[ -n "$SETUP_MACHINE_ID" ]]; then
        SETUP_ENVIRONMENTS="$SETUP_PROFILE,host-$SETUP_MACHINE_ID"
    fi

    SETUP_EXCEPTION_MANIFEST="$SETUP_ROOT/tasks/setup/exceptions.tsv"
}

setup_mise() {
    local mise_bin platform ruby_path ruby_bin
    mise_bin="$(resolve_mise_bin)" || return $?

    # Native package bootstrap evaluates Homebrew taps with Ruby. On macOS,
    # expose the already-selected mise Ruby directly so that evaluation does
    # not go through the shim from inside the package sandbox. Never install
    # Ruby here: status remains read-only, and a missing runtime leaves the
    # native command to report its own result.
    platform="$(uname -s 2>/dev/null || true)"
    if [[ "$platform" == "Darwin" && "${1:-}" == "bootstrap" ]] &&
        { [[ "${2:-}" == "status" ]] || [[ "${2:-}" == "packages" ]]; }; then
        ruby_path="$(MISE_AUTO_INSTALL=0 "$mise_bin" -C "$SETUP_ROOT" -E "$SETUP_ENVIRONMENTS" which ruby 2>/dev/null || true)"
        if [[ -n "$ruby_path" && -x "$ruby_path" ]]; then
            ruby_bin="$(dirname "$ruby_path")"
            PATH="$ruby_bin:$PATH" MISE_AUTO_INSTALL=0 "$mise_bin" -C "$SETUP_ROOT" -E "$SETUP_ENVIRONMENTS" "$@"
            return $?
        fi
    fi

    MISE_AUTO_INSTALL=0 "$mise_bin" -C "$SETUP_ROOT" -E "$SETUP_ENVIRONMENTS" "$@"
}

setup_exception_path() {
    local name="$1"
    [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || return 2
    printf '%s/tasks/setup/exceptions/%s\n' "$SETUP_ROOT" "$name"
}

setup_each_exception() {
    local callback="$1"
    local exception_profile="" name="" extra="" script_path
    [[ -f "$SETUP_EXCEPTION_MANIFEST" ]] || return 0

    while IFS=$'\t' read -r exception_profile name extra || [[ -n "$exception_profile$name$extra" ]]; do
        [[ -z "$exception_profile" || "$exception_profile" == \#* ]] && continue
        if [[ -n "$extra" || ! "$exception_profile" =~ ^(base|workstation|nas)$ ]]; then
            setup_error "invalid installer exception row in $SETUP_EXCEPTION_MANIFEST"
            return 2
        fi
        [[ "$exception_profile" == "$SETUP_PROFILE" || "$exception_profile" == base ]] || continue
        script_path="$(setup_exception_path "$name")" || {
            setup_error "invalid installer exception name in $SETUP_EXCEPTION_MANIFEST"
            return 2
        }
        if [[ ! -x "$script_path" ]]; then
            setup_error "installer exception '$name' has no executable at $script_path"
            return 2
        fi
        "$callback" "$name" "$script_path" || return $?
    done < "$SETUP_EXCEPTION_MANIFEST"
}

setup_print_exceptions() {
    local exception_profile="" name="" extra="" script_path
    if [[ ! -f "$SETUP_EXCEPTION_MANIFEST" ]]; then
        printf 'Installer exceptions: none declared\n'
        return 0
    fi

    printf 'Installer exceptions for %s:\n' "$SETUP_PROFILE"
    local any=0
    while IFS=$'\t' read -r exception_profile name extra || [[ -n "$exception_profile$name$extra" ]]; do
        [[ -z "$exception_profile" || "$exception_profile" == \#* ]] && continue
        if [[ -n "$extra" || ! "$exception_profile" =~ ^(base|workstation|nas)$ ]]; then
            setup_error "invalid installer exception row in $SETUP_EXCEPTION_MANIFEST"
            return 2
        fi
        [[ "$exception_profile" == "$SETUP_PROFILE" || "$exception_profile" == base ]] || continue
        script_path="$(setup_exception_path "$name")" || return 2
        any=1
        if [[ -x "$script_path" ]]; then
            printf '  %s (ready)\n' "$name"
        else
            printf '  %s (missing executable: %s)\n' "$name" "$script_path"
            return 2
        fi
    done < "$SETUP_EXCEPTION_MANIFEST"
    [[ "$any" -eq 1 ]] || printf '  none declared\n'
}

setup_read_history_mode() { setup_mise settings get history.sync; }
