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

        do {
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

    func checkDependencies() -> Bool {
        let ntfs3gExists = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/ntfs-3g") ||
                           FileManager.default.fileExists(atPath: "/usr/local/bin/ntfs-3g")

        if !ntfs3gExists {
            errorMessage = "ntfs-3g not installed. Run: brew install ntfs-3g"
        }

        return ntfs3gExists
    }
}
