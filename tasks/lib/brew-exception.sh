#!/usr/bin/env bash

# Print the executable path for a real macOS Homebrew installation. Check PATH
# first, then the two supported prefixes so first bootstrap does not depend on
# the caller having Homebrew's shell setup loaded yet.
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

# Only named unsupported casks may call this updater.
update_brew_cask_exception() {
    local token="$1" running_process="${2:-}" mode="${3:-}"
    local brew_bin auto_updates=0 requires_admin=0 outdated outdated_status=0
    if [[ "$(uname -s)" != Darwin ]]; then
        printf 'Deferred: %s is macOS-only.\n' "$token"
        return 0
    fi
    case "$token" in
        brooklyn) ;;
        antinote|omnidisksweeper) auto_updates=1 ;;
        mactex-no-gui) requires_admin=1 ;;
        zoom|karabiner-elements|tailscale-app) auto_updates=1; requires_admin=1 ;;
        font-sf-pro) auto_updates=1; requires_admin=1 ;;
        *) printf 'Refusing unlisted Homebrew cask exception: %s\n' "$token" >&2; return 2 ;;
    esac
    brew_bin="$(find_real_brew)" || { echo "A standard-prefix Homebrew installation is required for exception $token" >&2; return 1; }

    if ! "$brew_bin" list --cask "$token" >/dev/null 2>&1; then
        if [[ -n "$running_process" ]] && pgrep -x "$running_process" >/dev/null 2>&1; then
            printf 'Deferred: %s is running; close it before installing.\n' "$token"
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

# Only named unsupported formulas may call this updater. Keep the command
# scoped to one formula; never use a global Homebrew upgrade here.
update_brew_formula_exception() {
    local token="$1" mode="${2:-}"
    local brew_bin outdated outdated_status=0
    if [[ "$(uname -s)" != Darwin ]]; then
        printf 'Deferred: %s is macOS-only.\n' "$token"
        return 0
    fi
    case "$token" in
        antoniorodr/memo/memo|qmk/qmk/qmk|steipete/tap/peekaboo|osx-cross/arm/arm-none-eabi-binutils|osx-cross/arm/arm-none-eabi-gcc@9|osx-cross/avr/avr-gcc@9) ;;
        felixkratz/formulae/borders|modem-dev/tap/hunk|dastrobu/tap/mail-mcp|ezracerpac/tap/typst-time-machine) ;;
        *) printf 'Refusing unlisted Homebrew formula exception: %s\n' "$token" >&2; return 2 ;;
    esac
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

# Kanata and Karabiner are held at the versions known to work with the current
# input setup. Homebrew cannot express a portable cask hold, and mise's Brew
# updater otherwise replaces a formula with the current bottle. These helpers
# deliberately inspect and report; they never upgrade held keyboard software.
hold_brew_formula_exception() {
    local token="$1" held_version="$2"
    local brew_bin installed_version
    if [[ "$token" != kanata ]]; then
        printf 'Refusing unlisted held Homebrew formula: %s\n' "$token" >&2
        return 2
    fi
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
        printf 'Manual action required: install %s %s from the keyboard setup instructions; refusing an unpinned Homebrew install.\n' "$token" "$held_version" >&2
        return 1
    fi
    if [[ "$installed_version" != "$held_version" ]]; then
        printf 'Held: %s is %s, but this setup requires %s; refusing to change it.\n' "$token" "$installed_version" "$held_version" >&2
        return 1
    fi
    printf 'Held: %s %s (keyboard compatibility hold).\n' "$token" "$held_version"
}

hold_brew_cask_exception() {
    local token="$1" held_version="$2" app_path="$3"
    local version_plist installed_version
    if [[ "$token" != karabiner-elements ]]; then
        printf 'Refusing unlisted held Homebrew cask: %s\n' "$token" >&2
        return 2
    fi
    if [[ "$(uname -s)" != Darwin ]]; then
        printf 'Deferred: %s is macOS-only.\n' "$token"
        return 0
    fi
    version_plist="$app_path/Contents/Info.plist"
    if [[ ! -f "$version_plist" ]]; then
        printf 'Manual action required: install Karabiner-Elements %s from the keyboard setup instructions; refusing the current Homebrew cask.\n' "$held_version" >&2
        return 1
    fi
    installed_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$version_plist" 2>/dev/null || true)"
    if [[ "$installed_version" != "$held_version" ]]; then
        printf 'Held: %s is %s, but this setup requires %s; refusing to change it.\n' "$token" "${installed_version:-unknown}" "$held_version" >&2
        return 1
    fi
    printf 'Held: %s %s (keyboard compatibility hold).\n' "$token" "$held_version"
}

brew_exception_admin_available() {
    if [[ "$(id -u)" == 0 ]] || { [[ -t 0 ]] && [[ -t 1 ]]; }; then
        return 0
    fi
    command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1
}

brew_exception_defer_for_admin() {
    printf 'Deferred: %s needs interactive administrator authorization; run in a terminal: sudo -v && mise -C ~/.config/mise run setup:update\n' "$1"
}
