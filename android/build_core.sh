#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$DIR/.." && pwd)"

export PATH="/opt/homebrew/opt/openjdk@17/bin:/opt/homebrew/share/android-commandlinetools/cmdline-tools/latest/bin:$HOME/go/bin:$PATH"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$ANDROID_HOME/ndk/26.1.10909125}"

mkdir -p "$DIR/app/libs"
cd "$ROOT_DIR"
gomobile bind -target=android/arm64,android/amd64 -androidapi 26 -o "$DIR/app/libs/core.aar" ./core
echo "==> Successfully generated: $DIR/app/libs/core.aar"
