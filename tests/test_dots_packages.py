"""Fixture tests for the native-package half of the ``dots`` wrapper."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import tomllib
import unittest


HELPER = Path(__file__).resolve().parents[1] / "setup-scripts/lib/dots-package-add.sh"


FAKE_MISE = r'''#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
import tomllib


def log_call(args, content=None):
    log = os.environ.get("DOTS_PACKAGE_LOG")
    if log:
        with open(log, "a") as stream:
            stream.write(json.dumps({
                "args": args,
                "config_dir": os.environ.get("MISE_CONFIG_DIR"),
                "trusted": os.environ.get("MISE_TRUSTED_CONFIG_PATHS"),
                "cwd": str(effective_cwd),
                "content": content,
            }) + "\n")


def toml_value(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(value, list):
        return "[" + ", ".join(toml_value(item) for item in value) + "]"
    raise ValueError(value)


args = sys.argv[1:]
effective_cwd = Path(args[args.index("-C") + 1]) if "-C" in args else Path.cwd()

if "cache" in args and "path" in args:
    print(os.environ.get("DOTS_CACHE_DIR", "/real/mise-cache"))
    log_call(args)
    raise SystemExit(0)

if "config" in args and "get" in args:
    config = Path(args[args.index("--file") + 1])
    key_path = args[-1].split(".")
    if key_path == ["bootstrap", "brew", "taps"] and os.environ.get("FAIL_TAP_READ"):
        print("tap config unreadable", file=sys.stderr)
        raise SystemExit(37)
    value = tomllib.loads(config.read_text())
    try:
        for part in key_path:
            value = value[part]
    except KeyError:
        print("mise ERROR Key not found: " + args[-1], file=sys.stderr)
        raise SystemExit(1)
    log_call(args)
    if isinstance(value, dict):
        for key, item in value.items():
            rendered_key = '"' + key + '"' if key_path == ["bootstrap", "brew", "taps"] else key
            print(rendered_key + " = " + toml_value(item))
    else:
        print(value)
    raise SystemExit(0)

if "config" in args and "set" in args:
    config = Path(args[args.index("--file") + 1])
    key = args[-2]
    value = args[-1]
    prefix, package, option = key.rsplit(".", 2)
    assert prefix == "bootstrap.packages"
    with config.open("a") as stream:
        stream.write('\n[bootstrap.packages."' + package + '"]\n')
        stream.write(option + ' = "' + value + '"\n')
    log_call(args)
    raise SystemExit(0)

if "bootstrap" in args and "packages" in args and "use" in args:
    config = Path(args[args.index("--path") + 1])
    package = args[-1]
    manager, name = package.split(":", 1)
    if manager in {"apt", "dnf", "pacman", "apk"} and "@" in name:
        name, version = name.split("@", 1)
    else:
        version = "latest"
    lines = config.read_text().splitlines(keepends=True)
    insertion = len(lines)
    in_packages = False
    for index, line in enumerate(lines):
        if line.strip() == "[bootstrap.packages]":
            in_packages = True
            continue
        if in_packages and line.startswith("["):
            insertion = index
            break
    lines.insert(insertion, '"' + manager + ":" + name + '" = "' + version + '"\n')
    config.write_text("".join(lines))
    log_call(args)
    raise SystemExit(0)

if "bootstrap" in args and "packages" in args and "apply" in args:
    content = (effective_cwd / "mise.toml").read_text()
    log_call(args, content)
    raise SystemExit(int(os.environ.get("DOTS_PACKAGE_APPLY_STATUS", "0")))

log_call(args)
raise SystemExit(0)
'''


class DotsPackageTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="dots-package-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / "setup"
        self.root.mkdir()
        (self.root / "config.toml").write_text(
            "[bootstrap.brew.taps]\n"
            '"shared/tap" = "https://base.invalid/tap"\n'
            '"base/only" = "https://base.invalid/only"\n'
        )
        self.target = self.root / "config.workstation.toml"
        self.target.write_text(
            "[bootstrap.packages]\n"
            '"brew:existing" = { os = "macos/arm64", adopt = true }\n'
            '"brew:other" = { os = "macos/arm64" }\n'
            '"apt:existing" = "1.0"\n'
            "\n[bootstrap.brew.taps]\n"
            '"shared/tap" = "https://target.invalid/tap"\n'
            '"target/only" = "https://target.invalid/only"\n'
        )
        self.mise = self.root / "fake-mise"
        self.mise.write_text(FAKE_MISE)
        self.mise.chmod(0o755)
        self.log = self.root / "calls.jsonl"
        self.env = dict(
            os.environ,
            DOTS_PACKAGE_LOG=str(self.log),
            DOTS_CACHE_DIR=str(self.root / "cache"),
            MISE_CONFIG_DIR=str(self.root / "caller-project"),
        )
        self.env.pop("MISE_TRUSTED_CONFIG_PATHS", None)

    def run_helper(self, *packages, **env):
        return subprocess.run(
            ["bash", str(HELPER), str(self.mise), str(self.root), str(self.target), *packages],
            cwd=self.root,
            env=dict(self.env, **env),
            text=True,
            capture_output=True,
            timeout=30,
        )

    def calls(self):
        if not self.log.exists():
            return []
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def apply_calls(self):
        return [call for call in self.calls() if "apply" in call["args"]]

    def test_failed_tap_read_stops_before_install_or_write(self):
        before = self.target.read_bytes()
        result = self.run_helper("brew:libmagic", FAIL_TAP_READ="1")
        self.assertEqual(result.returncode, 37, result.stderr)
        self.assertIn("tap config unreadable", result.stderr)
        self.assertFalse(self.apply_calls())
        self.assertEqual(self.target.read_bytes(), before)

    def test_new_mac_entries_are_guarded_before_install(self):
        result = self.run_helper("brew:libmagic", "brew-cask:firefox")
        self.assertEqual(result.returncode, 0, result.stderr)

        packages = tomllib.loads(self.target.read_text())["bootstrap"]["packages"]
        self.assertEqual(packages["brew:libmagic"], {"os": "macos/arm64"})
        self.assertEqual(packages["brew-cask:firefox"], {"os": "macos/arm64"})
        self.assertEqual(len(self.apply_calls()), 2)
        self.assertTrue(all("brew:other" not in call["content"] for call in self.apply_calls()))
        for call in self.apply_calls():
            self.assertIn('"base/only" = "https://base.invalid/only"', call["content"])
            self.assertIn('"target/only" = "https://target.invalid/only"', call["content"])
            self.assertIn('"shared/tap" = "https://target.invalid/tap"', call["content"])
            self.assertNotIn('"shared/tap" = "https://base.invalid/tap"', call["content"])
        for call in self.apply_calls():
            self.assertEqual(Path(call["config_dir"]).resolve(), Path(call["cwd"]).resolve())
            self.assertEqual(Path(call["trusted"]).resolve(), Path(call["cwd"]).resolve())
            self.assertEqual(Path(call["args"][1]).resolve(), Path(call["cwd"]).resolve())

    def test_existing_declaration_is_installed_without_rewriting_options(self):
        before = self.target.read_bytes()
        result = self.run_helper("brew:existing")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.target.read_bytes(), before)
        content = self.apply_calls()[0]["content"]
        self.assertIn('[bootstrap.packages."brew:existing"]', content)
        self.assertIn('adopt = true', content)
        self.assertNotIn("brew:other", content)
        self.assertFalse(any("set" in call["args"] or "use" in call["args"] for call in self.calls()))

    def test_non_homebrew_pin_keeps_mise_version_value(self):
        result = self.run_helper("apt:curl@8.5.0-2")
        self.assertEqual(result.returncode, 0, result.stderr)
        packages = tomllib.loads(self.target.read_text())["bootstrap"]["packages"]
        self.assertEqual(packages["apt:curl"], "8.5.0-2")
        self.assertIn('"apt:curl" = "8.5.0-2"', self.apply_calls()[0]["content"])

    def test_failed_install_leaves_new_mac_guard_in_place(self):
        result = self.run_helper("brew-cask:broken", DOTS_PACKAGE_APPLY_STATUS="17")
        self.assertEqual(result.returncode, 17)
        self.assertIn(
            {"os": "macos/arm64"},
            tomllib.loads(self.target.read_text())["bootstrap"]["packages"].values(),
        )
        self.assertTrue(any("set" in call["args"] for call in self.calls()))

    def test_dotted_key_is_rejected_before_native_write(self):
        before = self.target.read_bytes()
        result = self.run_helper("brew:tool.with.dots")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.target.read_bytes(), before)
        self.assertEqual(self.calls(), [])

    def test_real_mise_config_set_and_get_with_installer_stub(self):
        real_mise = os.environ.get("SETUP_TEST_MISE", "mise")
        wrapper = self.root / "mise-with-stubbed-installer"
        wrapper.write_text(
            "#!/usr/bin/env bash\n"
            "if [[ \"${3:-}\" == bootstrap && \"${4:-}\" == packages && \"${5:-}\" == apply ]]; then\n"
            "    exit 0\n"
            "fi\n"
            f"exec {real_mise!r} \"$@\"\n"
        )
        wrapper.chmod(0o755)
        env = dict(
            self.env,
            MISE_TRUSTED_CONFIG_PATHS=str(self.root),
            MISE_CACHE_DIR=str(self.root / "cache"),
            MISE_DATA_DIR=str(self.root / "data"),
            MISE_STATE_DIR=str(self.root / "state"),
        )
        result = subprocess.run(
            ["bash", str(HELPER), str(wrapper), str(self.root), str(self.target), "brew:real-probe"],
            cwd=self.root,
            env=env,
            text=True,
            capture_output=True,
            timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        packages = tomllib.loads(self.target.read_text())["bootstrap"]["packages"]
        self.assertEqual(packages["brew:real-probe"], {"os": "macos/arm64"})


if __name__ == "__main__":
    unittest.main()
