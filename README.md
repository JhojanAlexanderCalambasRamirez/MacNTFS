<p align="center">
  <img src="Images/LogoAppMacNTFS.png" alt="MacNTFS Logo" width="150">
</p>

<h1 align="center">MacNTFS</h1>

<p align="center">
  Native macOS app that enables full read/write support for NTFS-formatted external drives.
</p>

macOS detects NTFS drives but mounts them as **read-only**. MacNTFS re-mounts them with write support using `ntfs-3g`, so you can copy, move, rename, and delete files — without reformatting.

## Features

- **Auto-detection** — Detects external drives as soon as they're connected
- **NTFS identification** — Highlights NTFS drives and their status
- **One-click R/W mount** — Re-mounts NTFS drives with full write support via ntfs-3g
- **Built-in file manager** — Copy, move, rename, delete files with drag-and-drop
- **Progress tracking** — Visual progress for large file operations
- **Integrity checks** — Verifies file size after copy to prevent corruption
- **Live logs** — Real-time operation log panel

## Requirements

- macOS 14.0+ (Sonoma or later)
- Apple Silicon (M1/M2/M3/M4/M5) or Intel Mac
- [Xcode](https://apps.apple.com/app/xcode/id497799835) (for building from source)

## Quick Start

### Option 1: Build from source (developers)

```bash
git clone https://github.com/JhojanAlexanderCalambasRamirez/Mac-NTFS.git
cd Mac-NTFS
chmod +x setup.sh
./setup.sh
```

The script installs all dependencies, builds the app, and optionally copies it to `/Applications`.

### Option 2: Download release (users)

1. Go to [Releases](https://github.com/JhojanAlexanderCalambasRamirez/Mac-NTFS/releases)
2. Download the latest `.dmg`
3. Open the `.dmg` and drag **MacNTFS** to **Applications**
4. Install dependencies (one-time):
   ```bash
   brew install --cask macfuse
   brew tap gromgit/fuse
   brew install gromgit/fuse/ntfs-3g-mac
   ```

## How it works

```
Connect NTFS drive via USB
        │
        ▼
MacNTFS detects drive (DiskArbitration API)
        │
        ▼
Click "Mount with Write Support"
        │
        ▼
App unmounts read-only mount → re-mounts via ntfs-3g
        │
        ▼
Full R/W access — browse, copy, move, rename, delete
```

## Dependencies

| Component | Purpose | Install |
|-----------|---------|---------|
| [macFUSE](https://osxfuse.github.io/) | Filesystem in userspace | `brew install --cask macfuse` |
| [ntfs-3g](https://github.com/tuxera/ntfs-3g) | NTFS read/write driver | `brew install gromgit/fuse/ntfs-3g-mac` |

Both are installed automatically by `setup.sh`.

## Project Structure

```
MacNTFS/
├── App/            # Entry point, settings
├── Models/         # ExternalDisk, FileOperation
├── Services/       # Disk detection, NTFS mount, file ops, logging
├── ViewModels/     # UI state management
├── Views/          # SwiftUI views
└── Helpers/        # Privileged helper, shell executor
```

## Tech Stack

- **Swift 6** + **SwiftUI** — Native macOS UI
- **DiskArbitration.framework** — Real-time disk detection
- **macFUSE + ntfs-3g** — NTFS write support
- **XPC Services** — Privileged operations (mount/unmount)

## Building

```bash
# SPM
swift build

# Xcode
xcodebuild -project MacNTFS.xcodeproj -scheme MacNTFS build

# Create .dmg for distribution
chmod +x scripts/create-dmg.sh
mkdir -p dist
./scripts/create-dmg.sh 1.0.0
```

## License

[MIT](LICENSE) — Alexander Calambas

## Contact

- LinkedIn: [j4cr](https://www.linkedin.com/in/j4cr/)
- GitHub: [JhojanAlexanderCalambasRamirez](https://github.com/JhojanAlexanderCalambasRamirez)
- Email: alexandercalambas23@gmail.com
