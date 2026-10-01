# Superfile

Superfile (`spf`) replaces Yazi as the workstation terminal file manager. It is
declared as a mise `latest` tool in the workstation profile. The existing Yazi
installation and its data are retained; this migration does not uninstall Yazi
or delete its state.

## Configuration location

Superfile reads its configuration from `~/.config/superfile` (XDG) and, on
macOS, from `~/Library/Application Support/superfile`. Both paths are linked to
the same tracked source, so either lookup finds the same files. Edit the
source, not a copy: [`dotfiles/.config/superfile/config.toml`](../dotfiles/.config/superfile/config.toml)
and [`dotfiles/.config/superfile/hotkeys.toml`](../dotfiles/.config/superfile/hotkeys.toml).

## Chosen settings

| Setting | Value | Notes |
| --- | --- | --- |
| `theme` | `catppuccin-mocha` | With `transparent_background = true` and `nerdfont = true` |
| Preview | `bat` | File and image previews enabled; code previews use the existing `bat` tool |
| `editor`, `dir_editor` | `nvim` | Files and directories open in Neovim |
| `zoxide_support` | `true` | Uses the existing zoxide install and database |
| `default_sort_type` | `4` | Natural sort |
| `file_panel_extra_columns` | `2` | Size and date columns |
| `auto_check_update` | `false` | mise owns updates |
| `cd_on_quit` | `false` | Directory handoff is explicit through `Q` |
| `metadata` | `false` | Built-in metadata; no ExifTool extension |
| `ignore_missing_fields` | `true` | Missing config fields do not trigger warnings |

## Hotkeys

The hotkey file starts from the upstream v1.6.0 Vim hotkeys. Changes and the
bindings worth remembering:

| Key | Action |
| --- | --- |
| `h`, `Left`, `Backspace` | Parent directory |
| `Ctrl+C` | Quit |
| `q` | Close the current file panel |
| `Q` | Quit and change the shell directory |
| `y` / `x` / `p` | Copy / cut / paste |
| `d` | Delete |
| `r` | Rename |
| `a` | Create a file or directory |
| `z` | Zoxide jump |

## Shell wrappers

Fish and Zsh wrap `spf` so that `Q` changes the calling shell's directory. Each
wrapper:

1. Asks `command spf pl --lastdir-file` for the handoff file path instead of
   hard-coding it.
2. Removes any stale handoff file before launch, so an old `cd 'path'` line is
   never replayed.
3. Runs `command spf` with the original arguments.
4. On success, consumes the generated `cd 'path'` line and removes the file.
5. Returns Superfile's exit status unchanged.

Fish completes `spf` with ordinary filename completion. No completion
generator or generated completion file is tracked for it.

## Neovim chooser

Neovim opens Superfile in a floating terminal with `--chooser-file` pointing at
a temporary result file.

| Mapping | Starting directory |
| --- | --- |
| `<leader>-` | Folder of the current file; falls back to the working directory |
| `<leader>cw` | Neovim's working directory |
| `<leader>cy` | Toggles the active chooser, or reopens it in the last launch folder |

A selected file opens in the editor window that launched the chooser. Selecting
a directory reopens the chooser in that directory. Cancelling leaves the buffer
and window unchanged.
