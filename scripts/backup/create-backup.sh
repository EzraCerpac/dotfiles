#!/usr/bin/env bash

set -euo pipefail

# Backup script for dotfiles
# Creates timestamped backups of important configurations

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils/logging.sh"

readonly BACKUP_DATE="$(date +%Y%m%d-%H%M%S)"
readonly BACKUP_DIR="$HOME/.dotfiles-backups"
readonly BACKUP_FILE="dotfiles-backup-${BACKUP_DATE}.tar.gz"

function create_backup_directory() {
    log_info "Creating backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
}

function backup_configurations() {
    log_step "Backing up configuration files"
    
    local temp_dir
    temp_dir=$(mktemp -d)
    local backup_root="${temp_dir}/dotfiles-backup-${BACKUP_DATE}"
    mkdir -p "$backup_root"
    
    # Backup config directories
    local config_dirs=(
        ".config/fish"
        ".config/nvim"
        ".config/git"
        ".config/gh"
        ".config/starship.toml"
        ".config/raycast"
        ".config/aerospace"
        ".local/bin"
    )
    
    for config_dir in "${config_dirs[@]}"; do
        local source_path="$HOME/$config_dir"
        local dest_path="$backup_root/$config_dir"
        
        if [[ -e "$source_path" ]]; then
            log_info "Backing up $config_dir"
            mkdir -p "$(dirname "$dest_path")"
            cp -R "$source_path" "$dest_path" 2>/dev/null || log_warning "Failed to backup $config_dir"
        else
            log_debug "$config_dir does not exist, skipping"
        fi
    done
    
    # Backup shell files
    local shell_files=(
        ".zshrc"
        ".zshenv" 
        ".bashrc"
        ".bash_profile"
        ".profile"
    )
    
    for shell_file in "${shell_files[@]}"; do
        local source_path="$HOME/$shell_file"
        if [[ -f "$source_path" ]]; then
            log_info "Backing up $shell_file"
            cp "$source_path" "$backup_root/" 2>/dev/null || log_warning "Failed to backup $shell_file"
        fi
    done
    
    # Backup SSH config (excluding private keys)
    if [[ -d "$HOME/.ssh" ]]; then
        log_info "Backing up SSH configuration"
        mkdir -p "$backup_root/.ssh"
        cp "$HOME/.ssh/config" "$backup_root/.ssh/" 2>/dev/null || true
        cp "$HOME/.ssh/"*.pub "$backup_root/.ssh/" 2>/dev/null || true
        cp "$HOME/.ssh/authorized_keys" "$backup_root/.ssh/" 2>/dev/null || true
    fi
    
    # Create archive
    log_info "Creating backup archive: $BACKUP_FILE"
    cd "$temp_dir"
    tar -czf "${BACKUP_DIR}/${BACKUP_FILE}" "dotfiles-backup-${BACKUP_DATE}/" 2>/dev/null
    
    # Cleanup
    rm -rf "$temp_dir"
    
    log_success "Backup created: ${BACKUP_DIR}/${BACKUP_FILE}"
}

function backup_chezmoi_source() {
    log_step "Backing up chezmoi source"
    
    if ! command -v chezmoi &>/dev/null; then
        log_warning "chezmoi not installed, skipping source backup"
        return 0
    fi
    
    local source_dir
    if ! source_dir=$(chezmoi source-path 2>/dev/null); then
        log_warning "chezmoi not initialized, skipping source backup"
        return 0
    fi
    
    if [[ -d "$source_dir" ]]; then
        local chezmoi_backup="chezmoi-source-${BACKUP_DATE}.tar.gz"
        log_info "Creating chezmoi source backup: $chezmoi_backup"
        
        cd "$(dirname "$source_dir")"
        tar -czf "${BACKUP_DIR}/${chezmoi_backup}" "$(basename "$source_dir")/" 2>/dev/null
        
        log_success "Chezmoi source backup created: ${BACKUP_DIR}/${chezmoi_backup}"
    fi
}

function backup_package_lists() {
    log_step "Backing up package lists"
    
    local package_list_file="${BACKUP_DIR}/packages-${BACKUP_DATE}.txt"
    
    {
        echo "# Package list backup created on $(date)"
        echo "# System: $(uname -s) $(uname -r) $(uname -m)"
        echo
        
        # Homebrew packages (macOS)
        if command -v brew &>/dev/null; then
            echo "=== Homebrew Packages ==="
            brew list --formula 2>/dev/null || true
            echo
            echo "=== Homebrew Casks ==="
            brew list --cask 2>/dev/null || true
            echo
        fi
        
        # APT packages (Ubuntu/Debian)
        if command -v apt &>/dev/null; then
            echo "=== APT Packages ==="
            apt list --installed 2>/dev/null | grep -E "installed|automatic" || true
            echo
        fi
        
        # DNF/YUM packages (Fedora/RHEL)
        if command -v dnf &>/dev/null; then
            echo "=== DNF Packages ==="
            dnf list installed 2>/dev/null || true
            echo
        elif command -v yum &>/dev/null; then
            echo "=== YUM Packages ==="
            yum list installed 2>/dev/null || true
            echo
        fi
        
        # Python packages
        if command -v uv &>/dev/null; then
            echo "=== Python Packages (uv) ==="
            uv pip list --format=freeze 2>/dev/null || true
            echo
        elif command -v pip3 &>/dev/null; then
            echo "=== Python Packages (pip) ==="
            pip3 list --format=freeze 2>/dev/null || true
            echo
        fi
        
        # Cargo packages (Rust)
        if command -v cargo &>/dev/null; then
            echo "=== Cargo Packages ==="
            cargo install --list 2>/dev/null || true
            echo
        fi
        
    } > "$package_list_file"
    
    log_success "Package lists saved: $package_list_file"
}

function backup_system_info() {
    log_step "Backing up system information"
    
    local system_info_file="${BACKUP_DIR}/system-info-${BACKUP_DATE}.txt"
    
    {
        echo "# System information backup created on $(date)"
        echo
        
        echo "=== System Information ==="
        echo "OS: $(uname -s) $(uname -r)"
        echo "Architecture: $(uname -m)"
        echo "Hostname: $(hostname)"
        echo "User: $USER"
        echo "Home: $HOME"
        echo "Shell: $SHELL"
        echo
        
        echo "=== Environment Variables ==="
        env | sort | grep -E '^(EDITOR|PAGER|BROWSER|PATH|LANG)' || true
        echo
        
        echo "=== Tool Versions ==="
        command -v chezmoi &>/dev/null && echo "chezmoi: $(chezmoi --version)"
        command -v fish &>/dev/null && echo "fish: $(fish --version)"
        command -v git &>/dev/null && echo "git: $(git --version)"
        command -v nvim &>/dev/null && echo "nvim: $(nvim --version | head -1)"
        echo
        
        echo "=== Disk Usage ==="
        df -h "$HOME" 2>/dev/null || true
        echo
        
    } > "$system_info_file"
    
    log_success "System information saved: $system_info_file"
}

function cleanup_old_backups() {
    log_step "Cleaning up old backups"
    
    local days_to_keep=${BACKUP_RETENTION_DAYS:-30}
    
    if [[ -d "$BACKUP_DIR" ]]; then
        log_info "Removing backups older than $days_to_keep days"
        
        find "$BACKUP_DIR" -name "*.tar.gz" -type f -mtime "+$days_to_keep" -delete 2>/dev/null || true
        find "$BACKUP_DIR" -name "*.txt" -type f -mtime "+$days_to_keep" -delete 2>/dev/null || true
        
        local remaining_backups
        remaining_backups=$(find "$BACKUP_DIR" -name "*.tar.gz" -type f | wc -l)
        log_info "Remaining backups: $remaining_backups"
    fi
}

function show_backup_summary() {
    log_step "Backup Summary"
    
    local backup_size
    backup_size=$(du -h "${BACKUP_DIR}/${BACKUP_FILE}" 2>/dev/null | awk '{print $1}' || echo "unknown")
    
    log_success "Backup completed successfully!"
    log_info "Backup location: ${BACKUP_DIR}/${BACKUP_FILE}"
    log_info "Backup size: $backup_size"
    
    echo
    echo "To restore this backup:"
    echo "  tar -xzf '${BACKUP_DIR}/${BACKUP_FILE}' -C /tmp"
    echo "  # Then manually copy files from /tmp/dotfiles-backup-${BACKUP_DATE}/ to your home directory"
    echo
}

function main() {
    log_info "Starting dotfiles backup..."
    
    create_backup_directory
    backup_configurations
    backup_chezmoi_source
    backup_package_lists
    backup_system_info
    cleanup_old_backups
    show_backup_summary
    
    log_success "Backup process completed!"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi