#!/bin/bash
set -eu
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
export CLANG_MODULE_CACHE_PATH="$PROJECT_ROOT/.build/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_ROOT/.build/clang"
mkdir -p "$CLANG_MODULE_CACHE_PATH" .build/cache .build/config .build/security
exec swift "$@" --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security
