#!/usr/bin/env bash

# shellcheck source=setup-scripts/local/common
source "$(dirname -- "${BASH_SOURCE[0]}")/common"
require_setup_profile workstation
require_macos
# shellcheck source=setup-scripts/local/capd-provenance.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/capd-provenance.sh"
capd_codesign="${CAPD_CODESIGN_BIN:-/usr/bin/codesign}"
capd_plutil="${CAPD_PLUTIL_BIN:-/usr/bin/plutil}"

# Signing identities belong to the host; preserve the signer of its current app.
capd_identity="${CAPD_CODESIGN_IDENTITY:-}"
if [[ -z "$capd_identity" && -d /Applications/capd.app ]]; then
    capd_identity="$("$capd_codesign" -dv --verbose=4 /Applications/capd.app 2>&1 | sed -n 's/^Authority=//p' | head -n 1 || true)"
fi
capd_validate_app() {
    local app="${1:?app required}" component
    [[ -d "$app" ]] || return 1
    [[ "$("$capd_plutil" -extract CFBundleIdentifier raw -o - "$app/Contents/Info.plist")" == dev.jxd.capd ]] || return 1
    for component in CapdApp capd capd-agent; do
        [[ -x "$app/Contents/MacOS/$component" ]] || return 1
        "$capd_codesign" --verify --strict "$app/Contents/MacOS/$component" || return 1
        [[ "$("$capd_codesign" -dv --verbose=4 "$app/Contents/MacOS/$component" 2>&1 | sed -n 's/^Authority=//p' | head -n 1)" == "$capd_identity" ]] || return 1
    done
    [[ -d "$app/Contents/PlugIns/CapdShareExtension.appex" ]] || return 1
    [[ "$("$capd_codesign" -dv --verbose=4 "$app/Contents/PlugIns/CapdShareExtension.appex" 2>&1 | sed -n 's/^Authority=//p' | head -n 1)" == "$capd_identity" ]] || return 1
    "$capd_codesign" --verify --deep --strict "$app" || return 1
    [[ "$("$capd_codesign" -dv --verbose=4 "$app" 2>&1 | sed -n 's/^Authority=//p' | head -n 1)" == "$capd_identity" ]] || return 1
}
