function __mise_source_yazi_completion --argument-names command_name
    set -l yazi_bin (command -s yazi 2>/dev/null)
    if test (count $yazi_bin) -ne 1; or string match -q '*/mise/shims/yazi' -- "$yazi_bin"
        if command -q mise
            set yazi_bin (mise which yazi 2>/dev/null)
        end
    end

    test (count $yazi_bin) -eq 1; or return
    set -l completion_dir (path dirname "$yazi_bin")/completions
    set -l completion "$completion_dir/$command_name.fish"
    test -f "$completion"; or return
    source "$completion"
end
