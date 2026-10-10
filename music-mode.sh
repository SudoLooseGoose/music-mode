#!/usr/bin/env bash

SCRIPT_PATH="$(realpath -- "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname -- "$SCRIPT_PATH")"
VIDEO_DIR="$HOME/Videos/MusicMode"
MPV_SOCKET="/tmp/music-mode-mpv.sock"
MPV_PID_FILE="/tmp/music-mode-mpv.pid"

if [[ -f "$MPV_PID_FILE" ]]; then
  OLD_MPV_PID="$(cat "$MPV_PID_FILE")"

  if kill -0 "$OLD_MPV_PID" 2>/dev/null; then
    echo "Stopping old Music mode player..."
    kill "$OLD_MPV_PID"
    sleep 1
  fi
fi

rm -f "$MPV_PID_FILE"
rm -f "$MPV_SOCKET"

VIDEO_FILE="$(find "$VIDEO_DIR" -maxdepth 1 -type f -print0 | shuf -z -n 1 | tr -d '\0')"

VIDEO_DURATION="$(ffprobe \
  -v error \
  -show_entries format=duration \
  -of csv=p=0 \
  "$VIDEO_FILE")"

VIDEO_DURATION_INT="${VIDEO_DURATION%.*}"
RANDOM_START=$((RANDOM % VIDEO_DURATION_INT))

echo "Selected video: $(basename "$VIDEO_FILE")"
echo "Duration: $VIDEO_DURATION_INT seconds"
echo "Starting at: $RANDOM_START seconds"

flatpak run com.spotify.Client &

alacritty \
  --config-file "$SCRIPT_DIR/cava-alacritty.toml" \
  -e bash -c 'echo "$$" > /tmp/music-mode-cava.pid; exec cava' &

mpv \
  --mute=yes \
  --osc=no \
  --osd-level=0 \
  --glsl-shaders="$SCRIPT_DIR/shaders/scanlines.glsl" \
  --title="Music Mode - Cartoon" \
  --wayland-app-id=MusicModeCartoon \
  --keepaspect=yes \
  --keepaspect-window=no \
  --auto-window-resize=no \
  --force-window=yes \
  --idle=yes \
  --input-ipc-server="$MPV_SOCKET" \
  "$VIDEO_FILE" &

MPV_PID=$!
echo "$MPV_PID" >"$MPV_PID_FILE"

# Wait for mpv's IPC socket to become available.
for _ in {1..50}; do
  [[ -S "$MPV_SOCKET" ]] && break
  sleep 0.1
done

# Apply the random start only to the initial video.
SEEK_COMMAND="$(jq -nc \
  --argjson start "$RANDOM_START" \
  '{command:["set_property","time-pos",$start]}')"

printf '%s\n' "$SEEK_COMMAND" | socat - "$MPV_SOCKET"

# Start the automatic TV channel switcher.
echo "Starting channel switcher..."
bash "$SCRIPT_DIR/channel-switcher.sh" &
CHANNEL_SWITCHER_PID=$!

# Start the Spotify playback controller.
echo "Starting Spotify controller..."
CAVA_PID="$(cat /tmp/music-mode-cava.pid)"

bash "$SCRIPT_DIR/spotify-controller.sh" "$CAVA_PID" &
SPOTIFY_CONTROLLER_PID=$!

# Wait for Retro TV to close, then clean up.
wait "$MPV_PID"

echo "Cleaning up Music Mode..."

# Stop the Spotify controller.
kill "$SPOTIFY_CONTROLLER_PID" 2>/dev/null
wait "$SPOTIFY_CONTROLLER_PID" 2>/dev/null

rm -f "$MPV_PID_FILE" "$MPV_SOCKET"
