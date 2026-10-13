#!/usr/bin/env bash
# Enables the HUD's "Hey Jarvis" wake word: installs openWakeWord into the voice
# server's venv, fetches the model, and restarts the voice server.
# Run from anywhere:  linux/install-hud-wakeword.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VENV="$REPO_DIR/server/.venv"
[ -x "$VENV/bin/python" ] || { echo "Missing $VENV — set up the server venv first." >&2; exit 1; }

# openwakeword's Linux dependency tflite-runtime has no Python 3.12+ wheels;
# install without deps and use the ONNX runtime (the server loads models that way).
"$VENV/bin/pip" install -q onnxruntime tqdm scipy scikit-learn requests
"$VENV/bin/pip" install -q --no-deps openwakeword==0.6.0

echo "Fetching the hey_jarvis model..."
"$VENV/bin/python" - <<'EOF'
from openwakeword import utils
from openwakeword.model import Model
utils.download_models(["hey_jarvis"])
Model(wakeword_models=["hey_jarvis"], inference_framework="onnx")
print("model OK")
EOF

if systemctl --user cat jarvis-voice >/dev/null 2>&1; then
  systemctl --user restart jarvis-voice
  echo "Voice server restarted (allow ~40 s to warm up)."
else
  echo "Restart the voice server to pick up the change."
fi
echo "Then reload the HUD and click  ○ WAKE WORD: OFF  under VOICE LINK to arm it."
