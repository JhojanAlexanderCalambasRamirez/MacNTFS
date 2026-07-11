import Foundation

enum DiskStatus: String, Sendable {
    case detected = "Detected"
    case mounting = "Mounting..."
    case mounted = "Mounted (R/W)"
    case readOnly = "Read Only"
    case unmounting = "Unmounting..."
    case ejecting = "Ejecting..."
    case error = "Error"
}

struct ExternalDisk: Identifiable, Sendable {
    let id: String          // BSD name (e.g., "disk4s1")
    let name: String        // Volume name
    let fileSystem: String  // "ntfs", "exfat", "apfs", etc.
    let size: UInt64        // Bytes
    let mountPoint: String?
    var status: DiskStatus
    let isRemovable: Bool
    let busProtocol: String // "USB", "Thunderbolt", etc.

    var isNTFS: Bool {
        fileSystem.lowercased().contains("ntfs") ||
        fileSystem.lowercased().contains("windows_ntfs")
    }

    var sizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    var devicePath: String {
        "/dev/\(id)"
    }
}
