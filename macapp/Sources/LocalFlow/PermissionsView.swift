import AppKit
import SwiftUI

@MainActor
final class PermissionsWindow {
    static let shared = PermissionsWindow()
    private var window: NSWindow?

    func show(controller: DictationController) {
        let root = PermissionsView(controller: controller)
        let host = NSHostingController(rootView: root)
        let win = NSWindow(contentViewController: host)
        win.title = "LocalFlow Permissions"
        win.styleMask = [.titled, .closable]
        win.setContentSize(NSSize(width: 440, height: 380))
        win.center()
        win.isReleasedWhenClosed = false
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }
}

struct PermissionsView: View {
    let controller: DictationController
    @State private var micOK = Permissions.microphoneGranted
    @State private var axOK = Permissions.accessibilityTrusted

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("LocalFlow permissions")
                .font(.title3.weight(.semibold))

            Text("Hold Right ⌘ to dictate. Auto-paste needs Accessibility.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            permissionRow(
                title: "Microphone",
                ok: micOK,
                actionTitle: micOK ? "Granted" : "Request…"
            ) {
                Task {
                    _ = await Permissions.requestMicrophone()
                    micOK = Permissions.microphoneGranted
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: axOK ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(axOK ? .green : .orange)
                    Text("Accessibility")
                    Spacer()
                    Text(axOK ? "Trusted" : "Not trusted by macOS")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Open Settings") {
                        Permissions.openAccessibilitySettings()
                    }
                    Button("Request Access…") {
                        Permissions.promptAccessibility()
                        axOK = Permissions.accessibilityTrusted
                    }
                }
                Text("After rebuilding LocalFlow, macOS may keep an old Accessibility entry. Toggle LocalFlow OFF → ON, or remove it and re-enable this build.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))

            Spacer()

            HStack {
                Button("Refresh") {
                    micOK = Permissions.microphoneGranted
                    axOK = Permissions.accessibilityTrusted
                }
                Spacer()
                Button("Reload Whisper") {
                    Task { await controller.startSidecar() }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func permissionRow(title: String, ok: Bool, actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(ok ? .green : .orange)
            Text(title)
            Spacer()
            Button(actionTitle, action: action)
                .disabled(ok)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
    }
}
