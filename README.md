# local-speech-to-text

Local speech-to-text on Apple Silicon using [whisper.cpp](https://github.com/ggml-org/whisper.cpp) and OpenAI Whisper **large-v3** GGML weights from Hugging Face.

## What's ready

| Piece | Status |
|---|---|
| `whisper-cli` (Metal on M5 Max) | installed |
| `models/ggml-large-v3.bin` (~2.9 GB) | downloaded |
| CLI: `./scripts/transcribe.sh` | ready |
| Gradio record UI | ready |
| **LocalFlow** (Wispr-style menu-bar dictation) | ready |

## LocalFlow (menu-bar dictation)

Hold **Right ⌘** → speak → release → transcript is pasted into the focused text field in *any* app.

```bash
cd macapp
./build-app.sh
open dist/LocalFlow.app
```

On first launch:
1. Allow **Microphone**
2. Grant **Accessibility** (needed for global hotkey + paste)
3. Wait a few seconds for Whisper to load (Dock app + menu bar waveform)

Menu bar item (`waveform`): status, pause/resume, permissions, quit.

Rebuild after code changes: `pkill -x LocalFlow; cd macapp && ./build-app.sh && open dist/LocalFlow.app`

## Record UI (browser)

```bash
./scripts/run-ui.sh
```

Opens http://127.0.0.1:7860 — mic **Record** or upload, then **Transcribe**.

## CLI

```bash
./scripts/transcribe.sh path/to/audio.wav
# → outputs/<name>.txt, .srt, .json
```

### Options

| Env | Default | Meaning |
|---|---|---|
| `WHISPER_MODEL` | `models/ggml-large-v3.bin` | GGML model path |
| `WHISPER_LANG` | `auto` | Language (`en`, `es`, …) or auto-detect |
| `WHISPER_OUT` | `outputs/` | Transcript output dir |
| `STT_PORT` | `7860` | Gradio UI port |
| `LOCALFLOW_MODEL` | (auto) | Override model path for LocalFlow |
| `LOCALFLOW_ROOT` | (auto) | Override project root for LocalFlow |

## Setup (already done on this machine)

```bash
brew install whisper-cpp ffmpeg
./scripts/download-model.sh   # ~2.9 GiB large-v3
uv sync                       # Gradio UI deps
```

Model source: [ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp) → `ggml-large-v3.bin`

## Benchmarks

See [reports/local-stt-eval-benchmark-2026-07-18.html](reports/local-stt-eval-benchmark-2026-07-18.html) — ~12–17× realtime on M5 Max.
