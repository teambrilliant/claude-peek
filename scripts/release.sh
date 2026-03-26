#!/bin/bash
set -euo pipefail

# Required env vars for notarization:
#   NOTARY_KEY_ID     — App Store Connect API Key ID
#   NOTARY_KEY_PATH   — path to .p8 file
#   NOTARY_ISSUER_ID  — Issuer ID (UUID from App Store Connect)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_NAME="ClaudePeek"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
SIGNING_IDENTITY="Developer ID Application: BRILLIANT CONSULTING, SL (3SBUQ56769)"
ZIP_PATH="$PROJECT_DIR/$APP_NAME.zip"

for var in NOTARY_KEY_ID NOTARY_KEY_PATH NOTARY_ISSUER_ID; do
    if [ -z "${!var:-}" ]; then
        echo "Error: $var is not set" >&2
        exit 1
    fi
done

cd "$PROJECT_DIR"

# Build
echo "Building $APP_NAME (release)..."
swift build -c release 2>&1

# Create app bundle
echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp .build/release/ClaudePeek "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"
cp claude-peek.icns "$APP_BUNDLE/Contents/Resources/claude-peek.icns"

# Sign
echo "Signing with: $SIGNING_IDENTITY"
codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"

echo "Verifying signature..."
codesign --verify --verbose "$APP_BUNDLE"

# Zip for notarization (notarytool requires a zip/dmg/pkg)
echo "Creating zip..."
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

# Notarize
echo "Submitting for notarization..."
xcrun notarytool submit "$ZIP_PATH" \
    --key "$NOTARY_KEY_PATH" \
    --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER_ID" \
    --wait

# Staple
echo "Stapling notarization ticket..."
xcrun stapler staple "$APP_BUNDLE"

# Re-zip with stapled ticket
echo "Creating final zip..."
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo ""
echo "Done: $ZIP_PATH"
echo "Upload this to GitHub Releases."
