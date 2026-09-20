# Fish completion coverage

Fish loads completion sources from the managed dotfiles and then uses the
Carapace bridge for tools that do not ship a Fish file. `config.fish` passes
`fish` explicitly to Carapace; omitting that argument makes Carapace reject the
source request and leaves the bridge empty.

The workstation profile keeps Herdr and Tinymist as small lazy shims. Each
shim asks the installed binary for its current Fish script when that command's
completion is first requested, so upgrades do not require checked-in generated
files. Herdr is verified with `herdr completion fish`; Tinymist is verified
with `tinymist completion fish`.

The audit of the installed development tools found these working providers:

- Carapace covers the common managed tools, including `age`, `atuin`, `bat`,
  `cargo`, `deno`, `eza`, `fd`, `fzf`, `gh`, `git`, `gitleaks`, `glow`,
  `lazygit`, `rclone`, `typst`, `wt`, `yt-dlp`, and `zoxide`.
- Existing Fish or shell initialization covers `atuin`, `fzf`, `jw`, `mole`,
  `openclaw`, `tv`, `wt`, and `zoxide`. Native/vendor files were also observed
  for `mise`, `jj`, `gh`, `gitleaks`, `glow`, `lazygit`, and `git-lfs`.
- Native Fish generators were checked for `rclone`, `typst`, `starship`, and
  `deno`; Carapace already provides their interactive command completions, so
  no duplicate generated files are tracked.

Some installed tools do not provide a usable Fish provider and are left
explicitly unsupported: `opencode` currently emits a Bash-only yargs script
even when passed `fish`; `yazi`/`ya`, `jjui`, `typstyle`, `xcodegen`,
`swiftformat`, `swiftlint`, and `sccache` expose neither a working Fish
generator nor a Carapace spec in this installation. They retain normal
filename completion where Fish can provide it.

Validate the integration with:

```sh
fish -n ~/.config/fish/config.fish ~/.config/fish/completions/herdr.fish
fish -i -c 'complete -C "herdr "'
fish -i -c 'complete -C "tinymist "'
```
