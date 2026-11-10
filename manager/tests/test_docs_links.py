"""Relative links in the manager's documentation point at files inside the manager."""

from __future__ import annotations

import re
import unittest
from pathlib import Path

MANAGER = Path(__file__).resolve().parents[1]
LINK = re.compile(r"\]\(([^)\s]+)\)")


class DocumentationLinkTests(unittest.TestCase):
    def test_relative_links_resolve_inside_the_manager(self) -> None:
        documents = [path for path in sorted(MANAGER.rglob("*.md")) if "tests" not in path.relative_to(MANAGER).parts]
        self.assertGreater(len(documents), 3)
        broken = []
        for document in documents:
            for target in LINK.findall(document.read_text()):
                if re.match(r"[a-z]+:", target) or target.startswith("#"):
                    continue
                resolved = (document.parent / target.split("#", 1)[0]).resolve()
                if not resolved.exists() or not resolved.is_relative_to(MANAGER.resolve()):
                    broken.append(f"{document.relative_to(MANAGER)} -> {target}")
        self.assertEqual(broken, [])


if __name__ == "__main__":
    unittest.main()
