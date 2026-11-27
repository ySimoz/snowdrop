#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NEXT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT_DIR="$(cd "$NEXT_DIR/.." && pwd)"

export JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@17}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
if [ -d "$ANDROID_HOME/ndk/27.3.13750724" ]; then
    export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$ANDROID_HOME/ndk/27.3.13750724}"
else
    export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$ANDROID_HOME/ndk/26.1.10909125}"
fi
GO_BIN_DIR="$(go env GOPATH)/bin"
export PATH="$JAVA_HOME/bin:/opt/homebrew/share/android-commandlinetools/cmdline-tools/latest/bin:$GO_BIN_DIR:$PATH"

export CGO_LDFLAGS="-Wl,-z,max-page-size=16384 -Wl,-z,common-page-size=16384"

if ! command -v gomobile >/dev/null 2>&1 || gomobile version 2>&1 | grep -q "out of date"; then
    echo "==> Installing gomobile/gobind for active Go toolchain..."
    (cd "$ROOT_DIR/core" && go install golang.org/x/mobile/cmd/gobind && go install golang.org/x/mobile/cmd/gomobile)
fi

mkdir -p "$NEXT_DIR/app/libs"
cd "$ROOT_DIR/core"
gomobile bind -target=android/arm64,android/amd64 -androidapi 26 -ldflags="-checklinkname=0 -extldflags=-Wl,-z,max-page-size=16384" -o "$NEXT_DIR/app/libs/core.aar" .
echo "==> Generated: $NEXT_DIR/app/libs/core.aar"
