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
mkdir -p "$APP_DIR/Contents/Resources"
mkdir -p "$APP_DIR/Contents/PlugIns/SnowdropShare.appex/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/PlugIns/SnowdropShare.appex/Contents/Resources"
cp "$DIR/.build/release/Snowdrop" "$APP_DIR/Contents/MacOS/Snowdrop"
cp "$DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
if [ -d "$DIR/Resources" ]; then
    cp -r "$DIR/Resources/"* "$APP_DIR/Contents/Resources/"
    cp "$DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/PlugIns/SnowdropShare.appex/Contents/Resources/AppIcon.icns"
    cp "$DIR/Resources/AppIcon.png" "$APP_DIR/Contents/PlugIns/SnowdropShare.appex/Contents/Resources/AppIcon.png" 2>/dev/null || true
fi

echo "==> Building macOS Share Extension..."
swiftc -target arm64-apple-macosx13.0 \
    -parse-as-library \
    -Xlinker -e -Xlinker _NSExtensionMain \
    "$DIR/ShareExtension/ShareViewController.swift" \
    -o "$APP_DIR/Contents/PlugIns/SnowdropShare.appex/Contents/MacOS/SnowdropShare"

cp "$DIR/ShareExtension/Info.plist" "$APP_DIR/Contents/PlugIns/SnowdropShare.appex/Contents/Info.plist"
echo "APPL????" > "$APP_DIR/Contents/PkgInfo"
echo "XPC!????" > "$APP_DIR/Contents/PlugIns/SnowdropShare.appex/Contents/PkgInfo"

echo "==> Ad-hoc signing bundles..."
codesign -s - --force --entitlements "$DIR/ShareExtension/ShareExtension.entitlements" "$APP_DIR/Contents/PlugIns/SnowdropShare.appex"
codesign -s - --force "$APP_DIR"

touch "$APP_DIR"
touch "$APP_DIR/Contents/PlugIns/SnowdropShare.appex"

echo "==> Registering with LaunchServices and pluginkit..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR" 2>/dev/null || true
pluginkit -r "$APP_DIR/Contents/PlugIns/SnowdropShare.appex" 2>/dev/null || true
pluginkit -a "$APP_DIR/Contents/PlugIns/SnowdropShare.appex" 2>/dev/null || true
pluginkit -e use -i com.snowdrop.mac.share 2>/dev/null || true
/System/Library/CoreServices/pbs -update 2>/dev/null || true

echo "==> Snowdrop.app built successfully at: $APP_DIR"
