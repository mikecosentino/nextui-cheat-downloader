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

fetch_root_index() {
  local sha="$1"
  local resp="$CACHE_DIR/root_resp.json"
  local root_json="$CACHE_DIR/root.json"

  curl -k -sS -L -H "User-Agent: minui-cheats" \
    "https://api.github.com/repos/libretro/libretro-database/git/trees/${sha}?recursive=1" \
    -o "$resp"

  # Extract only entries where .path starts with "cht/", strip "cht/" prefix
  jq '{tree: [.tree[] | select(.type=="tree" and (.path|startswith("cht/"))) | {path: (.path | sub("^cht/"; "")), url, sha}]}' "$resp" > "$root_json"
  rm -f "$resp"
}

list_systems() {
  local tmp="$CACHE_DIR/systems_all.json"
  local out="$CACHE_DIR/systems.json"

  # Build the raw list of systems from root.json
  jq -r '{items: [.tree[] | {name: .path}], selected: 0}' "$CACHE_DIR/root.json" > "$tmp"

  # Start clean
  echo '{ "items": [], "selected": 0 }' > "$out"

  # Loop over each system in the JSON and only keep supported ones
  jq -r '.items[].name' "$tmp" | while read -r system_name; do
    # Get short-names for this system
    short_names=$(jq -r --arg value "$system_name" 'to_entries[] | select(.value == $value) | .key' "$PAK_DIR/systems-mapping.json")

    # See if any ROM dir exists for these short names
    for sn in $short_names; do
      if find "$ROM_ROOT" -maxdepth 1 -type d -name "*($sn)" | grep -q .; then
        # Append system_name to out.json
        jq --arg name "$system_name" '.items += [{name: $name}]' "$out" > "$out.tmp" && mv "$out.tmp" "$out"
        break
      fi
    done
  done
}

list_cheats_for_system() {
  local system_name="$1"
  local system_json="$CACHE_DIR/${system_name}.json"

  # Extract the git tree URL for the system from root.json
  local git_url
  git_url=$(jq -r --arg path "$system_name" '.tree[] | select(.path == $path) | .url' "$CACHE_DIR/root.json")

  if [ -z "$git_url" ]; then
    echo "No git tree URL found for system: $system_name" >&2
    return 1
  fi

  # Fetch and cache the system tree
  curl -k -sS -L -H "User-Agent: minui-cheats" "$git_url" -o "$system_json"

  # Convert to minui-list JSON with items having name and url
  jq '{items: [.tree[] | {name: .path, url: .url}], selected: 0}' "$system_json" > "$CACHE_DIR/cheats.json"
}

encode_uri() {
  # Encode a string for use in a URL path segment
  # Requires jq (already bundled with your pak)
  printf '%s' "$1" | jq -Rr @uri
}

download_cheat() {
  local system_name="$1"
  local cheat_name="$2"
  local cheat_url="$3"

  # Get possible short names for this system
  short_names=$(jq -r --arg value "$system_name" \
    'to_entries[] | select(.value == $value) | .key' \
    "$PAK_DIR/systems-mapping.json")

  rom_dir=""
  selected_short=""
  rom_file=""

  # Try each short name until we find a valid ROM directory
  for sn in $short_names; do
    candidate_dir=$(find "$ROM_ROOT" -maxdepth 1 -type d -name "*($sn)" | head -n1)
    if [ -n "$candidate_dir" ] && [ -d "$candidate_dir" ]; then
      if ls "$candidate_dir"/* 1>/dev/null 2>&1; then
        rom_dir="$candidate_dir"
        selected_short="$sn"
        break
      fi
    fi
  done

  [ -z "$selected_short" ] && selected_short=$(echo "$short_names" | head -n1)
  dest_dir="$CHEATS_ROOT/$selected_short"
  mkdir -p "$dest_dir"

  # Normalize the cheat name
  base_cheat_name="${cheat_name%.cht}"

  rom_basename=""
  rom_filename=""
  local cheats_json="$CACHE_DIR/cheats.json"

  # --- Try to match ROMs to the *selected cheat* ---
  if [ -d "$rom_dir" ]; then
    for rom_file in "$rom_dir"/*; do
      [ -f "$rom_file" ] || continue
      rom_file_base="${rom_file##*/}"
      rom_file_base="${rom_file_base%.*}"

      # Exact match against selected cheat
      if [ "$rom_file_base" = "$base_cheat_name" ]; then
        rom_basename="$rom_file_base"
        rom_filename="$(basename "$rom_file")"
        echo "Exact ROM match for selected cheat: $cheat_name"
        break
      fi

      # Fallback: if ROM contains the cheat base name as substring
      rb_lc=$(echo "$rom_file_base" | tr '[:upper:]' '[:lower:]')
      cb_lc=$(echo "$base_cheat_name" | tr '[:upper:]' '[:lower:]')
      if echo "$rb_lc" | grep -qiF "$cb_lc"; then
        rom_basename="$rom_file_base"
        rom_filename="$(basename "$rom_file")"
        echo "Substring ROM match for selected cheat: $cheat_name"
        break
      fi
    done
  fi

  # --- Finalize dest_file ---
  if [ -n "$rom_filename" ]; then
    dest_file="$dest_dir/${rom_filename}.cht"
    echo "Using ROM filename for cheat: $rom_filename"
  else
    dest_file="$dest_dir/${base_cheat_name}.cht"
    echo "No ROM match found, falling back to cheat name: $base_cheat_name"
  fi

  # --- Download cheat ---
  encoded_system_name=$(encode_uri "$system_name")
  encoded_cheat_name=$(encode_uri "$cheat_name")
  raw_url="https://raw.githubusercontent.com/libretro/libretro-database/master/cht/${encoded_system_name}/${encoded_cheat_name}"

  curl -k -sS -L -H "User-Agent: minui-cheats" -o "$dest_file" "$raw_url"
  if [ -s "$dest_file" ]; then
    echo "Cheat file downloaded: $dest_file"
    minui-presenter --message "Downloaded ${cheat_name} for ${system_name}" --show-time-left --timeout 10
  else
    echo "Failed to download cheat: ${cheat_name}"
    minui-presenter --message "Failed to download cheat: ${cheat_name}" --show-time-left --timeout 10
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
  local local_sha_file="$CACHE_DIR/sha.txt"
  local local_sha=""
  local remote_sha=""

  if [ -f "$local_sha_file" ]; then
    local_sha=$(cat "$local_sha_file")
  fi

  remote_sha=$(curl -k -sS -L -H "User-Agent: minui-cheats" "https://api.github.com/repos/libretro/libretro-database/commits/master" | jq -r '.sha')

  if [ "$local_sha" != "$remote_sha" ]; then
    show_status "Fetching system list..."
    fetch_root_index "$remote_sha"
    hide_status
    echo "$remote_sha" > "$local_sha_file"
  else
    echo "Using cached root index for SHA: $local_sha"
  fi

  while true; do
    list_systems
    if ! display_list "$CACHE_DIR/systems.json" "Select System" "$CACHE_DIR/systems_state.json"; then
      exit 0
    fi
    selected_system=$(jq -r '.items[.selected].name' "$CACHE_DIR/systems_state.json")

    show_status "Loading $selected_system..."
    list_cheats_for_system "$selected_system"
    hide_status

    if ! display_list "$CACHE_DIR/cheats.json" "$selected_system" "$CACHE_DIR/cheats_state.json"; then
      continue
    fi
    selected_cheat_name=$(jq -r '.items[.selected].name' "$CACHE_DIR/cheats_state.json")
    selected_cheat_url=$(jq -r --arg name "$selected_cheat_name" '.items[] | select(.name == $name) | .url' "$CACHE_DIR/cheats.json")

    show_status "Downloading $selected_cheat_name..."
    download_cheat "$selected_system" "$selected_cheat_name" "$selected_cheat_url"
    hide_status
  done
}

main