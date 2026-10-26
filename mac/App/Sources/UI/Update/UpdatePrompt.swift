import AppKit
import AsistanCore
import SwiftUI

/// A small window that tells about a newer release once per version and offers to install it. It doesn't block
/// anything: Bilge keeps listening, and closing it leaves the offer in the menu.
@MainActor
final class UpdatePrompt {
    private let updates: UpdateChecker
    private var panel: NSPanel?

    init(updates: UpdateChecker) {
        self.updates = updates
    }

    func show(_ release: ReleaseCheck.Release) {
        panel?.close()
        let panel = NSPanel(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView],
                            backing: .buffered, defer: true)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        let view = NSHostingView(rootView: UpdatePromptView(updates: updates, release: release) { [weak panel] in
            panel?.close()
        })
        view.sizingOptions = [.intrinsicContentSize]
        panel.contentView = view
        panel.center()
        self.panel = panel
        panel.orderFrontRegardless()
    }
}

private struct UpdatePromptView: View {
    let updates: UpdateChecker
    let release: ReleaseCheck.Release
    let close: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                Text("\(AppIdentity.name) \(release.version) çıktı").font(.headline)
                Text(updates.canInstall
                    ? String(localized: "Şimdi indirip kurabilir ve yeniden başlayabilirim; birkaç dakika sürer. Neler değiştiğini sürüm sayfasında görebilirsin.")
                    : String(localized: "Yeni sürümü sürüm sayfasından indirebilirsin."))
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                status
                HStack {
                    Button("Sonra", action: close).keyboardShortcut(.cancelAction)
                    Button("Neler yeni?") { NSWorkspace.shared.open(release.page) }
                    Spacer()
                    if updates.canInstall {
                        Button("Güncelle ve yeniden başlat") { Task { await updates.installer.install(release) } }
                            .keyboardShortcut(.defaultAction)
                            .disabled(updates.installer.isWorking)
                    } else {
                        Button("İndirme sayfasını aç") {
                            NSWorkspace.shared.open(release.page)
                            close()
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    @ViewBuilder
    private var status: some View {
        switch updates.installer.state {
        case let .working(step):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(step).font(.caption).foregroundStyle(.secondary)
            }
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        case .idle:
            EmptyView()
        }
    }
}
