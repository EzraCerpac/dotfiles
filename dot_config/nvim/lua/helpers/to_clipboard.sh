#!/bin/bash
# Converts file to RTF via pygmentize and copies to macOS clipboard
# Usage: to_clipboard.sh <filetype> <input_file> [theme]

LEXER="${1:-lua}"
INPUT="${2:-/dev/stdin}"
THEME="${3:-xcode}"

# Write RTF to temp file
RTFFILE=$(mktemp).rtf
pygmentize -f rtf -O style="$THEME" -l "$LEXER" "$INPUT" > "$RTFFILE"

# Remove trailing newline that causes issues
truncate -s -1 "$RTFFILE"

# Use pbcopy directly - it should recognize RTF by header
pbcopy < "$RTFFILE"

rm -f "$RTFFILE"
