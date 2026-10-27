#!/bin/bash
# Build the independent desktop reference, then run only isolated test peers.
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_ROOT"
command -v bwrap >/dev/null || { echo 'bubblewrap is required; comparison refuses to run without isolation.' >&2; exit 1; }
scripts/prepare-backend.sh
export PROTOC_BINARY="$(command -v protoc)"
if command -v uv >/dev/null; then export UV_BINARY="$(command -v uv)"; fi
mkdir -p build/comparison
# This creates Vendor/anki/out/pyenv, not a system or user Anki installation.
(cd Vendor/anki && RELEASE=1 just build) > build/comparison/reference-build.log 2>&1
cc -shared -fPIC -o /tmp/anki-comparison-clock.so tools/comparison/clock.c -ldl
cargo build --lib --release --locked --manifest-path NativeEngine/Cargo.toml --features validation-comparison > build/comparison/native-build.log 2>&1
# SwiftPM does not track changes to an externally linked Rust static archive.
touch Sources/CSchedulingEngine/shim.c
swift build --product AnkiComparisonDriver > build/comparison/swift-build.log 2>&1
python3 tools/comparison/run.py "$@"
