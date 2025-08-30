#!/usr/bin/env bash

set -euo pipefail

# Linux-specific installation script
# Installs packages and configures Linux-specific settings

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common/setup.sh"

function detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    elif [ -f /etc/redhat-release ]; then
        echo "rhel"
    elif [ -f /etc/debian_version ]; then
        echo "debian"
    else
        echo "unknown"
    fi
}

function install_packages_ubuntu() {
    log_info "Installing packages for Ubuntu/Debian..."
    
    # Update package lists
    sudo apt-get update -qq
    
    # Essential packages
    local packages=(
        "build-essential"
        "curl"
        "wget"
        "git"
        "unzip"
        "software-properties-common"
        "apt-transport-https"
        "ca-certificates"
        "gnupg"
        "lsb-release"
        "fish"
        "neovim"
        "tmux"
        "fzf"
        "ripgrep"
        "fd-find"
        "bat"
        "tree"
        "htop"
        "btop"
    )
    
    for package in "${packages[@]}"; do
        if dpkg -l | grep -q "^ii  $package "; then
            log_info "$package already installed"
        else
            log_info "Installing $package..."
            sudo apt-get install -y "$package" || log_warning "Failed to install $package"
        fi
    done
    
    # Install modern tools from other sources if needed
    install_modern_tools_ubuntu
    
    log_success "Ubuntu packages installation complete"
}

function install_modern_tools_ubuntu() {
    # Install eza (ls replacement)
    if ! command -v eza &>/dev/null; then
        log_info "Installing eza..."
        wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
        echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | sudo tee /etc/apt/sources.list.d/gierens.list
        sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
        sudo apt-get update -qq
        sudo apt-get install -y eza || log_warning "Failed to install eza"
    fi
    
    # Install zoxide
    if ! command -v zoxide &>/dev/null; then
        log_info "Installing zoxide..."
        curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
    fi
    
    # Install starship
    if ! command -v starship &>/dev/null; then
        log_info "Installing starship..."
        curl -sS https://starship.rs/install.sh | sh -s -- -y
    fi
    
    # Install delta
    if ! command -v delta &>/dev/null; then
        log_info "Installing git-delta..."
        local delta_version="0.16.5"
        wget "https://github.com/dandavison/delta/releases/download/${delta_version}/git-delta_${delta_version}_amd64.deb"
        sudo dpkg -i "git-delta_${delta_version}_amd64.deb" || sudo apt-get install -f -y
        rm "git-delta_${delta_version}_amd64.deb"
    fi
}

function install_packages_fedora() {
    log_info "Installing packages for Fedora/RHEL..."
    
    # Essential packages
    local packages=(
        "curl"
        "wget"
        "git"
        "unzip"
        "fish"
        "neovim"
        "tmux"
        "fzf"
        "ripgrep"
        "fd-find"
        "bat"
        "tree"
        "htop"
        "btop"
        "gcc"
        "gcc-c++"
        "make"
    )
    
    for package in "${packages[@]}"; do
        if rpm -q "$package" &>/dev/null; then
            log_info "$package already installed"
        else
            log_info "Installing $package..."
            sudo dnf install -y "$package" || log_warning "Failed to install $package"
        fi
    done
    
    install_modern_tools_fedora
    
    log_success "Fedora packages installation complete"
}

function install_modern_tools_fedora() {
    # Install eza
    if ! command -v eza &>/dev/null; then
        log_info "Installing eza..."
        sudo dnf install -y eza || log_warning "Failed to install eza"
    fi
    
    # Install zoxide
    if ! command -v zoxide &>/dev/null; then
        log_info "Installing zoxide..."
        curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
    fi
    
    # Install starship
    if ! command -v starship &>/dev/null; then
        log_info "Installing starship..."
        curl -sS https://starship.rs/install.sh | sh -s -- -y
    fi
}

function setup_fish_shell_linux() {
    if ! command -v fish &>/dev/null; then
        log_warning "Fish shell not installed, skipping shell setup"
        return 1
    fi
    
    log_info "Setting up Fish shell..."
    
    local fish_path
    fish_path="$(command -v fish)"
    
    # Add fish to /etc/shells if not already there
    if ! grep -q "$fish_path" /etc/shells 2>/dev/null; then
        log_info "Adding Fish to /etc/shells..."
        echo "$fish_path" | sudo tee -a /etc/shells
    fi
    
    # Change default shell to fish
    if [[ "$SHELL" != "$fish_path" ]]; then
        log_info "Changing default shell to Fish..."
        chsh -s "$fish_path"
        log_info "Shell changed to Fish. Please restart your terminal or run: exec fish"
    fi
    
    log_success "Fish shell setup complete"
}

function install_development_tools() {
    log_info "Installing development tools..."
    
    # Install uv (Python package manager)
    if ! command -v uv &>/dev/null; then
        log_info "Installing uv..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
    fi
    
    # Install ruff (Python linter/formatter)
    if ! command -v ruff &>/dev/null; then
        log_info "Installing ruff via pip..."
        if command -v python3 &>/dev/null && command -v pip3 &>/dev/null; then
            python3 -m pip install --user ruff || log_warning "Failed to install ruff - python3/pip3 not available"
        else
            log_warning "Python3/pip3 not available, skipping ruff installation"
        fi
    fi
    
    log_success "Development tools installation complete"
}

function main() {
    log_info "Running Linux-specific setup..."
    
    # Run common setup first  
    source "${SCRIPT_DIR}/../common/setup.sh"
    
    local distro
    distro=$(detect_distro)
    
    case "$distro" in
        ubuntu|debian)
            install_packages_ubuntu
            ;;
        fedora|rhel|centos)
            install_packages_fedora
            ;;
        *)
            log_warning "Unsupported distribution: $distro"
            log_info "Please install packages manually"
            ;;
    esac
    
    install_development_tools
    setup_fish_shell_linux
    
    log_success "Linux setup completed!"
    log_info "Please restart your terminal or run: exec fish (to start Fish shell immediately)"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi