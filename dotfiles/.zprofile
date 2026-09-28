# Login shells, including non-interactive `zsh -lc`, get mise's shims here;
# .zshrc skips its own activation for them.
if command -v mise >/dev/null 2>&1; then
    eval "$(mise activate zsh --shims)"
fi
