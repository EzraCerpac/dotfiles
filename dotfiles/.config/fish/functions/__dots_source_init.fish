function __dots_source_init --description 'Source a tool init script, cached until the tool or config changes'
    # usage: __dots_source_init TOOL [ARGS...]
    # Runs `TOOL ARGS...` once and sources the cached output afterwards. The
    # cache's first line fingerprints the resolved executable and config.fish
    # by path and mtime, and any difference regenerates it. Matching exactly,
    # rather than "newer than", means a tool that moves to another path or
    # carries a future mtime cannot pin a stale cache or defeat it for good.
    set -l executable (command -s -- $argv[1]); or return 0
    set -l cache_root $HOME/.cache
    test -n "$XDG_CACHE_HOME"; and set cache_root $XDG_CACHE_HOME
    set -l key (string join _ -- $argv | string replace -ra '[^A-Za-z0-9_.-]+' _)
    set -l cache $cache_root/fish/init/$key.fish

    set -l resolved (path resolve -- $executable)
    # A mise shim resolves to mise itself, whose path and mtime do not change
    # when the tool is switched or upgraded; fingerprint the selected binary.
    if test "$argv[1]" != mise; and test (path basename -- $resolved) = mise
        set -l selected (command mise which -- $argv[1] 2>/dev/null)
        and set resolved (path resolve -- $selected)
    end
    set -l config (path resolve -- $__fish_config_dir/config.fish)
    # A missing file's mtime is empty and simply drops out of the fingerprint.
    set -l stamp (string join ' ' -- '# dots-init' $resolved (path mtime -- $resolved) $config (path mtime -- $config))

    set -l cached
    test -f $cache; and read cached <$cache
    if test "$cached" != "$stamp"
        set -l directory (path dirname -- $cache)
        if not mkdir -p $directory 2>/dev/null; or not test -w $directory
            # An unwritable cache must not cost the integration; run it uncached.
            command $argv 2>/dev/null | source
            return
        end
        set -l temporary $cache.$fish_pid
        if begin
                printf '%s\n' $stamp
                command $argv
            end >$temporary 2>/dev/null
            command mv -f -- $temporary $cache
        else
            command rm -f -- $temporary
            return 1
        end
    end
    source $cache
end
