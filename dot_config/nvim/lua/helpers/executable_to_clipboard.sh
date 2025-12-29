#!/bin/bash
# Reads from stdin, converts to RTF via pygmentize, copies to macOS clipboard
# Usage: echo "code" | to_clipboard.sh
# Sets filetype via first argument (default: lua)
pygmentize -s -f rtf -O style=xcode -g | pbcopy
