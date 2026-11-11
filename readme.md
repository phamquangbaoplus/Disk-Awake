# Disk Awake

A lightweight macOS menu bar app that helps keep external drives awake with periodic writes, with a separate option to prevent your Mac from sleeping automatically.

<p align="center">
  <img width="335" height="186" alt="screenshot" src="https://github.com/user-attachments/assets/9740b725-c310-4a7e-920b-a3c1a4cbfae9" />
</p>

## Features

- Automatically detects connected external drives.
- Keeps external drives active with a small write every 30 seconds.
- Controls periodic writes for all external drives with a single toggle.
- Keeps your Mac awake independently of drive activity.
- Displays the number of connected volumes, a countdown to the next write, and write error counts.
- Runs in the menu bar without a Dock icon.
- Pauses writes during system sleep and resumes after the display wakes.

## Usage

Open Disk Awake, then click the drive icon in the menu bar to access the controls. Connect your external drives; the app detects them automatically.

| Control | Behavior |
| --- | --- |
| **Keep Mac Awake** | Prevents automatic system sleep due to inactivity. The display can still sleep, and you can still put your Mac to sleep manually. |
| **Keep All External Drives Awake** | Turns periodic writes on or off for all external drives the app can write to. |
| **Quit** | Exits the app, stops periodic writes, and releases the request to keep your Mac awake. |

External drive activity is enabled by default on first launch, and your preference is saved between launches. **Keep Mac Awake** starts disabled each time you launch the app and applies only to the current session.

## How It Works

Disk Awake checks for connected external drives every 15 seconds. Every 30 seconds, it updates a small, hidden 4 KiB file on each drive it can write to. The file stays the same size over time. Internal drives, network drives, and read-only drives are not written to.

The hidden file is named `.disk-awake-<UUID>` and is stored at the top level of each drive.

The same file is reused and remains on the volume after the app quits. To remove it, quit Disk Awake, then delete the `.disk-awake-<UUID>` file created by the app on each volume.

Periodic writes create drive activity, but whether they prevent sleep depends on the drive or enclosure hardware and firmware. Keeping external drives active does not, by itself, prevent your Mac from sleeping.

## Troubleshooting

| Status or issue | What to check |
| --- | --- |
| **No external drives** | Confirm the drive is mounted in Finder, then allow up to 15 seconds for the next scan. |
| **Read-only drives** | Check the volume's file system and write permissions. The app skips writes to read-only volumes. |
| **Paused** | Enable **Keep All External Drives Awake** to resume periodic writes. |
| **write errors** | Check the drive connection, available space, and write access to the volume's root directory. |
| The drive still sleeps | Check the drive or enclosure's power-saving settings. Some devices manage sleep independently. |
