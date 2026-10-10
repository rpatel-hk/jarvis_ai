#!/bin/bash
# Self-signed TLS cert for the HUD. Add your hostnames/IPs to the SAN list.
# Usage: scripts/make-certs.sh [LAN_IP]   (auto-detects the primary LAN IP if omitted)
cd "$(dirname "$0")/.."
mkdir -p certs
DETECTED=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')
HOST_IP=${1:-${DETECTED:-127.0.0.1}}
HOST_NAME=$(hostname)
openssl req -x509 -newkey rsa:2048 -keyout certs/key.pem -out certs/cert.pem -days 825 -nodes \
  -subj "/CN=Jarvis HUD" \
  -addext "subjectAltName=DNS:jarvis.local,DNS:jarvis,DNS:$HOST_NAME,DNS:$HOST_NAME.local,DNS:localhost,IP:$HOST_IP,IP:127.0.0.1"
cp certs/cert.pem hud/jarvis.cer   # downloadable from the HUD for phones
echo "cert created for IP $HOST_IP and host $HOST_NAME.local — trust certs/cert.pem on your devices"
