#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NEXT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
INSTALL_APP="/Applications/Snowdrop.app"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

echo "==> Generating Xcode project..."
xcodegen generate --spec "$NEXT_DIR/project.yml"

echo "==> Building Release Snowdrop.app..."
xcodebuild \
    -project "$NEXT_DIR/Snowdrop.xcodeproj" \
    -scheme Snowdrop \
    -configuration Release \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR" \
    ONLY_ACTIVE_ARCH=YES \
    CODE_SIGNING_ALLOWED=NO \
    build

APP_DIR="$BUILD_DIR/Snowdrop.app"
if [ ! -d "$APP_DIR" ]; then
    echo "error: built bundle not found at $APP_DIR" >&2
    exit 1
fi

echo "==> Ad-hoc signing inside-out with sandbox entitlements..."
codesign --force --sign - "$APP_DIR/Contents/Frameworks/SnowdropCore.framework"
codesign --force --sign - --entitlements "$NEXT_DIR/Config/SnowdropShare.entitlements" "$APP_DIR/Contents/PlugIns/SnowdropShare.appex"
codesign --force --sign - --entitlements "$NEXT_DIR/Config/Snowdrop.entitlements" "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "==> Installing to $INSTALL_APP..."
killall Snowdrop ShareExtension SnowdropShare 2>/dev/null || true
for _ in $(seq 1 25); do
    pgrep -x Snowdrop >/dev/null 2>&1 || break
    sleep 0.2
done

rm -rf "$INSTALL_APP"
ditto "$APP_DIR" "$INSTALL_APP"
touch "$INSTALL_APP"
touch "$INSTALL_APP/Contents/PlugIns/SnowdropShare.appex"

echo "==> Registering LaunchServices, Share Extension, and Services..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -r "$INSTALL_APP"
pluginkit -r "$INSTALL_APP/Contents/PlugIns/SnowdropShare.appex" 2>/dev/null || true
pluginkit -a "$INSTALL_APP/Contents/PlugIns/SnowdropShare.appex"
pluginkit -e use -i com.snowdrop.mac.share
/System/Library/CoreServices/pbs -update 2>/dev/null || true
killall ShareSheetUI 2>/dev/null || true

echo "==> Launching $INSTALL_APP..."
open -a "$INSTALL_APP"
