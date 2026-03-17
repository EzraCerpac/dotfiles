function __jwc_workspaces
    jj workspace list -T 'name ++ "\n"' --color=never 2>/dev/null
end

function __jwc_workspace_candidates
    for name in (__jwc_workspaces)
        printf '%s\t%s\n' $name 'Existing workspace'
    end

    printf '%s\t%s\n' @ 'Current workspace'
    printf '%s\t%s\n' - 'Previous workspace'
    printf '%s\t%s\n' ^ 'Default workspace'
end

complete -e -c jwc
complete -c jwc -f -a '(__jwc_workspace_candidates)'
