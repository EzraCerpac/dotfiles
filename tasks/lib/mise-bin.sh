#!/usr/bin/env bash

resolve_mise_bin() {
    local candidate

    if [[ -n "${SETUP_MISE_BIN:-}" ]]; then
        if [[ -x "$SETUP_MISE_BIN" ]]; then
            printf '%s\n' "$SETUP_MISE_BIN"
            return 0
        fi
        printf 'mise: SETUP_MISE_BIN is not executable: %s\n' "$SETUP_MISE_BIN" >&2
        return 2
    fi

    # Some invocations forward MISE_BIN; others only expose mise_bin to config
    # templates, so keep the standalone path ahead of ambient PATH as fallback.
    if [[ -n "${MISE_BIN:-}" && -x "$MISE_BIN" ]]; then
        printf '%s\n' "$MISE_BIN"
        return 0
    fi

    if [[ -n "${HOME:-}" && -x "$HOME/.local/bin/mise" ]]; then
        printf '%s\n' "$HOME/.local/bin/mise"
        return 0
    fi

    candidate="$(command -v mise 2>/dev/null || true)"
    if [[ -n "$candidate" && -x "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi

    printf 'mise: no executable found in SETUP_MISE_BIN, MISE_BIN, ~/.local/bin, or PATH\n' >&2
    return 127
}
