import SwiftUI

struct DiskListView: View {
    @EnvironmentObject var diskVM: DiskViewModel
    @EnvironmentObject var loc: LocalizationManager

    var body: some View {
        List(selection: $diskVM.selectedDisk) {
            if !diskVM.ntfsDisks.isEmpty {
                Section(loc.t("ntfs.drives")) {
                    ForEach(diskVM.ntfsDisks) { disk in
                        DiskCardView(disk: disk)
                            .tag(disk)
                            .contextMenu { diskContextMenu(disk) }
                    }
                }
            }

            if !diskVM.otherDisks.isEmpty {
                Section(loc.t("other.drives")) {
                    ForEach(diskVM.otherDisks) { disk in
                        DiskCardView(disk: disk)
                            .tag(disk)
                    }
                }
            }

            if diskVM.diskService.disks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "externaldrive.trianglebadge.exclamationmark")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.5))

                    Text(loc.t("no.drives"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    Text(loc.t("no.drives.subtitle"))
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            }
        }
        .navigationTitle(loc.t("drives"))
    }

    @ViewBuilder
    private func diskContextMenu(_ disk: ExternalDisk) -> some View {
        if disk.isNTFS && disk.status != .mounted {
            Button {
                Task { await diskVM.mountWithWriteSupport(disk) }
            } label: {
                Label(loc.t("mount.rw"), systemImage: "externaldrive.fill.badge.plus")
            }
        }
        if disk.status == .mounted {
            Button {
                Task { await diskVM.unmountDisk(disk) }
            } label: {
                Label(loc.t("unmount"), systemImage: "eject.fill")
            }
            Divider()
            Button {
                if let mp = disk.mountPoint {
                    NSWorkspace.shared.open(URL(fileURLWithPath: mp))
                }
            } label: {
                Label(loc.t("open.finder"), systemImage: "folder.badge.person.crop")
            }
        }
    }
}

struct DiskCardView: View {
    let disk: ExternalDisk

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(statusColor.opacity(0.12))
                        .frame(width: 38, height: 38)

                    Image(systemName: iconName)
                        .font(.system(size: 18))
                        .foregroundColor(statusColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(disk.name)
                        .font(.headline)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Label(disk.fileSystem.uppercased(), systemImage: "doc.viewfinder")
                            .font(.system(size: 10))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(disk.isNTFS ? Color.blue.opacity(0.12) : Color.gray.opacity(0.12))
                            .cornerRadius(3)

                        Label(disk.busProtocol, systemImage: "cable.connector")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if disk.status == .mounting || disk.status == .unmounting {
                    ProgressView()
                        .scaleEffect(0.65)
                }
            }

            // Storage bar
            VStack(alignment: .leading, spacing: 3) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.secondary.opacity(0.15))
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 3)
                            .fill(storageBarColor)
                            .frame(width: max(0, geo.size.width * storageUsedFraction), height: 6)
                    }
                }
                .frame(height: 6)

                HStack {
                    Text(disk.sizeFormatted)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    Spacer()

                    HStack(spacing: 2) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                        Text(disk.status.rawValue)
                            .font(.system(size: 10))
                            .foregroundColor(statusColor)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var storageUsedFraction: CGFloat {
        disk.size > 0 ? 0.65 : 0 // placeholder — real value needs disk usage query
    }

    private var storageBarColor: LinearGradient {
        let fraction = storageUsedFraction
        let color: Color = fraction > 0.9 ? .red : fraction > 0.7 ? .orange : .blue
        return LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing)
    }

    private var iconName: String {
        switch disk.status {
        case .mounted: return "externaldrive.fill.badge.checkmark"
        case .readOnly: return "externaldrive.badge.minus"
        case .error: return "externaldrive.badge.xmark"
        case .mounting, .unmounting: return "externaldrive.fill"
        case .detected: return "externaldrive"
        }
    }

    private var statusColor: Color {
        switch disk.status {
        case .mounted: return .green
        case .readOnly: return .orange
        case .error: return .red
        default: return .secondary
        }
    }
}

extension ExternalDisk: Hashable {
    static func == (lhs: ExternalDisk, rhs: ExternalDisk) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
