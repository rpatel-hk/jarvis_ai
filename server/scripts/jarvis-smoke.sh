#!/bin/bash
# Linux: synthesize a test phrase locally and push it through the full voice stack.
# Needs: sudo apt install espeak-ng ffmpeg
cd "$(dirname "$0")/.."
command -v espeak-ng >/dev/null && command -v ffmpeg >/dev/null || {
  echo "Install first: sudo apt install espeak-ng ffmpeg" >&2; exit 1; }
espeak-ng -w /tmp/jarvis_smoke_raw.wav "Say only the word confirmed."
ffmpeg -y -loglevel error -i /tmp/jarvis_smoke_raw.wav -ar 16000 -ac 1 -sample_fmt s16 /tmp/jarvis_smoke.wav
.venv/bin/python scripts/ws_e2e_test.py /tmp/jarvis_smoke.wav jarvis-debug
