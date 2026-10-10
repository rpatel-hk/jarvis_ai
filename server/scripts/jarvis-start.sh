#!/bin/bash
# Linux: start the systemd user services installed by linux/install-services.sh
UNITS="jarvis-voice jarvis-dashboard"
systemctl --user cat jarvis-gateway >/dev/null 2>&1 && UNITS="jarvis-gateway $UNITS"
systemctl --user start $UNITS
echo "started (voice server warms its STT model for ~40s)"
