#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=tasks/local/common
source "${SCRIPT_DIR}/common"

deferred_status=3

stable_shell_path="${HOME}/.local/bin/fish"
mise_data_dir="${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}"
needs_stable_link=0
fish_command="$(command -v fish 2>/dev/null || true)"
if [[ -z "$fish_command" || ! -x "$fish_command" ]]; then
    echo "Fish is not installed for the ${SETUP_PROFILE} profile; install the declared Fish package and rerun dots bootstrap." >&2
    exit 1
fi

fish_real="$(realpath "$fish_command" 2>/dev/null || true)"
if [[ -z "$fish_real" || ! -x "$fish_real" ]]; then
    echo "Fish was found at '$fish_command', but its executable target could not be validated." >&2
    exit 1
fi

is_mise_shim_path() {
    case "$1" in
        "$mise_data_dir"/shims/*) return 0 ;;
        *) return 1 ;;
    esac
}

is_mise_install_path() {
    case "$1" in
        "$mise_data_dir"/installs/*) return 0 ;;
        *) return 1 ;;
    esac
}

resolve_mise_fish_install() {
    command -v jq >/dev/null 2>&1 || return 0
    { setup_mise ls --current --json 2>/dev/null || true; } |
        jq -r '
            to_entries[]
            | select((.key | ascii_downcase | contains("fish-shell")) or .key == "fish")
            | .value[]
            | select(.active == true and .installed == true)
            | if .requested_version == "latest"
              then .install_path | sub("/[^/]+$"; "/latest")
              else .install_path end
        ' 2>/dev/null | head -n 1
}

mise_fish_install=""
if [[ -L "$stable_shell_path" ]]; then
    # A stable link can outlive a MISE_DATA_DIR/XDG_DATA_HOME change. Resolve
    # the active Fish metadata before deciding whether the link is managed;
    # otherwise an old target looks like a host-package Fish and is never
    # repaired.
    mise_fish_install="$(resolve_mise_fish_install)"
fi

mise_fish_candidate=""
for candidate in "$mise_fish_install/fish" "$mise_fish_install/bin/fish"; do
    if [[ -n "$mise_fish_install" && -x "$candidate" ]]; then
        mise_fish_candidate="$candidate"
        break
    fi
done
mise_fish_real="$(realpath "$mise_fish_candidate" 2>/dev/null || true)"

mise_fish_identity() {
    local install_path="${1#*/installs/}"
    [[ "$install_path" != "$1" && "$install_path" == */*/fish ]] || return 1
    printf '%s/%s\n' "${install_path%%/*}" "${install_path##*/}"
}

stable_link_is_mise=0
stable_link_real="$(realpath "$stable_shell_path" 2>/dev/null || true)"
if [[ -n "$mise_fish_real" && -L "$stable_shell_path" && -n "$stable_link_real" ]]; then
    # Compare the backend/executable identity from active metadata while
    # allowing the installed version and data-directory prefix to change.
    existing_identity="$(mise_fish_identity "$stable_link_real" 2>/dev/null || true)"
    active_identity="$(mise_fish_identity "$mise_fish_real" 2>/dev/null || true)"
    if [[ -n "$existing_identity" && "$existing_identity" == "$active_identity" ]]; then
        stable_link_is_mise=1
    fi
fi

if is_mise_shim_path "$fish_command" || is_mise_install_path "$fish_real" ||
    [[ "$fish_command" == "$stable_shell_path" && "$stable_link_is_mise" -eq 1 ]]; then
    needs_stable_link=1
    # A mise shim is not a valid login-shell target: it can re-enter mise while
    # mise is constructing the login environment. Find the active install
    # without depending on a backend name or a versioned install directory.
    fish_install="$mise_fish_install"
    [[ -n "$fish_install" ]] || fish_install="$(resolve_mise_fish_install)"

    target_candidate=""
    for candidate in "$fish_install/fish" "$fish_install/bin/fish"; do
        if [[ -n "$fish_install" && -x "$candidate" ]]; then
            target_candidate="$candidate"
            break
        fi
    done
    if [[ -z "$target_candidate" ]]; then
        echo "Fish is selected through mise, but its installed executable could not be resolved; rerun after Fish installation completes." >&2
        exit 1
    fi
    fish_real="$(realpath "$target_candidate" 2>/dev/null || true)"
    if [[ -z "$fish_real" || ! -x "$fish_real" ]] || is_mise_shim_path "$fish_real"; then
        echo "Fish's mise-installed executable failed stable-path validation: '$target_candidate'." >&2
        exit 1
    fi

    runtime_shell="$target_candidate"
    mkdir -p "$(dirname "$stable_shell_path")"
    if [[ -e "$stable_shell_path" && ! -L "$stable_shell_path" ]]; then
        echo "Cannot create stable Fish login path: '$stable_shell_path' is an existing regular file." >&2
        exit 1
    fi
    if [[ -L "$stable_shell_path" && -e "$stable_shell_path" ]]; then
        existing_real="$(realpath "$stable_shell_path" 2>/dev/null || true)"
        if [[ -z "$existing_real" ]] || {
            ! is_mise_install_path "$existing_real" &&
            [[ "$stable_link_is_mise" -ne 1 ]];
        }; then
            echo "Cannot replace stable Fish login path: '$stable_shell_path' is not a mise-managed Fish link." >&2
            exit 1
        fi
    fi
else
    # Host package managers expose a version-independent Fish path already.
    runtime_shell="$fish_command"
fi

runtime_real="$(realpath "$runtime_shell" 2>/dev/null || true)"
if [[ ! -x "$runtime_shell" || -z "$runtime_real" ]] || is_mise_shim_path "$runtime_real"; then
    echo "Refusing to configure an invalid Fish login path: '$runtime_shell'." >&2
    exit 1
fi

# The single-quoted Fish program must receive its arguments from Fish's argv.
# shellcheck disable=SC2016
if ! "$runtime_shell" --no-config -c \
    'fish_add_path --path --dry-run "$argv[1]" >/dev/null 2>&1; or test $status -eq 1; and "$argv[2]" --version >/dev/null' \
    "$(dirname "$runtime_shell")" "$runtime_shell"; then
    echo "Fish was found at '$runtime_shell', but its no-config runtime validation failed." >&2
    exit 1
fi

if [[ "$needs_stable_link" -eq 1 ]]; then
    # Keep mise's backend-managed `latest` path in the link. The resolved
    # version is used only for validation, so upgrades do not strand chsh on a
    # removed version directory.
    ln -sfn "$runtime_shell" "$stable_shell_path"
    target_shell="$stable_shell_path"
else
    target_shell="$runtime_shell"
fi

target_real="$(realpath "$target_shell" 2>/dev/null || true)"
if [[ ! -x "$target_shell" || -z "$target_real" ]] || is_mise_shim_path "$target_real"; then
    echo "Refusing to configure an invalid Fish login path: '$target_shell'." >&2
    exit 1
fi

local_file="$SETUP_ROOT/config.local.toml"
# Recording a declaration needs no administrator access. Check the real account
# before requesting privileges, including first enrollment of an existing Fish user.
setup_mise config set --file "$local_file" bootstrap.user.login_shell "$target_shell"
if setup_mise bootstrap user status --missing >/dev/null 2>&1; then
    echo "Fish is already the configured login shell for the ${SETUP_PROFILE} profile."
    exit 0
fi

admin_needs_prompt=0
if [[ "$(id -u)" -ne 0 ]] && ! sudo -n true >/dev/null 2>&1; then
    admin_needs_prompt=1
    if [[ ! -t 0 ]]; then
        echo "Login-shell setup needs administrator approval. Rerun 'dots bootstrap' in a terminal, or grant passwordless sudo, then retry." >&2
        exit "$deferred_status"
    fi
    echo "Login-shell setup needs administrator approval; mise will ask for your sudo password."
fi

# Resolve the validated host/install path after installer exceptions, then let
# native mise own /etc/shells and the account update.
if setup_mise bootstrap user apply --yes; then
    exit 0
fi
if [[ "$admin_needs_prompt" -eq 1 ]]; then
    echo "Login-shell setup was not applied. Rerun 'dots bootstrap' in a terminal after approving administrator access." >&2
    exit "$deferred_status"
fi
exit 1
