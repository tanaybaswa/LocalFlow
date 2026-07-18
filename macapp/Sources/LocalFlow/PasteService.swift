import AppKit
import ApplicationServices

enum PasteError: LocalizedError {
    case emptyText
    case automationFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyText: return "Nothing to paste."
        case .automationFailed(let detail):
            return "System Events could not paste: \(detail). The transcript remains on the clipboard."
        }
    }
}

@MainActor
final class PasteTarget {
    let application: NSRunningApplication?
    let focusedElement: AXUIElement?

    var applicationName: String {
        application?.localizedName ?? "focused app"
    }

    private init(application: NSRunningApplication?, focusedElement: AXUIElement?) {
        self.application = application
        self.focusedElement = focusedElement
    }

    static func capture() -> PasteTarget {
        let localBundleID = Bundle.main.bundleIdentifier
        let frontmost = NSWorkspace.shared.frontmostApplication
        let application = frontmost?.bundleIdentifier == localBundleID ? nil : frontmost

        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        let focusedElement: AXUIElement?
        if AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success, let focusedValue {
            focusedElement = (focusedValue as! AXUIElement)
        } else {
            focusedElement = nil
        }

        return PasteTarget(application: application, focusedElement: focusedElement)
    }
}

struct PasteResult: Sendable {
    let targetApplication: String
    let method: String
}

/// Exactly one insertion path: clipboard → restore captured focus → System Events ⌘V.
@MainActor
final class PasteService {
    func paste(_ text: String, into target: PasteTarget?) async throws -> PasteResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PasteError.emptyText }

        try await waitForModifiersClear()

        let board = NSPasteboard.general
        let saved = snapshotPasteboard(board)
        board.clearContents()
        board.declareTypes([.string], owner: nil)
        board.setString(trimmed, forType: .string)
        await restoreFocus(to: target)
        try await Task.sleep(nanoseconds: 120_000_000)

        do {
            try Self.pasteOnceViaSystemEvents()
        } catch {
            // Leave the transcript on the clipboard so manual ⌘V still works.
            throw error
        }

        try await Task.sleep(nanoseconds: 900_000_000)
        restorePasteboard(board, saved: saved)

        let appName = target?.applicationName
            ?? NSWorkspace.shared.frontmostApplication?.localizedName
            ?? "focused app"
        NSLog("LocalFlow paste: one System Events paste delivered to \(appName)")
        return PasteResult(targetApplication: appName, method: "System Events")
    }

    private func restoreFocus(to target: PasteTarget?) async {
        guard let target else { return }

        if let app = target.application, !app.isTerminated {
            let isFrontmost =
                NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
            if !isFrontmost {
                _ = app.activate()
                for _ in 0..<30 {
                    if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
                        break
                    }
                    try? await Task.sleep(nanoseconds: 20_000_000)
                }
            }
        }

        if let element = target.focusedElement {
            _ = AXUIElementSetAttributeValue(
                element,
                kAXFocusedAttribute as CFString,
                kCFBooleanTrue
            )
        }
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

    private static func pasteOnceViaSystemEvents() throws {
        let source = """
        tell application "System Events"
            keystroke "v" using command down
        end tell
        """
        var error: NSDictionary?
        guard let appleScript = NSAppleScript(source: source) else {
            throw PasteError.automationFailed("AppleScript could not be created")
        }
        _ = appleScript.executeAndReturnError(&error)
        if let error {
            NSLog("LocalFlow AppleScript paste error: \(error)")
            let message = error[NSAppleScript.errorMessage] as? String
                ?? error.description
            throw PasteError.automationFailed(message)
        }
    }
}
