import SwiftUI

/// What the user asked the assistant to remember; each fact can be deleted here as well as by voice.
struct MemoryView: View {
    let memory: MemoryStore
    @State private var confirmingClear = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if memory.book.entries.isEmpty {
                ContentUnavailableView("Hafıza boş", systemImage: "brain",
                                       description: Text("\"Bilge, eşimin adının Ayşe olduğunu hatırla\" dediğinde bilgi burada görünür."))
            } else {
                List(memory.book.entries.reversed()) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.text)
                            Text(entry.created, format: .dateTime.day().month().year())
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) { perform { try memory.forget(id: entry.id) } } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Bu bilgiyi sil")
                    }
                }
            }
            Divider()
            HStack {
                Text(errorMessage ?? String(localized: "Bilgiler yalnızca bu Mac'te saklanır."))
                    .font(.caption).foregroundStyle(errorMessage == nil ? Color.secondary : Color.red)
                Spacer()
                Button("Tümünü sil", role: .destructive) { confirmingClear = true }
                    .disabled(memory.book.entries.isEmpty)
            }
            .padding(10)
        }
        .confirmationDialog("Hatırlanan tüm bilgiler silinsin mi?", isPresented: $confirmingClear) {
            Button("Tümünü sil", role: .destructive) { perform { _ = try memory.forgetAll() } }
        }
    }

    private func perform(_ change: () throws -> Void) {
        do {
            try change()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
