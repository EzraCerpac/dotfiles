# Deprecated Installation Scripts

These scripts have been replaced by chezmoi's native script functionality.

The functionality of these scripts is now handled by:
- `run_once_before_install-chezmoi.sh.tmpl`
- `run_once_install-homebrew-macos.sh.tmpl`
- `run_once_install-packages-macos.sh.tmpl`  
- `run_once_install-packages-linux.sh.tmpl`
- `run_once_setup-directories.sh.tmpl`
- `run_after_setup-shell.sh.tmpl`

These new scripts use chezmoi's templating system and run automatically during `chezmoi apply`.

## Migration

Instead of running these scripts manually, use:
```bash
sh -c "$(curl -fsLS get.chezmoi.io)" -- init --apply EzraCerpac/dotfiles
```

The old scripts are kept for reference but are no longer used.