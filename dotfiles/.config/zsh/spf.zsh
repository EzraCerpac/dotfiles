spf() {
    local lastdir_file spf_status

    if ! lastdir_file="$(command spf pl --lastdir-file 2>/dev/null)" || [[ -z "$lastdir_file" ]]; then
        command spf "$@"
        return $?
    fi

    command rm -f -- "$lastdir_file" 2>/dev/null
    if [[ -e "$lastdir_file" ]]; then
        command spf "$@"
        spf_status=$?
        command rm -f -- "$lastdir_file" 2>/dev/null
        return "$spf_status"
    fi

    command spf "$@"
    spf_status=$?

    if (( spf_status == 0 )) && [[ -f "$lastdir_file" ]]; then
        source "$lastdir_file"
    fi
    command rm -f -- "$lastdir_file" 2>/dev/null
    return "$spf_status"
}
