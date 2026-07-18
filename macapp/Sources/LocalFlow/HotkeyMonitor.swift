import AppKit

@MainActor
protocol HotkeyMonitorDelegate: AnyObject {
    func hotkeyDidBeginHold()
    func hotkeyDidEndHold()
    func hotkeyDidCancel()
}

/// Hold Right ⌘ to record. Cancel if another key is pressed while held.
@MainActor
final class HotkeyMonitor {
    weak var delegate: HotkeyMonitorDelegate?

    private var flagsMonitor: Any?
    private var keyMonitor: Any?
    private var localFlagsMonitor: Any?
    private var localKeyMonitor: Any?

    private var holdingRightCommand = false
    private var cancelledThisHold = false
    private var holdStartedAt: Date?
    private let minimumHold: TimeInterval = 0.35

    /// Right Command keyCode (Carbon kVK_RightCommand).
    private let rightCommandKeyCode: UInt16 = 54

    func start() {
        stop()
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in self?.handleFlags(event) }
        }
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in self?.handleKeyDown(event) }
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in self?.handleFlags(event) }
            return event
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in self?.handleKeyDown(event) }
            return event
        }
    }

    func stop() {
        [flagsMonitor, keyMonitor, localFlagsMonitor, localKeyMonitor].compactMap { $0 }.forEach {
            NSEvent.removeMonitor($0)
        }
        flagsMonitor = nil
        keyMonitor = nil
        localFlagsMonitor = nil
        localKeyMonitor = nil
        holdingRightCommand = false
        cancelledThisHold = false
        holdStartedAt = nil
    }

    private func handleFlags(_ event: NSEvent) {
        guard event.keyCode == rightCommandKeyCode else { return }

        let cmdDown = event.modifierFlags.contains(.command)
        if cmdDown && !holdingRightCommand {
            holdingRightCommand = true
            cancelledThisHold = false
            holdStartedAt = Date()
            delegate?.hotkeyDidBeginHold()
        } else if !cmdDown && holdingRightCommand {
            let started = holdStartedAt
            holdingRightCommand = false
            holdStartedAt = nil
            if cancelledThisHold {
                cancelledThisHold = false
                return
            }
            if let started, Date().timeIntervalSince(started) < minimumHold {
                delegate?.hotkeyDidCancel()
                return
            }
            delegate?.hotkeyDidEndHold()
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        guard holdingRightCommand else { return }
        let mods: Set<UInt16> = [54, 55, 56, 58, 59, 60, 61, 62, 63]
        if mods.contains(event.keyCode) { return }
        cancelledThisHold = true
        holdingRightCommand = false
        holdStartedAt = nil
        delegate?.hotkeyDidCancel()
    }
}
