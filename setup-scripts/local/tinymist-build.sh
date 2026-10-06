#!/usr/bin/env bash
set -euo pipefail
setup_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
source_revision=32f908199ee17ea295512bbc27166e890c438175
# Interner source fix: https://github.com/Myriad-Dreamin/tinymist/pull/2735
# Patch from bd37ec637106f55aab9e74ac2e2a4c9f9cb2f512; tested alongside the GC patch.
# When bumping source_revision to an upstream release containing this fix, remove
# this patch/check/apply and its resource. Verify the separate GC patch independently.
interner_patch="$setup_root/resources/tinymist-interner-release-race.patch"
interner_patch_sha256=3e658158129c84a7ce32589cfa698558573eb99e6654f8565095785ef457c474
source_dir="$(mktemp -d "${TMPDIR:-/tmp}/tinymist-build.XXXXXX")"
trap 'rm -rf -- "$source_dir"' EXIT
stage_root="${TINYMIST_STAGE_ROOT:-${HOME}/.local/share/tinymist-patched}"
mkdir -p "$stage_root"
git clone --quiet --depth 1 --branch v0.15.8 https://github.com/Myriad-Dreamin/tinymist.git "$source_dir"
if [[ "$(git -C "$source_dir" rev-parse HEAD)" != "$source_revision" ]]; then
    printf 'Unexpected Tinymist source revision; refusing to build.\n' >&2
    exit 1
fi
if [[ "$(shasum -a 256 "$interner_patch" | awk '{print $1}')" != "$interner_patch_sha256" ]]; then
    printf 'Unexpected interner patch checksum; refusing to build.\n' >&2
    exit 1
fi
git -C "$source_dir" apply --check "$setup_root/resources/tinymist-query-history-gc.patch"
git -C "$source_dir" apply "$setup_root/resources/tinymist-query-history-gc.patch"
git -C "$source_dir" apply --check "$interner_patch"
git -C "$source_dir" apply "$interner_patch"
export CARGO_TARGET_DIR="$stage_root/target"
# The embedded script expands $1 in the child shell.
# shellcheck disable=SC2016
mise -C "$setup_root" exec -- bash -c '
    set -euo pipefail
    cd -- "$1"
    cargo test --locked -j 2 -p tinymist-query --lib
    cargo test --locked -j 2 -p tinymist-analysis --lib
    cargo build --locked --release -j 2 -p tinymist-cli --bin tinymist
' tinymist-build "$source_dir"
mkdir -p "$stage_root/bin"
install -m 755 "$CARGO_TARGET_DIR/release/tinymist" "$stage_root/bin/tinymist.new"
mv "$stage_root/bin/tinymist.new" "$stage_root/bin/tinymist"
printf 'Installed patched Tinymist: %s/bin/tinymist\n' "$stage_root"
