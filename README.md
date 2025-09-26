# Cheat Downloader.pak

A MinUI pak for downloading cheat files from the Libretro database

## Requirements

This pak is designed and tested on the following MinUI Platforms and devices:
- `tg5040`: Trimui Brick and Trimui Smart Pro

## Known Issues

- Cheat file (.cht) have to be stored in a specific location with a specific file name. I am working on the functionality to automatically find your locally installed game so that the .cht file is appropriately named. For now you need to manually select the game and it'll handle naming and storing the .cht file

## Installation

1. Mount your MinUI SD card.
2. Download the latest release from [GitHub releases](https://github.com/mikecosentino/nextui-cheat-downloader/releases). It will be named `Cheat Downloader.pak.zip`.
3. Create the folder `/Tools/$PLATFORM/Cheat Downloader.pak.`
4. Copy the zip file to `/Tools/$PLATFORM/Cheat Downloader.pak.zip`.
4. Extract the zip in place, then delete the zip file.
5. Confirm that there is a `/Tools/$PLATFORM/Cheat Downloader.pak/launch.sh` file on your SD card.
6. Unmount your SD Card and insert it into your MinUI device.

## Usage

- Browse to `Tools > Cheat Downloader` and press `A` to enter the Pak. 
- Select a system with `A`
- Select a cheat with `A` 
- Cheat Downloader will check your Roms folder to try find a matching Rom in order to download the correct cheat for your rom
- After confirmation that the rom was downloaded
- Open the game, press `Menu > Options > Cheats` and turn on the cheats you want to use

## Information
 
- Cheats are downloaded to `/mnt/SDCARD/Cheats/` in folders for each system 

## Acknowledgements

- [minui-list](https://github.com/josegonzalez/minui-list) by Jose Diaz-Gonzalez
- [minui-presenter](https://github.com/josegonzalez/minui-presenter) by Jose Diaz-Gonzalez
