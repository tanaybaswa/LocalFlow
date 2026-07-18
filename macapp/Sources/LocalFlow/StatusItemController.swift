import AppKit
import SwiftUI

@MainActor
final class StatusItemController {
    private var statusItem: NSStatusItem?
    private let controller: DictationController
    private var menu: NSMenu?
    private var observationTask: Task<Void, Never>?

    init(controller: DictationController) {
        self.controller = controller
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "LocalFlow")
            button.image?.isTemplate = true
            button.toolTip = "LocalFlow"
        }
        statusItem = item
        rebuildMenu()
        observationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 400_000_000)
                self?.rebuildMenu()
                self?.updateIcon()
            }
        }
    }

    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        let name: String
        switch controller.state {
        case .recording: name = "waveform.badge.mic"
        case .transcribing, .startingSidecar: name = "hourglass"
        case .error: name = "exclamationmark.triangle"
        default: name = controller.enabled ? "waveform" : "waveform.slash"
        }
        button.image = NSImage(systemSymbolName: name, accessibilityDescription: "LocalFlow")
        button.image?.isTemplate = true
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let status = NSMenuItem(title: controller.statusMessage, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let toggle = NSMenuItem(
            title: controller.enabled ? "Pause Dictation" : "Resume Dictation",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        toggle.target = self
        menu.addItem(toggle)

        let history = NSMenuItem(title: "Show Transcripts", action: #selector(showHistory), keyEquivalent: "l")
        history.target = self
        menu.addItem(history)

        let perms = NSMenuItem(title: "Check Permissions…", action: #selector(showPermissions), keyEquivalent: "")
        perms.target = self
        menu.addItem(perms)

        if !controller.lastTranscript.isEmpty {
            menu.addItem(.separator())
            let preview = String(controller.lastTranscript.prefix(80))
            let last = NSMenuItem(title: "Last: \(preview)", action: #selector(copyLast), keyEquivalent: "")
            last.target = self
            menu.addItem(last)
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit LocalFlow", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem?.menu = menu
        self.menu = menu
    }

    @objc private func toggleEnabled() {
        controller.enabled.toggle()
        rebuildMenu()
        updateIcon()
    }

    @objc private func showHistory() {
        (NSApp.delegate as? AppDelegate)?.openHistoryWindow()
    }

    @objc private func showPermissions() {
        PermissionsWindow.shared.show(controller: controller)
    }

    @objc private func copyLast() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(controller.lastTranscript, forType: .string)
    }

    @objc private func quit() {
        controller.shutdown()
        NSApp.terminate(nil)
    }
}
