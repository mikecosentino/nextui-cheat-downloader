# cheats.pak

A MinUI pak for finding and downloading cheat files (.cht)

## Requirements

This pak is designed and tested on the following MinUI Platforms and devices:
- `tg5040`: Trimui Brick

If you haven't installed [minui-screenshot-monitor-pak](https://github.com/josegonzalez/minui-screenshot-monitor-pak/) already, install it, configure a shortcut to take screenshots, and then use this pak to view the screenshots. 

## Installation

1. Mount your MinUI SD card.
2. Download the latest release from [GitHub releases](https://github.com/mikecosentino/nextui-cheats/releases). It will be named `Cheats.pak.zip`.
3. Create the folder `/Tools/$PLATFORM/Cheats.pak.`
4. Copy the zip file to `/Tools/$PLATFORM/Cheats.pak.zip`.
4. Extract the zip in place, then delete the zip file.
5. Confirm that there is a `/Tools/$PLATFORM/Cheats.pak/launch.sh` file on your SD card.
6. Unmount your SD Card and insert it into your MinUI device.

## Usage

- Browse to `Tools > Cheats` and press `A` to enter the Pak. 
- Select a system and then a game with `A` to find cheats for that game
- If a cheat file (.cht) is found, press `A` to save it to the appropriate location on your device
- Open the game, press `Menu > Options > Cheats` and turn on the cheats you want to use

## Information
 
- Cheats are downloaded to `/mnt/SDCARD/Cheats/game-syste` 

## Acknowledgements

- [minui-list](https://github.com/josegonzalez/minui-list) by Jose Diaz-Gonzalez
- [minui-presenter](https://github.com/josegonzalez/minui-presenter) by Jose Diaz-Gonzalez

