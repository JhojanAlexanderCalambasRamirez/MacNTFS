import SwiftUI

struct OnboardingView: View {
    @Binding var isComplete: Bool
    @State private var currentStep = 0
    @State private var brewInstalled = false
    @State private var macFUSEInstalled = false
    @State private var ntfs3gInstalled = false
    @State private var isInstalling = false
    @State private var installError: String?
    @State private var installLog: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "externaldrive.fill.badge.checkmark")
                    .font(.system(size: 56))
                    .foregroundStyle(.blue)

                Text("Welcome to MacNTFS")
                    .font(.title)
                    .fontWeight(.bold)

                Text("A few components are needed to enable NTFS write support.\nThis only takes a minute.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 32)
            .padding(.bottom, 24)

            Divider()

            // Steps
            VStack(alignment: .leading, spacing: 16) {
                StepRow(
                    number: 1,
                    title: "Homebrew",
                    subtitle: "Package manager for macOS",
                    status: brewInstalled ? .installed : (currentStep == 0 && isInstalling ? .installing : .pending),
                    action: !brewInstalled ? { await installBrew() } : nil
                )

                StepRow(
                    number: 2,
                    title: "macFUSE",
                    subtitle: "Filesystem driver for macOS",
                    status: macFUSEInstalled ? .installed : (currentStep == 1 && isInstalling ? .installing : .pending),
                    action: brewInstalled && !macFUSEInstalled ? { await installMacFUSE() } : nil
                )

                StepRow(
                    number: 3,
                    title: "ntfs-3g",
                    subtitle: "NTFS read/write support",
                    status: ntfs3gInstalled ? .installed : (currentStep == 2 && isInstalling ? .installing : .pending),
                    action: brewInstalled && macFUSEInstalled && !ntfs3gInstalled ? { await installNTFS3G() } : nil
                )
            }
            .padding(24)

            if !installLog.isEmpty {
                ScrollView {
                    Text(installLog)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 80)
                .background(Color.black.opacity(0.05))
                .cornerRadius(6)
                .padding(.horizontal, 24)
            }

            if let error = installError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
            }

            Spacer()

            Divider()

            // Footer
            HStack {
                if allInstalled {
                    Button("Install All") { }
                        .hidden()
                } else {
                    Button("Install All") {
                        Task { await installAll() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isInstalling)
                }

                Spacer()

                if allInstalled {
                    Button("Get Started") {
                        isComplete = true
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    Button("Skip") {
                        isComplete = true
                    }
                    .foregroundColor(.secondary)
                }
            }
            .padding(20)
        }
        .frame(width: 500, height: 560)
        .onAppear { checkDependencies() }
    }

    private var allInstalled: Bool {
        brewInstalled && macFUSEInstalled && ntfs3gInstalled
    }

    private func checkDependencies() {
        brewInstalled = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") ||
                        FileManager.default.fileExists(atPath: "/usr/local/bin/brew")
        macFUSEInstalled = FileManager.default.fileExists(atPath: "/Library/Frameworks/macFUSE.framework")
        ntfs3gInstalled = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/ntfs-3g") ||
                          FileManager.default.fileExists(atPath: "/usr/local/bin/ntfs-3g")

        if allInstalled {
            isComplete = true
        }
    }

    private func installAll() async {
        if !brewInstalled { await installBrew() }
        if !macFUSEInstalled { await installMacFUSE() }
        if !ntfs3gInstalled { await installNTFS3G() }
    }

    private func installBrew() async {
        currentStep = 0
        isInstalling = true
        installError = nil

        let result = await runPrivileged(
            "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        )

        if result {
            brewInstalled = true
            appendLog("Homebrew installed successfully")
        }
        isInstalling = false
    }

    private func installMacFUSE() async {
        currentStep = 1
        isInstalling = true
        installError = nil

        let brewPath = findBrew()
        let result = await runPrivileged("\(brewPath) install --cask macfuse")

        if result {
            macFUSEInstalled = true
            appendLog("macFUSE installed successfully")
        }
        isInstalling = false
    }

    private func installNTFS3G() async {
        currentStep = 2
        isInstalling = true
        installError = nil

        let brewPath = findBrew()
        let tapResult = await runShell("\(brewPath) tap gromgit/fuse")
        if tapResult {
            appendLog("Tap gromgit/fuse added")
        }

        let result = await runShell("\(brewPath) install gromgit/fuse/ntfs-3g-mac")

        if result {
            ntfs3gInstalled = true
            appendLog("ntfs-3g installed successfully")
        }
        isInstalling = false
    }

    private func runPrivileged(_ command: String) async -> Bool {
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\")
                             .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"

        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let script = NSAppleScript(source: source)
                var error: NSDictionary?
                script?.executeAndReturnError(&error)

                if let error {
                    let msg = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                    Task { @MainActor in
                        self.installError = msg
                        self.appendLog("Error: \(msg)")
                    }
                    continuation.resume(returning: false)
                } else {
                    continuation.resume(returning: true)
                }
            }
        }
    }

    private func runShell(_ command: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-c", command]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""

                    Task { @MainActor in
                        if !output.isEmpty {
                            self.appendLog(output.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                    }

                    continuation.resume(returning: process.terminationStatus == 0)
                } catch {
                    Task { @MainActor in
                        self.installError = error.localizedDescription
                    }
                    continuation.resume(returning: false)
                }
            }
        }
    }

    private func findBrew() -> String {
        if FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") {
            return "/opt/homebrew/bin/brew"
        }
        return "/usr/local/bin/brew"
    }

    private func appendLog(_ text: String) {
        if installLog.isEmpty {
            installLog = text
        } else {
            installLog += "\n" + text
        }
    }
}

struct StepRow: View {
    let number: Int
    let title: String
    let subtitle: String
    let status: StepStatus
    let action: (() async -> Void)?

    enum StepStatus {
        case pending, installing, installed
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 36, height: 36)

                switch status {
                case .pending:
                    Text("\(number)")
                        .font(.headline)
                        .foregroundColor(statusColor)
                case .installing:
                    ProgressView()
                        .scaleEffect(0.7)
                case .installed:
                    Image(systemName: "checkmark")
                        .font(.headline)
                        .foregroundColor(.green)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if status == .pending, let action {
                Button("Install") {
                    Task { await action() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if status == .installed {
                Text("Installed")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
    }

    private var statusColor: Color {
        switch status {
        case .pending: return .secondary
        case .installing: return .blue
        case .installed: return .green
        }
    }
}
