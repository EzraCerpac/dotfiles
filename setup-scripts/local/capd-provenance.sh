#!/usr/bin/env bash

capd_validate_source() {
    local app="${1:?app required}" revision="${2:?revision required}" plist="$1/Contents/Info.plist"
    [[ "$revision" =~ ^[0-9a-f]{40}$ ]] || return 1
    [[ "$(/usr/bin/plutil -extract CapdSourceRepository raw -o - "$plist" 2>/dev/null)" == 'https://github.com/EzraCerpac/capd' ]] || return 1
    [[ "$(/usr/bin/plutil -extract CapdSourceBranch raw -o - "$plist" 2>/dev/null)" == main ]] || return 1
    [[ "$(/usr/bin/plutil -extract CapdSourceRevision raw -o - "$plist" 2>/dev/null)" == "$revision" ]] || return 1
}
