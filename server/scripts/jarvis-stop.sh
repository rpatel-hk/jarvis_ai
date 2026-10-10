#!/bin/bash
# Linux: stop the systemd user services, then clear anything still holding our ports
# (catches orphaned STT children whose cmdline doesn't contain "server.py").
# Note: leaves jarvis-gateway (Hermes) running, matching the original macOS script.
systemctl --user stop jarvis-voice jarvis-dashboard 2>/dev/null
sleep 2
for port in 443 8765 8766 9443; do
  fuser -k -n tcp "$port" >/dev/null 2>&1
done
pkill -9 -if "server\.py" 2>/dev/null
echo "stopped (ports cleared)"
