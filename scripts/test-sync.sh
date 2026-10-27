#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$TASK_ROOT/scripts/prepare-backend.sh"
export PROTOC_BINARY="$(command -v protoc)"
cargo build --locked --release --manifest-path "$TASK_ROOT/NativeEngine/Cargo.toml" --features validation-server --bin anki-compat-sync-server --lib
if [ "$(uname -s)" = Linux ]; then
  command -v bwrap >/dev/null || { echo 'bubblewrap is required for local sync tests.' >&2; exit 1; }
  cc -shared -fPIC -o /tmp/anki-comparison-clock.so "$TASK_ROOT/tools/comparison/clock.c" -ldl
  cd "$TASK_ROOT"
  touch Sources/CSchedulingEngine/shim.c
  swift build --build-tests
  TASK_TEST_BIN="$(swift build --show-bin-path)"
  if [ -x "$TASK_TEST_BIN/FlashcardsCoreTests-test-runner" ]; then
    TASK_TEST_EXECUTABLE="$TASK_TEST_BIN/FlashcardsCoreTests-test-runner"
  else
    TASK_TEST_EXECUTABLE="$TASK_TEST_BIN/FlashcardsCorePackageTests.xctest"
  fi
  exec python3 tools/comparison/isolated_command.py "$TASK_ROOT/Vendor/anki/out/pyenv/bin/python" \
    "$TASK_ROOT/tools/comparison/sync.py" --test-executable "$TASK_TEST_EXECUTABLE"
fi
TASK_SYNC_DIR="$(mktemp -d)"
TASK_SYNC_PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
SYNC_USER1=compatibility:fixture-password SYNC_USER2=rwkv-compatibility:fixture-password SYNC_HOST=127.0.0.1 SYNC_PORT="$TASK_SYNC_PORT" SYNC_BASE="$TASK_SYNC_DIR" \
  "$TASK_ROOT/NativeEngine/target/release/anki-compat-sync-server" > "$TASK_SYNC_DIR/server.log" 2>&1 &
TASK_SYNC_PID=$!
trap 'kill "$TASK_SYNC_PID" 2>/dev/null || true; wait "$TASK_SYNC_PID" 2>/dev/null || true; rm -rf "$TASK_SYNC_DIR"' EXIT
export ANKI_SYNC_TEST_ENDPOINT="http://127.0.0.1:$TASK_SYNC_PORT/"
python3 - <<'PY'
import os,socket,time,urllib.parse
port=urllib.parse.urlsplit(os.environ['ANKI_SYNC_TEST_ENDPOINT']).port
for _ in range(100):
 try:
  with socket.create_connection(('127.0.0.1',port),timeout=.2): break
 except OSError: time.sleep(.1)
else: raise SystemExit('The isolated sync server did not start')
PY
cd "$TASK_ROOT"
swift test --filter 'AnkiCompatibilityTests/test(TwoClientsSyncThroughForkServer|RWKVSyncRefreshesCachedCandidates)'
