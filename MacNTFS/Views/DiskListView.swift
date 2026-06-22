import SwiftUI

struct DiskListView: View {
    @EnvironmentObject var diskVM: DiskViewModel

    var body: some View {
        List(selection: $diskVM.selectedDisk) {
            if !diskVM.ntfsDisks.isEmpty {
                Section("NTFS Drives") {
                    ForEach(diskVM.ntfsDisks) { disk in
                        DiskRowView(disk: disk)
                            .tag(disk)
                            .contextMenu {
                                diskContextMenu(disk)
                            }
                    }
                }
            }

            if !diskVM.otherDisks.isEmpty {
                Section("Other Drives") {
                    ForEach(diskVM.otherDisks) { disk in
                        DiskRowView(disk: disk)
                            .tag(disk)
                    }
                }
            }

            if diskVM.diskService.disks.isEmpty {
                ContentUnavailableView {
                    Label("No External Drives", systemImage: "externaldrive")
                } description: {
                    Text("Connect a USB drive to get started")
                }
            }
        }
        .navigationTitle("Drives")
    }

    @ViewBuilder
    private func diskContextMenu(_ disk: ExternalDisk) -> some View {
        if disk.isNTFS && disk.status != .mounted {
            Button("Mount R/W") {
                Task { await diskVM.mountWithWriteSupport(disk) }
            }
        }
        if disk.status == .mounted {
            Button("Unmount") {
                Task { await diskVM.unmountDisk(disk) }
            }
            Divider()
            Button("Open in Finder") {
                if let mp = disk.mountPoint {
                    NSWorkspace.shared.open(URL(fileURLWithPath: mp))
                }
            }
        }
    }
}

struct DiskRowView: View {
    let disk: ExternalDisk

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.title2)
                .foregroundColor(iconColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(disk.name)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(disk.fileSystem.uppercased())
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(disk.isNTFS ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                        .cornerRadius(3)

                    Text(disk.sizeFormatted)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(disk.status.rawValue)
                    .font(.caption2)
                    .foregroundColor(statusColor)
            }

            Spacer()

            if disk.status == .mounting || disk.status == .unmounting {
                ProgressView()
                    .scaleEffect(0.7)
            }
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        switch disk.status {
        case .mounted: return "externaldrive.fill.badge.checkmark"
        case .readOnly: return "externaldrive.badge.minus"
        case .error: return "externaldrive.badge.xmark"
        default: return "externaldrive"
        }
    }

    private var iconColor: Color {
        switch disk.status {
        case .mounted: return .green
        case .readOnly: return .orange
        case .error: return .red
        default: return .secondary
        }
    }

    private var statusColor: Color {
        switch disk.status {
        case .mounted: return .green
        case .error: return .red
        case .readOnly: return .orange
        default: return .secondary
        }
    }
}

extension ExternalDisk: Hashable {
    static func == (lhs: ExternalDisk, rhs: ExternalDisk) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
