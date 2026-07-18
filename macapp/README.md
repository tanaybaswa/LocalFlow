# LocalFlow

Menu-bar + Dock dictation app (Wispr Flow–style) for macOS.

## Use

```bash
./build-app.sh
open dist/LocalFlow.app
```

1. Grant **Microphone** + **Accessibility** when prompted (menu → Check Permissions…)
2. Wait until status says **Ready — hold Right ⌘ to dictate**
3. Click into any text field → **hold Right ⌘** → speak → **release**
4. Transcript auto-pastes and appears in the history window

Cancel: press any other key while still holding Right ⌘.

## Architecture

- `SidecarManager` — keeps `whisper-server` warm on `127.0.0.1:12321` with `models/ggml-large-v3.bin`
- `AudioRecorder` — mic → mono PCM16 WAV
- `HotkeyMonitor` — Right ⌘ hold / release / cancel
- `TranscriptionService` — `POST /inference` multipart
- `PasteService` — clipboard + AX insert + synthetic ⌘V
- `TranscriptStore` — persisted history for the Dock window

## Requirements

- Homebrew `whisper-cpp` (`whisper-server`) and `ffmpeg`
- Model at `../models/ggml-large-v3.bin` (project root)
- **Accessibility** must be ON for LocalFlow or auto-paste will fail (transcript still saved)
