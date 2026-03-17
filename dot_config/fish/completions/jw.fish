function __jw_workspaces
    jj workspace list -T 'name ++ "\n"' --color=never 2>/dev/null
end

function __jw_workspace_candidates
    for name in (__jw_workspaces)
        printf '%s\t%s\n' $name 'Existing workspace'
    end

    printf '%s\t%s\n' @ 'Current workspace'
    printf '%s\t%s\n' - 'Previous workspace'
    printf '%s\t%s\n' ^ 'Default workspace'
end

function __jw_subcommands
    printf '%s\t%s\n' switch 'Switch to or create a workspace'
    printf '%s\t%s\n' s 'Alias for switch'
    printf '%s\t%s\n' list 'List known workspaces'
    printf '%s\t%s\n' path 'Print a workspace path'
    printf '%s\t%s\n' remove 'Forget a workspace'
    printf '%s\t%s\n' rm 'Alias for remove'
    printf '%s\t%s\n' prune 'Forget missing workspaces'
    printf '%s\t%s\n' root 'Print current workspace root'
    printf '%s\t%s\n' current 'Print current workspace name'
    printf '%s\t%s\n' help 'Show usage'
end

function __jw_needs_subcommand
    set -l cmd (commandline -opc)
    test (count $cmd) -le 1
end

function __jw_using_subcommand
    set -l cmd (commandline -opc)
    test (count $cmd) -ge 2
    and contains -- $cmd[2] $argv
end

complete -e -c jw

complete -c jw -n __jw_needs_subcommand -f -a '(__jw_subcommands)'
complete -c jw -s h -l help -d 'Show usage'

complete -c jw -n '__jw_using_subcommand switch s' -f -a '(__jw_workspace_candidates)'
complete -c jw -n '__jw_using_subcommand switch s' -l at -r -d 'Create workspace at revset'
complete -c jw -n '__jw_using_subcommand switch s' -l bookmark -s b -r -d 'Create bookmark in new workspace'
complete -c jw -n '__jw_using_subcommand switch s' -l execute -s x -r -d 'Run command after switching'
complete -c jw -n '__jw_using_subcommand switch s' -l print-path -d 'Print target path only'

complete -c jw -n '__jw_using_subcommand path' -f -a '(__jw_workspace_candidates)'
complete -c jw -n '__jw_using_subcommand remove rm' -f -a '(__jw_workspace_candidates)'
complete -c jw -n '__jw_using_subcommand remove rm' -l delete-dir -d 'Also delete the workspace directory'
