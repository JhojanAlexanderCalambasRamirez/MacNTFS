import Foundation

enum ShellExecutor {
    struct Result: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String
        var success: Bool { exitCode == 0 }
    }

    static func run(_ command: String, arguments: [String] = [], timeout: TimeInterval = 30) async throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                process.waitUntilExit()
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                continuation.resume(returning: Result(
                    exitCode: process.terminationStatus,
                    stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                    stderr: String(data: stderrData, encoding: .utf8) ?? ""
                ))
            }
        }
    }

    static func diskutil(_ args: String...) async throws -> Result {
        try await run("/usr/sbin/diskutil", arguments: Array(args))
    }
}
