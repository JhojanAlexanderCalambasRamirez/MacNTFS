import SwiftUI

struct ContentView: View {
    @EnvironmentObject var diskVM: DiskViewModel
    @EnvironmentObject var loc: LocalizationManager
    @State private var showingLogs = false
    @State private var showingAbout = false
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                DiskListView()
                    .navigationSplitViewColumnWidth(min: 250, ideal: 280)
            } detail: {
                if let disk = diskVM.selectedDisk, disk.status == .mounted, let mp = disk.mountPoint {
                    FileManagerView(rootPath: mp)
                } else if let disk = diskVM.selectedDisk {
                    DiskDetailView(disk: disk)
                } else {
                    EmptyStateView()
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    Button { showingSettings.toggle() } label: {
                        Image(systemName: "gearshape")
                    }
                    .help(loc.t("settings"))

                    Button { showingAbout.toggle() } label: {
                        Image(systemName: "info.circle")
                    }
                    .help(loc.t("about"))

                    Divider()

                    Button { showingLogs.toggle() } label: {
                        Image(systemName: showingLogs ? "rectangle.rightthird.inset.filled" : "rectangle.trailingthird.inset.filled")
                    }
                    .help(loc.t("logs"))
                }
            }
            .inspector(isPresented: $showingLogs) {
                LogView()
                    .inspectorColumnWidth(min: 250, ideal: 300)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsSheetView()
                    .environmentObject(loc)
            }
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }

            // Status bar
            StatusBarView()
        }
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    @EnvironmentObject var loc: LocalizationManager

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.08))
                    .frame(width: 100, height: 100)

                Image(systemName: "externaldrive.badge.plus")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary.opacity(0.6))
            }

            VStack(spacing: 6) {
                Text(loc.t("connect.ntfs"))
                    .font(.title3)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                VStack(spacing: 4) {
                    StepIndicator(number: 1, text: loc.language == .spanish ? "Conecta un disco USB con formato NTFS" : "Connect a USB drive formatted as NTFS")
                    StepIndicator(number: 2, text: loc.language == .spanish ? "Selecciona el disco en la barra lateral" : "Select the drive from the sidebar")
                    StepIndicator(number: 3, text: loc.language == .spanish ? "Haz clic en montar con escritura" : "Click mount with write support")
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StepIndicator: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 22, height: 22)
                Text("\(number)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.8))
        }
    }
}

// MARK: - Disk Detail (not mounted)

struct DiskDetailView: View {
    let disk: ExternalDisk
    @EnvironmentObject var diskVM: DiskViewModel
    @EnvironmentObject var loc: LocalizationManager

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(disk.isNTFS ? Color.orange.opacity(0.1) : Color.gray.opacity(0.1))
                    .frame(width: 90, height: 90)

                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 36))
                    .foregroundColor(disk.isNTFS ? .orange : .secondary)
            }

            VStack(spacing: 4) {
                Text(disk.name)
                    .font(.title2)
                    .fontWeight(.semibold)

                HStack(spacing: 8) {
                    Label(disk.fileSystem.uppercased(), systemImage: "doc.viewfinder")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.12))
                        .cornerRadius(4)

                    Label(disk.sizeFormatted, systemImage: "internaldrive")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Label(disk.busProtocol, systemImage: "cable.connector")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            VStack(spacing: 10) {
                if disk.isNTFS && disk.status != .mounted && disk.status != .ejecting {
                    Button {
                        Task { await diskVM.mountWithWriteSupport(disk) }
                    } label: {
                        Label(loc.t("mount.rw"), systemImage: "lock.open.fill")
                            .frame(minWidth: 200)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(diskVM.isMounting)
                }

                Button {
                    Task { await diskVM.ejectDisk(disk) }
                } label: {
                    Label(loc.t("eject.safe"), systemImage: "eject.fill")
                        .frame(minWidth: 200)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(diskVM.isMounting)

                if diskVM.isMounting {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text(disk.status == .ejecting ? loc.t("ejecting") : loc.t("mounting"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if let error = diskVM.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.08))
                .cornerRadius(6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Status Bar

struct StatusBarView: View {
    @EnvironmentObject var diskVM: DiskViewModel
    @EnvironmentObject var loc: LocalizationManager

    private var totalDisks: Int { diskVM.diskService.disks.count }
    private var mountedDisks: Int { diskVM.diskService.disks.filter { $0.status == .mounted }.count }
    private var ntfsDisks: Int { diskVM.ntfsDisks.count }

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 5) {
                Image(systemName: "externaldrive")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text("\(totalDisks) \(totalDisks == 1 ? "disk" : "disks")")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            if ntfsDisks > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "doc.viewfinder")
                        .font(.system(size: 10))
                        .foregroundColor(.blue)
                    Text("\(ntfsDisks) NTFS")
                        .font(.system(size: 11))
                        .foregroundColor(.blue)
                }
            }

            if mountedDisks > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                    Text("\(mountedDisks) \(loc.language == .spanish ? "montados" : "mounted")")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                }
            }

            Spacer()

            Text("by J4CR")
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.35))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

// MARK: - About

struct AboutView: View {
    @EnvironmentObject var loc: LocalizationManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.fill.badge.checkmark")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            Text("MacNTFS")
                .font(.title)
                .fontWeight(.bold)

            Text("v1.0.0")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("NTFS read/write support for macOS")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Divider()
                .padding(.horizontal, 40)

            VStack(spacing: 8) {
                Text(loc.t("developed.by"))
                    .font(.subheadline)

                HStack(spacing: 16) {
                    Button {
                        openURL(URL(string: "https://www.linkedin.com/in/j4cr/")!)
                    } label: {
                        Label("LinkedIn", systemImage: "link")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)

                    Button {
                        openURL(URL(string: "https://github.com/JhojanAlexanderCalambasRamirez")!)
                    } label: {
                        Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }

                Text("alexandercalambas23@gmail.com")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer().frame(height: 8)

            Button(loc.t("close")) { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .frame(width: 320, height: 320)
    }
}
