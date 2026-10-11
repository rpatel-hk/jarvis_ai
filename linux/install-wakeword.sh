#!/usr/bin/env bash
# Hands-free "Hey Jarvis" listener on THIS machine (needs a mic + speaker plugged in here).
# Installs the client venv and a systemd user service that starts at boot.
#
# Usage:   linux/install-wakeword.sh            # install + start
#          linux/install-wakeword.sh --list     # just list audio devices
# Pick a specific mic/speaker:  INPUT_DEVICE=3 OUTPUT_DEVICE=5 linux/install-wakeword.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLIENT_DIR="$REPO_DIR/client"
VENV="$CLIENT_DIR/.venv"
UNIT_DIR="$HOME/.config/systemd/user"

if ! dpkg -s libportaudio2 >/dev/null 2>&1; then
  echo "Installing PortAudio (needs sudo once)..."
  sudo apt-get install -y libportaudio2 python3-venv
fi

if [ ! -x "$VENV/bin/python" ]; then
  python3 -m venv "$VENV"
fi
"$VENV/bin/pip" install -q --upgrade pip
"$VENV/bin/pip" install -q sounddevice websockets numpy openwakeword

if [ "${1:-}" = "--list" ]; then
  "$VENV/bin/python" "$CLIENT_DIR/client.py" --list-devices
  exit 0
fi

# Fetch the wake-word models now rather than on first start
"$VENV/bin/python" -c "from openwakeword import utils; utils.download_models()" >/dev/null 2>&1 || true

EXTRA=""
[ -n "${INPUT_DEVICE:-}" ]  && EXTRA="$EXTRA --input-device $INPUT_DEVICE"
[ -n "${OUTPUT_DEVICE:-}" ] && EXTRA="$EXTRA --output-device $OUTPUT_DEVICE"

mkdir -p "$UNIT_DIR"
cat > "$UNIT_DIR/jarvis-wake.service" <<EOF
[Unit]
Description=Jarvis hands-free wake-word listener ("Hey Jarvis")
After=jarvis-voice.service pipewire.service pipewire-pulse.service
Wants=jarvis-voice.service

[Service]
WorkingDirectory=$CLIENT_DIR
# Give the voice server time to warm its STT model before connecting
ExecStartPre=/bin/sleep 45
ExecStart=$VENV/bin/python $CLIENT_DIR/client.py --server ws://127.0.0.1:8765/ws$EXTRA
Environment=PYTHONUNBUFFERED=1
# The client exits when the server restarts; come straight back
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now jarvis-wake.service
echo
echo "Installed. Say \"Hey Jarvis\" in ~45 s (after the beep, speak your request)."
echo "Watch it:  journalctl --user -u jarvis-wake -f"
