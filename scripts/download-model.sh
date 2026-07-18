#!/usr/bin/env bash
# Download Whisper GGML weights for whisper.cpp via the Hugging Face CLI.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODEL_NAME="${1:-ggml-large-v3.bin}"
REPO="ggerganov/whisper.cpp"
OUT_DIR="$ROOT/models"

if ! command -v hf >/dev/null 2>&1; then
  echo "error: hf CLI not found. Install with: curl -LsSf https://hf.co/cli/install.sh | bash -s" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
echo "Downloading $REPO / $MODEL_NAME → $OUT_DIR"
hf download "$REPO" "$MODEL_NAME" --local-dir "$OUT_DIR"
echo "Done: $OUT_DIR/$MODEL_NAME"
