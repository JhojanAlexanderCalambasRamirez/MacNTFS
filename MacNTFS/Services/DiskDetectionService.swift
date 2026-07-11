import Foundation
import DiskArbitration

@MainActor
final class DiskDetectionService: ObservableObject {
    @Published var disks: [ExternalDisk] = []
    var mountingDisks: Set<String> = []

    private var session: DASession?
    private let queue = DispatchQueue(label: "com.macntfs.diskdetection")

    // BSD names currently claimed by ntfs-3g — DA auto-mount blocked for these.
    // Lock protects access from both MainActor and DA dispatch queue.
    nonisolated(unsafe) private var _claimedDisks: Set<String> = []
    nonisolated(unsafe) private let claimedLock = NSLock()

    nonisolated private func isClaimed(_ bsdName: String) -> Bool {
        claimedLock.lock()
        defer { claimedLock.unlock() }
        return _claimedDisks.contains(bsdName)
    }

    func claimDisk(_ bsdName: String) {
        claimedLock.lock()
        _claimedDisks.insert(bsdName)
        claimedLock.unlock()
        LogService.shared.log(.debug, "DA auto-mount blocked for \(bsdName)")
    }

    func releaseDisk(_ bsdName: String) {
        claimedLock.lock()
        _claimedDisks.remove(bsdName)
        claimedLock.unlock()
    }

    func startMonitoring() {
        guard let session = DASessionCreate(kCFAllocatorDefault) else {
            LogService.shared.log(.error, "Failed to create DiskArbitration session")
            return
        }
        self.session = session

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let appearedCallback: DADiskAppearedCallback = { disk, context in
            guard let context else { return }
            let service = Unmanaged<DiskDetectionService>.fromOpaque(context).takeUnretainedValue()
            service.handleDiskAppeared(disk)
        }

        let disappearedCallback: DADiskDisappearedCallback = { disk, context in
            guard let context else { return }
            let service = Unmanaged<DiskDetectionService>.fromOpaque(context).takeUnretainedValue()
            service.handleDiskDisappeared(disk)
        }

        // Block DA from auto-mounting NTFS partitions held by ntfs-3g.
        // Without this, DA periodically cycles the underlying partition,
        // causing fuse-t NFS loopback to drop open file handles → Error -43.
        let mountApproval: DADiskMountApprovalCallback = { disk, context -> Unmanaged<DADissenter>? in
            guard let context else { return nil }
            let svc = Unmanaged<DiskDetectionService>.fromOpaque(context).takeUnretainedValue()
            guard let desc = DADiskCopyDescription(disk) as? [String: Any],
                  let bsdName = desc[kDADiskDescriptionMediaBSDNameKey as String] as? String,
                  svc.isClaimed(bsdName) else { return nil }
            return Unmanaged.passRetained(
                DADissenterCreate(kCFAllocatorDefault, DAReturn(kDAReturnBusy), "Managed by MacNTFS" as CFString)
            )
        }

        let match: CFDictionary = [kDADiskDescriptionVolumeMountableKey: true] as NSDictionary

        DARegisterDiskAppearedCallback(session, match, appearedCallback, selfPtr)
        DARegisterDiskDisappearedCallback(session, match, disappearedCallback, selfPtr)
        DARegisterDiskMountApprovalCallback(session, nil, mountApproval, selfPtr)
        DASessionSetDispatchQueue(session, queue)

        LogService.shared.log(.info, "Disk monitoring started")
        scanExistingDisks()
    }

    func stopMonitoring() {
        if let session {
            DASessionSetDispatchQueue(session, nil)
        }
        session = nil
        LogService.shared.log(.info, "Disk monitoring stopped")
    }

    private func scanExistingDisks() {
        Task.detached { [weak self] in
            guard let self else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
            process.arguments = ["list", "-plist", "external"]

            let pipe = Pipe()
            process.standardOutput = pipe

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                   let allDisks = plist["AllDisksAndPartitions"] as? [[String: Any]] {
                    for diskInfo in allDisks {
                        if let partitions = diskInfo["Partitions"] as? [[String: Any]] {
                            for partition in partitions {
                                if let disk = self.parseDiskInfo(partition) {
                                    await MainActor.run { self.addOrUpdateDisk(disk) }
                                }
                            }
                        } else {
                            if let disk = self.parseDiskInfo(diskInfo) {
                                await MainActor.run { self.addOrUpdateDisk(disk) }
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    LogService.shared.log(.error, "Failed to scan disks: \(error.localizedDescription)")
                }
            }
        }
    }

    private nonisolated func handleDiskAppeared(_ daDisk: DADisk) {
        guard let desc = DADiskCopyDescription(daDisk) as? [String: Any] else { return }

        let bsdName = desc[kDADiskDescriptionMediaBSDNameKey as String] as? String ?? "unknown"
        let volumeName = desc[kDADiskDescriptionVolumeNameKey as String] as? String ?? "Untitled"
        let fsType = desc[kDADiskDescriptionVolumeKindKey as String] as? String ?? "unknown"
        let mediaSize = desc[kDADiskDescriptionMediaSizeKey as String] as? UInt64 ?? 0
        let removable = desc[kDADiskDescriptionMediaRemovableKey as String] as? Bool ?? false
        let protocol_ = desc[kDADiskDescriptionDeviceProtocolKey as String] as? String ?? ""
        let mountURL = desc[kDADiskDescriptionVolumePathKey as String] as? URL

        // Skip fuse-t NFS loopback mounts — not real external disks
        guard fsType != "nfs" && fsType != "autofs" else { return }

        let busProtocol: String
        switch protocol_.lowercased() {
        case let p where p.contains("usb"): busProtocol = "USB"
        case let p where p.contains("thunderbolt"): busProtocol = "Thunderbolt"
        case let p where p.contains("firewire"): busProtocol = "FireWire"
        default: busProtocol = protocol_.isEmpty ? "USB" : protocol_
        }

        let disk = ExternalDisk(
            id: bsdName,
            name: volumeName,
            fileSystem: fsType,
            size: mediaSize,
            mountPoint: mountURL?.path,
            status: fsType.lowercased().contains("ntfs") ? .readOnly : .detected,
            isRemovable: removable,
            busProtocol: busProtocol
        )

        Task { @MainActor in
            // Don't reset state for a mounted volume (BSD name may differ after fuse-t cycling)
            let alreadyMounted = self.disks.contains(where: {
                ($0.id == disk.id || $0.name == disk.name) && $0.status == .mounted
            })
            if alreadyMounted { return }
            self.addOrUpdateDisk(disk)
            LogService.shared.log(.info, "Disk appeared: \(disk.name) (\(disk.fileSystem)) — \(disk.sizeFormatted)")
            NotificationService.sendDiskConnected(disk)
        }
    }

    private nonisolated func handleDiskDisappeared(_ daDisk: DADisk) {
        guard let desc = DADiskCopyDescription(daDisk) as? [String: Any],
              let bsdName = desc[kDADiskDescriptionMediaBSDNameKey as String] as? String else { return }

        Task { @MainActor in
            guard !self.mountingDisks.contains(bsdName) else { return }
            // Keep mounted/mounting disks — fuse-t causes DA cycling on the underlying partition
            if let existing = self.disks.first(where: { $0.id == bsdName }),
               existing.status == .mounted || existing.status == .mounting {
                return
            }
            guard let name = self.disks.first(where: { $0.id == bsdName })?.name else { return }
            self.disks.removeAll { $0.id == bsdName }
            LogService.shared.log(.info, "Disk removed: \(name)")
            NotificationService.sendDiskDisconnected(name)
        }
    }

    private func addOrUpdateDisk(_ disk: ExternalDisk) {
        if let idx = disks.firstIndex(where: { $0.id == disk.id }) {
            disks[idx] = disk
        } else {
            disks.append(disk)
        }
    }

    private nonisolated func parseDiskInfo(_ info: [String: Any]) -> ExternalDisk? {
        guard let bsdName = info["DeviceIdentifier"] as? String else { return nil }
        let content = info["Content"] as? String ?? ""
        guard content != "nfs" && content != "autofs" else { return nil }
        let size = info["Size"] as? UInt64 ?? 0
        let volumeName = info["VolumeName"] as? String ?? "Untitled"
        let mountPoint = info["MountPoint"] as? String

        return ExternalDisk(
            id: bsdName,
            name: volumeName,
            fileSystem: content,
            size: size,
            mountPoint: mountPoint,
            status: content.lowercased().contains("ntfs") ? .readOnly : .detected,
            isRemovable: true,
            busProtocol: "USB"
        )
    }
}
