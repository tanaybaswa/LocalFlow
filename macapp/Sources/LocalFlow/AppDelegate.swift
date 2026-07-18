import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = DictationController()
    private var statusItem: StatusItemController?
    private var historyWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Regular Dock app (history window) + menu bar status item.
        NSApp.setActivationPolicy(.regular)

        let status = StatusItemController(controller: controller)
        status.install()
        statusItem = status

        openHistoryWindow()

        if !Permissions.microphoneGranted {
            Task { _ = await Permissions.requestMicrophone() }
        }
        // Never auto-prompt Accessibility here — it opens System Settings and is unreliable
        // with ad-hoc signed rebuilds. User grants via Permissions window when needed.

        controller.bootstrap()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.shutdown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openHistoryWindow()
        }
        return true
    }

    func openHistoryWindow() {
        if let historyWindow {
            historyWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = HistoryView(controller: controller)
        let host = NSHostingController(rootView: root)
        let win = NSWindow(contentViewController: host)
        win.title = "LocalFlow"
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        win.setContentSize(NSSize(width: 480, height: 560))
        win.center()
        win.isReleasedWhenClosed = false
        // Show history without forcing LocalFlow to steal keyboard focus forever.
        win.orderFront(nil)
        historyWindow = win
    }
}
