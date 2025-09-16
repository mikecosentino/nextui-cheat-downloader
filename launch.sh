#!/bin/sh
# Cheat Downloader. A MinUI pak for downloading cheat files from the Libretro database
# Mike Cosentino
# https://github.com/mikecosentino/nextui-cheat-downloader

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
  jq -r '{items: [.tree[] | {name: .path}], selected: 0}' "$CACHE_DIR/root.json" > "$CACHE_DIR/systems.json"
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

  local short_name
  short_name=$(jq -r --arg value "$system_name" \
    'to_entries[] | select(.value == $value) | .key' \
    "$PAK_DIR/systems-mapping.json")
  [ -z "$short_name" ] && short_name="$system_name"

  local dest_dir dest_file rom_basename base_cheat_name rom_dir rom_file
  dest_dir="$CHEATS_ROOT/$short_name"
  mkdir -p "$dest_dir"

  base_cheat_name="${cheat_name%.cht}"

  # ROM directory (find folder ending with "(ShortName)")
  rom_dir=$(find "$ROM_ROOT" -maxdepth 1 -type d -name "*(${short_name})" | head -n1)
  [ -z "$rom_dir" ] && rom_dir="$ROM_ROOT/$system_name"

  rom_basename=""
  local matched_cheat_name=""
  local cheats_json="$CACHE_DIR/cheats.json"

  # Helper: extract title and regions
  extract_title_and_regions() {
    local name="$1"
    local title regions
    title=$(echo "$name" | sed 's/ *(.*)//g' | xargs) # strip first () block
    regions=$(echo "$name" | grep -o '([^)]*)' | sed 's/[()]//g' | tr '\n' ';' | sed 's/;$//')
    echo "$title|$regions"
  }

  # --- Priority 1: exact ROM filename match
  if [ -d "$rom_dir" ]; then
    for rom_file in "$rom_dir"/*; do
      [ -f "$rom_file" ] || continue
      local rom_file_base="${rom_file##*/}"
      rom_file_base="${rom_file_base%.*}"
      matched_cheat_name=$(jq -r --arg rb "$rom_file_base" \
        '.items[] | select((.name | endswith(".cht")) and ((.name | sub("\\.cht$"; "")) == $rb)) | .name' "$cheats_json")
      if [ -n "$matched_cheat_name" ]; then
        rom_basename="$rom_file_base"
        echo "Exact match found: $matched_cheat_name for ROM: $rom_file_base"
        break
      fi
    done
  fi

  # --- Priority 2: same title + overlapping region tags
  if [ -z "$matched_cheat_name" ] && [ -d "$rom_dir" ]; then
    jq -r '.items[].name' "$cheats_json" > "$CACHE_DIR/.cheat_names.txt"
    for rom_file in "$rom_dir"/*; do
      [ -f "$rom_file" ] || continue
      local rom_file_base="${rom_file##*/}"
      rom_file_base="${rom_file_base%.*}"

      rom_line=$(extract_title_and_regions "$rom_file_base")
      rom_title=$(echo "$rom_line" | cut -d'|' -f1)
      rom_regions=$(echo "$rom_line" | cut -d'|' -f2-)

      while IFS= read -r c_name; do
        local cheat_line c_title c_regions
        c_name="${c_name%.cht}"
        cheat_line=$(extract_title_and_regions "$c_name")
        c_title=$(echo "$cheat_line" | cut -d'|' -f1)
        c_regions=$(echo "$cheat_line" | cut -d'|' -f2-)

        if [ "$rom_title" = "$c_title" ]; then
          overlap_found=0
          if [ -z "$rom_regions" ] && [ -z "$c_regions" ]; then
            overlap_found=1
          else
            for rr in $(echo "$rom_regions" | tr ';' ' '); do
              for cr in $(echo "$c_regions" | tr ';' ' '); do
                [ "$rr" = "$cr" ] && overlap_found=1 && break 2
              done
            done
          fi
          if [ $overlap_found -eq 1 ]; then
            matched_cheat_name="${c_name}.cht"
            rom_basename="$rom_file_base"
            echo "Title+region match: $matched_cheat_name for ROM: $rom_file_base"
            break 2
          fi
        fi
      done < "$CACHE_DIR/.cheat_names.txt"
    done
  fi

  # --- Priority 3: substring (case-insensitive)
  if [ -z "$matched_cheat_name" ] && [ -d "$rom_dir" ]; then
    for rom_file in "$rom_dir"/*; do
      [ -f "$rom_file" ] || continue
      local rom_file_base="${rom_file##*/}"
      rom_file_base="${rom_file_base%.*}"
      rb_lc=$(echo "$rom_file_base" | tr '[:upper:]' '[:lower:]')
      matched_cheat_name=$(jq -r --arg rb "$rb_lc" \
        '.items[] | select((.name | endswith(".cht")) and ((.name | ascii_downcase | contains($rb)))) | .name' "$cheats_json" | head -n1)
      if [ -n "$matched_cheat_name" ]; then
        rom_basename="$rom_file_base"
        echo "Substring match: $matched_cheat_name for ROM: $rom_file_base"
        break
      fi
    done
  fi

  # --- Fallback
  [ -z "$rom_basename" ] && rom_basename="$base_cheat_name"
  [ -z "$matched_cheat_name" ] && matched_cheat_name="$cheat_name"

  # Set dest_file: use actual ROM filename (with extension) if available, else fallback to rom_basename
  if [ -n "$rom_file" ]; then
    rom_filename="$(basename "$rom_file")"
    dest_file="$dest_dir/${rom_filename}.cht"
    echo "Using ROM filename for cheat: $rom_filename"
  else
    dest_file="$dest_dir/${rom_basename}.cht"
    echo "Falling back to rom_basename for cheat: $rom_basename"
  fi

  encoded_system_name=$(encode_uri "$system_name")
  encoded_cheat_name=$(encode_uri "$matched_cheat_name")
  raw_url="https://raw.githubusercontent.com/libretro/libretro-database/master/cht/${encoded_system_name}/${encoded_cheat_name}"

  curl -k -sS -L -H "User-Agent: minui-cheats" -o "$dest_file" "$raw_url"
  if [ -s "$dest_file" ]; then
    echo "Cheat file downloaded: $dest_file"
    minui-presenter --message "Download finished: ${matched_cheat_name}" --timeout 0
  else
    echo "Failed to download cheat: ${matched_cheat_name}"
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

main() {
  local local_sha_file="$CACHE_DIR/sha.txt"
  local local_sha=""
  local remote_sha=""

  if [ -f "$local_sha_file" ]; then
    local_sha=$(cat "$local_sha_file")
  fi

  remote_sha=$(curl -k -sS -L -H "User-Agent: minui-cheats" "https://api.github.com/repos/libretro/libretro-database/commits/master" | jq -r '.sha')

  if [ "$local_sha" != "$remote_sha" ]; then
    fetch_root_index "$remote_sha"
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

    list_cheats_for_system "$selected_system"
    if ! display_list "$CACHE_DIR/cheats.json" "$selected_system" "$CACHE_DIR/cheats_state.json"; then
      continue
    fi
    selected_cheat_name=$(jq -r '.items[.selected].name' "$CACHE_DIR/cheats_state.json")
    selected_cheat_url=$(jq -r --arg name "$selected_cheat_name" '.items[] | select(.name == $name) | .url' "$CACHE_DIR/cheats.json")

    download_cheat "$selected_system" "$selected_cheat_name" "$selected_cheat_url"
  done
}

main