# Disk Awake

A lightweight macOS menu bar app that helps keep external drives awake with periodic writes, with a separate option to prevent your Mac from sleeping automatically.

## Features

- Automatically detects connected external drives.
- Keeps external drives active with a small write every 30 seconds.
- Controls periodic writes for all external drives with a single toggle.
- Can use the Jellyfin API to keep all external drives active while a client is connected or playing, plus a 5-minute grace period.
- Can use the same Jellyfin activity state to keep the Mac awake, with TCP 8096 retained only as a wake/bootstrap fallback.
- Keeps your Mac awake independently of drive activity.
- Displays the number of connected volumes, a countdown to the next write, and write error counts.
- Runs in the menu bar without a Dock icon.
- Automatically closes older Disk Awake instances when a new copy starts.
- Pauses writes during system sleep and resumes after the display wakes.

## Usage

Open Disk Awake, then click the drive icon in the menu bar to access the controls. Connect your external drives; the app detects them automatically.

| Control | Behavior |
| --- | --- |
| **Keep Mac Awake** | Prevents automatic system sleep due to inactivity. The display can still sleep, and you can still put your Mac to sleep manually. |
| **Keep Mac Awake for Jellyfin** | Uses the shared Jellyfin API activity monitor to keep the Mac awake during active sessions and for a 5-minute grace period. Dark Wake and TCP 8096 provide startup fallback after a network wake. |
| **Keep External Drives Awake** | Turns periodic writes on or off for all external drives the app can write to. |
| **Keep External Drives Awake for Jellyfin** | Checks the local Jellyfin server every 15 seconds and keeps writable external drives active for 5 minutes after an active connection or playback is detected. Configure the API key in **Settings**. |
| **Quit** | Exits the app, stops periodic writes, and releases the request to keep your Mac awake. |

External drive activity is enabled by default on first launch, and your preference is saved between launches. **Keep Mac Awake** starts disabled each time you launch the app and applies only to the current session.

## How It Works

Disk Awake checks for connected external drives every 15 seconds. Every 30 seconds, it updates a small, hidden 4 KiB file on each drive it can write to. The file stays the same size over time. Internal drives, network drives, and read-only drives are not written to.

When both external-drive wake controls are idle, periodic volume scans stop so metadata checks do not wake sleeping disks. The app scans once at launch, when a volume is mounted or unmounted, and while a drive-wake policy is active.

The hidden file is named `.disk-awake-<UUID>` and is stored at the top level of each drive.

The same file is reused and remains on the volume after the app quits. To remove it, quit Disk Awake, then delete the `.disk-awake-<UUID>` file created by the app on each volume.

Periodic writes create drive activity, but whether they prevent sleep depends on the drive or enclosure hardware and firmware. Keeping external drives active does not, by itself, prevent your Mac from sleeping.

The Jellyfin server is fixed at `http://localhost:8096`. The API key is stored in app preferences. One shared monitor requests `/Sessions` every 15 seconds with a 60-second activity window and never places the API key in the URL. Both Jellyfin switches consume this shared state, so enabling both does not create duplicate API polling.

## Troubleshooting

| Status or issue | What to check |
| --- | --- |
| **No external drives** | Confirm the drive is mounted in Finder, then allow up to 15 seconds for the next scan. |
| **Read-only drives** | Check the volume's file system and write permissions. The app skips writes to read-only volumes. |
| **Paused** | Enable **Keep External Drives Awake** to resume periodic writes. |
| **write errors** | Check the drive connection, available space, and write access to the volume's root directory. |
| The drive still sleeps | Check the drive or enclosure's power-saving settings. Some devices manage sleep independently. |
