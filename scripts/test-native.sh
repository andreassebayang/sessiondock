#!/bin/bash
set -eu
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
if [ -n "${SESSIONDOCK_LIBSSH2_PREFIX:-}" ]; then
    NATIVE_PREFIX="$SESSIONDOCK_LIBSSH2_PREFIX"
elif [ -d /opt/homebrew/opt/libssh2 ]; then
    NATIVE_PREFIX=/opt/homebrew/opt/libssh2
else
    NATIVE_PREFIX=/usr/local/opt/libssh2
fi
mkdir -p .build
clang -Wall -Wextra -Werror -I Sources/CSFTP/include -I "$NATIVE_PREFIX/include" Tests/NativeFixtures/sftp-lifecycle.c Sources/CSFTP/CSFTP.c -L "$NATIVE_PREFIX/lib" -lssh2 -o .build/sftp-lifecycle
.build/sftp-lifecycle
printf 'Native SFTP lifecycle checks passed.\n'
