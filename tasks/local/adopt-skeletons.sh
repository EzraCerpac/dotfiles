#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common"
[[ "$(uname -s)" == Linux && "$SETUP_PROFILE" == workstation ]] || exit 0

# A new distro account may already have vendor shell defaults. Only adopt
# exact /etc/skel copies; independently edited files stay for native conflict review.
command -v cmp >/dev/null || { setup_error "diffutils is required to compare vendor defaults"; exit 1; }
backup_dir=""
for name in .bashrc .bash_profile .zshrc .zprofile; do
    target="$HOME/$name"
    vendor="/etc/skel/$name"
    [[ -f "$target" && ! -L "$target" && -f "$vendor" ]] || continue
    cmp -s "$target" "$vendor" || continue
    if [[ -z "$backup_dir" ]]; then
        umask 077
        backup_root="${XDG_STATE_HOME:-$HOME/.local/state}/mise/bootstrap-backups/skeletons"
        mkdir -p "$backup_root"
        backup_dir="$(mktemp -d "$backup_root/vendor.XXXXXX")"
    fi
    mv -- "$target" "$backup_dir/$name"
    printf 'Preserved pristine vendor default %s in %s\n' "$name" "$backup_dir"
done
