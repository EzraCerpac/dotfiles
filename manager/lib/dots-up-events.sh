#!/usr/bin/env bash

dots_up_event_sink_enabled() {
    [[ -n "${DOTS_UP_STREAM_NONCE:-}" || -n "${DOTS_UP_EVENT_FD:-}" ]]
}

dots_up_event_json() {
    dots_up_event_sink_enabled || return 0
    if [[ -n "${DOTS_UP_EVENT_JQ:-}" && -x "$DOTS_UP_EVENT_JQ" ]]; then
        "$DOTS_UP_EVENT_JQ" -cn "$@" 2>/dev/null || true
    elif command -v jq >/dev/null 2>&1; then
        jq -cn "$@" 2>/dev/null || true
    fi
}

dots_up_emit_event() {
    local json="$1"
    [[ -n "$json" ]] || return 0
    if [[ -n "${DOTS_UP_STREAM_NONCE:-}" ]]; then
        printf '\036dots-up/1:%s:%s\037' "$DOTS_UP_STREAM_NONCE" "$json" 2>/dev/null || true
    elif [[ -n "${DOTS_UP_EVENT_FD:-}" ]]; then
        printf '%s\n' "$json" >&"$DOTS_UP_EVENT_FD" 2>/dev/null || true
    fi
}

dots_up_emit_notice() {
    local severity="$1" summary="$2" action="${3:-}" stage="${4:-}" json
    json="$(dots_up_event_json --arg severity "$severity" --arg summary "$summary" --arg action "$action" --arg stage "$stage" \
        '{v:1,kind:"notice",severity:$severity,summary:$summary,action:$action,stage:$stage}')"
    dots_up_emit_event "$json"
}

dots_up_emit_item() {
    local id="$1" group="$2" label="$3" status="$4" summary="$5" json
    json="$(dots_up_event_json --arg id "$id" --arg group "$group" --arg label "$label" --arg status "$status" --arg summary "$summary" \
        '{v:1,kind:"item_upsert",id:$id,group:$group,label:$label,status:$status,summary:$summary,action:"",before:"",after:""}')"
    dots_up_emit_event "$json"
}
