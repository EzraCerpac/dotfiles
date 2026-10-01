#!/usr/bin/env bash
set -euo pipefail
umask 077
# shellcheck source=setup-scripts/local/capd-common.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/capd-common.sh"

source_dir="${CAPD_SOURCE_DIR:-${HOME}/Projects/capd}"
stage_root="${CAPD_STAGE_ROOT:-${HOME}/.local/state/capd/staged}"
[[ $# -eq 0 ]] || { setup_error 'usage: local:capd-build'; exit 2; }
require_file "$source_dir/Scripts/package-app.sh"
[[ -z "$(mise_exec git -C "$source_dir" status --porcelain=v1 --untracked-files=all)" ]] || {
    setup_error 'commit or reconcile capd source changes before building'; exit 1;
}
revision="$(mise_exec git -C "$source_dir" rev-parse HEAD)"
[[ "$revision" =~ ^[0-9a-f]{40}$ ]] || exit 1
[[ "$(/usr/bin/security find-identity -v -p codesigning | grep -Fc "\"${capd_identity}\"")" == 1 ]] || {
    setup_error "signing identity missing or ambiguous: $capd_identity"; exit 1;
}
mkdir -p "$stage_root"
build_root="$(mktemp -d "$stage_root/.build.XXXXXX")"
trap 'rm -rf -- "$build_root"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir "$build_root/source"
mise_exec git -C "$source_dir" archive HEAD | tar -xf - -C "$build_root/source"
# Xcode 27's Swift build system uses .build/out rather than .build/apple.
# Adapt only this disposable script and let Swift report the product directory.
package_script="$build_root/source/Scripts/package-app.sh"
[[ "$(grep -Fxc 'BIN=.build/apple/Products/Release' "$package_script")" == 1 ]] || {
    setup_error 'upstream package script changed; inspect its product path before building'; exit 1;
}
# shellcheck disable=SC2016
[[ "$(grep -Fxc '    lipo "$binary" -verify_arch arm64 x86_64 || {' "$package_script")" == 1 ]] || {
    setup_error 'upstream package script changed; inspect its architecture check before building'; exit 1;
}
# shellcheck disable=SC2016
sed -e 's|^BIN=.build/apple/Products/Release$|BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)|' \
    -e 's/    lipo "\$binary" -verify_arch arm64 x86_64 || {/    lipo "$binary" -verify_arch arm64 \&\& lipo "$binary" -verify_arch x86_64 || {/' \
    "$package_script" > "$package_script.adapted"
mv "$package_script.adapted" "$package_script"
# package-app.sh clears dist, so run it in this task-owned source copy.
# mise_exec selects the setup checkout; the package script selects its own root.
mise_exec env "CODESIGN_IDENTITY=$capd_identity" bash "$package_script"
app="$build_root/source/dist/capd.app"
capd_validate_app "$app"
version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$app/Contents/Info.plist")"
stage="$stage_root/${version}-${revision}-$(date -u +%Y%m%dT%H%M%SZ)"
[[ ! -e "$stage" ]] || { setup_error "stage already exists: $stage"; exit 1; }
mkdir "$build_root/stage"
/usr/bin/ditto "$app" "$build_root/stage/capd.app"
printf 'revision=%s\nversion=%s\nsigning_identity=%s\n' "$revision" "$version" "$capd_identity" > "$build_root/stage/BUILD-INFO"
mv "$build_root/stage" "$stage"
printf 'Staged capd at %s\nInstall explicitly: mise -C %s run local:capd-install -- %q\n' "$stage" "$SETUP_ROOT" "$stage"
