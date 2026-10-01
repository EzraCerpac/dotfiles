"""NAS proxy routing survives native dotfile rendering when opted in."""

import subprocess
import tempfile
import unittest
from pathlib import Path

from lib.prereq import requires
from lib.tera import render_profile_dotfile


@requires("mise", "ssh")
class NasSshProxyTests(unittest.TestCase):
    def test_rendered_aliases_use_only_the_opted_in_proxy(self):
        proxy = "/usr/bin/nc -X 5 -x 127.0.0.1:11080 %h %p"
        for enabled in (False, True):
            with self.subTest(enabled=enabled), tempfile.TemporaryDirectory() as scratch:
                root = Path(scratch)
                rendered = render_profile_dotfile(
                    "workstation", "~/.ssh/config", root,
                    extra_vars={"nas_ssh_proxy_command": proxy} if enabled else {},
                )
                config = root / "ssh_config"
                config.write_text(rendered)
                for host in ("cerpacnas", "nas", "driehuisnas", "gitlab.ewi.tudelft.nl"):
                    result = subprocess.run(
                        ["ssh", "-G", "-F", str(config), host],
                        capture_output=True, text=True, check=True,
                    )
                    lines = result.stdout.splitlines()
                    with self.subTest(host=host):
                        if enabled and host != "gitlab.ewi.tudelft.nl":
                            self.assertIn("proxycommand " + proxy, lines)
                        else:
                            self.assertFalse(any(line.startswith("proxycommand ") for line in lines))
                        self.assertIn("stricthostkeychecking ask", lines)


if __name__ == "__main__":
    unittest.main()
