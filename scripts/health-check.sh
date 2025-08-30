#!/usr/bin/env bash

set -euo pipefail

# Health check script for dotfiles
# Validates configuration files and tool installations

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils/logging.sh"

function check_chezmoi() {
    log_step "Checking chezmoi setup"
    
    if ! command -v chezmoi &>/dev/null; then
        log_error "chezmoi is not installed"
        return 1
    fi
    
    log_info "chezmoi version: $(chezmoi --version)"
    
    if ! chezmoi source-path &>/dev/null; then
        log_error "chezmoi is not initialized"
        return 1
    fi
    
    log_info "Source directory: $(chezmoi source-path)"
    
    # Check if there are any issues
    if ! chezmoi verify &>/dev/null; then
        log_warning "chezmoi verify found issues:"
        chezmoi verify 2>&1 | while read -r line; do
            log_warning "  $line"
        done
    else
        log_success "chezmoi verification passed"
    fi
    
    return 0
}

function check_shell_tools() {
    log_step "Checking shell and CLI tools"
    
    local tools=(
        "fish:Fish shell"
        "starship:Starship prompt"
        "git:Git version control"
        "gh:GitHub CLI"
        "nvim:Neovim editor"
        "fzf:Fuzzy finder"
        "rg:ripgrep"
        "fd:fd-find"
        "bat:bat (cat alternative)"
        "eza:eza (ls alternative)"
        "zoxide:zoxide (cd alternative)"
    )
    
    local missing_tools=()
    
    for tool_info in "${tools[@]}"; do
        local tool="${tool_info%%:*}"
        local desc="${tool_info##*:}"
        
        if command -v "$tool" &>/dev/null; then
            log_info "$desc: ✓"
        else
            log_warning "$desc: ✗ (not installed)"
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -eq 0 ]]; then
        log_success "All essential tools are installed"
        return 0
    else
        log_warning "Missing tools: ${missing_tools[*]}"
        return 1
    fi
}

function check_development_tools() {
    log_step "Checking development tools"
    
    local dev_tools=(
        "rust:Rust language" 
        "uv:UV Python package manager"
        "ruff:Ruff Python linter"
    )
    
    local missing_dev_tools=()
    
    for tool_info in "${dev_tools[@]}"; do
        local tool="${tool_info%%:*}"
        local desc="${tool_info##*:}"
        
        if command -v "$tool" &>/dev/null; then
            local version=""
            case $tool in
                rust) version="$(rustc --version | awk '{print $2}')" ;;
                uv) version="$(uv --version 2>/dev/null | awk '{print $2}' || echo 'installed')" ;;
                ruff) version="$(ruff --version 2>/dev/null | awk '{print $2}' || echo 'installed')" ;;
            esac
            log_info "$desc ($version): ✓"
        else
            log_warning "$desc: ✗ (not installed)"
            missing_dev_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_dev_tools[@]} -eq 0 ]]; then
        log_success "All development tools are available"
        return 0
    else
        log_info "Optional development tools missing: ${missing_dev_tools[*]}"
        return 0  # Don't fail for missing dev tools
    fi
}

function check_config_files() {
    log_step "Checking configuration files"
    
    local config_dirs=(
        "$HOME/.config/fish"
        "$HOME/.config/nvim"
        "$HOME/.config/git"
        "$HOME/.config/gh"
    )
    
    local issues=0
    
    for dir in "${config_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            log_info "$(basename "$dir") config: ✓"
        else
            log_warning "$(basename "$dir") config: ✗ (directory not found)"
            ((issues++))
        fi
    done
    
    # Check specific important files
    local important_files=(
        "$HOME/.config/fish/config.fish:Fish configuration"
        "$HOME/.config/git/config:Git configuration"
    )
    
    for file_info in "${important_files[@]}"; do
        local file="${file_info%%:*}"
        local desc="${file_info##*:}"
        
        if [[ -f "$file" ]]; then
            log_info "$desc: ✓"
        else
            log_warning "$desc: ✗ (file not found)"
            ((issues++))
        fi
    done
    
    if [[ $issues -eq 0 ]]; then
        log_success "All configuration files are in place"
        return 0
    else
        log_warning "$issues configuration issues found"
        return 1
    fi
}

function check_shell_environment() {
    log_step "Checking shell environment"
    
    # Check if Fish is the default shell
    if [[ "$SHELL" =~ fish ]]; then
        log_info "Default shell: Fish ✓"
    else
        log_info "Default shell: $SHELL (consider switching to Fish)"
    fi
    
    # Check PATH
    if [[ ":$PATH:" == *":$HOME/.local/bin:"* ]]; then
        log_info "~/.local/bin in PATH: ✓"
    else
        log_warning "~/.local/bin not in PATH"
    fi
    
    # Check important environment variables
    local env_vars=(
        "EDITOR"
        "PAGER" 
        "BROWSER"
    )
    
    for var in "${env_vars[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            log_info "$var: ${!var} ✓"
        else
            log_info "$var: not set (will use defaults)"
        fi
    done
    
    return 0
}

function check_git_config() {
    log_step "Checking Git configuration"
    
    local git_settings=(
        "user.name"
        "user.email"
        "init.defaultBranch"
        "core.editor"
    )
    
    local issues=0
    
    for setting in "${git_settings[@]}"; do
        local value
        if value=$(git config --global "$setting" 2>/dev/null); then
            log_info "$setting: $value ✓"
        else
            if [[ "$setting" == "user.name" || "$setting" == "user.email" ]]; then
                log_error "$setting: not set (required)"
                ((issues++))
            else
                log_info "$setting: not set (optional)"
            fi
        fi
    done
    
    if [[ $issues -eq 0 ]]; then
        log_success "Git configuration looks good"
        return 0
    else
        log_error "Git configuration has $issues critical issues"
        return 1
    fi
}

function check_permissions() {
    log_step "Checking file permissions"
    
    # Check for common permission issues
    local dirs_to_check=(
        "$HOME/.config"
        "$HOME/.local"
        "$HOME/.local/bin"
    )
    
    for dir in "${dirs_to_check[@]}"; do
        if [[ -d "$dir" ]]; then
            if [[ -r "$dir" && -w "$dir" ]]; then
                log_info "$dir: permissions OK ✓"
            else
                log_error "$dir: permission issues"
                return 1
            fi
        fi
    done
    
    # Check SSH permissions if SSH directory exists
    if [[ -d "$HOME/.ssh" ]]; then
        local ssh_perms
        ssh_perms=$(stat -c "%a" "$HOME/.ssh" 2>/dev/null || stat -f "%A" "$HOME/.ssh" 2>/dev/null || echo "unknown")
        if [[ "$ssh_perms" == "700" ]]; then
            log_info "~/.ssh permissions: $ssh_perms ✓"
        else
            log_warning "~/.ssh permissions: $ssh_perms (should be 700)"
        fi
    fi
    
    return 0
}

function generate_report() {
    log_step "Generating health report"
    
    local report_file="$HOME/.dotfiles-health-$(date +%Y%m%d-%H%M%S).log"
    
    {
        echo "Dotfiles Health Check Report"
        echo "Generated: $(date)"
        echo "System: $(uname -s) $(uname -r) $(uname -m)"
        echo
        
        echo "=== Tool Versions ==="
        command -v chezmoi &>/dev/null && echo "chezmoi: $(chezmoi --version)"
        command -v fish &>/dev/null && echo "fish: $(fish --version)"
        command -v git &>/dev/null && echo "git: $(git --version)"
        command -v nvim &>/dev/null && echo "nvim: $(nvim --version | head -1)"
        echo
        
        echo "=== Environment ==="
        echo "SHELL: $SHELL"
        echo "PATH: $PATH"
        echo "HOME: $HOME"
        echo
        
        echo "=== Chezmoi Status ==="
        chezmoi status 2>&1 || echo "chezmoi not initialized"
        echo
        
    } > "$report_file"
    
    log_info "Health report saved to: $report_file"
}

function main() {
    log_info "Starting dotfiles health check..."
    
    local checks_passed=0
    local total_checks=6
    
    check_chezmoi && ((checks_passed++)) || true
    check_shell_tools && ((checks_passed++)) || true
    check_development_tools && ((checks_passed++)) || true
    check_config_files && ((checks_passed++)) || true
    check_shell_environment && ((checks_passed++)) || true
    check_git_config && ((checks_passed++)) || true
    check_permissions && ((checks_passed++)) || true
    
    generate_report
    
    log_step "Health Check Summary"
    log_info "Checks passed: $checks_passed/$total_checks"
    
    if [[ $checks_passed -eq $total_checks ]]; then
        log_success "All health checks passed! 🎉"
        return 0
    elif [[ $checks_passed -ge $((total_checks * 2 / 3)) ]]; then
        log_warning "Most checks passed, but some issues were found"
        return 1
    else
        log_error "Multiple health check failures detected"
        return 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi