# fish sources conf.d files before config.fish.
if test (uname) = Darwin
    # ---------- Homebrew ----------
    set -gx HOMEBREW_NO_ENV_HINTS 1
    for path in /opt/homebrew/bin /opt/homebrew/sbin
        if test -d "$path"
            fish_add_path --global --path "$path"
        end
    end

    if test -x /opt/homebrew/bin/brew
        eval (/opt/homebrew/bin/brew shellenv | string collect)
    end

    # Add uutils-coreutils to PATH (unprefixed commands).
    set -l uutils_bin /opt/homebrew/opt/uutils-coreutils/libexec/uubin
    if test -d "$uutils_bin"
        fish_add_path --global --path "$uutils_bin"
    end

    # ---------- Keychain credentials ----------
    if not set -q OPENAI_API_KEY; and command -q security
        set -l openai_api_key (security find-generic-password -a "$USER" -s OPENAI_API_KEY -w 2>/dev/null)
        if test -n "$openai_api_key"
            set -gx OPENAI_API_KEY "$openai_api_key"
        end
    end

    if not set -q ELEVENLABS_API_KEY; and command -q security
        set -l elevenlabs_api_key (security find-generic-password -a "$USER" -s ELEVENLABS_API_KEY -w 2>/dev/null)
        if test -n "$elevenlabs_api_key"
            set -gx ELEVENLABS_API_KEY "$elevenlabs_api_key"
        end
    end

    if not set -q HF_TOKEN; and command -q security
        set -l hf_token (security find-generic-password -a "$USER" -s HF_TOKEN -w 2>/dev/null)
        if test -n "$hf_token"
            set -gx HF_TOKEN "$hf_token"
            set -gx HUGGINGFACE_HUB_TOKEN "$hf_token"
        end
    end

    if not set -q WAKATIME_API_KEY; and command -q security
        set -l wakatime_api_key (security find-generic-password -a "$USER" -s WAKATIME_API_KEY -w 2>/dev/null)
        if test -n "$wakatime_api_key"
            set -gx WAKATIME_API_KEY "$wakatime_api_key"
        end
    end

    # ---------- Tailscale ----------
    set -l tailscale_cli /Applications/Tailscale.app/Contents/MacOS/Tailscale
    if test -x "$tailscale_cli"
        alias tailscale "$tailscale_cli"
    end

    # ---------- DBus and OrbStack ----------
    if set -q DBUS_LAUNCHD_SESSION_BUS_SOCKET
        alias DBUS_SESSION_BUS_ADDRESS "unix:path=$DBUS_LAUNCHD_SESSION_BUS_SOCKET"
    end

    set -l orbstack_init "$HOME/.orbstack/shell/init2.fish"
    if test -f "$orbstack_init"
        source "$orbstack_init" 2>/dev/null || :
    end

    if command -q realpath
        alias grealpath realpath
    end
end
