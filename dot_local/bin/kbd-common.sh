#!/usr/bin/env bash

if [[ -n "${KBD_COMMON_SH_LOADED:-}" ]]; then
    return 0
fi
readonly KBD_COMMON_SH_LOADED=1

QMK_RUNNER=()
QMK_RUNNER_MODE=""
QMK_RUNNER_WORKDIR=""

resolve_kbd_script() {
    local script_name="${1:?script name required}"
    local script_dir="${2:?script dir required}"

    if [[ -x "${script_dir}/${script_name}" ]]; then
        printf '%s\n' "${script_dir}/${script_name}"
        return 0
    fi

    if [[ -x "${script_dir}/executable_${script_name}" ]]; then
        printf '%s\n' "${script_dir}/executable_${script_name}"
        return 0
    fi

    if command -v "${script_name}" >/dev/null 2>&1; then
        command -v "${script_name}"
        return 0
    fi

    echo "missing helper script: ${script_name}" >&2
    return 1
}

resolve_qmk_runner() {
    if [[ -n "${QMK_RUNNER_MODE}" ]]; then
        return 0
    fi

    local qmk_home="${QMK_HOME:-${HOME}/Projects/keyboards/qmk_firmware}"
    local candidate=""
    local lib_root=""
    local py_name=""
    local prefix=""
    local python_bin=""
    local -a site_packages=(
        /opt/homebrew/Cellar/qmk/*/libexec/lib/python*/site-packages
        /usr/local/Cellar/qmk/*/libexec/lib/python*/site-packages
    )

    if [[ -d "${qmk_home}/lib/python/qmk/cli" ]]; then
        for candidate in "${site_packages[@]}"; do
            [[ -d "${candidate}" ]] || continue

            lib_root="${candidate%/site-packages}"
            py_name="$(basename "${lib_root}")"
            prefix="${lib_root%/lib/*}"
            python_bin="${prefix}/bin/${py_name}"

            if [[ -x "${python_bin}" ]] && (
                cd "${qmk_home}" &&
                env ORIG_CWD="${qmk_home}" \
                    PYTHONPATH="${qmk_home}/lib/python:${candidate}${PYTHONPATH:+:${PYTHONPATH}}" \
                    "${python_bin}" -c 'import sys; from qmk.cli import cli; sys.argv[0] = "qmk"; cli()' --help >/dev/null 2>&1
            ); then
                QMK_RUNNER_MODE="local_qmk_home"
                QMK_RUNNER_WORKDIR="${qmk_home}"
                QMK_RUNNER=(
                    env
                    "ORIG_CWD=${qmk_home}"
                    "PYTHONPATH=${qmk_home}/lib/python:${candidate}${PYTHONPATH:+:${PYTHONPATH}}"
                    "${python_bin}"
                    -c
                    'import sys; from qmk.cli import cli; sys.argv[0] = "qmk"; cli()'
                )
                return 0
            fi
        done
    fi

    if command -v qmk >/dev/null 2>&1 && qmk --version >/dev/null 2>&1; then
        QMK_RUNNER_MODE="system_qmk"
        QMK_RUNNER=(qmk)
        return 0
    fi

    for candidate in "${site_packages[@]}"; do
        if [[ -d "${candidate}/qmk_cli" ]] && python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); from qmk_cli.script_qmk import main' "${candidate}" >/dev/null 2>&1; then
            QMK_RUNNER_MODE="wrapper_qmk"
            QMK_RUNNER=(env "PYTHONPATH=${candidate}${PYTHONPATH:+:${PYTHONPATH}}" python3 -m qmk_cli.script_qmk)
            return 0
        fi
    done

    echo "qmk CLI is unavailable. Re-run kbd-setup or repair the Homebrew qmk install." >&2
    return 1
}

run_qmk() {
    resolve_qmk_runner
    if [[ "${QMK_RUNNER_MODE}" == "local_qmk_home" ]]; then
        (
            cd "${QMK_RUNNER_WORKDIR}"
            "${QMK_RUNNER[@]}" "$@"
        )
        return
    fi

    "${QMK_RUNNER[@]}" "$@"
}
