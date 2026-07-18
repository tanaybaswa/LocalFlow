import AppKit
import SwiftUI

/// Floating non-activating pill shown while recording — white with live amplitude bars.
@MainActor
final class RecordingIndicator {
    static let shared = RecordingIndicator()

    private var panel: NSPanel?
    private var hosting: NSHostingView<IndicatorView>?

    func show() {
        RecordingLevels.shared.start()

        if panel == nil {
            let view = IndicatorView(levels: RecordingLevels.shared)
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(x: 0, y: 0, width: 168, height: 44)

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
        } else {
            hosting?.rootView = IndicatorView(levels: RecordingLevels.shared)
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
        RecordingLevels.shared.stop()
        panel?.orderOut(nil)
    }
}

private struct IndicatorView: View {
    @Bindable var levels: RecordingLevels

    var body: some View {
        HStack(spacing: 10) {
            WaveformView(bars: levels.bars)
                .frame(width: 88, height: 22)

            Text("Listening")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(white: 0.22))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(
            Capsule()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
        )
        .overlay(
            Capsule()
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct WaveformView: View {
    let bars: [CGFloat]

    var body: some View {
        GeometryReader { geo in
            let count = max(bars.count, 1)
            let spacing: CGFloat = 2
            let barWidth = max(2, (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))

            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, level in
                    RoundedRectangle(cornerRadius: barWidth / 2, style: .continuous)
                        .fill(Color(white: 0.18))
                        .frame(
                            width: barWidth,
                            height: max(3, geo.size.height * level)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .animation(.easeOut(duration: 0.06), value: bars)
        }
    }
}
