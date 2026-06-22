import Foundation

@objc protocol HelperProtocol {
    func mountNTFS(device: String, mountPoint: String, volumeName: String, reply: @escaping @Sendable (Bool, String?) -> Void)
    func unmountVolume(mountPoint: String, reply: @escaping @Sendable (Bool, String?) -> Void)
    func checkNTFS3G(reply: @escaping @Sendable (Bool, String?) -> Void)
}
