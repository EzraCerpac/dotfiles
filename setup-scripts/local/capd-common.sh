#!/usr/bin/env bash

# shellcheck source=setup-scripts/local/common
source "$(dirname -- "${BASH_SOURCE[0]}")/common"
require_setup_profile workstation
require_macos

# Signing identities belong to the host; preserve the signer of its current app.
capd_identity="${CAPD_CODESIGN_IDENTITY:-}"
if [[ -z "$capd_identity" && -d /Applications/capd.app ]]; then
    capd_identity="$(/usr/bin/codesign -dv --verbose=4 /Applications/capd.app 2>&1 | sed -n 's/^Authority=//p' | head -n 1 || true)"
fi
[[ -n "$capd_identity" ]] || {
    setup_error 'set CAPD_CODESIGN_IDENTITY or keep the signed current capd app available'
    return 1
}

capd_validate_app() {
    local app="${1:?app required}" component
    [[ -d "$app" ]] || return 1
    [[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$app/Contents/Info.plist")" == dev.jxd.capd ]] || return 1
    for component in CapdApp capd capd-agent; do
        [[ -x "$app/Contents/MacOS/$component" ]] || return 1
        /usr/bin/codesign --verify --strict "$app/Contents/MacOS/$component" || return 1
        [[ "$(/usr/bin/codesign -dv --verbose=4 "$app/Contents/MacOS/$component" 2>&1 | sed -n 's/^Authority=//p' | head -n 1)" == "$capd_identity" ]] || return 1
    done
    [[ -d "$app/Contents/PlugIns/CapdShareExtension.appex" ]] || return 1
    [[ "$(/usr/bin/codesign -dv --verbose=4 "$app/Contents/PlugIns/CapdShareExtension.appex" 2>&1 | sed -n 's/^Authority=//p' | head -n 1)" == "$capd_identity" ]] || return 1
    /usr/bin/codesign --verify --deep --strict "$app" || return 1
    [[ "$(/usr/bin/codesign -dv --verbose=4 "$app" 2>&1 | sed -n 's/^Authority=//p' | head -n 1)" == "$capd_identity" ]] || return 1
}
