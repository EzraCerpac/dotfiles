# Adding and editing configs

Edit ordinary symlinked files at their native target; the target is the tracked source. Edit a Tera template with `--apply` to render and deploy the result. Add globally shared links with `-g`, or scope an entry to a profile:

```bash
mise -C ~/.config/mise bootstrap dotfiles edit ~/.config/fish/config.fish
mise -C ~/.config/mise bootstrap dotfiles edit --apply ~/.config/git/config
mise -C ~/.config/mise bootstrap dotfiles add --mode symlink -g ~/.config/new-app/config.yaml
mise -C ~/.config/mise bootstrap dotfiles add --mode symlink --path ~/.config/mise/config.workstation.toml ~/.config/new-app/config.yaml
```

Change `workstation` to `nas` for a profile-specific entry. Use `dots up` for declared package/tool updates; it does not publish source.

## Cross-platform notes

- Native packages and binary backends declare their supported Mac architectures
- OS and profile variants select the appropriate files and package declarations
- Tera templates provide small machine-specific values; ordinary linked files remain directly editable
- The `workstation` or `nas` role must be selected explicitly in local mise configuration

## Shared static groups

Bat and Neovim use native mise dotfile groups, requiring mise 2026.10.3 or
newer on each selected host. The shared configuration explicitly selects
`bat` and `nvim`; their source trees are `dotfiles/.config/bat` and
`dotfiles/.config/nvim`. New source files in these trees are included automatically.
Each file retains its own absolute symlink, while unrelated application state
in the destination directory stays unmanaged. Templates, renamed links and
profile-specific files keep their individual declarations.
