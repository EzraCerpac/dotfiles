#!/usr/bin/env bash

set -euo pipefail

# Validation script for dotfiles configuration
# Checks syntax and validates configuration files

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/utils/logging.sh"

function validate_fish_configs() {
    log_step "Validating Fish configuration"
    
    local fish_config_dir="$HOME/.config/fish"
    
    if [[ ! -d "$fish_config_dir" ]]; then
        log_warning "Fish config directory not found"
        return 1
    fi
    
    # Check if Fish can parse the config
    if command -v fish &>/dev/null; then
        log_info "Testing Fish configuration syntax..."
        if fish -n -c 'source ~/.config/fish/config.fish' 2>/dev/null; then
            log_success "Fish configuration syntax is valid"
        else
            log_error "Fish configuration has syntax errors"
            fish -n -c 'source ~/.config/fish/config.fish'
            return 1
        fi
    else
        log_warning "Fish not installed, skipping syntax validation"
    fi
    
    return 0
}

function validate_git_configs() {
    log_step "Validating Git configuration"
    
    local git_config_file="$HOME/.config/git/config"
    
    if [[ ! -f "$git_config_file" ]]; then
        log_warning "Git config file not found at $git_config_file"
        return 1
    fi
    
    # Test if git config is valid
    if git config --file "$git_config_file" -l &>/dev/null; then
        log_success "Git configuration is valid"
    else
        log_error "Git configuration has errors"
        return 1
    fi
    
    # Check for required settings
    local required_settings=("user.name" "user.email")
    for setting in "${required_settings[@]}"; do
        if git config --global "$setting" &>/dev/null; then
            log_info "$setting is set"
        else
            log_warning "$setting is not set in global config"
        fi
    done
    
    return 0
}

function validate_nvim_configs() {
    log_step "Validating Neovim configuration"
    
    local nvim_config_dir="$HOME/.config/nvim"
    
    if [[ ! -d "$nvim_config_dir" ]]; then
        log_warning "Neovim config directory not found"
        return 1
    fi
    
    if command -v nvim &>/dev/null; then
        log_info "Testing Neovim configuration..."
        # Test basic neovim startup
        if run_with_spinner "Checking nvim startup" bash -c "timeout 10 nvim --headless -c 'quit' 2>/dev/null"; then
            log_success "Neovim configuration loads successfully"
        else
            log_error "Neovim configuration has issues"
            return 1
        fi
    else
        log_warning "Neovim not installed, skipping validation"
    fi
    
    return 0
}

function validate_starship_config() {
    log_step "Validating Starship configuration"
    
    local starship_config="$HOME/.config/starship.toml"
    
    if [[ ! -f "$starship_config" ]]; then
        log_info "Starship config not found (using defaults)"
        return 0
    fi
    
    if command -v starship &>/dev/null; then
        log_info "Testing Starship configuration..."
        if starship config 2>/dev/null | grep -q "starship"; then
            log_success "Starship configuration is valid"
        else
            log_error "Starship configuration has issues"
            return 1
        fi
    else
        log_warning "Starship not installed, skipping validation"
    fi
    
    return 0
}

function validate_chezmoi_templates() {
    log_step "Validating chezmoi templates"
    
    if ! command -v chezmoi &>/dev/null; then
        log_warning "chezmoi not installed, skipping template validation"
        return 1
    fi
    
    local source_dir
    source_dir=$(chezmoi source-path 2>/dev/null) || {
        log_warning "chezmoi not initialized, skipping template validation"
        return 1
    }
    
    # Check for template files
    if find "$source_dir" -name "*.tmpl" -type f | grep -q .; then
        log_info "Found template files, checking syntax..."
        
        # Test template parsing
        if run_with_spinner "Checking template syntax" bash -c 'chezmoi execute-template --init false </dev/null &>/dev/null'; then
            log_success "Template syntax is valid"
        else
            log_error "Template syntax errors found"
            chezmoi execute-template --init false </dev/null
            return 1
        fi
    else
        log_info "No template files found"
    fi
    
    return 0
}

function validate_shell_scripts() {
    log_step "Validating shell scripts"
    
    local script_dirs=(
        "$HOME/.local/bin"
        "$(dirname "$0")"
        "$(dirname "$0")/../install"
    )
    
    local issues=0
    
    for dir in "${script_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            log_info "Checking scripts in $dir"
            
            # Find shell scripts
            while IFS= read -r -d '' script; do
                if [[ -x "$script" ]] && file "$script" 2>/dev/null | grep -q "shell script"; then
                    log_debug "Checking $script"
                    
                    # Basic syntax check with bash -n
                    if bash -n "$script" 2>/dev/null; then
                        log_debug "$script: syntax OK"
                    else
                        log_error "$script: syntax error"
                        ((issues++))
                    fi
                fi
            done < <(find "$dir" -type f -print0 2>/dev/null)
        fi
    done
    
    if [[ $issues -eq 0 ]]; then
        log_success "All shell scripts have valid syntax"
        return 0
    else
        log_error "Found $issues shell script syntax errors"
        return 1
    fi
}

function validate_symlinks() {
    log_step "Validating symlinks"
    
    local broken_links=()
    
    # Check common directories for broken symlinks
    local dirs_to_check=(
        "$HOME/.config"
        "$HOME/.local/bin"
        "$HOME"
    )
    
    for dir in "${dirs_to_check[@]}"; do
        if [[ -d "$dir" ]]; then
            while IFS= read -r -d '' link; do
                if [[ -L "$link" ]] && [[ ! -e "$link" ]]; then
                    broken_links+=("$link")
                fi
            done < <(find "$dir" -maxdepth 3 -type l -print0 2>/dev/null)
        fi
    done
    
    if [[ ${#broken_links[@]} -eq 0 ]]; then
        log_success "No broken symlinks found"
        return 0
    else
        log_error "Found ${#broken_links[@]} broken symlinks:"
        for link in "${broken_links[@]}"; do
            log_error "  $link -> $(readlink "$link")"
        done
        return 1
    fi
}

function validate_file_permissions() {
    log_step "Validating file permissions"
    
    local permission_issues=0
    
    # Check SSH files if they exist
    if [[ -d "$HOME/.ssh" ]]; then
        # SSH directory should be 700
        local ssh_perms
        ssh_perms=$(stat -c "%a" "$HOME/.ssh" 2>/dev/null || stat -f "%A" "$HOME/.ssh" 2>/dev/null)
        if [[ "$ssh_perms" != "700" ]]; then
            log_error "~/.ssh has incorrect permissions: $ssh_perms (should be 700)"
            ((permission_issues++))
        fi
        
        # SSH private keys should be 600
        find "$HOME/.ssh" -type f -name "id_*" ! -name "*.pub" | while read -r keyfile; do
            local key_perms
            key_perms=$(stat -c "%a" "$keyfile" 2>/dev/null || stat -f "%A" "$keyfile" 2>/dev/null)
            if [[ "$key_perms" != "600" ]]; then
                log_error "$keyfile has incorrect permissions: $key_perms (should be 600)"
                ((permission_issues++))
            fi
        done
    fi
    
    # Check that executable scripts are actually executable
    local script_dirs=("$HOME/.local/bin")
    for dir in "${script_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            find "$dir" -type f | while read -r file; do
                if file "$file" 2>/dev/null | grep -q "shell script" && [[ ! -x "$file" ]]; then
                    log_warning "$file is a shell script but not executable"
                fi
            done
        fi
    done
    
    if [[ $permission_issues -eq 0 ]]; then
        log_success "File permissions look correct"
        return 0
    else
        log_error "Found $permission_issues permission issues"
        return 1
    fi
}

function main() {
    log_info "Starting dotfiles validation..."
    
    local validations_passed=0
    local total_validations=7
    
    validate_fish_configs && ((validations_passed++)) || true
    validate_git_configs && ((validations_passed++)) || true
    validate_nvim_configs && ((validations_passed++)) || true
    validate_starship_config && ((validations_passed++)) || true
    validate_chezmoi_templates && ((validations_passed++)) || true
    validate_shell_scripts && ((validations_passed++)) || true
    validate_symlinks && ((validations_passed++)) || true
    validate_file_permissions && ((validations_passed++)) || true
    
    log_step "Validation Summary"
    log_info "Validations passed: $validations_passed/$total_validations"
    
    if [[ $validations_passed -eq $total_validations ]]; then
        log_success "All validations passed! ✓"
        return 0
    elif [[ $validations_passed -ge $((total_validations * 2 / 3)) ]]; then
        log_warning "Most validations passed, but some issues were found"
        return 1
    else
        log_error "Multiple validation failures detected"
        return 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
