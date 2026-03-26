#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="ClaudePeek"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
INSTALL_PATH="/Applications/$APP_NAME.app"

cd "$PROJECT_DIR"

echo "Building $APP_NAME..."
swift build -c release 2>&1

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp .build/release/ClaudePeek "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"
cp claude-peek.icns "$APP_BUNDLE/Contents/Resources/claude-peek.icns"

# Codesign so accessibility permission persists across rebuilds
codesign --force --sign - "$APP_BUNDLE" 2>/dev/null || true

# Install to /Applications (preserves accessibility permission grant)
echo "Installing to $INSTALL_PATH..."
rm -rf "$INSTALL_PATH"
cp -r "$APP_BUNDLE" "$INSTALL_PATH"

echo "Built and installed: $INSTALL_PATH"
echo "To run: open $INSTALL_PATH"
