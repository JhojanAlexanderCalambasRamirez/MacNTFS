#!/bin/bash
set -euo pipefail

echo "=== MacNTFS Dependency Installer ==="

# Check Homebrew
if ! command -v brew &> /dev/null; then
    echo "ERROR: Homebrew not found. Install from https://brew.sh"
    exit 1
fi
echo "✓ Homebrew found"

# Install macFUSE
if [ ! -d "/Library/Frameworks/macFUSE.framework" ]; then
    echo "Installing macFUSE..."
    brew install --cask macfuse
else
    echo "✓ macFUSE already installed"
fi

# Install ntfs-3g-mac (from gromgit/fuse tap)
if ! command -v ntfs-3g &> /dev/null; then
    echo "Installing ntfs-3g-mac..."
    brew tap gromgit/fuse 2>/dev/null || true
    brew install gromgit/fuse/ntfs-3g-mac
else
    echo "✓ ntfs-3g already installed at $(which ntfs-3g)"
fi

# Verify
echo ""
echo "=== Verification ==="
ntfs-3g --version 2>&1 | head -1 || echo "WARNING: ntfs-3g version check failed"

echo ""
echo "=== Setup Complete ==="
echo "You can now build and run MacNTFS."
echo ""
echo "Note: Mounting NTFS volumes requires root privileges."
echo "The app will use a privileged helper tool for this."
