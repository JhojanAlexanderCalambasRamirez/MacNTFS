#!/bin/bash
set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
NC='\033[0m'

APP_NAME="MacNTFS"
DMG_NAME="MacNTFS-Installer"
VERSION="${1:-1.0.0}"
DMG_FINAL="${DMG_NAME}-v${VERSION}.dmg"

echo -e "${BOLD}=== Creating ${DMG_FINAL} ===${NC}"

# Build Release
echo "Building Release..."
xcodebuild -project MacNTFS.xcodeproj -scheme MacNTFS -configuration Release build -quiet

APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/MacNTFS*/Build/Products/Release -name "MacNTFS.app" -maxdepth 1 2>/dev/null | head -1)

if [ -z "$APP_PATH" ]; then
    echo "ERROR: MacNTFS.app not found after build"
    exit 1
fi

# Prepare staging directory
STAGING_DIR=$(mktemp -d)
cp -R "$APP_PATH" "$STAGING_DIR/${APP_NAME}.app"
ln -s /Applications "$STAGING_DIR/Applications"

# Create DMG
echo "Creating DMG..."
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov -format UDZO \
    "dist/${DMG_FINAL}"

# Cleanup
rm -rf "$STAGING_DIR"

echo ""
echo -e "${GREEN}✓${NC} Created dist/${DMG_FINAL}"
echo "Upload this file as a GitHub Release asset."
