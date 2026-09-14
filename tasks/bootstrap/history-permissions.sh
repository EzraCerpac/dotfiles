#!/usr/bin/env bash
set -euo pipefail

history_permissions_error() {
    printf 'bootstrap: %s\n' "$*" >&2
}

bootstrap_secure_history_paths() {
    if [[ -z "${HOME:-}" || ! -d "$HOME" ]]; then
        history_permissions_error 'HOME must name an existing directory'
        return 2
    fi

    local home_real path parent_real normalized count=0 has_targets=0
    local -a targets=()
    home_real="$(cd "$HOME" && pwd -P)" || return 1

    while IFS= read -r path || [[ -n "$path" ]]; do
        [[ -n "$path" ]] || continue
        if [[ "$path" != /* || "$path" == *$'\r'* || "$path" == *$'\t'* ]]; then
            history_permissions_error 'native history path list contains an invalid path'
            return 2
        fi
        case "$path" in
            "$HOME"/*|"$home_real"/*) ;;
            *) history_permissions_error 'history path is outside HOME'; return 2 ;;
        esac
        case "/$path/" in
            */../*|*/./*) history_permissions_error 'history path contains a relative path component'; return 2 ;;
        esac
        if [[ -L "$path" ]]; then
            history_permissions_error "refusing symlink history path: $path"
            return 2
        fi
        [[ -e "$path" ]] || continue
        if [[ ! -f "$path" ]]; then
            history_permissions_error "refusing non-regular history path: $path"
            return 2
        fi

        parent_real="$(cd "$(dirname "$path")" && pwd -P)" || return 1
        case "$parent_real/" in
            "$home_real"/*) ;;
            *) history_permissions_error 'history path resolves outside HOME'; return 2 ;;
        esac
        normalized="$parent_real/$(basename "$path")"
        if [[ -L "$normalized" || ! -f "$normalized" ]]; then
            history_permissions_error "history path changed during permission check: $path"
            return 2
        fi
        targets+=("$normalized")
        has_targets=1
    done

    if [[ "$has_targets" -eq 0 ]]; then
        printf 'Secured 0 tracked history files with mode 0600.\n'
        return 0
    fi

    for path in "${targets[@]}"; do
        chmod 600 "$path" || {
            history_permissions_error "could not set mode 0600 on tracked history file: $path"
            return 1
        }
        ((count += 1))
    done

    printf 'Secured %d tracked history files with mode 0600.\n' "$count"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    bootstrap_secure_history_paths
fi
