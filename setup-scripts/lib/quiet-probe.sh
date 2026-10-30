#!/usr/bin/env bash

# Keep successful health checks quiet, but retain both streams on failure.
quiet_probe() {
    local output result
    if output="$("$@" 2>&1)"; then
        return 0
    else
        result=$?
        printf '%s\n' "$output" >&2
        return "$result"
    fi
}
