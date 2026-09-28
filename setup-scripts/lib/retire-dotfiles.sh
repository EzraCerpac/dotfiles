#!/usr/bin/env bash
# Remove links left behind by retired [dotfiles] declarations.
#
# usage: retire-dotfiles.sh SETUP_ROOT
#
# mise leaves a symlink in place when its declaration disappears, and such a
# dangling link can break its reader (Neovim imports every lua/plugins/ file).
# Each target in setup-scripts/setup/retired-dotfiles is removed only while it
# is still a symlink into this checkout whose source no longer exists. Anything
# else is left alone: a regular file, a live link, or a link somewhere else.
set -euo pipefail

logical_root="${1:?usage: retire-dotfiles.sh SETUP_ROOT}"
logical_root="${logical_root%/}"
physical_root="$(cd "$logical_root" && pwd -P)"
list="$physical_root/setup-scripts/setup/retired-dotfiles"
[[ -f "$list" ]] || exit 0

# Resolve PATH through its nearest existing ancestor, so a link spelled via a
# symlinked directory (macOS /var -> /private/var) still matches the checkout.
physical_path() {
    local head="$1" tail=""
    while [[ -n "$head" && ! -d "$head" ]]; do
        tail="/${head##*/}$tail"
        head="${head%/*}"
    done
    [[ -n "$head" ]] || head=/
    printf '%s%s\n' "$(cd "$head" && pwd -P)" "$tail"
}

while IFS= read -r entry || [[ -n "$entry" ]]; do
    [[ -n "$entry" && "$entry" != \#* ]] || continue
    if [[ "$entry" != "~/"* || "$entry" == *"/../"* || "$entry" == *"/.." ]]; then
        printf 'retire-dotfiles: ignoring entry outside HOME: %s\n' "$entry" >&2
        continue
    fi
    target="$HOME/${entry#"~/"}"
    [[ -L "$target" ]] || continue
    link="$(readlink "$target")"
    [[ "$link" == /* ]] || link="$(dirname "$target")/$link"
    link="$(physical_path "$link")"
    case "$link" in
        "$logical_root"/*|"$physical_root"/*) ;;
        *) continue ;;
    esac
    # A source that exists again means the entry was re-declared; keep it.
    [[ ! -e "$target" ]] || continue
    rm -- "$target"
    printf 'Removed retired link %s\n' "$entry"
done <"$list"
