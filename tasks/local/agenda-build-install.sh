#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=tasks/local/common
source "${SCRIPT_DIR}/common"

require_setup_profile workstation
require_macos

SOURCE_DIR="${HOME}/Projects/Tools/swift-agenda"
INSTALL_PARENT="${HOME}/.local/libexec"
INSTALL_DIR="${INSTALL_PARENT}/agenda"

for path in \
    "${SOURCE_DIR}/Package.swift" \
    "${SOURCE_DIR}/Package.resolved" \
    "${SOURCE_DIR}/Sources/agenda/Info.plist" \
    "${SOURCE_DIR}/Sources" \
    "${SOURCE_DIR}/Tests"; do
    if [[ ! -e "${path}" ]]; then
        setup_error "required agenda source path not found: ${path}"
        exit 1
    fi
done

for command_name in swift strip codesign lipo otool strings; do
    command -v "${command_name}" >/dev/null 2>&1 || {
        setup_error "Xcode Command Line Tools are required (${command_name} not found)"
        exit 1
    }
done
[[ -x /usr/libexec/PlistBuddy ]] || { setup_error "PlistBuddy is required"; exit 1; }

if [[ -L "${INSTALL_DIR}" ]]; then
    setup_error "refusing to replace symlinked libexec path: ${INSTALL_DIR}"
    exit 1
fi
if [[ -e "${INSTALL_DIR}" && ! -d "${INSTALL_DIR}" ]]; then
    setup_error "refusing to replace non-directory libexec path: ${INSTALL_DIR}"
    exit 1
fi

mkdir -p "${INSTALL_PARENT}"
transaction_dir=""
previous_dir=""
had_previous=0
swap_started=0

cleanup() {
    local status=$?
    local restore_failed=0
    trap - EXIT INT TERM

    if [[ -n "${transaction_dir}" && -d "${transaction_dir}" ]]; then
        if (( status != 0 && swap_started )); then
            if (( had_previous )); then
                if [[ -d "${previous_dir}" ]]; then
                    if [[ -e "${INSTALL_DIR}" || -L "${INSTALL_DIR}" ]]; then
                        mv "${INSTALL_DIR}" "${transaction_dir}/failed-install" || restore_failed=1
                    fi
                    if (( restore_failed == 0 )); then
                        mv "${previous_dir}" "${INSTALL_DIR}" || restore_failed=1
                    fi
                elif [[ ! -e "${INSTALL_DIR}" && ! -L "${INSTALL_DIR}" ]]; then
                    restore_failed=1
                fi
            elif [[ -e "${INSTALL_DIR}" || -L "${INSTALL_DIR}" ]]; then
                mv "${INSTALL_DIR}" "${transaction_dir}/failed-install" || restore_failed=1
            fi
        fi

        if (( restore_failed )); then
            setup_error "install failed; recovery files remain at ${transaction_dir}"
        elif ! rm -rf "${transaction_dir}"; then
            setup_error "install finished, but temporary files remain at ${transaction_dir}"
        fi
    fi

    exit "${status}"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

transaction_dir="$(mktemp -d "${INSTALL_PARENT}/.agenda-install.XXXXXX")"
previous_dir="${transaction_dir}/previous"
source_copy="${transaction_dir}/source"
scratch_dir="${transaction_dir}/scratch"
staged_install="${transaction_dir}/package"
mkdir -p "${source_copy}" "${staged_install}"

# Build a small source snapshot outside the checkout. This avoids the release
# script's `rm -rf dist` and keeps SwiftPM scratch files out of the source tree.
cp -R \
    "${SOURCE_DIR}/Package.swift" \
    "${SOURCE_DIR}/Package.resolved" \
    "${SOURCE_DIR}/Sources" \
    "${SOURCE_DIR}/Tests" \
    "${source_copy}/"

mise_exec env "SWIFT_MODULECACHE_PATH=${transaction_dir}/module-cache" swift build \
    --package-path "${source_copy}" \
    --scratch-path "${scratch_dir}" \
    --skip-update \
    --arch arm64 \
    --configuration release

build_dir="$(mise_exec swift build \
    --package-path "${source_copy}" \
    --scratch-path "${scratch_dir}" \
    --skip-update \
    --arch arm64 \
    --configuration release \
    --show-bin-path)"
build_binary="${build_dir}/agenda"
if [[ ! -x "${build_binary}" ]]; then
    setup_error "Swift build did not produce ${build_binary}"
    exit 1
fi

cp "${build_binary}" "${staged_install}/agenda"
chmod 0755 "${staged_install}/agenda"
shopt -s nullglob
resource_bundles=("${build_dir}"/*.bundle)
for bundle in "${resource_bundles[@]}"; do
    cp -R "${bundle}" "${staged_install}/"
done

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${source_copy}/Sources/agenda/Info.plist")"
expected_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${source_copy}/Sources/agenda/Info.plist")"
if [[ "${bundle_id}" != "com.arraypress.agenda" ]]; then
    setup_error "agenda bundle identity changed (${bundle_id}); review before replacing the installed app identity"
    exit 1
fi
[[ -n "${expected_version}" ]] || { setup_error "agenda version is missing from Info.plist"; exit 1; }

# Match the source release build: strip only the staged copy, then ad-hoc sign
# with the stable bundle ID already embedded by Package.swift.
strip -rSTx "${staged_install}/agenda"
codesign --force --sign - --identifier "${bundle_id}" "${staged_install}/agenda"
codesign --verify --strict "${staged_install}/agenda"

archs="$(lipo -archs "${staged_install}/agenda")"
[[ "${archs}" == "arm64" ]] || { setup_error "expected arm64 agenda binary, got: ${archs}"; exit 1; }

load_commands="${transaction_dir}/load-commands.txt"
otool -l "${staged_install}/agenda" >"${load_commands}"
if ! grep -Fq -- 'sectname __info_plist' "${load_commands}"; then
    setup_error "agenda binary is missing its embedded permission Info.plist"
    exit 1
fi

binary_strings="${transaction_dir}/binary-strings.txt"
strings "${staged_install}/agenda" >"${binary_strings}"
for marker in \
    "${bundle_id}" \
    NSCalendarsFullAccessUsageDescription \
    NSRemindersFullAccessUsageDescription; do
    if ! grep -Fq -- "${marker}" "${binary_strings}"; then
        setup_error "agenda binary is missing embedded permission metadata: ${marker}"
        exit 1
    fi
done

signature="$(codesign -dv --verbose=4 "${staged_install}/agenda" 2>&1)"
for identity in "Identifier=${bundle_id}" 'Signature=adhoc' 'TeamIdentifier=not set'; do
    if ! grep -Fq -- "${identity}" <<<"${signature}"; then
        setup_error "unexpected agenda code identity: expected ${identity}"
        exit 1
    fi
done

reported_version="$("${staged_install}/agenda" --version)"
[[ "${reported_version}" == "${expected_version}" ]] || {
    setup_error "agenda version mismatch: Info.plist says ${expected_version}, binary says ${reported_version}"
    exit 1
}
"${staged_install}/agenda" --help >/dev/null
"${staged_install}/agenda" describe --json >/dev/null

if [[ -L "${INSTALL_DIR}" ]]; then
    setup_error "refusing to replace symlinked libexec path: ${INSTALL_DIR}"
    exit 1
fi
if [[ -e "${INSTALL_DIR}" && ! -d "${INSTALL_DIR}" ]]; then
    setup_error "refusing to replace non-directory libexec path: ${INSTALL_DIR}"
    exit 1
fi

swap_started=1
if [[ -e "${INSTALL_DIR}" ]]; then
    had_previous=1
    mv "${INSTALL_DIR}" "${previous_dir}"
fi
mv "${staged_install}" "${INSTALL_DIR}"

printf 'Installed agenda %s (%s, ad-hoc) at %s\n' "${reported_version}" "${archs}" "${INSTALL_DIR}/agenda"
