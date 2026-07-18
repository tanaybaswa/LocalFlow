# LocalFlow

**Private, on-device dictation for macOS.** Hold Right ⌘, speak, release — your words paste into whatever app you’re in. Audio never leaves your machine.

Built on [whisper.cpp](https://github.com/ggml-org/whisper.cpp) + OpenAI Whisper **large-v3**, tuned for Apple Silicon (Metal). On an M5 Max it runs about **12–17× realtime**.

## Demo

Watch a quick walkthrough: **[LocalFlow demo (Loom)](https://www.loom.com/share/38975bfa994442c8a5872bc2e6ebad89)**

---

## Why it exists

Cloud dictation is convenient — and it uploads your voice. LocalFlow keeps speech recognition local:

- **Privacy** — mic audio is transcribed on-device with a local Whisper server
- **Anywhere** — works in Slack, Cursor, browsers, Notes… wherever the caret is
- **Fast enough to feel native** — warm sidecar model, push-to-talk UX
- **Open stack** — Homebrew whisper.cpp, GGML weights from Hugging Face, Swift menu-bar app

> Think Wispr Flow–style dictation, but the model lives on your Mac.

---

## Features

| | |
|---|---|
| **Push-to-talk** | Hold **Right ⌘** to record, release to transcribe & paste |
| **Live waveform** | White Glow Pulse pill with lilac/purple amplitude bars while you speak |
| **Cross-app paste** | Clipboard + System Events ⌘V into the app you started in |
| **History** | Dock window with past transcripts and paste diagnostics |
| **Also included** | Gradio browser UI + CLI for file transcription |

---

## Quick start (macOS Apple Silicon)

### 1. Dependencies

```bash
brew install whisper-cpp ffmpeg
# Optional — Gradio UI only:
# curl -LsSf https://astral.sh/uv/install.sh | sh
```

### 2. Clone & download the model (~2.9 GB)

```bash
git clone https://github.com/tanaybaswa/LocalFlow.git
cd LocalFlow
./scripts/download-model.sh   # → models/ggml-large-v3.bin
```

Model source: [`ggerganov/whisper.cpp`](https://huggingface.co/ggerganov/whisper.cpp) → `ggml-large-v3.bin`

### 3. Build & launch LocalFlow

```bash
cd macapp
./build-app.sh
open dist/LocalFlow.app
```

On first launch:

1. Allow **Microphone**
2. Grant **Accessibility** (global hotkey + focus)
3. Allow **Automation → System Events** when prompted (paste)
4. Wait until the menu bar status says **Ready**

Then click any text field → **hold Right ⌘** → speak → **release**.

Cancel mid-hold: press any other key while still holding Right ⌘.

Rebuild after code changes:

```bash
pkill -x LocalFlow
cd macapp && ./build-app.sh && open dist/LocalFlow.app
```

---

## Other ways to transcribe

### Browser UI (Gradio)

```bash
uv sync
./scripts/run-ui.sh
# → http://127.0.0.1:7860
```

### CLI

```bash
./scripts/transcribe.sh path/to/audio.wav
# → outputs/<name>.txt, .srt, .json
```

---

## How LocalFlow works

```text
Right ⌘ hold
    → capture focused app + AX element
    → record mic (PCM16 WAV) + live RMS waveform
Right ⌘ release
    → POST WAV to local whisper-server (127.0.0.1:12321)
    → clipboard + one System Events ⌘V into the captured target
```

Key design choice: **a single paste path**. Earlier multi-path injectors (AX + CGEvent + AppleScript together) caused duplicate pastes in apps like ChatGPT/Claude. The current path is clipboard → restore focus → one System Events keystroke.

Details for contributors: [`reports/localflow-product-handoff-2026-07-18.html`](reports/localflow-product-handoff-2026-07-18.html)

---

## Benchmarks

On Apple **M5 Max (36 GB)**, Whisper large-v3 via whisper.cpp / Metal sustained roughly **12–17× realtime** across lecture, podcast, and tutorial clips.

Full write-up: [`reports/local-stt-eval-benchmark-2026-07-18.html`](reports/local-stt-eval-benchmark-2026-07-18.html)

---

## Configuration

| Env | Default | Meaning |
|---|---|---|
| `WHISPER_MODEL` | `models/ggml-large-v3.bin` | GGML model path (CLI / Gradio) |
| `WHISPER_LANG` | `auto` | Language code or auto-detect |
| `WHISPER_OUT` | `outputs/` | Transcript output directory |
| `STT_PORT` | `7860` | Gradio port |
| `LOCALFLOW_MODEL` | (auto) | Override model path for LocalFlow |
| `LOCALFLOW_ROOT` | (auto) | Override project root for LocalFlow |
| `LOCALFLOW_WHISPER_SERVER` | Homebrew path | Override `whisper-server` binary |

---

## Repo layout

```text
├── macapp/                 # LocalFlow Swift app (SPM + build-app.sh)
├── app/ui.py               # Gradio UI
├── scripts/                # download-model, transcribe, run-ui
├── models/                 # ggml weights (gitignored — download script)
├── reports/                # benchmark + handoff HTML
└── samples/                # optional local audio (gitignored)
```

---

## Requirements & limits

- **macOS 14+**, Apple Silicon recommended (Metal)
- Homebrew `whisper-cpp` + `ffmpeg`
- ~**2.9 GB** disk for large-v3 (not committed to git)
- Accessibility + Automation permissions for auto-paste
- Ad-hoc signed builds may need re-granting Accessibility after rebuilds

Not a polished App Store product yet — it’s a solid local experiment that already works as daily dictation.

---

## License

Personal / experimental project. Whisper model weights and whisper.cpp retain their upstream licenses. See [OpenAI Whisper](https://github.com/openai/whisper) and [whisper.cpp](https://github.com/ggml-org/whisper.cpp) for details.
