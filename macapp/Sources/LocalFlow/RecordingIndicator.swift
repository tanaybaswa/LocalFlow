import AppKit
import SwiftUI

/// Floating non-activating pill shown while recording.
@MainActor
final class RecordingIndicator {
    static let shared = RecordingIndicator()

    private var panel: NSPanel?
    private var hosting: NSHostingView<IndicatorView>?

    func show() {
        if panel == nil {
            let view = IndicatorView()
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(x: 0, y: 0, width: 160, height: 40)

            let p = NSPanel(
                contentRect: host.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.isOpaque = false
            p.backgroundColor = .clear
            p.level = .statusBar
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            p.hidesOnDeactivate = false
            p.hasShadow = true
            p.contentView = host
            panel = p
            hosting = host
        }
        guard let panel else { return }
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let size = panel.frame.size
            let x = frame.midX - size.width / 2
            let y = frame.minY + 28
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }
}

private struct IndicatorView: View {
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
            Text("Recording")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.82))
        )
    }
}
