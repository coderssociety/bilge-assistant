import AppKit
import SwiftUI

/// Everything the assistant did, refused or was told not to do, read from the local audit log.
struct HistoryView: View {
    private static let maxEntries = 200
    @State private var entries: [ActionAuditLog.Entry] = []

    var body: some View {
        VStack(spacing: 0) {
            if entries.isEmpty {
                ContentUnavailableView("Henüz bir işlem yok", systemImage: "clock",
                                       description: Text("Asistanın yaptığı ve onay bekleyen işler burada listelenir."))
            } else {
                List(Array(entries.enumerated()), id: \.offset) { _, entry in
                    HistoryRow(entry: entry)
                }
            }
            Divider()
            HStack {
                Button("Yenile") { Task { await load() } }
                Spacer()
                Button("Günlük dosyasını Finder'da göster") {
                    if let url = ActionAuditLog.fileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                }
                .disabled(entries.isEmpty)
            }
            .padding(10)
        }
        .task { await load() }
    }

    private func load() async {
        entries = await ActionAuditLog.shared.recentEntries(limit: Self.maxEntries)
    }
}

private struct HistoryRow: View {
    let entry: ActionAuditLog.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(entry.command).font(.body).lineLimit(1)
                Spacer()
                Text(entry.decision.label)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(entry.decision.tint.opacity(0.15), in: Capsule())
                    .foregroundStyle(entry.decision.tint)
            }
            HStack(spacing: 6) {
                Text(entry.date, format: .dateTime.day().month().hour().minute())
                Text("·")
                Text(entry.tool)
                if let result = entry.result {
                    Text("·")
                    Text(result).lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private extension ActionAuditLog.Decision {
    var label: String {
        switch self {
        case .executed: "Yapıldı"
        case .rejected: "Reddettin"
        case .unconfirmed: "Onaysız, yapılmadı"
        }
    }

    var tint: Color {
        switch self {
        case .executed: .green
        case .rejected: .orange
        case .unconfirmed: .secondary
        }
    }
}
