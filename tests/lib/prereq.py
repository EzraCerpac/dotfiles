"""Locate optional test prerequisites so suites skip instead of crashing.

Tests exercise real tools (mise, jj, Neovim, Typst, ...) when they are
installed and skip with a clear reason when they are not. ``tests/run`` and CI
install the full set, so a skip there means a missing CI prerequisite.
"""

from __future__ import annotations

import functools
import os
import shutil
import subprocess
import unittest
from pathlib import Path
from typing import Callable, TypeVar

_T = TypeVar("_T")


@functools.cache
def mise_binary() -> str | None:
    """Return the mise executable tests should use, or ``None`` if absent.

    An explicit ``SETUP_TEST_MISE`` (or the older ``MISE_TEST_BINARY``) wins,
    then ``mise`` on ``PATH``, then the official installer location.
    """
    for variable in ("SETUP_TEST_MISE", "MISE_TEST_BINARY"):
        explicit = os.environ.get(variable)
        if explicit:
            return explicit
    found = shutil.which("mise")
    if found:
        return found
    installed = Path.home() / ".local/bin/mise"
    return str(installed) if installed.is_file() and os.access(installed, os.X_OK) else None


def tool_path(tool: str) -> str | None:
    """Resolve ``tool`` the same way the tests will invoke it."""
    return mise_binary() if tool == "mise" else shutil.which(tool)


@functools.cache
def nvim_has_parser(language: str) -> bool:
    """Whether headless Neovim can load the tree-sitter parser for ``language``."""
    nvim = shutil.which("nvim")
    if nvim is None:
        return False
    # Older Neovim raises for a missing parser; newer releases return nil.
    probe = (
        f"lua local ok, added = pcall(vim.treesitter.language.add, {language!r}) "
        "if not (ok and added) then vim.cmd('cquit 1') end"
    )
    result = subprocess.run(
        [nvim, "--headless", "-u", "NONE", "-c", probe, "-c", "qall!"],
        capture_output=True,
        check=False,
        timeout=30,
    )
    return result.returncode == 0


def requires(*tools: str) -> Callable[[_T], _T]:
    """Skip a test or test case unless every named executable is available."""
    missing = [tool for tool in tools if tool_path(tool) is None]
    return unittest.skipIf(bool(missing), f"requires {', '.join(missing)}")


def requires_nvim_parser(language: str) -> Callable[[_T], _T]:
    """Skip unless headless Neovim has the ``language`` tree-sitter parser."""
    return unittest.skipUnless(
        nvim_has_parser(language), f"requires Neovim with the {language} tree-sitter parser"
    )


if __name__ == "__main__":
    # Shell tests: `python3 tests/lib/prereq.py mise jj || exit $?` skips (77)
    # with a message when any named tool is absent.
    import sys

    absent = [tool for tool in sys.argv[1:] if tool_path(tool) is None]
    if absent:
        print(f"skip: requires {', '.join(absent)}")
        raise SystemExit(77)
