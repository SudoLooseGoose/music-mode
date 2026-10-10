#!/usr/bin/env bash

MPV_SOCKET="/tmp/music-mode-mpv.sock"
CAVA_PID="$1"
LAST_STATUS=""

echo "Spotify controller started."

while true; do
  STATUS="$(playerctl -p spotify status 2>/dev/null)"

  if [[ "$STATUS" != "$LAST_STATUS" ]]; then
    echo "Spotify status: ${STATUS:-Unavailable}"

    if [[ "$STATUS" == "Playing" ]]; then
      PAUSE=false
      kill -CONT "$CAVA_PID" 2>/dev/null
    else
      PAUSE=true
      kill -STOP "$CAVA_PID" 2>/dev/null
    fi

    printf '{"command":["set_property","pause",%s]}\n' "$PAUSE" |
      socat - "$MPV_SOCKET" >/dev/null 2>&1

    LAST_STATUS="$STATUS"
  fi

  sleep 1
done
