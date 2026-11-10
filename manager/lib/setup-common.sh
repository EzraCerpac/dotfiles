#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/mise-bin.sh"

setup_error() {
    printf 'setup: %s\n' "$*" >&2
}

setup_init() {
    # Resolve from this library; callers can sit at different depths.
    local script_path="${BASH_SOURCE[0]}"
    local script_dir
    script_dir="$(cd "$(dirname "$script_path")" && pwd -P)" || return 1

    if [[ -n "${SETUP_CONFIG_ROOT:-}" && -d "$SETUP_CONFIG_ROOT" ]]; then
        # Explicit override exists for disposable task fixtures. Normal runs
        # use the configuration dots selected (DOTS_ROOT), even if the caller's
        # global MISE_CONFIG_DIR points elsewhere.
        SETUP_ROOT="$(cd "$SETUP_CONFIG_ROOT" && pwd -P)" || return 1
    elif [[ -n "${DOTS_ROOT:-}" && -d "$DOTS_ROOT" ]]; then
        SETUP_ROOT="$(cd "$DOTS_ROOT" && pwd -P)" || return 1
    else
        # Outside dots, the manager still sits inside its configuration checkout.
        SETUP_ROOT="$(cd "$script_dir/../.." && pwd -P)" || return 1
    fi
    # Keep the manager that started this run for every child.
    if [[ -z "${DOTS_HOME:-}" ]]; then
        DOTS_HOME="$(cd "$script_dir/.." && pwd -P)" || return 1
    fi
    export DOTS_HOME

    export DOTS_ROOT="$SETUP_ROOT"

    SETUP_PROFILE="${SETUP_PROFILE:-}"
    setup_dots_profiles || return $?
    if [[ -z "$SETUP_PROFILE" ]]; then
        # Fresh clones have no persisted profile yet (miserc.toml and
        # config.local.toml are gitignored). Derive it from the mise
        # environment selector, e.g. `mise -E <profile> bootstrap`.
        local candidate="" matches=0
        for candidate in $SETUP_DOTS_PROFILES; do
            if [[ ",${MISE_ENV:-}," == *",$candidate,"* ]]; then
                SETUP_PROFILE="$candidate"
                ((matches += 1))
            fi
        done
        if ((matches > 1)); then
            SETUP_PROFILE=""
        fi
    fi
    if ! setup_is_profile "$SETUP_PROFILE"; then
        setup_error "SETUP_PROFILE must be one of [vars] dots_profiles: ${SETUP_DOTS_PROFILES// /, } (pass -E PROFILE or export SETUP_PROFILE)"
        return 2
    fi
    export SETUP_PROFILE
    export DOTS_PROFILE="$SETUP_PROFILE"

    SETUP_MACHINE_ID="${SETUP_MACHINE_ID:-}"
    if [[ -n "$SETUP_MACHINE_ID" && ! "$SETUP_MACHINE_ID" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
        setup_error "SETUP_MACHINE_ID must contain lowercase letters, digits, and hyphens"; return 2
    fi

    SETUP_ENVIRONMENTS="$SETUP_PROFILE"
    if [[ -n "$SETUP_MACHINE_ID" ]]; then
        SETUP_ENVIRONMENTS="$SETUP_PROFILE,host-$SETUP_MACHINE_ID"
    fi

    SETUP_EXCEPTION_MANIFEST="$SETUP_ROOT/dots/exceptions.tsv"
}

# Read one [vars] setting from the configuration's config.toml through mise,
# once per process, into SETUP_VAR_<name>. Fails naming the missing setting.
#   setup_dots_var NAME [optional]
setup_dots_var() {
    local name="$1" optional="${2:-}" value mise_bin
    [[ "$name" =~ ^dots_[a-z0-9_]+$ ]] || { setup_error "invalid setting name: $name"; return 2; }
    case " ${SETUP_VARS_LOADED:-} " in *" $name "*) return 0 ;; esac
    mise_bin="$(resolve_mise_bin)" || return $?
    if ! value="$(MISE_AUTO_INSTALL=0 "$mise_bin" -C "$SETUP_ROOT" config get --file "$SETUP_ROOT/config.toml" "vars.$name" 2>/dev/null)"; then
        if [[ "$optional" != optional ]]; then
            setup_error "missing setting: add $name to [vars] in $SETUP_ROOT/config.toml"
            return 2
        fi
        value=""
    fi
    printf -v "SETUP_VAR_$name" '%s' "$value"
    SETUP_VARS_LOADED="${SETUP_VARS_LOADED:-} $name"
}

# Print a list setting one word per line. mise [vars] values must be strings,
# so a list is one string of space-separated words: dots_profiles = "a b".
setup_dots_list() {
    local name="$1" optional="${2:-}" reference word
    setup_dots_var "$name" "$optional" || return $?
    reference="SETUP_VAR_$name"
    for word in ${!reference}; do printf '%s\n' "$word"; done
}

# Load [vars] dots_profiles into SETUP_DOTS_PROFILES (space-separated).
setup_dots_profiles() {
    local profiles profile
    [[ -z "${SETUP_DOTS_PROFILES:-}" ]] || return 0
    profiles="$(setup_dots_list dots_profiles)" || return $?
    for profile in $profiles; do
        if [[ ! "$profile" =~ ^[a-z0-9][a-z0-9-]*$ || "$profile" == base || "$profile" == local || "$profile" == host-* ]]; then
            setup_error "invalid profile name in [vars] dots_profiles: $profile"
            return 2
        fi
    done
    [[ -n "$profiles" ]] || { setup_error "[vars] dots_profiles in $SETUP_ROOT/config.toml lists no profiles"; return 2; }
    SETUP_DOTS_PROFILES="$(printf '%s ' $profiles)"
    SETUP_DOTS_PROFILES="${SETUP_DOTS_PROFILES% }"
}

setup_is_profile() {
    [[ -n "$1" && " ${SETUP_DOTS_PROFILES:-} " == *" $1 "* ]]
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
    printf '%s/dots/exceptions/%s\n' "$SETUP_ROOT" "$name"
}

# Read dots/exceptions.tsv (format in its header) and call
#   CALLBACK NAME PATH FLAGS
# for each row selected for PROFILE (base rows always; "" selects every row).
# A missing manifest declares nothing. Invalid rows stop with status 2. The
# manifest is read on descriptor 3, so callbacks (and the recipes they run)
# keep the caller's stdin, such as the terminal for an administrator prompt.
setup_read_exceptions() {
    local callback="$1" profile="$2"
    local exception_profile="" name="" flags="" extra="" flag script_path
    [[ -f "$SETUP_EXCEPTION_MANIFEST" ]] || return 0
    setup_dots_profiles || return $?
    while IFS=$'\t' read -r -u 3 exception_profile name flags extra || [[ -n "$exception_profile$name$flags$extra" ]]; do
        [[ -z "$exception_profile" || "$exception_profile" == \#* ]] && continue
        if [[ -n "$extra" ]] || { [[ "$exception_profile" != base ]] && ! setup_is_profile "$exception_profile"; }; then
            setup_error "invalid installer exception row in $SETUP_EXCEPTION_MANIFEST"
            return 2
        fi
        for flag in ${flags//,/ }; do
            case "$flag" in
                install-only) ;;
                hold=*)
                    [[ "${flag#hold=}" =~ ^[a-z][a-z0-9-]*:[A-Za-z0-9@._/+-]+$ ]] || {
                        setup_error "invalid hold package '${flag#hold=}' in $SETUP_EXCEPTION_MANIFEST"
                        return 2
                    } ;;
                *) setup_error "unknown installer exception flag '$flag' in $SETUP_EXCEPTION_MANIFEST"; return 2 ;;
            esac
        done
        [[ -z "$profile" || "$exception_profile" == base || "$exception_profile" == "$profile" ]] || continue
        script_path="$(setup_exception_path "$name")" || {
            setup_error "invalid installer exception name in $SETUP_EXCEPTION_MANIFEST"
            return 2
        }
        "$callback" "$name" "$script_path" "$flags" 3<&- || return $?
    done 3< "$SETUP_EXCEPTION_MANIFEST"
}

setup_exception_has_flag() {
    [[ ",$1," == *",$2,"* ]]
}

# Set SETUP_HOLDER to the installer exception whose hold=PACKAGE flag covers
# package KEY (manager:name, with an optional tap prefix or @version), or to ""
# when none does. Returns 2 for an invalid manifest.
setup_exception_holder() {
    SETUP_HOLD_KEY="$1"
    SETUP_HOLDER=""
    setup_read_exceptions setup_match_hold ""
}

setup_match_hold() {
    local flag manager="${SETUP_HOLD_KEY%%:*}" name="${SETUP_HOLD_KEY#*:}"
    name="${name##*/}"
    for flag in ${3//,/ }; do
        [[ "$flag" == hold=* ]] || continue
        if [[ "$manager:$name" == "${flag#hold=}" || "$manager:${name%%@*}" == "${flag#hold=}" ]]; then
            SETUP_HOLDER="$1"
        fi
    done
    return 0
}

# Call CALLBACK NAME PATH FLAGS for each exception of the selected profile.
setup_each_exception() {
    SETUP_EACH_EXCEPTION_CALLBACK="$1"
    setup_read_exceptions setup_each_exception_row "$SETUP_PROFILE"
}

setup_each_exception_row() {
    if [[ ! -x "$2" ]]; then
        setup_error "installer exception '$1' has no executable at $2"
        return 2
    fi
    "$SETUP_EACH_EXCEPTION_CALLBACK" "$@"
}

setup_print_exceptions() {
    if [[ ! -f "$SETUP_EXCEPTION_MANIFEST" ]]; then
        printf 'Installer exceptions: none declared\n'
        return 0
    fi
    printf 'Installer exceptions for %s:\n' "$SETUP_PROFILE"
    SETUP_PRINTED_EXCEPTIONS=0
    setup_read_exceptions setup_print_exception_row "$SETUP_PROFILE" || return $?
    [[ "$SETUP_PRINTED_EXCEPTIONS" -eq 1 ]] || printf '  none declared\n'
}

setup_print_exception_row() {
    SETUP_PRINTED_EXCEPTIONS=1
    if [[ -x "$2" ]]; then
        printf '  %s (ready)\n' "$1"
    else
        printf '  %s (missing executable: %s)\n' "$1" "$2"
        return 2
    fi
}

# Print the executable hooks in DIR, one path per line, in name order. Only
# regular executable files with a plain [A-Za-z0-9._-] name are hooks; a
# missing directory has none.
setup_list_hooks() {
    local directory="$1" path name
    [[ -d "$directory" ]] || return 0
    for path in "$directory"/*; do
        name="${path##*/}"
        [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || continue
        [[ -f "$path" && -x "$path" ]] || continue
        printf '%s\n' "$path"
    done | LC_ALL=C sort
}

# A hook's stage label is its name without a leading order number or a file
# extension, with dashes and underscores as spaces: 20-Login-shell.sh -> Login shell.
setup_hook_label() {
    local label="${1##*/}"
    if [[ "$label" =~ ^[0-9]+[-_](.+)$ ]]; then label="${BASH_REMATCH[1]}"; fi
    if [[ "$label" =~ ^(.+)\.[A-Za-z0-9]+$ ]]; then label="${BASH_REMATCH[1]}"; fi
    label="${label//[-_]/ }"
    printf '%s\n' "$label"
}

setup_read_history_mode() { setup_mise settings get history.sync; }

setup_history_branch() {
    if [[ -z "${SETUP_MACHINE_ID:-}" || ! "$SETUP_MACHINE_ID" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
        setup_error 'SETUP_MACHINE_ID is required to derive the history branch'
        return 2
    fi
    printf 'host-%s\n' "$SETUP_MACHINE_ID"
}

setup_require_history_branch() {
    local expected configured
    expected="$(setup_history_branch)" || return $?
    configured="$(setup_mise config get --file "$SETUP_ROOT/config.local.toml" history.origin.branch 2>/dev/null)" || {
        setup_error "history origin branch is not configured as $expected; enroll this host before publishing"
        return 2
    }
    if [[ "$configured" != "$expected" ]]; then
        setup_error "history origin branch is '$configured', expected '$expected'; refusing to publish"
        return 2
    fi
    printf '%s\n' "$expected"
}
