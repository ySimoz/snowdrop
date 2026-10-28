#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$DIR/.." && pwd)"

echo "==> Building core Go C-archive (libsnowdrop.a)..."
mkdir -p "$DIR/Frameworks"
cd "$ROOT_DIR"
go build -buildmode=c-archive -o "$DIR/Frameworks/libsnowdrop.a" core/bridge_darwin.go

echo "==> Building Swift macOS Menu Bar App..."
cd "$DIR"
swift build -c release

echo "==> Assembling Snowdrop.app bundle..."
APP_DIR="$DIR/dist/Snowdrop.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$DIR/.build/release/Snowdrop" "$APP_DIR/Contents/MacOS/Snowdrop"
cp "$DIR/Info.plist" "$APP_DIR/Contents/Info.plist"

echo "==> Snowdrop.app built successfully at: $APP_DIR"
