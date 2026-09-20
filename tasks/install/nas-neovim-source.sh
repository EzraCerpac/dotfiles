#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/../local/common"
require_setup_profile nas

# Build the latest Neovim from the official source repository for hosts whose
# glibc is too old for the upstream prebuilt Linux archive.
#
# Required tools: bash, curl, git, tar, make, and cmake.
# Optional environment:
#   NEOVIM_BUILD_PREFIX  install root (default: ~/.local/share/neovim-built)
#   NEOVIM_CMAKE_BIN     portable cmake executable
#   NEOVIM_BUILD_JOBS    parallel build jobs (default: 2)
#   NEOVIM_VERSION       exact version without or with leading v

prefix=${NEOVIM_BUILD_PREFIX:-"$HOME/.local/share/neovim-built"}
jobs=${NEOVIM_BUILD_JOBS:-2}
cmake_bin=${NEOVIM_CMAKE_BIN:-${CMAKE:-}}
current="$prefix/current"
mkdir -p "$prefix/logs" "$prefix/work"

if [[ -z "$cmake_bin" ]]; then
  cmake_bin=$(command -v cmake || true)
fi
if [[ -z "$cmake_bin" ]]; then
  printf '%s\n' "cmake not found; set NEOVIM_CMAKE_BIN to a portable CMake executable" >&2
  exit 2
fi
if [[ ! -x "$cmake_bin" ]]; then
  printf 'CMake is not executable: %s\n' "$cmake_bin" >&2
  exit 2
fi

for command_name in curl git make tar; do
  command -v "$command_name" >/dev/null || {
    printf 'required command missing: %s\n' "$command_name" >&2
    exit 2
  }
done

release_tag=
if [[ -n "${NEOVIM_VERSION:-}" ]]; then
  release_tag="$NEOVIM_VERSION"
else
  # Reuse mise's GitHub credentials and release cache.
  release_tag=$(setup_mise latest github:neovim/neovim)
fi
[[ "$release_tag" == v* ]] || release_tag="v$release_tag"
version=${release_tag#v}
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] || {
  printf 'unexpected Neovim release tag: %s\n' "$release_tag" >&2
  exit 2
}

target="$prefix/$version"
if [[ -x "$target/bin/nvim" ]]; then
  if "$target/bin/nvim" --headless -u NONE -i NONE '+qa' >/dev/null 2>&1; then
    printf 'Neovim %s is already installed and runnable at %s\n' "$version" "$target"
    ln -sfn "$version" "$current.tmp.$$"
    mv -Tf "$current.tmp.$$" "$current"
    exit 0
  fi
fi

if [[ -e "$target" || -L "$target" ]]; then
  printf 'existing Neovim target is not runnable; refusing to overwrite: %s\n' "$target" >&2
  exit 1
fi

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
log="$prefix/logs/$version-$timestamp.log"
work="$prefix/work/$version-$$"
staging="$prefix/.staging-$version-$$"
mkdir -p "$work" "$staging"
exec > >(tee -a "$log") 2>&1

printf 'Neovim source build: version=%s\n' "$version"
printf 'source ref: %s\n' "$release_tag"
printf 'work: %s\n' "$work"
printf 'staging: %s\n' "$staging"
printf 'log: %s\n' "$log"
"$cmake_bin" --version | head -1

remote_sha=$(git ls-remote https://github.com/neovim/neovim.git "refs/tags/$release_tag^{}" | awk 'NR == 1 { print $1 }')
[[ "$remote_sha" =~ ^[0-9a-f]{40}$ ]] || {
  printf 'could not resolve peeled commit for %s\n' "$release_tag" >&2
  exit 1
}
git clone --depth 1 --branch "$release_tag" --single-branch https://github.com/neovim/neovim.git "$work/source"
actual_sha=$(git -C "$work/source" rev-parse HEAD)
[[ "$actual_sha" == "$remote_sha" ]] || {
  printf 'source commit mismatch: remote=%s clone=%s\n' "$remote_sha" "$actual_sha" >&2
  exit 1
}

export DEPS_BUILD_DIR="$work/deps"
"$cmake_bin" -S "$work/source/cmake.deps" -B "$DEPS_BUILD_DIR" -G "Unix Makefiles" \
  -D CMAKE_BUILD_TYPE=Release -D ENABLE_WASMTIME=OFF
"$cmake_bin" --build "$DEPS_BUILD_DIR" --parallel "$jobs"
"$cmake_bin" -S "$work/source" -B "$work/build" -G "Unix Makefiles" \
  -D CMAKE_BUILD_TYPE=Release -D CMAKE_INSTALL_PREFIX="$staging" \
  -D ENABLE_WASMTIME=OFF
"$cmake_bin" --build "$work/build" --parallel "$jobs"
"$cmake_bin" --install "$work/build"

test -x "$staging/bin/nvim"
"$staging/bin/nvim" --headless -u NONE -i NONE '+lua assert(vim.version().major == 0)' '+qa'
mv "$staging" "$target"
ln -sfn "$version" "$current.tmp.$$"
mv -Tf "$current.tmp.$$" "$current"
printf 'Neovim %s installed and selected at %s\n' "$version" "$current"
