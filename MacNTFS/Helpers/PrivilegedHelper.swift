import Foundation
import ServiceManagement

@MainActor
final class PrivilegedHelper {
    static let shared = PrivilegedHelper()

    private let helperID = "com.macntfs.helper"
    private var connection: NSXPCConnection?

    func installHelper() throws {
        let service = SMAppService.daemon(plistName: "\(helperID).plist")
        try service.register()
    }

    func connectToHelper() -> (any HelperProtocol)? {
        if connection == nil {
            connection = NSXPCConnection(machServiceName: helperID, options: .privileged)
            connection?.remoteObjectInterface = NSXPCInterface(with: HelperProtocol.self)
            connection?.invalidationHandler = { [weak self] in
                Task { @MainActor in
                    self?.connection = nil
                }
            }
            connection?.resume()
        }

        return connection?.remoteObjectProxyWithErrorHandler { error in
            LogService.shared.log(.error, "XPC error: \(error.localizedDescription)")
        } as? any HelperProtocol
    }

    func mountNTFS(device: String, mountPoint: String, volumeName: String) async throws -> String {
        guard let helper = connectToHelper() else {
            throw NTFSError.operationFailed("Cannot connect to helper")
        }

        return try await withCheckedThrowingContinuation { continuation in
            helper.mountNTFS(device: device, mountPoint: mountPoint, volumeName: volumeName) { success, result in
                if success, let mp = result {
                    continuation.resume(returning: mp)
                } else {
                    continuation.resume(throwing: NTFSError.mountFailed(result ?? "Unknown error"))
                }
            }
        }
    }

    func unmount(mountPoint: String) async throws {
        guard let helper = connectToHelper() else {
            throw NTFSError.operationFailed("Cannot connect to helper")
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            helper.unmountVolume(mountPoint: mountPoint) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: NTFSError.unmountFailed(error ?? mountPoint))
                }
            }
        }
    }
}
