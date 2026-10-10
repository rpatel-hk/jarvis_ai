#!/usr/bin/env bash
# One-time generation of the boot greeting audio via ElevenLabs (~110 characters total)
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p hud/audio

ENV_FILE="$HOME/.hermes/.env"
CONFIG="config/server.yaml"

# First matching key; strip surrounding quotes and any Windows CR line endings
EK=$(grep -E '^(ELEVENLABS_API_KEY|ELEVEN_API_KEY|XI_API_KEY)=' "$ENV_FILE" \
      | head -n1 | cut -d= -f2- | tr -d '"'"'"'\r')
VOICE=$(grep 'voice_id:' "$CONFIG" | head -n1 | awk '{print $2}' | tr -d '"'"'"'\r')
NAME=${1:-there}

[ -n "$EK" ]    || { echo "No ElevenLabs API key found in $ENV_FILE" >&2; exit 1; }
[ -n "$VOICE" ] || { echo "No voice_id found in $CONFIG" >&2; exit 1; }

gen() {
  local slot=$1 text=$2
  local out="hud/audio/boot_${slot}.mp3"
  local code
  code=$(curl -s -m 30 -X POST "https://api.elevenlabs.io/v1/text-to-speech/$VOICE" \
    -H "xi-api-key: $EK" -H "Content-Type: application/json" \
    -d "{\"text\":\"$text\",\"model_id\":\"eleven_flash_v2_5\"}" \
    -o "$out" -w '%{http_code}')
  if [ "$code" != "200" ]; then
    echo "Failed ($slot): HTTP $code — $(cat "$out")" >&2
    rm -f "$out"
    return 1
  fi
  echo "OK: $out"
}

gen morning   "Systems online. Good morning, $NAME."
gen afternoon "Systems online. Good afternoon, $NAME."
gen evening   "Systems online. Good evening, $NAME."

ls -la hud/audio/
