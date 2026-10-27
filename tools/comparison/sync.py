#!/usr/bin/env python3
"""Run synthetic server/client sync checks inside an audited private namespace."""
import os
import argparse
from pathlib import Path
import socket
import subprocess
import tempfile
import time

if os.environ.get("ANKI_COMPARISON_ISOLATED")!="1":
    raise SystemExit("Run with tools/comparison/isolated_command.py; namespace isolation is required")
root=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument("--test-executable",type=Path,default=root/".build/debug/FlashcardsCoreTests-test-runner")
args=parser.parse_args()
work=Path(tempfile.mkdtemp(prefix="sync-fixture-",dir=os.environ["TMPDIR"]))
probe=socket.socket();probe.bind(("127.0.0.1",0));port=probe.getsockname()[1];probe.close()
env=dict(os.environ,SYNC_USER1="compatibility:fixture-password",SYNC_USER2="rwkv-compatibility:fixture-password",SYNC_HOST="127.0.0.1",SYNC_PORT=str(port),SYNC_BASE=str(work/"server"),ANKI_SYNC_TEST_ENDPOINT=f"http://127.0.0.1:{port}/")
with (work/"server.log").open("w") as log:
    server=subprocess.Popen([str(root/"NativeEngine/target/release/anki-compat-sync-server")],env=env,stdout=log,stderr=log)
    try:
        for _ in range(100):
            try:
                connection=socket.create_connection(("127.0.0.1",port),timeout=.2);connection.close();break
            except OSError:time.sleep(.1)
        else:raise RuntimeError("Private-namespace sync server did not start: "+(work/"server.log").read_text())
        for case in ("testTwoClientsSyncThroughForkServer","testRWKVSyncRefreshesCachedCandidates"):
            subprocess.run([str(args.test_executable),f"FlashcardsCoreTests.AnkiCompatibilityTests/{case}"],env=env,check=True)
    finally:
        server.terminate()
        try:server.wait(timeout=10)
        except subprocess.TimeoutExpired:server.kill();server.wait()
