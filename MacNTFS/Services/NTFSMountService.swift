import Foundation

enum FormatType: String, CaseIterable, Sendable {
    case ntfs = "NTFS"
    case exfat = "ExFAT"
    case fat32 = "FAT32"
}

actor NTFSMountService {
    static let shared = NTFSMountService()

    private let ntfs3gPaths = [
        "/opt/homebrew/bin/ntfs-3g",
        "/usr/local/bin/ntfs-3g",
        "/opt/homebrew/sbin/ntfs-3g",
    ]

    private let mountBase = "/Volumes"

    func findNTFS3G() -> String? {
        for path in ntfs3gPaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }

    func mount(disk: ExternalDisk) async throws -> String {
        guard disk.isNTFS else {
            throw NTFSError.notNTFS(disk.fileSystem)
        }

        guard let ntfs3gPath = findNTFS3G() else {
            throw NTFSError.ntfs3gNotFound
        }

        let mountPoint = "\(mountBase)/\(sanitizeName(disk.name))"
        let devicePath = disk.devicePath

        LogService.shared.log(.info, "Mounting \(disk.id) at \(mountPoint) with ntfs-3g")

        // Kill any existing ntfs-3g processes
        _ = await sudo("/usr/bin/pkill", ["-9", "-f", "ntfs-3g"])
        try await Task.sleep(nanoseconds: 1_000_000_000)

        // Force unmount existing mount
        _ = await sudo("/usr/sbin/diskutil", ["unmount", "force", devicePath])

        // Create mount point
        _ = await sudo("/bin/mkdir", ["-p", mountPoint])

        // Mount with ntfs-3g.
        // uid/gid: mount files owned by the calling user, not root.
        // Without this, FileManager operations fail with EPERM on the NFS mount.
        let uid = Int(getuid())
        let gid = Int(getgid())
        // fmask=0,dmask=0: all files owned by current user, full rwx — prevents Finder "Locked" errors.
        // auto_xattr removed: it creates ._AppleDouble files that can become immutable and block deletion.
        // nolocal: marks mount as network volume so Spotlight (mds) doesn't index it and hold file handles open.
        let options = "allow_other,big_writes,noatime,remove_hiberfile,uid=\(uid),gid=\(gid),fmask=0,dmask=0,nolocal"
        let (exitCode, output) = await sudo(ntfs3gPath, [devicePath, mountPoint, "-o", options])

        if exitCode != 0 {
            let msg = output.isEmpty ? "ntfs-3g exited \(exitCode)" : output
            LogService.shared.log(.error, "Mount error: \(msg)")
            throw NTFSError.mountFailed(msg)
        }

        // Give fuse-t time to complete NFS mount
        try await Task.sleep(nanoseconds: 1_500_000_000)

        // Verify mount
        let check = await shellOutput("mount | grep '\(mountPoint)'")
        guard !check.isEmpty else {
            throw NTFSError.mountFailed("ntfs-3g started but volume not found at \(mountPoint)")
        }

        // Prevent Spotlight from indexing — mds holds file handles open causing "folder in use" on delete.
        FileManager.default.createFile(atPath: "\(mountPoint)/.metadata_never_index", contents: nil)

        LogService.shared.log(.info, "Successfully mounted \(disk.name) at \(mountPoint)")
        return mountPoint
    }

    func unmount(mountPoint: String) async throws {
        let (exitCode, output) = await sudo("/sbin/umount", ["-f", mountPoint])
        if exitCode != 0 {
            let msg = output.isEmpty ? "umount exited \(exitCode)" : output
            LogService.shared.log(.error, "Unmount error: \(msg)")
            throw NTFSError.unmountFailed(mountPoint)
        }
        LogService.shared.log(.info, "Unmounted \(mountPoint)")
    }

    func eject(disk: ExternalDisk) async throws {
        // Tear down NFS loopback if mounted by ntfs-3g
        if let mountPoint = disk.mountPoint {
            _ = await sudo("/sbin/umount", ["-f", mountPoint])
        }
        // Kill any remaining ntfs-3g process for this device
        _ = await sudo("/usr/bin/pkill", ["-9", "-f", "ntfs-3g.*\(disk.devicePath)"])
        try await Task.sleep(nanoseconds: 500_000_000)
        // Eject the whole physical disk — diskutil unmounts any remaining macOS volumes first
        let parent = parentBSDName(disk.id)
        let (code, output) = await sudo("/usr/sbin/diskutil", ["eject", parent])
        if code != 0 {
            throw NTFSError.operationFailed(output.isEmpty ? "diskutil eject exited \(code)" : output)
        }
        LogService.shared.log(.info, "Ejected \(disk.name) (\(parent))")
    }

    func format(disk: ExternalDisk, label: String, format: FormatType) async throws {
        let parent = parentBSDName(disk.id)
        // Tear down any existing mount
        if let mp = disk.mountPoint {
            _ = await sudo("/sbin/umount", ["-f", mp])
        }
        _ = await sudo("/usr/bin/pkill", ["-9", "-f", "ntfs-3g.*\(disk.devicePath)"])
        try await Task.sleep(nanoseconds: 500_000_000)
        _ = await sudo("/usr/sbin/diskutil", ["unmountDisk", "force", parent])
        try await Task.sleep(nanoseconds: 500_000_000)

        // FAT32/exFAT labels max 11 chars; truncate for safety across all formats
        let safeLabel = String(label.prefix(11)).isEmpty ? "UNTITLED" : String(label.prefix(11))

        switch format {
        case .ntfs:
            guard let mkntfs = findMkntfs() else {
                throw NTFSError.operationFailed("mkntfs not found. Re-run setup.sh to add /opt/homebrew/sbin/mkntfs to sudoers, then retry.")
            }
            // Create GPT partition table with a temp ExFAT partition, then overwrite with NTFS
            let (c1, o1) = await sudo("/usr/sbin/diskutil", ["eraseDisk", "ExFAT", safeLabel, "GPTFormat", parent])
            if c1 != 0 { throw NTFSError.operationFailed(o1.isEmpty ? "eraseDisk failed (\(c1))" : o1) }
            try await Task.sleep(nanoseconds: 2_000_000_000)
            let (c2, o2) = await sudo(mkntfs, ["--fast", "-L", safeLabel, "/dev/\(parent)s1"])
            if c2 != 0 { throw NTFSError.operationFailed(o2.isEmpty ? "mkntfs failed (\(c2))" : o2) }
            LogService.shared.log(.info, "Formatted \(parent) as NTFS label=\(safeLabel)")

        case .exfat:
            let (c, o) = await sudo("/usr/sbin/diskutil", ["eraseDisk", "ExFAT", safeLabel, "GPTFormat", parent])
            if c != 0 { throw NTFSError.operationFailed(o.isEmpty ? "eraseDisk failed (\(c))" : o) }
            LogService.shared.log(.info, "Formatted \(parent) as ExFAT label=\(safeLabel)")

        case .fat32:
            let (c, o) = await sudo("/usr/sbin/diskutil", ["eraseDisk", "MS-DOS", safeLabel, "MBRFormat", parent])
            if c != 0 { throw NTFSError.operationFailed(o.isEmpty ? "eraseDisk failed (\(c))" : o) }
            LogService.shared.log(.info, "Formatted \(parent) as FAT32 label=\(safeLabel)")
        }
    }

    private func findMkntfs() -> String? {
        let paths = ["/opt/homebrew/sbin/mkntfs", "/usr/local/sbin/mkntfs", "/opt/homebrew/bin/mkntfs"]
        return paths.first { FileManager.default.fileExists(atPath: $0) }
    }

    private func parentBSDName(_ bsdName: String) -> String {
        // "disk5s1" → "disk5"; "disk5" → "disk5"
        guard let lastS = bsdName.lastIndex(of: "s") else { return bsdName }
        let suffix = bsdName[bsdName.index(after: lastS)...]
        guard !suffix.isEmpty, suffix.allSatisfy(\.isNumber) else { return bsdName }
        let parent = String(bsdName[..<lastS])
        return parent.hasPrefix("disk") ? parent : bsdName
    }

    // MARK: - Private

    private func sudo(_ executable: String, _ arguments: [String]) async -> (Int32, String) {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
                process.arguments = ["-n", executable] + arguments

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let out = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !out.isEmpty {
                        LogService.shared.log(.debug, "[\(URL(fileURLWithPath: executable).lastPathComponent)] \(out)")
                    }
                    continuation.resume(returning: (process.terminationStatus, out))
                } catch {
                    continuation.resume(returning: (-1, error.localizedDescription))
                }
            }
        }
    }

    private func shellOutput(_ command: String) async -> String {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = ["-c", command]
                let pipe = Pipe()
                process.standardOutput = pipe
                try? process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let out = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: out)
            }
        }
    }

    private func sanitizeName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_"))
        return name.unicodeScalars
            .filter { allowed.contains($0) }
            .map { String($0) }
            .joined()
    }
}

enum NTFSError: LocalizedError {
    case notNTFS(String)
    case ntfs3gNotFound
    case mountFailed(String)
    case unmountFailed(String)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notNTFS(let fs): return "Disk is \(fs), not NTFS"
        case .ntfs3gNotFound: return "ntfs-3g not found. Install: brew install ntfs-3g"
        case .mountFailed(let msg): return "Mount failed: \(msg)"
        case .unmountFailed(let path): return "Failed to unmount \(path)"
        case .operationFailed(let msg): return "Operation failed: \(msg)"
        }
    }
}
