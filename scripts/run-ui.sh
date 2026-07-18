#!/usr/bin/env bash
# Launch the local record → transcript web UI.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ ! -f "$ROOT/models/ggml-large-v3.bin" ]]; then
  echo "error: model missing. Run ./scripts/download-model.sh" >&2
  exit 1
fi

if ! command -v whisper-cli >/dev/null 2>&1; then
  echo "error: whisper-cli not found. Install with: brew install whisper-cpp" >&2
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "error: ffmpeg not found. Install with: brew install ffmpeg" >&2
  exit 1
fi

echo "Starting UI at http://127.0.0.1:${STT_PORT:-7860}"
exec uv run python -m app.ui
