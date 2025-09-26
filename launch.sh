#!/bin/sh
# Cheats Downloader. A MinUI pak for downloading cheat files from the Libretro database
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

build_system_map() {
  local map_file="$CACHE_DIR/system_map.json"
  echo '{' > "$map_file"
  local first=true
  for dir in "$ROM_ROOT"/*; do
    [ -d "$dir" ] || continue
    folder=$(basename "$dir")
    case "$folder" in
      *\(*\)*)
        short=$(printf '%s\n' "$folder" | sed -n 's/.*(\(.*\)).*/\1/p')
        $first || echo ',' >> "$map_file"
        first=false
        echo "  \"$short\": \"$dir\"" >> "$map_file"
        ;;
    esac
  done
  echo '}' >> "$map_file"
}

download_cheat() {
  local gameId="$1"
  curl -k "https://dev.cosentino.wtf/nextui-cheat-downloader/api/cheat/$gameId" -o "$CACHE_DIR/$gameId.cht"
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
  local system_short="$3"

  show_status "Loading $game_name..."
  curl -k "https://dev.cosentino.wtf/nextui-cheat-downloader/api/game/$game_id" -o "$CACHE_DIR/game.json"
  hide_status

  download_cheat "$game_id"

  if ! display_list "$CACHE_DIR/game.json" "$game_name" "$CACHE_DIR/game_state.json"; then
    return
  fi

  selected_item=$(jq -r --argjson i "$(jq -r '.selected' "$CACHE_DIR/game_state.json")" '.items[$i].name' "$CACHE_DIR/game.json")

  case "$selected_item" in
    "Choose installed game and save cheat")
      if chosen_file=$(choose_rom "$system_short" "$game_id"); then
        display_game "$game_id" "$game_name" "$system_short"
      fi
      ;;
    "Download cheat file")
      download_cheat "$game_id"
      ;;
  esac

}

choose_rom() {
  local system_short="$1"
  local game_id="$2"
  local rom_dir
  rom_dir=$(jq -r --arg short "$system_short" '.[$short]' "$CACHE_DIR/system_map.json")
  if [ -z "$rom_dir" ] || [ "$rom_dir" = "null" ]; then
    echo '{ "items": [ { "name": "No ROMs found" } ] }' > "$roms_json"
    return 1
  fi
  local roms_json="$CACHE_DIR/roms_$system_short.json"
  local state_file="$CACHE_DIR/roms_state.json"

  if [ ! -d "$rom_dir" ]; then
    echo '{ "items": [ { "name": "No ROMs found" } ] }' > "$roms_json"
    return 1
  fi

  # Build JSON list of ROMs
  {
    echo '{ "items": ['
    local first=true
    for f in "$rom_dir"/*; do
      [ -f "$f" ] || continue
      name=$(basename "$f")
      $first || echo ','
      first=false
      echo "  { \"name\": \"$name\", \"file\": \"$f\" }"
    done
    echo '] }'
  } > "$roms_json"

  # Display to user
  if ! display_list "$roms_json" "Choose installed game..." "$state_file"; then
    return 1
  fi

  # Grab selection
  local selected_index
  selected_index=$(jq -r '.selected' "$state_file")
  local selected_file
  selected_file=$(jq -r --argjson i "$selected_index" '.items[$i].file' "$roms_json")

  # Move cached cheat file to CHEATS_ROOT/$system_short/<rom_basename>.cht
  local rom_basename
  rom_basename=$(basename "$selected_file")
  mkdir -p "$CHEATS_ROOT/$system_short"
  if [ -f "$CACHE_DIR/$game_id.cht" ]; then
    mv "$CACHE_DIR/$game_id.cht" "$CHEATS_ROOT/$system_short/$rom_basename.cht"
    echo "Moved cheat file to $CHEATS_ROOT/$system_short/$rom_basename.cht"
    minui-presenter --message "Cheat saved for $rom_basename" --timeout 3
  fi

  echo "$selected_file"
}

main() {
  build_system_map
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

    display_game "$game_id" "$game_name" "$system_short"
  done
}

main