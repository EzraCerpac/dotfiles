# AGENTS.md (Concise Ops Guide)

- Tooling: Prefer uv (uv sync | uv add | uv run <cmd>), cargo, ripgrep (rg), fd, fzf, bat, eza; output JSON + jq when available.
- Build/Test: Python: uv sync; run single test: uv run pytest path::TestClass::test_name -q; all tests: uv run pytest -q; type check if mypy/ruff present: uv run ruff check . && uv run ruff format --check.
- Functions: Single responsibility; early return over deep nesting; avoid side effects in pure utilities; docstring only when behavior non-obvious.
- Tests: No value hard-coding; write deterministic tests; isolate external services behind interfaces; fast unit tests first.
- State & Side Effects: Pure functions preferred; isolate IO at edges; configuration via explicit parameters not globals.
- Docs/READMEs: ≤50 lines; quick start + key commands; avoid fluff; update when interface changes.
- Consistency: Match existing style before improving; do not mix paradigms mid-file; refactor incrementally with tests.
- Priority: Correctness > Clarity > Performance > Brevity; ask on conflicting instructions.
