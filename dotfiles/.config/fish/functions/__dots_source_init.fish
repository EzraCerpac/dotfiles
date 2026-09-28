function __dots_source_init --description 'Source a tool init script, cached until the tool or config changes'
    # usage: __dots_source_init TOOL [ARGS...]
    # Runs `TOOL ARGS...` once and sources the cached output afterwards. The cache
    # is regenerated when the resolved executable or config.fish is newer than it.
    set -l executable (command -s -- $argv[1]); or return 0
    set -l cache_root $HOME/.cache
    set -q XDG_CACHE_HOME[1]; and set cache_root $XDG_CACHE_HOME
    set -l key (string join _ -- $argv | string replace -ra '[^A-Za-z0-9_.-]+' _)
    set -l cache $cache_root/fish/init/$key.fish

    set -l newest (path mtime -- (path resolve -- $executable))
    set -l config (path resolve -- $__fish_config_dir/config.fish)
    if test -f "$config"
        set -l config_mtime (path mtime -- $config)
        test "$config_mtime" -gt "$newest"; and set newest $config_mtime
    end

    if not test -f $cache; or test (path mtime -- $cache) -lt $newest
        mkdir -p (path dirname -- $cache)
        set -l temporary $cache.$fish_pid
        if command $argv >$temporary 2>/dev/null
            command mv -f -- $temporary $cache
        else
            command rm -f -- $temporary
            return 1
        end
    end
    source $cache
end
