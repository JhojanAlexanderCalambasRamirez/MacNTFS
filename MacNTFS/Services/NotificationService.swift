import Foundation
import UserNotifications

enum NotificationService {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func sendDiskConnected(_ disk: ExternalDisk) {
        let content = UNMutableNotificationContent()
        content.title = "MacNTFS"
        content.body = disk.isNTFS
            ? "\(disk.name) (\(disk.sizeFormatted)) — NTFS detected. Ready to mount R/W."
            : "\(disk.name) (\(disk.sizeFormatted)) connected."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "disk-\(disk.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    static func sendDiskDisconnected(_ name: String) {
        let content = UNMutableNotificationContent()
        content.title = "MacNTFS"
        content.body = "\(name) disconnected."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "disk-removed-\(name)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
