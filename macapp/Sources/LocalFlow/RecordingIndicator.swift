import AppKit

/// Floating non-activating pill — white Glow Pulse waveform (lilac/purple brand).
/// Drawn in AppKit so the panel never shows a gray rectangular chrome.
@MainActor
final class RecordingIndicator {
    static let shared = RecordingIndicator()

    /// Extra room for soft purple glow outside the pill.
    private static let panelSize = NSSize(width: 156, height: 48)
    /// Shorter, waveform-only pill.
    private static let pillSize = NSSize(width: 132, height: 34)

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
            let y = frame.minY + 28
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

// MARK: - Brand palette (#7C3AED family)

private enum Brand {
    static let violet = NSColor(calibratedRed: 0.486, green: 0.227, blue: 0.929, alpha: 1) // #7C3AED
    static let soft = NSColor(calibratedRed: 0.655, green: 0.545, blue: 0.980, alpha: 1)   // #A78BFA
    static let lilac = NSColor(calibratedRed: 0.769, green: 0.710, blue: 0.992, alpha: 1)  // #C4B5FD
    static let mist = NSColor(calibratedRed: 0.914, green: 0.835, blue: 1.0, alpha: 1)     // #E9D5FF
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
    var bars: [CGFloat] = Array(repeating: 0.08, count: 20) {
        didSet { needsDisplay = true }
    }

    private let cornerRadius: CGFloat = 17

    override var isOpaque: Bool { false }
    override var wantsDefaultClipping: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
        // Soft lilac glow following the rounded pill (not a rectangular window shadow).
        shadow = {
            let s = NSShadow()
            s.shadowColor = Brand.violet.withAlphaComponent(0.26)
            // ~25% tighter than previous blur (14 → 10.5)
            s.shadowBlurRadius = 10.5
            s.shadowOffset = NSSize(width: 0, height: 0)
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

        let pill = bounds.insetBy(dx: 1.0, dy: 1.0)
        let path = NSBezierPath(roundedRect: pill, xRadius: cornerRadius, yRadius: cornerRadius)

        // Clean white fill.
        NSColor.white.setFill()
        path.fill()

        // Subtle purple outline.
        Brand.lilac.withAlphaComponent(0.85).setStroke()
        path.lineWidth = 1.0
        path.stroke()

        // Inner hairline for polish.
        let inner = pill.insetBy(dx: 0.5, dy: 0.5)
        let innerPath = NSBezierPath(roundedRect: inner, xRadius: cornerRadius - 0.5, yRadius: cornerRadius - 0.5)
        Brand.mist.withAlphaComponent(0.55).setStroke()
        innerPath.lineWidth = 0.5
        innerPath.stroke()

        drawWaveform(in: pill.insetBy(dx: 18, dy: 8))
    }

    private func drawWaveform(in rect: NSRect) {
        let count = max(bars.count, 1)
        let spacing: CGFloat = 2.75
        let barWidth: CGFloat = 2.25
        let totalWidth = CGFloat(count) * barWidth + CGFloat(count - 1) * spacing
        var x = rect.midX - totalWidth / 2

        for level in bars {
            let height = max(2.5, rect.height * level)
            let barRect = NSRect(
                x: x,
                y: rect.midY - height / 2,
                width: barWidth,
                height: height
            )
            let barPath = NSBezierPath(
                roundedRect: barRect,
                xRadius: barWidth / 2,
                yRadius: barWidth / 2
            )

            // Soft purple glow bloom behind louder bars.
            if level > 0.12 {
                Brand.soft.withAlphaComponent(0.22 * level).setFill()
                let glow = barRect.insetBy(dx: -1.5, dy: -1.5)
                NSBezierPath(
                    roundedRect: glow,
                    xRadius: (barWidth + 3) / 2,
                    yRadius: (barWidth + 3) / 2
                ).fill()
            }

            NSGradient(colors: [Brand.lilac, Brand.soft, Brand.violet])?
                .draw(in: barPath, angle: 270)

            x += barWidth + spacing
        }
    }
}
