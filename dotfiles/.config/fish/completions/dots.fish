complete -c dots -f
complete -c dots -n 'not __fish_seen_subcommand_from up update status apply bootstrap backup restore add help' -a 'up status apply bootstrap backup restore add help'
complete -c dots -n '__fish_seen_subcommand_from add' -l base -d 'Record in the shared base'
complete -c dots -n '__fish_seen_subcommand_from add' -l profile -x -a 'workstation nas' -d 'Record in this role'
complete -c dots -n '__fish_seen_subcommand_from add' -l path -r -d 'Record in an explicit config file'
complete -c dots -s h -l help -d 'Show help'
