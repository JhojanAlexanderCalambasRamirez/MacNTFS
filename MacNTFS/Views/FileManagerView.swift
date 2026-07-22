import SwiftUI
import UniformTypeIdentifiers

struct FileManagerView: View {
    let rootPath: String
    @EnvironmentObject var loc: LocalizationManager
    @StateObject private var vm = FileOperationViewModel()
    @State private var selectedFile: String?
    @State private var showingRenameSheet = false
    @State private var newFileName = ""
    @State private var showingDeleteConfirm = false
    @State private var searchText = ""

    private var filteredContents: [(name: String, isDirectory: Bool, size: UInt64, modified: Date)] {
        if searchText.isEmpty { return vm.contents }
        return vm.contents.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Navigation bar
            HStack(spacing: 8) {
                Button { Task { await vm.navigateUp() } } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.borderless)
                .disabled(vm.currentPath == rootPath)

                // Breadcrumb
                BreadcrumbView(fullPath: vm.currentPath, rootPath: rootPath) { path in
                    Task { await vm.loadDirectory(path) }
                }

                Spacer()

                // Search
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    TextField(loc.language == .spanish ? "Buscar..." : "Search...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(6)
                .frame(width: 180)

                Text("\(filteredContents.count) \(loc.t("items"))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: vm.currentPath))
                } label: {
                    Image(systemName: "folder.badge.person.crop")
                }
                .buttonStyle(.borderless)
                .help(loc.t("open.finder"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            // File list
            if vm.isLoading {
                VStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if filteredContents.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: searchText.isEmpty ? "folder" : "magnifyingglass")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text(searchText.isEmpty
                         ? (loc.language == .spanish ? "Carpeta vacía" : "Empty folder")
                         : (loc.language == .spanish ? "Sin resultados" : "No results"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(selection: $selectedFile) {
                    ForEach(filteredContents.map { FileItem(name: $0.name, isDirectory: $0.isDirectory, size: $0.size, modified: $0.modified, path: (vm.currentPath as NSString).appendingPathComponent($0.name)) }) { item in
                        FileRowView(item: item)
                            .tag(item.path)
                            .contextMenu { fileContextMenu(item) }
                            .onTapGesture(count: 2) {
                                if item.isDirectory {
                                    Task { await vm.loadDirectory(item.path) }
                                }
                            }
                    }
                }
            }

            // Operations progress
            if !vm.operations.isEmpty {
                Divider()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(vm.operations.suffix(5)) { op in
                            OperationBadge(operation: op)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .background(.bar)
            }

            if let error = vm.errorMessage {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 12))
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                    Spacer()
                    Button {
                        vm.errorMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.red.opacity(0.06))
            }
        }
        .task { await vm.loadDirectory(rootPath) }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .sheet(isPresented: $showingRenameSheet) {
            RenameSheet(currentName: newFileName, loc: loc) { name in
                if let selected = selectedFile {
                    Task { await vm.renameFile(at: selected, newName: name) }
                }
            }
        }
        .confirmationDialog(
            loc.language == .spanish ? "¿Eliminar este archivo?" : "Delete this file?",
            isPresented: $showingDeleteConfirm
        ) {
            Button(loc.t("delete"), role: .destructive) {
                if let selected = selectedFile {
                    Task { await vm.deleteFile(at: selected) }
                }
            }
        }
    }

    @ViewBuilder
    private func fileContextMenu(_ item: FileItem) -> some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
        } label: {
            Label(loc.t("open.finder"), systemImage: "folder.badge.person.crop")
        }
        Divider()
        Button {
            selectedFile = item.path
            newFileName = item.name
            showingRenameSheet = true
        } label: {
            Label(loc.t("rename"), systemImage: "pencil")
        }
        Button(role: .destructive) {
            selectedFile = item.path
            showingDeleteConfirm = true
        } label: {
            Label(loc.t("delete"), systemImage: "trash")
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
}

// MARK: - Breadcrumb

struct BreadcrumbView: View {
    let fullPath: String
    let rootPath: String
    let onNavigate: (String) -> Void

    private var segments: [(name: String, path: String)] {
        guard fullPath.hasPrefix(rootPath) else { return [] }
        let relative = String(fullPath.dropFirst(rootPath.count))
        let parts = relative.split(separator: "/").map(String.init)

        var result: [(String, String)] = [("Root", rootPath)]
        var current = rootPath
        for part in parts {
            current = (current as NSString).appendingPathComponent(part)
            result.append((part, current))
        }
        return result
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary.opacity(0.5))
                }

                Button(segment.name) {
                    onNavigate(segment.path)
                }
                .buttonStyle(.borderless)
                .font(.system(size: 12, weight: index == segments.count - 1 ? .semibold : .regular))
                .foregroundColor(index == segments.count - 1 ? .primary : .secondary)
                .lineLimit(1)
            }
        }
    }
}

// MARK: - File Row

struct FileRowView: View {
    let item: FileItem

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(item.isDirectory ? Color.blue.opacity(0.1) : Color.secondary.opacity(0.06))
                    .frame(width: 28, height: 28)

                Image(systemName: item.isDirectory ? "folder.fill" : fileIcon(item.name))
                    .font(.system(size: 14))
                    .foregroundColor(item.isDirectory ? .blue : .secondary)
            }

            Text(item.name)
                .font(.system(size: 13))
                .lineLimit(1)

            Spacer()

            Text(item.isDirectory ? "--" : ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file))
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)

            Text(item.modified, style: .date)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    private func fileIcon(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf": return "doc.fill"
        case "jpg", "jpeg", "png", "gif", "heic", "webp": return "photo"
        case "mp4", "mov", "avi", "mkv": return "film"
        case "mp3", "wav", "aac", "flac", "m4a": return "waveform"
        case "zip", "rar", "7z", "tar", "gz": return "doc.zipper"
        case "txt", "md", "rtf", "csv": return "doc.text"
        case "doc", "docx", "pages": return "doc.richtext"
        case "xls", "xlsx", "numbers": return "tablecells"
        case "ppt", "pptx", "key": return "rectangle.stack"
        case "swift", "py", "js", "ts", "html", "css", "json": return "curlybraces"
        case "dmg", "iso", "img": return "opticaldisc"
        case "app": return "app"
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

// MARK: - Operation Badge

struct OperationBadge: View {
    let operation: FileOperation

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: operation.error != nil ? "xmark.circle.fill" : operation.isComplete ? "checkmark.circle.fill" : "arrow.right.circle")
                .foregroundColor(operation.error != nil ? .red : operation.isComplete ? .green : .blue)
                .font(.system(size: 11))

            Text(operation.type.rawValue)
                .font(.system(size: 10))

            if !operation.isComplete && operation.error == nil {
                ProgressView(value: operation.progress)
                    .frame(width: 40)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(4)
    }
}

// MARK: - Rename Sheet

struct RenameSheet: View {
    @State var currentName: String
    let loc: LocalizationManager
    let onRename: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text(loc.t("rename"))
                .font(.headline)

            TextField(loc.t("new.name"), text: $currentName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button(loc.t("cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(loc.t("rename")) {
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
