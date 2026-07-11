#!/bin/bash
set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${BOLD}=== MacNTFS Setup ===${NC}"
echo -e "${CYAN}NTFS read/write for macOS 26 Tahoe (Apple Silicon)${NC}"
echo ""

# ── 1. macOS check ──────────────────────────────────────────────────────────
if [[ "$(uname)" != "Darwin" ]]; then
    echo -e "${RED}ERROR: macOS required${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} macOS $(sw_vers -productVersion)"

# ── 2. Homebrew ─────────────────────────────────────────────────────────────
if ! command -v brew &>/dev/null; then
    echo -e "${YELLOW}Installing Homebrew...${NC}"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # Add to PATH for this session (Apple Silicon path)
    if [[ -f /opt/homebrew/bin/brew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    fi
else
    echo -e "${GREEN}✓${NC} Homebrew $(brew --version | head -1)"
fi

# ── 3. FUSE-T ────────────────────────────────────────────────────────────────
# macFUSE requires a kext that cannot load on macOS 26 arm64 with SIP enabled.
# FUSE-T uses NFS loopback — no kext, no SIP bypass needed.
if [[ -d /Library/Frameworks/fuse_t.framework ]]; then
    echo -e "${GREEN}✓${NC} FUSE-T already installed"
else
    echo ""
    echo -e "${YELLOW}Installing FUSE-T...${NC}"
    if brew list --cask fuse-t &>/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} FUSE-T (via Homebrew cask)"
    else
        brew install --cask fuse-t || {
            echo ""
            echo -e "${YELLOW}Homebrew cask failed. Download manually from:${NC}"
            echo "  https://www.fuse-t.org/"
            echo ""
            echo "Install it, then run this script again."
            exit 1
        }
    fi

    if [[ ! -d /Library/Frameworks/fuse_t.framework ]]; then
        echo -e "${RED}ERROR: FUSE-T installed but framework not found at /Library/Frameworks/fuse_t.framework${NC}"
        echo "Open /Applications/fuse-t.app to complete installation, then run this script again."
        exit 1
    fi
    echo -e "${GREEN}✓${NC} FUSE-T installed"
fi

# ── 4. Build ntfs-3g from source and patch for FUSE-T ───────────────────────
NTFS3G_BIN="/opt/homebrew/bin/ntfs-3g"
NEEDS_BUILD=false

if [[ ! -f "$NTFS3G_BIN" ]]; then
    NEEDS_BUILD=true
else
    # Check if already linked to fuse_t.framework
    if ! otool -L "$NTFS3G_BIN" 2>/dev/null | grep -q "fuse_t.framework"; then
        NEEDS_BUILD=true
    fi
fi

if [[ "$NEEDS_BUILD" == "false" ]]; then
    echo -e "${GREEN}✓${NC} ntfs-3g already built and patched for FUSE-T"
else
    echo ""
    echo -e "${YELLOW}Building ntfs-3g from source (this takes ~2 minutes)...${NC}"

    # Install build dependencies
    brew install autoconf automake libtool pkg-config 2>/dev/null || true
    echo -e "${GREEN}✓${NC} Build tools ready"

    # Clone and build
    BUILD_DIR="$(mktemp -d)/ntfs-3g-build"
    git clone --depth=1 https://github.com/tuxera/ntfs-3g.git "$BUILD_DIR"
    cd "$BUILD_DIR"

    ./autogen.sh
    ./configure \
        CFLAGS="-I/Library/Frameworks/fuse_t.framework/Headers" \
        LDFLAGS="-F/Library/Frameworks -framework fuse_t" \
        --disable-ntfsprogs \
        --disable-crypto \
        --quiet

    make -j"$(sysctl -n hw.logicalcpu)"
    sudo make install

    cd -
    rm -rf "$BUILD_DIR"

    # Patch dynamic library path
    if [[ -f "$NTFS3G_BIN" ]]; then
        OLD_LIB=$(otool -L "$NTFS3G_BIN" 2>/dev/null | grep libfuse | awk '{print $1}' | head -1 || true)
        if [[ -n "$OLD_LIB" ]]; then
            sudo install_name_tool -change \
                "$OLD_LIB" \
                "/Library/Frameworks/fuse_t.framework/fuse_t" \
                "$NTFS3G_BIN"
            echo -e "${GREEN}✓${NC} ntfs-3g patched: libfuse → fuse_t.framework"
        else
            echo -e "${GREEN}✓${NC} ntfs-3g built (no libfuse path to patch)"
        fi
    else
        echo -e "${RED}ERROR: ntfs-3g build succeeded but binary not found at $NTFS3G_BIN${NC}"
        exit 1
    fi

    # Verify
    if otool -L "$NTFS3G_BIN" 2>/dev/null | grep -q "fuse_t.framework"; then
        echo -e "${GREEN}✓${NC} ntfs-3g links to fuse_t.framework — verified"
    else
        echo -e "${RED}WARNING: Could not confirm fuse_t linkage. Manual verification:${NC}"
        echo "  otool -L $NTFS3G_BIN | grep fuse"
    fi
fi

# ── 5. Configure sudoers (NOPASSWD) ─────────────────────────────────────────
SUDOERS_FILE="/etc/sudoers.d/ntfs3g"
SUDOERS_OK=true

for bin in /usr/bin/pkill /usr/sbin/diskutil /bin/mkdir "$NTFS3G_BIN" /sbin/umount; do
    if ! sudo grep -q "NOPASSWD: $bin" "$SUDOERS_FILE" 2>/dev/null; then
        SUDOERS_OK=false
        break
    fi
done

if [[ "$SUDOERS_OK" == "true" ]]; then
    echo -e "${GREEN}✓${NC} sudoers already configured"
else
    echo ""
    echo -e "${YELLOW}Configuring sudo privileges (requires admin password)...${NC}"
    sudo tee "$SUDOERS_FILE" > /dev/null << SUDOEOF
ALL ALL=(ALL) NOPASSWD: /usr/bin/pkill
ALL ALL=(ALL) NOPASSWD: /usr/sbin/diskutil
ALL ALL=(ALL) NOPASSWD: /bin/mkdir
ALL ALL=(ALL) NOPASSWD: $NTFS3G_BIN
ALL ALL=(ALL) NOPASSWD: /sbin/umount
SUDOEOF
    sudo chmod 440 "$SUDOERS_FILE"
    sudo visudo -c &>/dev/null && echo -e "${GREEN}✓${NC} sudoers configured" || {
        echo -e "${RED}ERROR: sudoers syntax invalid — removing${NC}"
        sudo rm "$SUDOERS_FILE"
        exit 1
    }
fi

# ── 6. Xcode check ──────────────────────────────────────────────────────────
if ! command -v xcodebuild &>/dev/null; then
    echo ""
    echo -e "${RED}ERROR: Xcode not found.${NC}"
    echo "Install from App Store: https://apps.apple.com/app/xcode/id497799835"
    echo "Then run this script again."
    exit 1
fi

XCODE_PATH=$(xcode-select -p 2>/dev/null)
if [[ "$XCODE_PATH" == */CommandLineTools* ]]; then
    echo -e "${YELLOW}Switching xcode-select from CommandLineTools to Xcode.app...${NC}"
    if [[ -d /Applications/Xcode.app ]]; then
        sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
        echo -e "${GREEN}✓${NC} xcode-select → Xcode.app"
    else
        echo -e "${RED}ERROR: Xcode.app not found in /Applications${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓${NC} Xcode: $XCODE_PATH"
fi

if ! xcodebuild -checkFirstLaunchStatus &>/dev/null; then
    echo -e "${YELLOW}Accepting Xcode license...${NC}"
    sudo xcodebuild -license accept 2>/dev/null || true
    sudo xcodebuild -runFirstLaunch 2>/dev/null || true
fi

# ── 7. Generate Xcode project (if xcodegen present) ─────────────────────────
if command -v xcodegen &>/dev/null && [[ -f project.yml ]]; then
    xcodegen generate 2>/dev/null
    echo -e "${GREEN}✓${NC} Xcode project generated"
fi

# ── 8. Build the app ─────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}Building MacNTFS...${NC}"
BUILD_DIR_APP="$(mktemp -d)/macntfs-release"
xcodebuild \
    -project MacNTFS.xcodeproj \
    -scheme MacNTFS \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR_APP" \
    build -quiet 2>&1

APP_PATH="$BUILD_DIR_APP/Build/Products/Release/MacNTFS.app"

if [[ -d "$APP_PATH" ]]; then
    echo -e "${GREEN}✓${NC} Build succeeded"
else
    echo -e "${RED}Build failed. Open MacNTFS.xcodeproj in Xcode for details.${NC}"
    exit 1
fi

# ── 9. Install ───────────────────────────────────────────────────────────────
echo ""
read -p "Install MacNTFS.app to /Applications? [y/N] " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf /Applications/MacNTFS.app
    cp -R "$APP_PATH" /Applications/MacNTFS.app
    INSTALLED_PATH="/Applications/MacNTFS.app"
    echo -e "${GREEN}✓${NC} Installed to /Applications/MacNTFS.app"
else
    rm -rf ~/Desktop/MacNTFS.app
    cp -R "$APP_PATH" ~/Desktop/MacNTFS.app
    INSTALLED_PATH="$HOME/Desktop/MacNTFS.app"
    echo -e "${GREEN}✓${NC} Copied to Desktop/MacNTFS.app"
fi

rm -rf "$BUILD_DIR_APP"

# ── 10. Done ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}=== Setup Complete ===${NC}"
echo ""
echo -e "${BOLD}IMPORTANT — Required manual step:${NC}"
echo ""
echo "  Grant Full Disk Access to MacNTFS:"
echo "  System Settings → Privacy & Security → Full Disk Access"
echo "  Click + → select MacNTFS.app → toggle ON"
echo ""
echo "  Without this, ntfs-3g cannot open /dev/disk devices."
echo ""
echo -e "${BOLD}First launch — Gatekeeper:${NC}"
echo "  Right-click MacNTFS.app → Open → click Open in the dialog"
echo "  (or System Settings → Privacy & Security → Open Anyway)"
echo ""
echo -e "Connect an NTFS drive and click ${BOLD}Mount with Write Support${NC}."
echo ""
echo -e "${CYAN}https://github.com/JhojanAlexanderCalambasRamirez/MacNTFS${NC}"
