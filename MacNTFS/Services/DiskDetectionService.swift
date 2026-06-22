import Foundation
import DiskArbitration

@MainActor
final class DiskDetectionService: ObservableObject {
    @Published var disks: [ExternalDisk] = []

    private var session: DASession?
    private let queue = DispatchQueue(label: "com.macntfs.diskdetection")

    func startMonitoring() {
        guard let session = DASessionCreate(kCFAllocatorDefault) else {
            LogService.shared.log(.error, "Failed to create DiskArbitration session")
            return
        }
        self.session = session

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

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let match: CFDictionary = [
            kDADiskDescriptionVolumeMountableKey: true,
            kDADiskDescriptionMediaRemovableKey: true,
        ] as NSDictionary

        DARegisterDiskAppearedCallback(session, match, appearedCallback, selfPtr)
        DARegisterDiskDisappearedCallback(session, match, disappearedCallback, selfPtr)
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
                            if let disk = parseDiskInfo(partition) {
                                Task { @MainActor in
                                    self.addOrUpdateDisk(disk)
                                }
                            }
                        }
                    }
                }
            }
        } catch {
            LogService.shared.log(.error, "Failed to scan disks: \(error.localizedDescription)")
        }
    }

    private nonisolated func handleDiskAppeared(_ daDisk: DADisk) {
        guard let desc = DADiskCopyDescription(daDisk) as? [String: Any] else { return }

        let bsdName = desc[kDADiskDescriptionMediaBSDNameKey as String] as? String ?? "unknown"
        let volumeName = desc[kDADiskDescriptionVolumeNameKey as String] as? String ?? "Untitled"
        let fsType = desc[kDADiskDescriptionVolumeKindKey as String] as? String ?? "unknown"
        let mediaSize = desc[kDADiskDescriptionMediaSizeKey as String] as? UInt64 ?? 0
        let removable = desc[kDADiskDescriptionMediaRemovableKey as String] as? Bool ?? false
        let bus = desc[kDADiskDescriptionBusPathKey as String] as? String ?? ""
        let mountURL = desc[kDADiskDescriptionVolumeMountableKey as String] as? URL

        let disk = ExternalDisk(
            id: bsdName,
            name: volumeName,
            fileSystem: fsType,
            size: mediaSize,
            mountPoint: mountURL?.path,
            status: fsType.lowercased().contains("ntfs") ? .readOnly : .detected,
            isRemovable: removable,
            busProtocol: bus.contains("USB") ? "USB" : "Thunderbolt"
        )

        Task { @MainActor in
            self.addOrUpdateDisk(disk)
            LogService.shared.log(.info, "Disk appeared: \(disk.name) (\(disk.fileSystem)) — \(disk.sizeFormatted)")
        }
    }

    private nonisolated func handleDiskDisappeared(_ daDisk: DADisk) {
        guard let desc = DADiskCopyDescription(daDisk) as? [String: Any],
              let bsdName = desc[kDADiskDescriptionMediaBSDNameKey as String] as? String else { return }

        Task { @MainActor in
            self.disks.removeAll { $0.id == bsdName }
            LogService.shared.log(.info, "Disk removed: \(bsdName)")
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
