#!/usr/bin/env python3
"""Run a built test command with the same audited isolation as both peers."""
import argparse
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
from isolation import environment_and_command

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("command", nargs=argparse.REMAINDER)
args = parser.parse_args()
if not args.command:
    parser.error("supply an absolute executable path and its arguments")
os.umask(0o077)
work = Path(tempfile.mkdtemp(prefix="anki-isolated-tests-"))
probe = socket.socket()
probe.bind(("127.0.0.1", 0)); probe.listen()
env = dict(os.environ, ANKI_COMPARISON_PROBE_PORT=str(probe.getsockname()[1]))
for key in ("LD_PRELOAD", "ANKI_COMPARISON_CLOCK_FILE", "ANKI_COMPARISON_ISOLATED"):
    env.pop(key, None)
env, command = environment_and_command(args.command, env, ROOT, work, Path("/tmp/anki-comparison-clock.so"), "tests")
try:
    result = subprocess.run(command, env=env)
    if (work/"tests-isolation.json").exists():
        print((work/"tests-isolation.json").read_text())
finally:
    probe.close()
    shutil.rmtree(work)
raise SystemExit(result.returncode)
