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
export KBD_KANATA_WRAPPER="${TMP_ROOT}/libexec/kanata-daemon"
export KBD_KANATA_PID_FILE="${TMP_ROOT}/run/kanata.pid"
export KBD_KANATA_NEWSYSLOG_CONFIG="${TMP_ROOT}/newsyslog.d/kanata.conf"
export KBD_KANATA_LOG="${TMP_ROOT}/log/kanata.log"
export KBD_KANATA_ERR_LOG="${TMP_ROOT}/log/kanata.err.log"
export KBD_KANATA_LEGACY_AGENT="${TMP_ROOT}/com.kanata.agent.plist"
export KBD_TCC_DB="${TMP_ROOT}/TCC.db"
export KBD_KANATA_STAT="${TMP_ROOT}/stat"
export KBD_KANATA_CONSOLE_DEVICE="${TMP_ROOT}/console"
export KBD_KANATA_LAUNCHCTL="${TMP_ROOT}/launchctl"
printf '#!/bin/sh\n[ "$1" = asuser ] || exit 2\nshift 2\nexec "$@"\n' >"${KBD_KANATA_LAUNCHCTL}"
chmod +x "${KBD_KANATA_LAUNCHCTL}"

TEST_UID="$(id -u)"
# Root containers have no interactive Mac user. Model one for the fixture;
# production still rejects root as the owner of a GUI keyboard session.
if [[ "$TEST_UID" == 0 ]]; then
    TEST_UID=1000
    id() {
        if [[ "$*" == -u ]]; then printf '%s\n' "$TEST_UID";
        else command id "$@"; fi
    }
fi
printf '%s\n' "$TEST_UID" >"${KBD_KANATA_CONSOLE_DEVICE}"
printf '#!/bin/sh\ncat "%s"\n' "${KBD_KANATA_CONSOLE_DEVICE}" >"${KBD_KANATA_STAT}"
chmod +x "${KBD_KANATA_STAT}"

# shellcheck source=../dotfiles/.local/bin/kbd
source "${ROOT}/dotfiles/.local/bin/kbd"

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

seed_kanata_runtime_files() {
    mkdir -p "$(dirname "${KBD_KANATA_WRAPPER}")" "$(dirname "${KBD_KANATA_NEWSYSLOG_CONFIG}")" "$(dirname "${KBD_KANATA_PLIST}")"
    render_kanata_wrapper "${KBD_KANATA_WRAPPER}" "$TEST_UID"
    render_kanata_newsyslog_config "${KBD_KANATA_NEWSYSLOG_CONFIG}"
    render_kanata_plist "${FAKE_KANATA}" "${KBD_KANATA_PLIST}"
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
    assert_contains "${output}" "Run: mise -C ~/.config/mise bootstrap"
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

test_render_runtime_files() {
    local wrapper="${TMP_ROOT}/rendered-wrapper"
    local plist="${TMP_ROOT}/rendered.plist"
    local newsyslog="${TMP_ROOT}/rendered-newsyslog.conf"
    local fake_command="${TMP_ROOT}/fake-command"
    local wrapper_status

    render_kanata_wrapper "${wrapper}" "$TEST_UID"
    render_kanata_plist "/tmp/a&b/kanata" "${plist}"
    render_kanata_newsyslog_config "${newsyslog}"

    assert_contains "$(<"${wrapper}")" "printf '%s\\n' \"\$\$\""
    assert_contains "$(<"${wrapper}")" "owner_uid=$TEST_UID"
    assert_contains "$(<"${wrapper}")" 'asuser "${owner_uid}"'
    assert_contains "$(<"${plist}")" "${KBD_KANATA_WRAPPER}"
    assert_contains "$(<"${plist}")" "/tmp/a&amp;b/kanata"
    assert_contains "$(<"${plist}")" "a&amp;b/config.kbd"
    assert_contains "$(<"${plist}")" "--cfg"
    assert_contains "$(<"${plist}")" "--release-grab-on-lock"
    assert_contains "$(<"${newsyslog}")" "${KBD_KANATA_LOG} root:wheel 644 3 10240 * J ${KBD_KANATA_PID_FILE} 15"

    mkdir -p "$(dirname "${KBD_KANATA_PID_FILE}")"
    printf '#!/bin/sh\nprintf "%%s\\n" "$$" >"%s"\nprintf "%%s\\n" "$@" >"%s"\n' "${TMP_ROOT}/exec.pid" "${TMP_ROOT}/exec.args" >"${fake_command}"
    chmod +x "${wrapper}" "${fake_command}"
    "${wrapper}" "${fake_command}" 'one two' three
    [[ -s "${KBD_KANATA_PID_FILE}" ]] || exit 1
    pass
    assert_contains "$(<"${TMP_ROOT}/exec.args")" $'one two\nthree'
    wrapper_status=0
    "${wrapper}" >/dev/null 2>&1 || wrapper_status=$?
    [[ "${wrapper_status}" == "64" ]] || exit 1
    pass
}

test_wrapper_runs_only_for_configured_console_user() {
    local wrapper="${TMP_ROOT}/user-gated-wrapper"
    local marker="${TMP_ROOT}/user-gated.marker"
    local pid

    render_kanata_wrapper "${wrapper}" "$TEST_UID"
    printf '#!/bin/sh\nprintf ok >"%s"\n' "${marker}" >"${TMP_ROOT}/marker-command"
    chmod +x "${wrapper}" "${TMP_ROOT}/marker-command"

    printf '%s\n' "$((TEST_UID + 1))" >"${KBD_KANATA_CONSOLE_DEVICE}"
    "${wrapper}" "${TMP_ROOT}/marker-command" &
    pid=$!
    sleep 0.3
    [[ ! -e "${marker}" ]] || exit 1

    printf '%s\n' "$TEST_UID" >"${KBD_KANATA_CONSOLE_DEVICE}"
    wait "${pid}"
    [[ -f "${marker}" ]] || exit 1
    pass
}

test_unchanged_unloaded_daemon_bootstraps() {
    local calls="${TMP_ROOT}/launchctl.calls"
    printf '#!/bin/sh\nexit 0\n' >"${FAKE_KANATA}"
    mkdir -p "$(dirname "${KBD_KANATA_CONFIG}")"
    printf '(defcfg)\n' >"${KBD_KANATA_CONFIG}"
    chmod +x "${FAKE_KANATA}"
    resolve_kanata_bin() { printf '%s\n' "${FAKE_KANATA}"; }
    seed_kanata_runtime_files
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
    assert_contains "$(<"${calls}")" "kickstart system/com.kanata.daemon"
}

test_changed_plist_reloads_daemon() {
    local calls="${TMP_ROOT}/changed.calls"
    seed_kanata_runtime_files
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
    seed_kanata_runtime_files
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
    seed_kanata_runtime_files
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
    assert_contains "$(<"${calls}")" "kickstart system/com.kanata.daemon"
}

test_missing_runtime_files_install_once() {
    local calls="${TMP_ROOT}/runtime-install.calls"
    rm -f "${KBD_KANATA_WRAPPER}" "${KBD_KANATA_NEWSYSLOG_CONFIG}" "${KBD_KANATA_PLIST}"
    sudo() {
        if [[ "$1" == "install" && "$2" == "-d" ]]; then
            mkdir -p "${@: -1}"
            return 0
        fi
        if [[ "$1" == "install" ]]; then
            mkdir -p "$(dirname "${@: -1}")"
            cp "${@: -2:1}" "${@: -1}"
            printf 'install %s\n' "${@: -1}" >>"${calls}"
            return 0
        fi
        if [[ "$1" == "launchctl" ]]; then
            shift
            printf '%s\n' "$*" >>"${calls}"
            if [[ "$1" == "print" ]] && ! grep -q '^bootstrap ' "${calls}"; then
                return 1
            fi
            return 0
        fi
        "$@"
    }

    cmd_provision_kanata "${FAKE_KANATA}"
    cmd_provision_kanata "${FAKE_KANATA}"

    [[ "$(grep -c "^install ${KBD_KANATA_WRAPPER}$" "${calls}")" == "1" ]] || exit 1
    pass
    [[ "$(grep -c "^install ${KBD_KANATA_NEWSYSLOG_CONFIG}$" "${calls}")" == "1" ]] || exit 1
    pass
    [[ "$(grep -c "^install ${KBD_KANATA_PLIST}$" "${calls}")" == "1" ]] || exit 1
    pass
}

test_large_log_rotates() {
    local calls="${TMP_ROOT}/rotation.calls"
    seed_kanata_runtime_files
    mkdir -p "$(dirname "${KBD_KANATA_LOG}")"
    mkdir -p "$(dirname "${KBD_KANATA_PID_FILE}")"
    truncate -s 10485760 "${KBD_KANATA_LOG}"
    printf '%s\n' "$$" >"${KBD_KANATA_PID_FILE}"
    sudo() {
        if [[ "$1" == "newsyslog" ]]; then
            printf '%s\n' "$*" >>"${calls}"
            return 0
        fi
        if [[ "$1" == "launchctl" ]]; then
            return 0
        fi
        if [[ "$1" == "kill" ]]; then
            shift
            kill "$@"
            return
        fi
        "$@"
    }

    cmd_provision_kanata "${FAKE_KANATA}"
    assert_contains "$(<"${calls}")" "newsyslog -f ${KBD_KANATA_NEWSYSLOG_CONFIG} ${KBD_KANATA_LOG}"
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
    assert_contains "${output}" "Run mise -C ~/.config/mise bootstrap"
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
test_render_runtime_files
test_wrapper_runs_only_for_configured_console_user
test_unchanged_unloaded_daemon_bootstraps
test_changed_plist_reloads_daemon
test_legacy_agent_is_removed
test_unchanged_loaded_daemon_skips_bootstrap
test_missing_runtime_files_install_once
test_large_log_rotates
test_stopped_daemon_fails
test_missing_config_fails
test_qmk_config_failure_propagates
test_provision_finishes_with_doctor
test_doctor_failure_propagates

echo "kbd provision tests passed: ${TESTS} assertions"
