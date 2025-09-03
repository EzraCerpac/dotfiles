# AGENTS.md (Concise Ops Guide)

- Tooling: Prefer uv (uv sync | uv add | uv run <cmd>), ripgrep (rg), fd, fzf, bat, eza; output JSON + jq when available.
- Build/Test: Python: uv sync; run single test: uv run pytest path::TestClass::test_name -q; all tests: uv run pytest -q; type check if mypy/ruff present: uv run ruff check . && uv run ruff format --check.
- Imports: stdlib, then third-party, then local; absolute over relative; no unused imports; collapse from x import y,z ≤ 3 items else multiline.
- Types: Use built-in generics (list[str]); use | for unions; avoid Optional[T] (use T | None); no implicit Any; add precise return types; prefer Protocol over duck-typing comments.
- Formatting: Let ruff/formatter decide; 100 char soft wrap; no trailing whitespace; keep logical blank lines (1 between top-level defs).
- Naming: snake_case for functions/vars; PascalCase for classes/Protocols; UPPER_SNAKE for constants; private helpers _prefixed.
- Functions: Single responsibility; early return over deep nesting; avoid side effects in pure utilities; docstring only when behavior non-obvious.
- Error Handling: Do not blanket try/except; raise specific errors; validate inputs early; never silence exceptions; only narrow try around failing call.
- Data: Prefer dataclass / TypedDict for structured data; avoid bare dicts; immutable where possible (frozen dataclass) for configs.
- Search & Refactor: Use rg for locating symbols; never raw grep; verify unique match before edit; batch related edits.
- JSON/CLI: Always request machine-readable (-o json/--json); post-process with jq; never parse ad-hoc text when JSON exists.
- Tests: No value hard-coding; write deterministic tests; isolate external services behind interfaces; fast unit tests first.
- State & Side Effects: Pure functions preferred; isolate IO at edges; configuration via explicit parameters not globals.
- Docs/READMEs: ≤50 lines; quick start + key commands; avoid fluff; update when interface changes.
- Consistency: Match existing style before improving; do not mix paradigms mid-file; refactor incrementally with tests.
- Priority: Correctness > Clarity > Performance > Brevity; ask on conflicting instructions.
