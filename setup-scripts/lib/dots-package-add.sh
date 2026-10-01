#!/usr/bin/env bash
# Add native bootstrap packages for the `dots add` wrapper.
#
# The first three arguments are explicit so this helper can select the setup
# before mise reads the directory from which the wrapper was called:
#
#   dots-package-add.sh MISE_BIN SETUP_ROOT TARGET_CONFIG PACKAGE...

set -euo pipefail

usage() {
    printf 'usage: %s MISE_BIN SETUP_ROOT TARGET_CONFIG PACKAGE...\n' "$0" >&2
}

if [[ "$#" -lt 4 ]]; then
    usage
    exit 2
fi

mise_bin="$1"
setup_root="$2"
target_file="$3"
shift 3
source "$setup_root/setup-scripts/lib/dots-add-common.sh"

[[ -x "$mise_bin" ]] || { printf 'dots: mise executable is missing: %s\n' "$mise_bin" >&2; exit 2; }
[[ -d "$setup_root" ]] || { printf 'dots: setup root is missing: %s\n' "$setup_root" >&2; exit 2; }
[[ -f "$target_file" ]] || { printf 'dots: package config is missing: %s\n' "$target_file" >&2; exit 2; }

# Keep package discovery rooted in the setup checkout.  Do not add the target
# directory to mise's trust list: choosing --path is permission to edit that
# file, not permission to execute nearby configuration.
export MISE_CONFIG_DIR="$setup_root"
work_root="$(mktemp -d "${TMPDIR:-/tmp}/dots-package-add.XXXXXX")"
trap 'rm -rf "$work_root"' EXIT
cp "$target_file" "$work_root/before.toml"

mise_packages() {
    "$mise_bin" -C "$setup_root" bootstrap packages "$@"
}

toml_quote() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '"%s"' "$value"
}

# A package table is copied into a temporary one-package config for the
# installer.  This retains adopt/os/version and other native options while
# ensuring `apply` cannot install all of the target profile's packages.
write_isolated_config() {
    local file="$1" key="$2" declaration="$3" taps="$4"
    {
        # The isolated config cannot see the setup's global settings.  Keep
        # GitHub auth available for third-party Homebrew taps without copying
        # a token into the temporary file.
        printf '[settings.github]\ncredential_command = '
        toml_quote "sh \"$setup_root/setup-scripts/lib/github-credential.sh\""
        printf '\n\n'
        if [[ -n "$taps" ]]; then
            printf '[bootstrap.brew.taps]\n%s\n\n' "$taps"
        fi
        if [[ "$declaration" == *'='* ]]; then
            printf '[bootstrap.packages.'
            toml_quote "$key"
            printf ']\n%s\n' "$declaration"
        else
            printf '[bootstrap.packages]\n'
            toml_quote "$key"
            printf ' = '
            toml_quote "$declaration"
            printf '\n'
        fi
    } >"$file"
}

# Read one declaration from a selected config.  A missing key is expected;
# every other mise error is fatal so a trust or parse problem cannot become a
# write to the wrong file.
read_declaration() {
    local target="$1" key_path="$2" error_file="$3"
    "$mise_bin" -C "$setup_root" config get --file "$target" "$key_path" 2>"$error_file"
}

read_optional_declaration() {
    local target="$1" key_path="$2" error_file value status
    error_file="$(mktemp "${TMPDIR:-/tmp}/dots-package-optional.XXXXXX")"
    if value="$(read_declaration "$target" "$key_path" "$error_file")"; then
        rm -f "$error_file"
        printf '%s' "$value"
        return 0
    else
        status=$?
    fi
    if grep -q 'Key not found' "$error_file"; then
        rm -f "$error_file"
        return 0
    fi
    cat "$error_file" >&2
    rm -f "$error_file"
    return "$status"
}

merge_taps() {
    # `mise config get` emits one TOML assignment per tap.  Keep base entries
    # first and replace duplicate keys with the target's value, so a profile
    # can override a shared tap without duplicate TOML keys.
    awk '
        function key(line, rest) {
            rest = line
            sub(/^[[:space:]]*/, "", rest)
            sub(/[[:space:]]*=.*$/, "", rest)
            return rest
        }
        NF {
            current = key($0)
            if (!(current in values)) order[++count] = current
            values[current] = $0
        }
        END {
            for (i = 1; i <= count; i++) print values[order[i]]
        }
    '
}

package_manager=""
package_name=""
package_key=""
key_path=""
declaration=""
error_file=""
probe_status=0
package_is_mac=0
package_is_new=0

declare -a package_list=()
declare -a package_managers=()
declare -a package_keys=()
declare -a package_declarations=()
declare -a package_new=()
declare -a package_mac=()

# Preflight all package names and declarations before changing the target.
for package in "$@"; do
    case "$package" in
        brew:*|brew-cask:*|mas:*|apt:*|dnf:*|pacman:*|apk:*) ;;
        *) printf 'dots: unsupported bootstrap package: %s\n' "$package" >&2; exit 2 ;;
    esac

    package_manager="${package%%:*}"
    package_name="${package#*:}"
    [[ -n "$package_name" ]] || { printf 'dots: empty package name: %s\n' "$package" >&2; exit 2; }

    # Homebrew and mas include @ in their package names.  Other supported
    # managers use @ to separate a version, which mise stores as the value.
    case "$package_manager" in
        brew|brew-cask|mas)
            package_key="$package"
            package_is_mac=1
            ;;
        *)
            package_key="$package_manager:${package_name%%@*}"
            package_is_mac=0
            ;;
    esac

    # Dotted mise paths cannot address a literal dotted package key.  Reject
    # such input before native mise can write a misleading nested declaration.
    if [[ ! "$package_key" =~ ^[A-Za-z0-9_/@:+-]+$ ]]; then
        printf 'dots: package name is not safe for a mise config key: %s\n' "$package" >&2
        exit 2
    fi
    # ${a[@]+...}: macOS /bin/bash 3.2 treats an empty array as unset under set -u.
    for previous_key in ${package_keys[@]+"${package_keys[@]}"}; do
        if [[ "$previous_key" == "$package_key" ]]; then
            printf 'dots: package was supplied more than once: %s\n' "$package" >&2
            exit 2
        fi
    done

    key_path="bootstrap.packages.$package_key"
    error_file="$(mktemp "${TMPDIR:-/tmp}/dots-package-probe.XXXXXX")"
    if declaration="$(read_declaration "$work_root/before.toml" "$key_path" "$error_file")"; then
        package_is_new=0
    else
        probe_status=$?
        if ! grep -q 'Key not found' "$error_file"; then
            cat "$error_file" >&2
            rm -f "$error_file"
            exit "$probe_status"
        fi
        declaration=""
        package_is_new=1
    fi
    rm -f "$error_file"

    package_list+=("$package")
    package_managers+=("$package_manager")
    package_keys+=("$package_key")
    package_declarations+=("$declaration")
    package_new+=("$package_is_new")
    package_mac+=("$package_is_mac")
done

data_dir="${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}"
state_dir="${MISE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/mise}"
if [[ -n "${MISE_CACHE_DIR:-}" ]]; then
    cache_dir="$MISE_CACHE_DIR"
else
    if cache_dir="$("$mise_bin" -C "$setup_root" cache path 2>/dev/null)" && [[ -n "$cache_dir" ]]; then
        :
    else
        printf 'dots: could not determine mise cache directory\n' >&2
        exit 1
    fi
fi

# Read shared tap metadata before writing any requested package declaration.
taps=""
for manager in ${package_managers[@]+"${package_managers[@]}"}; do
    case "$manager" in
        brew|brew-cask)
            base_taps=""
            if [[ -f "$setup_root/config.toml" ]]; then
                base_taps="$(read_optional_declaration "$setup_root/config.toml" bootstrap.brew.taps)"
            fi
            target_taps="$(read_optional_declaration "$work_root/before.toml" bootstrap.brew.taps)"
            taps="$(printf '%s\n%s\n' "$base_taps" "$target_taps" | merge_taps)"
            break
            ;;
    esac
done

declare -a staged_configs=() replace_keys=() resolved_keys=()

isolated_apply() {
    local config="$1"
    shift
    local directory="${config%/*}"
    MISE_CONFIG_DIR="$directory" MISE_ENV= MISE_TRUSTED_CONFIG_PATHS="$directory" \
        MISE_DATA_DIR="$data_dir" MISE_CACHE_DIR="$cache_dir" MISE_STATE_DIR="$state_dir" \
        "$mise_bin" -C "$directory" bootstrap packages apply "$@"
}

describe_declaration() {
    local key="$1" value="$2"
    if [[ "$value" == *'='* ]]; then
        printf '[bootstrap.packages.'; toml_quote "$key"; printf ']\n%s\n' "$value"
    else
        printf '[bootstrap.packages]\n'; toml_quote "$key"; printf ' = '; toml_quote "$value"; printf '\n'
    fi
}

record_package() {
    local config="$1" key="$2" old_key="$3"
    local arguments=(record-package "$target_file" "$config" "$key" --before "$work_root/before.toml")
    [[ -z "$old_key" ]] || arguments+=(--replace-key "$old_key")
    dots_edit_config "${arguments[@]}" || return $?
    printf 'Recorded %s in %s\n' "$key" "$target_file"
}

failed_package() {
    local status="$1" config="$2" key="$3" value="$4"
    printf 'dots: failed to install package: %s\n' "$key" >&2
    if [[ "$status" -ne 130 && "$status" -ne 143 ]] && \
        dots_record_failed "$(describe_declaration "$key" "$value")" "$target_file"; then
        # Existing declarations survive a failed attempt, including an old
        # formula key. Only a successful cask install completes that migration.
        record_package "$config" "$key" "" || printf 'dots: failed to record package: %s\n' "$key" >&2
    fi
    exit "$status"
}

formula_absent() {
    local errors="$1" name="$2"
    # A metadata failure alone is insufficient for taps: the Ruby definition
    # may still exist. Only fall back after mise's definition lookup says no.
    if [[ "$name" == */* ]]; then
        grep -Fq "mise ERROR tap has no formula named '${name##*/}' in " "$errors"
    else
        grep -Fxq "mise ERROR HTTP status client error (404 Not Found) for url (https://formulae.brew.sh/api/formula/$name.json)" "$errors"
    fi
}

check_held_package() {
    local key="$1" manager="${1%%:*}" token="${1##*/}"
    token="${token#*:}"
    case "$manager:$token" in
        brew:kanata|brew:kanata@*|brew-cask:karabiner-elements|brew-cask:karabiner-elements@*)
            printf 'dots: Kanata and Karabiner are held installer exceptions; change their reviewed hold recipe instead\n' >&2
            return 2 ;;
    esac
}

# Resolve every package first. A duplicate discovered after cask routing must
# stop before any package in this group is installed or recorded.
for index in "${!package_list[@]}"; do
    package="${package_list[$index]}"
    package_manager="${package_managers[$index]}"
    package_key="${package_keys[$index]}"
    declaration="${package_declarations[$index]}"
    package_is_new="${package_new[$index]}"
    package_is_mac="${package_mac[$index]}"
    old_key=""
    check_held_package "$package_key"
    install_root="$work_root/$index"
    mkdir "$install_root"
    install_config="$install_root/mise.toml"

    if [[ "$package_is_new" -eq 1 ]]; then
        if [[ "$package_is_mac" -eq 1 ]]; then
            declaration='os = "macos/arm64"'
        else
            # Let mise retain its native version parsing, but only in staging.
            printf '[bootstrap.packages]\n' > "$install_config"
            mise_packages use --no-install --path "$install_config" "$package"
            declaration="$(read_optional_declaration "$install_config" "bootstrap.packages.$package_key")"
        fi
    fi
    write_isolated_config "$install_config" "$package_key" "$declaration" "$taps"

    if [[ "$package_manager" == brew ]]; then
        if isolated_apply "$install_config" --dry-run > "$work_root/probe.out" 2> "$work_root/probe.err"; then
            :
        else
            probe_status=$?
            if formula_absent "$work_root/probe.err" "${package#*:}"; then
                candidate="brew-cask:${package#*:}"
                candidate_declaration="$(read_optional_declaration "$work_root/before.toml" "bootstrap.packages.$candidate")"
                if [[ -n "$candidate_declaration" ]]; then
                    if [[ "$package_is_new" -eq 0 && "$declaration" != "$candidate_declaration" ]]; then
                        printf 'dots: conflicting formula and cask declarations for %s; reconcile them first\n' "$package" >&2
                        exit 2
                    fi
                    declaration="$candidate_declaration"
                fi
                write_isolated_config "$install_config" "$candidate" "$declaration" "$taps"
                if isolated_apply "$install_config" --dry-run > "$work_root/cask.out" 2> "$work_root/cask.err"; then
                    [[ "$package_is_new" -eq 1 ]] || old_key="$package_key"
                    package_key="$candidate"
                else
                    probe_status=$?
                    cat "$work_root/probe.err" "$work_root/cask.err" >&2
                    # Neither type resolved: retain the original request for
                    # the optional record prompt, without claiming a cask.
                    declaration="${package_declarations[$index]}"
                    [[ -n "$declaration" ]] || declaration='os = "macos/arm64"'
                    write_isolated_config "$install_config" "$package_key" "$declaration" "$taps"
                    failed_package "$probe_status" "$install_config" "$package_key" "$declaration"
                fi
            else
                cat "$work_root/probe.err" >&2
                failed_package "$probe_status" "$install_config" "$package_key" "$declaration"
            fi
        fi
    fi
    check_held_package "$package_key"
    for resolved in "${resolved_keys[@]+"${resolved_keys[@]}"}"; do
        if [[ "$resolved" == "$package_key" ]]; then
            printf 'dots: package was supplied more than once after routing: %s\n' "$package_key" >&2
            exit 2
        fi
    done
    resolved_keys+=("$package_key")
    staged_configs+=("$install_config")
    replace_keys+=("$old_key")
    package_declarations[$index]="$declaration"
done

for index in "${!resolved_keys[@]}"; do
    package_key="${resolved_keys[$index]}"
    install_config="${staged_configs[$index]}"
    old_key="${replace_keys[$index]}"
    printf 'Installing %s\n' "$package_key"
    if isolated_apply "$install_config" --yes; then
        if record_package "$install_config" "$package_key" "$old_key"; then
            :
        else
            record_status=$?
            printf 'dots: %s installed, but its declaration could not be recorded\n' "$package_key" >&2
            exit "$record_status"
        fi
    else
        install_status=$?
        failed_package "$install_status" "$install_config" "$package_key" "${package_declarations[$index]}"
    fi
done
