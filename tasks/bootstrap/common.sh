#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/../lib/mise-bin.sh"

bootstrap_error() {
    printf 'bootstrap: %s\n' "$*" >&2
}

bootstrap_init() {
    if [[ -z "${HOME:-}" ]]; then
        bootstrap_error 'HOME is not set'
        return 2
    fi

    BOOTSTRAP_CONFIG_DIR="${MISE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/mise}"
    if [[ ! -d "$BOOTSTRAP_CONFIG_DIR" ]]; then
        bootstrap_error "mise config directory does not exist: $BOOTSTRAP_CONFIG_DIR"
        return 2
    fi
    BOOTSTRAP_CONFIG_DIR="$(cd "$BOOTSTRAP_CONFIG_DIR" && pwd -P)" || return 1
    BOOTSTRAP_HOME="$(cd "$HOME" && pwd -P)" || return 1
    BOOTSTRAP_MISE_ENV="${SETUP_PROFILE},host-${SETUP_MACHINE_ID}"

    BOOTSTRAP_MISE_BIN="$(resolve_mise_bin)" || {
        local resolve_status=$?
        bootstrap_error 'could not select a mise executable; use SETUP_MISE_BIN or install mise in ~/.local/bin or PATH'
        return "$resolve_status"
    }

    export MISE_CONFIG_DIR="$BOOTSTRAP_CONFIG_DIR"
}

bootstrap_validate_profile() {
    case "${SETUP_PROFILE:-}" in
        workstation|nas) ;;
        *) bootstrap_error 'profile must be workstation or nas'; return 2 ;;
    esac

    if [[ -z "${SETUP_MACHINE_ID:-}" || ! "$SETUP_MACHINE_ID" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
        bootstrap_error 'machine id must contain lowercase letters, digits, and hyphens'
        return 2
    fi
}

bootstrap_toml_quote() {
    local escaped="$1"
    escaped="${escaped//\\/\\\\}"
    escaped="${escaped//\"/\\\"}"
    printf '"%s"' "$escaped"
}

bootstrap_mise() {
    "$BOOTSTRAP_MISE_BIN" --quiet --cd "$BOOTSTRAP_CONFIG_DIR" --env "$BOOTSTRAP_MISE_ENV" "$@"
}

bootstrap_miserc_env_values() {
    local path="$BOOTSTRAP_CONFIG_DIR/miserc.toml" scan selector_present env_table raw values
    [[ -e "$path" || -L "$path" ]] || return 0
    if [[ -L "$path" || ! -f "$path" ]]; then
        bootstrap_error "refusing non-regular mise early config: $path"
        return 2
    fi

    # Let mise validate the complete file, then ask its TOML reader for the
    # early selector. This accepts multiline arrays and TOML single-quoted
    # strings without parsing source syntax ourselves.
    if ! "$BOOTSTRAP_MISE_BIN" --quiet --cd "$BOOTSTRAP_CONFIG_DIR" config get --file "$path" >/dev/null 2>&1; then
        bootstrap_error "could not parse mise early config: $path"
        return 2
    fi
    scan="$(awk '
        BEGIN { in_table = 0; selector = 0; env_table = 0 }
        /^[[:space:]]*\[/ {
            header = $0
            gsub(/[[:space:]]/, "", header)
            if (header == "[env]" || header == "[[env]]" ||
                header ~ /^\[env\./ || header ~ /^\[\[env\./) env_table = 1
            in_table = 1
            next
        }
        !in_table && /^[[:space:]]*env[[:space:]]*=/ { selector = 1 }
        END { printf "%d %d\n", selector, env_table }
    ' "$path")" || return 1
    read -r selector_present env_table <<< "$scan"
    if [[ "$env_table" -eq 1 ]]; then
        bootstrap_error 'miserc [env] tables conflict with its early selector; use a bare env array'
        return 2
    fi
    [[ "$selector_present" -eq 1 ]] || return 0

    raw="$("$BOOTSTRAP_MISE_BIN" --quiet --cd "$BOOTSTRAP_CONFIG_DIR" config get --file "$path" env 2>/dev/null)" || {
        bootstrap_error 'could not read the miserc early environment selector'
        return 2
    }
    values="$(printf '%s\n' "$raw" | awk '
        function skip_space() {
            while (pos <= size && index(" \t\r\n", substr(text, pos, 1))) pos++
        }
        function invalid() { exit 2 }
        { text = text $0 " " }
        END {
            size = length(text)
            pos = 1
            skip_space()
            if (substr(text, pos, 1) != "[") invalid()
            pos++
            skip_space()
            if (substr(text, pos, 1) == "]") {
                pos++
                skip_space()
                if (pos <= size) invalid()
                exit 0
            }
            while (pos <= size) {
                if (substr(text, pos, 1) != "\"") invalid()
                pos++
                item = ""
                while (pos <= size && substr(text, pos, 1) != "\"") {
                    char = substr(text, pos, 1)
                    if (char == "\\" || char ~ /[[:cntrl:]]/) invalid()
                    item = item char
                    pos++
                }
                if (pos > size || item !~ /^[A-Za-z0-9_.-]+$/) invalid()
                print item
                pos++
                skip_space()
                char = substr(text, pos, 1)
                if (char == ",") {
                    pos++
                    skip_space()
                    if (substr(text, pos, 1) == "]") { pos++; break }
                    continue
                }
                if (char == "]") { pos++; break }
                invalid()
            }
            skip_space()
            if (pos <= size) invalid()
        }
    ' 2>/dev/null)" || {
        bootstrap_error 'miserc env must be a simple array of selector names; refusing to rewrite it'
        return 2
    }
    if [[ -n "$values" ]]; then
        printf '%s\n' "$values"
    fi
    return 0
}

bootstrap_set_miserc_env() {
    local profile="$1" machine_id="$2" tmp selector values host_count=0 selector_line
    local prior duplicate i
    local path="$BOOTSTRAP_CONFIG_DIR/miserc.toml"
    local -a selectors=() preserved=()
    values="$(bootstrap_miserc_env_values)" || return $?
    selectors=("$profile" "host-$machine_id")
    while IFS= read -r selector; do
        [[ -n "$selector" ]] || continue
        case "$selector" in
            workstation|nas|delftblue) continue ;;
        esac
        if [[ "$selector" =~ ^host-[a-z0-9][a-z0-9-]*$ ]]; then
            ((host_count += 1))
            if [[ "$host_count" -gt 1 ]]; then
                bootstrap_error 'miserc has multiple host identities; resolve them before changing the profile'
                return 2
            fi
            continue
        fi
        duplicate=0
        for prior in "${selectors[@]}"; do
            [[ "$prior" == "$selector" ]] && duplicate=1
        done
        if ((${#preserved[@]})); then
            for prior in "${preserved[@]}"; do
                [[ "$prior" == "$selector" ]] && duplicate=1
            done
        fi
        [[ "$duplicate" -eq 1 ]] || preserved+=("$selector")
    done <<< "$values"
    if ((${#preserved[@]})); then
        selectors+=("${preserved[@]}")
    fi

    selector_line='env = ['
    for ((i = 0; i < ${#selectors[@]}; i++)); do
        ((i == 0)) || selector_line+=", "
        selector_line+="$(bootstrap_toml_quote "${selectors[$i]}")"
    done
    selector_line+=']'

    if [[ -L "$path" || ( -e "$path" && ! -f "$path" ) ]]; then
        bootstrap_error "refusing non-regular mise early config: $path"
        return 2
    fi
    tmp="$(mktemp "$BOOTSTRAP_CONFIG_DIR/.miserc.XXXXXX")" || return 1
    {
        # This bare array is mise's early config selector. It must be in the
        # global miserc, before normal config discovery begins.
        if [[ -f "$path" ]]; then
            awk -v selector_line="$selector_line" '
                function array_closed(s, i, c, quote, escaped) {
                    quote = ""
                    escaped = 0
                    for (i = 1; i <= length(s); i++) {
                        c = substr(s, i, 1)
                        if (escaped) { escaped = 0; continue }
                        if (quote == "\"" && c == "\\") { escaped = 1; continue }
                        if (quote != "") {
                            if (c == quote) quote = ""
                            continue
                        }
                        if (c == "#") break
                        if (c == "\"" || c == "\047") { quote = c; continue }
                        if (c == "]") return 1
                    }
                    return 0
                }
                BEGIN { in_table = 0; skip_env = 0 }
                skip_env {
                    if (array_closed($0)) skip_env = 0
                    next
                }
                /^[[:space:]]*\[/ {
                    if (!wrote) { print selector_line; wrote = 1 }
                    in_table = 1
                    print
                    next
                }
                !in_table && /^[[:space:]]*env[[:space:]]*=/ {
                    if (!wrote) { print selector_line; wrote = 1 }
                    value = $0
                    sub(/^[[:space:]]*env[[:space:]]*=/, "", value)
                    if (!array_closed(value)) skip_env = 1
                    next
                }
                {
                    if (!wrote && !in_table) { print selector_line; wrote = 1 }
                    print
                }
                END { if (!wrote) print selector_line }
            ' "$path"
        else
            printf '%s\n' "$selector_line"
        fi
    } > "$tmp" || { rm -f "$tmp"; return 1; }
    chmod 600 "$tmp" || { rm -f "$tmp"; return 1; }
    mv "$tmp" "$path" || { rm -f "$tmp"; return 1; }
}

bootstrap_set_local() {
    local key="$1" value="$2" type="${3:-}"
    local path="$BOOTSTRAP_CONFIG_DIR/config.local.toml"
    touch "$path" || return 1
    chmod 600 "$path" || return 1

    if [[ -n "$type" ]]; then
        bootstrap_mise config set --type "$type" --file "$path" "$key" "$value"
    else
        bootstrap_mise config set --file "$path" "$key" "$value"
    fi
}

bootstrap_append_local() {
    local key="$1" value="$2" type="${3:-}"
    local path="$BOOTSTRAP_CONFIG_DIR/config.local.toml"
    touch "$path" || return 1
    chmod 600 "$path" || return 1

    if [[ -n "$type" ]]; then
        bootstrap_mise config set --append --type "$type" --file "$path" "$key" "$value"
    else
        bootstrap_mise config set --append --file "$path" "$key" "$value"
    fi
}

bootstrap_persist_local_profile() {
    local identity_label="${1:-}"
    bootstrap_set_local env.SETUP_PROFILE "$SETUP_PROFILE" || return $?
    bootstrap_set_local env.SETUP_MACHINE_ID "$SETUP_MACHINE_ID" || return $?
    bootstrap_set_local settings.history.sync manual || return $?

    if [[ -n "$identity_label" ]]; then
        bootstrap_set_local env.SETUP_AGE_IDENTITY "$identity_label" || return $?
        bootstrap_set_local settings.age.identity_files "$identity_label" list || return $?
    fi

    if [[ -n "${SETUP_HISTORY_ORIGIN:-}" ]]; then
        bootstrap_set_local env.SETUP_HISTORY_ORIGIN "$SETUP_HISTORY_ORIGIN" || return $?
    fi
}

bootstrap_persist_profile() {
    local identity_label="${1:-}"
    bootstrap_init || return $?
    bootstrap_validate_profile || return $?

    # Global miserc is read before mise discovers the profile config files.
    bootstrap_set_miserc_env "$SETUP_PROFILE" "$SETUP_MACHINE_ID" || return $?
    bootstrap_persist_local_profile "$identity_label"
}
