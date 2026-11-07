#!/bin/bash
set -eu
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SWIFT_BIN="$(dirname "$(xcrun --find swiftc)")"
TEST_PLUGIN="$SWIFT_BIN/../lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [ -f "$TEST_PLUGIN" ]; then
    exec bash "$PROJECT_ROOT/scripts/swift-local.sh" test --disable-xctest -Xswiftc -load-plugin-library -Xswiftc "$TEST_PLUGIN" "$@"
fi
exec bash "$PROJECT_ROOT/scripts/swift-local.sh" test --disable-xctest "$@"
