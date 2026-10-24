#!/bin/bash
set -euo pipefail
# Also works outside Xcode: scripts/build-native.sh builds the host library for swift test.
export PATH="$HOME/.cargo/bin:$PATH"
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "${PLATFORM_NAME:-}" ]; then
  cargo build --locked --release --manifest-path "$TASK_ROOT/NativeEngine/Cargo.toml"
  exit 0
fi
TASK_LIBS=()
for TASK_ARCH in ${ARCHS:-arm64}; do
  case "$PLATFORM_NAME:$TASK_ARCH" in
    iphonesimulator:arm64) TASK_TARGET=aarch64-apple-ios-sim ;;
    iphonesimulator:x86_64) TASK_TARGET=x86_64-apple-ios ;;
    iphoneos:arm64) TASK_TARGET=aarch64-apple-ios ;;
    *) echo "Unsupported Rust target: $PLATFORM_NAME $TASK_ARCH" >&2; exit 1 ;;
  esac
  rustup target add "$TASK_TARGET"
  # Cargo's build scripts are host tools. Don't let the Xcode SDK contaminate them.
  env -u SDKROOT -u CFLAGS -u CXXFLAGS -u LDFLAGS cargo build --locked --release \
    --manifest-path "$TASK_ROOT/NativeEngine/Cargo.toml" --target "$TASK_TARGET"
  TASK_LIBS+=("$TASK_ROOT/NativeEngine/target/$TASK_TARGET/release/libscheduling_engine.a")
done
mkdir -p "$TASK_ROOT/build/native/$PLATFORM_NAME"
xcrun lipo -create "${TASK_LIBS[@]}" -output "$TASK_ROOT/build/native/$PLATFORM_NAME/libscheduling_engine.a"
