#!/usr/bin/env bash

set -euo pipefail

# Common installation script for all platforms
# This script installs essential tools and packages that work across platforms

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../scripts/utils/logging.sh" 2>/dev/null || {
    log_info() { echo -e "\033[0;34m[INFO]\033[0m $*"; }
    log_success() { echo -e "\033[0;32m[SUCCESS]\033[0m $*"; }
    log_error() { echo -e "\033[0;31m[ERROR]\033[0m $*" >&2; }
    log_warning() { echo -e "\033[0;33m[WARNING]\033[0m $*"; }
}

function install_essential_tools() {
    log_info "Installing essential command-line tools..."
    
    # Essential tools that should be available on most systems
    local tools=(
        "git"
        "curl" 
        "wget"
        "unzip"
        "tar"
    )
    
    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            log_warning "$tool not found - please install manually"
        else
            log_info "$tool ✓"
        fi
    done
}

function setup_directories() {
    log_info "Setting up directory structure..."
    
    # Create common directories
    mkdir -p ~/.local/bin
    mkdir -p ~/.local/share
    mkdir -p ~/.config
    mkdir -p ~/Projects
    mkdir -p ~/Scripts
    
    # Ensure ~/.local/bin is in PATH
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        log_info "Adding ~/.local/bin to PATH in shell configuration"
        # This will be handled by the shell configurations in chezmoi
    fi
    
    log_success "Directory structure created"
}

function install_modern_unix_tools() {
    log_info "Installing modern Unix replacement tools..."
    
    # List of modern CLI tools we want
    local modern_tools=(
        "bat"      # cat replacement
        "eza"      # ls replacement  
        "fd"       # find replacement
        "rg"       # grep replacement
        "fzf"      # fuzzy finder
        "zoxide"   # cd replacement
        "delta"    # git diff viewer
    )
    
    for tool in "${modern_tools[@]}"; do
        if command -v "$tool" &>/dev/null; then
            log_info "$tool ✓"
        else
            log_warning "$tool not installed - will be handled by platform-specific scripts"
        fi
    done
}

function setup_git_config() {
    log_info "Setting up basic Git configuration..."
    
    # Basic git settings that should be consistent
    if ! git config --global user.name &>/dev/null; then
        log_info "Git user.name not set - will be configured by chezmoi"
    fi
    
    if ! git config --global user.email &>/dev/null; then
        log_info "Git user.email not set - will be configured by chezmoi"
    fi
    
    # Set some sensible defaults
    git config --global init.defaultBranch main || true
    git config --global pull.rebase false || true
    git config --global core.autocrlf input || true
    
    log_success "Basic Git configuration complete"
}

function main() {
    log_info "Running common setup for all platforms..."
    
    setup_directories
    install_essential_tools
    install_modern_unix_tools
    setup_git_config
    
    log_success "Common setup completed!"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi