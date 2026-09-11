from __future__ import annotations

import importlib.util
import io
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
MODULE_PATH = ROOT / "dotfiles/.local/share/humanize-text/main.py"
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
            llm_rewrite=lambda *args, **kwargs: "rewritten",
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
            llm_rewrite=lambda *args, **kwargs: "rewritten",
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
            llm_rewrite=lambda *args, **kwargs: "rewritten",
            niutrans_translate=lambda *args, **kwargs: "niutrans",
            google_translate=strict_source_fails,
        )
        with MODULE.google_fallback_for_niutrans(pipeline, enabled=True):
            self.assertEqual(pipeline.niutrans_translate("text", "fi", "en", None), "translated")
        self.assertEqual(sources, ["fi", "fi", "fi", "auto"])

    @patch("time.sleep")
    def test_google_none_result_retries_then_detects_source(self, _sleep) -> None:
        sources = []

        def google_returns_none(text, source, target):
            sources.append(source)
            return "translated" if source == "auto" else None

        pipeline = types.SimpleNamespace(
            llm_rewrite=lambda *args, **kwargs: "rewritten",
            niutrans_translate=lambda *args, **kwargs: "niutrans",
            google_translate=google_returns_none,
        )
        with MODULE.google_fallback_for_niutrans(pipeline, enabled=True):
            self.assertEqual(pipeline.niutrans_translate("text", "fi", "en", None), "translated")
        self.assertEqual(sources, ["fi", "fi", "fi", "auto"])

    @patch("time.sleep")
    def test_google_error_page_uses_fallback(self, _sleep) -> None:
        page = (
            "Error 500 (Server Error)!!1500.That’s an error.There was an error. "
            "Please try again later.That’s all we know."
        )
        pipeline = types.SimpleNamespace(
            llm_rewrite=lambda *args, **kwargs: "rewritten",
            niutrans_translate=lambda *args, **kwargs: "niutrans",
            google_translate=lambda *args, **kwargs: page,
        )
        with MODULE.google_fallback_for_niutrans(
            pipeline, enabled=True, translation_fallback=lambda text, target: "valid translation"
        ):
            self.assertEqual(pipeline.google_translate("source", "fi", "en"), "valid translation")

    @patch("time.sleep")
    def test_google_empty_result_uses_llm_translation_fallback(self, _sleep) -> None:
        fallback_calls = []
        pipeline = types.SimpleNamespace(
            llm_rewrite=lambda *args, **kwargs: "rewritten",
            niutrans_translate=lambda *args, **kwargs: "niutrans",
            google_translate=lambda text, source, target: None,
        )

        def fallback(text, target):
            fallback_calls.append((text, target))
            return "llm translated"

        with MODULE.google_fallback_for_niutrans(
            pipeline,
            enabled=True,
            translation_fallback=fallback,
        ):
            self.assertEqual(pipeline.niutrans_translate("text", "fi", "en", None), "llm translated")
        self.assertEqual(fallback_calls, [("text", "en")])

    @patch("time.sleep")
    def test_type_error_retries_only_failed_llm_pass(self, sleep) -> None:
        attempts = 0

        def flaky_llm(*args, **kwargs):
            nonlocal attempts
            attempts += 1
            if attempts == 1:
                raise TypeError("bad response shape")
            return "rewritten"

        pipeline = types.SimpleNamespace(
            llm_rewrite=flaky_llm,
            niutrans_translate=lambda *args, **kwargs: "niutrans",
            google_translate=lambda text, source, target: "translated",
        )
        with MODULE.google_fallback_for_niutrans(pipeline, enabled=True):
            self.assertEqual(pipeline.llm_rewrite("text"), "rewritten")
        self.assertEqual(attempts, 2)
        sleep.assert_called_once()

    @patch("time.sleep")
    def test_http_status_error_retries_only_failed_llm_pass(self, sleep) -> None:
        class HTTPStatusError(RuntimeError):
            pass

        attempts = 0

        def flaky_llm(*args, **kwargs):
            nonlocal attempts
            attempts += 1
            if attempts < 3:
                raise HTTPStatusError("temporary upstream failure")
            return "rewritten"

        pipeline = types.SimpleNamespace(
            llm_rewrite=flaky_llm,
            niutrans_translate=lambda *args, **kwargs: "niutrans",
            google_translate=lambda text, source, target: "translated",
        )
        with MODULE.google_fallback_for_niutrans(pipeline, enabled=True):
            self.assertEqual(pipeline.llm_rewrite("text"), "rewritten")
        self.assertEqual(attempts, 3)
        self.assertEqual(sleep.call_count, 2)

    def test_save_model_preserves_other_local_overrides(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "config.toml"
            path.write_text("[presets.typst]\ntemperature = 0.9\n", encoding="utf-8")
            MODULE.save_model("chosen-model", path)
            parsed = MODULE.load_toml(path, required=True)
            self.assertEqual(parsed["llm"]["model"], "chosen-model")
            self.assertEqual(parsed["presets"]["typst"]["temperature"], 0.9)


class RewritingTests(unittest.TestCase):
    def test_progress_is_tty_only_and_never_prints_source(self) -> None:
        visible = io.StringIO()
        progress = MODULE.ParagraphProgress(visible, enabled=True)
        progress.start(3)
        progress.paragraph(2)
        progress.finish()
        rendered = visible.getvalue()
        self.assertIn("2/3", rendered)
        self.assertIn("██", rendered)
        self.assertIn("3 paragraphs rewritten", rendered)
        self.assertNotIn("SECRET SOURCE", rendered)

        hidden = io.StringIO()
        quiet = MODULE.ParagraphProgress(hidden, enabled=False)
        quiet.start(3)
        quiet.paragraph(2)
        quiet.finish()
        self.assertEqual(hidden.getvalue(), "")

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

        stream = io.StringIO()
        progress = MODULE.ParagraphProgress(stream, enabled=True)
        with self.assertRaisesRegex(MODULE.HumanizeError, "Paragraph 2 failed"):
            MODULE.rewrite_typst("source", True, rewrite, guard=guard, progress=progress)
        self.assertEqual([name for name, _ in calls], ["prepare", "restore"])
        self.assertIn("stopped at paragraph 2/2", stream.getvalue())
        self.assertNotIn("source", stream.getvalue())

    def test_typst_restore_receives_all_outputs(self) -> None:
        def guard(operation, payload):
            if operation == "prepare":
                return {"plan": {"opaque": True}, "chunks": [{"id": "p1", "text": "hello"}]}
            self.assertEqual(payload["outputs"], [{"id": "p1", "text": "HELLO"}])
            return {"source": "proposal"}

        result = MODULE.rewrite_typst("source", True, str.upper, guard=guard)
        self.assertEqual(result, "proposal")

    def test_typst_placeholder_damage_rewrites_around_protected_tokens(self) -> None:
        calls = []

        def guard(operation, payload):
            if operation == "prepare":
                return {
                    "plan": {"opaque": True},
                    "chunks": [{"id": "p1", "text": "hello ⟦TYPST_GUARD_0001⟧ world"}],
                }
            self.assertEqual(payload["outputs"][0]["text"], "HELLO ⟦TYPST_GUARD_0001⟧ WORLD")
            return {"source": "proposal"}

        def rewrite(text):
            calls.append(text)
            if "TYPST_GUARD" in text:
                return "broken ⟦TYPST_GUARD_0002⟧"
            return text.upper()

        result = MODULE.rewrite_typst("source", True, rewrite, guard=guard)
        self.assertEqual(result, "proposal")
        self.assertEqual(calls, ["hello ⟦TYPST_GUARD_0001⟧ world", "hello", "world"])

    def test_typst_safe_fragments_preserve_lines_and_escape_markup(self) -> None:
        calls = []

        def rewrite(text):
            calls.append(text)
            return "changed #tag\nextra"

        result = MODULE.rewrite_around_typst_placeholders(
            "  first line\n  second ⟦TYPST_GUARD_0001⟧ tail",
            rewrite,
        )
        self.assertEqual(calls, ["first line", "second", "tail"])
        self.assertEqual(result.count("\n"), 1)
        self.assertIn(r"changed \#tag extra", result)
        self.assertIn("⟦TYPST_GUARD_0001⟧", result)

    def test_typst_syntax_failure_retries_only_that_paragraph(self) -> None:
        attempts = 0
        restore_calls = 0

        def guard(operation, payload):
            nonlocal restore_calls
            if operation == "prepare":
                return {
                    "plan": {"opaque": True},
                    "chunks": [{"id": "p1", "text": "original"}],
                }
            restore_calls += 1
            if payload["outputs"][0]["text"] == "bad #syntax":
                raise MODULE.HumanizeError("Typst syntax contains a parse error")
            return {"source": "proposal"}

        def rewrite(_text):
            nonlocal attempts
            attempts += 1
            return "bad #syntax" if attempts == 1 else "good prose"

        result = MODULE.rewrite_typst("source", True, rewrite, guard=guard)
        self.assertEqual(result, "proposal")
        self.assertEqual(attempts, 2)
        self.assertEqual(restore_calls, 3)

    def test_typst_compile_failure_retries_only_that_paragraph(self) -> None:
        rewrites = 0
        validations = []

        def guard(operation, payload):
            if operation == "prepare":
                return {"plan": {}, "chunks": [{"id": "p1", "text": "original"}]}
            source = payload["outputs"][0]["text"]
            return {"source": source}

        def rewrite(_text):
            nonlocal rewrites
            rewrites += 1
            return "bad syntax" if rewrites == 1 else "safe prose"

        def validate(source):
            validations.append(source)
            if source == "bad syntax":
                raise MODULE.HumanizeError("Typst compile check failed: bad syntax")

        result = MODULE.rewrite_typst("source", True, rewrite, guard=guard, validate=validate)
        self.assertEqual(result, "safe prose")
        self.assertEqual(rewrites, 2)
        self.assertEqual(validations, ["bad syntax", "safe prose", "safe prose"])

    def test_headless_guard_adapter_round_trip(self) -> None:
        adapter = ROOT / "dotfiles/.local/share/humanize-text/typst_guard_cli.lua"
        guard_path = ROOT / "dotfiles/.config/nvim/lua/custom/typst_guard.lua"
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
        with (
            patch.object(MODULE.subprocess, "run") as run,
            patch.object(MODULE.sys, "stdout", new_callable=io.StringIO) as output,
        ):
            MODULE.publish("finished", args=args, clipboard=True, target=None, typst=False, settings=settings)
        run.assert_called_once_with(["pbcopy"], input="finished", text=True, check=True)
        self.assertEqual(output.getvalue(), "finished\n")

    def test_clipboard_rejects_provider_error_without_writing(self) -> None:
        args = MODULE.make_parser(clipboard=True).parse_args([])
        settings = MODULE.RunSettings(1.3, False, "url", Path("proxy"), "model", "fi", ())
        with patch.object(MODULE.subprocess, "run") as run:
            with self.assertRaisesRegex(MODULE.HumanizeError, "error page"):
                MODULE.publish(
                    "Error 500 (Server Error)!!1500.That’s an error.That’s all we know.",
                    args=args,
                    clipboard=True,
                    target=None,
                    typst=False,
                    settings=settings,
                )
        run.assert_not_called()

    def test_typst_compile_check_uses_temporary_sibling(self) -> None:
        settings = MODULE.RunSettings(1.0, True, "url", Path("proxy"), "model", "fi", ())
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "chapter.typ"
            path.write_text("= Original\n\nText.\n", encoding="utf-8")
            MODULE.compile_typst_proposal(path, "= Revised\n\nText.\n", settings)
            self.assertEqual(path.read_text(encoding="utf-8"), "= Original\n\nText.\n")
            self.assertEqual(list(path.parent.glob(".humanize-*.typ")), [])

    def test_typst_compile_error_keeps_useful_context(self) -> None:
        settings = MODULE.RunSettings(1.0, True, "url", Path("proxy"), "model", "fi", ())
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "chapter.typ"
            path.write_text("original", encoding="utf-8")
            diagnostic = "error: bad syntax\n  ┌─ file.typ:2:3\n  │\n2 │ bad\n  │   ^"
            failed = subprocess.CompletedProcess([], 1, "", diagnostic)
            passed = subprocess.CompletedProcess([], 0, "", "")
            with patch.object(MODULE, "command_result", side_effect=[failed, passed]):
                with self.assertRaisesRegex(MODULE.HumanizeError, "error: bad syntax") as raised:
                    MODULE.compile_typst_proposal(path, "bad", settings)
            self.assertIn("file.typ:2:3", str(raised.exception))

    def test_typst_compile_allows_existing_baseline_errors(self) -> None:
        settings = MODULE.RunSettings(1.0, True, "url", Path("proxy"), "model", "fi", ())
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "chapter.typ"
            path.write_text("original", encoding="utf-8")
            existing = subprocess.CompletedProcess([], 1, "", "error: label <missing> does not exist")
            with patch.object(MODULE, "command_result", side_effect=[existing, existing]):
                MODULE.compile_typst_proposal(path, "proposal", settings)

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
