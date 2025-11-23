# Homebrew (Apple Silicon first)
fish_add_path /opt/homebrew/bin /opt/homebrew/sbin
fish_add_path /usr/local/bin /usr/local/sbin # Rosetta fallback only

# Enable vi key bindings
fish_vi_key_bindings

if status is-interactive
    # Commands to run in interactive sessions can go here
    atuin init fish --disable-up-arrow | source
    # eval (zellij setup --generate-auto-start fish | string collect)
end

# Auto-Warpify
status --is-interactive; and printf 'P$f{"hook": "SourcedRcFileForWarp", "value": { "shell": "fish", "uname": "Darwin" }}�'

function fish_greeting
    random choice "Hello!" Hi "G'day" Howdy "Hey, stranger!"
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
alias nv='nvim'
alias nvim-local='nvim -c "TempRoot"'
alias nvim-local-env='NVIM_LOCAL_ROOT=1 nvim'
fzf --fish | source # Set up fzf key bindings
# set -Ux fifc_editor nvim
# set -U fifc_keybinding \ct # Bind fzf completions to ctrl-x
set -Ux CARAPACE_BRIDGES 'fish,bash,inshellisense' # optional (removed zsh)
carapace _carapace | source

# ---------- Julia ----------
alias pluto="julia --banner=no -e 'using Pluto; Pluto.run()'"

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

fish_add_path $HOME/.local/bin

# Added by Antigravity
fish_add_path /Users/ezracerpac/.antigravity/antigravity/bin
