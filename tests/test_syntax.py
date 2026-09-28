"""Parse every deployed or executed shell source without running it.

Rendered Tera templates are excluded; their output is exercised by the
template tests. Each interpreter is optional so the suite still runs on hosts
that lack Fish or zsh.
"""

from __future__ import annotations

import shutil
import subprocess
import unittest
from pathlib import Path

from lib.prereq import requires

ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIRS = ("dotfiles", "setup-scripts", "tests")
ZSH_SOURCES = ("dotfiles/.zshrc", "dotfiles/.zshenv", "dotfiles/.zprofile")


def _sources() -> list[Path]:
    files: list[Path] = []
    for directory in SOURCE_DIRS:
        files.extend(path for path in (ROOT / directory).rglob("*") if path.is_file() and path.suffix != ".tera")
    return sorted(files)


def _shebang(path: Path) -> str:
    with path.open("rb") as stream:
        first = stream.readline(128)
    return first.decode("utf-8", "replace").strip() if first.startswith(b"#!") else ""


def _interpreter(path: Path) -> str | None:
    shebang = _shebang(path)
    if "bash" in shebang or (not shebang and path.suffix == ".sh"):
        return "bash"
    if shebang.split("/")[-1] in {"sh", "env sh"}:
        return "sh"
    return None


class ShellSyntaxTests(unittest.TestCase):
    def _assert_parses(self, command: list[str], path: Path) -> None:
        result = subprocess.run([*command, str(path)], capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, f"{path.relative_to(ROOT)}:\n{result.stderr}")

    def test_posix_and_bash_sources_parse(self) -> None:
        checked = 0
        for path in _sources():
            interpreter = _interpreter(path)
            if interpreter is None:
                continue
            with self.subTest(path=str(path.relative_to(ROOT))):
                self._assert_parses([interpreter, "-n"], path)
            checked += 1
        self.assertGreater(checked, 50, "shell source discovery found suspiciously few scripts")

    @requires("fish")
    def test_fish_sources_parse(self) -> None:
        fish_files = [path for path in _sources() if path.suffix == ".fish"]
        self.assertTrue(fish_files)
        for path in fish_files:
            with self.subTest(path=str(path.relative_to(ROOT))):
                self._assert_parses([shutil.which("fish") or "fish", "--no-execute"], path)

    @requires("zsh")
    def test_zsh_startup_files_parse(self) -> None:
        for name in ZSH_SOURCES:
            with self.subTest(path=name):
                self._assert_parses([shutil.which("zsh") or "zsh", "-n"], ROOT / name)


if __name__ == "__main__":
    unittest.main()
