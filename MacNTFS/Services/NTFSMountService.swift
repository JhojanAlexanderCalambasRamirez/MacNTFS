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

        // Create mount point if needed
        if !FileManager.default.fileExists(atPath: mountPoint) {
            try FileManager.default.createDirectory(
                atPath: mountPoint,
                withIntermediateDirectories: true
            )
        }

        // Unmount existing read-only mount first
        if disk.mountPoint != nil {
            try await unmountNative(disk: disk)
        }

        // Mount with ntfs-3g
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ntfs3gPath)
        process.arguments = [
            disk.devicePath,
            mountPoint,
            "-o", "local,allow_other,auto_xattr,volname=\(disk.name)",
            "-o", "big_writes",    // Better write performance
            "-o", "noatime",       // Skip access time updates
        ]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        LogService.shared.log(.info, "Mounting \(disk.id) at \(mountPoint) with ntfs-3g")

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw NTFSError.mountFailed(errorMsg)
        }

        LogService.shared.log(.info, "Successfully mounted \(disk.name) at \(mountPoint)")
        return mountPoint
    }

    func unmount(mountPoint: String) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/umount")
        process.arguments = [mountPoint]

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            // Force unmount as fallback
            let forceProcess = Process()
            forceProcess.executableURL = URL(fileURLWithPath: "/usr/bin/umount")
            forceProcess.arguments = ["-f", mountPoint]

            try forceProcess.run()
            forceProcess.waitUntilExit()

            if forceProcess.terminationStatus != 0 {
                throw NTFSError.unmountFailed(mountPoint)
            }
        }

        LogService.shared.log(.info, "Unmounted \(mountPoint)")
    }

    private func unmountNative(disk: ExternalDisk) async throws {
        guard let mountPoint = disk.mountPoint else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["unmount", disk.devicePath]

        try process.run()
        process.waitUntilExit()

        LogService.shared.log(.info, "Unmounted native mount at \(mountPoint)")
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
