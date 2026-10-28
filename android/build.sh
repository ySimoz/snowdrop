#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export PATH="/opt/homebrew/opt/openjdk@17/bin:/opt/homebrew/share/android-commandlinetools/cmdline-tools/latest/bin:$HOME/go/bin:$PATH"
export JAVA_HOME="/opt/homebrew/opt/openjdk@17"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$ANDROID_HOME/ndk/26.1.10909125}"

echo "==> Building Go core.aar..."
"$DIR/build_core.sh"

echo "==> Building Android APK..."
cd "$DIR"
./gradlew assembleDebug

echo "==> APK generated successfully at: $DIR/app/build/outputs/apk/debug/app-debug.apk"
