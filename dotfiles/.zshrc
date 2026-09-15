if [[ -o interactive \
    && ( "${__CFBundleIdentifier:-}" == "com.openai.codex" \
        || "${TERM_PROGRAM:-}" == "WezTerm" \
        || "${HERDR_ENV:-}" == "1" ) ]]; then
    unset NO_COLOR
    if [[ "${TERM:-}" == "dumb" ]]; then
        export TERM="xterm-256color"
    fi
fi

export PATH="$HOME/.local/bin:$PATH"

# opencode
export PATH=${HOME}/.opencode/bin:$PATH

# Default editor
export EDITOR="nvim"
export VISUAL="$EDITOR"
export GIT_EDITOR="$EDITOR"

if [ -z "${OPENAI_API_KEY:-}" ] && command -v security >/dev/null 2>&1; then
    openai_api_key="$(security find-generic-password -a "$USER" -s OPENAI_API_KEY -w 2>/dev/null || true)"
    if [ -n "$openai_api_key" ]; then
        export OPENAI_API_KEY="$openai_api_key"
    fi
    unset openai_api_key
fi

if [ -z "${ELEVENLABS_API_KEY:-}" ] && command -v security >/dev/null 2>&1; then
    elevenlabs_api_key="$(security find-generic-password -a "$USER" -s ELEVENLABS_API_KEY -w 2>/dev/null || true)"
    if [ -n "$elevenlabs_api_key" ]; then
        export ELEVENLABS_API_KEY="$elevenlabs_api_key"
    fi
    unset elevenlabs_api_key
fi

if [ -z "${HF_TOKEN:-}" ] && command -v security >/dev/null 2>&1; then
    hf_token="$(security find-generic-password -a "$USER" -s HF_TOKEN -w 2>/dev/null || true)"
    if [ -n "$hf_token" ]; then
        export HF_TOKEN="$hf_token"
        export HUGGINGFACE_HUB_TOKEN="$hf_token"
    fi
    unset hf_token
fi

if [ -z "${WAKATIME_API_KEY:-}" ] && command -v security >/dev/null 2>&1; then
    wakatime_api_key="$(security find-generic-password -a "$USER" -s WAKATIME_API_KEY -w 2>/dev/null || true)"
    if [ -n "$wakatime_api_key" ]; then
        export WAKATIME_API_KEY="$wakatime_api_key"
    fi
    unset wakatime_api_key
fi

# Activate mise before any tool guard below. Fresh shells start without
# shims on PATH, so guards like `command -v tv` would otherwise skip.
if command -v mise >/dev/null 2>&1; then
    eval "$(mise activate zsh --shims)"
fi

if command -v starship >/dev/null 2>&1; then
    eval "$(starship init zsh)"
fi

# Replace ls with eza
if command -v eza >/dev/null 2>&1; then
    alias ls='eza --icons=auto --group-directories-first --git'
    alias ll='eza -la --icons=auto --group-directories-first --git'
fi

# Alias: quick launch nvim with `v`
alias v='nvim'
if command -v gh >/dev/null 2>&1 && gh extension list 2>/dev/null | rg -q '^github/gh-copilot'; then
    eval "$(gh copilot alias -- zsh)"
fi


# Shell completion configuration for the Click Python package
command -v flow-cli > /dev/null 2>&1 && eval "$(_FLOW_CLI_COMPLETE=zsh_source flow-cli)"
if command -v wt >/dev/null 2>&1; then eval "$(command wt config shell init zsh)"; fi
if command -v jw >/dev/null 2>&1; then
    autoload -Uz compinit
    (( $+functions[compdef] )) || compinit
    eval "$(command jw shell init zsh)"
fi
if [[ -o interactive ]] && command -v tv >/dev/null 2>&1; then eval "$(tv init zsh)"; fi

wto() {
    worktree-opencode "$@"
}

prdiff() {
    prdiff-review "$@"
}

glf() {
    gitlogue-select browse "$@"
}

gitlogue-menu() {
    gitlogue-select menu "$@"
}

# OpenClaw Completion
if command -v openclaw >/dev/null 2>&1; then
    source <(openclaw completion --shell zsh)
fi
