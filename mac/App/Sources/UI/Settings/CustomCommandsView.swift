import AsistanCore
import SwiftUI

/// The user's own commands: a name to say and the command line it runs, without a shell. Edited as a draft and saved
/// together, so a half-typed line never runs.
struct CustomCommandsView: View {
    let store: CustomCommandStore
    @State private var rows: [Row] = []
    @State private var message: String?
    @State private var isError = false

    private struct Row: Identifiable, Equatable {
        let id: UUID
        var name: String
        var line: String
    }

    var body: some View {
        VStack(spacing: 0) {
            if rows.isEmpty {
                ContentUnavailableView("Henüz komut yok", systemImage: "terminal",
                                       description: Text("Bir ad ve bir komut satırı ekle; sonra “\(AppIdentity.name), yedekleme komutunu çalıştır” de."))
            } else {
                List {
                    ForEach($rows) { $row in
                        HStack(alignment: .firstTextBaseline) {
                            TextField("Ad", text: $row.name, prompt: Text("yedekleme"))
                                .frame(width: 150)
                            TextField("Komut satırı", text: $row.line, prompt: Text("rsync -a ~/Documents /Volumes/Yedek"))
                                .font(.body.monospaced())
                            Button(role: .destructive) { rows.removeAll { $0.id == row.id } } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Bu komutu sil")
                        }
                        .textFieldStyle(.roundedBorder)
                    }
                }
            }
            Divider()
            HStack {
                Button("Komut ekle") { rows.append(Row(id: UUID(), name: "", line: "")) }
                Spacer()
                Button("Vazgeç") { load() }.disabled(!hasChanges)
                Button("Kaydet", action: save).keyboardShortcut(.defaultAction).disabled(!hasChanges)
            }
            .padding(10)
            Text(message ?? String(localized: "Komut kabuk olmadan, yazıldığı gibi çalışır: yalnızca ~ açılır, boşluklu yolu tırnağa al. Söylediğin hiçbir şey eklenmez. 60 saniyede bitmeli; çıktısının başını okurum. Her komut ilk kez ve değiştikten sonra ilk kez çalışmadan önce komut satırını okuyup onay isterim."))
                .font(.caption).foregroundStyle(isError ? Color.red : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding([.horizontal, .bottom], 10)
        }
        .onAppear(perform: load)
    }

    private var savedRows: [Row] {
        store.commands.map { Row(id: $0.id, name: $0.name, line: $0.line) }
    }

    private var hasChanges: Bool { rows != savedRows }

    private func load() {
        rows = savedRows
        message = nil
        isError = false
    }

    private func save() {
        do {
            try store.replace(with: try commands())
            rows = savedRows
            message = String(localized: "Komutlar kaydedildi.")
            isError = false
        } catch {
            message = error.localizedDescription
            isError = true
        }
    }

    /// The commands in the list; empty rows are left out.
    private func commands() throws -> [CustomCommand] {
        var found: [CustomCommand] = []
        for row in rows {
            let name = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let line = row.line.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty, line.isEmpty { continue }
            guard !name.isEmpty, !line.isEmpty else { throw CommandListError.incomplete }
            guard let words = try? CommandLineText.split(line) else { throw CommandListError.unparsable(name) }
            guard !words.isEmpty else { throw CommandListError.incomplete }
            guard !found.contains(where: { TurkishText.folded($0.name) == TurkishText.folded(name) }) else {
                throw CommandListError.duplicate(name)
            }
            found.append(CustomCommand(id: row.id, name: name, arguments: words))
        }
        return found
    }
}

private enum CommandListError: LocalizedError {
    case incomplete
    case unparsable(String)
    case duplicate(String)

    var errorDescription: String? {
        switch self {
        case .incomplete: String(localized: "Her komutun hem adı hem komut satırı olmalı.")
        case let .unparsable(name): String(localized: "'\(name)' komutunda kapanmamış bir tırnak var.")
        case let .duplicate(name): String(localized: "'\(name)' adında iki komut olamaz.")
        }
    }
}
