from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import types
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "dot_local/share/humanize-text/executable_main.py"
SPEC = importlib.util.spec_from_file_location("humanize_text_main", MODULE_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class ConfigurationTests(unittest.TestCase):
    def test_local_config_overrides_defaults_and_cli_wins(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            defaults = root / "defaults.toml"
            local = root / "config.toml"
            defaults.write_text(
                """
[proxy]
base_url = "http://127.0.0.1:8317/v1"
config_path = "~/.cli-proxy-api/config.yaml"
[llm]
model = "default-model"
[presets.typst]
temperature = 1.0
paragraphs = true
[typst]
compile_command = []
""",
                encoding="utf-8",
            )
            local.write_text('[llm]\nmodel = "chosen-model"\n', encoding="utf-8")
            settings = MODULE.load_settings(
                "typst",
                temperature=0.8,
                paragraph_override=False,
                defaults_path=defaults,
                local_path=local,
            )
            self.assertEqual(settings.model, "chosen-model")
            self.assertEqual(settings.temperature, 0.8)
            self.assertFalse(settings.paragraphs)

    def test_proxy_key_ignores_example_values(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "config.yaml"
            path.write_text('api-keys:\n  - "your-api-key-1"\n  - "real-local-key"\n', encoding="utf-8")
            self.assertEqual(MODULE.read_proxy_key(path), "real-local-key")

    def test_proxy_can_explicitly_disable_local_auth(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "config.yaml"
            path.write_text("api-keys: []\n", encoding="utf-8")
            self.assertIsNone(MODULE.read_proxy_key(path))

    @patch("subprocess.run", side_effect=subprocess.CalledProcessError(1, ["security"]))
    def test_missing_niutrans_key_is_optional(self, _run) -> None:
        self.assertIsNone(MODULE.read_niutrans_key())

    def test_google_fallback_only_replaces_niutrans_temporarily(self) -> None:
        def original(*args, **kwargs):
            return "niutrans"

        pipeline = types.SimpleNamespace(
            niutrans_translate=original,
            google_translate=lambda text, source, target: f"google:{source}:{target}:{text}",
        )
        with MODULE.google_fallback_for_niutrans(pipeline, enabled=True):
            self.assertEqual(pipeline.niutrans_translate("text", "fi", "en", None), "google:fi:en:text")
        self.assertIs(pipeline.niutrans_translate, original)

    @patch("time.sleep")
    def test_google_translation_retries_without_repeating_pipeline(self, sleep) -> None:
        attempts = 0

        def flaky_google(text, source, target):
            nonlocal attempts
            attempts += 1
            if attempts < 3:
                raise RuntimeError("TranslationNotFound")
            return "translated"

        pipeline = types.SimpleNamespace(
            niutrans_translate=lambda *args, **kwargs: "niutrans",
            google_translate=flaky_google,
        )
        with MODULE.google_fallback_for_niutrans(pipeline, enabled=True):
            self.assertEqual(pipeline.niutrans_translate("text", "fi", "en", None), "translated")
        self.assertEqual(attempts, 3)
        self.assertEqual(sleep.call_count, 2)

    @patch("time.sleep")
    def test_google_translation_falls_back_to_source_detection(self, _sleep) -> None:
        sources = []

        def strict_source_fails(text, source, target):
            sources.append(source)
            if source != "auto":
                raise RuntimeError("TranslationNotFound")
            return "translated"

        pipeline = types.SimpleNamespace(
            niutrans_translate=lambda *args, **kwargs: "niutrans",
            google_translate=strict_source_fails,
        )
        with MODULE.google_fallback_for_niutrans(pipeline, enabled=True):
            self.assertEqual(pipeline.niutrans_translate("text", "fi", "en", None), "translated")
        self.assertEqual(sources, ["fi", "fi", "fi", "auto"])

    def test_save_model_preserves_other_local_overrides(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "config.toml"
            path.write_text("[presets.typst]\ntemperature = 0.9\n", encoding="utf-8")
            MODULE.save_model("chosen-model", path)
            parsed = MODULE.load_toml(path, required=True)
            self.assertEqual(parsed["llm"]["model"], "chosen-model")
            self.assertEqual(parsed["presets"]["typst"]["temperature"], 0.9)


class RewritingTests(unittest.TestCase):
    def test_plain_paragraphs_preserve_separators(self) -> None:
        result = MODULE.rewrite_plain("one\n\n\ntwo", True, lambda text: text.upper())
        self.assertEqual(result, "ONE\n\n\nTWO")

    def test_typst_chunks_are_atomic(self) -> None:
        calls = []

        def guard(operation, payload):
            calls.append((operation, payload))
            if operation == "prepare":
                return {"plan": {"opaque": True}, "chunks": [{"id": "1", "text": "a"}, {"id": "2", "text": "b"}]}
            return {"source": "done"}

        def rewrite(text):
            if text == "b":
                raise MODULE.HumanizeError("network")
            return text.upper()

        with self.assertRaisesRegex(MODULE.HumanizeError, "Paragraph 2 failed"):
            MODULE.rewrite_typst("source", True, rewrite, guard=guard)
        self.assertEqual([name for name, _ in calls], ["prepare"])

    def test_typst_restore_receives_all_outputs(self) -> None:
        def guard(operation, payload):
            if operation == "prepare":
                return {"plan": {"opaque": True}, "chunks": [{"id": "p1", "text": "hello"}]}
            self.assertEqual(payload["outputs"], [{"id": "p1", "text": "HELLO"}])
            return {"source": "proposal"}

        result = MODULE.rewrite_typst("source", True, str.upper, guard=guard)
        self.assertEqual(result, "proposal")

    def test_headless_guard_adapter_round_trip(self) -> None:
        adapter = ROOT / "dot_local/share/humanize-text/typst_guard_cli.lua"
        guard_path = ROOT / "dot_config/nvim/lua/custom/typst_guard.lua"
        environment = dict(os.environ, HUMANIZE_TYPST_GUARD_PATH=str(guard_path))
        prepared = subprocess.run(
            ["nvim", "--headless", "-u", "NONE", "-l", str(adapter), "prepare"],
            input=json.dumps({"source": "= Heading\nProse @cite with $x$ and 42.", "paragraph_mode": True}),
            text=True,
            capture_output=True,
            check=True,
            env=environment,
        )
        payload = json.loads(prepared.stdout)
        outputs = [
            {"id": chunk["id"], "text": chunk["text"].replace("Prose", "Revised prose")} for chunk in payload["chunks"]
        ]
        restored = subprocess.run(
            ["nvim", "--headless", "-u", "NONE", "-l", str(adapter), "restore"],
            input=json.dumps({"plan": payload["plan"], "outputs": outputs}),
            text=True,
            capture_output=True,
            check=True,
            env=environment,
        )
        result = json.loads(restored.stdout)["source"]
        self.assertIn("Revised prose", result)
        self.assertIn("@cite", result)
        self.assertIn("$x$", result)
        self.assertIn("42", result)


class OutputTests(unittest.TestCase):
    def test_output_refuses_existing_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "result.txt"
            path.write_text("old", encoding="utf-8")
            with self.assertRaisesRegex(MODULE.HumanizeError, "already exists"):
                MODULE.atomic_write(path, "new", refuse_existing=True)
            self.assertEqual(path.read_text(encoding="utf-8"), "old")

    def test_atomic_write_preserves_existing_mode(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "result.txt"
            path.write_text("old", encoding="utf-8")
            path.chmod(0o640)
            MODULE.atomic_write(path, "new", refuse_existing=False)
            self.assertEqual(path.stat().st_mode & 0o777, 0o640)

    def test_write_restores_original_after_compile_failure(self) -> None:
        settings = MODULE.RunSettings(1.0, True, "url", Path("proxy"), "model", "fi", ())
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "chapter.typ"
            path.write_text("original", encoding="utf-8")
            with patch.object(MODULE, "compile_typst_proposal", side_effect=MODULE.HumanizeError("bad")):
                with self.assertRaisesRegex(MODULE.HumanizeError, "bad"):
                    MODULE.write_in_place(path, "proposal", typst=True, settings=settings)
            self.assertEqual(path.read_text(encoding="utf-8"), "original")

    def test_clipboard_is_written_only_after_processing(self) -> None:
        parser = MODULE.make_parser(clipboard=True)
        args = parser.parse_args([])
        settings = MODULE.RunSettings(1.3, False, "url", Path("proxy"), "model", "fi", ())
        with patch.object(MODULE.subprocess, "run") as run:
            MODULE.publish("finished", args=args, clipboard=True, target=None, typst=False, settings=settings)
        run.assert_called_once_with(["pbcopy"], input="finished", text=True, check=True)

    def test_typst_compile_check_uses_temporary_sibling(self) -> None:
        settings = MODULE.RunSettings(1.0, True, "url", Path("proxy"), "model", "fi", ())
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "chapter.typ"
            path.write_text("= Original\n\nText.\n", encoding="utf-8")
            MODULE.compile_typst_proposal(path, "= Revised\n\nText.\n", settings)
            self.assertEqual(path.read_text(encoding="utf-8"), "= Original\n\nText.\n")
            self.assertEqual(list(path.parent.glob(".humanize-*.typ")), [])

    def test_default_typst_sink_creates_described_parent_and_empty_child(self) -> None:
        settings = MODULE.RunSettings(1.0, True, "url", Path("proxy"), "model", "fi", ())
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["jj", "git", "init"], cwd=root, check=True, capture_output=True)
            path = root / "chapter.typ"
            path.write_text("= Original\n", encoding="utf-8")
            subprocess.run(["jj", "commit", "-m", "base"], cwd=root, check=True, capture_output=True)
            with patch.object(MODULE, "compile_typst_proposal"):
                MODULE.write_and_commit(path, "= Revised\n", "docs(manuscript): revise chapter prose", settings)
            description = subprocess.run(
                ["jj", "log", "-r", "@-", "--no-graph", "-T", "description.first_line()"],
                cwd=root,
                check=True,
                capture_output=True,
                text=True,
            ).stdout
            self.assertEqual(description, "docs(manuscript): revise chapter prose")
            status = subprocess.run(
                ["jj", "status", "--no-pager"], cwd=root, check=True, capture_output=True, text=True
            ).stdout
            self.assertIn("The working copy has no changes.", status)


if __name__ == "__main__":
    unittest.main()
