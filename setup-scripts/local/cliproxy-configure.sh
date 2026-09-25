#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=setup-scripts/local/common
source "${SCRIPT_DIR}/common"

require_setup_profile workstation
require_macos
config_source="${HOME}/.cli-proxy-api/config.yaml"
require_file "$config_source"
brew_bin="${BREW_BIN:-}"
if [[ -z "$brew_bin" ]]; then
    if [[ -x /opt/homebrew/bin/brew ]]; then
        brew_bin=/opt/homebrew/bin/brew
    elif [[ -x /usr/local/bin/brew ]]; then
        brew_bin=/usr/local/bin/brew
    else
        brew_bin="$(command -v brew || true)"
    fi
fi
[[ -n "$brew_bin" && -x "$brew_bin" ]] || {
    echo "Homebrew is required to find the CLIProxyAPI service configuration path" >&2
    exit 1
}
prefix="$(mise_exec "$brew_bin" --prefix)"
config_target="${prefix}/etc/cliproxyapi.conf"
config_dir="$(dirname -- "$config_target")"
mkdir -p "$config_dir"

if [[ -L "$config_target" ]]; then
    existing_target="$(realpath "$config_target" 2>/dev/null || true)"
    expected_target="$(realpath "$config_source")"
    [[ "$existing_target" == "$expected_target" ]] || {
        echo "refusing to replace conflicting CLIProxyAPI config symlink: ${config_target} -> $(readlink "$config_target")" >&2
        exit 1
    }
    echo "CLIProxyAPI config link is already correct."
    exit 0
fi

if [[ -e "$config_target" ]]; then
    [[ -f "$config_target" ]] || {
        echo "refusing to replace non-file CLIProxyAPI config path: $config_target" >&2
        exit 1
    }
    if cmp -s "$config_source" "$config_target"; then
        :
    else
        backup="${config_target}.pre-mise"
        [[ ! -e "$backup" && ! -L "$backup" ]] || {
            echo "refusing to overwrite existing backup: $backup" >&2
            exit 1
        }
        cp -p "$config_target" "$backup"
        echo "Preserved the previous config at ${backup}."
    fi
    rm "$config_target"
fi

staged="$(mktemp "${config_dir}/.cliproxyapi.conf.XXXXXX")"
trap 'rm -f "$staged"' EXIT
rm -f "$staged"
ln -s "$config_source" "$staged"
mv "$staged" "$config_target"
trap - EXIT
echo "Configured CLIProxyAPI to use ${config_source}. Service state was not changed."
