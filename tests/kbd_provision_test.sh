#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMP_ROOT}"' EXIT

export HOME="${TMP_ROOT}/home"
export KBD_KARABINER_MANAGER="${TMP_ROOT}/Karabiner Manager"
export KBD_KARABINER_DAEMON="${TMP_ROOT}/Karabiner Daemon"
export KBD_KARABINER_LEGACY_PLIST="${TMP_ROOT}/legacy-virtualhid.plist"
export KBD_KARABINER_CORE_LEGACY_PLIST="${TMP_ROOT}/legacy-core.plist"
export KBD_KANATA_CONFIG="${TMP_ROOT}/a&b/config.kbd"
export KBD_KANATA_PLIST="${TMP_ROOT}/com.kanata.daemon.plist"
export KBD_KANATA_LEGACY_AGENT="${TMP_ROOT}/com.kanata.agent.plist"
export KBD_TCC_DB="${TMP_ROOT}/TCC.db"

# shellcheck source=../dot_local/bin/executable_kbd
source "${ROOT}/dot_local/bin/executable_kbd"

TESTS=0
FAKE_KANATA="${TMP_ROOT}/kanata"

pass() {
    TESTS=$((TESTS + 1))
}

assert_contains() {
    local haystack="${1:?text required}"
    local needle="${2:?expected text required}"
    [[ "${haystack}" == *"${needle}"* ]] || {
        echo "expected output to contain: ${needle}" >&2
        echo "actual: ${haystack}" >&2
        exit 1
    }
    pass
}

assert_not_contains() {
    local haystack="${1:?text required}"
    local needle="${2:?unexpected text required}"
    [[ "${haystack}" != *"${needle}"* ]] || {
        echo "expected output not to contain: ${needle}" >&2
        exit 1
    }
    pass
}

test_missing_prerequisite() {
    local output
    command() {
        if [[ "$1" == "-v" && "$2" == "kanata" ]]; then
            return 1
        fi
        builtin command "$@"
    }

    output="$(cmd_provision_prerequisites 2>&1 || true)"
    assert_contains "${output}" "missing keyboard prerequisite: kanata"
    assert_contains "${output}" "Run: chezmoi apply"
    unset -f command
}

test_missing_virtualhid() {
    local output
    output="$(cmd_provision_virtualhid 2>&1 || true)"
    assert_contains "${output}" "Karabiner VirtualHID components are missing"
}

test_driverkit_gate() {
    local output
    mkdir -p "$(dirname "${KBD_KARABINER_MANAGER}")"
    printf '#!/bin/sh\nexit 0\n' >"${KBD_KARABINER_MANAGER}"
    printf '#!/bin/sh\nexit 0\n' >"${KBD_KARABINER_DAEMON}"
    chmod +x "${KBD_KARABINER_MANAGER}" "${KBD_KARABINER_DAEMON}"
    driverkit_is_active() { return 1; }
    sudo() { "$@"; }

    output="$(cmd_provision_virtualhid 2>&1 || true)"
    assert_contains "${output}" "Approve Karabiner DriverKit"
}

test_tcc_gate() {
    local output
    local fake_kanata="${TMP_ROOT}/kanata"
    printf '#!/bin/sh\nexit 0\n' >"${fake_kanata}"
    chmod +x "${fake_kanata}"
    sudo() {
        if [[ "$1" == "sqlite3" ]]; then
            printf 'kTCCServiceListenEvent|%s|2\n' "$(realpath "${fake_kanata}")"
            return 0
        fi
        "$@"
    }

    output="$(provision_check_kanata_tcc "${fake_kanata}" 2>&1 || true)"
    assert_contains "${output}" "Privacy & Security > Accessibility"
}

test_render_escapes_xml() {
    local output="${TMP_ROOT}/kanata.plist"
    render_kanata_plist "/tmp/a&b/kanata" "${output}"
    assert_contains "$(<"${output}")" "/tmp/a&amp;b/kanata"
    assert_contains "$(<"${output}")" "a&amp;b/config.kbd"
}

test_unchanged_unloaded_daemon_bootstraps() {
    local calls="${TMP_ROOT}/launchctl.calls"
    printf '#!/bin/sh\nexit 0\n' >"${FAKE_KANATA}"
    mkdir -p "$(dirname "${KBD_KANATA_CONFIG}")"
    printf '(defcfg)\n' >"${KBD_KANATA_CONFIG}"
    chmod +x "${FAKE_KANATA}"
    resolve_kanata_bin() { printf '%s\n' "${FAKE_KANATA}"; }
    render_kanata_plist "${FAKE_KANATA}" "${KBD_KANATA_PLIST}"
    sudo() {
        if [[ "$1" == "launchctl" ]]; then
            shift
            printf '%s\n' "$*" >>"${calls}"
            [[ "$1" != "print" ]]
            return
        fi
        "$@"
    }

    cmd_provision_kanata "${FAKE_KANATA}"
    assert_contains "$(<"${calls}")" "bootstrap system ${KBD_KANATA_PLIST}"
    assert_contains "$(<"${calls}")" "kickstart -k system/com.kanata.daemon"
}

test_changed_plist_reloads_daemon() {
    local calls="${TMP_ROOT}/changed.calls"
    printf 'stale\n' >"${KBD_KANATA_PLIST}"
    sudo() {
        if [[ "$1" == "install" ]]; then
            cp "${@: -2:1}" "${@: -1}"
            printf 'install\n' >>"${calls}"
            return 0
        fi
        if [[ "$1" == "launchctl" ]]; then
            shift
            printf '%s\n' "$*" >>"${calls}"
            if [[ "$1" == "print" ]] && grep -q '^bootout ' "${calls}"; then
                return 1
            fi
            return 0
        fi
        "$@"
    }

    cmd_provision_kanata "${FAKE_KANATA}"
    assert_contains "$(<"${calls}")" "install"
    assert_contains "$(<"${calls}")" "bootout system/com.kanata.daemon"
    assert_contains "$(<"${calls}")" "bootstrap system ${KBD_KANATA_PLIST}"
}

test_legacy_agent_is_removed() {
    local calls="${TMP_ROOT}/legacy-agent.calls"
    mkdir -p "$(dirname "${KBD_KANATA_LEGACY_AGENT}")"
    printf 'legacy\n' >"${KBD_KANATA_LEGACY_AGENT}"
    render_kanata_plist "${FAKE_KANATA}" "${KBD_KANATA_PLIST}"
    launchctl() {
        printf '%s\n' "$*" >>"${calls}"
        return 0
    }
    sudo() { return 0; }

    cmd_provision_kanata "${FAKE_KANATA}"
    [[ ! -e "${KBD_KANATA_LEGACY_AGENT}" ]] || exit 1
    pass
    assert_contains "$(<"${calls}")" "bootout gui/$(id -u) ${KBD_KANATA_LEGACY_AGENT}"
}

test_unchanged_loaded_daemon_skips_bootstrap() {
    local calls="${TMP_ROOT}/loaded.calls"
    render_kanata_plist "${FAKE_KANATA}" "${KBD_KANATA_PLIST}"
    sudo() {
        if [[ "$1" == "launchctl" ]]; then
            shift
            printf '%s\n' "$*" >>"${calls}"
            return 0
        fi
        "$@"
    }

    cmd_provision_kanata "${FAKE_KANATA}"
    assert_not_contains "$(<"${calls}")" "bootstrap"
    assert_contains "$(<"${calls}")" "kickstart -k system/com.kanata.daemon"
}

test_stopped_daemon_fails() {
    local output
    sudo() {
        if [[ "$1" == "launchctl" && "$2" == "kickstart" ]]; then
            return 1
        fi
        return 0
    }

    output="$(cmd_provision_kanata "${FAKE_KANATA}" 2>&1 || true)"
    assert_contains "${output}" "Kanata daemon did not start"
}

test_missing_config_fails() {
    local output
    rm -f "${KBD_KANATA_CONFIG}"
    output="$(cmd_provision_kanata "${FAKE_KANATA}" 2>&1 || true)"
    assert_contains "${output}" "Kanata config is missing"
}

test_qmk_config_failure_propagates() {
    local output
    git() { return 0; }
    run_qmk() { return 1; }

    if output="$(configure_qmk_checkout 2>&1)"; then
        echo "expected QMK config failure to propagate" >&2
        exit 1
    fi
    pass
    assert_contains "${output}" "QMK config failed"
    assert_contains "${output}" "Run chezmoi apply"
}

test_provision_finishes_with_doctor() {
    local calls="${TMP_ROOT}/provision.calls"
    uname() { printf 'Darwin\n'; }
    cmd_provision_prerequisites() { printf 'prerequisites\n' >>"${calls}"; }
    cmd_provision_qmk() { printf 'qmk\n' >>"${calls}"; }
    sudo() { return 0; }
    cmd_provision_runtime() { printf 'runtime\n' >>"${calls}"; }
    cmd_doctor() { printf 'doctor\n' >>"${calls}"; }

    cmd_provision >/dev/null
    cmd_provision >/dev/null
    [[ "$(grep -c '^doctor$' "${calls}")" == "2" ]] || {
        echo "expected healthy rerun to finish doctor twice" >&2
        exit 1
    }
    pass
    assert_contains "$(<"${calls}")" $'prerequisites\nqmk\nruntime\ndoctor\nprerequisites\nqmk\nruntime\ndoctor'
}

test_doctor_failure_propagates() {
    local output
    cmd_provision_prerequisites() { return 0; }
    cmd_provision_qmk() { return 0; }
    cmd_provision_runtime() { return 0; }
    cmd_doctor() { return 1; }
    output="$(cmd_provision 2>&1 || true)"
    assert_contains "${output}" "keyboard provisioning complete"
    if cmd_provision >/dev/null 2>&1; then
        echo "expected doctor failure to fail provision" >&2
        exit 1
    fi
    pass
}

test_missing_prerequisite
test_missing_virtualhid
test_driverkit_gate
test_tcc_gate
test_render_escapes_xml
test_unchanged_unloaded_daemon_bootstraps
test_changed_plist_reloads_daemon
test_legacy_agent_is_removed
test_unchanged_loaded_daemon_skips_bootstrap
test_stopped_daemon_fails
test_missing_config_fails
test_qmk_config_failure_propagates
test_provision_finishes_with_doctor
test_doctor_failure_propagates

echo "kbd provision tests passed: ${TESTS} assertions"
