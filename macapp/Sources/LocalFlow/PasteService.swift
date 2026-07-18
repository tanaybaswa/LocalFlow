import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum PasteError: LocalizedError {
    case emptyText

    var errorDescription: String? {
        switch self {
        case .emptyText: return "Nothing to paste."
        }
    }
}

/// Paste transcript into the app that was focused when dictation started.
///
/// Notes/TextEdit often accept AX insert. Chrome, Slack, Cursor, VS Code, etc. need
/// clipboard + ⌘V, and the target app must be frontmost — otherwise events land on LocalFlow.
@MainActor
final class PasteService {
    func paste(_ text: String, into targetApp: NSRunningApplication?) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PasteError.emptyText }

        try await waitForModifiersClear()

        // Critical: put focus back on the app the user was typing in.
        await activateTarget(targetApp)

        let board = NSPasteboard.general
        let saved = snapshotPasteboard(board)
        board.clearContents()
        board.declareTypes([.string], owner: nil)
        board.setString(trimmed, forType: .string)
        try await Task.sleep(nanoseconds: 120_000_000)

        // 1) Native AX insert (Notes, TextEdit, many AppKit fields)
        if Self.tryAXInsert(trimmed) {
            NSLog("LocalFlow paste: AX insert OK into \(targetApp?.localizedName ?? "?")")
            try await Task.sleep(nanoseconds: 350_000_000)
            restorePasteboard(board, saved: saved)
            return
        }

        // 2) Universal path: clipboard ⌘V (Electron / browsers / most apps)
        NSLog("LocalFlow paste: AX unsupported — using ⌘V into \(targetApp?.localizedName ?? "frontmost") pid=\(targetApp?.processIdentifier ?? -1)")
        Self.postCommandVMaccyStyle()
        try await Task.sleep(nanoseconds: 60_000_000)
        _ = Self.pasteViaAppleScript(targetPID: targetApp?.processIdentifier)

        // Electron apps are slow to read the pasteboard.
        try await Task.sleep(nanoseconds: 700_000_000)
        restorePasteboard(board, saved: saved)
    }

    private func activateTarget(_ app: NSRunningApplication?) async {
        guard let app, !app.isTerminated else { return }
        // Don't activate ourselves.
        if app.bundleIdentifier == Bundle.main.bundleIdentifier { return }

        // If the target is already frontmost, do NOT call activate().
        // activate() often moves keyboard focus from a text field (e.g. Cursor chat)
        // to the window chrome — then ⌘V lands nowhere useful.
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
            NSLog("LocalFlow paste: \(app.localizedName ?? "app") already frontmost — preserving field focus")
            try? await Task.sleep(nanoseconds: 40_000_000)
            return
        }

        NSLog("LocalFlow paste: activating \(app.localizedName ?? "app")")
        _ = app.activate()
        // Wait until macOS reports it frontmost (or timeout).
        for _ in 0..<25 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
                break
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        // Extra beat for focus / caret to settle inside the text field.
        try? await Task.sleep(nanoseconds: 80_000_000)
    }

    private func waitForModifiersClear() async throws {
        for _ in 0..<40 {
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

        // Must look like an editable field.
        var roleRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(focused, kAXRoleAttribute as CFString, &roleRef) == .success,
           let role = roleRef as? String {
            let editableRoles: Set<String> = [
                "AXTextField", "AXTextArea", "AXComboBox", "AXSearchField",
            ]
            // Many web fields report AXGroup / AXWebArea — skip AX insert for those.
            if !editableRoles.contains(role) && role != "AXTextArea" {
                // Still try selected-text; some native roles differ.
            }
        }

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
            // Avoid clobbering huge documents via full AXValue replace unless it looks like a field.
            if existing.count < 20_000 {
                if AXUIElementSetAttributeValue(
                    focused,
                    kAXValueAttribute as CFString,
                    (existing + text) as CFTypeRef
                ) == .success {
                    return true
                }
            }
        }
        return false
    }

    private static func postCommandVMaccyStyle() {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let cmdFlag = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x000008)
        let keyV = CGKeyCode(kVK_ANSI_V)

        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
        else { return }

        keyDown.flags = cmdFlag
        keyUp.flags = cmdFlag
        // Session + annotated taps — both used by working clipboard managers.
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }

    @discardableResult
    private static func pasteViaAppleScript(targetPID: pid_t?) -> Bool {
        let script: String
        if let pid = targetPID, pid > 0 {
            script = """
            tell application "System Events"
                set procs to (every process whose unix id is \(pid))
                if (count of procs) > 0 then
                    set frontmost of item 1 of procs to true
                    delay 0.05
                end if
                keystroke "v" using command down
            end tell
            """
        } else {
            script = """
            tell application "System Events"
                keystroke "v" using command down
            end tell
            """
        }
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: script) else { return false }
        _ = appleScript.executeAndReturnError(&error)
        if let error {
            NSLog("LocalFlow AppleScript paste error: \(error)")
            return false
        }
        return true
    }
}
