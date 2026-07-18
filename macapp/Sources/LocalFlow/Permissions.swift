import AppKit
import ApplicationServices
import AVFoundation

enum Permissions {
    static var microphoneGranted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Silent check — never opens System Settings.
    static var accessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestMicrophone() async -> Bool {
        await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                cont.resume(returning: granted)
            }
        }
    }

    /// Opens the Accessibility prompt / Settings. Call ONLY from an explicit user action
    /// (e.g. Permissions window button). Never call from paste/hotkey paths — with ad-hoc
    /// builds `AXIsProcessTrusted()` can be false even when the toggle looks ON, which
    /// would spam System Settings on every dictate.
    @discardableResult
    static func promptAccessibility() -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let opts = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    /// Opens System Settings → Accessibility without the blocking TCC dialog.
    static func openAccessibilitySettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
        ]
        for s in urls {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }

    static var allReady: Bool {
        microphoneGranted && accessibilityTrusted
    }
}
