#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_NAME="备考桌面小组件.app"
EXECUTABLE_NAME="StudyScheduleWidget"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
APP_BUNDLE="$BUILD_DIR/$APP_NAME"
INSTALL_PATH="/Applications/$APP_NAME"

rm -rf "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

echo "Generating app icon..."
swift "$SCRIPT_DIR/generate_icon.swift" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

echo "Compiling Swift sources..."
swiftc \
    -O \
    -target arm64-apple-macosx13.0 \
    -framework AppKit \
    -framework SwiftUI \
    -framework Combine \
    "$SCRIPT_DIR/Sources/Models.swift" \
    "$SCRIPT_DIR/Sources/ScheduleStore.swift" \
    "$SCRIPT_DIR/Sources/WidgetView.swift" \
    "$SCRIPT_DIR/Sources/AppDelegate.swift" \
    "$SCRIPT_DIR/Sources/main.swift" \
    -o "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"

cp "$SCRIPT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

echo "Signing app bundle (ad-hoc)..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "Installing to $INSTALL_PATH..."
rm -rf "$INSTALL_PATH"
cp -R "$APP_BUNDLE" "$INSTALL_PATH"

echo "Build and install complete: $INSTALL_PATH"
