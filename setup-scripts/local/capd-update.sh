#!/usr/bin/env bash
set -euo pipefail
umask 077
# shellcheck source=setup-scripts/local/capd-common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/capd-common.sh"

stage_only=0
if [[ $# -eq 1 && "$1" == --stage-only ]]; then
    stage_only=1
elif [[ $# -ne 0 ]]; then
    setup_error 'usage: local:capd-update [--stage-only]'; exit 2
fi
repository=https://github.com/EzraCerpac/capd.git
branch=main
stage_root="${CAPD_STAGE_ROOT:-${HOME}/.local/state/capd/staged}"
git_bin="${CAPD_GIT_BIN:-/usr/bin/git}"
plutil_bin="${CAPD_PLUTIL_BIN:-/usr/bin/plutil}"
security_bin="${CAPD_SECURITY_BIN:-/usr/bin/security}"
installed_app="${CAPD_APP_PATH:-/Applications/capd.app}"

# Avoid rebuilding and reinstalling an already-current app. Check the branch
# head first, then check the cloned commit again to cover a concurrent push.
remote_revision="$("$git_bin" ls-remote "$repository" "refs/heads/$branch" | awk 'NR == 1 { print $1 }')"
[[ "$remote_revision" =~ ^[0-9a-f]{40}$ ]] || {
    setup_error 'could not resolve EzraCerpac/capd main'; exit 1;
}
installed_revision=""
if [[ -f "$installed_app/Contents/Info.plist" ]]; then
    installed_revision="$("$plutil_bin" -extract CapdSourceRevision raw -o - "$installed_app/Contents/Info.plist" 2>/dev/null || true)"
fi
if (( stage_only == 0 )) && [[ "$installed_revision" == "$remote_revision" ]] &&
    capd_validate_source "$installed_app" "$remote_revision" &&
    capd_validate_app "$installed_app"; then
    printf 'Capd already matches EzraCerpac/capd main at %s; no rebuild or restart needed.\n' "$remote_revision"
    exit 0
fi

[[ -n "$capd_identity" ]] || {
    setup_error 'set CAPD_CODESIGN_IDENTITY or keep the signed current capd app available'; exit 1;
}
[[ "$("$security_bin" find-identity -v -p codesigning | grep -Fc "\"${capd_identity}\"")" == 1 ]] || {
    setup_error "signing identity missing or ambiguous: $capd_identity"; exit 1;
}

mkdir -p "$stage_root"
work_root="$(mktemp -d "${TMPDIR:-/tmp}/capd-update.XXXXXX")"
trap 'rm -rf -- "$work_root"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
source_dir="$work_root/source"
"$git_bin" clone --quiet --depth 1 --single-branch --branch "$branch" "$repository" "$source_dir"
[[ "$("$git_bin" -C "$source_dir" remote get-url origin)" == "$repository" ]] || {
    setup_error 'fetched Capd source is not EzraCerpac/capd'; exit 1;
}
revision="$("$git_bin" -C "$source_dir" rev-parse HEAD)"
[[ "$revision" =~ ^[0-9a-f]{40}$ ]] || { setup_error 'invalid fetched Capd revision'; exit 1; }
[[ "$("$git_bin" -C "$source_dir" branch --show-current)" == "$branch" ]] || {
    setup_error 'fetched Capd source is not main'; exit 1;
}
if (( stage_only == 0 )) && [[ "$installed_revision" == "$revision" ]] &&
    capd_validate_source "$installed_app" "$revision" &&
    capd_validate_app "$installed_app"; then
    printf 'Capd already matches the cloned EzraCerpac/capd main at %s; no rebuild or restart needed.\n' "$revision"
    exit 0
fi
require_file "$source_dir/Scripts/package-app.sh"

# The fork packaging script owns SwiftPM engine selection, locked dependency
# resolution, bundle assembly and source metadata. Skip its release-only DMG.
mise_exec env "CAPD_SOURCE_REVISION=$revision" CAPD_SKIP_DMG=1 \
    "CODESIGN_IDENTITY=$capd_identity" bash "$source_dir/Scripts/package-app.sh"
app="$source_dir/dist/capd.app"
/usr/bin/xattr -cr "$app"
capd_validate_source "$app" "$revision"
capd_validate_app "$app"
version="$("$plutil_bin" -extract CFBundleShortVersionString raw -o - "$app/Contents/Info.plist")"
stage="$stage_root/${version}-${revision}-$(date -u +%Y%m%dT%H%M%SZ)"
[[ ! -e "$stage" ]] || { setup_error "stage already exists: $stage"; exit 1; }
stage_tmp="$work_root/stage"
mkdir "$stage_tmp"
/usr/bin/ditto "$app" "$stage_tmp/capd.app"
/usr/bin/xattr -cr "$stage_tmp/capd.app"
printf 'repository=%s\nbranch=%s\nrevision=%s\nversion=%s\nsigning_identity=%s\n' \
    'https://github.com/EzraCerpac/capd' "$branch" "$revision" "$version" "$capd_identity" > "$stage_tmp/BUILD-INFO"
mv "$stage_tmp" "$stage"
if (( stage_only )); then
    printf 'Staged EzraCerpac/capd main at %s\nInstall explicitly: mise -C %s run local:capd-install -- %q\n' \
        "$revision" "$SETUP_ROOT" "$stage"
else
    printf 'Installing EzraCerpac/capd main at %s\n' "$revision"
    mise_exec bash "$SETUP_ROOT/setup-scripts/local/capd-install.sh" "$stage"
fi
