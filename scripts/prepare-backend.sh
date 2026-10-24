#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ ! -f "$TASK_ROOT/Vendor/anki/rslib/Cargo.toml" ]; then
  git -C "$TASK_ROOT" submodule update --init --depth 1 Vendor/anki
fi
if [ ! -d "$TASK_ROOT/Vendor/anki/ftl/core-repo/core" ] || [ ! -d "$TASK_ROOT/Vendor/anki/ftl/qt-repo/desktop" ]; then
  git -C "$TASK_ROOT/Vendor/anki" submodule update --init --depth 1 ftl/core-repo ftl/qt-repo
fi
if ! command -v protoc >/dev/null; then
  echo 'Install Protocol Buffers (protoc) before building the full Anki backend.' >&2
  exit 1
fi
