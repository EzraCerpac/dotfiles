function __jwc_workspaces
    jj workspace list -T 'name ++ "\n"' --color=never 2>/dev/null
end

complete -e -c jwc
complete -c jwc -f -a '(__jwc_workspaces) - @ ^' -d 'Workspace name'
