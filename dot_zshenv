export PATH="$HOME/.local/bin:$PATH"
export HOMEBREW_NO_ENV_HINTS=1

# Add Homebrew to PATH
if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv zsh)"
elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv zsh)"
fi

. "$HOME/.cargo/env"
