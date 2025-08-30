# Dotfiles

A modular and comprehensive dotfiles repository managed with [chezmoi](https://www.chezmoi.io/) for easy installation, maintenance, and portability across machines. Inspired by modern dotfiles practices with automated installation, validation, and cross-platform support.

## 🚀 Quick Start

### One-Command Installation

```bash
# Complete setup with automated installation
curl -fsSL https://raw.githubusercontent.com/EzraCerpac/dotfiles/main/setup.sh | bash
```

### Alternative Methods

```bash
# Using chezmoi directly
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply EzraCerpac

# Using make (if repository is already cloned)
make install

# For existing installations
make update
```

## 📁 Repository Structure

This repository uses a modular structure with automated installation and management:

```
dotfiles/
├── 📁 install/                 # Platform-specific installation scripts
│   ├── common/setup.sh        # Cross-platform common setup
│   ├── macos/setup.sh          # macOS-specific installation (Homebrew, defaults)
│   └── linux/setup.sh          # Linux-specific installation (apt, dnf)
├── 📁 scripts/                 # Maintenance and utility scripts
│   ├── utils/logging.sh        # Shared logging utilities
│   ├── health-check.sh         # Comprehensive system health check
│   ├── validate.sh             # Configuration validation
│   └── backup/create-backup.sh # Automated backup system
├── 📁 dot_config/              # Maps to ~/.config/ (chezmoi managed)
│   ├── fish/                   # → ~/.config/fish/
│   ├── nvim/                   # → ~/.config/nvim/
│   ├── git/                    # → ~/.config/git/
│   └── ...                     # All other config directories
├── setup.sh                    # One-command installation script
├── Makefile                    # Common operations and workflows
├── Dockerfile                  # Docker testing environment
└── README.md                   # This file
```

## 🛠️ Management Commands

### Daily Operations
```bash
# Update dotfiles from repository
make update

# Check what would be changed
make status

# Show differences
make diff

# Apply configurations
make apply

# Run health check
make health

# Validate configurations
make validate
```

### Development & Testing
```bash
# Watch for changes (requires watchexec)
make watch

# Test in Docker environment
make docker-test

# Run comprehensive health check
make health

# Create backup
make backup
```

### Git Operations
```bash
# Add and commit changes
make git-add
make git-commit MSG="your message"

# Push to remote
make git-push

# Combined commit and push
make commit-and-push MSG="your message"
```

### Using chezmoi directly

```bash
# Check status and differences
chezmoi status
chezmoi diff

# Edit configurations (opens in your $EDITOR)
chezmoi edit ~/.config/fish/config.fish

# Apply changes to your system
chezmoi apply

# Add new files to management
chezmoi add ~/.new_config_file

# Update from repository
chezmoi update
```

## 📦 Available Configurations

### Core System

- **fish** - Fish shell with vi bindings and custom functions
- **starship** - Cross-shell prompt with git integration  
- **git** - Git configuration with user settings and aliases
- **jj** - Jujutsu VCS configuration

### Development

- **nvim** - Neovim with LazyVim configuration
- **zed** - Zed editor configuration
- **opencode** - VS Code configuration  
- **ruff** - Python formatter and linter settings
- **uv** - Python package manager configuration
- **lazygit** - Git TUI configuration
- **gh** - GitHub CLI configuration
- **gh-copilot** - GitHub Copilot CLI settings

### Terminal & UI

- **ghostty** - Terminal emulator configuration
- **iterm2** - iTerm2 terminal settings  
- **zellij** - Terminal multiplexer configuration
- **sketchybar** - macOS menu bar customization
- **btop** - System monitor configuration
- **karabiner** - Keyboard remapping (macOS)
- **aerospace** - Window manager (macOS)

### Applications  

- **raycast** - Raycast launcher configuration
- **qBittorrent** - BitTorrent client settings
- **ParaView** - ParaView scientific visualization
- **atuin** - Shell history synchronization
- **bat** - Better cat with syntax highlighting
- And many more...

## 🔧 Features

### Automated Installation
- **Cross-platform support**: macOS and Linux (Ubuntu/Fedora)
- **Package management**: Homebrew (macOS), apt/dnf (Linux)
- **Shell setup**: Automatic Fish shell configuration
- **Tool installation**: Modern CLI tools (bat, eza, fzf, rg, etc.)

### Health & Validation
- **Health checks**: Comprehensive system and configuration validation
- **Syntax validation**: Automatic checking of config file syntax
- **Broken symlink detection**: Find and report broken symbolic links
- **Permission validation**: Check file and directory permissions

### Backup & Recovery
- **Automated backups**: Timestamped configuration backups
- **Package lists**: Export installed packages for restoration
- **System information**: Capture environment details
- **Retention management**: Automatic cleanup of old backups

### Development Support
- **Docker testing**: Test configurations in isolated environment
- **Live reloading**: Watch mode for development
- **Template validation**: Check chezmoi template syntax
- **Git integration**: Streamlined version control workflows

## 🔧 Configuration

### Adding New Files

```bash
# Add any file to chezmoi management
chezmoi add ~/.config/new-app/config.yaml
```

### Templates and Data

chezmoi supports powerful templating. Edit the chezmoi config:

```bash
chezmoi edit-config
```

Example `.chezmoi.toml`:

```toml
[data]
    name = "Your Name"
    email = "your.email@example.com"
    
[edit]
    command = "nvim"
    
[git]
    autoCommit = true
    autoPush = true
```

### Conditional Files

Use chezmoi's templating for machine-specific configs:

```bash
# Create OS-specific configs
chezmoi add --template ~/.config/app/config.yaml

# Then edit to include conditions:
# {{- if eq .chezmoi.os "darwin" }}
# macos_setting = true
# {{- else if eq .chezmoi.os "linux" }}  
# linux_setting = true
# {{- end }}
```

## 🔄 Daily Workflow

### Editing Configurations

```bash
# Method 1: Edit with chezmoi (recommended)
chezmoi edit ~/.config/fish/config.fish
# This opens the source file, and you can apply with 'chezmoi apply'

# Method 2: Edit directly and re-add
$EDITOR ~/.config/fish/config.fish
chezmoi re-add ~/.config/fish/config.fish
```

### Syncing Changes

```bash
# Pull latest changes and apply
chezmoi update

# Push your changes (if auto-push is disabled)
chezmoi cd
git add -A && git commit -m "Update configurations" && git push
exit  # Return to original directory
```

### Managing Files

```bash
# See what's managed
chezmoi managed

# See what needs to be applied
chezmoi status  

# See differences
chezmoi diff ~/.config/nvim/init.lua

# Remove a file from management
chezmoi forget ~/.config/old-app/config.conf
```

## 🚨 Migration from Existing Setup

If you have an existing dotfiles setup, use the migration script:

```bash
# Preview what will be migrated (dry run)
./migrate-to-chezmoi.sh --dry-run

# Perform the migration (creates automatic backup)
./migrate-to-chezmoi.sh

# Or with verbose output
./migrate-to-chezmoi.sh --verbose
```

The migration script will:

1. ✅ Create a comprehensive backup of your current setup
2. ✅ Install chezmoi if not present  
3. ✅ Initialize chezmoi repository
4. ✅ Convert all configuration directories
5. ✅ Set up ignore patterns and templates
6. ✅ Create management scripts
7. ✅ Provide rollback capability on failure

## 🚨 Troubleshooting

### Common Issues

#### Installation Problems
```bash
# Check system health
make health

# Validate configurations
make validate

# Run Docker test
make docker-test
```

#### Permission Issues
```bash
# Fix common permission problems
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_*
chmod +x ~/.local/bin/*
```

#### Tool Not Found
```bash
# Check if tools are properly installed
which fish nvim git
echo $PATH | tr ':' '\n' | grep ".local/bin"

# Reinstall missing tools
./install/macos/setup.sh  # macOS
./install/linux/setup.sh  # Linux
```

#### Configuration Conflicts
```bash
# Check for configuration issues
chezmoi doctor
chezmoi verify

# Reset to clean state (use with caution)
make reset
```

### Getting Help

1. **Check the health status**: `make health`
2. **Validate configurations**: `make validate`
3. **Review logs**: Check `~/.dotfiles-health-*.log`
4. **Test in isolation**: Use `make docker-test`
5. **Create an issue**: [GitHub Issues](https://github.com/EzraCerpac/dotfiles/issues)

## 🔄 Daily Workflow

### Recommended Daily Commands
```bash
# Quick health check and update
make daily-update

# Or step by step:
make status        # Check what needs updating
make update        # Pull and apply changes
make health        # Verify everything works
```

### Making Changes
```bash
# Edit a config file
chezmoi edit ~/.config/fish/config.fish

# Add a new file
chezmoi add ~/.config/new-app/config.yaml

# Commit and push changes
make commit-and-push MSG="Add new-app configuration"
```

### Common Issues

**Permission errors:**

```bash
# Fix ownership if needed
sudo chown -R $(whoami) ~/.local/share/chezmoi
```

**Merge conflicts:**

```bash
# View differences
chezmoi diff

# Edit problematic files  
chezmoi edit ~/.config/problematic/file

# Apply after resolving
chezmoi apply
```

**Lost changes:**

```bash
# See what chezmoi would change
chezmoi diff

# Re-add modified files
chezmoi re-add ~/.config/modified/file
```

### Advanced Troubleshooting

```bash
# Run diagnostics
chezmoi doctor

# Check chezmoi status
chezmoi data

# View detailed diff
chezmoi diff --format=unified

# See what's managed vs what's not
chezmoi managed
ls ~/.config/ | grep -v "$(chezmoi managed | sed 's|.*/||')"
```

## 🔧 Advanced Features

### Encrypted Files

Store sensitive data securely:

```bash
# Add encrypted file (requires age or gpg)
chezmoi add --encrypt ~/.ssh/private_key

# chezmoi will prompt for passphrase on apply
```

### Scripts and Hooks

Automate setup with scripts:

```bash
# Create run-once script
chezmoi add --template ~/.local/share/chezmoi/run_once_install-packages.sh

# Create script that runs after applying
chezmoi add --template ~/.local/share/chezmoi/run_after_setup-permissions.sh
```

### External Dependencies

Manage external tools in `.chezmoi.toml`:

```toml
[data.packages]
    brew = ["fish", "nvim", "git", "starship"]
    apt = ["fish", "neovim", "git"]
```

## 🏠 Directory Conventions

This repository follows XDG Base Directory specifications and chezmoi conventions:

- **Configuration files**: `dot_config/` → `~/.config/`
- **Local files**: `dot_local/` → `~/.local/`
- **Hidden files**: `dot_file` → `~/.file`
- **Executable files**: `executable_*` prefix
- **Templates**: `.tmpl` suffix
- **Encrypted files**: `encrypted_*` prefix

## 🤝 Contributing

### Adding New Configurations

1. Add the file to chezmoi: `chezmoi add ~/.config/new-app/config`
2. Edit if needed: `chezmoi edit ~/.config/new-app/config`  
3. Apply to test: `chezmoi apply`
4. Commit: `chezmoi cd && git add -A && git commit -m "Add new-app config"`

### Sharing Configurations

```bash
# Fork this repository
# Make your changes
chezmoi cd
git remote add origin https://github.com/yourusername/dotfiles.git
git push -u origin main
```

## 📚 Resources

- [chezmoi User Guide](https://www.chezmoi.io/user-guide/)
- [chezmoi Quick Start](https://www.chezmoi.io/quick-start/)
- [chezmoi Reference](https://www.chezmoi.io/reference/)
- [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html)

## 🆘 Getting Help

```bash
# Show help for chezmoi
chezmoi help

# Show help for the dotfiles wrapper
./dotfiles --help

# Run system diagnostics
chezmoi doctor

# Check current status
chezmoi status
```

For issues or questions, open an issue in this repository.
