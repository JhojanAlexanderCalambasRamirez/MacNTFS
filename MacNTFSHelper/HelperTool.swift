import Foundation

@main
final class HelperTool: NSObject, HelperProtocol, NSXPCListenerDelegate, @unchecked Sendable {
    private nonisolated(unsafe) let listener: NSXPCListener

    override init() {
        listener = NSXPCListener(machServiceName: "com.macntfs.helper")
        super.init()
        listener.delegate = self
    }

    static func main() {
        let tool = HelperTool()
        tool.listener.resume()
        RunLoop.current.run()
    }

    // MARK: - NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: HelperProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    // MARK: - HelperProtocol

    func mountNTFS(device: String, mountPoint: String, volumeName: String, reply: @escaping @Sendable (Bool, String?) -> Void) {
        guard device.hasPrefix("/dev/disk") else {
            reply(false, "Invalid device path")
            return
        }

        guard mountPoint.hasPrefix("/Volumes/") else {
            reply(false, "Invalid mount point")
            return
        }

        let fm = FileManager.default
        if !fm.fileExists(atPath: mountPoint) {
            do {
                try fm.createDirectory(atPath: mountPoint, withIntermediateDirectories: true)
            } catch {
                reply(false, "Failed to create mount point: \(error.localizedDescription)")
                return
            }
        }

        let ntfs3gPath = findNTFS3G()
        guard let ntfs3gPath else {
            reply(false, "ntfs-3g not found")
            return
        }

        let unmount = Process()
        unmount.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        unmount.arguments = ["unmount", device]
        try? unmount.run()
        unmount.waitUntilExit()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ntfs3gPath)
        process.arguments = [
            device, mountPoint,
            "-o", "local,allow_other,auto_xattr,volname=\(volumeName),big_writes,noatime"
        ]

        let errPipe = Pipe()
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                reply(true, mountPoint)
            } else {
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errMsg = String(data: errData, encoding: .utf8) ?? "Unknown error"
                reply(false, errMsg)
            }
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    func unmountVolume(mountPoint: String, reply: @escaping @Sendable (Bool, String?) -> Void) {
        guard mountPoint.hasPrefix("/Volumes/") else {
            reply(false, "Invalid mount point")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/umount")
        process.arguments = [mountPoint]

        do {
            try process.run()
            process.waitUntilExit()
            reply(process.terminationStatus == 0, nil)
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    func checkNTFS3G(reply: @escaping @Sendable (Bool, String?) -> Void) {
        if let path = findNTFS3G() {
            reply(true, path)
        } else {
            reply(false, nil)
        }
    }

    private func findNTFS3G() -> String? {
        let paths = [
            "/opt/homebrew/bin/ntfs-3g",
            "/usr/local/bin/ntfs-3g",
            "/opt/homebrew/sbin/ntfs-3g",
        ]
        return paths.first { FileManager.default.fileExists(atPath: $0) }
    }
}
