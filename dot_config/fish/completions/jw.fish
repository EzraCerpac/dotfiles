function __jw_workspaces
    jj workspace list -T 'name ++ "\n"' --color=never 2>/dev/null
end

function __jw_subcommands
    printf '%s\n' switch s list path remove rm prune root current help
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

complete -c jw -n '__jw_using_subcommand switch s' -f -a '(__jw_workspaces) - @ ^' -d 'Workspace name'
complete -c jw -n '__jw_using_subcommand switch s' -l at -r -d 'Create workspace at revset'
complete -c jw -n '__jw_using_subcommand switch s' -l bookmark -s b -r -d 'Create bookmark in new workspace'
complete -c jw -n '__jw_using_subcommand switch s' -l execute -s x -r -d 'Run command after switching'
complete -c jw -n '__jw_using_subcommand switch s' -l print-path -d 'Print target path only'

complete -c jw -n '__jw_using_subcommand path' -f -a '(__jw_workspaces) - @ ^' -d 'Workspace name'
complete -c jw -n '__jw_using_subcommand remove rm' -f -a '(__jw_workspaces) - @ ^' -d 'Workspace name'
complete -c jw -n '__jw_using_subcommand remove rm' -l delete-dir -d 'Also delete the workspace directory'
