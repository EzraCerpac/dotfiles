"""Check byte-preserving conversion and the external merge/editor boundary."""

import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HELPER = Path(__file__).resolve().parents[1] / "dotfiles/.local/bin/jj-merge"
LOADER = importlib.machinery.SourceFileLoader("jj_merge", str(HELPER))
SPEC = importlib.util.spec_from_loader(LOADER.name, LOADER)
merge = importlib.util.module_from_spec(SPEC)
LOADER.exec_module(merge)


def diff3(left=b"left\n", base=b"base\n", right=b"right\n", length=7, ending=b"\n"):
    return (b"<" * length + b" left" + ending + left + b"|" * length + b" base" + ending +
            base + b"=" * length + ending + right + b">" * length + b" right" + ending)


class ConversionTests(unittest.TestCase):
    def test_multiple_conflicts_preserve_partial_resolutions(self):
        content = b"already merged\n" + diff3() + b"unchanged\n" + diff3(b"new\n", b"old\n", b"other\n") + b"last line"
        result = merge.convert_diff3(content, 7)
        self.assertTrue(result.startswith(b"already merged\n<<<<<<< conflict 1 of 2\n"))
        self.assertIn(b"-base\n+left\n+++++++ Contents of side #2\nright\n", result)
        self.assertIn(b"unchanged\n<<<<<<< conflict 2 of 2\n", result)
        self.assertTrue(result.endswith(b">>>>>>> conflict 2 of 2 ends\nlast line"))

    def test_diff_keeps_context_and_handles_insertions_and_deletions(self):
        result = merge.convert_diff3(diff3(b"same\nadded\nend\n", b"same\nremoved\nend\n"), 7)
        self.assertIn(b" same\n-removed\n+added\n end\n", result)
        self.assertIn(b"+only\n", merge.convert_diff3(diff3(b"only\n", b""), 7))
        self.assertIn(b"-only\n", merge.convert_diff3(diff3(b"", b"only\n"), 7))

    def test_crlf_long_markers_and_non_utf8_bytes(self):
        content = diff3(b"\xffleft\r\n", b"\xfebase\r\n", b"right\r\n", 11, b"\r\n")
        result = merge.convert_diff3(content, 11)
        self.assertIn(b"-\xfebase\r\n+\xffleft\r\n", result)
        self.assertTrue(result.startswith(b"<<<<<<<<<<< conflict 1 of 1\r\n"))
        self.assertNotIn(b"\n", result.replace(b"\r\n", b""))

    def test_unsafe_markers_and_data_rejected(self):
        unsafe = [
            b"no conflict\n", diff3().replace(b"||||||| base\n", b""),
            diff3().replace(b">>>>>>> right\n", b""), diff3(b"<<<<<<< nested\n"),
            diff3(b"+++++++ source code\n"), diff3(b"\\\\\\\\\\\\\\ source code\n"),
            b"=======\n" + diff3(), diff3(b"binary\0\n"),
            diff3(b"bare\rcarriage\n"), diff3().replace(b"||||||| base\n", b"||||||| base\r\n"),
            diff3().replace(b">>>>>>> right\n", b">>>>>>> right"),
        ]
        for data in unsafe:
            with self.subTest(data=data), self.assertRaises(merge.UnsafeConversion):
                merge.convert_diff3(data, 7)


class HelperTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.paths = [self.root / name for name in ("base", "left", "right", "output")]
        for path, data in zip(self.paths, (b"base\n", b"left\n", b"right\n", b"original JJ conflict\n")):
            path.write_bytes(data)
        self.candidate = self.root / "candidate"
        self.candidate.write_bytes(diff3())
        self.log = self.root / "log"
        self.env = dict(os.environ, PATH=str(self.bin), CANDIDATE=str(self.candidate),
                        TOOL_LOG=str(self.log), MERGER_STATUS="1", EDITOR_STATUS="0")
        self.fake("mergiraf", """
from pathlib import Path
if os.environ.get('OMIT_OUTPUT') != '1':
    Path(sys.argv[sys.argv.index('-o') + 1]).write_bytes(Path(os.environ['CANDIDATE']).read_bytes())
sys.exit(int(os.environ['MERGER_STATUS']))
""")
        self.fake("nvim", """
from pathlib import Path
if 'EDITOR_CONTENT' in os.environ:
    Path(sys.argv[5]).write_bytes(os.environ['EDITOR_CONTENT'].encode())
sys.exit(int(os.environ['EDITOR_STATUS']))
""")

    def fake(self, name, body):
        path = self.bin / name
        path.write_text(f"#!{sys.executable}\nimport json, os, sys\nwith open(os.environ['TOOL_LOG'], 'a') as f:\n    f.write(json.dumps([os.path.basename(sys.argv[0]), *sys.argv[1:]]) + '\\n')\n" + body)
        path.chmod(0o755)

    def run_helper(self, length=7):
        return subprocess.run([sys.executable, str(HELPER), *(str(path) for path in self.paths), str(length),
                               "directory/file with spaces.rs"], env=self.env, capture_output=True, text=True)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_clean_merge_skips_editor_and_preserves_bytes(self):
        self.env["MERGER_STATUS"] = "0"
        self.candidate.write_bytes(b"merged\r\nno trailing newline")
        (self.bin / "nvim").unlink()
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.paths[3].read_bytes(), self.candidate.read_bytes())
        self.assertEqual(len(self.calls()), 1)
        arguments = self.calls()[0]
        self.assertEqual(arguments[1:5], ["merge", *(str(path) for path in self.paths[:3])])
        self.assertEqual(arguments[-5:], ["-l", "7", "-p", "directory/file with spaces.rs", "--fast"])
        self.assertNotEqual(arguments[arguments.index("-o") + 1], str(self.paths[3]))

    def test_remaining_conflicts_open_editor_with_original_history(self):
        self.candidate.write_bytes(b"partially merged\n" + diff3(length=10))
        result = self.run_helper(10)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.paths[3].read_bytes().startswith(b"partially merged\n<<<<<<<<<< conflict"))
        self.assertEqual(self.calls()[1], ["nvim", "-c", "let g:jj_diffconflicts_marker_length=10", "-c",
                                         "JJDiffConflicts!", str(self.paths[3]), *(str(path) for path in self.paths[:3])])

    def test_editor_abort_restores_original_and_propagates_status(self):
        self.env.update(EDITOR_STATUS="23", EDITOR_CONTENT="aborted edits")
        result = self.run_helper()
        self.assertEqual(result.returncode, 23)
        self.assertEqual(self.paths[3].read_bytes(), b"original JJ conflict\n")

    def test_editor_resolution_is_retained(self):
        self.env["EDITOR_CONTENT"] = "resolved\n"
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.paths[3].read_bytes(), b"resolved\n")

    def test_unsafe_conversion_opens_original_and_explains(self):
        for data in (b"malformed conflict\n", diff3(b"<<<<<<< nested\n")):
            with self.subTest(data=data):
                self.candidate.write_bytes(data)
                result = self.run_helper()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("opening the original JJ conflict", result.stderr)
                self.assertEqual(self.paths[3].read_bytes(), b"original JJ conflict\n")

    def test_missing_final_newline_falls_back_safely(self):
        self.paths[1].write_bytes(b"left without newline")
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("no final newline", result.stderr)
        self.assertEqual(self.paths[3].read_bytes(), b"original JJ conflict\n")

    def test_missing_dependencies_preserve_output(self):
        for tool in ("mergiraf", "nvim"):
            with self.subTest(tool=tool):
                path = self.bin / tool
                moved = path.with_suffix(".disabled")
                path.rename(moved)
                result = self.run_helper()
                moved.rename(path)
                self.assertEqual(result.returncode, 1)
                self.assertIn("unavailable", result.stderr)
                self.assertEqual(self.paths[3].read_bytes(), b"original JJ conflict\n")

    def test_merger_errors_and_missing_output_do_not_open_editor(self):
        for changes in ({"MERGER_STATUS": "2"}, {"MERGER_STATUS": "0", "OMIT_OUTPUT": "1"}):
            with self.subTest(changes=changes):
                self.env.update(changes)
                result = self.run_helper()
                self.assertEqual(result.returncode, 1)
                self.assertEqual(self.paths[3].read_bytes(), b"original JJ conflict\n")
                self.assertTrue(all(call[0] == "mergiraf" for call in self.calls()))


if __name__ == "__main__":
    unittest.main()
