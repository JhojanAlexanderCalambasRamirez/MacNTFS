import SwiftUI

struct DiskListView: View {
    @EnvironmentObject var diskVM: DiskViewModel
    @EnvironmentObject var loc: LocalizationManager

    var body: some View {
        List(selection: $diskVM.selectedDisk) {
            if !diskVM.ntfsDisks.isEmpty {
                Section(loc.t("ntfs.drives")) {
                    ForEach(diskVM.ntfsDisks) { disk in
                        // Pass diskId so the card reads live state from diskVM.
                        // Passing disk directly captures a value snapshot — status
                        // changes (mount/unmount) would not update the card buttons.
                        DiskCardView(diskId: disk.id)
                            .tag(disk)
                    }
                }
            }

            if !diskVM.otherDisks.isEmpty {
                Section(loc.t("other.drives")) {
                    ForEach(diskVM.otherDisks) { disk in
                        DiskCardView(diskId: disk.id)
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
}

// MARK: - Disk Card

struct DiskCardView: View {
    let diskId: String
    @EnvironmentObject var diskVM: DiskViewModel
    @EnvironmentObject var loc: LocalizationManager

    // Always reads the current disk from diskVM so any status change
    // (mounting → mounted → unmounting) re-renders the action buttons immediately.
    private var disk: ExternalDisk? {
        diskVM.diskService.disks.first { $0.id == diskId }
    }

    var body: some View {
        if let disk {
            cardContent(disk: disk)
        }
    }

    @ViewBuilder
    private func cardContent(disk: ExternalDisk) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Row 1: icon + name + action buttons
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(statusColor(disk).opacity(0.12))
                        .frame(width: 36, height: 36)

                    Image(systemName: iconName(disk))
                        .font(.system(size: 17))
                        .foregroundColor(statusColor(disk))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(disk.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Text(disk.fileSystem.uppercased())
                            .font(.system(size: 9, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(disk.isNTFS ? Color.blue.opacity(0.14) : Color.gray.opacity(0.12))
                            .foregroundColor(disk.isNTFS ? .blue : .secondary)
                            .cornerRadius(3)

                        Text(disk.busProtocol)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                actionButtons(disk: disk)
            }

            // Row 2: storage bar + size + status
            VStack(alignment: .leading, spacing: 3) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.13))
                            .frame(height: 5)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(storageBarColor(disk))
                            .frame(width: max(0, geo.size.width * storageUsedFraction), height: 5)
                    }
                }
                .frame(height: 5)

                HStack {
                    Text(disk.sizeFormatted)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    Spacer()

                    HStack(spacing: 3) {
                        Circle()
                            .fill(statusColor(disk))
                            .frame(width: 5, height: 5)
                        Text(disk.status.rawValue)
                            .font(.system(size: 10))
                            .foregroundColor(statusColor(disk))
                    }
                }
            }
        }
        .padding(.vertical, 5)
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private func actionButtons(disk: ExternalDisk) -> some View {
        if disk.status == .mounting || disk.status == .unmounting || disk.status == .ejecting {
            ProgressView()
                .scaleEffect(0.65)
                .frame(width: 24, height: 24)
        } else {
            HStack(spacing: 4) {
                if disk.isNTFS && (disk.status == .readOnly || disk.status == .detected) {
                    CardActionButton(icon: "lock.open.fill",
                                     label: loc.language == .spanish ? "Montar" : "Mount",
                                     color: .blue) {
                        Task { await diskVM.mountWithWriteSupport(disk) }
                    }
                    .disabled(diskVM.isMounting)
                }

                if disk.status == .mounted {
                    if let mp = disk.mountPoint {
                        CardActionButton(icon: "folder.fill",
                                         label: "Finder",
                                         color: .blue) {
                            NSWorkspace.shared.open(URL(fileURLWithPath: mp))
                        }
                    }

                    CardActionButton(icon: "arrow.uturn.backward",
                                     label: loc.t("unmount"),
                                     color: .secondary) {
                        Task { await diskVM.unmountDisk(disk) }
                    }
                    .disabled(diskVM.isMounting)
                }

                CardActionButton(icon: "eject.fill",
                                 label: loc.language == .spanish ? "Expulsar" : "Eject",
                                 color: .orange) {
                    Task { await diskVM.ejectDisk(disk) }
                }
                .disabled(diskVM.isMounting)
            }
        }
    }

    // MARK: - Helpers

    private var storageUsedFraction: CGFloat { 0.65 }

    private func storageBarColor(_ disk: ExternalDisk) -> LinearGradient {
        let color: Color = storageUsedFraction > 0.9 ? .red : storageUsedFraction > 0.7 ? .orange : .blue
        return LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing)
    }

    private func iconName(_ disk: ExternalDisk) -> String {
        switch disk.status {
        case .mounted:                          return "externaldrive.fill.badge.checkmark"
        case .readOnly:                         return "externaldrive.badge.minus"
        case .error:                            return "externaldrive.badge.xmark"
        case .mounting, .unmounting, .ejecting: return "externaldrive.fill"
        case .detected:                         return "externaldrive"
        }
    }

    private func statusColor(_ disk: ExternalDisk) -> Color {
        switch disk.status {
        case .mounted:  return .green
        case .readOnly: return .orange
        case .error:    return .red
        case .ejecting: return .purple
        default:        return .secondary
        }
    }
}

// MARK: - Card Action Button

struct CardActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.13))
            .foregroundColor(color)
            .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .help(label)
    }
}

extension ExternalDisk: Hashable {
    static func == (lhs: ExternalDisk, rhs: ExternalDisk) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
