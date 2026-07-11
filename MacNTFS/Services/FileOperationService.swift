import Foundation

actor FileOperationService {
    static let shared = FileOperationService()

    func copyFile(from source: String, to destination: String, progress: @Sendable @escaping (Double) -> Void) async throws {
        let sourceURL = URL(fileURLWithPath: source)
        let destURL = URL(fileURLWithPath: destination)

        guard FileManager.default.fileExists(atPath: source) else {
            throw NTFSError.operationFailed("Source not found: \(source)")
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: source)
        let totalSize = attrs[.size] as? UInt64 ?? 0

        if totalSize > 100_000_000 {
            try await chunkedCopy(from: sourceURL, to: destURL, totalSize: totalSize, progress: progress)
        } else {
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            progress(1.0)
        }

        try verifyIntegrity(source: source, destination: destination)
        LogService.shared.log(.info, "Copied: \(sourceURL.lastPathComponent)")
    }

    func moveFile(from source: String, to destination: String) async throws {
        let sourceURL = URL(fileURLWithPath: source)
        let destURL = URL(fileURLWithPath: destination)

        try FileManager.default.moveItem(at: sourceURL, to: destURL)
        LogService.shared.log(.info, "Moved: \(sourceURL.lastPathComponent) → \(destURL.lastPathComponent)")
    }

    func renameFile(at path: String, newName: String) async throws {
        let url = URL(fileURLWithPath: path)
        let newURL = url.deletingLastPathComponent().appendingPathComponent(newName)

        guard !FileManager.default.fileExists(atPath: newURL.path) else {
            throw NTFSError.operationFailed("File already exists: \(newName)")
        }

        try FileManager.default.moveItem(at: url, to: newURL)
        LogService.shared.log(.info, "Renamed: \(url.lastPathComponent) → \(newName)")
    }

    func deleteFile(at path: String) async throws {
        // Use /bin/rm via Process() instead of FileManager.removeItem.
        // FileManager calls on NFS (fuse-t loopback) can hang indefinitely
        // when the mount is in a transient state. Process() runs in a separate
        // thread and can be terminated after a timeout.
        let (code, output) = try await runWithTimeout(
            executable: "/bin/rm",
            arguments: ["-rf", path],
            timeoutSeconds: 15
        )
        if code != 0 {
            throw NTFSError.operationFailed(output.isEmpty ? "rm exited \(code)" : output)
        }
        LogService.shared.log(.info, "Deleted: \(URL(fileURLWithPath: path).lastPathComponent)")
    }

    private func runWithTimeout(executable: String, arguments: [String], timeoutSeconds: Double) async throws -> (Int32, String) {
        return try await withThrowingTaskGroup(of: (Int32, String).self) { group in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            group.addTask {
                return try await withCheckedThrowingContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            try process.run()
                            process.waitUntilExit()
                            let data = pipe.fileHandleForReading.readDataToEndOfFile()
                            let out = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                            continuation.resume(returning: (process.terminationStatus, out))
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                process.terminate()
                throw NTFSError.operationFailed("Operation timed out (\(Int(timeoutSeconds))s) — drive may be unresponsive")
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    func listContents(at path: String) throws -> [(name: String, isDirectory: Bool, size: UInt64, modified: Date)] {
        let contents = try FileManager.default.contentsOfDirectory(atPath: path)
        return contents.compactMap { name in
            let fullPath = (path as NSString).appendingPathComponent(name)
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: fullPath) else { return nil }
            let isDir = (attrs[.type] as? FileAttributeType) == .typeDirectory
            let size = attrs[.size] as? UInt64 ?? 0
            let modified = attrs[.modificationDate] as? Date ?? Date()
            return (name: name, isDirectory: isDir, size: size, modified: modified)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Private

    private func chunkedCopy(from source: URL, to dest: URL, totalSize: UInt64, progress: @Sendable @escaping (Double) -> Void) async throws {
        let chunkSize = 4 * 1024 * 1024 // 4MB

        guard let input = InputStream(url: source) else {
            throw NTFSError.operationFailed("Cannot open source for reading")
        }
        guard let output = OutputStream(url: dest, append: false) else {
            throw NTFSError.operationFailed("Cannot open destination for writing")
        }

        input.open()
        output.open()
        defer {
            input.close()
            output.close()
        }

        var buffer = [UInt8](repeating: 0, count: chunkSize)
        var totalWritten: UInt64 = 0

        while input.hasBytesAvailable {
            let bytesRead = input.read(&buffer, maxLength: chunkSize)
            if bytesRead < 0 {
                throw NTFSError.operationFailed("Read error: \(input.streamError?.localizedDescription ?? "unknown")")
            }
            if bytesRead == 0 { break }

            var bytesRemaining = bytesRead
            var writeOffset = 0
            while bytesRemaining > 0 {
                let written = buffer.withUnsafeBufferPointer { bufferPtr in
                    output.write(bufferPtr.baseAddress! + writeOffset, maxLength: bytesRemaining)
                }
                if written < 0 {
                    throw NTFSError.operationFailed("Write error: \(output.streamError?.localizedDescription ?? "unknown")")
                }
                bytesRemaining -= written
                writeOffset += written
            }

            totalWritten += UInt64(bytesRead)
            progress(Double(totalWritten) / Double(totalSize))
        }
    }

    private func verifyIntegrity(source: String, destination: String) throws {
        let sourceAttrs = try FileManager.default.attributesOfItem(atPath: source)
        let destAttrs = try FileManager.default.attributesOfItem(atPath: destination)

        let sourceSize = sourceAttrs[.size] as? UInt64 ?? 0
        let destSize = destAttrs[.size] as? UInt64 ?? 0

        guard sourceSize == destSize else {
            try? FileManager.default.removeItem(atPath: destination)
            throw NTFSError.operationFailed("Size mismatch after copy: \(sourceSize) vs \(destSize)")
        }
    }
}
