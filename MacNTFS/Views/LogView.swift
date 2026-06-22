import SwiftUI

struct LogView: View {
    @EnvironmentObject var logService: LogService
    @EnvironmentObject var loc: LocalizationManager

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(loc.t("logs"))
                    .font(.headline)
                Spacer()
                Button(loc.t("clear")) {
                    logService.clear()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(logService.entries) { entry in
                            LogEntryRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .onChange(of: logService.entries.count) { _, _ in
                    if let last = logService.entries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .font(.system(.caption, design: .monospaced))
    }
}

struct LogEntryRow: View {
    let entry: LogEntry

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return df
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Text(Self.timeFormatter.string(from: entry.timestamp))
                .foregroundColor(.secondary)

            Text(entry.level.rawValue)
                .foregroundColor(levelColor)
                .fontWeight(.medium)

            Text(entry.message)
                .foregroundColor(entry.level == .error ? .red : .primary)
        }
    }

    private var levelColor: Color {
        switch entry.level {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .debug: return .gray
        }
    }
}
