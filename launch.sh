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
  # Encode a string for use in a URL path segment
  # Requires jq (already bundled with your pak)
  printf '%s' "$1" | jq -Rr @uri
}

download_cheat() {
  local system_name="$1"
  local game_name="$2"
  local game_url="$3"
  local selected_short="$4"

  rom_dir=$(find "$ROM_ROOT" -maxdepth 1 -type d -name "*($selected_short)" | head -n1)
  rom_file=""

  # Normalize the game name
  base_game_name="${game_name%.cht}"

  rom_basename=""
  rom_filename=""
  local games_json="$CACHE_DIR/games.json"

  # --- Try to match ROMs to the *selected game* ---
  if [ -d "$rom_dir" ]; then
    for rom_file in "$rom_dir"/*; do
      [ -f "$rom_file" ] || continue
      rom_file_base="${rom_file##*/}"
      rom_file_base="${rom_file_base%.*}"

      # Exact match against selected game
      if [ "$rom_file_base" = "$base_game_name" ]; then
        rom_basename="$rom_file_base"
        rom_filename="$(basename "$rom_file")"
        echo "Exact ROM match for selected game: $game_name"
        break
      fi

      # Fallback: if ROM contains the game base name as substring
      rb_lc=$(echo "$rom_file_base" | tr '[:upper:]' '[:lower:]')
      cb_lc=$(echo "$base_game_name" | tr '[:upper:]' '[:lower:]')
      if echo "$rb_lc" | grep -qiF "$cb_lc"; then
        rom_basename="$rom_file_base"
        rom_filename="$(basename "$rom_file")"
        echo "Substring ROM match for selected game: $game_name"
        break
      fi
    done
  fi

  # --- Finalize dest_file ---
  dest_dir="$CHEATS_ROOT/$selected_short"
  mkdir -p "$dest_dir"

  if [ -n "$rom_filename" ]; then
    dest_file="$dest_dir/${rom_filename}.cht"
    echo "Using ROM filename for cheat: $rom_filename"
  else
    dest_file="$dest_dir/${base_game_name}.cht"
    echo "No ROM match found, falling back to cheat name: $base_game_name"
  fi

  # --- Download cheat ---
  encoded_system_name=$(encode_uri "$system_name")
  encoded_game_name=$(encode_uri "$game_name")
  raw_url="https://raw.githubusercontent.com/libretro/libretro-database/master/cht/${encoded_system_name}/${encoded_game_name}"

  curl -k -sS -L -H "User-Agent: minui-cheats" -o "$dest_file" "$raw_url"
  if [ -s "$dest_file" ]; then
    echo "Cheat file downloaded: $dest_file"
    minui-presenter --message "Downloaded ${game_name} for ${system_name}" --show-time-left --timeout 10
  else
    echo "Failed to download cheat: ${game_name}"
    minui-presenter --message "Failed to download cheat: ${game_name}" --show-time-left --timeout 10
    rm -f "$dest_file"
    return 1
  fi
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

main() {
  curl -k -sS "https://dev.cosentino.wtf/nextui-cheat-downloader/" -o "$CACHE_DIR/systems.json"
  echo "[DEBUG] Downloaded systems.json:"
  cat "$CACHE_DIR/systems.json"

  while true; do
    # Extract selected system's short name by index from original systems.json
    if ! display_list "$CACHE_DIR/systems.json" "Select System" "$CACHE_DIR/systems_state.json"; then
      echo "[INFO] User exited at system selection."
      exit 0
    fi

    # echo "[DEBUG] Raw state JSON:"
    # cat "$CACHE_DIR/systems_state.json"

    selected_index=$(jq -r '.selected' "$CACHE_DIR/systems_state.json")
    selected_system=$(jq -r --argjson i "$selected_index" '.items[$i].name' "$CACHE_DIR/systems.json")
    system_short=$(jq -r --argjson i "$selected_index" '.items[$i].short' "$CACHE_DIR/systems.json")

    echo "[DEBUG] Selected system: $selected_system"
    echo "[DEBUG] Short name: $system_short"

    if [ -z "$system_short" ] || [ "$system_short" = "null" ]; then
      echo "[ERROR] No short_name found for '$selected_system'. Skipping..."
      minui-presenter --message "No short name for '$selected_system'" --timeout 4
      continue
    fi

    show_status "Loading $selected_system..."
    curl -k -sS "https://dev.cosentino.wtf/nextui-cheat-downloader/?system=$system_short" -o "$CACHE_DIR/games.json"
    echo "[DEBUG] Downloaded games.json for $system_short:"
    cat "$CACHE_DIR/games.json"
    hide_status

    if ! display_list "$CACHE_DIR/games.json" "$selected_system" "$CACHE_DIR/cheats_state.json"; then
      echo "[INFO] User backed out from games list for $selected_system."
      continue
    fi

    selected_game_name=$(jq -r '.items[.selected].title' "$CACHE_DIR/cheats_state.json")
    selected_game_url=$(jq -r --arg name "$selected_game_name" '.items[] | select(.title == $name) | .url' "$CACHE_DIR/games.json")

    echo "[DEBUG] Selected game: $selected_game_name"
    echo "[DEBUG] Game URL: $selected_game_url"

    show_status "Downloading $selected_game_name..."
    download_cheat "$selected_system" "$selected_game_name" "$selected_game_url" "$system_short"
    hide_status
  done
}

main