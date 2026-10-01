function spf --description "Run Superfile and change directory after a successful quit"
    set -l lastdir_file (command spf pl --lastdir-file 2>/dev/null)
    if test -z "$lastdir_file"
        command spf $argv
        return $status
    end

    command rm -f -- "$lastdir_file" 2>/dev/null
    if test -e "$lastdir_file"
        command spf $argv
        set -l spf_status $status
        command rm -f -- "$lastdir_file" 2>/dev/null
        return $spf_status
    end

    command spf $argv
    set -l spf_status $status

    if test $spf_status -eq 0; and test -f "$lastdir_file"
        source "$lastdir_file"
    end
    command rm -f -- "$lastdir_file" 2>/dev/null
    return $spf_status
end
