#!/bin/sh
# Cheats. A MinUI pak for finding and downloading cheat files (.cht)
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
CACHE_DIR="/mnt/SDCARD/.userdata/tg5040/cheats"
mkdir -p "$CACHE_DIR"

list_systems() {
  for d in "$ROM_ROOT"/*; do
    [ -d "$d" ] || continue
    case "$(basename "$d")" in
      .*) continue ;;
    esac
    basename "$d"
  done | sort -f > "$CACHE_DIR/systems.txt"

  jq -R -s '{items: split("\n")[:-1] | map({name: .}), selected: 0}' "$CACHE_DIR/systems.txt" > "$CACHE_DIR/systems.json"
}

list_roms() {
  local system_name="$1"
  local system_dir="$ROM_ROOT/$system_name"

  if [ ! -d "$system_dir" ]; then
    echo "Directory not found: $system_dir" >&2
    exit 1
  fi

  ls -p "$system_dir" | grep -v '/$' | grep -v '^\.' | sort -f > "$CACHE_DIR/roms.txt"

  if [ ! -s "$CACHE_DIR/roms.txt" ]; then
    echo "(no files found)" > "$CACHE_DIR/roms.txt"
  fi

  jq -R -s '{items: split("\n")[:-1] | map({name: .}), selected: 0}' "$CACHE_DIR/roms.txt" > "$CACHE_DIR/roms.json"
}

map_system_to_repo() {
  local system_name="$1"
  local json="$PAK_DIR/systems-mapping.json"

  # Extract the code inside parentheses from your system folder name
  local code
  code=$(echo "$system_name" | sed -n 's/.*(\(.*\)).*/\1/p')

  if [ -z "$code" ]; then
    echo ""
    return 1
  fi

  # Use jq to map code → repo folder name
  jq -r --arg key "$code" '.[$key] // empty' "$json"
}

encode_uri() {
  # Encode a string for use in a URL path segment
  # Requires jq (already bundled with your pak)
  printf '%s' "$1" | jq -Rr @uri
}

fetch_repo_index() {
  local repo_system="$1"
  local index_file="$CACHE_DIR/$(printf '%s' "$repo_system" | tr '/' '_').txt"

  # Only fetch once and cache the listing
  if [ ! -f "$index_file" ]; then
    local repo_encoded resp
    repo_encoded="$(encode_uri "$repo_system")"
    resp="$CACHE_DIR/.gh_resp.json"

    # Use -L to follow redirects and set a User-Agent to avoid some 403s
    curl -k -sS -L -H "User-Agent: minui-cheats" \
      "https://api.github.com/repos/libretro/libretro-database/contents/cht/${repo_encoded}" \
      -o "$resp"

    # Ensure we actually got an array (directory listing); otherwise, surface the error
    if jq -e 'type == "array"' "$resp" >/dev/null 2>&1; then
      jq -r '.[].name' "$resp" > "$index_file"
    else
      echo "GitHub API error: $(jq -r '.message // "unknown error"' "$resp")" >&2
      rm -f "$index_file"
      rm -f "$resp"
      return 1
    fi

    rm -f "$resp"
  fi

  echo "$index_file"
}

download_cheat() {
  local system_name="$1"
  local rom_name="$2"

  local repo_system index_file
  repo_system="$(map_system_to_repo "$system_name")"
  if [ -z "$repo_system" ]; then
    echo "No mapping found for: $system_name"
    return 1
  fi

  index_file="$(fetch_repo_index "$repo_system")" || {
    echo "Failed to fetch index for $repo_system"
    return 1
  }

  # Base ROM name (strip extension)
  local rom_base match title_only
  rom_base="${rom_name%.*}"

  # Escape regex special chars in rom_base for grep
  local rom_base_escaped
  rom_base_escaped="$(printf '%s' "$rom_base" | sed 's/[.[\*^$()+?{}|\\]/\\&/g')"

  # 1) exact starts-with (case-insensitive)
  match="$(grep -i "^${rom_base_escaped}" "$index_file" | head -n1)"

  # 2) fallback: title only up to first " ("
  if [ -z "$match" ]; then
    title_only="$(printf '%s' "$rom_base" | sed 's/ (.*//')"
    if [ -n "$title_only" ]; then
      local title_only_escaped
      title_only_escaped="$(printf '%s' "$title_only" | sed 's/[.[\*^$()+?{}|\\]/\\&/g')"
      match="$(grep -i "^${title_only_escaped}" "$index_file" | head -n1)"
    fi
  fi

  # 3) final fallback: case-insensitive contains
  if [ -z "$match" ] && [ -n "$title_only" ]; then
    local title_only_escaped
    title_only_escaped="$(printf '%s' "$title_only" | sed 's/[.[\*^$()+?{}|\\]/\\&/g')"
    match="$(grep -i "${title_only_escaped}" "$index_file" | head -n1)"
  fi

  if [ -z "$match" ]; then
    echo "No cheat match found for $rom_base"
    return 1
  fi

  # Build encoded download URL
  local repo_encoded file_encoded cht_url dest_file
  repo_encoded="$(encode_uri "$repo_system")"
  file_encoded="$(encode_uri "$match")"
  cht_url="https://raw.githubusercontent.com/libretro/libretro-database/master/cht/${repo_encoded}/${file_encoded}"
    dest_file="$CACHE_DIR/${rom_name}.cht"

  curl -k -sS -L -H "User-Agent: minui-cheats" -o "$dest_file" "$cht_url"
  if [ -s "$dest_file" ]; then
    echo "Cheat file downloaded: $dest_file"
  else
    echo "Failed to download cheat: $match"
    rm -f "$dest_file"
    return 1
  fi
}

display_list() {
  local json_file="$1"
  local title="$2"
  local state_file="$3"

  minui-list --file "$json_file" --item-key "items" --title "$title" --write-value state --write-location "$state_file"
}

main() {
  list_systems
  display_list "$CACHE_DIR/systems.json" "Select System" "$CACHE_DIR/systems_state.json"
  selected_system=$(jq -r '.items[.selected].name' "$CACHE_DIR/systems_state.json")

  list_roms "$selected_system"
  display_list "$CACHE_DIR/roms.json" "$selected_system" "$CACHE_DIR/roms_state.json"
  selected_rom=$(jq -r '.items[.selected].name' "$CACHE_DIR/roms_state.json")

  echo "User picked ROM: $selected_rom"
  download_cheat "$selected_system" "$selected_rom"
}

main