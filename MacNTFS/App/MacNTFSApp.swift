import SwiftUI

enum AppTheme: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@main
struct MacNTFSApp: App {
    @StateObject private var diskVM = DiskViewModel()
    @StateObject private var logService = LogService.shared
    @StateObject private var localization = LocalizationManager.shared
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @AppStorage("appTheme") private var appTheme: AppTheme = .system

    var body: some Scene {
        WindowGroup {
            Group {
                if onboardingComplete {
                    ContentView()
                        .environmentObject(diskVM)
                        .environmentObject(logService)
                        .environmentObject(localization)
                        .onAppear {
                        diskVM.startMonitoring()
                        NotificationService.requestPermission()
                    }
                        .onDisappear { diskVM.stopMonitoring() }
                } else {
                    OnboardingView(isComplete: $onboardingComplete)
                        .environmentObject(localization)
                }
            }
            .preferredColorScheme(appTheme.colorScheme)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 600)

        Settings {
            SettingsView()
                .environmentObject(localization)
                .preferredColorScheme(appTheme.colorScheme)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var loc: LocalizationManager

    var body: some View {
        TabView {
            AppearanceSettingsView()
                .tabItem { Label(loc.t("appearance"), systemImage: "paintbrush") }

            DependencyCheckView()
                .tabItem { Label(loc.t("dependencies"), systemImage: "shippingbox") }

            UninstallView()
                .tabItem { Label(loc.t("uninstall"), systemImage: "trash") }
        }
        .environmentObject(loc)
        .padding()
        .frame(width: 480, height: 340)
    }
}

struct AppearanceSettingsView: View {
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @EnvironmentObject var loc: LocalizationManager

    var body: some View {
        Form {
            Section(loc.t("appearance")) {
                Picker(loc.t("dark.mode"), selection: $appTheme) {
                    Text(loc.t("theme.system")).tag(AppTheme.system)
                    Text(loc.t("theme.light")).tag(AppTheme.light)
                    Text(loc.t("theme.dark")).tag(AppTheme.dark)
                }
                .pickerStyle(.segmented)
            }

            Section(loc.t("language")) {
                Picker(loc.t("language"), selection: $loc.language) {
                    ForEach(AppLanguage.allCases, id: \.self) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }
}

struct DependencyCheckView: View {
    @State private var ntfs3gInstalled = false
    @State private var fuseInstalled = false
    @EnvironmentObject var loc: LocalizationManager

    var body: some View {
        Form {
            Section("Status") {
                HStack {
                    Image(systemName: ntfs3gInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(ntfs3gInstalled ? .green : .red)
                    Text("ntfs-3g")
                    Spacer()
                    if ntfs3gInstalled {
                        Text(loc.t("installed")).font(.caption).foregroundColor(.green)
                    }
                }

                HStack {
                    Image(systemName: fuseInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(fuseInstalled ? .green : .red)
                    Text("macFUSE")
                    Spacer()
                    if fuseInstalled {
                        Text(loc.t("installed")).font(.caption).foregroundColor(.green)
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
}

struct UninstallView: View {
    @EnvironmentObject var loc: LocalizationManager
    @State private var showConfirm = false
    @State private var removeDeps = true
    @State private var isUninstalling = false
    @State private var uninstallLog: String = ""
    @State private var uninstallComplete = false

    var body: some View {
        Form {
            Section(loc.t("uninstall.title")) {
                Text(loc.t("uninstall.desc"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle(loc.t("uninstall.deps"), isOn: $removeDeps)

                if !uninstallLog.isEmpty {
                    Text(uninstallLog)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                if uninstallComplete {
                    Label(loc.t("uninstall.complete"), systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                } else {
                    Button(loc.t("uninstall.button"), role: .destructive) {
                        showConfirm = true
                    }
                    .disabled(isUninstalling)
                }
            }
        }
        .confirmationDialog(
            loc.t("uninstall.confirm"),
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button(loc.t("uninstall"), role: .destructive) {
                Task { await performUninstall() }
            }
            Button(loc.t("cancel"), role: .cancel) { }
        }
    }

    private func performUninstall() async {
        isUninstalling = true
        uninstallLog = ""

        let brewPath = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew")
            ? "/opt/homebrew/bin/brew" : "/usr/local/bin/brew"

        if removeDeps {
            appendLog("Removing ntfs-3g...")
            await runPrivileged("\(brewPath) uninstall gromgit/fuse/ntfs-3g-mac 2>/dev/null; true")
            appendLog("Removing macFUSE...")
            await runPrivileged("\(brewPath) uninstall --cask macfuse 2>/dev/null; true")
            appendLog("Dependencies removed.")
        }

        appendLog("Removing MacNTFS.app...")
        let appPath = Bundle.main.bundlePath
        await runPrivileged("rm -rf \"\(appPath)\"")

        appendLog("Cleaning preferences...")
        await runShell("defaults delete com.macntfs.app 2>/dev/null; true")

        uninstallComplete = true
        isUninstalling = false
    }

    @discardableResult
    private func runPrivileged(_ command: String) async -> Bool {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
                             .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"

        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let script = NSAppleScript(source: source)
                var error: NSDictionary?
                script?.executeAndReturnError(&error)
                continuation.resume(returning: error == nil)
            }
        }
    }

    @discardableResult
    private func runShell(_ command: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-c", command]
                try? process.run()
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus == 0)
            }
        }
    }

    private func appendLog(_ text: String) {
        if uninstallLog.isEmpty {
            uninstallLog = text
        } else {
            uninstallLog += "\n" + text
        }
    }
}

struct SettingsSheetView: View {
    @EnvironmentObject var loc: LocalizationManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(loc.t("settings"))
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            TabView {
                AppearanceSettingsView()
                    .tabItem { Label(loc.t("appearance"), systemImage: "paintbrush") }

                DependencyCheckView()
                    .tabItem { Label(loc.t("dependencies"), systemImage: "shippingbox") }

                UninstallView()
                    .tabItem { Label(loc.t("uninstall"), systemImage: "trash") }
            }
            .environmentObject(loc)
            .padding()
        }
        .frame(width: 500, height: 400)
    }
}
