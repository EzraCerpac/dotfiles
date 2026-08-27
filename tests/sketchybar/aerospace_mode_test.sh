#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
FIXTURES="$ROOT/tests/sketchybar/fixtures"
MODULE="$ROOT/dot_config/sketchybar/plugins/executable_aerospace_mode.sh"
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT

export PATH="$FIXTURES/bin:/usr/bin:/bin"
export CONFIG_DIR="$FIXTURES/config"
export AEROSPACE_STATE="$TEST_TMP/aerospace"
export SKETCHYBAR_STATE="$TEST_TMP/sketchybar"
export SKETCHYBAR_LOG="$TEST_TMP/sketchybar.log"

mkdir -p "$AEROSPACE_STATE" "$SKETCHYBAR_STATE"
: > "$SKETCHYBAR_LOG"
printf 'main\n' > "$AEROSPACE_STATE/mode"
touch "$SKETCHYBAR_STATE/aerospace.mode"

assert_set_contains() {
  property=$1
  grep -F -- $'--set\taerospace.mode\t' "$SKETCHYBAR_LOG" \
    | grep -F -- $'\t'"$property" >/dev/null || {
      printf 'missing %s\n' "$property" >&2
      exit 1
    }
}

NAME=aerospace.mode /bin/bash "$MODULE"
assert_set_contains 'drawing=off'
assert_set_contains 'label.drawing=off'

: > "$SKETCHYBAR_LOG"
MODE=service NAME=aerospace.mode /bin/bash "$MODULE"
assert_set_contains 'drawing=on'
assert_set_contains 'label.drawing=on'
assert_set_contains 'label=SERVICE'
assert_set_contains 'label.color=red'

printf 'aerospace mode tests passed\n'
