#!/bin/sh
# Cheats Downloader. A MinUI pak for downloading cheat files (.cht) from the Libretro database.
# Mike Cosentino

# Setup
PAK_DIR="$(dirname "$0")"
PAK_NAME="$(basename "$PAK_DIR")"
PAK_NAME="${PAK_NAME%.*}"
set -x
rm -f "$LOGS_PATH/$PAK_NAME.txt"
exec >>"$LOGS_PATH/$PAK_NAME.txt"
exec 2>&1
export PATH="$PAK_DIR/bin/tg5040:$PATH"

# Constants
ROM_ROOT="/mnt/SDCARD/Roms"
CHEATS_ROOT="/mnt/SDCARD/Cheats"
CACHE_DIR="/mnt/SDCARD/.userdata/tg5040/$PAK_NAME"
mkdir -p "$CACHE_DIR"

encode_uri() {
  printf '%s' "$1" | jq -Rr @uri
}

download_cheat() {
  local gameId="$1"
  # TODO: Take gameId and then send to API to get the download URL
}

display_list() {
  local json_file="$1"
  local title="$2"
  local state_file="$3"

  minui-list --file "$json_file" --item-key "items" --title "$title" --write-value state --write-location "$state_file"
  local result=$?
  if [ $result -ne 0 ]; then
    echo "User pressed Back at $title"
    return 1
  fi
}

show_status() {
  local msg="$1"
  minui-presenter --message "$msg" --timeout -1 &
  STATUS_PID=$!
  echo "Started status presenter PID=$STATUS_PID ($msg)"
}

hide_status() {
  echo "Killing all minui-presenter instances..."
  killall -q minui-presenter 2>/dev/null || true
  STATUS_PID=""
}

cache_all_systems() {
  show_status "Loading systems..."
  curl -k "https://dev.cosentino.wtf/nextui-cheat-downloader/api/systems" -o "$CACHE_DIR/systems.json"
  hide_status
}

cache_system() {
  local system_short="$1"
  local system_name="$2"
  show_status "Loading $system_name..."
  curl -k "https://dev.cosentino.wtf/nextui-cheat-downloader/api/system/$system_short" -o "$CACHE_DIR/$system_short.json"
  hide_status
}

display_game() {
  local game_id="$1"
  local game_name="$2"

  show_status "Loading $game_name..."
  curl -k "https://dev.cosentino.wtf/nextui-cheat-downloader/api/game/$game_id" -o "$CACHE_DIR/game.json"
  hide_status

  local augmented_json
  augmented_json=$(augment_with_matches "$game_id" "$system_short")

  if ! display_list "$augmented_json" "$game_name" "$CACHE_DIR/game_state.json"; then
    return
  fi

  selected_item=$(jq -r --argjson i "$(jq -r '.selected' "$CACHE_DIR/game_state.json")" '.items[$i].name' "$augmented_json")

  if [ "$selected_item" = "View Cheats" ]; then
    show_status "Loading Cheats..."
    curl -k "https://dev.cosentino.wtf/nextui-cheat-downloader/api/cheat/$game_id" -o "$CACHE_DIR/cheats.json"
    hide_status
    display_list "$CACHE_DIR/cheats.json" "Cheats for $game_name" "$CACHE_DIR/cheats_state.json"
  fi
}

augment_with_matches() {
  local game_id="$1"
  local system_short="$2"
  local output_json="$CACHE_DIR/game_aug.json"

  local rom_dir
  rom_dir=$(find "$ROM_ROOT" -maxdepth 1 -type d -name "*($system_short)" | head -n 1)

  local matched_file=""
  if [ -n "$rom_dir" ]; then
    local myrient_files
    myrient_files=$(jq -r '.items[] | select(.name=="Myrient Filename") | .options[]' "$CACHE_DIR/game.json")
    if [ -n "$myrient_files" ]; then
      for f in $myrient_files; do
        if [ -f "$rom_dir/$f" ]; then
          matched_file="$f"
          break
        fi
      done
    fi
  fi

  if [ -n "$matched_file" ]; then
    curl -k "https://dev.cosentino.wtf/nextui-cheat-downloader/api/match/$game_id/$(encode_uri "$matched_file")" -o "$output_json"
  else
    curl -k "https://dev.cosentino.wtf/nextui-cheat-downloader/api/match/$game_id/none" -o "$output_json"
  fi

  echo "$output_json"
}

main() {
  cache_all_systems
  cat "$CACHE_DIR/systems.json"

  while true; do
    if ! display_list "$CACHE_DIR/systems.json" "Select System" "$CACHE_DIR/systems_state.json"; then
      exit 0
    fi

    selected_index=$(jq -r '.selected' "$CACHE_DIR/systems_state.json")
    selected_system=$(jq -r --argjson i "$selected_index" '.items[$i].name' "$CACHE_DIR/systems.json")
    system_short=$(jq -r --argjson i "$selected_index" '.items[$i].short' "$CACHE_DIR/systems.json")

    if [ -z "$system_short" ] || [ "$system_short" = "null" ]; then
      minui-presenter --message "No short name for '$selected_system'" --timeout 4
      continue
    fi

    cache_system "$system_short" "$selected_system"

    if ! display_list "$CACHE_DIR/$system_short.json" "$selected_system" "$CACHE_DIR/cheats_state.json"; then
      continue
    fi

    selected_game_index=$(jq -r '.selected' "$CACHE_DIR/cheats_state.json")
    game_name=$(jq -r --argjson i "$selected_game_index" '.items[$i].name' "$CACHE_DIR/$system_short.json")
    game_id=$(jq -r --argjson i "$selected_game_index" '.items[$i].id // .items[$i].url' "$CACHE_DIR/$system_short.json")

    display_game "$game_id" "$game_name"
  done
}

main