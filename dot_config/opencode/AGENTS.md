# AGENTS.md (Concise Ops Guide)

1. Tooling: Prefer uv (uv sync | uv add | uv run <cmd>), ripgrep (rg), fd, fzf, bat, eza; output JSON + jq when available.
2. Build/Test: Python: uv sync; run single test: uv run pytest path::TestClass::test_name -q; all tests: uv run pytest -q; type check if mypy/ruff present: uv run ruff check . && uv run ruff format --check.
3. Imports: stdlib, then third-party, then local; absolute over relative; no unused imports; collapse from x import y,z ≤ 3 items else multiline.
4. Types: Use built-in generics (list[str]); use | for unions; avoid Optional[T] (use T | None); no implicit Any; add precise return types; prefer Protocol over duck-typing comments.
5. Formatting: Let ruff/formatter decide; 100 char soft wrap; no trailing whitespace; keep logical blank lines (1 between top-level defs).
6. Naming: snake_case for functions/vars; PascalCase for classes/Protocols; UPPER_SNAKE for constants; private helpers _prefixed.
7. Functions: Single responsibility; early return over deep nesting; avoid side effects in pure utilities; docstring only when behavior non-obvious.
8. Error Handling: Do not blanket try/except; raise specific errors; validate inputs early; never silence exceptions; only narrow try around failing call.
9. Data: Prefer dataclass / TypedDict for structured data; avoid bare dicts; immutable where possible (frozen dataclass) for configs.
10. Performance: Avoid premature micro-opts; measure; prefer generator expressions for streaming; batch IO and tool calls.
11. Git/JJ: Use jj for advanced flows (jj new -A, jj squash --from <c> --into <branch>); keep working copy clean; meaningful commit messages (why > what).
12. Search & Refactor: Use rg for locating symbols; never raw grep; verify unique match before edit; batch related edits.
13. JSON/CLI: Always request machine-readable (-o json/--json); post-process with jq; never parse ad-hoc text when JSON exists.
14. Tests: No value hard-coding; write deterministic tests; isolate external services behind interfaces; fast unit tests first.
15. State & Side Effects: Pure functions preferred; isolate IO at edges; configuration via explicit parameters not globals.
16. Security: No secrets committed; inspect diffs for keys; fail build if secret detected.
17. Docs/READMEs: ≤50 lines; quick start + key commands; avoid fluff; update when interface changes.
18. Multi-Agent: Read PLAN.md if present; follow task list; update status files; avoid overlapping edits; use worktrees if large parallel work.
19. Consistency: Match existing style before improving; do not mix paradigms mid-file; refactor incrementally with tests.
20. Priority: Correctness > Clarity > Performance > Brevity; ask on conflicting instructions.
