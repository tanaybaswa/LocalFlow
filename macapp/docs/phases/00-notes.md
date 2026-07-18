# LocalFlow — phase notes

## 0 Decisions
- Bundle ID: `com.tanaybaswa.localflow`
- Menu-bar (`LSUIElement`), no Dock
- Sandbox OFF (global hotkeys + Accessibility paste + sidecar)
- Ad-hoc signing
- Model: existing `models/ggml-large-v3.bin`
- Engine: Homebrew `whisper-server` sidecar on `127.0.0.1:12321`
- Hotkey: hold Left ⌘ (cancel on other key)

## 1 Scaffold
SPM + `build-app.sh` + Info.plist.

## 2–4 Logic
SidecarManager → TranscriptionService → AudioRecorder → HotkeyMonitor → PasteService → DictationController.
