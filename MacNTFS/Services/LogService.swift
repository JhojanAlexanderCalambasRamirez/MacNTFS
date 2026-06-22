import Foundation

final class LogService: ObservableObject, @unchecked Sendable {
    static let shared = LogService()

    @MainActor @Published var entries: [LogEntry] = []

    private let maxEntries = 500

    func log(_ level: LogEntry.LogLevel, _ message: String) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message)

        Task { @MainActor in
            self.entries.append(entry)
            if self.entries.count > self.maxEntries {
                self.entries.removeFirst(self.entries.count - self.maxEntries)
            }
        }

        #if DEBUG
        let ts = ISO8601DateFormatter().string(from: entry.timestamp)
        print("[\(ts)] [\(level.rawValue)] \(message)")
        #endif
    }

    @MainActor
    func clear() {
        entries.removeAll()
    }
}
