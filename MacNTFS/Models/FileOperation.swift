import Foundation

enum FileOperationType: String, Sendable {
    case copy = "Copy"
    case move = "Move"
    case rename = "Rename"
    case delete = "Delete"
}

struct FileOperation: Identifiable, Sendable {
    let id = UUID()
    let type: FileOperationType
    let sourcePath: String
    let destinationPath: String?
    let fileSize: UInt64
    var progress: Double = 0.0  // 0.0 - 1.0
    var isComplete: Bool = false
    var error: String?
    let startedAt: Date = Date()

    var statusText: String {
        if let error { return "Error: \(error)" }
        if isComplete { return "Complete" }
        return "\(Int(progress * 100))%"
    }
}

struct LogEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let message: String

    enum LogLevel: String, Sendable {
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
        case debug = "DEBUG"
    }
}
