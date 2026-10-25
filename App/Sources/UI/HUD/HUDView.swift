import SwiftUI

/// Floating status card: what the assistant is doing, what it heard and what it is saying.
struct HUDView: View {
    let assistant: AssistantController
    static let width: CGFloat = 420

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                StatusOrb(status: assistant.status, level: assistant.inputLevel)
                Text(assistant.statusTitle)
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 8)
                if assistant.status == .speaking || assistant.status == .thinking {
                    Button {
                        assistant.interrupt()
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Yanıtı durdur")
                    .accessibilityLabel("Yanıtı durdur")
                }
            }
            if let heard = assistant.lastHeard, assistant.status != .listening {
                Text("“\(heard)”")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if let reply = assistant.lastReply, !reply.isEmpty {
                Text(reply)
                    .font(.body)
                    .lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if assistant.pendingConfirmation != nil {
                HStack {
                    Button("Evet, yap") { assistant.resolveConfirmation(.confirmed) }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    Button("Hayır") { assistant.resolveConfirmation(.rejected) }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(16)
        .frame(width: Self.width, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .animation(.smooth(duration: 0.25), value: assistant.status)
    }
}

private struct StatusOrb: View {
    let status: AssistantController.Status
    let level: Float
    private static let size: CGFloat = 34

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.18))
                .scaleEffect(isListeningForCommand ? 1 + CGFloat(level) * 0.35 : 1)
                .animation(.easeOut(duration: 0.2), value: level)
            Image(systemName: status.symbolName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .symbolEffect(.pulse, isActive: status == .thinking || status == .transcribing || status == .recording)
                .symbolEffect(.variableColor.iterative, isActive: status == .speaking)
        }
        .frame(width: Self.size, height: Self.size)
        .accessibilityHidden(true)
    }

    private var isListeningForCommand: Bool {
        status == .awake || status == .confirming
    }

    private var tint: Color {
        switch status {
        case .awake, .transcribing: .blue
        case .thinking: .purple
        case .speaking: .green
        case .confirming: .orange
        case .recording, .failed: .red
        default: .secondary
        }
    }
}
