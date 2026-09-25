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
    echo "Homebrew is required for the CLIProxyAPI service" >&2
    exit 1
}
config_target="$(mise_exec "$brew_bin" --prefix)/etc/cliproxyapi.conf"
if [[ ! -L "$config_target" || "$(realpath "$config_target" 2>/dev/null || true)" != "$(realpath "$config_source")" ]]; then
    echo "CLIProxyAPI config is not linked to the intended file. Run the configure task first." >&2
    exit 1
fi

service_status="$(mise_exec "$brew_bin" services list 2>/dev/null | awk '$1 == "cliproxyapi" { print $2; exit }')"
case "$service_status" in
    started)
        echo "CLIProxyAPI service is already running; leaving it untouched."
        exit 0
        ;;
    stopped|none) ;;
    *)
        echo "CLIProxyAPI service has state '${service_status:-not found}'; inspect installation before activation." >&2
        exit 1
        ;;
esac

mise_exec "$brew_bin" services start cliproxyapi
echo "Started CLIProxyAPI."
