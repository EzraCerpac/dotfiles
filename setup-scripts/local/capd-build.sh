#!/usr/bin/env bash
set -euo pipefail
# Keep the established build task as an alias for the safe fork update flow.
exec bash "$(dirname -- "${BASH_SOURCE[0]}")/capd-update.sh" --stage-only "$@"
