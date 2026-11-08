#!/bin/bash
set -eu
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
bash scripts/swift-local.sh build -c release
BIN_DIR="$(bash scripts/swift-local.sh build -c release --show-bin-path)"
BUNDLE="$PROJECT_ROOT/dist/Connection Workbench.app"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN_DIR/ConnectionWorkbench" "$BUNDLE/Contents/MacOS/ConnectionWorkbench"
for NOTICE_FILE in "$BUNDLE/Contents/Resources/"*-LICENSE.txt; do
    if [ -f "$NOTICE_FILE" ]; then chmod u+w "$NOTICE_FILE"; fi
done
cp Resources/*-LICENSE.txt "$BUNDLE/Contents/Resources/"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
python3 scripts/bundle-libraries.py "$BUNDLE" "$BIN_DIR"
plutil -lint "$BUNDLE/Contents/Info.plist"
printf 'Built %s\n' "$BUNDLE"
