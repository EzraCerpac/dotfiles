"""Rendered Git configuration must only use settings Git understands.

Git silently ignores unknown keys and invalid whitespace rules, so a typo
never fails loudly; ``git help --config`` is the authority used here.
"""

from __future__ import annotations

import functools
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

from lib.prereq import requires
from lib.tera import render_profile_dotfile

# Sections owned by other programs that read Git's configuration file.
THIRD_PARTY_SECTIONS = frozenset({"delta"})
# Valid keys documented in gitattributes(5) rather than in `git help --config`.
GITATTRIBUTES_KEYS = ("filter.<driver>.process", "filter.<driver>.required")
WHITESPACE_RULES = frozenset(
    {
        "blank-at-eol",
        "blank-at-eof",
        "trailing-space",
        "space-before-tab",
        "indent-with-non-tab",
        "tab-in-indent",
        "cr-at-eol",
    }
)


@functools.cache
def documented_patterns() -> tuple[re.Pattern[str], ...]:
    listing = subprocess.run(["git", "help", "--config"], capture_output=True, text=True, check=True).stdout
    patterns = []
    for line in (*listing.splitlines(), *GITATTRIBUTES_KEYS):
        name = line.strip()
        if not name or " " in name:
            continue
        # "url.<base>.insteadOf" and "credential.<url>.*" match any subsection.
        regex = re.sub(r"<[^>]+>|\\\*", ".+", re.escape(name).replace(r"\<", "<").replace(r"\>", ">"))
        patterns.append(re.compile(f"{regex}$", re.IGNORECASE))
    return tuple(patterns)


def config_entries(text: str) -> list[tuple[str, str]]:
    listing = subprocess.run(
        ["git", "config", "--file", "-", "--list", "--null"], input=text, capture_output=True, text=True, check=True
    ).stdout
    entries = []
    for record in filter(None, listing.split("\0")):
        key, _, value = record.partition("\n")
        entries.append((key, value))
    return entries


@requires("mise", "git")
class RenderedGitConfigTests(unittest.TestCase):
    def _render(self, profile: str) -> str:
        with tempfile.TemporaryDirectory() as scratch:
            return render_profile_dotfile(profile, "~/.config/git/config", Path(scratch))

    def test_every_key_is_documented_by_git(self) -> None:
        for profile in ("workstation", "nas"):
            with self.subTest(profile=profile):
                undocumented = [
                    key
                    for key, _ in config_entries(self._render(profile))
                    if key.split(".", 1)[0] not in THIRD_PARTY_SECTIONS
                    and not any(pattern.match(key) for pattern in documented_patterns())
                ]
                self.assertEqual(undocumented, [], f"{profile}: keys git does not document")

    def test_whitespace_rules_are_valid(self) -> None:
        for profile in ("workstation", "nas"):
            with self.subTest(profile=profile):
                for key, value in config_entries(self._render(profile)):
                    if key != "core.whitespace":
                        continue
                    for rule in filter(None, (part.strip() for part in value.split(","))):
                        name = rule.removeprefix("-")
                        self.assertTrue(
                            name in WHITESPACE_RULES or re.fullmatch(r"tabwidth=\d+", name),
                            f"{profile}: unknown core.whitespace rule {rule!r}",
                        )

    def test_profiles_share_identity_and_defaults(self) -> None:
        import tomllib

        identity = tomllib.loads((Path(__file__).resolve().parents[1] / "config.toml").read_text())["vars"]
        for profile in ("workstation", "nas"):
            with self.subTest(profile=profile):
                entries = dict(config_entries(self._render(profile)))
                self.assertEqual(entries["user.name"], identity["name"])
                self.assertEqual(entries["user.email"], identity["email"])
                for key, value in {
                    "merge.conflictstyle": "zdiff3",
                    "diff.algorithm": "histogram",
                    "fetch.prune": "true",
                    "push.autosetupremote": "true",
                }.items():
                    self.assertEqual(entries.get(key), value, key)
                # Legacy transport workarounds that Git's docs advise against.
                self.assertNotIn("http.version", entries)
                self.assertNotIn("http.postbuffer", entries)


if __name__ == "__main__":
    unittest.main()
