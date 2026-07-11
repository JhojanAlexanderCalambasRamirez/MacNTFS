import Foundation

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
