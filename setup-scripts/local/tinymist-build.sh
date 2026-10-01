#!/usr/bin/env bash
set -euo pipefail
setup_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
source_revision=32f908199ee17ea295512bbc27166e890c438175
source_dir="$(mktemp -d "${TMPDIR:-/tmp}/tinymist-build.XXXXXX")"
trap 'rm -rf -- "$source_dir"' EXIT
stage_root="${HOME}/.local/share/tinymist-patched"
mkdir -p "$stage_root"
git clone --quiet --depth 1 --branch v0.15.8 https://github.com/Myriad-Dreamin/tinymist.git "$source_dir"
[[ "$(git -C "$source_dir" rev-parse HEAD)" == "$source_revision" ]]
git -C "$source_dir" apply "$setup_root/resources/tinymist-query-history-gc.patch"
export CARGO_TARGET_DIR="$stage_root/target"
mise -C "$setup_root" exec -- bash -c '
    set -euo pipefail
    cd -- "$1"
    cargo test --locked -j 2 -p tinymist-query --lib
    cargo build --locked --release -j 2 -p tinymist-cli --bin tinymist
' tinymist-build "$source_dir"
mkdir -p "$stage_root/bin"
install -m 755 "$CARGO_TARGET_DIR/release/tinymist" "$stage_root/bin/tinymist.new"
mv "$stage_root/bin/tinymist.new" "$stage_root/bin/tinymist"
printf 'Installed patched Tinymist: %s/bin/tinymist\n' "$stage_root"
