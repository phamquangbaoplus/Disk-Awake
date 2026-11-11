# Disk Awake

A lightweight macOS menu bar app that helps keep external drives awake with periodic writes, with a separate option to prevent your Mac from sleeping automatically.

## Features

- Automatically detects mounted external volumes.
- Writes 4 KiB every 30 seconds to each writable external volume.
- Controls periodic writes for all external drives with a single toggle.
- Keeps your Mac awake independently of drive activity.
- Displays the connected volume count, a countdown to the next write, and write error counts.
- Runs in the menu bar without a Dock icon.
- Pauses writes during system sleep and resumes after the display wakes.

## Requirements

- **macOS 27.2 or later**, based on the project's current deployment target.
- An Xcode version that supports the project format and required SDK. The project currently records Xcode 27.2 as its last upgrade version.
- Write access to the root directory of each external volume you want to keep active.

## Build from Source

1. Clone the repository and open the project:

   ```sh
   git clone https://github.com/phamquangbaoplus/Disk-Awake.git
   cd Disk-Awake
   open "Disk Awake.xcodeproj"
   ```

2. Select the **Disk Awake** scheme and **My Mac** as the run destination.
3. If Xcode requests signing configuration, select your development team under **Signing & Capabilities**.
4. Press **Command-R** to build and run.
5. Click the drive icon in the menu bar to open the controls.

## Usage

| Control | Behavior |
| --- | --- |
| **Keep Mac Awake** | Prevents automatic system sleep due to inactivity. The display can still sleep, and you can still put your Mac to sleep manually. |
| **Keep All External Drives Awake** | Enables or disables periodic writes to all writable external volumes. |
| **Quit** | Exits the app, stops periodic writes, and releases the request to keep your Mac awake. |

External drive activity is enabled by default on first launch, and your preference is saved between launches. **Keep Mac Awake** starts disabled each time you launch the app and applies only to the current session.

## How It Works

Disk Awake scans mounted volumes every 15 seconds. It selects local volumes that macOS identifies as external and skips hidden volumes. Internal drives and network shares are excluded. Read-only volumes are detected but never written to.

For each writable external volume, the app creates a hidden file named `.disk-awake-<UUID>` in the volume's root directory. Each write replaces its contents with 4 KiB of random data, keeps the file at 4 KiB, and requests synchronization to the drive using `F_FULLFSYNC`, falling back to `fsync` if needed. The file is closed after each write.

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

## Project Structure

| Path | Purpose |
| --- | --- |
| `Disk Awake/MyApp.swift` | App entry point and menu bar setup. |
| `Disk Awake/ContentView.swift` | Controls, status indicators, and write countdown. |
| `Disk Awake/DiskAwakeModel.swift` | Volume discovery, periodic writes, and sleep/wake handling. |
| `Disk Awake/Localizable.xcstrings` | Interface strings and translations. |

## Contributing

Bug reports and feature requests are welcome through [GitHub Issues](https://github.com/phamquangbaoplus/Disk-Awake/issues). For drive-related issues, include your macOS version, drive or enclosure model, volume format, and steps to reproduce the problem.

## License

This repository does not currently include a `LICENSE` file.
