#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
readonly SCRIPT_DIR
SOURCE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
readonly SOURCE_ROOT
readonly LABEL_KEY="local.chezmoi.mise-migration.linux-bootstrap"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$-${RANDOM}"
readonly RUN_ID
TEST_LOG_DIR="${TMPDIR:-/tmp}/mise-linux-bootstrap-${RUN_ID}"
mkdir -m 700 "$TEST_LOG_DIR"
readonly TEST_LOG_DIR
SUMMARY_LOG="$TEST_LOG_DIR/summary.log"
readonly SUMMARY_LOG
exec > >(tee -a "$SUMMARY_LOG") 2>&1

remove_owned_container() {
    local container_id="$1" label_value
    [[ -n "$container_id" ]] || return 0
    label_value="$(docker inspect --format "{{index .Config.Labels \"$LABEL_KEY\"}}" "$container_id" 2>/dev/null || true)"
    if [[ "$label_value" == "$RUN_ID" ]]; then
        docker rm --force "$container_id" >/dev/null
    fi
}

cleanup_owned_containers() {
    local exit_status=$? container_id
    if ((exit_status != 0)); then
        echo "Preserving failed labeled container(s) for diagnosis. Logs: $TEST_LOG_DIR"
        docker ps --all --filter "label=$LABEL_KEY=$RUN_ID" --format '{{.ID}} {{.Names}} {{.Status}} {{.Label "local.chezmoi.mise-migration.linux-bootstrap"}}' || true
        return 0
    fi
    while IFS= read -r container_id; do
        [[ -n "$container_id" ]] || continue
        remove_owned_container "$container_id" || true
    done < <(docker ps --all --quiet --filter "label=$LABEL_KEY=$RUN_ID" 2>/dev/null || true)
    rm -rf "$TEST_LOG_DIR"
}
trap cleanup_owned_containers EXIT
readonly BOOTSTRAP_TIMEOUT_SECONDS="${BOOTSTRAP_TIMEOUT_SECONDS:-3600}"
readonly TEST_CONTAINER_CPUS="${TEST_CONTAINER_CPUS:-2}"
readonly TEST_CONTAINER_MEMORY="${TEST_CONTAINER_MEMORY:-6g}"

distro_selection="fedora"
prepare_only=0

usage() {
    cat <<'USAGE'
Usage: tests/linux-bootstrap.sh [--distro ubuntu|fedora|arch|all] [--prepare-only]

Run the workstation profile in disposable Docker containers. --prepare-only
installs prerequisites and verifies the pinned mise binary without copying or
running the dotfiles profile.

Set BOOTSTRAP_TIMEOUT_SECONDS to bound each full bootstrap invocation.
USAGE
}

run_container_step() {
    local distro="$1" label="$2" timeout_seconds="$3" log_path status
    shift 3
    log_path="$TEST_LOG_DIR/${distro}-${label}.log"
    printf 'Running %s (timeout %s)\n' "$label" "$timeout_seconds"
    if docker exec --user 0 "$container_id" timeout --signal=TERM --kill-after=20s \
        "$timeout_seconds" su "$@" >"$log_path" 2>&1; then
        awk '/mise|bootstrap|setup:|ERROR|Error|error|WARN|Warning|failed|node|Created default/ { print; fflush() }' \
            "$log_path"
    else
        status=$?
        printf 'Step %s failed with exit %s; final output follows. Full log: %s\n' \
            "$label" "$status" "$log_path" >&2
        tail -n 120 "$log_path" >&2
        return "$status"
    fi
}

pull_image() {
    local platform="$1" image="$2" attempt
    for attempt in 1 2 3; do
        if docker pull --platform "$platform" "$image"; then
            return 0
        fi
        if [[ "$attempt" != 3 ]]; then
            printf 'Image pull failed; retrying in %s second(s).\n' "$attempt" >&2
            sleep "$attempt"
        fi
    done
    return 1
}

while (($#)); do
    case "$1" in
    --distro)
        (($# >= 2)) || { usage >&2; exit 2; }
        distro_selection="$2"
        shift 2
        ;;
    --prepare-only)
        prepare_only=1
        shift
        ;;
    --help|-h)
        usage
        exit 0
        ;;
    *)
        printf 'Unknown argument: %s\n' "$1" >&2
        usage >&2
        exit 2
        ;;
    esac
done

case "$distro_selection" in
all|ubuntu|fedora|arch) ;;
*)
    printf 'Unknown distro: %s\n' "$distro_selection" >&2
    usage >&2
    exit 2
    ;;
esac

command -v docker >/dev/null 2>&1 || { echo 'docker is required' >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo 'jq is required to resolve immutable base image digests' >&2; exit 1; }
docker info --format '{{.OSType}}' | grep -qx linux || {
    echo 'Docker must use a Linux engine' >&2
    exit 1
}

server_arch="$(docker info --format '{{.Architecture}}')"
case "$server_arch" in
aarch64|arm64) native_platform='linux/arm64' ;;
x86_64|amd64) native_platform='linux/amd64' ;;
*)
    printf 'Unsupported Docker engine architecture: %s\n' "$server_arch" >&2
    exit 1
    ;;
esac

test_one_distro() {
    local distro="$1"
    local image platform name container_id image_arch manifest image_digest immutable_image setup_log status

    case "$distro" in
    ubuntu)
        image='ubuntu:24.04'
        platform="$native_platform"
        ;;
    fedora)
        image='fedora:44'
        platform="$native_platform"
        ;;
    arch)
        image='archlinux:latest'
        # The official Arch Linux container image is x86_64-only.
        platform='linux/amd64'
        ;;
    esac

    case "$platform" in
    linux/arm64) image_arch='arm64' ;;
    linux/amd64) image_arch='amd64' ;;
    esac

    # Resolve the official tag without retagging or updating any local image.
    manifest="$(docker manifest inspect --verbose "$image")"
    image_digest="$(jq -er --arg arch "$image_arch" \
        '[.[] | select(.Descriptor.platform.os == "linux" and .Descriptor.platform.architecture == $arch) | .Descriptor.digest] | first' \
        <<<"$manifest")"
    immutable_image="${image%%:*}@${image_digest}"

    name="mise-linux-bootstrap-${distro}-${RUN_ID}"
    printf '\n=== %s (%s, %s, %s) ===\n' "$distro" "$immutable_image" "$platform" "$image_arch"

    pull_image "$platform" "$immutable_image"

    container_id="$(docker create \
        --platform "$platform" \
        --cpus "$TEST_CONTAINER_CPUS" \
        --memory "$TEST_CONTAINER_MEMORY" \
        --memory-swap "$TEST_CONTAINER_MEMORY" \
        --pull=never \
        --label "$LABEL_KEY=$RUN_ID" \
        --name "$name" \
        "$immutable_image" \
        /bin/sh -c 'while :; do sleep 3600; done')"

    docker start "$container_id" >/dev/null
    docker exec --user 0 "$container_id" sh -c 'cat /etc/os-release; printf "Container architecture: "; uname -m'
    if [[ "$distro" == arch && "$native_platform" == linux/arm64 && "$platform" == linux/amd64 ]]; then
        echo 'Arch uses amd64 emulation here; disabling only pacman downloader syscall sandbox inside this container.'
        docker exec --user 0 "$container_id" sh -c \
            "grep -q '^[[:space:]]*DisableSandboxSyscalls' /etc/pacman.conf || sed -i '/^\\[options\\]/a DisableSandboxSyscalls' /etc/pacman.conf"
    fi
    setup_log="$TEST_LOG_DIR/${distro}-container-setup.log"
    if docker exec --interactive --user 0 "$container_id" bash -se \
        >"$setup_log" 2>&1 <<'CONTAINER_SETUP'
set -euo pipefail

case "$(. /etc/os-release && printf '%s' "$ID")" in
ubuntu)
    export DEBIAN_FRONTEND=noninteractive
    timeout --signal=TERM --kill-after=15s 900s apt-get update -qq
    timeout --signal=TERM --kill-after=15s 900s apt-get -qq install -y --no-install-recommends \
        ca-certificates coreutils curl git sudo
    ;;
fedora)
    timeout --signal=TERM --kill-after=15s 900s dnf -q -y install \
        ca-certificates coreutils curl git sudo
    ;;
arch)
    timeout --signal=TERM --kill-after=15s 900s pacman -Sy --quiet --noconfirm --needed \
        ca-certificates coreutils curl git sudo
    ;;
*)
    printf 'Unexpected container OS: %s\n' "$(. /etc/os-release && printf '%s' "$ID")" >&2
    exit 1
    ;;
esac

if ! id workspace-user >/dev/null 2>&1; then
    useradd --create-home --home-dir /workspace-user --shell /bin/bash workspace-user
fi
test "$(getent passwd workspace-user | cut -d: -f6)" = /workspace-user
mkdir -p /etc/sudoers.d
printf '%s\n' 'workspace-user ALL=(ALL:ALL) NOPASSWD: ALL' >/etc/sudoers.d/90-mise-bootstrap-tests
chmod 0440 /etc/sudoers.d/90-mise-bootstrap-tests
visudo -c -f /etc/sudoers.d/90-mise-bootstrap-tests

case "$(uname -m)" in
x86_64)
    mise_asset='linux-x64'
    mise_sha256='f917e52216924ef0a8b4eca3f7004dfcff3b94665716ac5685fd53006a491eee'
    ;;
aarch64|arm64)
    mise_asset='linux-arm64'
    mise_sha256='1b46a14314c18f9bbce4bf6f88cc1fb3b31be8dd2b23327a851555f4e144fc61'
    ;;
*)
    printf 'Unsupported container architecture: %s\n' "$(uname -m)" >&2
    exit 1
    ;;
esac

mise_url="https://github.com/jdx/mise/releases/download/v2026.9.10/mise-v2026.9.10-${mise_asset}"
mise_tmp="$(mktemp -d)"
trap 'rm -rf "$mise_tmp"' EXIT
curl --fail --silent --show-error --location --retry 3 \
    --connect-timeout 15 --max-time 180 "$mise_url" --output "$mise_tmp/mise"
printf '%s  %s\n' "$mise_sha256" "$mise_tmp/mise" | sha256sum --check
install -m 0755 "$mise_tmp/mise" /usr/local/bin/mise

mise_output="$(mise --version)"
printf '%s\n' "$mise_output"
[[ "$mise_output" == *"2026.9.10"* ]] || {
    printf 'Unexpected mise version: %s\n' "$mise_output" >&2
    exit 1
}
CONTAINER_SETUP
    then
        awk '/mise|sha256sum|parsed OK|warning|Warning|failed/ { print; fflush() }' "$setup_log"
    else
        status=$?
        echo "Container prerequisite setup failed with exit $status. Full log: $setup_log" >&2
        tail -n 120 "$setup_log" >&2
        return "$status"
    fi

    if ((prepare_only)); then
        docker exec --user 0 "$container_id" /usr/local/bin/mise bootstrap --help
        return 0
    fi

    local user_root='/workspace-user/.config/mise'
    local root_root='/root/.config/mise'
    docker exec --user 0 "$container_id" mkdir -p "$user_root" "$root_root"
    COPYFILE_DISABLE=1 tar --no-xattrs -C "$SOURCE_ROOT" -cf - \
        config.toml setup-tasks.toml config.workstation.toml mise.workstation.lock locks dotfiles templates seeds setup-scripts resources |
        docker exec --interactive --user 0 "$container_id" tar -xf - -C "$user_root"
    COPYFILE_DISABLE=1 tar --no-xattrs -C "$SOURCE_ROOT" -cf - \
        config.toml setup-tasks.toml config.workstation.toml mise.workstation.lock locks dotfiles templates seeds setup-scripts resources |
        docker exec --interactive --user 0 "$container_id" tar -xf - -C "$root_root"
    docker exec --user 0 "$container_id" chown -R workspace-user:workspace-user /workspace-user/.config

    printf '\n--- Root bootstrap plan/config parse ---\n'
    run_container_step "$distro" root-profile-parse 120s - root -c \
        "test \"\$HOME\" = /root && cd '$root_root' && mise -E workstation bootstrap packages apply --dry-run"

    printf '\n--- Workstation bootstrap as workspace-user ---\n'
    run_container_step "$distro" workstation-bootstrap "${BOOTSTRAP_TIMEOUT_SECONDS}s" - workspace-user -c \
        "cd '$user_root' && MISE_JOBS=2 CARGO_BUILD_JOBS=2 mise -E workstation bootstrap --yes"

    printf '\n--- Second workstation bootstrap as workspace-user ---\n'
    run_container_step "$distro" workstation-bootstrap-second "${BOOTSTRAP_TIMEOUT_SECONDS}s" - workspace-user -c \
        "cd '$user_root' && MISE_JOBS=2 CARGO_BUILD_JOBS=2 mise bootstrap --yes"

    printf '\n--- Representative installed tool ---\n'
    run_container_step "$distro" installed-tool-check 120s - workspace-user -c \
        "cd '$user_root' && MISE_AUTO_INSTALL=0 mise exec -- node --version"

    printf '\n--- Fish configuration and command resolution ---\n'
    run_container_step "$distro" fish-syntax-check 120s - workspace-user -c \
        "cd '$user_root' && MISE_AUTO_INSTALL=0 mise exec -- fish -n /workspace-user/.config/fish/config.fish && printf '%s\n' 'fish config syntax OK'"
    run_container_step "$distro" fish-command-check 120s - workspace-user -c \
        "cd '$user_root' && MISE_AUTO_INSTALL=0 mise exec -- fish -i -c 'type -q node; or exit 1; type -q jj; or exit 1; type -q python3; or exit 1; printf \"node=%s\\njj=%s\\npython3=%s\\n\" (command -s node) (command -s jj) (command -s python3); node --version; and jj --version; and python3 --version'"

    printf '\n--- Representative versioned tools ---\n'
    run_container_step "$distro" jj-version-check 120s - workspace-user -c \
        "cd '$user_root' && MISE_AUTO_INSTALL=0 mise exec -- jj --version"
    run_container_step "$distro" python-version-check 120s - workspace-user -c \
        "cd '$user_root' && MISE_AUTO_INSTALL=0 mise exec -- python3 --version"
    run_container_step "$distro" nvim-clean-check 120s - workspace-user -c \
        "cd '$user_root' && MISE_AUTO_INSTALL=0 mise exec -- nvim --clean --headless +q"

    printf '\n--- SSH and resolved jj config permissions ---\n'
    # Shell expansions are intentionally deferred to the container login shell.
    # shellcheck disable=SC2016
    run_container_step "$distro" private-mode-check 120s - workspace-user -c \
        'test -d /workspace-user/.ssh && test ! -L /workspace-user/.ssh && test "$(stat -c %a /workspace-user/.ssh)" = 700 && test -f /workspace-user/.ssh/config && test ! -L /workspace-user/.ssh/config && test "$(stat -c %a /workspace-user/.ssh/config)" = 600 && test -d /workspace-user/.config/jj && test ! -L /workspace-user/.config/jj && test "$(stat -c %a /workspace-user/.config/jj)" = 700 && test -L /workspace-user/.config/jj/config.toml && test "$(realpath /workspace-user/.config/jj/config.toml)" = /workspace-user/.config/mise/dotfiles/.config/jj/config.toml && test "$(stat -L -c %a /workspace-user/.config/jj/config.toml)" = 600 && test -L /workspace-user/.config/jj/agent-config.toml && test "$(realpath /workspace-user/.config/jj/agent-config.toml)" = /workspace-user/.config/mise/dotfiles/.config/jj/agent-config.toml && test "$(stat -L -c %a /workspace-user/.config/jj/agent-config.toml)" = 600 && printf "%s\n" "SSH and resolved jj config permissions OK"'

    remove_owned_container "$container_id"
    container_id=''
}

if [[ "$distro_selection" == all ]]; then
    for distro in ubuntu fedora arch; do
        test_one_distro "$distro"
    done
else
    test_one_distro "$distro_selection"
fi
