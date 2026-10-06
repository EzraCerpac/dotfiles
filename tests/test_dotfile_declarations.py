"""Every managed source file is declared, and every declaration has a source.

Static app trees can use selected groups; individual files and templates keep
their explicit declarations. Application state beside group links stays
unmanaged. This test catches missing source ownership in either form.
"""

from __future__ import annotations

import re
import subprocess
import tomllib
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONFIGS = ("config.toml", "config.workstation.toml", "config.nas.toml")
MANAGED_TREES = ("dotfiles", "templates", "seeds")

# Sources used by something other than a [dotfiles] declaration.
INDIRECT = {
    "dotfiles/.config/herdr/config.toml": "read by templates/.config/herdr/config.tera",
    "templates/.config/herdr/config.tera": "declared per host by setup-scripts/local/shell-select.sh",
    "seeds/.codex/config.toml": "seeded once by setup-scripts/local/seed-configs.sh",
    "seeds/.config/aegis/config.json": "seeded once by setup-scripts/local/seed-configs.sh",
    "seeds/.config/karabiner/karabiner.json": "seeded once by setup-scripts/local/seed-configs.sh",
    "seeds/.config/nvim/lazyvim.json": "seeded once by setup-scripts/local/seed-configs.sh",
}


def declarations() -> dict[str, dict]:
    entries: dict[str, dict] = {}
    for name in CONFIGS:
        config = tomllib.loads((ROOT / name).read_text())
        for target, entry in config.get("dotfiles", {}).items():
            entries[f"{name}:{target}"] = entry
        groups = config.get("dotfile_groups", {})
        selected = config.get("bootstrap", {}).get("dotfile_groups", list(groups))
        for group_name in selected:
            group = groups[group_name]
            source_root = ROOT / 'dotfiles' / group['root']
            if not source_root.is_dir():
                raise ValueError(f"missing group source: {source_root}")
            # These groups deliberately own complete static trees, without
            # templates, exclusions, renames or explicit entry overrides.
            if set(group) != {'root', 'target', 'mode', 'relative'} or group['mode'] != 'symlink-each':
                raise ValueError(f"unsupported static group shape: {group_name}")
            for source in source_root.rglob('*'):
                if source.is_file():
                    target = group['target'].rstrip('/') + '/' + source.relative_to(source_root).as_posix()
                    entries[f"{name}:{target}"] = {'source': source.relative_to(ROOT).as_posix(), 'mode': 'symlink'}
    return entries


def tracked(*trees: str) -> set[str]:
    listing = subprocess.run(["git", "ls-files", "-z", "--", *trees], cwd=ROOT, capture_output=True, text=True, check=True)
    return set(filter(None, listing.stdout.split("\0")))


class DotfileDeclarationTests(unittest.TestCase):
    def test_every_declared_source_exists(self) -> None:
        missing = [
            f"{key} -> {entry['source']}"
            for key, entry in declarations().items()
            if "source" in entry and not (ROOT / entry["source"]).is_file()
        ]
        self.assertEqual(missing, [])

    def test_every_managed_file_is_declared_or_explained(self) -> None:
        declared = {entry["source"] for entry in declarations().values() if "source" in entry}
        undeclared = sorted(tracked(*MANAGED_TREES) - declared - INDIRECT.keys())
        self.assertEqual(undeclared, [], "declare these in a config file, archive them, or explain them in INDIRECT")

    def test_indirect_sources_are_still_referenced(self) -> None:
        for source in INDIRECT:
            with self.subTest(source=source):
                self.assertTrue((ROOT / source).is_file())
                uses = subprocess.run(
                    ["git", "grep", "-l", "-F", source.split("/", 1)[1], "--", "setup-scripts", "templates"],
                    cwd=ROOT, capture_output=True, text=True, check=False,
                )
                self.assertTrue(uses.stdout.strip(), f"nothing references {source}; archive or delete it")

    def test_archive_is_never_deployed(self) -> None:
        deployed = [key for key, entry in declarations().items() if entry.get("source", "").startswith("archive/")]
        self.assertEqual(deployed, [])

    def test_declarations_do_not_restate_every_supported_os(self) -> None:
        # An entry applies on every OS unless restricted; listing both is noise.
        redundant = [
            key
            for key, entry in declarations().items()
            if sorted(variant.get("os") for variant in entry.get("variants", []) if set(variant) == {"os"})
            == ["linux", "macos"]
        ]
        self.assertEqual(redundant, [])



class DocumentedEditTargetsTests(unittest.TestCase):
    """`dotfiles edit` examples in the docs name targets that are still managed."""

    EXAMPLE = re.compile(r"bootstrap dotfiles edit (--apply )?(~/\S+)")

    def test_documented_edit_targets_are_declared(self) -> None:
        by_target = {key.split(":", 1)[1]: entry for key, entry in declarations().items()}
        documents = [ROOT / "README.md", *sorted((ROOT / "docs").glob("*.md"))]
        found = 0
        for document in documents:
            for apply, target in self.EXAMPLE.findall(document.read_text()):
                found += 1
                with self.subTest(document=document.name, target=target):
                    self.assertIn(target, by_target, "the example edits an undeclared target")
                    if apply:
                        self.assertEqual(by_target[target].get("mode"), "template", "--apply edits a template")
        self.assertGreater(found, 0, "no documented examples found; update the pattern")

if __name__ == "__main__":
    unittest.main()
