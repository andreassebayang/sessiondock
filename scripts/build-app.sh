#!/bin/bash
set -eu
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
bash scripts/swift-local.sh build -c release
BIN_DIR="$(bash scripts/swift-local.sh build -c release --show-bin-path)"
BUNDLE="$PROJECT_ROOT/dist/Connection Workbench.app"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN_DIR/ConnectionWorkbench" "$BUNDLE/Contents/MacOS/ConnectionWorkbench"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
plutil -lint "$BUNDLE/Contents/Info.plist"
printf 'Built %s\n' "$BUNDLE"
