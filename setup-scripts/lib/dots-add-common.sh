#!/usr/bin/env bash
# Shared recording behavior for dots add tools and bootstrap packages.

dots_edit_config() {
    (cd "$setup_root" && uv run --script "$setup_root/setup-scripts/lib/dots-add-config.py" "$@")
}

dots_record_failed() {
    local declaration="$1" target="$2" answer
    printf '\nRequested declaration for %s:\n%s\n' "$target" "$declaration" >&2
    if [[ ! -t 0 || ! -t 2 ]]; then
        printf 'dots: request was not recorded (noninteractive run).\n' >&2
        return 1
    fi
    printf 'Record this request for a later retry? [y/N] ' >&2
    if ! IFS= read -r answer; then
        printf '\ndots: request was not recorded.\n' >&2
        return 1
    fi
    case "$answer" in
        y|Y|yes|Yes|YES) return 0 ;;
        *) printf 'dots: request was not recorded.\n' >&2; return 1 ;;
    esac
}
