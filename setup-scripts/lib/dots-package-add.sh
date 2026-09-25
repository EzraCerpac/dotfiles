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

[[ -x "$mise_bin" ]] || { printf 'dots: mise executable is missing: %s\n' "$mise_bin" >&2; exit 2; }
[[ -d "$setup_root" ]] || { printf 'dots: setup root is missing: %s\n' "$setup_root" >&2; exit 2; }
[[ -f "$target_file" ]] || { printf 'dots: package config is missing: %s\n' "$target_file" >&2; exit 2; }

# Keep package discovery rooted in the setup checkout.  Do not add the target
# directory to mise's trust list: choosing --path is permission to edit that
# file, not permission to execute nearby configuration.
export MISE_CONFIG_DIR="$setup_root"

mise_config() {
    "$mise_bin" -C "$setup_root" config "$@"
}

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
    for previous_key in "${package_keys[@]}"; do
        if [[ "$previous_key" == "$package_key" ]]; then
            printf 'dots: package was supplied more than once: %s\n' "$package" >&2
            exit 2
        fi
    done

    key_path="bootstrap.packages.$package_key"
    error_file="$(mktemp "${TMPDIR:-/tmp}/dots-package-probe.XXXXXX")"
    if declaration="$(read_declaration "$target_file" "$key_path" "$error_file")"; then
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
for manager in "${package_managers[@]}"; do
    case "$manager" in
        brew|brew-cask)
            base_taps=""
            if [[ -f "$setup_root/config.toml" ]]; then
                base_taps="$(read_optional_declaration "$setup_root/config.toml" bootstrap.brew.taps)"
            fi
            target_taps="$(read_optional_declaration "$target_file" bootstrap.brew.taps)"
            taps="$(printf '%s\n%s\n' "$base_taps" "$target_taps" | merge_taps)"
            break
            ;;
    esac
done

for index in "${!package_list[@]}"; do
    package="${package_list[$index]}"
    package_manager="${package_managers[$index]}"
    package_key="${package_keys[$index]}"
    declaration="${package_declarations[$index]}"
    package_is_new="${package_new[$index]}"
    package_is_mac="${package_mac[$index]}"

    if [[ "$package_is_new" -eq 1 ]]; then
        if [[ "$package_is_mac" -eq 1 ]]; then
            # An absent key can safely become a child table.  This writes the
            # macOS guard before any installer runs, so a failed install never
            # leaves an unguarded package in shared workstation config.
            if mise_config set --file "$target_file" "bootstrap.packages.$package_key.os" macos/arm64; then
                :
            else
                install_status=$?
                printf 'dots: failed to record package: %s\n' "$package" >&2
                exit "$install_status"
            fi
        else
            # `use --no-install` writes the native manager's version shape
            # (for example apt:curl@8.5.0-2 becomes apt:curl = "8.5.0-2")
            # without starting an installation yet.
            if mise_packages use --no-install --path "$target_file" "$package"; then
                :
            else
                install_status=$?
                printf 'dots: failed to record package: %s\n' "$package" >&2
                exit "$install_status"
            fi
        fi

        error_file="$(mktemp "${TMPDIR:-/tmp}/dots-package-declaration.XXXXXX")"
        if declaration="$(read_declaration "$target_file" "bootstrap.packages.$package_key" "$error_file")"; then
            :
        else
            install_status=$?
            cat "$error_file" >&2
            rm -f "$error_file"
            printf 'dots: package declaration could not be read back: %s\n' "$package" >&2
            exit "$install_status"
        fi
        rm -f "$error_file"
    fi

    install_root="$(mktemp -d "${TMPDIR:-/tmp}/dots-package-install.XXXXXX")"
    install_config="$install_root/mise.toml"
    write_isolated_config "$install_config" "$package_key" "$declaration" "$taps"

    # Use a private config directory for the selected declaration only.  Keep
    # mise's real install data/cache/state so an installed package is visible
    # to the normal setup, while MISE_ENV is empty so no profile is merged.
    if MISE_CONFIG_DIR="$install_root" MISE_ENV= MISE_TRUSTED_CONFIG_PATHS="$install_root" \
        MISE_DATA_DIR="$data_dir" MISE_CACHE_DIR="$cache_dir" MISE_STATE_DIR="$state_dir" \
        "$mise_bin" -C "$install_root" bootstrap packages apply --yes; then
        rm -rf "$install_root"
    else
        install_status=$?
        rm -rf "$install_root"
        printf 'dots: failed to install package: %s\n' "$package" >&2
        exit "$install_status"
    fi
done
