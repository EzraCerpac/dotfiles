# Tinymist owns this completion spec. Keep the tracked file as a small lazy
# shim so upgrades refresh the native completion without generated bulk code.
if command -q tinymist
    command tinymist completion fish 2>/dev/null | source
end
