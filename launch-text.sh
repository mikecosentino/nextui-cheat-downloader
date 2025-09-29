#!/bin/sh
# Launch-Test with aliases.json support
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
ROMS_DIR="/mnt/SDCARD/Roms"
CACHE_DIR="/mnt/SDCARD/.userdata/tg5040/$PAK_NAME"
mkdir -p "$CACHE_DIR"

ALIASES_FILE="$CACHE_DIR/aliases.json"

# Create aliases.json if it doesn’t exist
if [ ! -f "$ALIASES_FILE" ]; then
cat > "$ALIASES_FILE" <<'EOF'
{
  "Game Boy Advance": ["GBA", "MGBA"],
  "SNES": ["SFC", "SUPA"],
  "Pico-8": ["P8", "PICO"]
}
EOF
fi

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

build_systems() {
    selected_system="$1"
    show_status "Caching all systems..."
    ls -1 "$ROMS_DIR/" > "$CACHE_DIR/all_systems.txt"
    hide_status
}

build_system() {
    selected_system="$1"
    show_status "Loading $selected_system..."
    ls -1 "$ROMS_DIR/$selected_system" > "$CACHE_DIR/${selected_system}.txt"
    hide_status
}

display_list() {
  local file="$1"
  local title="$2"
  local selected="$3"

  minui-list --file "$CACHE_DIR/$file" --format "text" --title "$title" --write-value state --write-location "$selected" --disable-auto-sleep
  local result=$?
  if [ $result -ne 0 ]; then
    echo "User pressed Back at $title"
    return 1
  fi
}

display_game() {
    local text_file="$1"
    local title="$2"
    
    minui-list --format "text" --file "$CACHE_DIR/$text_file" --title "$title" --disable-auto-sleep
    local result=$?
    if [ $result -ne 0 ]; then
        echo "User pressed Back at $title"
        return 1
    fi
}

main() {
    # Step 1: Build all systems list
    build_systems

    # Step 2: Show systems list
    display_list "all_systems.txt" "Select System" "$CACHE_DIR/selected_system.txt" || exit 0
    selected_system="$(jq -r '.items[.selected].name' "$CACHE_DIR/selected_system.txt")"
    echo "User selected system: $selected_system"

    # Step 3: Build games list for system
    build_system "$selected_system"

    # Step 4: Show games list
    display_list "${selected_system}.txt" "Select Game" "$CACHE_DIR/selected_game.txt" || exit 0
    selected_game="$(jq -r '.items[.selected].name' "$CACHE_DIR/selected_game.txt")"
    echo "User selected game: $selected_game"
}

main