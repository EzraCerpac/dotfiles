#!/usr/bin/env bash
# Hand terminal control to an interactive native operation, then restore it.
dots_terminal_run() {
    local id="$1" label="$2" ack status json
    shift 2
    DOTS_HANDOFF_FAILED=0
    json="$(dots_up_event_json --arg id "$id" --arg label "$label" \
        '{v:1,kind:"stage_start",id:$id,group:"Software",label:$label,terminal:"handoff"}')"
    if [[ -n "${DOTS_UP_ACK_FD:-}" && -z "$json" ]]; then
        DOTS_HANDOFF_FAILED=1
        printf 'dots: could not create terminal handoff event\n' >&2
        return 1
    fi
    dots_up_emit_event "$json"
    if [[ -n "${DOTS_UP_ACK_FD:-}" ]]; then
        if ! IFS= read -r ack <&"$DOTS_UP_ACK_FD" || [[ "$ack" != "go:$id" ]]; then
            DOTS_HANDOFF_FAILED=1
            printf 'dots: terminal handoff failed\n' >&2
            json="$(dots_up_event_json --arg id "$id" --arg label "$label" \
                '{v:1,kind:"stage_end",id:$id,label:$label,status:"failed",exit_code:1,summary:"terminal handoff failed"}')"
            dots_up_emit_event "$json"
            return 1
        fi
    fi
    if "$@"; then status=0; else status=$?; fi
    json="$(dots_up_event_json --arg id "$id" --arg label "$label" --argjson code "$status" \
        '{v:1,kind:"stage_end",id:$id,label:$label,status:(if $code == 0 then "ok" else "failed" end),exit_code:$code,summary:(if $code == 0 then "completed" else "failed" end)}')"
    dots_up_emit_event "$json"
    return "$status"
}
