#!/usr/bin/env bash
# Add mise-managed tools one at a time for the `dots add` wrapper.
#
#   dots-tool-add.sh MISE_BIN SETUP_ROOT TARGET_CONFIG TOOL@VERSION...

set -euo pipefail

usage() {
    printf 'usage: %s MISE_BIN SETUP_ROOT TARGET_CONFIG TOOL@VERSION...\n' "$0" >&2
}

if [[ "$#" -lt 4 ]]; then
    usage
    exit 2
fi

mise_bin="$1"
setup_root="$2"
target_file="$3"
shift 3

[[ -x "$mise_bin" ]] || { printf 'dots: mise executable is missing: %s\n' "$mise_bin" >&2; exit 2; }
[[ -d "$setup_root" ]] || { printf 'dots: setup root is missing: %s\n' "$setup_root" >&2; exit 2; }
[[ -f "$setup_root/setup-scripts/lib/dots-add-common.sh" ]] || {
    printf 'dots: shared add helper is missing under %s\n' "$setup_root" >&2
    exit 2
}

# Keep mise's registries and defaults rooted in the setup checkout. A private
# temp path lets us exercise the native resolver without giving it the final
# config as a partial-write destination.
export MISE_CONFIG_DIR="$setup_root"
# shellcheck source=/dev/null
source "$setup_root/setup-scripts/lib/dots-add-common.sh"

stage_dir=""
snapshot=""
cleanup() {
    [[ -z "$snapshot" ]] || rm -f "$snapshot"
    [[ -z "$stage_dir" ]] || rm -rf "$stage_dir"
}
trap cleanup EXIT

for request in "$@"; do
    stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/dots-tool-stage.XXXXXX")"
    snapshot="$(mktemp "${TMPDIR:-/tmp}/dots-tool-before.XXXXXX")"
    staged_file="$stage_dir/mise.toml"
    if [[ -f "$target_file" ]]; then
        cp "$target_file" "$snapshot"
    fi
    # Only tool declarations cross into the temporary trust boundary. Target
    # hooks, env, includes and settings must never execute through --path.
    dots_edit_config stage-tools "$snapshot" "$staged_file" "$request"
    cp "$staged_file" "$stage_dir/before.toml"

    if MISE_TRUSTED_CONFIG_PATHS="$stage_dir${MISE_TRUSTED_CONFIG_PATHS:+:$MISE_TRUSTED_CONFIG_PATHS}" "$mise_bin" -C "$setup_root" use --path "$staged_file" "$request"; then
        if ! dots_edit_config record-tools "$target_file" "$staged_file" --before "$snapshot" --staged-before "$stage_dir/before.toml"; then
            printf 'dots: mise succeeded, but its tool declaration could not be merged into %s\n' "$target_file" >&2
            exit 1
        fi
        if "$mise_bin" -C "$setup_root" reshim; then
            printf 'dots: installed %s and saved its native declaration to %s\n' "$request" "$target_file" >&2
            rm -f "$snapshot"
            snapshot=""
            rm -rf "$stage_dir"
            stage_dir=""
            continue
        else
            reshim_status=$?
            printf 'dots: %s was installed and recorded, but mise reshim failed\n' "$request" >&2
            exit "$reshim_status"
        fi
    else
        mise_status=$?
    fi

    # A keyboard cancellation belongs to the user; don't follow it with a
    # second prompt asking whether to preserve the interrupted request.
    if [[ "$mise_status" -eq 130 || "$mise_status" -eq 143 ]]; then
        exit "$mise_status"
    fi

    declaration=""
    if ! declaration="$(dots_edit_config show-tool "$target_file" "$request")"; then
        printf 'dots: could not display failed tool request: %s\n' "$request" >&2
        exit "$mise_status"
    fi
    if dots_record_failed "$declaration" "$target_file"; then
        if dots_edit_config record-tool "$target_file" "$request" --before "$snapshot"; then
            printf 'dots: recorded failed request in %s\n' "$target_file" >&2
        else
            printf 'dots: failed request was not recorded: %s\n' "$request" >&2
        fi
    fi
    exit "$mise_status"
done
