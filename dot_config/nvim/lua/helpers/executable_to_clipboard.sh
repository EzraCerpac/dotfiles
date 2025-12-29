#!/bin/bash
# Reads from stdin, converts to RTF via pygmentize, copies to macOS clipboard
# Usage: echo "code" | to_clipboard.sh <filetype> [theme]
# Defaults: filetype=lua, theme=xcode

LEXER="${1:-lua}"
THEME="${2:-xcode}"

# Write RTF to temp file
RTFFILE=$(mktemp).rtf
cat | pygmentize -f rtf -O style="$THEME" -l "$LEXER" > "$RTFFILE"

# Use AppleScript to copy only RTF (no plain text)
osascript << APPLESCRIPT
set rtfFile to "$RTFFILE" as POSIX file
tell application "System Events"
    set rtfData to read rtfFile as «class RTF »
    set the clipboard to rtfData
end tell
APPLESCRIPT

rm -f "$RTFFILE"
