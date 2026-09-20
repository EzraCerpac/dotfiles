# Herdr owns this completion spec. Keep the tracked file as a small lazy shim
# so upgrades refresh the native completion without committing generated code.
if command -q herdr
    command herdr completion fish 2>/dev/null | source
end
