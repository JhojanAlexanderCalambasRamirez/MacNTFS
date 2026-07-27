import Foundation
import SwiftUI
import Combine

@MainActor
final class DiskViewModel: ObservableObject {
    @Published var selectedDisk: ExternalDisk?
    @Published var isMounting = false
    @Published var errorMessage: String?

    let diskService = DiskDetectionService()
    private let mountService = NTFSMountService.shared
    private var cancellable: AnyCancellable?
    private var watchdogTasks: [String: Task<Void, Never>] = [:]

    init() {
        cancellable = diskService.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
    }

    var ntfsDisks: [ExternalDisk] {
        diskService.disks.filter { $0.isNTFS }
    }

    var otherDisks: [ExternalDisk] {
        diskService.disks.filter { !$0.isNTFS }
    }

    func startMonitoring() {
        diskService.startMonitoring()
        // Start watchdog + power assertion for mounts restored from a previous session.
        // restoreExistingMounts() is async, so wait for it to settle before scanning.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self else { return }
            for disk in self.diskService.disks where disk.status == .mounted {
                await self.mountService.acquirePowerAssertion()
                self.startWatchdog(for: disk)
            }
        }
    }

    func stopMonitoring() {
        diskService.stopMonitoring()
    }

    func mountWithWriteSupport(_ disk: ExternalDisk) async {
        guard disk.isNTFS else {
            errorMessage = "Not an NTFS disk"
            return
        }

        isMounting = true
        errorMessage = nil
        diskService.mountingDisks.insert(disk.id)

        do {
            if let idx = diskService.disks.firstIndex(where: { $0.id == disk.id }) {
                diskService.disks[idx].status = .mounting
            }

            let mountPoint = try await mountService.mount(disk: disk)

            // Block DA from auto-mounting the NTFS partition while ntfs-3g holds it.
            // DA cycling forces fuse-t NFS loopback to drop open file handles → Error -43.
            diskService.claimDisk(disk.id)

            let mountedDisk = ExternalDisk(
                id: disk.id,
                name: disk.name,
                fileSystem: disk.fileSystem,
                size: disk.size,
                mountPoint: mountPoint,
                status: .mounted,
                isRemovable: disk.isRemovable,
                busProtocol: disk.busProtocol
            )
            if let idx = diskService.disks.firstIndex(where: { $0.id == disk.id }) {
                diskService.disks[idx] = mountedDisk
            } else {
                diskService.disks.append(mountedDisk)
            }
            startWatchdog(for: mountedDisk)
        } catch {
            errorMessage = error.localizedDescription
            if let idx = diskService.disks.firstIndex(where: { $0.id == disk.id }) {
                diskService.disks[idx].status = .error
            }
        }

        diskService.mountingDisks.remove(disk.id)
        isMounting = false
    }

    func unmountDisk(_ disk: ExternalDisk) async {
        guard let mountPoint = disk.mountPoint else { return }

        stopWatchdog(for: disk.id)
        do {
            // Release DA claim before unmounting so DA can re-detect the partition normally
            diskService.releaseDisk(disk.id)

            if let idx = diskService.disks.firstIndex(where: { $0.id == disk.id }) {
                diskService.disks[idx].status = .unmounting
            }

            try await mountService.unmount(mountPoint: mountPoint)

            if let idx = diskService.disks.firstIndex(where: { $0.id == disk.id }) {
                diskService.disks[idx].status = .detected
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func ejectDisk(_ disk: ExternalDisk) async {
        stopWatchdog(for: disk.id)
        isMounting = true
        errorMessage = nil
        diskService.releaseDisk(disk.id)

        if let idx = diskService.disks.firstIndex(where: { $0.id == disk.id }) {
            diskService.disks[idx].status = .ejecting
        }

        do {
            try await mountService.eject(disk: disk)
            diskService.disks.removeAll { $0.id == disk.id }
            if selectedDisk?.id == disk.id { selectedDisk = nil }
        } catch {
            errorMessage = error.localizedDescription
            if let idx = diskService.disks.firstIndex(where: { $0.id == disk.id }) {
                diskService.disks[idx].status = disk.status == .mounted ? .mounted : .detected
            }
        }

        isMounting = false
    }

    func formatDisk(_ disk: ExternalDisk, label: String, format: FormatType) async {
        isMounting = true
        errorMessage = nil
        diskService.releaseDisk(disk.id)

        if let idx = diskService.disks.firstIndex(where: { $0.id == disk.id }) {
            diskService.disks[idx].status = .mounting
        }

        do {
            try await mountService.format(disk: disk, label: label, format: format)
            diskService.disks.removeAll { $0.id == disk.id }
            if selectedDisk?.id == disk.id { selectedDisk = nil }
        } catch {
            errorMessage = error.localizedDescription
            if let idx = diskService.disks.firstIndex(where: { $0.id == disk.id }) {
                diskService.disks[idx].status = disk.status
            }
        }

        isMounting = false
    }

    // MARK: - Watchdog

    private func startWatchdog(for disk: ExternalDisk) {
        stopWatchdog(for: disk.id)
        let diskId = disk.id
        let devicePath = disk.devicePath
        let diskName = disk.name

        watchdogTasks[diskId] = Task.detached { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { break }

                let alive = await self?.checkNTFS3GAlive(devicePath: devicePath) ?? true
                if !alive {
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        guard let idx = self.diskService.disks.firstIndex(where: { $0.id == diskId }),
                              self.diskService.disks[idx].status == .mounted else { return }
                        let snapshot = self.diskService.disks[idx]
                        self.diskService.disks[idx].status = .error
                        if self.selectedDisk?.id == diskId {
                            self.selectedDisk = self.diskService.disks[idx]
                        }
                        self.errorMessage = "'\(diskName)' disconnected unexpectedly. Safely eject and reconnect."
                        _ = Task { await self.mountService.cleanupCrashedMount(disk: snapshot) }
                        NotificationService.sendDiskDisconnected(diskName)
                        LogService.shared.log(.error, "Watchdog: ntfs-3g died for \(diskName) — marked error")
                    }
                    break
                }
            }
            await MainActor.run { [weak self] in
                self?.watchdogTasks.removeValue(forKey: diskId)
            }
        }
    }

    private func stopWatchdog(for diskId: String) {
        watchdogTasks[diskId]?.cancel()
        watchdogTasks.removeValue(forKey: diskId)
    }

    private func checkNTFS3GAlive(devicePath: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
                process.arguments = ["-f", "ntfs-3g.*\(devicePath)"]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()
                try? process.run()
                process.waitUntilExit()
                let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                continuation.resume(returning: !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    func checkDependencies() -> Bool {
        let ntfs3gExists = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/ntfs-3g") ||
                           FileManager.default.fileExists(atPath: "/usr/local/bin/ntfs-3g")

        if !ntfs3gExists {
            errorMessage = "ntfs-3g not installed. Run: brew install ntfs-3g"
        }

        return ntfs3gExists
    }
}
