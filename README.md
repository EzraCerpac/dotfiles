# Dotfiles

A modular and comprehensive dotfiles repository managed with [chezmoi](https://www.chezmoi.io/) for easy installation, maintenance, and portability across machines. Inspired by modern dotfiles practices with automated installation, validation, and cross-platform support.

## 🚀 Quick Start

### One-Command Installation

The simplest way to install these dotfiles is using chezmoi's one-liner:

```bash
# Install dotfiles using chezmoi
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply EzraCerpac
```

This command will:

1. Install chezmoi if not present
2. Clone this repository
3. Run all setup scripts automatically
4. Apply all configurations

### Alternative Installation

If you prefer to install step-by-step:

```bash
# Install chezmoi first
sh -c "$(curl -fsLS get.chezmoi.io)"

# Then initialize and apply dotfiles
chezmoi init --apply EzraCerpac
```

## 📁 Repository Structure

This repository uses chezmoi's native script functionality for automated setup:

```
dotfiles/
├── 📁 dot_config/                    # Maps to ~/.config/ (chezmoi managed)
│   ├── fish/                         # → ~/.config/fish/
│   ├── nvim/                         # → ~/.config/nvim/
│   ├── git/                          # → ~/.config/git/
│   └── ...                           # All other config directories
├── 📁 scripts/                       # Validation and utility scripts  
│   ├── utils/logging.sh              # Shared logging utilities
│   ├── health-check.sh               # System health check
│   └── validate.sh                   # Configuration validation
├── 📁 install-deprecated/            # Old installation scripts (no longer used)
├── 📄 run_once_before_install-chezmoi.sh.tmpl        # Install chezmoi
├── 📄 run_once_install-homebrew-macos.sh.tmpl        # Install Homebrew (macOS)
├── 📄 run_once_install-packages-macos.sh.tmpl        # Install macOS packages  
├── 📄 run_once_install-packages-linux.sh.tmpl        # Install Linux packages
├── 📄 run_once_setup-directories.sh.tmpl             # Setup directory structure
├── 📄 run_after_setup-shell.sh.tmpl                  # Final shell setup
├── Makefile                          # Simplified development commands
└── README.md                         # This file
```

The `run_once_*` and `run_after_*` scripts handle all installation and setup automatically when you run `chezmoi apply`.

## 🛠️ Daily Operations

Most operations should use chezmoi commands directly instead of the Makefile:

```bash
# Check what needs to be updated/applied
chezmoi status

# Show differences between current and target state
chezmoi diff

# Apply configurations to your system
chezmoi apply

# Update from repository and apply changes
chezmoi update

# Run system diagnostics
chezmoi doctor
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
- **gitui** - Git TUI configuration
- **jjui** - jj TUI configuration
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
# This opens the source file, apply changes with 'chezmoi apply'

# Method 2: Edit directly and re-add
$EDITOR ~/.config/fish/config.fish
chezmoi re-add ~/.config/fish/config.fish
```

### Syncing Changes

```bash
# Pull latest changes and apply
chezmoi update

# Push your changes
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

<<<<<<< HEAD

## 🚨 Migration from Existing Setup

If you have an existing dotfiles setup, you can migrate to this chezmoi-based approach:

```bash
# Backup your current dotfiles first
tar -czf dotfiles-backup-$(date +%Y%m%d).tar.gz ~/.config ~/.local/bin ~/.zshrc ~/.bashrc

# Install and initialize this repository
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply EzraCerpac/dotfiles

# If there are conflicts, resolve them manually:
chezmoi diff
chezmoi apply --dry-run  # Preview changes
chezmoi apply            # Apply when ready
```

The automated scripts will:

1. ✅ Install chezmoi and required tools
2. ✅ Set up directory structure  
3. ✅ Install platform-specific packages
4. ✅ Configure shell and development tools

=======
>>>>>>> c9740d0 (Update README.md)
>>>>>>>
## 🚨 Troubleshooting

### Common Issues

#### Installation Problems

```bash
# Check system health with chezmoi
chezmoi doctor

# Check what's managed and what needs applying  
chezmoi status
chezmoi diff

# Run validation if available
make validate
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

# If packages are missing, chezmoi scripts should have installed them
# You can re-run the installation scripts by forcing them:
chezmoi state delete-bucket --bucket=scriptState
chezmoi apply  # This will re-run all run_once_ scripts
```

#### Configuration Conflicts

```bash
# Check for configuration issues
chezmoi doctor
chezmoi verify

# See what conflicts exist
chezmoi diff

# Reset to clean state (use with caution)
chezmoi apply --force
```

### Getting Help

1. **Check the system status**: `chezmoi doctor`
2. **Validate configurations**: `make validate` (if available)  
3. **Review what's managed**: `chezmoi status`
4. **Check for differences**: `chezmoi diff`
5. **Create an issue**: [GitHub Issues](https://github.com/EzraCerpac/dotfiles/issues)

## 🔄 Daily Workflow

### Recommended Daily Commands

```bash
# Check and update dotfiles
chezmoi status      # Check what needs updating  
chezmoi update      # Pull and apply changes
chezmoi doctor      # Verify everything works

# Or use the classic command:
# make validate     # Run validation if available
```

### Making Changes

```bash
# Edit a config file
chezmoi edit ~/.config/fish/config.fish

# Add a new file
chezmoi add ~/.config/new-app/config.yaml

# Commit and push changes
chezmoi cd
git add -A && git commit -m "Add new-app configuration" && git push
exit
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

This repository uses chezmoi's native scripting capabilities:

```bash
# Scripts that run once during initial setup
run_once_before_install-chezmoi.sh.tmpl    # Install chezmoi
run_once_install-homebrew-macos.sh.tmpl    # Install Homebrew (macOS)
run_once_install-packages-macos.sh.tmpl    # Install packages (macOS)
run_once_install-packages-linux.sh.tmpl    # Install packages (Linux)
run_once_setup-directories.sh.tmpl         # Setup directory structure

# Scripts that run after applying configurations
run_after_setup-shell.sh.tmpl              # Final shell setup
```

These scripts handle:

- Installing chezmoi if not present
- OS detection and platform-specific package installation
- Setting up development tools and shell configurations
- Creating necessary directories and permissions

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
