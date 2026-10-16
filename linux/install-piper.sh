#!/usr/bin/env bash
# Free local voice (Piper) as a fallback for when ElevenLabs refuses (quota, 401/402).
# Installs piper-tts into the voice server's venv, downloads a British male voice,
# adds voice.fallback to server.yaml (backup kept), and restarts the voice server.
#
# Usage:  linux/install-piper.sh                 # default voice en_GB-alan-medium
#         linux/install-piper.sh en_GB-northern_english_male-medium
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SERVER_DIR="$REPO_DIR/server"
CONFIG="$SERVER_DIR/config/server.yaml"
VOICE="${1:-en_GB-alan-medium}"

# Use the exact Python the service runs (falls back to server/.venv)
PY=$(systemctl --user cat jarvis-voice 2>/dev/null | sed -n 's/^ExecStart=\([^ ]*\).*/\1/p' | head -n1 || true)
PY=${PY:-$SERVER_DIR/.venv/bin/python}
[ -x "$PY" ] || { echo "Can't find the voice server's Python ($PY)." >&2; exit 1; }
[ -f "$CONFIG" ] || { echo "Missing $CONFIG" >&2; exit 1; }

echo "Installing piper-tts into $PY ..."
"$PY" -m pip install -q piper-tts

mkdir -p "$SERVER_DIR/voices"
MODEL="voices/$VOICE.onnx"
if [ ! -f "$SERVER_DIR/$MODEL" ] && [ $# -eq 0 ] && [ -f "$SERVER_DIR/voices/en-gb-alan-low.onnx" ]; then
  MODEL="voices/en-gb-alan-low.onnx"      # backup voice from an earlier run
fi
if [ ! -f "$SERVER_DIR/$MODEL" ]; then
  echo "Downloading voice $VOICE ..."
  if ! "$PY" -m piper.download_voices "$VOICE" --data-dir "$SERVER_DIR/voices"; then
    echo "Voice download failed; using the older en-gb-alan-low voice from GitHub instead."
    curl -fsSL -o /tmp/piper-alan.tgz \
      https://github.com/rhasspy/piper/releases/download/v0.0.2/voice-en-gb-alan-low.tar.gz
    tar -xzf /tmp/piper-alan.tgz -C "$SERVER_DIR/voices" en-gb-alan-low.onnx en-gb-alan-low.onnx.json
    MODEL="voices/en-gb-alan-low.onnx"
  fi
fi

echo "Testing the voice ..."
"$PY" - "$SERVER_DIR/$MODEL" <<'EOF'
import sys, time
from piper import PiperVoice
v = PiperVoice.load(sys.argv[1])
t = time.perf_counter()
chunks = list(v.synthesize("Systems online. Backup voice ready."))
secs = sum(len(c.audio_int16_bytes) for c in chunks) / 2 / chunks[0].sample_rate
print(f"OK: {secs:.1f}s of speech generated in {time.perf_counter() - t:.2f}s")
EOF

if grep -qE '^  fallback:' "$CONFIG"; then
  echo "server.yaml already has voice.fallback; leaving it as is (model: $MODEL)."
else
  cp "$CONFIG" "$CONFIG.bak-$(date +%F-%H%M)"
  "$PY" - "$CONFIG" "$MODEL" <<'EOF'
import sys, re
path, model = sys.argv[1], sys.argv[2]
lines = open(path).read().split("\n")
block = ["  fallback:                  # local Piper voice when ElevenLabs refuses (quota/auth/network)",
         f"    model: {model}",
         "    retry_after_seconds: 600   # how long to stay on Piper before trying ElevenLabs again"]
try:
    start = next(i for i, l in enumerate(lines) if l.startswith("voice:"))
except StopIteration:
    sys.exit("No 'voice:' section in server.yaml; add voice.fallback by hand.")
end = start + 1
while end < len(lines) and (lines[end].startswith(" ") or not lines[end].strip()):
    end += 1
while end > start + 1 and not lines[end - 1].strip():
    end -= 1
lines[end:end] = block
open(path, "w").write("\n".join(lines))
print("Added voice.fallback to server.yaml (backup saved next to it).")
EOF
fi

if systemctl --user cat jarvis-voice >/dev/null 2>&1; then
  systemctl --user restart jarvis-voice
  echo "Voice server restarted (~40 s to warm up)."
fi
echo "Done. When ElevenLabs refuses, Jarvis now speaks with Piper instead of going silent."
