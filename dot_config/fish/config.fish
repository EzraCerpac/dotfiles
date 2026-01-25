# Homebrew (Apple Silicon first)
fish_add_path /opt/homebrew/bin /opt/homebrew/sbin
fish_add_path /usr/local/bin /usr/local/sbin # Rosetta fallback only
fish_add_path $HOME/.local/bin

# Enable vi key bindings
fish_vi_key_bindings

if status is-interactive
    # Commands to run in interactive sessions can go here
    atuin init fish --disable-up-arrow | source
    bind \cr _atuin_search
    bind -M insert \cr _atuin_search
end

# Auto-Warpify
status --is-interactive; and printf 'P$f{"hook": "SourcedRcFileForWarp", "value": { "shell": "fish", "uname": "Darwin" }}�'

# Silence the default greeting
function fish_greeting
end

# extensions
zoxide init fish --cmd cd | source
starship init fish | source

# Add Rust cargo to PATH
fish_add_path ~/.cargo/bin

# Add uutils-coreutils to PATH (unprefixed commands)
fish_add_path /opt/homebrew/opt/uutils-coreutils/libexec/uubin

# ---------- Default editor ----------
set -gx EDITOR /opt/homebrew/bin/nvim
set -gx VISUAL $EDITOR
set -gx GIT_EDITOR $EDITOR # Fallback for tools that check this var

# ---------- XDG Config ----------
set -gx XDG_CONFIG_HOME /Users/ezracerpac/.config

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
# alias -='cd -'  # Doesn't work apparently

# ---------- Editor and tools ----------
alias v='nvim'
alias nvim-local='NVIM_LOCAL_ROOT=1 nvim'
alias vl='nvim-local'

fzf --fish | source # Set up fzf key bindings

alias claude='claude --dangerously-skip-permissions'
alias cc='claude'

# ---------- Tailscale ----------
alias tailscale='/Applications/Tailscale.app/Contents/MacOS/Tailscale'

# ---------- Completions ----------
# set -Ux fifc_editor nvim
# set -U fifc_keybinding \ct # Bind fzf completions to ctrl-x
set -Ux CARAPACE_BRIDGES 'fish,bash,inshellisense' # optional (removed zsh)
carapace _carapace | source

set -l output (mole completion fish 2>/dev/null); and echo "$output" | source

# ---------- Julia ----------
alias pluto="julia --banner=no -e 'using Pluto; Pluto.run(auto_reload_from_file=true)'"
alias lss='julia -e "import LiveServer as LS; LS.serve(launch_browser=true)"'

# ---------- Gitlogue ----------
# Browse commits and launch gitlogue on selection
function glf
    set -l commit (git log --oneline --color=always $argv | \
        fzf --ansi \
            --no-sort \
            --preview 'git show --stat --color=always {1}' \
            --preview-window=right:60% | \
        awk '{print $1}')
    test -n "$commit"; and gitlogue --commit "$commit"
end

# Interactive gitlogue menu
function gitlogue-menu
    set -l choice (printf '%s\n' "Random commits" "Specific commit" "By author" "By date range" "Theme selection" | \
        fzf --prompt="gitlogue> " --height=40% --reverse)

    switch $choice
        case "Random commits"
            gitlogue
        case "Specific commit"
            set -l commit (git log --oneline | fzf --prompt="Select commit> " | awk '{print $1}')
            test -n "$commit"; and gitlogue --commit "$commit"
        case "By author"
            set -l author (git log --format='%an' | sort -u | fzf --prompt="Select author> ")
            test -n "$author"; and gitlogue --author "$author"
        case "By date range"
            set -l after (printf '%s\n' "1 day ago" "1 week ago" "2 weeks ago" "1 month ago" | fzf --prompt="After> ")
            test -n "$after"; and gitlogue --after "$after"
        case "Theme selection"
            set -l theme (gitlogue theme list | tail -n +2 | sed 's/^  - //' | fzf --prompt="Select theme> ")
            test -n "$theme"; and gitlogue --theme "$theme"
    end
end

# ------------ Zellij ----------
# set -gx ZELLIJ_AUTO_ATTACH false
# set -gx ZELLIJ_AUTO_EXIT false

# ---------- Homebrew ----------
alias ibrew='env /usr/bin/arch -x86_64 /usr/local/bin/brew'
eval (/opt/homebrew/bin/brew shellenv | string collect)

# ---------- DBUS ----------
alias DBUS_SESSION_BUS_ADDRESS="unix:path=$DBUS_LAUNCHD_SESSION_BUS_SOCKET"

# Added by OrbStack: command-line tools and integration
# This won't be added again if you remove it.
source ~/.orbstack/shell/init2.fish 2>/dev/null || :
alias grealpath realpath
