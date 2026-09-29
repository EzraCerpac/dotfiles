"""Relative links in the README and docs point at files that exist."""

from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LINK = re.compile(r"\]\(([^)\s]+)\)")


class DocumentationLinkTests(unittest.TestCase):
    def test_relative_links_resolve(self) -> None:
        broken = []
        for document in [ROOT / "README.md", *sorted((ROOT / "docs").glob("*.md"))]:
            for target in LINK.findall(document.read_text()):
                if re.match(r"[a-z]+:", target) or target.startswith("#"):
                    continue
                if not (document.parent / target.split("#", 1)[0]).exists():
                    broken.append(f"{document.relative_to(ROOT)} -> {target}")
        self.assertEqual(broken, [])


if __name__ == "__main__":
    unittest.main()
