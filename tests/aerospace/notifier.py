"""Check callback writes without starting Aegis or touching its real FIFO."""
import os
from pathlib import Path
import subprocess
import tempfile

notifier = Path(__file__).resolve().parents[2] / "dot_config/aegis/executable_aegis-aerospace-notify"
with tempfile.TemporaryDirectory() as directory:
    env = dict(os.environ, HOME=directory)
    pipe = Path(directory) / ".config/aegis/aerospace.pipe"
    pipe.parent.mkdir(parents=True)

    def send(*args):
        return subprocess.run(["/usr/bin/perl", str(notifier), *args], env=env, timeout=1)

    assert send().returncode == 0
    pipe.write_text("leave regular files alone")
    assert send().returncode == 0
    assert pipe.read_text() == "leave regular files alone"
    pipe.unlink()
    os.mkfifo(pipe)
    assert send().returncode == 0  # No reader must never block a WM callback.
    reader = os.open(pipe, os.O_RDONLY | os.O_NONBLOCK)
    try:
        assert send().returncode == 0
        assert os.read(reader, 4096) == b"workspace_changed\n"
        assert send("mode:service").returncode == 0
        assert os.read(reader, 4096) == b"mode:service\n"
        assert send("mode:service\ninjected").returncode == 2
    finally:
        os.close(reader)
print("Aegis notifier checks passed")
