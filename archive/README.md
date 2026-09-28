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
| `gitui/` | gitui themes; jjui, lazygit, Hunk and delta cover review |
