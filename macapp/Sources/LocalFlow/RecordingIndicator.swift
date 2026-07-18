import AppKit
import SwiftUI

/// Floating non-activating pill shown while recording — dark navy with luminous amplitude bars.
/// Drawn entirely with AppKit so NSHostingView cannot leave a gray rectangular fill.
@MainActor
final class RecordingIndicator {
    static let shared = RecordingIndicator()

    private static let panelSize = NSSize(width: 160, height: 64)
    private static let pillSize = NSSize(width: 140, height: 46)

    private var panel: NSPanel?
    private var pillView: WaveformPillView?
    private var pollTimer: Timer?

    func show() {
        RecordingLevels.shared.start()
        tearDown()

        let size = Self.panelSize
        let root = ClearView(frame: NSRect(origin: .zero, size: size))

        let pill = WaveformPillView(frame: NSRect(
            x: (size.width - Self.pillSize.width) / 2,
            y: (size.height - Self.pillSize.height) / 2,
            width: Self.pillSize.width,
            height: Self.pillSize.height
        ))
        pill.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        root.addSubview(pill)

        let p = NSPanel(
            contentRect: root.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.hidesOnDeactivate = false
        p.hasShadow = false
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isFloatingPanel = true
        p.becomesKeyOnlyIfNeeded = true
        p.animationBehavior = .none
        p.contentView = root

        panel = p
        pillView = pill

        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pillView?.bars = RecordingLevels.shared.bars
            }
        }
        if let pollTimer {
            RunLoop.main.add(pollTimer, forMode: .common)
        }

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let x = frame.midX - size.width / 2
            let y = frame.minY + 24
            p.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        }
        p.orderFrontRegardless()
    }

    func hide() {
        RecordingLevels.shared.stop()
        tearDown()
    }

    private func tearDown() {
        pollTimer?.invalidate()
        pollTimer = nil
        panel?.orderOut(nil)
        panel?.contentView = nil
        panel = nil
        pillView = nil
    }
}

// MARK: - Views

private final class ClearView: NSView {
    override var isOpaque: Bool { false }
    override var wantsUpdateLayer: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class WaveformPillView: NSView {
    var bars: [CGFloat] = Array(repeating: 0.08, count: 16) {
        didSet { needsDisplay = true }
    }

    private let cornerRadius: CGFloat = 12

    override var isOpaque: Bool { false }
    override var wantsDefaultClipping: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
        // Soft drop shadow that follows the rounded path (not the panel bounds).
        shadow = {
            let s = NSShadow()
            s.shadowColor = NSColor.black.withAlphaComponent(0.40)
            s.shadowBlurRadius = 10
            s.shadowOffset = NSSize(width: 0, height: -3)
            return s
        }()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        defer { ctx.restoreGState() }

        let pill = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: pill, xRadius: cornerRadius, yRadius: cornerRadius)

        // Icon-matched navy fill.
        let navyTop = NSColor(calibratedRed: 0.08, green: 0.22, blue: 0.26, alpha: 1)
        let navyBottom = NSColor(calibratedRed: 0.04, green: 0.14, blue: 0.18, alpha: 1)
        let gradient = NSGradient(starting: navyTop, ending: navyBottom)
        gradient?.draw(in: path, angle: 270)

        // Hairline edge.
        NSColor.white.withAlphaComponent(0.08).setStroke()
        path.lineWidth = 0.5
        path.stroke()

        drawWaveform(in: pill.insetBy(dx: 16, dy: 12))
    }

    private func drawWaveform(in rect: NSRect) {
        let count = max(bars.count, 1)
        let spacing: CGFloat = 3.5
        let barWidth: CGFloat = 1.75
        let totalWidth = CGFloat(count) * barWidth + CGFloat(count - 1) * spacing
        var x = rect.midX - totalWidth / 2

        let mintHot = NSColor(calibratedRed: 0.78, green: 1.0, blue: 0.96, alpha: 1)
        let mint = NSColor(calibratedRed: 0.55, green: 0.95, blue: 0.88, alpha: 1)
        let mintDim = NSColor(calibratedRed: 0.28, green: 0.62, blue: 0.58, alpha: 1)

        for level in bars {
            let height = max(3, rect.height * level)
            let barRect = NSRect(
                x: x,
                y: rect.midY - height / 2,
                width: barWidth,
                height: height
            )
            let barPath = NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2)

            // Soft glow behind the bar.
            if level > 0.1 {
                NSColor(calibratedRed: 0.55, green: 0.95, blue: 0.88, alpha: 0.35 * level).setFill()
                let glow = barRect.insetBy(dx: -1.2, dy: -1.2)
                NSBezierPath(roundedRect: glow, xRadius: (barWidth + 2.4) / 2, yRadius: (barWidth + 2.4) / 2).fill()
            }

            NSGradient(colors: [mintHot, mint, mintDim])?.draw(in: barPath, angle: 270)
            x += barWidth + spacing
        }
    }
}
