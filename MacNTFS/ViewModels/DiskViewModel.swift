import Foundation
import SwiftUI

@MainActor
final class DiskViewModel: ObservableObject {
    @Published var selectedDisk: ExternalDisk?
    @Published var isMounting = false
    @Published var errorMessage: String?

    let diskService = DiskDetectionService()
    private let mountService = NTFSMountService.shared

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

        do {
            if let idx = diskService.disks.firstIndex(where: { $0.id == disk.id }) {
                diskService.disks[idx].status = .mounting
            }

            let mountPoint = try await mountService.mount(disk: disk)

            if let idx = diskService.disks.firstIndex(where: { $0.id == disk.id }) {
                diskService.disks[idx] = ExternalDisk(
                    id: disk.id,
                    name: disk.name,
                    fileSystem: disk.fileSystem,
                    size: disk.size,
                    mountPoint: mountPoint,
                    status: .mounted,
                    isRemovable: disk.isRemovable,
                    busProtocol: disk.busProtocol
                )
            }
        } catch {
            errorMessage = error.localizedDescription
            if let idx = diskService.disks.firstIndex(where: { $0.id == disk.id }) {
                diskService.disks[idx].status = .error
            }
        }

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
