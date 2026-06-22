#!/bin/bash
set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BOLD}=== MacNTFS Setup ===${NC}"
echo ""

# 1. Check macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo -e "${RED}ERROR: macOS required${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} macOS detected"

# 2. Check Homebrew
if ! command -v brew &> /dev/null; then
    echo -e "${YELLOW}Installing Homebrew...${NC}"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
    echo -e "${GREEN}✓${NC} Homebrew found"
fi

# 3. Install macFUSE
if [ ! -d "/Library/Frameworks/macFUSE.framework" ]; then
    echo -e "${YELLOW}Installing macFUSE (requires admin password)...${NC}"
    brew install --cask macfuse
else
    echo -e "${GREEN}✓${NC} macFUSE installed"
fi

# 4. Install ntfs-3g
if ! command -v ntfs-3g &> /dev/null; then
    echo -e "${YELLOW}Installing ntfs-3g...${NC}"
    brew tap gromgit/fuse 2>/dev/null || true
    brew install gromgit/fuse/ntfs-3g-mac
else
    echo -e "${GREEN}✓${NC} ntfs-3g installed ($(ntfs-3g --version 2>&1 | head -1))"
fi

# 5. Check Xcode
if ! command -v xcodebuild &> /dev/null; then
    echo -e "${RED}ERROR: Xcode required. Install from App Store.${NC}"
    echo "After installing, run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    exit 1
fi
echo -e "${GREEN}✓${NC} Xcode found"

# 6. Generate Xcode project
if command -v xcodegen &> /dev/null; then
    echo "Generating Xcode project..."
    xcodegen generate 2>/dev/null
    echo -e "${GREEN}✓${NC} Xcode project generated"
else
    echo -e "${YELLOW}xcodegen not found, installing...${NC}"
    brew install xcodegen
    xcodegen generate 2>/dev/null
    echo -e "${GREEN}✓${NC} Xcode project generated"
fi

# 7. Build
echo "Building MacNTFS..."
xcodebuild -project MacNTFS.xcodeproj -scheme MacNTFS -configuration Release build -quiet 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Build succeeded"
else
    echo -e "${RED}Build failed. Open MacNTFS.xcodeproj in Xcode for details.${NC}"
    exit 1
fi

# 8. Copy to Applications
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/MacNTFS*/Build/Products/Release -name "MacNTFS.app" -maxdepth 1 2>/dev/null | head -1)

if [ -n "$APP_PATH" ]; then
    echo ""
    read -p "Install MacNTFS.app to /Applications? [y/N] " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cp -R "$APP_PATH" /Applications/MacNTFS.app
        echo -e "${GREEN}✓${NC} Installed to /Applications/MacNTFS.app"
    else
        cp -R "$APP_PATH" ~/Desktop/MacNTFS.app
        echo -e "${GREEN}✓${NC} Copied to Desktop/MacNTFS.app"
    fi
fi

echo ""
echo -e "${BOLD}=== Setup Complete ===${NC}"
echo ""
echo "Open MacNTFS from Applications or Desktop."
echo "Connect an NTFS drive and click 'Mount with Write Support'."
echo ""
echo -e "Created by Alexander Calambas — ${BOLD}https://github.com/JhojanAlexanderCalambasRamirez${NC}"
