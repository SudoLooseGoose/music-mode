#!/usr/bin/env bash

VIDEO_DIR="$HOME/Videos/MusicMode"
MPV_SOCKET="/tmp/music-mode-mpv.sock"
STATIC_FILE="$(dirname "$(realpath "$0")")/assets/tv-static.mp4"

echo "Channel switcher started."
echo "Watching: $MPV_SOCKET"

LAST_VIDEO="$(printf '%s\n' '{"command":["get_property","path"]}' |
  socat - "$MPV_SOCKET" |
  jq -r '.data // empty')"

if [[ -n "$LAST_VIDEO" ]]; then
  echo "Starting Channel: $(basename "$LAST_VIDEO")"
fi

NEXT_START=""
TIMER_PID=""
PLAYING_STATIC=false

cancel_timer() {
  if [[ -n "$TIMER_PID" ]] && kill -0 "$TIMER_PID" 2>/dev/null; then
    kill "$TIMER_PID" 2>/dev/null
    wait "$TIMER_PID" 2>/dev/null
  fi

  TIMER_PID=""
}

play_static() {
  PLAYING_STATIC=true

  jq -nc \
    --arg file "$STATIC_FILE" \
    '{command:["loadfile",$file,"replace"]}' |
    socat - "$MPV_SOCKET"
}

start_channel_timer() {
  local WAIT_SECONDS="$1"

  cancel_timer

  (
    remaining="$WAIT_SECONDS"

    while ((remaining > 0)); do
      if [[ "$(playerctl -p spotify status 2>/dev/null)" == "Playing" ]]; then
        sleep 1
        ((remaining--))
      else
        sleep 1
      fi
    done

    echo "Viewing timer expired. Changing channel."

    printf '%s\n' '{"command":["stop"]}' |
      socat - "$MPV_SOCKET"
  ) &

  TIMER_PID=$!
}

cleanup() {
  cancel_timer
}

trap cleanup EXIT INT TERM

socat -u "UNIX-CONNECT:$MPV_SOCKET", STDOUT |
  while IFS= read -r EVENT; do
    echo "$EVENT"

    if [[ "$EVENT" == *'"event":"idle"'* ]]; then
      cancel_timer

      if [[ "$PLAYING_STATIC" == true ]]; then
        PLAYING_STATIC=false
        echo "Static finished. Loading next cartoon."

      else
        echo "TV is idle. Playing channel static."
        play_static
        continue
      fi

      NEXT_VIDEO="$(
        find "$VIDEO_DIR" -maxdepth 1 -type f -print0 |
          while IFS= read -r -d '' VIDEO; do
            if [[ "$VIDEO" != "$LAST_VIDEO" ]]; then
              printf '%s\0' "$VIDEO"
            fi
          done |
          shuf -z -n 1 |
          tr -d '\0'
      )"

      echo "Next Channel: $(basename "$NEXT_VIDEO")"

      NEXT_DURATION="$(ffprobe \
        -v error \
        -show_entries format=duration \
        -of csv=p=0 \
        "$NEXT_VIDEO")"

      NEXT_DURATION_INT="${NEXT_DURATION%.*}"
      NEXT_START=$((RANDOM % NEXT_DURATION_INT))

      echo "Starting at: $NEXT_START seconds"

      LOAD_COMMAND="$(jq -nc \
        --arg file "$NEXT_VIDEO" \
        '{command:["loadfile",$file,"replace"]}')"

      printf '%s\n' "$LOAD_COMMAND" | socat - "$MPV_SOCKET"

      LAST_VIDEO="$NEXT_VIDEO"

    elif [[ "$EVENT" == *'"event":"file-loaded"'* && "$PLAYING_STATIC" == true ]]; then
      echo "TV static is playing."

    elif [[ "$EVENT" == *'"event":"file-loaded"'* && -n "$NEXT_START" ]]; then
      echo "Seeking to: $NEXT_START seconds"

      SEEK_COMMAND="$(jq -nc \
        --argjson start "$NEXT_START" \
        '{command:["set_property","time-pos",$start]}')"

      printf '%s\n' "$SEEK_COMMAND" | socat - "$MPV_SOCKET"

      ROLL=$((RANDOM % 100))

      if ((ROLL < 15)); then
        VIEW_MODE="Quick flip"
        WAIT_SECONDS=$((30 + RANDOM % 61))
      elif ((ROLL < 65)); then
        VIEW_MODE="Normal watch"
        WAIT_SECONDS=$((120 + RANDOM % 241))
      elif ((ROLL < 80)); then
        VIEW_MODE="Long watch"
        WAIT_SECONDS=$((420 + RANDOM % 481))
      else
        VIEW_MODE="Stay tuned"
        WAIT_SECONDS=0
      fi

      echo "Viewing behavior: $VIEW_MODE"

      if ((WAIT_SECONDS == 0)); then
        echo "Stay on this channel until the video ends."
        cancel_timer
      else
        echo "Stay on channel for: $WAIT_SECONDS seconds"
        start_channel_timer "$WAIT_SECONDS"
      fi

      NEXT_START=""
    fi
  done
