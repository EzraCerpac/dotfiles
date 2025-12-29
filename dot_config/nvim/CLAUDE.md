# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a **LazyVim-based Neovim configuration** managed by chezmoi. The config is located at `~/.local/share/chezmoi/dot_config/nvim` but installed plugins reside in `~/.local/share/nvim/lazy/`.

## Key Architecture

### Directory Structure
- `init.lua` - Entry point, bootstraps lazy.nvim and loads config
- `lua/config/` - Core configuration (lazy.lua, options.lua, keymaps.lua, autocmds.lua)
- `lua/plugins/` - Individual plugin configurations (one file per plugin)
- `lua/custom/` - Custom utilities and commands (e.g., `latex_to_typst.lua`)
- `lua/overseer/` - Overseer task templates

### Plugin Management
- Uses **lazy.nvim** plugin manager
- Plugins defined in `lua/plugins/` as individual `.lua` files
- LazyVim core plugins imported from `LazyVim/LazyVim`
- Config inheritance: defaults from LazyVim + overrides in this repo

### Notable Customizations
- **Picker**: fzf-lua (configured in `keymaps.lua`)
- **Completion**: blink.cmp (default, with fallback to nvim-cmp)
- **File explorer**: mini.files (bound to `<leader>e`)
- **Build tasks**: Overseer (`lua/plugins/overseer.lua`)

### Keybindings
- `<leader>qr` - Restart Neovim
- `gh` - Jump to first char of line (Helix-like)
- `gl` - Jump to last char of line (Helix-like)
- `<leader>e` - Open mini.files for current file directory
- `<localleader>tl` - Convert LaTeX to Typst (visual mode)
- `<leader>tl` - Paste converted Typst from clipboard

### Environment Variables
- `XDG_CONFIG_HOME` set to `~/.config` (for lazygit)

## Commands

### Plugin Management

```bash
:Lazy         # Open LazyVim UI
:Lazy sync    # Sync/install plugins
:Lazy update  # Update plugins
```

### Configuration Reloading

```bash
:Restart      # Restart Neovim to reload config
```

### Task/Build Commands

```bash
:OverseerRun  # Run a task
:OverseerLoadTemplateBuilder  # Create new task template
```

## Related Documentation
- [LazyVim Documentation](https://lazyvim.github.io/installation)
- Plugin configs often reference LazyVim source at `lua/lazyvim/config/`
