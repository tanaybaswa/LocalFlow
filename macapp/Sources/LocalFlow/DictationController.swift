import AppKit
import Foundation
import Observation

enum DictationState: Equatable {
    case idle
    case startingSidecar
    case ready
    case recording
    case transcribing
    case error(String)
}

@MainActor
@Observable
final class DictationController {
    var state: DictationState = .idle
    var lastTranscript: String = ""
    var statusMessage: String = "Starting…"
    var enabled: Bool = true {
        didSet {
            if enabled {
                hotkey.start()
            } else {
                hotkey.stop()
                if case .recording = state {
                    recorder.cancel()
                    state = sidecar.isReady ? .ready : .idle
                }
            }
            refreshStatus()
        }
    }

    let transcripts = TranscriptStore()

    private let sidecar = SidecarManager()
    private let transcription = TranscriptionService()
    private let recorder = AudioRecorder()
    private let paste = PasteService()
    private let hotkey = HotkeyMonitor()

    /// App that had focus when the user started holding Right ⌘.
    private var targetApp: NSRunningApplication?

    init() {
        hotkey.delegate = self
    }

    func bootstrap() {
        Task { await startSidecar() }
    }

    func shutdown() {
        hotkey.stop()
        recorder.cancel()
        sidecar.stop()
    }

    func startSidecar() async {
        state = .startingSidecar
        statusMessage = "Loading Whisper model…"
        do {
            try await sidecar.start()
            state = .ready
            statusMessage = "Ready — hold Right ⌘ to dictate"
            if enabled { hotkey.start() }
        } catch {
            state = .error(error.localizedDescription)
            statusMessage = error.localizedDescription
        }
    }

    private func refreshStatus() {
        switch state {
        case .ready:
            statusMessage = enabled
                ? "Ready — hold Right ⌘ to dictate"
                : "Paused — enable from menu"
        case .recording:
            let name = targetApp?.localizedName ?? "app"
            statusMessage = "Recording into \(name)… release Right ⌘"
        case .transcribing:
            statusMessage = "Transcribing…"
        case .startingSidecar:
            statusMessage = "Loading Whisper model…"
        case .idle:
            statusMessage = "Idle"
        case .error(let msg):
            statusMessage = msg
        }
    }

    private func captureTargetApp() {
        let front = NSWorkspace.shared.frontmostApplication
        if let front, front.bundleIdentifier != Bundle.main.bundleIdentifier {
            targetApp = front
        } else if targetApp == nil || targetApp?.isTerminated == true {
            // Fall back to any other running app that was recently active — keep last good target.
            targetApp = NSWorkspace.shared.runningApplications.first {
                $0.activationPolicy == .regular
                    && $0.bundleIdentifier != Bundle.main.bundleIdentifier
                    && !$0.isTerminated
            }
        }
        NSLog("LocalFlow: target app = \(targetApp?.localizedName ?? "nil") (\(targetApp?.bundleIdentifier ?? "-"))")
    }

    private func beginRecording() {
        guard enabled else { return }
        guard case .ready = state else { return }
        guard Permissions.microphoneGranted else {
            state = .error("Microphone permission required")
            statusMessage = "Grant Microphone access in System Settings"
            return
        }
        captureTargetApp()
        do {
            try recorder.start()
            state = .recording
            refreshStatus()
            RecordingIndicator.shared.show()
        } catch {
            state = .error(error.localizedDescription)
            refreshStatus()
        }
    }

    private func finishRecording() {
        guard case .recording = state else { return }
        RecordingIndicator.shared.hide()
        state = .transcribing
        refreshStatus()

        let pasteTarget = targetApp

        Task {
            do {
                let wav = try recorder.stop()
                let text = try await transcription.transcribe(wavData: wav)
                lastTranscript = text
                transcripts.add(text)
                do {
                    try await paste.paste(text, into: pasteTarget)
                    state = .ready
                    let dest = pasteTarget?.localizedName ?? "app"
                    statusMessage = "Pasted into \(dest): \(text.prefix(50))\(text.count > 50 ? "…" : "")"
                } catch {
                    state = .ready
                    statusMessage = "Saved (paste failed): \(error.localizedDescription)"
                }
            } catch {
                recorder.cancel()
                state = .ready
                statusMessage = "Error: \(error.localizedDescription)"
            }
        }
    }

    private func cancelRecording() {
        guard case .recording = state else { return }
        recorder.cancel()
        RecordingIndicator.shared.hide()
        state = .ready
        statusMessage = "Cancelled"
    }
}

extension DictationController: HotkeyMonitorDelegate {
    func hotkeyDidBeginHold() { beginRecording() }
    func hotkeyDidEndHold() { finishRecording() }
    func hotkeyDidCancel() { cancelRecording() }
}
