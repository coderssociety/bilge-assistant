import AppKit
import Observation
import SwiftUI

/// Shows the HUD while the assistant is engaged and hides it shortly after it goes back to idle.
/// The panel never takes focus, so whatever the user is typing into keeps the keyboard.
@MainActor
final class HUDPresenter {
    private static let hideDelay = Duration.seconds(3)
    private static let topMargin: CGFloat = 10

    private let assistant: AssistantController
    private let settings: AssistantSettings
    private let panel: NSPanel
    private let hostingView: NSHostingView<HUDView>
    private var observeTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?

    init(assistant: AssistantController, settings: AssistantSettings) {
        self.assistant = assistant
        self.settings = settings
        hostingView = NSHostingView(rootView: HUDView(assistant: assistant))
        hostingView.sizingOptions = [.intrinsicContentSize]
        panel = NSPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.contentView = hostingView
    }

    func start() {
        guard observeTask == nil else { return }
        let assistant = assistant
        let settings = settings
        observeTask = Task { [weak self] in
            let changes = Observations {
                (assistant.status, assistant.lastReply, assistant.pendingConfirmation, settings.showHUD)
            }
            for await (status, _, _, enabled) in changes {
                self?.update(status: status, enabled: enabled)
            }
        }
    }

    private func update(status: AssistantController.Status, enabled: Bool) {
        let engaged = switch status {
        case .awake, .transcribing, .thinking, .speaking, .confirming, .recording, .failed: true
        default: false
        }
        guard enabled, engaged else {
            scheduleHide()
            return
        }
        hideTask?.cancel()
        hideTask = nil
        show()
    }

    private func show() {
        let size = hostingView.fittingSize
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let origin = NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - Self.topMargin)
        panel.setFrame(NSRect(origin: origin, size: size), display: true, animate: panel.isVisible)
        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = 1 }
        }
    }

    private func scheduleHide() {
        guard panel.isVisible, hideTask == nil else { return }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.hideDelay)
            guard !Task.isCancelled, let self else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; self.panel.animator().alphaValue = 0 }) {
                Task { @MainActor in
                    self.panel.orderOut(nil)
                    self.hideTask = nil
                }
            }
        }
    }
}
