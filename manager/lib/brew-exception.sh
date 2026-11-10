#!/usr/bin/env bash

# Print the executable path for a real macOS Homebrew installation. Check PATH
# first, then the two supported prefixes so first bootstrap does not depend on
# the caller having Homebrew's shell setup loaded yet.
source "$(dirname "${BASH_SOURCE[0]}")/dots-up-events.sh"

find_real_brew() {
    local path_brew candidate prefix
    path_brew="$(type -P brew 2>/dev/null || true)"

    for candidate in "$path_brew" /opt/homebrew/bin/brew /usr/local/bin/brew; do
        [[ -n "$candidate" && -x "$candidate" ]] || continue
        prefix="$("$candidate" --prefix 2>/dev/null)" || continue
        case "$prefix" in
            /opt/homebrew|/usr/local)
                printf '%s\n' "$candidate"
                return 0
                ;;
        esac
    done

    return 1
}

# Install or update one Homebrew cask from its own exception recipe; the
# reviewed recipe and manifest row are what allow a cask here.
#   update_brew_cask_exception [--auto-updates] [--admin] TOKEN [PROCESS] [--install-only]
# --auto-updates  the app updates itself; compare and upgrade with --greedy
# --admin         installing or upgrading needs administrator authorization
# PROCESS         defer while a process with this exact name is running
update_brew_cask_exception() {
    local auto_updates=0 requires_admin=0
    while (($#)); do
        case "$1" in
            --auto-updates) auto_updates=1; shift ;;
            --admin) requires_admin=1; shift ;;
            *) break ;;
        esac
    done
    local token="${1:?cask token required}" running_process="${2:-}" mode="${3:-}"
    local brew_bin outdated outdated_status=0
    if [[ "$(uname -s)" != Darwin ]]; then
        printf 'Deferred: %s is macOS-only.\n' "$token"
        return 0
    fi
    brew_bin="$(find_real_brew)" || { echo "A standard-prefix Homebrew installation is required for exception $token" >&2; return 1; }

    if ! "$brew_bin" list --cask "$token" >/dev/null 2>&1; then
        if [[ -n "$running_process" ]] && pgrep -x "$running_process" >/dev/null 2>&1; then
            printf 'Deferred: %s is running; close it before installing.\n' "$token"
            dots_up_emit_notice attention "$token installation was deferred because it is running." "Close $token and rerun dots up." "installer exception: $token"
            return 0
        fi
        if [[ "$requires_admin" -eq 1 ]] && ! brew_exception_admin_available; then
            brew_exception_defer_for_admin "$token"
            return 0
        fi
        HOMEBREW_NO_AUTOREMOVE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 "$brew_bin" install --cask "$token"
        return $?
    fi
    if [[ "$mode" == --install-only ]]; then
        printf 'Already installed: %s\n' "$token"
        return 0
    fi
    if [[ "$auto_updates" -eq 1 ]]; then
        outdated="$("$brew_bin" outdated --cask --greedy --quiet "$token")" || outdated_status=$?
    else
        outdated="$("$brew_bin" outdated --cask --quiet "$token")" || outdated_status=$?
    fi
    # Homebrew's cask outdated command returns 1 when it found outdated
    # casks. Accept that status only when it supplied the requested result;
    # empty output with status 1 and all other errors remain failures.
    if [[ "$outdated_status" -ne 0 ]] &&
        { [[ "$outdated_status" -ne 1 ]] || [[ -z "$outdated" ]]; }; then
        return "$outdated_status"
    fi
    if [[ -z "$outdated" ]]; then
        printf 'Unchanged: %s\n' "$token"
        return 0
    fi
    if [[ -n "$running_process" ]] && pgrep -x "$running_process" >/dev/null 2>&1; then
        printf 'Deferred: %s is running; close it before upgrading.\n' "$token"
        dots_up_emit_notice attention "$token upgrade was deferred because it is running." "Close $token and rerun dots up." "installer exception: $token"
        return 0
    fi
    if [[ "$requires_admin" -eq 1 ]] && ! brew_exception_admin_available; then
        brew_exception_defer_for_admin "$token"
        return 0
    fi
    if [[ "$auto_updates" -eq 1 ]]; then
        HOMEBREW_NO_AUTOREMOVE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 "$brew_bin" upgrade --cask --greedy "$token"
    else
        HOMEBREW_NO_AUTOREMOVE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 "$brew_bin" upgrade --cask "$token"
    fi
}

# Install or update one Homebrew formula from its own exception recipe. Keep
# the command scoped to one formula; never use a global Homebrew upgrade here.
#   update_brew_formula_exception TOKEN [--install-only]
update_brew_formula_exception() {
    local token="${1:?formula required}" mode="${2:-}"
    local brew_bin outdated outdated_status=0
    if [[ "$(uname -s)" != Darwin ]]; then
        printf 'Deferred: %s is macOS-only.\n' "$token"
        return 0
    fi
    brew_bin="$(find_real_brew)" || { echo "A standard-prefix Homebrew installation is required for exception $token" >&2; return 1; }

    if ! "$brew_bin" list --formula "$token" >/dev/null 2>&1; then
        HOMEBREW_NO_AUTOREMOVE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 \
            "$brew_bin" install --formula "$token"
        return $?
    fi
    if [[ "$mode" == --install-only ]]; then
        printf 'Already installed: %s\n' "$token"
        return 0
    fi

    outdated="$("$brew_bin" outdated --formula --quiet "$token")" || outdated_status=$?
    if [[ "$outdated_status" -ne 0 ]] &&
        { [[ "$outdated_status" -ne 1 ]] || [[ -z "$outdated" ]]; }; then
        return "$outdated_status"
    fi
    if [[ -z "$outdated" ]]; then
        printf 'Unchanged: %s\n' "$token"
        return 0
    fi
    HOMEBREW_NO_AUTOREMOVE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 \
        "$brew_bin" upgrade --formula "$token"
}

# Hold a package at a known-good version. Homebrew cannot express a portable
# cask hold, and mise's Brew updater otherwise replaces a formula with the
# current bottle. These helpers deliberately inspect and report; they never
# install or upgrade held software. Mark the manifest row hold=PACKAGE so
# `dots add` refuses to manage the same package.
#   hold_brew_formula_exception TOKEN VERSION [REASON]
hold_brew_formula_exception() {
    local token="${1:?formula required}" held_version="${2:?held version required}" reason="${3:-held version}"
    local brew_bin installed_version
    if [[ "$(uname -s)" != Darwin ]]; then
        printf 'Deferred: %s is macOS-only.\n' "$token"
        return 0
    fi
    brew_bin="$(find_real_brew)" || {
        printf 'A standard-prefix Homebrew installation is required to inspect held formula %s\n' "$token" >&2
        return 1
    }
    installed_version="$("$brew_bin" list --versions "$token" 2>/dev/null | awk 'NF { print $NF }')"
    if [[ -z "$installed_version" ]]; then
        printf 'Manual action required: install %s %s (%s); refusing an unpinned Homebrew install.\n' "$token" "$held_version" "$reason" >&2
        return 1
    fi
    if [[ "$installed_version" != "$held_version" ]]; then
        printf 'Held: %s is %s, but this setup requires %s; refusing to change it.\n' "$token" "$installed_version" "$held_version" >&2
        return 1
    fi
    printf 'Held: %s %s (%s).\n' "$token" "$held_version" "$reason"
}

#   hold_brew_cask_exception TOKEN VERSION APP_PATH [REASON]
hold_brew_cask_exception() {
    local token="${1:?cask token required}" held_version="${2:?held version required}" app_path="${3:?app path required}" reason="${4:-held version}"
    local version_plist installed_version
    if [[ "$(uname -s)" != Darwin ]]; then
        printf 'Deferred: %s is macOS-only.\n' "$token"
        return 0
    fi
    version_plist="$app_path/Contents/Info.plist"
    if [[ ! -f "$version_plist" ]]; then
        printf 'Manual action required: install %s %s (%s); refusing the current Homebrew cask.\n' "$token" "$held_version" "$reason" >&2
        return 1
    fi
    installed_version="$("${BREW_EXCEPTION_PLISTBUDDY:-/usr/libexec/PlistBuddy}" -c 'Print :CFBundleShortVersionString' "$version_plist" 2>/dev/null || true)"
    if [[ "$installed_version" != "$held_version" ]]; then
        printf 'Held: %s is %s, but this setup requires %s; refusing to change it.\n' "$token" "${installed_version:-unknown}" "$held_version" >&2
        return 1
    fi
    printf 'Held: %s %s (%s).\n' "$token" "$held_version" "$reason"
}

brew_exception_admin_available() {
    if [[ "$(id -u)" == 0 ]] || { [[ -t 0 ]] && [[ -t 1 ]]; }; then
        return 0
    fi
    command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1
}

brew_exception_defer_for_admin() {
    printf 'Deferred: %s needs interactive administrator authorization; run in a terminal: sudo -v && dots up\n' "$1"
    dots_up_emit_notice attention "$1 was deferred because interactive administrator authorization is unavailable." "Run sudo -v, then rerun dots up." "installer exception: $1"
}
