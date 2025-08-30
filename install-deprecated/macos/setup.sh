#!/usr/bin/env bash

set -euo pipefail

# macOS-specific installation script
# Installs Homebrew packages and configures macOS-specific settings

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common/setup.sh"

function install_homebrew() {
    if command -v brew &>/dev/null; then
        log_info "Homebrew already installed"
        return 0
    fi
    
    log_info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Setup Homebrew environment
    if [[ $(arch) == "arm64" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ $(arch) == "i386" ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
    
    log_success "Homebrew installed"
}

function install_homebrew_packages() {
    log_info "Installing Homebrew packages..."
    
    # Essential CLI tools
    local essential_tools=(
        "fish"
        "starship"
        "git"
        "gh"
        "neovim"
        "tmux"
        "fzf"
        "ripgrep"
        "fd"
        "bat"
        "eza"
        "zoxide"
        "delta"
        "curl"
        "wget"
        "tree"
        "htop"
        "btop"
    )
    
    # Development tools
    local dev_tools=(
        "rust"
        "uv"
        "ruff"
    )
    
    # GUI applications via Homebrew Cask
    local cask_apps=(
        "raycast"
        "aerospace"
        "ghostty"
    )
    
    # Install essential tools
    for tool in "${essential_tools[@]}"; do
        if brew list "$tool" &>/dev/null; then
            log_info "$tool already installed"
        else
            log_info "Installing $tool..."
            brew install "$tool" || log_warning "Failed to install $tool"
        fi
    done
    
    # Install development tools
    for tool in "${dev_tools[@]}"; do
        if brew list "$tool" &>/dev/null; then
            log_info "$tool already installed"
        else
            log_info "Installing $tool..."
            brew install "$tool" || log_warning "Failed to install $tool"
        fi
    done
    
    # Install GUI applications
    for app in "${cask_apps[@]}"; do
        if brew list --cask "$app" &>/dev/null; then
            log_info "$app already installed"
        else
            log_info "Installing $app..."
            brew install --cask "$app" || log_warning "Failed to install $app"
        fi
    done
    
    log_success "Homebrew packages installation complete"
}

function setup_macos_defaults() {
    log_info "Setting macOS defaults..."
    
    # Dock settings
    defaults write com.apple.dock autohide -bool true
    defaults write com.apple.dock show-recents -bool false
    defaults write com.apple.dock mineffect -string "scale"
    
    # Finder settings  
    defaults write com.apple.finder ShowPathbar -bool true
    defaults write com.apple.finder ShowStatusBar -bool true
    defaults write NSGlobalDomain AppleShowAllExtensions -bool true
    
    # Trackpad settings
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
    defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
    
    # Keyboard settings
    defaults write NSGlobalDomain KeyRepeat -int 2
    defaults write NSGlobalDomain InitialKeyRepeat -int 15
    
    # Screenshots location
    mkdir -p ~/Pictures/Screenshots
    defaults write com.apple.screencapture location ~/Pictures/Screenshots
    
    # Menu bar clock
    defaults write com.apple.menuextra.clock DateFormat -string "EEE MMM d  h:mm a"
    
    log_info "Restarting affected applications..."
    killall Dock || true
    killall Finder || true
    killall SystemUIServer || true
    
    log_success "macOS defaults configured"
}

function setup_fish_shell() {
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

function main() {
    log_info "Running macOS-specific setup..."
    
    # Run common setup first
    source "${SCRIPT_DIR}/../common/setup.sh"
    
    install_homebrew
    install_homebrew_packages
    setup_macos_defaults
    setup_fish_shell
    
    log_success "macOS setup completed!"
    log_info "Please restart your terminal or run: exec fish (to start Fish shell immediately)"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi