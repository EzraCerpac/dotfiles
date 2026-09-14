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

# Portable preferences previously stored as fish universal variables.
set -gx CARAPACE_BRIDGES 'fish,bash,inshellisense'
set -gx fifc_editor nvim
set -g fifc_keybinding "\x14"
set -g fifc_open_keybinding ctrl-o

# Enable vi key bindings
fish_vi_key_bindings

if status is-interactive
    # Commands to run in interactive sessions can go here
    if command -q atuin
        atuin init fish --disable-up-arrow | source
    end

    if command -q tv
        tv init fish | source
    end

    # Reapply our preferred bindings after third-party init scripts.
    fish_user_key_bindings
end

# Silence the default greeting
function fish_greeting
end

# extensions
if command -q zoxide
    zoxide init fish --cmd cd | source
end
if command -q starship
    starship init fish | source
end
# ---------- Default editor ----------
set -gx EDITOR nvim
set -gx VISUAL $EDITOR
set -gx GIT_EDITOR $EDITOR

# ---------- XDG Config ----------
set -gx XDG_CONFIG_HOME $HOME/.config
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

alias cc='JJ_CONFIG="$HOME/.config/jj/config.toml:$HOME/.config/jj/agent-config.toml" claude --dangerously-skip-permissions'
alias oc='JJ_CONFIG="$HOME/.config/jj/config.toml:$HOME/.config/jj/agent-config.toml" opencode'

if command -q wt
    wt config shell init fish | source
end

if command -q jw
    command jw shell init fish | source
end

function wto --description "Create or switch a worktree and launch OpenCode"
    worktree-opencode $argv
end

function prdiff --description "Review a pull request diff in diffnav"
    prdiff-review $argv
end
# ---------- Completions ----------
if command -q carapace
    carapace _carapace 2>/dev/null | source
end

if command -q mole
    set -l output (mole completion fish 2>/dev/null); and echo "$output" | source
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
# OpenClaw Completion (lazy-loaded to speed up shell startup)
function __openclaw_lazy_load --on-event fish_preexec
    string match -q "openclaw*" -- $argv[1]
    and openclaw completion --shell fish 2>/dev/null | source
    and functions --erase __openclaw_lazy_load
end

# Keep mise activation after all startup setup.
if command -q mise
    mise activate fish | source
end

# Prefer the standalone tools directory over mise-managed executables.
if test -d "$HOME/.local/bin"
    fish_add_path --global --path --prepend --move "$HOME/.local/bin"
end
