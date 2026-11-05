#!/usr/bin/env bash
# Claude Code reads skills only from ~/.claude/skills. Codex and other agents
# share ~/.agents/skills, where installers such as `rex skill setup` write.
# Link each shared skill directory into Claude's folder so the installer keeps
# owning the content. Claude's own skills and foreign links are never replaced.

set -euo pipefail

shared="${HOME}/.agents/skills"
claude="${HOME}/.claude/skills"

# Drop links whose shared skill was removed (for example `rex skill remove`).
for link in "$claude"/*; do
    [[ -L "$link" && ! -e "$link" ]] || continue
    [[ "$(readlink "$link")" == "$shared"/* ]] || continue
    rm -- "$link"
    echo "Removed stale Claude skill link ~/.claude/skills/${link##*/}"
done

for dir in "$shared"/*/; do
    dir="${dir%/}"
    name="${dir##*/}"
    [[ -f "$dir/SKILL.md" ]] || continue
    dest="$claude/$name"
    if [[ -L "$dest" && "$(readlink "$dest")" == "$dir" ]]; then
        continue
    elif [[ -e "$dest" || -L "$dest" ]]; then
        echo "Kept existing ~/.claude/skills/$name; not linking the shared copy"
        continue
    fi
    mkdir -p "$claude"
    ln -s "$dir" "$dest"
    echo "Linked shared skill $name into ~/.claude/skills"
done
