#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$DIR/.." && pwd)"

echo "==> Building core Go C-archive..."
mkdir -p "$DIR/Frameworks"
cd "$ROOT_DIR"
go build -buildmode=c-archive -o "$DIR/Frameworks/libmeshdrop.a" core/bridge_darwin.go

echo "==> Building Swift macOS Menu Bar App..."
cd "$DIR"
swift build -c release

echo "==> Assembling MeshDrop.app bundle..."
APP_DIR="$DIR/dist/MeshDrop.app"
mkdir -p "$APP_DIR/Contents/MacOS"
cp "$DIR/.build/release/MeshDrop" "$APP_DIR/Contents/MacOS/MeshDrop"
cp "$DIR/Info.plist" "$APP_DIR/Contents/Info.plist"

echo "==> MeshDrop.app built successfully at: $APP_DIR"
