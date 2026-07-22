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

        // nil match: catch ALL disks including unmounted NTFS partitions.
        // kDADiskDescriptionVolumeMountableKey:true would miss NTFS on macOS 26 (no built-in NTFS driver).
        DARegisterDiskAppearedCallback(session, nil, appearedCallback, selfPtr)
        DARegisterDiskDisappearedCallback(session, nil, disappearedCallback, selfPtr)
        DARegisterDiskMountApprovalCallback(session, nil, mountApproval, selfPtr)
        DASessionSetDispatchQueue(session, queue)

        LogService.shared.log(.info, "Disk monitoring started")
        scanExistingDisks()
        restoreExistingMounts()
    }

    // Detect ntfs-3g processes already running from a previous session.
    // Without this, restarting the app while a disk is mounted shows it as .readOnly
    // and DA cycling isn't blocked, causing Error -43 stale file handles.
    private func restoreExistingMounts() {
        Task.detached { [weak self] in
            guard let self else { return }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", "ps aux | grep -v grep | grep ntfs-3g"]
            let pipe = Pipe()
            process.standardOutput = pipe
            try? process.run()
            process.waitUntilExit()

            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }

            for line in lines {
                // ps line: user pid cpu mem ... /path/to/ntfs-3g /dev/diskXsY /Volumes/NAME -o ...
                let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                guard let ntfsIdx = parts.firstIndex(where: { $0.hasSuffix("ntfs-3g") }),
                      ntfsIdx + 2 < parts.count else { continue }

                let devicePath = parts[ntfsIdx + 1]
                let mountPoint = parts[ntfsIdx + 2]

                guard devicePath.hasPrefix("/dev/"), mountPoint.hasPrefix("/Volumes/") else { continue }

                let bsdName = String(devicePath.dropFirst("/dev/".count))
                let volumeName = String(mountPoint.dropFirst("/Volumes/".count))

                await MainActor.run {
                    let existingSize = self.disks.first(where: { $0.id == bsdName })?.size ?? 0
                    let restored = ExternalDisk(
                        id: bsdName,
                        name: volumeName,
                        fileSystem: "ntfs",
                        size: existingSize,
                        mountPoint: mountPoint,
                        status: .mounted,
                        isRemovable: true,
                        busProtocol: "USB"
                    )
                    self.addOrUpdateDisk(restored)
                    self.claimDisk(bsdName)
                    LogService.shared.log(.info, "Restored existing mount: \(volumeName) (\(bsdName)) at \(mountPoint)")
                }
            }
        }
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

        // Skip internal disks (main SSD, APFS containers, Recovery, Preboot, etc.)
        let isInternal = desc[kDADiskDescriptionDeviceInternalKey as String] as? Bool ?? false
        guard !isInternal else { return }

        // Skip whole-disk entries that have sub-partitions (disk5, not disk5s1).
        // DA fires appeared for both; without this filter, disk5 + disk5s1 both appear
        // in the list as two separate entries for the same physical drive.
        let isLeaf = desc[kDADiskDescriptionMediaLeafKey as String] as? Bool ?? true
        guard isLeaf else { return }

        let bsdName = desc[kDADiskDescriptionMediaBSDNameKey as String] as? String ?? "unknown"
        let volumeName = desc[kDADiskDescriptionVolumeNameKey as String] as? String ?? ""
        let fsType = desc[kDADiskDescriptionVolumeKindKey as String] as? String ?? ""
        // Partition content type — present even for unmounted partitions (e.g. "Windows_NTFS")
        let mediaContent = desc[kDADiskDescriptionMediaContentKey as String] as? String ?? ""
        let mediaSize = desc[kDADiskDescriptionMediaSizeKey as String] as? UInt64 ?? 0
        let removable = desc[kDADiskDescriptionMediaRemovableKey as String] as? Bool ?? false
        let protocol_ = desc[kDADiskDescriptionDeviceProtocolKey as String] as? String ?? ""
        let mountURL = desc[kDADiskDescriptionVolumePathKey as String] as? URL

        // Skip fuse-t NFS loopback mounts — not real external disks
        guard fsType != "nfs" && fsType != "autofs" else { return }

        // Skip virtual/container disks (no BSD name, or media content is a partition scheme)
        guard bsdName != "unknown",
              mediaContent != "GUID_partition_scheme",
              mediaContent != "FDisk_partition_scheme" else { return }

        // Resolve file system: use volume kind if mounted, fall back to media content for unmounted partitions
        let resolvedFs = fsType.isEmpty ? mediaContent : fsType
        let isNTFS = resolvedFs.lowercased().contains("ntfs") || mediaContent.lowercased().contains("ntfs")
        // Use BSD name as fallback display name for unmounted partitions with no volume label
        let displayName = volumeName.isEmpty ? bsdName : volumeName

        let busProtocol: String
        switch protocol_.lowercased() {
        case let p where p.contains("usb"): busProtocol = "USB"
        case let p where p.contains("thunderbolt"): busProtocol = "Thunderbolt"
        case let p where p.contains("firewire"): busProtocol = "FireWire"
        default: busProtocol = protocol_.isEmpty ? "USB" : protocol_
        }

        let disk = ExternalDisk(
            id: bsdName,
            name: displayName,
            fileSystem: resolvedFs,
            size: mediaSize,
            mountPoint: mountURL?.path,
            status: isNTFS ? .readOnly : .detected,
            isRemovable: removable,
            busProtocol: busProtocol
        )

        Task { @MainActor in
            // Don't reset state for a mounted or in-flight disk
            let alreadyMounted = self.disks.contains(where: {
                ($0.id == disk.id || $0.name == disk.name) &&
                ($0.status == .mounted || $0.status == .ejecting)
            })
            if alreadyMounted { return }
            self.addOrUpdateDisk(disk)
            LogService.shared.log(.info, "Disk appeared: \(disk.name) (\(resolvedFs.isEmpty ? "unknown" : resolvedFs)) — \(disk.sizeFormatted)")
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
        guard content != "nfs" && content != "autofs",
              content != "GUID_partition_scheme",
              content != "FDisk_partition_scheme" else { return nil }
        let size = info["Size"] as? UInt64 ?? 0
        // VolumeName may be absent for unmounted partitions — use BSD name as fallback
        let rawName = info["VolumeName"] as? String ?? ""
        let volumeName = rawName.isEmpty ? bsdName : rawName
        let mountPoint = info["MountPoint"] as? String
        let isNTFS = content.lowercased().contains("ntfs")

        return ExternalDisk(
            id: bsdName,
            name: volumeName,
            fileSystem: content,
            size: size,
            mountPoint: mountPoint,
            status: isNTFS ? .readOnly : .detected,
            isRemovable: true,
            busProtocol: "USB"
        )
    }
}
