import AsistanCore
import SwiftUI

/// The routines set up by voice; each can be deleted here as well as by voice.
struct RoutinesView: View {
    let store: RoutineStore
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if store.routines.isEmpty {
                ContentUnavailableView("Kurulu rutin yok", systemImage: "repeat",
                                       description: Text("\"Bilge, her gece 21'de hava durumunu söyle\" dediğinde rutin burada görünür."))
            } else {
                List(store.routines) { routine in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(routine.command)
                            Text(RoutineSchedule.describe(days: routine.days, hour: routine.hour, minute: routine.minute,
                                                          language: AppLanguage.current))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) { remove(routine) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Bu rutini sil")
                    }
                }
            }
            Divider()
            Text(errorMessage ?? String(localized: "Rutinler yalnızca dinleme açıkken çalışır; onay gerektiren bir adımı sen yokken yapmazlar."))
                .font(.caption).foregroundStyle(errorMessage == nil ? Color.secondary : Color.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
    }

    private func remove(_ routine: Routine) {
        do {
            try store.remove([routine.id])
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
