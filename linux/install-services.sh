#!/usr/bin/env bash
# Linux replacement for the launchd/ plists: installs systemd *user* services
# for the voice server and the Hermes dashboard (and optionally the Hermes
# gateway), enables them, and makes them start at boot.
#
# Usage (from anywhere):   linux/install-services.sh [--with-gateway]
#   --with-gateway   also run `hermes gateway` as a service (skip this if you
#                    already start the gateway some other way — two copies
#                    will fight over port 8642)
# Override the hermes binary location with:  HERMES_BIN=/path/to/hermes linux/install-services.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SERVER_DIR="$REPO_DIR/server"
PY="$SERVER_DIR/.venv/bin/python"
HERMES_BIN="${HERMES_BIN:-$HOME/.hermes/hermes-agent/venv/bin/hermes}"
UNIT_DIR="$HOME/.config/systemd/user"
WITH_GATEWAY=0
[ "${1:-}" = "--with-gateway" ] && WITH_GATEWAY=1

# ---- preflight -------------------------------------------------------------
[ -x "$PY" ] || { echo "Missing $PY — create the venv first (see README step 2)." >&2; exit 1; }
[ -f "$SERVER_DIR/config/server.yaml" ] || { echo "Missing server/config/server.yaml — copy server.example.yaml and edit it." >&2; exit 1; }
[ -f "$SERVER_DIR/certs/cert.pem" ] || { echo "Missing TLS cert — run server/scripts/make-certs.sh first." >&2; exit 1; }
if [ ! -x "$HERMES_BIN" ]; then
  HERMES_BIN="$(command -v hermes || true)"
  [ -n "$HERMES_BIN" ] || { echo "Can't find the hermes binary. Re-run with HERMES_BIN=/path/to/hermes" >&2; exit 1; }
fi

# Non-root processes can't bind ports below 1024 on Linux (macOS exempts
# wildcard binds; Linux doesn't). The HUD listens on 443.
if [ "$(cat /proc/sys/net/ipv4/ip_unprivileged_port_start)" -gt 443 ]; then
  echo "Port 443 needs privileges on Linux. Allowing unprivileged binds from 443 up (needs sudo once):"
  echo "net.ipv4.ip_unprivileged_port_start=443" | sudo tee /etc/sysctl.d/99-jarvis-port443.conf >/dev/null
  sudo sysctl -q --system
fi

mkdir -p "$UNIT_DIR"

# ---- voice server (com.jarvis.voice) --------------------------------------
cat > "$UNIT_DIR/jarvis-voice.service" <<EOF
[Unit]
Description=Jarvis voice pipeline + HUD
After=network-online.target
Wants=network-online.target

[Service]
WorkingDirectory=$SERVER_DIR
ExecStart=$PY $SERVER_DIR/server.py
Environment=PATH=$SERVER_DIR/.venv/bin:/usr/local/bin:/usr/bin:/bin
Environment=PYTHONUNBUFFERED=1
# Server idles at ~244 open files (Python libs + Whisper model)
LimitNOFILE=8192
Restart=always
RestartSec=5
# STT model warm-up takes ~40 s
TimeoutStartSec=120

[Install]
WantedBy=default.target
EOF

# ---- Hermes dashboard (com.jarvis.dashboard) ------------------------------
cat > "$UNIT_DIR/jarvis-dashboard.service" <<EOF
[Unit]
Description=Hermes dashboard (loopback only; exposed via the HUD TLS proxy)
After=network-online.target

[Service]
ExecStart=$HERMES_BIN dashboard --host 127.0.0.1 --port 9119 --no-open --skip-build --insecure
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF

UNITS="jarvis-voice.service jarvis-dashboard.service"

# ---- optional: Hermes gateway (API on :8642) -------------------------------
if [ "$WITH_GATEWAY" = 1 ]; then
  cat > "$UNIT_DIR/jarvis-gateway.service" <<EOF
[Unit]
Description=Hermes Agent gateway (API server on 127.0.0.1:8642)
After=network-online.target
Before=jarvis-voice.service

[Service]
ExecStart=$HERMES_BIN gateway
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF
  UNITS="jarvis-gateway.service $UNITS"
fi

systemctl --user daemon-reload
# shellcheck disable=SC2086
systemctl --user enable --now $UNITS

# Start at boot without needing to log in (launchd's RunAtLoad equivalent for a headless box)
loginctl enable-linger "$USER" 2>/dev/null || sudo loginctl enable-linger "$USER"

echo
echo "Installed and started: $UNITS"
echo "Voice server warms its STT model for ~40 s. Then run: server/scripts/jarvis-health.sh"
echo "Logs:  journalctl --user -u jarvis-voice -f"
