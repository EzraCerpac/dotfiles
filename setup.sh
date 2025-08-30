#!/usr/bin/env bash

set -Eeuo pipefail

if [ "${DOTFILES_DEBUG:-}" ]; then
    set -x
fi

# shellcheck disable=SC2016
declare -r DOTFILES_LOGO='
    ____        __  _____ __           
   / __ \____  / /_/ __(_) /__  _____
  / / / / __ \/ __/ /_/ / / _ \/ ___/
 / /_/ / /_/ / /_/ __/ / /  __(__  ) 
/_____/\____/\__/_/ /_/_/\___/____/  
                                     
*** Personal dotfiles setup with chezmoi ***
    https://github.com/EzraCerpac/dotfiles
'

declare -r DOTFILES_REPO_URL="https://github.com/EzraCerpac/dotfiles"
declare -r BRANCH_NAME="${BRANCH_NAME:-main}"
declare -r DOTFILES_GITHUB_PAT="${DOTFILES_GITHUB_PAT:-}"

function is_ci() {
    "${CI:-false}"
}

function is_tty() {
    [ -t 0 ]
}

function is_not_tty() {
    ! is_tty
}

function is_ci_or_not_tty() {
    is_ci || is_not_tty
}

function at_exit() {
    AT_EXIT+="${AT_EXIT:+$'\n'}"
    AT_EXIT+="${*?}"
    # shellcheck disable=SC2064
    trap "${AT_EXIT}" EXIT
}

function get_os_type() {
    uname
}

function log_info() {
    echo -e "\033[0;34m[INFO]\033[0m $*"
}

function log_success() {
    echo -e "\033[0;32m[SUCCESS]\033[0m $*"
}

function log_error() {
    echo -e "\033[0;31m[ERROR]\033[0m $*" >&2
}

function log_warning() {
    echo -e "\033[0;33m[WARNING]\033[0m $*"
}

function keepalive_sudo_linux() {
    log_info "Checking for \`sudo\` access which may request your password."
    sudo -v

    # Keep-alive: update existing sudo time stamp if set, otherwise do nothing.
    while true; do
        sudo -n true
        sleep 60
        kill -0 "$$" || exit
    done 2>/dev/null &
}

function keepalive_sudo_macos() {
    # Store password in keychain temporarily for automated sudo
    (
        builtin read -r -s -p "Password: " </dev/tty
        builtin echo "add-generic-password -U -s 'dotfiles' -a '${USER}' -w '${REPLY}'"
    ) | /usr/bin/security -i
    printf "\n"
    
    at_exit "
        log_info 'Removing password from Keychain...'
        /usr/bin/security delete-generic-password -s 'dotfiles' -a '${USER}' 2>/dev/null || true
    "
    
    SUDO_ASKPASS="$(/usr/bin/mktemp)"
    at_exit "
        log_info 'Cleaning up SUDO_ASKPASS script...'
        /bin/rm -f '${SUDO_ASKPASS}'
    "
    
    {
        echo "#!/bin/sh"
        echo "/usr/bin/security find-generic-password -s 'dotfiles' -a '${USER}' -w"
    } >"${SUDO_ASKPASS}"

    /bin/chmod +x "${SUDO_ASKPASS}"
    export SUDO_ASKPASS

    if ! /usr/bin/sudo -A -kv 2>/dev/null; then
        log_error 'Incorrect password.'
        exit 1
    fi
}

function keepalive_sudo() {
    local ostype
    ostype="$(get_os_type)"

    if [ "${ostype}" == "Darwin" ]; then
        keepalive_sudo_macos
    elif [ "${ostype}" == "Linux" ]; then
        keepalive_sudo_linux
    else
        log_error "Unsupported OS type: ${ostype}"
        exit 1
    fi
}

function is_homebrew_exists() {
    command -v brew &>/dev/null
}

function initialize_os_macos() {
    log_info "Initializing macOS environment..."

    # Install Homebrew if needed
    if ! is_homebrew_exists; then
        log_info "Installing Homebrew..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    # Setup Homebrew environment
    if [[ $(arch) == "arm64" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ $(arch) == "i386" ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    else
        log_error "Unsupported CPU architecture: $(arch)"
        exit 1
    fi

    log_success "macOS environment initialized"
}

function initialize_os_linux() {
    log_info "Initializing Linux environment..."
    
    # Update package lists
    if command -v apt-get &>/dev/null; then
        sudo apt-get update -qq
    elif command -v yum &>/dev/null; then
        sudo yum update -y -q
    elif command -v pacman &>/dev/null; then
        sudo pacman -Sy --noconfirm
    fi
    
    log_success "Linux environment initialized"
}

function initialize_os_env() {
    local ostype
    ostype="$(get_os_type)"

    if [ "${ostype}" == "Darwin" ]; then
        initialize_os_macos
    elif [ "${ostype}" == "Linux" ]; then
        initialize_os_linux
    else
        log_error "Unsupported OS type: ${ostype}"
        exit 1
    fi
}

function install_chezmoi() {
    local bin_dir="${HOME}/.local/bin"
    mkdir -p "${bin_dir}"
    export PATH="${PATH}:${bin_dir}"

    if ! command -v chezmoi &>/dev/null; then
        log_info "Installing chezmoi..."
        sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "${bin_dir}"
    else
        log_info "chezmoi already installed"
    fi
    
    log_success "chezmoi installation complete"
}

function run_chezmoi() {
    local bin_dir="${HOME}/.local/bin"
    export PATH="${PATH}:${bin_dir}"
    local chezmoi_cmd="${bin_dir}/chezmoi"

    # Check if chezmoi is in PATH
    if command -v chezmoi &>/dev/null; then
        chezmoi_cmd="chezmoi"
    elif [ ! -f "${chezmoi_cmd}" ]; then
        log_error "chezmoi not found. Please install it first."
        exit 1
    fi

    local no_tty_option=""
    if is_ci_or_not_tty; then
        no_tty_option="--no-tty"
    fi

    log_info "Initializing chezmoi with dotfiles repository..."
    "${chezmoi_cmd}" init "${DOTFILES_REPO_URL}" \
        --force \
        --branch "${BRANCH_NAME}" \
        --use-builtin-git true \
        ${no_tty_option}

    # Handle encrypted files in CI/non-TTY environments
    if is_ci_or_not_tty; then
        log_warning "Removing encrypted files in CI/non-TTY environment"
        find "$(${chezmoi_cmd} source-path)" -type f -name "encrypted_*" -exec rm -fv {} + 2>/dev/null || true
        find "$(${chezmoi_cmd} source-path)" -type f -name "private_*" -exec rm -fv {} + 2>/dev/null || true
    fi

    # Set up environment
    export PATH="${PATH}:${HOME}/.local/bin"
    if [[ -n "${DOTFILES_GITHUB_PAT}" ]]; then
        export DOTFILES_GITHUB_PAT
    fi

    log_info "Applying dotfiles configuration..."
    "${chezmoi_cmd}" apply ${no_tty_option}

    log_success "Dotfiles applied successfully!"
}

function run_platform_setup() {
    local ostype
    ostype="$(get_os_type | tr '[:upper:]' '[:lower:]')"
    
    local install_dir="$(dirname "$0")/install"
    local platform_script=""
    
    if [ "${ostype}" == "darwin" ]; then
        platform_script="${install_dir}/macos/setup.sh"
    elif [ "${ostype}" == "linux" ]; then
        platform_script="${install_dir}/linux/setup.sh"
    fi
    
    if [ -f "${platform_script}" ]; then
        log_info "Running platform-specific setup: ${platform_script}"
        bash "${platform_script}"
    else
        log_warning "No platform-specific setup found for ${ostype}"
    fi
}

function show_completion_message() {
    cat << 'EOF'

🎉 Dotfiles setup completed successfully!

Next steps:
  1. Restart your terminal or run: source ~/.zshrc (or ~/.bashrc)
  2. Check configuration: chezmoi doctor
  3. Update dotfiles: chezmoi update
  4. Edit configurations: chezmoi edit <file>

For more information:
  - chezmoi help
  - Visit: https://github.com/EzraCerpac/dotfiles

EOF
}

function initialize_dotfiles() {
    if ! is_ci_or_not_tty; then
        keepalive_sudo
    fi
    
    install_chezmoi
    run_chezmoi
    run_platform_setup
}

function main() {
    echo "$DOTFILES_LOGO"

    initialize_os_env
    initialize_dotfiles
    
    show_completion_message
}

# Allow sourcing this script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi