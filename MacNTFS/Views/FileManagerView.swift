import SwiftUI
import UniformTypeIdentifiers

struct FileManagerView: View {
    let rootPath: String
    @StateObject private var vm = FileOperationViewModel()
    @State private var selectedFile: String?
    @State private var showingRenameSheet = false
    @State private var newFileName = ""
    @State private var showingDeleteConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            // Breadcrumb bar
            HStack {
                Button(action: { Task { await vm.navigateUp() } }) {
                    Image(systemName: "chevron.left")
                }
                .disabled(vm.currentPath == rootPath)

                Text(vm.currentPath)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.head)

                Spacer()

                Text("\(vm.contents.count) items")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            // File list
            if vm.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(of: FileItem.self, selection: $selectedFile) {
                    TableColumn("Name") { item in
                        HStack(spacing: 6) {
                            Image(systemName: item.isDirectory ? "folder.fill" : fileIcon(item.name))
                                .foregroundColor(item.isDirectory ? .blue : .secondary)
                            Text(item.name)
                                .lineLimit(1)
                        }
                    }
                    .width(min: 200)

                    TableColumn("Size") { item in
                        Text(item.isDirectory ? "--" : ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file))
                            .foregroundColor(.secondary)
                    }
                    .width(80)

                    TableColumn("Modified") { item in
                        Text(item.modified, style: .date)
                            .foregroundColor(.secondary)
                    }
                    .width(100)
                } rows: {
                    ForEach(vm.contents.map { FileItem(name: $0.name, isDirectory: $0.isDirectory, size: $0.size, modified: $0.modified, path: (vm.currentPath as NSString).appendingPathComponent($0.name)) }) { item in
                        TableRow(item)
                            .contextMenu {
                                fileContextMenu(item)
                            }
                    }
                }
                .onDoubleClick(of: FileItem.self) { item in
                    if item.isDirectory {
                        Task { await vm.loadDirectory(item.path) }
                    }
                }
            }

            // Operations progress bar
            if !vm.operations.isEmpty {
                Divider()
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(vm.operations.suffix(5)) { op in
                            OperationBadge(operation: op)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
                .background(.bar)
            }

            if let error = vm.errorMessage {
                Divider()
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                    Spacer()
                    Button("Dismiss") { vm.errorMessage = nil }
                        .buttonStyle(.borderless)
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.1))
            }
        }
        .task { await vm.loadDirectory(rootPath) }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .sheet(isPresented: $showingRenameSheet) {
            RenameSheet(currentName: newFileName) { name in
                if let selected = selectedFile {
                    Task { await vm.renameFile(at: selected, newName: name) }
                }
            }
        }
        .confirmationDialog("Delete this file?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let selected = selectedFile {
                    Task { await vm.deleteFile(at: selected) }
                }
            }
        }
    }

    @ViewBuilder
    private func fileContextMenu(_ item: FileItem) -> some View {
        Button("Open in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
        }
        Divider()
        Button("Rename...") {
            selectedFile = item.path
            newFileName = item.name
            showingRenameSheet = true
        }
        Button("Delete", role: .destructive) {
            selectedFile = item.path
            showingDeleteConfirm = true
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let currentPath = vm.currentPath
        let viewModel = vm
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data = data as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                let dest = (currentPath as NSString).appendingPathComponent(url.lastPathComponent)
                Task { @MainActor in
                    await viewModel.copyFile(from: url.path, to: dest)
                }
            }
        }
        return true
    }

    private func fileIcon(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.fill"
        case "jpg", "jpeg", "png", "gif", "heic": return "photo"
        case "mp4", "mov", "avi", "mkv": return "film"
        case "mp3", "wav", "aac", "flac": return "music.note"
        case "zip", "rar", "7z", "tar": return "doc.zipper"
        case "txt", "md", "rtf": return "doc.text"
        case "doc", "docx": return "doc.richtext"
        case "xls", "xlsx": return "tablecells"
        default: return "doc"
        }
    }
}

struct FileItem: Identifiable {
    let name: String
    let isDirectory: Bool
    let size: UInt64
    let modified: Date
    let path: String
    var id: String { path }
}

extension Table where Value == FileItem {
    func onDoubleClick(of type: Value.Type, perform action: @escaping (Value) -> Void) -> some View {
        self
    }
}

struct OperationBadge: View {
    let operation: FileOperation

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: operation.isComplete ? "checkmark.circle.fill" : "arrow.right.circle")
                .foregroundColor(operation.error != nil ? .red : operation.isComplete ? .green : .blue)
                .font(.caption)

            Text(operation.type.rawValue)
                .font(.caption2)

            if !operation.isComplete && operation.error == nil {
                ProgressView(value: operation.progress)
                    .frame(width: 40)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(4)
    }
}

struct RenameSheet: View {
    @State var currentName: String
    let onRename: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Rename")
                .font(.headline)

            TextField("New name", text: $currentName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename") {
                    onRename(currentName)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(currentName.isEmpty)
            }
        }
        .padding()
        .frame(width: 300)
    }
}
