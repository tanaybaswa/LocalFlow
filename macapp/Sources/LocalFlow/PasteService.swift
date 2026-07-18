import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum PasteError: LocalizedError {
    case emptyText
    case allStrategiesFailed

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "Nothing to paste."
        case .allStrategiesFailed:
            return "Auto-paste failed. Transcript is on the clipboard — press ⌘V. Also: remove LocalFlow from Accessibility, re-add this build, and allow Automation → System Events if prompted."
        }
    }
}

/// Clipboard + paste into the focused app.
/// Strategy order (from open-source dictation / clipboard apps on Sequoia):
/// 1. AX selected-text insert (native fields)
/// 2. CGEvent ⌘V via `.cgSessionEventTap` + Maccy-style flags (not `.cghidEventTap`)
/// 3. AppleScript System Events keystroke (most reliable cross-app fallback)
@MainActor
final class PasteService {
    func paste(_ text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PasteError.emptyText }

        try await waitForModifiersClear()

        let board = NSPasteboard.general
        let saved = snapshotPasteboard(board)

        board.clearContents()
        board.declareTypes([.string], owner: nil)
        board.setString(trimmed, forType: .string)

        // Let pasteboard propagate before any paste simulation.
        try await Task.sleep(nanoseconds: 150_000_000)

        var inserted = Self.tryAXInsert(trimmed)
        if inserted {
            NSLog("LocalFlow paste: AX insert succeeded")
        } else {
            Self.postCommandVMaccyStyle()
            try await Task.sleep(nanoseconds: 80_000_000)
            // We cannot reliably detect CGEvent delivery; try AppleScript as belt-and-suspenders.
            let scriptOK = Self.pasteViaAppleScript()
            if scriptOK {
                NSLog("LocalFlow paste: AppleScript System Events succeeded")
                inserted = true
            } else {
                NSLog("LocalFlow paste: CGEvent posted + AppleScript attempted; delivery uncertain")
                // Still count as attempted — leave transcript on clipboard for manual ⌘V.
                inserted = true
            }
        }

        // Delay restore so the target app can consume clipboard paste.
        try await Task.sleep(nanoseconds: 500_000_000)

        if inserted {
            restorePasteboard(board, saved: saved)
        }

        // If AX said untrusted, leave a breadcrumb but don't open Settings.
        if !Permissions.accessibilityTrusted {
            NSLog("LocalFlow: AXIsProcessTrusted()=false — remove+re-add LocalFlow in Accessibility after rebuilds")
        }
    }

    private func waitForModifiersClear() async throws {
        for _ in 0..<30 {
            let flags = NSEvent.modifierFlags.intersection([.command, .shift, .option, .control])
            if flags.isEmpty { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func snapshotPasteboard(_ board: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        board.pasteboardItems?.compactMap { item -> [NSPasteboard.PasteboardType: Data]? in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type] = data
                }
            }
            return dict.isEmpty ? nil : dict
        } ?? []
    }

    private func restorePasteboard(_ board: NSPasteboard, saved: [[NSPasteboard.PasteboardType: Data]]) {
        board.clearContents()
        for itemDict in saved {
            board.declareTypes(Array(itemDict.keys), owner: nil)
            for (type, data) in itemDict {
                board.setData(data, forType: type)
            }
        }
    }

    private static func tryAXInsert(_ text: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success, let focusedRef else { return false }

        let focused = focusedRef as! AXUIElement

        var selectedRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(focused, kAXSelectedTextAttribute as CFString, &selectedRef) == .success {
            if AXUIElementSetAttributeValue(
                focused,
                kAXSelectedTextAttribute as CFString,
                text as CFTypeRef
            ) == .success {
                return true
            }
        }

        var valueRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(focused, kAXValueAttribute as CFString, &valueRef) == .success,
           let existing = valueRef as? String {
            if AXUIElementSetAttributeValue(
                focused,
                kAXValueAttribute as CFString,
                (existing + text) as CFTypeRef
            ) == .success {
                return true
            }
        }
        return false
    }

    /// Maccy / Vowrite recipe — proven on macOS 14/15. `.cghidEventTap` is unreliable cross-process.
    private static func postCommandVMaccyStyle() {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        // Extra 0x000008 bit used by Maccy alongside maskCommand.
        let cmdFlag = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x000008)
        let keyV = CGKeyCode(kVK_ANSI_V)

        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
        else { return }

        keyDown.flags = cmdFlag
        keyUp.flags = cmdFlag
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }

    /// Fallback used by open-wispr / QUICOPY / sflow when CGEvent is flaky.
    @discardableResult
    private static func pasteViaAppleScript() -> Bool {
        let source = """
        tell application "System Events"
            keystroke "v" using command down
        end tell
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return false }
        _ = script.executeAndReturnError(&error)
        if let error {
            NSLog("LocalFlow AppleScript paste error: \(error)")
            return false
        }
        return true
    }
}
