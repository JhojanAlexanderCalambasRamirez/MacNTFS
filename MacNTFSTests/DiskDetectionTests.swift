import XCTest
@testable import MacNTFS

final class DiskDetectionTests: XCTestCase {

    func testExternalDiskIsNTFS() {
        let disk = ExternalDisk(
            id: "disk4s1",
            name: "MyDrive",
            fileSystem: "ntfs",
            size: 500_000_000_000,
            mountPoint: nil,
            status: .readOnly,
            isRemovable: true,
            busProtocol: "USB"
        )
        XCTAssertTrue(disk.isNTFS)
        XCTAssertEqual(disk.devicePath, "/dev/disk4s1")
    }

    func testExternalDiskNotNTFS() {
        let disk = ExternalDisk(
            id: "disk3s1",
            name: "Backup",
            fileSystem: "exfat",
            size: 256_000_000_000,
            mountPoint: "/Volumes/Backup",
            status: .detected,
            isRemovable: true,
            busProtocol: "USB"
        )
        XCTAssertFalse(disk.isNTFS)
    }

    func testWindowsNTFSVariant() {
        let disk = ExternalDisk(
            id: "disk5s1",
            name: "WinDisk",
            fileSystem: "Windows_NTFS",
            size: 1_000_000_000_000,
            mountPoint: nil,
            status: .readOnly,
            isRemovable: true,
            busProtocol: "USB"
        )
        XCTAssertTrue(disk.isNTFS)
    }

    func testSizeFormatted() {
        let disk = ExternalDisk(
            id: "disk4s1",
            name: "Test",
            fileSystem: "ntfs",
            size: 500_000_000_000,
            mountPoint: nil,
            status: .detected,
            isRemovable: true,
            busProtocol: "USB"
        )
        XCTAssertFalse(disk.sizeFormatted.isEmpty)
    }
}
