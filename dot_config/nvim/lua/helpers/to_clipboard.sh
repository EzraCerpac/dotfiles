#!/bin/bash
# Converts file to RTF via pygmentize and copies to macOS clipboard
# Usage: to_clipboard.sh <filetype> [theme] <input_file>

LEXER="${1:-lua}"
THEME="${2:-xcode}"
INPUT="${3:-/dev/stdin}"

# Write RTF to temp file
RTFFILE=$(mktemp).rtf
pygmentize -f rtf -O style="$THEME" -l "$LEXER" "$INPUT" > "$RTFFILE"

# Use AppleScript to copy only RTF (no plain text)
osascript << APPLESCRIPT
set rtfFile to "$RTFFILE" as POSIX file
tell application "System Events"
    set rtfData to read rtfFile as «class RTF »
    set the clipboard to rtfData
end tell
APPLESCRIPT

rm -f "$RTFFILE"
