# Migration to Chezmoi Native Scripts

This document explains the migration from custom installation scripts to chezmoi's native script functionality.

## Changes Made

### Before (Complex Custom Scripts)
- `setup.sh` (302 lines) - Complex installation script with OS detection
- `Makefile` (200+ lines) - Wrapper commands around chezmoi
- `install/macos/setup.sh` - macOS-specific installation
- `install/linux/setup.sh` - Linux-specific installation 
- `install/common/setup.sh` - Common setup functionality

### After (Native Chezmoi Scripts)
- `run_once_before_install-chezmoi.sh.tmpl` - Install chezmoi if needed
- `run_once_install-homebrew-macos.sh.tmpl` - macOS Homebrew installation
- `run_once_install-packages-macos.sh.tmpl` - macOS packages via Homebrew
- `run_once_install-packages-linux.sh.tmpl` - Linux packages via apt/dnf
- `run_once_setup-directories.sh.tmpl` - Directory structure setup
- `run_after_setup-shell.sh.tmpl` - Final shell configuration
- `Makefile` (45 lines) - Simplified development commands only

## Benefits

1. **Reduced Complexity**: 300+ lines of custom shell code eliminated
2. **Native chezmoi Integration**: Uses chezmoi's built-in script execution
3. **Better OS Detection**: Leverages chezmoi's templating for OS-specific logic
4. **Automatic Execution**: Scripts run automatically during `chezmoi apply`
5. **Idempotent**: `run_once_` scripts only run once, preventing repeated execution

## New Installation

Users can now install with a single command:
```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply EzraCerpac/dotfiles
```

## Script Execution Order

1. `run_once_before_install-chezmoi.sh.tmpl` - Ensures chezmoi is installed
2. `run_once_install-homebrew-macos.sh.tmpl` - macOS only: Install Homebrew
3. `run_once_install-packages-*.sh.tmpl` - Install platform-specific packages
4. `run_once_setup-directories.sh.tmpl` - Create directory structure
5. All configurations applied from `dot_config/`
6. `run_after_setup-shell.sh.tmpl` - Final shell setup and completion message

## Rollback

The old scripts are preserved in `install-deprecated/` for reference.