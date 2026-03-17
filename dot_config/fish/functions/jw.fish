function jw --description "Manage and switch jj workspaces"
    if test (count $argv) -eq 0
        command jw
        return $status
    end

    switch $argv[1]
        case switch s
            if contains -- -x $argv; or contains -- --execute $argv; or contains -- -h $argv; or contains -- --help $argv
                command jw $argv
                return $status
            end

            set -l separator_index (contains -i -- -- $argv)
            set -l command_args

            if test -n "$separator_index"
                set command_args $argv[1..(math $separator_index - 1)] --print-path $argv[$separator_index..-1]
            else
                set command_args $argv --print-path
            end

            set -l target (command jw $command_args)
            or return $status

            cd $target
        case '*'
            command jw $argv
    end
end
