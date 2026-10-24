#!/usr/bin/env python3
"""Copy a local Anki profile without opening or writing its SQLite source.

Reads database/WAL bytes twice to detect concurrent edits; SQLite recovery and
backup run only on the private copy. No preferences, credentials or sync DBs
are copied. Keep the destination outside a public checkout.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import sqlite3
import tempfile


def digest(path):
    if not path.exists():
        return None
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def snapshot(source, destination):
    source = source.resolve(strict=True)
    destination = destination.resolve()
    if destination.exists() or source == destination or source in destination.parents:
        raise ValueError("Use a new destination outside the source profile.")
    database = source / "collection.anki2"
    if not database.is_file():
        raise ValueError("No collection.anki2 in the source profile.")
    destination.mkdir(mode=0o700, parents=True)
    files = [database, source / "collection.anki2-wal"]
    before = {p.name: digest(p) for p in files}
    try:
        with tempfile.TemporaryDirectory(prefix="capture-", dir=destination) as temporary:
            staged = Path(temporary)
            for p in files:
                if before[p.name] is not None:
                    shutil.copyfile(p, staged / p.name)
                    if digest(staged / p.name) != before[p.name]:
                        raise RuntimeError("Collection changed while copying. Close Anki and retry.")
            after = {p.name: digest(p) for p in files}
            if before != after:
                raise RuntimeError("Collection changed while copying. Close Anki and retry.")
            # Only the copied DB is opened. SQLite incorporates its copied WAL.
            with sqlite3.connect(staged / database.name) as copied:
                with sqlite3.connect(destination / database.name) as target:
                    copied.backup(target)
                    # Anki's custom collations/functions are registered by its
                    # backend, so integrity checks belong to the consumer.
                    target.execute("SELECT count(*) FROM sqlite_master").fetchone()
        media = source / "collection.media"
        if media.exists():
            # Symlinks are rejected rather than traversing out of the profile.
            if media.is_symlink() or any(p.is_symlink() for p in media.rglob("*")):
                raise ValueError("Media contains symlinks; copy regular media files separately.")
            shutil.copytree(media, destination / media.name)
        final = {p.name: digest(p) for p in files}
        if before != final:
            raise RuntimeError("Source changed during capture. Close Anki and retry.")
        manifest = {"sourceDatabaseHashes": before, "sourceUnchanged": True,
                    "snapshotDatabaseHash": digest(destination / database.name)}
        (destination / "snapshot-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    except BaseException:
        shutil.rmtree(destination)
        raise
    print(str(destination))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    os.umask(0o077)
    snapshot(args.source, args.destination)
