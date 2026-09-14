#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=tasks/local/common
source "${SCRIPT_DIR}/common"

require_setup_profile workstation
require_macos

SOURCE_DIR="${HOME}/Projects/Tools/remctl"
INSTALL_PARENT="${HOME}/.local/libexec"
INSTALL_DIR="${INSTALL_PARENT}/remctl"

require_file "${SOURCE_DIR}/install.sh"
require_file "${SOURCE_DIR}/remctl"
command -v swiftc >/dev/null 2>&1 || { setup_error "Xcode Command Line Tools (swiftc) are required"; exit 1; }
command -v codesign >/dev/null 2>&1 || { setup_error "codesign is required"; exit 1; }

if [[ -L "${INSTALL_DIR}" ]]; then
    setup_error "refusing to replace symlinked libexec path: ${INSTALL_DIR}"
    exit 1
fi
if [[ -e "${INSTALL_DIR}" && ! -d "${INSTALL_DIR}" ]]; then
    setup_error "refusing to replace non-directory libexec path: ${INSTALL_DIR}"
    exit 1
fi

setup_mise exec python@3.13 -- python3 --version >/dev/null

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

transaction_dir="$(mktemp -d "${INSTALL_PARENT}/.remctl-install.XXXXXX")"
previous_dir="${transaction_dir}/previous"
staged_bin="${transaction_dir}/bin"
mkdir -p "${staged_bin}"

# The upstream installer writes its config and completions under its configured
# directories. Keep both inside staging and make its bin path visible to suppress
# its PATH hint; never touch the managed ~/.local/bin wrapper.
(
    export REMCTL_BIN_DIR="${staged_bin}"
    export REMCTL_CONFIG_DIR="${transaction_dir}/config"
    export PATH="${staged_bin}:${PATH}"
    setup_mise exec python@3.13 -- bash "${SOURCE_DIR}/install.sh" --shell-completions none
)

for executable in remctl remctl-bridge remctl-permissions; do
    if [[ ! -x "${staged_bin}/${executable}" ]]; then
        setup_error "RemCTL source installer did not build ${executable}"
        exit 1
    fi
done

if [[ -x "${INSTALL_DIR}/remctl-private" && ! -x "${staged_bin}/remctl-private" ]]; then
    setup_error "RemCTL source installer did not preserve the installed private helper"
    exit 1
fi

version="$(setup_mise exec python@3.13 -- python3 "${staged_bin}/remctl" --version)"
[[ -n "${version}" ]] || { setup_error "RemCTL did not report a version"; exit 1; }

verify_helper_identity() {
    local name="$1"
    local path="${staged_bin}/${name}"
    local details
    local identity

    codesign --verify --strict "${path}"
    details="$(codesign -dv --verbose=4 "${path}" 2>&1)"
    for identity in "Identifier=${name}" "Signature=adhoc" "TeamIdentifier=not set"; do
        if ! grep -Fq -- "${identity}" <<<"${details}"; then
            setup_error "unexpected code identity for ${path}: expected ${identity}"
            return 1
        fi
    done
}

for helper in remctl-bridge remctl-permissions; do
    verify_helper_identity "${helper}"
done
if [[ -x "${staged_bin}/remctl-private" ]]; then
    verify_helper_identity remctl-private
fi

if [[ -f "${SOURCE_DIR}/assets/remctl-permissions-icon.png" && ! -f "${staged_bin}/remctl-permissions-icon.png" ]]; then
    setup_error "RemCTL permissions icon was not staged"
    exit 1
fi

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
mv "${staged_bin}" "${INSTALL_DIR}"

printf 'Installed RemCTL %s at %s\n' "${version}" "${INSTALL_DIR}/remctl"
