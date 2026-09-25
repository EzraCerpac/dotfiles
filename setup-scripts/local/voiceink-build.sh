#!/usr/bin/env bash

set -euo pipefail
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=setup-scripts/local/common
source "${SCRIPT_DIR}/common"
require_setup_profile workstation
require_macos

source_dir="${VOICEINK_SOURCE_DIR:-${HOME}/Projects/Tools/VoiceInk}"
active_app="/Applications/VoiceInk.app"
stage_root="${VOICEINK_STAGE_ROOT:-${HOME}/.local/state/voiceink/staged}"
package_state="${source_dir}/.local-build/SourcePackages"
resolved_file="${source_dir}/VoiceInk.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
whisper_framework="${VOICEINK_WHISPER_FRAMEWORK:-${HOME}/VoiceInk-Dependencies/whisper.cpp/build-apple/whisper.xcframework}"

setup_error() {
    printf 'voiceink: %s\n' "$*" >&2
}

require_command() {
    local command_name="${1:?command required}"
    mise_exec which "$command_name" >/dev/null 2>&1 || {
        setup_error "required command not found through mise: ${command_name}"
        return 1
    }
}

signature_authority() {
    local path="${1:?signed path required}"
    /usr/bin/codesign -dv --verbose=4 "$path" 2>&1 |
        sed -n 's/^Authority=//p' |
        head -n 1
}

validate_stage() {
    local stage="${1:?stage path required}"
    local app="${stage}/VoiceInk.app"
    local info="${app}/Contents/Info.plist"
    local app_version bundle_id

    [[ -d "$app" && -x "${app}/Contents/MacOS/VoiceInk" && -f "${stage}/BUILD-INFO" ]] || return 1
    /usr/bin/grep -Fxq "revision=${source_revision}" "${stage}/BUILD-INFO" || return 1
    /usr/bin/grep -Fxq "signing_identity=${signing_identity}" "${stage}/BUILD-INFO" || return 1
    app_version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$info" 2>/dev/null)" || return 1
    bundle_id="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$info" 2>/dev/null)" || return 1
    [[ "$bundle_id" == com.prakashjoshipax.VoiceInk ]] || return 1
    /usr/bin/grep -Fxq "version=${app_version}" "${stage}/BUILD-INFO" || return 1
    [[ "$(signature_authority "$app")" == "$signing_identity" ]] || return 1
    /usr/bin/codesign --verify --deep --strict "$app" >/dev/null 2>&1 || return 1
}

require_command git
require_command bash
require_command xcodebuild

[[ -d "$source_dir" && -f "${source_dir}/VoiceInk.xcodeproj/project.pbxproj" ]] || {
    setup_error "VoiceInk source checkout not found: ${source_dir}"
    exit 1
}
[[ -f "$resolved_file" ]] || {
    setup_error "the checked-in Swift package lockfile is missing: ${resolved_file}"
    exit 1
}
[[ -d "${package_state}/checkouts" && -f "${package_state}/workspace-state.json" ]] || {
    setup_error "resolved package checkouts are missing; this task will not download them"
    exit 1
}
[[ -d "$whisper_framework" ]] || {
    setup_error "required Whisper framework is missing: ${whisper_framework}; prepare it separately"
    exit 1
}
[[ -f "${source_dir}/VoiceInk/VoiceInk.local.entitlements" && -f "${source_dir}/LocalBuild.xcconfig" ]] || {
    setup_error "local build configuration or entitlements are missing"
    exit 1
}
/usr/bin/plutil -lint "${source_dir}/VoiceInk/VoiceInk.local.entitlements" >/dev/null || {
    setup_error "local build entitlements are invalid"
    exit 1
}

source_revision="$(mise_exec git -C "$source_dir" rev-parse HEAD)"
[[ "$source_revision" =~ ^[0-9a-f]{40}$ ]] || {
    setup_error "could not resolve the full source revision"
    exit 1
}
source_changes="$(mise_exec git -C "$source_dir" status --porcelain=v1 --untracked-files=all)"
[[ -z "$source_changes" ]] || {
    setup_error "source checkout has changes; preserve or reconcile them before building"
    printf '%s\n' "$source_changes" >&2
    exit 1
}

signing_identity="${VOICEINK_CODESIGN_IDENTITY:-}"
if [[ -z "$signing_identity" && -d "$active_app" ]]; then
    signing_identity="$(signature_authority "$active_app" || true)"
fi
[[ "$signing_identity" == Apple\ Development:* ]] || {
    setup_error "set VOICEINK_CODESIGN_IDENTITY to the current Apple Development identity"
    exit 1
}
identity_matches="$(/usr/bin/security find-identity -v -p codesigning | grep -F "\"${signing_identity}\"" || true)"
[[ "$(printf '%s\n' "$identity_matches" | awk 'NF { n += 1 } END { print n + 0 }')" -eq 1 ]] || {
    setup_error "Apple Development identity is missing or ambiguous in the keychain: ${signing_identity}"
    exit 1
}

stage_path="${stage_root}/${source_revision}"
if [[ -e "$stage_path" ]]; then
    if validate_stage "$stage_path"; then
        printf 'VoiceInk revision %s is already staged at %s\n' "$source_revision" "$stage_path"
        exit 0
    fi
    setup_error "staging destination exists but does not match this revision and signer; preserving it: ${stage_path}"
    exit 1
fi

mkdir -p "$stage_root"
build_root="$(mktemp -d "${stage_root}/.build.XXXXXX")"
cleanup() {
    [[ -n "${build_root:-}" && -d "$build_root" ]] && rm -rf -- "$build_root"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

source_copy="${build_root}/source"
mkdir -p "$source_copy"
mise_exec git -C "$source_dir" archive --format=tar "$source_revision" | tar -xf - -C "$source_copy"

echo "Building VoiceInk ${source_revision} in an isolated source copy with local updater protections"
# The literal $(inherited) is an Xcode setting expression, not shell expansion.
# shellcheck disable=SC2016
mise_exec xcodebuild \
    -project "${source_copy}/VoiceInk.xcodeproj" \
    -scheme VoiceInk \
    -configuration Debug \
    -derivedDataPath "${build_root}/DerivedData" \
    -clonedSourcePackagesDirPath "$package_state" \
    -xcconfig "${source_copy}/LocalBuild.xcconfig" \
    -disableAutomaticPackageResolution \
    -onlyUsePackageVersionsFromResolvedFile \
    -skipPackagePluginValidation \
    -skipMacroValidation \
    CODE_SIGN_IDENTITY="$signing_identity" \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGNING_ALLOWED=YES \
    DEVELOPMENT_TEAM= \
    CODE_SIGN_ENTITLEMENTS="${source_copy}/VoiceInk/VoiceInk.local.entitlements" \
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) LOCAL_BUILD' \
    build

app_build="${build_root}/DerivedData/Build/Products/Debug/VoiceInk.app"
[[ -d "$app_build" ]] || {
    setup_error "Xcode did not produce the expected app bundle: ${app_build}"
    exit 1
}
/usr/bin/codesign --force --sign "$signing_identity" \
    --entitlements "${source_copy}/VoiceInk/VoiceInk.local.entitlements" \
    --timestamp=none "$app_build" >/dev/null

stage_temp="${build_root}/stage"
mkdir -p "$stage_temp"
/usr/bin/ditto "$app_build" "${stage_temp}/VoiceInk.app"
app_version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "${stage_temp}/VoiceInk.app/Contents/Info.plist")"
cat > "${stage_temp}/BUILD-INFO" <<EOF
revision=${source_revision}
version=${app_version}
signing_identity=${signing_identity}
configuration=Debug
updater=disabled-local-build
EOF

if ! validate_stage "$stage_temp"; then
    setup_error "staged app failed version, bundle identifier, revision, or signature validation"
    exit 1
fi
if ! mv -n "$stage_temp" "$stage_path"; then
    setup_error "could not publish the validated stage at ${stage_path}"
    exit 1
fi
if ! validate_stage "$stage_path"; then
    setup_error "staging destination changed during publication; preserving it for inspection: ${stage_path}"
    exit 1
fi

printf 'Built and staged VoiceInk %s (%s) at %s\n' "$app_version" "$source_revision" "$stage_path"
echo 'No package updates, app install, launch, quit, or user-data changes were made.'
