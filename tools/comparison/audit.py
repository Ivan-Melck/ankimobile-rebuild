"""Executed inside each sandbox before the actual comparison peer starts."""
import errno
import json
import os
from pathlib import Path
import socket
import sys

work = Path(sys.argv[1])
name = sys.argv[2]
assert not Path("/home/user/.local/share/Anki2").exists(), "Live Anki data is visible"
assert os.environ["HOME"] == str(work/"home"), (os.environ["HOME"], str(work/"home"))
assert Path("/tmp/isolation-read-only-probe").read_text() == "unchanged"
try:
    Path("/tmp/isolation-read-only-probe").write_text("should never be written")
except OSError as error:
    assert error.errno in (errno.EROFS, errno.EACCES)
else:
    raise RuntimeError("Read-only filesystem isolation failed")
try:
    connection = socket.create_connection(("127.0.0.1", int(os.environ["ANKI_COMPARISON_PROBE_PORT"])), timeout=.25)
except OSError:
    pass
else:
    connection.close()
    raise RuntimeError("Host network is reachable")
if Path("/usr/bin/anki").exists():
    try: launcher = Path("/usr/bin/anki").read_bytes()
    except PermissionError: launcher = b""
    assert launcher == b"", "Installed launcher is visible"
(work/f"{name}-isolation.json").write_text(json.dumps({
    "liveAnkiDataHidden": True, "installedLauncherHidden": True,
    "hostFilesystemReadOnly": True, "hostNetworkUnreachable": True,
    "home": os.environ["HOME"], "python": sys.executable,
}, indent=2)+"\n")
os.environ["ANKI_COMPARISON_ISOLATED"] = "1"
os.execv(sys.argv[3],sys.argv[3:])
