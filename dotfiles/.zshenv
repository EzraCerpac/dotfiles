# Every zsh reads this, scripts included; keep it cheap. Duplicate PATH entries
# collapse to the first occurrence.
typeset -U path PATH
export HOMEBREW_NO_ENV_HINTS=1

# Homebrew's environment is inherited by child shells, so evaluate
# `brew shellenv` once per session; fpath is not exported, so re-add it.
if [[ -z "${HOMEBREW_PREFIX:-}" ]]; then
    if [[ -x /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv zsh)"
    elif [[ -x /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv zsh)"
    fi
elif [[ -d "$HOMEBREW_PREFIX/share/zsh/site-functions" ]]; then
    fpath=("$HOMEBREW_PREFIX/share/zsh/site-functions" $fpath)
fi

# Rustup is optional; mise provides Rust on the workstation.
if [[ -f "$HOME/.cargo/env" ]]; then
    . "$HOME/.cargo/env"
fi

# Standalone tools (including mise itself) come before Homebrew.
path=("$HOME/.local/bin" $path)
