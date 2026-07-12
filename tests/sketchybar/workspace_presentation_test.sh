#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
FIXTURES="$ROOT/tests/sketchybar/fixtures"
MODULE="$ROOT/dot_config/sketchybar/plugins/executable_workspace_presentation.sh"
EVENT_ADAPTER="$ROOT/dot_config/sketchybar/plugins/executable_space_windows.sh"
CLICK_ADAPTER="$ROOT/dot_config/sketchybar/plugins/executable_space.sh"
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT

export PATH="$FIXTURES/bin:/usr/bin:/bin"
export TMPDIR="$TEST_TMP"
export CONFIG_DIR="$FIXTURES/config"
export AEROSPACE_STATE="$TEST_TMP/aerospace"
export AEROSPACE_LOG="$TEST_TMP/aerospace.log"
export DISPATCH_LOG="$TEST_TMP/dispatch.log"
export SKETCHYBAR_STATE="$TEST_TMP/sketchybar"
export SKETCHYBAR_LOG="$TEST_TMP/sketchybar.log"

mkdir -p "$AEROSPACE_STATE" "$SKETCHYBAR_STATE"
: > "$AEROSPACE_LOG"
: > "$DISPATCH_LOG"
: > "$SKETCHYBAR_LOG"

write_state() {
  printf '%s' "$2" > "$AEROSPACE_STATE/$1"
}

set_initial_state() {
  write_state monitors $'1 | Main\n2 | External\n'
  write_state focused $'2\n'
  write_state workspaces_1 $'1\n2\n'
  write_state empty_1 $'2\n'
  write_state workspaces_2 $'M\n'
  write_state empty_2 ''
  write_state windows_1 $'101 | Safari | Browser\n102 | Code | Editor\n'
  write_state windows_2 ''
  write_state windows_M $'103 | WezTerm | Shell\n'
}

assert_set_contains() {
  item=$1
  property=$2
  if ! grep -F -- $'--set\t'"$item"$'\t' "$SKETCHYBAR_LOG" | grep -F -- $'\t'"$property"$'\t' >/dev/null; then
    printf 'missing %s on %s\n' "$property" "$item" >&2
    exit 1
  fi
}

set_initial_state
/bin/bash "$MODULE"

assert_set_contains space.1 'label=  :safari: :code:'
assert_set_contains space.1 display=1
assert_set_contains space.1 icon.highlight=false
assert_set_contains space.2 'label= —'
assert_set_contains space.2 display=1
assert_set_contains space.2 icon.highlight=true
assert_set_contains space.M 'label=  :terminal:'
assert_set_contains space.M display=2

if [[ $(grep -c $'\ticon.highlight=true\t' "$SKETCHYBAR_LOG") -ne 1 ]]; then
  printf 'expected exactly one highlighted workspace\n' >&2
  exit 1
fi

write_state focused $'M\n'
touch "$SKETCHYBAR_STATE/space.Z"
: > "$SKETCHYBAR_LOG"
/bin/bash "$MODULE"

assert_set_contains space.2 display=0
assert_set_contains space.2 icon.highlight=false
assert_set_contains space.M display=2
assert_set_contains space.M icon.highlight=true
assert_set_contains space.Z display=0
assert_set_contains space.Z icon.highlight=false

: > "$SKETCHYBAR_LOG"
if FAIL_QUERY_WORKSPACE=M /bin/bash "$MODULE"; then
  printf 'expected failed AeroSpace query to fail reconcile\n' >&2
  exit 1
fi
if [[ -s $SKETCHYBAR_LOG ]]; then
  printf 'failed snapshot emitted SketchyBar commands\n' >&2
  exit 1
fi

: > "$SKETCHYBAR_LOG"
if FAIL_ICON_APP=WezTerm /bin/bash "$MODULE"; then
  printf 'expected failed icon projection to fail reconcile\n' >&2
  exit 1
fi
if [[ -s $SKETCHYBAR_LOG ]]; then
  printf 'failed projection emitted SketchyBar commands\n' >&2
  exit 1
fi

SENDER=forced /bin/bash "$EVENT_ADAPTER"
SENDER=aerospace_workspace_change /bin/bash "$EVENT_ADAPTER"
SENDER=front_app_switched /bin/bash "$EVENT_ADAPTER"
if [[ $(grep -c reconcile "$DISPATCH_LOG") -ne 2 ]]; then
  printf 'event adapter dispatched wrong event set\n' >&2
  exit 1
fi

: > "$SKETCHYBAR_LOG"
lock_ready="$TEST_TMP/lock.ready"
/usr/bin/lockf -k "$TMPDIR/sketchybar-workspace-presentation.lock" \
  /bin/sh -c 'touch "$1"; sleep 1' _ "$lock_ready" &
lock_holder=$!
while [[ ! -e $lock_ready ]]; do
  sleep 0.01
done
/bin/bash "$MODULE" &
waiting_reconcile=$!
sleep 0.1
if [[ -s $SKETCHYBAR_LOG ]]; then
  printf 'reconcile emitted while another reconcile held lock\n' >&2
  exit 1
fi
wait "$lock_holder"
wait "$waiting_reconcile"
if [[ ! -s $SKETCHYBAR_LOG ]]; then
  printf 'waiting reconcile did not run after lock release\n' >&2
  exit 1
fi

: > "$AEROSPACE_LOG"
SENDER=mouse.clicked BUTTON=left MODIFIER= NAME=space.M /bin/bash "$CLICK_ADAPTER"
SENDER=mouse.clicked BUTTON=left MODIFIER=shift NAME=space.1 /bin/bash "$CLICK_ADAPTER"
SENDER=mouse.clicked BUTTON=right MODIFIER= NAME=space.2 /bin/bash "$CLICK_ADAPTER"

if [[ $(cat "$AEROSPACE_LOG") != $'workspace\tM' ]]; then
  printf 'click adapter accepted wrong click set\n' >&2
  exit 1
fi

printf 'workspace presentation tests passed\n'
