"""Linux namespace sandbox for both comparison peers.

The host root is read-only. Home, /tmp and session sockets are hidden; only
the repository, the fork's private Python runtime and this test's directory
are exposed. No host network or process namespace is shared.
"""
from pathlib import Path
import os
import shutil


def environment_and_command(command, environment, root, work, clock_library, name):
    bwrap = shutil.which("bwrap")
    if not bwrap:
        raise RuntimeError("bubblewrap is required: comparison will not run without isolation")
    # The isolated venv's interpreter is an absolute symlink to uv's runtime.
    runtime = (root/"Vendor/anki/out/pyenv/bin/python").resolve().parent.parent
    for directory in ("home", "config", "data", "cache", "tmp", "runtime"):
        (work/directory).mkdir(mode=0o700, exist_ok=True)
    marker=work/"read-only-probe"
    marker.write_text("unchanged")
    allowed = {"PATH", "LD_LIBRARY_PATH", "LANG", "LC_ALL", "TZ", "QT_QPA_PLATFORM",
               "PYTHONPATH", "LD_PRELOAD", "RAYON_NUM_THREADS", "ANKI_COMPARISON_CLOCK_FILE", "ANKI_COMPARISON_PROBE_PORT"}
    env = dict({key:value for key,value in environment.items() if key in allowed},
               HOME=str(work/"home"), XDG_CONFIG_HOME=str(work/"config"),
               XDG_DATA_HOME=str(work/"data"), XDG_CACHE_HOME=str(work/"cache"),
               XDG_RUNTIME_DIR=str(work/"runtime"), TMPDIR=str(work/"tmp"),
               ANKI_BASE=str(work/"data/Anki2"), PYTHONNOUSERSITE="1")
    for key in ("DISPLAY", "WAYLAND_DISPLAY", "DBUS_SESSION_BUS_ADDRESS", "PYTHONHOME"):
        env.pop(key, None)
    sandbox = [bwrap, "--die-with-parent", "--new-session", "--unshare-all",
               "--ro-bind", "/", "/", "--tmpfs", "/home", "--tmpfs", "/tmp",
               "--tmpfs", "/run/user", "--proc", "/proc", "--dev", "/dev",
               "--ro-bind", str(root), str(root),
               "--ro-bind", str(runtime), str(runtime),
               "--bind", str(work), str(work),
               "--ro-bind", str(marker), "/tmp/isolation-read-only-probe",
               "--ro-bind", str(clock_library), str(clock_library)]
    if Path("/usr/bin/anki").exists():
        sandbox += ["--ro-bind", "/dev/null", "/usr/bin/anki"]
    sandbox += ["--remount-ro", "/home", "--remount-ro", "/tmp", "--chdir", str(root), "--",
                str(root/"Vendor/anki/out/pyenv/bin/python"), str(root/"tools/comparison/audit.py"), str(work), name, *command]
    return env, sandbox
