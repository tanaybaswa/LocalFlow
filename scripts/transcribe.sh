#!/usr/bin/env bash
# Transcribe audio locally with whisper.cpp (Metal on Apple Silicon).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODEL="${WHISPER_MODEL:-$ROOT/models/ggml-large-v3.bin}"
LANG="${WHISPER_LANG:-auto}"
OUT_DIR="${WHISPER_OUT:-$ROOT/outputs}"
THREADS="${WHISPER_THREADS:-8}"

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <audio-file> [extra whisper-cli args...]" >&2
  echo "env:   WHISPER_MODEL    model path (default: models/ggml-large-v3.bin)" >&2
  echo "       WHISPER_LANG     language code or 'auto' (default: auto)" >&2
  echo "       WHISPER_OUT      output directory (default: outputs/)" >&2
  echo "       WHISPER_THREADS  CPU threads (default: 8)" >&2
  exit 1
fi

AUDIO="$1"
shift

if [[ ! -f "$AUDIO" ]]; then
  echo "error: audio file not found: $AUDIO" >&2
  exit 1
fi

if [[ ! -f "$MODEL" ]]; then
  echo "error: model not found: $MODEL" >&2
  echo "run: ./scripts/download-model.sh" >&2
  exit 1
fi

if ! command -v whisper-cli >/dev/null 2>&1; then
  echo "error: whisper-cli not found. Install with: brew install whisper-cpp" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
BASE="$(basename "$AUDIO")"
STEM="${BASE%.*}"
OUT_FILE="$OUT_DIR/$STEM"

echo "model:    $MODEL"
echo "audio:    $AUDIO"
echo "language: $LANG"
echo "output:   $OUT_FILE.{txt,srt,json}"
echo

whisper-cli \
  --model "$MODEL" \
  --file "$AUDIO" \
  --language "$LANG" \
  --threads "$THREADS" \
  --print-progress \
  --output-txt \
  --output-srt \
  --output-json \
  --output-file "$OUT_FILE" \
  "$@"
