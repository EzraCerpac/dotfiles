"""Parse every shell source of the manager without running it."""

from __future__ import annotations

import subprocess
import unittest
from pathlib import Path

MANAGER = Path(__file__).resolve().parents[1]


def _sources() -> list[Path]:
    return sorted(path for path in MANAGER.rglob("*")
                  if path.is_file() and "dots-up" not in path.relative_to(MANAGER).parts[:1])


def _interpreter(path: Path) -> str | None:
    with path.open("rb") as stream:
        first = stream.readline(128)
    shebang = first.decode("utf-8", "replace").strip() if first.startswith(b"#!") else ""
    if "bash" in shebang or (not shebang and path.suffix == ".sh"):
        return "bash"
    if shebang.split("/")[-1] in {"sh", "env sh"}:
        return "sh"
    return None


class ShellSyntaxTests(unittest.TestCase):
    def test_posix_and_bash_sources_parse(self) -> None:
        checked = 0
        for path in _sources():
            interpreter = _interpreter(path)
            if interpreter is None:
                continue
            with self.subTest(path=str(path.relative_to(MANAGER))):
                result = subprocess.run([interpreter, "-n", str(path)], capture_output=True, text=True, check=False)
                self.assertEqual(result.returncode, 0, f"{path.relative_to(MANAGER)}:\n{result.stderr}")
            checked += 1
        self.assertGreater(checked, 20, "shell source discovery found suspiciously few scripts")


if __name__ == "__main__":
    unittest.main()
