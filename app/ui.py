"""Local speech-to-text UI: record or upload audio → Whisper large-v3 transcript."""

from __future__ import annotations

import os
import subprocess
import tempfile
import time
from pathlib import Path

import gradio as gr

ROOT = Path(__file__).resolve().parent.parent
MODEL = Path(os.environ.get("WHISPER_MODEL", ROOT / "models" / "ggml-large-v3.bin"))
LANG = os.environ.get("WHISPER_LANG", "auto")
THREADS = os.environ.get("WHISPER_THREADS", "8")
OUT_DIR = Path(os.environ.get("WHISPER_OUT", ROOT / "outputs"))


def _ensure_wav(audio_path: str) -> Path:
    """Convert any Gradio audio path to 16 kHz mono WAV for whisper-cli."""
    src = Path(audio_path)
    if src.suffix.lower() == ".wav":
        return src

    dst = Path(tempfile.mkstemp(suffix=".wav", prefix="stt_")[1])
    subprocess.run(
        [
            "ffmpeg",
            "-y",
            "-i",
            str(src),
            "-ar",
            "16000",
            "-ac",
            "1",
            "-c:a",
            "pcm_s16le",
            str(dst),
        ],
        check=True,
        capture_output=True,
    )
    return dst


def transcribe(audio_path: str | None) -> tuple[str, str]:
    if not audio_path:
        return "", "Record or upload audio first."

    if not MODEL.is_file():
        return "", f"Model not found: {MODEL}\nRun ./scripts/download-model.sh"

    if not Path(audio_path).is_file():
        return "", f"Audio file missing: {audio_path}"

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    stem = f"ui_{int(time.time())}"
    out_base = OUT_DIR / stem
    wav = _ensure_wav(audio_path)

    try:
        proc = subprocess.run(
            [
                "whisper-cli",
                "--model",
                str(MODEL),
                "--file",
                str(wav),
                "--language",
                LANG,
                "--threads",
                THREADS,
                "--no-prints",
                "--output-txt",
                "--output-file",
                str(out_base),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
    finally:
        if wav != Path(audio_path) and wav.exists():
            wav.unlink(missing_ok=True)

    txt_path = Path(f"{out_base}.txt")
    if proc.returncode != 0 or not txt_path.is_file():
        err = (proc.stderr or proc.stdout or "whisper-cli failed").strip()
        return "", err

    text = txt_path.read_text(encoding="utf-8").strip()
    meta = f"Saved to {txt_path.name} · model {MODEL.name} · lang={LANG}"
    return text, meta


def build_ui() -> gr.Blocks:
    with gr.Blocks(title="Local Speech to Text") as demo:
        gr.Markdown(
            """
            # Local Speech to Text
            Record from your mic or upload a file. Runs **Whisper large-v3** on-device via whisper.cpp (Metal).
            """
        )
        with gr.Row():
            audio = gr.Audio(
                sources=["microphone", "upload"],
                type="filepath",
                label="Audio",
                format="wav",
            )
        with gr.Row():
            btn = gr.Button("Transcribe", variant="primary")
            clear = gr.ClearButton([audio], value="Clear")
        transcript = gr.Textbox(label="Transcript", lines=12)
        status = gr.Textbox(label="Status", lines=2)

        btn.click(fn=transcribe, inputs=[audio], outputs=[transcript, status])
        clear.add([transcript, status])

    return demo


def main() -> None:
    demo = build_ui()
    demo.launch(
        server_name="127.0.0.1",
        server_port=int(os.environ.get("STT_PORT", "7860")),
        inbrowser=True,
    )


if __name__ == "__main__":
    main()
