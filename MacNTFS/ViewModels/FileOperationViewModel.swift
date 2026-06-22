import Foundation

@MainActor
final class FileOperationViewModel: ObservableObject {
    @Published var currentPath: String = ""
    @Published var contents: [(name: String, isDirectory: Bool, size: UInt64, modified: Date)] = []
    @Published var operations: [FileOperation] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let fileService = FileOperationService.shared

    func loadDirectory(_ path: String) async {
        isLoading = true
        errorMessage = nil

        do {
            contents = try await fileService.listContents(at: path)
            currentPath = path
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func copyFile(from source: String, to destination: String) async {
        let attrs = try? FileManager.default.attributesOfItem(atPath: source)
        let size = attrs?[.size] as? UInt64 ?? 0

        let op = FileOperation(type: .copy, sourcePath: source, destinationPath: destination, fileSize: size)
        operations.append(op)
        let opIndex = operations.count - 1

        do {
            try await fileService.copyFile(from: source, to: destination) { [weak self] progress in
                Task { @MainActor in
                    self?.operations[opIndex].progress = progress
                }
            }
            operations[opIndex].isComplete = true
            operations[opIndex].progress = 1.0
            await loadDirectory(currentPath)
        } catch {
            operations[opIndex].error = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }

    func moveFile(from source: String, to destination: String) async {
        let attrs = try? FileManager.default.attributesOfItem(atPath: source)
        let size = attrs?[.size] as? UInt64 ?? 0

        let op = FileOperation(type: .move, sourcePath: source, destinationPath: destination, fileSize: size)
        operations.append(op)
        let opIndex = operations.count - 1

        do {
            try await fileService.moveFile(from: source, to: destination)
            operations[opIndex].isComplete = true
            operations[opIndex].progress = 1.0
            await loadDirectory(currentPath)
        } catch {
            operations[opIndex].error = error.localizedDescription
        }
    }

    func renameFile(at path: String, newName: String) async {
        do {
            try await fileService.renameFile(at: path, newName: newName)
            await loadDirectory(currentPath)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteFile(at path: String) async {
        do {
            try await fileService.deleteFile(at: path)
            await loadDirectory(currentPath)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func navigateUp() async {
        let parent = (currentPath as NSString).deletingLastPathComponent
        if !parent.isEmpty {
            await loadDirectory(parent)
        }
    }
}
