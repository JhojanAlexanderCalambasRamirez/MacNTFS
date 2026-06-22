import SwiftUI

struct ContentView: View {
    @EnvironmentObject var diskVM: DiskViewModel
    @State private var showingLogs = true
    @State private var showingAbout = false

    var body: some View {
        NavigationSplitView {
            DiskListView()
                .navigationSplitViewColumnWidth(min: 250, ideal: 280)
        } detail: {
            if let disk = diskVM.selectedDisk, disk.status == .mounted, let mp = disk.mountPoint {
                FileManagerView(rootPath: mp)
            } else if let disk = diskVM.selectedDisk {
                VStack(spacing: 16) {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text(disk.name)
                        .font(.title2)

                    Text(disk.fileSystem.uppercased())
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.2))
                        .cornerRadius(4)

                    Text(disk.sizeFormatted)
                        .foregroundColor(.secondary)

                    if disk.isNTFS {
                        Button("Mount with Write Support") {
                            Task { await diskVM.mountWithWriteSupport(disk) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(diskVM.isMounting)

                        if diskVM.isMounting {
                            ProgressView()
                        }
                    }

                    if let error = diskVM.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "externaldrive")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Connect an external NTFS drive")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    showingAbout.toggle()
                } label: {
                    Image(systemName: "info.circle")
                }
                .help("About")
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    showingLogs.toggle()
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                }
                .help("Toggle Logs")
            }
        }
        .inspector(isPresented: $showingLogs) {
            LogView()
                .inspectorColumnWidth(min: 250, ideal: 300)
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Text("by J4CR")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.4))
                    .padding(.trailing, 8)
                    .padding(.bottom, 2)
            }
        }
    }
}

struct AboutView: View {
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
                Text("Developed by Alexander Calambas")
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

            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .frame(width: 320, height: 320)
    }
}
