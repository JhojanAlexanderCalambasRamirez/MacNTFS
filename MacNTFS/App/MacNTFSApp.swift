import SwiftUI

@main
struct MacNTFSApp: App {
    @StateObject private var diskVM = DiskViewModel()
    @StateObject private var logService = LogService.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(diskVM)
                .environmentObject(logService)
                .onAppear {
                    diskVM.startMonitoring()
                }
                .onDisappear {
                    diskVM.stopMonitoring()
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 600)

        Settings {
            SettingsView()
        }
    }
}

struct SettingsView: View {
    var body: some View {
        Form {
            Section("Dependencies") {
                DependencyCheckView()
            }
        }
        .padding()
        .frame(width: 450)
    }
}

struct DependencyCheckView: View {
    @State private var ntfs3gInstalled = false
    @State private var fuseInstalled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: ntfs3gInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(ntfs3gInstalled ? .green : .red)
                Text("ntfs-3g")
                Spacer()
                if !ntfs3gInstalled {
                    Button("Install") {
                        openTerminal("brew install ntfs-3g")
                    }
                }
            }

            HStack {
                Image(systemName: fuseInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(fuseInstalled ? .green : .red)
                Text("macFUSE")
                Spacer()
                if !fuseInstalled {
                    Button("Install") {
                        openTerminal("brew install --cask macfuse")
                    }
                }
            }
        }
        .onAppear { checkDeps() }
    }

    private func checkDeps() {
        ntfs3gInstalled = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/ntfs-3g") ||
                          FileManager.default.fileExists(atPath: "/usr/local/bin/ntfs-3g")
        fuseInstalled = FileManager.default.fileExists(atPath: "/Library/Frameworks/macFUSE.framework") ||
                        FileManager.default.fileExists(atPath: "/usr/local/lib/libfuse.dylib")
    }

    private func openTerminal(_ command: String) {
        let script = "tell application \"Terminal\" to do script \"\(command)\""
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }
}
