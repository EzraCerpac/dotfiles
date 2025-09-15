# Chezmoi Guide

A comprehensive guide for managing dotfiles with chezmoi - robust, easy to use, and adaptable.

## 🎯 Why Chezmoi?

Chezmoi excels where other dotfiles managers fall short:

- **🔒 Security**: Built-in encryption for sensitive files (SSH keys, tokens)
- **🎭 Templating**: Dynamic configurations based on OS, hostname, or custom data
- **🔄 State Management**: Tracks and manages file states intelligently
- **🌐 Cross-Platform**: Seamless support for Linux, macOS, and Windows
- **🛡️ Safety**: Dry-run capability and comprehensive diff tools
- **📦 Integration**: Works with any VCS and supports external data sources

## 🚀 Core Concepts

### Source vs Target

- **Source Directory**: `~/.local/share/chezmoi` (managed by chezmoi)
- **Target Directory**: Your home directory (where configs are applied)

### File Naming Convention

Chezmoi uses special prefixes and suffixes:

```
dot_config        → ~/.config/
dot_bashrc        → ~/.bashrc
executable_script → ~/.local/bin/script (executable)
private_key       → ~/.ssh/key (600 permissions)
encrypted_token   → ~/.token (encrypted at rest)
config.yaml.tmpl  → config.yaml (processed as template)
```

## 📁 Repository Structure

Your dotfiles repository structure with chezmoi:

```
dotfiles/
├── dot_config/                    # → ~/.config/
│   ├── fish/                     # → ~/.config/fish/
│   │   ├── config.fish          
│   │   └── functions/
│   ├── nvim/                     # → ~/.config/nvim/
│   │   ├── init.lua
│   │   └── lua/
│   └── git/                      # → ~/.config/git/
│       ├── config
│       └── ignore
├── dot_local/                     # → ~/.local/
│   └── bin/                      # → ~/.local/bin/
│       ├── executable_dotfiles   # Management script
│       └── executable_update-all
├── .chezmoi.toml                 # Chezmoi configuration
├── .chezmoiignore                # Files to ignore
├── install.sh                    # One-command setup
├── migrate-to-chezmoi.sh         # Migration script
└── README.md
```

## 🛠️ Essential Commands

### Daily Operations

```bash
# Check what needs to be applied
chezmoi status

# See differences before applying
chezmoi diff

# Apply changes to your system
chezmoi apply

# Edit a managed file
chezmoi edit ~/.config/fish/config.fish

# Add a new file to management
chezmoi add ~/.new_config_file

# Update from remote repository
chezmoi update
```

### File Management

```bash
# See all managed files
chezmoi managed

# Re-add a file (if modified outside chezmoi)
chezmoi re-add ~/.config/modified/file

# Remove a file from management
chezmoi forget ~/.config/unwanted/file

# Copy a file without managing it
chezmoi cat ~/.config/fish/config.fish > /tmp/config.fish
```

### Repository Operations

```bash
# Change to source directory
chezmoi cd

# View git status in source directory
chezmoi git status

# Commit changes
chezmoi git add -A
chezmoi git commit -m "Update configurations"

# Push changes
chezmoi git push

# Exit source directory
exit

## 🔑 Using pass (password-store)

This repo uses `pass` in templates to avoid committing secrets:

- `dot_config/mcphub/servers.json.tmpl` → `{{ pass "key/github" }}` for the GitHub token
- `dot_config/raycast/private_config.json.tmpl` → `{{ pass "key/raycast" }}`

### Auto-bootstrap

On first apply, `run_once_setup-pass.sh.tmpl` will:

- Install `gnupg`, `pinentry`, and `pass` (via `brew`, `apt`, etc.)
- Configure `pinentry` (macOS uses `pinentry-mac`)
- Optionally import your GPG keys from env
- Initialize or clone `~/.password-store` and set `.gpg-id`
- Optionally seed pass entries from env

Environment variables (set before `chezmoi apply`):

- `PASS_GIT_REMOTE` – e.g., `git@github.com:<you>/password-store.git`
- `PASS_GPG_KEY_ID` – key id or fingerprint for encryption
- `PASS_GPG_PRIVATE_KEY_B64` / `PASS_GPG_PUBLIC_KEY_B64` – base64-encoded ASCII-armored keys
- `PASS_GPG_PRIVATE_KEY_FILE` / `PASS_GPG_PUBLIC_KEY_FILE` – key file paths
- `PASS_TRUST_KEY=1` – mark imported key as ultimately trusted
- `PASS_GIT_AUTHOR_NAME` / `PASS_GIT_AUTHOR_EMAIL` – git identity for the store
- `GITHUB_TOKEN` / `RAYCAST_TOKEN` – optional seeds for `key/github` and `key/raycast`

Example (macOS):

```sh
export GPG_TTY=$(tty)
export PASS_GIT_REMOTE=git@github.com:yourname/password-store.git
export PASS_GPG_KEY_ID=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
export PASS_GPG_PUBLIC_KEY_FILE=$HOME/keys/pub.asc
export PASS_GPG_PRIVATE_KEY_FILE=$HOME/keys/priv.asc
chezmoi apply
```

Tips:

- Encode for `_B64` env vars: `base64 -w0 < file.asc` (macOS: `base64 < file.asc | tr -d '\n'`)
- You’ll be prompted locally by `gpg-agent` for your key’s passphrase when needed.
```

## 🎭 Advanced Features

### Templates

Make configurations dynamic with Go templates:

```bash
# Add a template file
chezmoi add --template ~/.config/git/config

# Edit the template
chezmoi edit ~/.config/git/config
```

Example template:
```toml
[user]
    name = "{{ .name }}"
    email = "{{ .email }}"
{{- if eq .chezmoi.os "darwin" }}
[credential]
    helper = osxkeychain
{{- else if eq .chezmoi.os "linux" }}
[credential]
    helper = cache
{{- end }}
```

### Data Sources

Define data in `.chezmoi.toml`:

```toml
[data]
    name = "Ezra Cerpac"
    email = "ezra@example.com"
    
[data.packages]
    essential = ["fish", "git", "nvim"]
    development = ["zed", "lazygit", "gh"]
    
[data.features]
    use_copilot = true
    use_ai_tools = true
```

### Conditional Configuration

```bash
# OS-specific configurations
{{- if eq .chezmoi.os "darwin" }}
# macOS-specific settings
{{- else if eq .chezmoi.os "linux" }}
# Linux-specific settings  
{{- end }}

# Hostname-specific
{{- if eq .chezmoi.hostname "work-laptop" }}
# Work-specific settings
{{- end }}

# Custom feature flags
{{- if .features.use_copilot }}
# GitHub Copilot configuration
{{- end }}
```

### Encryption

Secure sensitive files:

```bash
# Add encrypted file (requires age or gpg)
chezmoi add --encrypt ~/.ssh/id_rsa

# Add encrypted template
chezmoi add --encrypt --template ~/.config/app/secrets.conf

# Set up age encryption key
age-keygen -o ~/.config/chezmoi/key.txt
echo "encryption = 'age'" >> ~/.config/chezmoi/chezmoi.toml
echo "    identity = '~/.config/chezmoi/key.txt'" >> ~/.config/chezmoi/chezmoi.toml
```

### Scripts and Automation

Automate setup tasks with scripts:

```bash
# Run once (e.g., install packages)
run_once_install-packages.sh

# Run after applying (e.g., set permissions)
run_after_setup-dotfiles.sh

# Run before applying (e.g., backup)
run_before_backup-configs.sh

# Run when specific files change
modify_font-cache.sh
```

Example script:
```bash
#!/bin/bash
# run_once_install-packages.sh.tmpl

{{- if eq .chezmoi.os "darwin" }}
# Install Homebrew packages
brew install {{ range .packages.essential }}{{ . }} {{ end }}
{{- else if eq .chezmoi.os "linux" }}
# Install apt packages  
sudo apt update && sudo apt install -y {{ range .packages.essential }}{{ . }} {{ end }}
{{- end }}
```

## 🔧 Configuration Profiles

### Machine-Specific Setup

Use chezmoi data to create machine profiles:

```toml
# .chezmoi.toml
[data]
    machine_type = "personal"  # or "work", "server"
    
[data.packages]
    {{- if eq .machine_type "personal" }}
    install = ["fish", "nvim", "raycast", "aerospace"]
    {{- else if eq .machine_type "work" }}
    install = ["fish", "nvim", "teams", "outlook"]
    {{- else }}
    install = ["fish", "nvim", "tmux"]
    {{- end }}
```

### Environment Detection

Chezmoi automatically provides system information:

```
{{ .chezmoi.os }}           # Operating system (darwin, linux, windows)
{{ .chezmoi.arch }}         # Architecture (amd64, arm64)
{{ .chezmoi.hostname }}     # Machine hostname
{{ .chezmoi.username }}     # Current user
{{ .chezmoi.homeDir }}      # Home directory path
{{ .chezmoi.sourceDir }}    # Chezmoi source directory
```

## 🚨 Migration Best Practices

### Pre-Migration Checklist

1. ✅ **Backup existing configurations**
2. ✅ **Document current setup** (what works, dependencies)
3. ✅ **Test on a VM or secondary machine first**
4. ✅ **Plan rollback strategy**
5. ✅ **Migrate during low-activity time**

### Migration Strategy

```bash
# 1. Preview migration (safe)
./migrate-to-chezmoi.sh --dry-run

# 2. Run with verbose output for debugging
./migrate-to-chezmoi.sh --verbose

# 3. Standard migration (recommended)
./migrate-to-chezmoi.sh
```

### Post-Migration Validation

```bash
# Check everything is managed
chezmoi managed | wc -l

# Verify no differences  
chezmoi diff

# Run diagnostics
chezmoi doctor

# Test applying to clean environment
chezmoi apply --dry-run
```

## 🔄 Maintenance Workflows

### Regular Updates

```bash
# Daily: Check for differences
chezmoi status

# Weekly: Update from repository
chezmoi update

# Monthly: Clean up and verify
chezmoi doctor
chezmoi verify
```

### Configuration Changes

```bash
# Method 1: Edit with chezmoi (recommended)
chezmoi edit ~/.config/fish/config.fish
chezmoi apply

# Method 2: Edit and re-add
$EDITOR ~/.config/fish/config.fish  
chezmoi re-add ~/.config/fish/config.fish

# Method 3: Bulk re-add changed files
chezmoi re-add $(chezmoi status | awk '{print $2}')
```

### Synchronization

```bash
# Push changes to repository
chezmoi cd
git add -A 
git commit -m "Update configurations"
git push
exit

# Or with auto-commit enabled in .chezmoi.toml:
[git]
    autoCommit = true
    autoPush = true
```

## 🚨 Troubleshooting

### Common Issues

**Merge conflicts after `chezmoi update`:**
```bash
# View the conflicts
chezmoi diff

# Resolve manually
chezmoi edit ~/.config/conflicted/file

# Or choose remote version
chezmoi apply --force
```

**Permissions issues:**
```bash
# Fix chezmoi directory permissions
sudo chown -R $(whoami) ~/.local/share/chezmoi

# For specific files, use private_ prefix
chezmoi add --private ~/.ssh/config
```

**Template errors:**
```bash
# Check template syntax
chezmoi cat ~/.config/templated/file

# Debug template data
chezmoi data

# Edit template
chezmoi edit ~/.config/templated/file
```

### Debugging

```bash
# Enable verbose mode
export CHEZMOI_VERBOSE=1

# Run with debug output
chezmoi --debug apply

# Check what chezmoi knows about your system
chezmoi data

# Verify specific file
chezmoi verify ~/.config/fish/config.fish
```

## 🔐 Security Best Practices

### Sensitive Data

```bash
# Encrypt sensitive files
chezmoi add --encrypt ~/.ssh/id_rsa
chezmoi add --encrypt ~/.config/app/api-keys.json

# Use private permissions
chezmoi add --private ~/.gnupg/

# Combine for maximum security
chezmoi add --encrypt --private ~/.ssh/work_key
```

### Key Management

```bash
# Generate age key for encryption
age-keygen -o ~/.config/chezmoi/key.txt

# Configure in .chezmoi.toml
[encryption]
    type = "age"
    identity = "~/.config/chezmoi/key.txt"
    recipient = "age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

## 📈 Advanced Patterns

### Machine Classification

```toml
# .chezmoi.toml.tmpl
{{- $machineType := "personal" }}
{{- if contains "work" .chezmoi.hostname }}
{{-   $machineType = "work" }}
{{- else if .chezmoi.kernel.osrelease | lower | contains "server" }}
{{-   $machineType = "server" }}
{{- end }}

[data]
    machine_type = "{{ $machineType }}"
```

### External Dependencies

```bash
# run_once_install-dependencies.sh.tmpl
#!/bin/bash

{{- if eq .chezmoi.os "darwin" }}
# Install Homebrew if not present
if ! command -v brew &> /dev/null; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Install packages
brew install {{ range .packages.homebrew }}{{ . }} {{ end }}
{{- end }}

{{- if eq .chezmoi.os "linux" }}
sudo apt update
sudo apt install -y {{ range .packages.apt }}{{ . }} {{ end }}
{{- end }}
```

### Configuration Validation

```bash
# run_after_validate-configs.sh
#!/bin/bash

# Validate fish configuration
if command -v fish &> /dev/null; then
    fish -n ~/.config/fish/config.fish && echo "✅ Fish config valid"
fi

# Validate nvim configuration
if command -v nvim &> /dev/null; then
    nvim --headless -c "checkhealth" -c "quit" && echo "✅ Neovim config valid"
fi
```

## 🎯 Tips for Success

### Start Small
1. Begin with essential configs (shell, editor, git)
2. Add applications gradually
3. Test on non-critical machines first

### Use Templates Wisely
- Template files that differ between machines
- Keep static files as-is for simplicity
- Use data variables for common substitutions

### Maintain Clean Structure
- Group related configurations logically
- Use consistent naming conventions
- Document machine-specific requirements

### Regular Maintenance
- Review `chezmoi status` weekly
- Keep templates simple and readable
- Update repository documentation as you grow

## 📚 Resources

- [Official Documentation](https://www.chezmoi.io/)
- [User Guide](https://www.chezmoi.io/user-guide/)
- [Template Reference](https://www.chezmoi.io/reference/templates/)
- [Community Examples](https://github.com/topics/chezmoi)

## 🆘 Getting Help

```bash
# Built-in help
chezmoi help
chezmoi help <command>

# System diagnostics
chezmoi doctor

# Template debugging
chezmoi cat ~/.config/templated/file
chezmoi data
```

For complex issues, the [chezmoi community](https://github.com/twpayne/chezmoi/discussions) is very helpful.
