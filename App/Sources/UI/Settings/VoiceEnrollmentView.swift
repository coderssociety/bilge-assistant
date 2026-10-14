import SwiftUI

/// Reads five commands aloud to enroll the user's voice. Listening is paused meanwhile.
struct VoiceEnrollmentView: View {
    @State var enrollment: VoiceEnrollment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Text("Sesini tanıt").font(.title2.weight(.semibold))
            switch enrollment.phase {
            case .ready, .recording:
                Text("\(enrollment.index + 1) / \(VoiceEnrollment.prompts.count)").foregroundStyle(.secondary)
                Text("“\(enrollment.prompt)”").font(.title3).multilineTextAlignment(.center)
                Button(enrollment.phase == .recording ? "Dinliyorum…" : "Kaydet ve oku") {
                    Task { await enrollment.recordNext() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(enrollment.phase == .recording)
                Text("Düğmeye bastıktan sonra cümleyi normal sesinle oku.").font(.caption).foregroundStyle(.secondary)
            case let .finished(consistency):
                Label("Sesin kaydedildi", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                Text("Tutarlılık \(consistency, format: .number.precision(.fractionLength(2))). Artık yalnızca senin sesine yanıt vereceğim.")
                    .multilineTextAlignment(.center)
                Button("Kapat") { dismiss() }.keyboardShortcut(.defaultAction)
            case let .failed(message):
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).multilineTextAlignment(.center)
                HStack {
                    Button("Vazgeç") { dismiss() }
                    Button("Baştan dene") { enrollment.restart() }.keyboardShortcut(.defaultAction)
                }
            }
            Text("Ses kaydı saklanmaz; yalnızca sesinin sayısal özeti bu Mac'te tutulur.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 420)
    }
}
