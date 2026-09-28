# ---------- XDG Config ----------
set -gx XDG_CONFIG_HOME $HOME/.config

if status is-interactive
    if test "$__CFBundleIdentifier" = com.openai.codex
        or test "$TERM_PROGRAM" = WezTerm
        or test "$HERDR_ENV" = 1
        set -e NO_COLOR
        if test "$TERM" = dumb
            set -gx TERM xterm-256color
        end
    end
end

# Portable paths kept previously in fish_user_paths. Add only directories
# that exist, in reverse order so prepend preserves their intended priority.
# ~/.local/bin is needed here already: the standalone mise lives there.
set -l portable_paths \
    /usr/local/bin \
    "$HOME/bin" \
    "$HOME/.cargo/bin" \
    "$HOME/.grok/bin" \
    "$HOME/.local/bin"
for path in $portable_paths
    if test -d "$path"
        fish_add_path --global --path --prepend --move "$path"
    end
end

# Activate mise in every shell, scripts included, so they find managed tools.
# Fresh login shells (e.g. herdr tabs) start without shims on PATH.
if command -q mise
    mise activate fish | source
end

# Portable preferences previously stored as fish universal variables.
set -gx CARAPACE_BRIDGES 'fish,bash,inshellisense'
set -gx fifc_editor nvim
set -g fifc_keybinding "\x14"
set -g fifc_open_keybinding ctrl-o

# ---------- Default editor ----------
set -gx EDITOR nvim
set -gx VISUAL $EDITOR
set -gx GIT_EDITOR $EDITOR

# Silence the default greeting
function fish_greeting
end

# Replace ls with eza
alias ls='eza --icons=auto --group-directories-first --git'
alias la='eza -a --icons=auto --group-directories-first --git'
alias ll='eza -la --icons=auto --group-directories-first --git'
alias tree='eza --tree --level=2 --icons=auto --git'

# ---------- Navigation aliases ----------
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias ......='cd ../../../../..'

# ---------- Editor and tools ----------
alias v='nvim'
alias nvim-local='NVIM_LOCAL_ROOT=1 nvim'
alias vl='nvim-local'

# JJ_CONFIG replaces the default search path, so list conf.d (commit signing) too.
alias cc='JJ_CONFIG="$HOME/.config/jj/config.toml:$HOME/.config/jj/conf.d:$HOME/.config/jj/agent-config.toml" claude'
alias oc='JJ_CONFIG="$HOME/.config/jj/config.toml:$HOME/.config/jj/conf.d:$HOME/.config/jj/agent-config.toml" opencode'

function wto --description "Create or switch a worktree and launch OpenCode"
    worktree-opencode $argv
end

function prdiff --description "Review a pull request diff in Hunk"
    prdiff-review $argv
end

# ---------- Julia ----------
alias pluto="julia --banner=no -e 'using Pluto; Pluto.run(auto_reload_from_file=true, require_secret_for_access=false, require_secret_for_open_links=false)'"
alias lss='julia -e "import LiveServer as LS; LS.serve(launch_browser=true)"'

# ---------- Gitlogue ----------
# Browse commits and launch gitlogue on selection
function glf
    gitlogue-select browse $argv
end

# Interactive gitlogue menu
function gitlogue-menu
    gitlogue-select menu $argv
end

# Prompt, key bindings, completions and cd integration only matter at a
# prompt. Scripts skip them, and interactive shells source cached init output
# (see functions/__dots_source_init.fish) instead of spawning each tool.
if status is-interactive
    fish_vi_key_bindings

    # Arrow-key recall belongs to this terminal session. Atuin still records
    # commands persistently and provides cross-session search on Ctrl-R.
    set -g fish_history ''

    __dots_source_init atuin init fish --disable-up-arrow
    __dots_source_init tv init fish
    __dots_source_init zoxide init fish --cmd cd
    __dots_source_init starship init fish --print-full-init
    __dots_source_init wt config shell init fish
    __dots_source_init jw shell init fish
    # Carapace cannot infer the shell when stdin is a Fish source pipeline.
    # Keep the shell explicit so its bridge covers the managed CLI set.
    __dots_source_init carapace _carapace fish
    __dots_source_init mole completion fish

    # OpenClaw completion, loaded on first use.
    function __openclaw_lazy_load --on-event fish_preexec
        string match -q "openclaw*" -- $argv[1]
        and openclaw completion --shell fish 2>/dev/null | source
        and functions --erase __openclaw_lazy_load
    end

    # Reapply our preferred bindings after third-party init scripts.
    fish_user_key_bindings
end

# mise's hook reorders PATH; keep the standalone tools directory first.
if test -d "$HOME/.local/bin"
    fish_add_path --global --path --prepend --move "$HOME/.local/bin"
end
