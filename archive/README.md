# Archive

Configuration kept for reference but no longer deployed or installed. Nothing
under `archive/` is declared in `[dotfiles]` or `[tools]`, so `dots up` ignores
it. To bring one back, move it under `dotfiles/` or `templates/` at its original
path, restore its declaration from the commit that archived it (`git log --
archive/<name>`), and run `dots up`. Each tool directory mirrors the source
tree, so `git mv archive/<tool>/dotfiles/... dotfiles/...` puts files back.

| Path | Why it is here |
| --- | --- |
| `nvim/unused/` | Neovim plugin specs outside the imported `lua/plugins/` tree |
| `rift/` | Rift LaunchAgent template; Rift is the rollback window manager |
| `ghostty/` | Ghostty terminal config; WezTerm is the terminal |
| `zellij/` | Zellij config and themes; Herdr organizes sessions, tmux stays for remote hosts |
| `xonsh/` | xonsh startup files; Fish is the login shell, zsh and bash remain for other callers |
| `gitui/` | gitui themes; jjui, Hunk and delta cover review |
| `gh-dash/` | gh-dash (gh extension) dashboard config; no longer used |
| `himalaya/` | Himalaya's age-encrypted config (still encrypted); `brew:himalaya` declaration removed; no longer used |
| none (Mathpix) | `brew-cask:mathpix-snipping-tool` declaration removed, no files to keep; no longer used, app left installed |
| none (Goodnotes) | `mas:1444383602` declaration removed, no files to keep; no longer used, app left installed |
| `goose/` | goose hints and recipe; no longer used |
| `humanize-text/` | humanize-text and humanize-clipboard script, wizard, defaults and docs; no longer used |
| `latexindent/` | latexindent config; no longer used |
| `lazygit/` | lazygit tool and config; jjui, Hunk and delta cover review |
