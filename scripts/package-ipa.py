#!/usr/bin/env python3
"""Validate an unsigned device archive and package it for external signing."""
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile


def command(*args):
    return subprocess.check_output(args, text=True).strip()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    archive, output = map(lambda p: Path(p).resolve(), sys.argv[1:])
    root = Path(__file__).resolve().parent.parent
    apps = list((archive / "Products/Applications").glob("*.app"))
    assert len(apps) == 1, "Archive must contain one application"
    app = apps[0]
    info = plistlib.loads((app / "Info.plist").read_bytes())
    assert info["CFBundleIdentifier"] == "com.ivanmelck.flashcardsrebuild"
    assert info["CFBundleSupportedPlatforms"] == ["iPhoneOS"], "Not a device archive"
    assert set(info["UIDeviceFamily"]) == {1, 2}, "Expected iPhone and iPad support"
    executable = app / info["CFBundleExecutable"]
    assert command("xcrun", "lipo", "-archs", str(executable)) == "arm64"
    binary = executable.read_bytes()
    magic, cpu, _, _, ncmds = struct.unpack_from("<IIIII", binary)
    assert magic == 0xFEEDFACF and cpu == 0x0100000C, "Expected arm64 Mach-O"
    offset, platforms, signed = 32, [], False
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", binary, offset)
        assert size >= 8 and offset + size <= len(binary), "Invalid Mach-O load command"
        if cmd == 0x32:  # LC_BUILD_VERSION
            platforms.append(struct.unpack_from("<I", binary, offset + 8)[0])
        if cmd == 0x1D:  # LC_CODE_SIGNATURE
            signed = True
        offset += size
    assert platforms == [2], "Executable must target iOS, not the simulator"
    assert not signed, "Expected unsigned archive for external signing"
    assert not (app / "embedded.mobileprovision").exists()
    assert not list(app.rglob("_CodeSignature"))
    models = {}
    for model in sorted((root / "Sources/FlashcardsCore/Resources/RWKV").glob("*.bin")):
        bundled = list(app.rglob(model.name))
        assert len(bundled) == 1 and digest(bundled[0]) == digest(model), f"Missing/changed model: {model.name}"
        models[model.name] = digest(model)
    assert len(models) == 5
    for resource in ("anki-mathjax-svg.js", "anki-image-occlusion.js", "reviewer.css"):
        assert digest(app / resource) == digest(root / "ios/Flashcards/Resources" / resource)
    source = command("git", "-C", str(root), "rev-parse", "HEAD")
    # XcodeGen regenerates the checked-in project on the hosted Mac.
    assert not command("git", "-C", str(root), "status", "--porcelain", "--untracked-files=no",
                       "--", ".", ":(exclude)Flashcards.xcodeproj"), "Build source is modified"
    backend = command("git", "-C", str(root / "Vendor/anki"), "rev-parse", "HEAD")
    output.mkdir(parents=True, exist_ok=True)
    ipa = output / f"Flashcards-{source[:7]}-unsigned.ipa"
    assert not ipa.exists(), "IPA already exists"
    with tempfile.TemporaryDirectory(dir=output) as stage:
        payload = Path(stage) / "Payload"
        payload.mkdir()
        shutil.copytree(app, payload / app.name, symlinks=True)
        subprocess.run(["/usr/bin/zip", "-qry", str(ipa), "Payload"], cwd=stage, check=True)
    with zipfile.ZipFile(ipa) as package:
        assert package.testzip() is None
        assert f"Payload/{app.name}/{info['CFBundleExecutable']}" in package.namelist()
        assert all(name.startswith("Payload/") for name in package.namelist())
    metadata = {
        "sourceCommit": source,
        "ankiCommit": backend,
        "bundleIdentifier": info["CFBundleIdentifier"],
        "version": info["CFBundleShortVersionString"],
        "build": info["CFBundleVersion"],
        "minimumOSVersion": info["MinimumOSVersion"],
        "architecture": "arm64",
        "platform": "iPhoneOS",
        "signing": "unsigned; requires signing and provisioning before installation",
        "xcode": command("xcodebuild", "-version"),
        "rustc": command("rustc", "--version"),
        "generatedProjectSHA256": digest(root / "Flashcards.xcodeproj/project.pbxproj"),
        "modelSHA256": models,
        "ipa": ipa.name,
        "ipaSHA256": digest(ipa),
        "ipaBytes": ipa.stat().st_size,
    }
    (output / "BuildInfo.json").write_text(json.dumps(metadata, indent=2) + "\n")
    (output / "SHA256SUMS").write_text(f"{digest(ipa)}  {ipa.name}\n")
    print(json.dumps(metadata, indent=2))


if __name__ == "__main__":
    main()
