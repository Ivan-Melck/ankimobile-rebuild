#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_ROOT"
TASK_OUTPUT="$TASK_ROOT/build/ipa"
mkdir -p "$TASK_OUTPUT"
if [ -e "$TASK_OUTPUT/Flashcards.xcarchive" ] || [ -e "$TASK_OUTPUT/DeviceArchive.xcresult" ]; then
  echo 'Archive output already exists. Move build/ipa aside before rebuilding.' >&2
  exit 1
fi
xcodebuild archive -project Flashcards.xcodeproj -scheme Flashcards \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$TASK_OUTPUT/Flashcards.xcarchive" \
  -derivedDataPath "$TASK_OUTPUT/DerivedData" \
  -resultBundlePath "$TASK_OUTPUT/DeviceArchive.xcresult" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  | tee "$TASK_OUTPUT/archive.log"
python3 scripts/package-ipa.py "$TASK_OUTPUT/Flashcards.xcarchive" "$TASK_OUTPUT"
