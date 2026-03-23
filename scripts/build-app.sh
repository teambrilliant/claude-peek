#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="ClaudePeek"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"

cd "$PROJECT_DIR"

echo "Building $APP_NAME..."
swift build -c release 2>&1

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"

cp .build/release/ClaudePeek "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

# Codesign so accessibility permission persists across rebuilds
codesign --force --sign - "$APP_BUNDLE" 2>/dev/null || true

echo "Built: $APP_BUNDLE"
echo ""
echo "To install:  cp -r $APP_BUNDLE /Applications/"
echo "To run:      open $APP_BUNDLE"
