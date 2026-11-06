# steam-desktop-sorter

A PowerShell script that tidies up your desktop by sorting Steam game shortcuts (`.url` / `.lnk`) into a single folder.

Studios that have **2 or more** games get their own subfolder (`<Target>\<Studio>`); studios with only one game simply sit in the root. The studio/publisher is detected **automatically** via the Steam store API, based on the app id found in the shortcut (`steam://` or `store.steampowered.com` links).

## Usage

Sort into a fixed folder of your choice (created automatically if missing):

```powershell
powershell -ExecutionPolicy Bypass -File "Sort-GameShortcuts.ps1" -TargetDir "C:\Users\niko4\OneDrive\Skrivebord\Spilgenveje - Steam"
```

Or sort into a `Games` folder  that it creates on your desktop (default behaviour):

```powershell
powershell -ExecutionPolicy Bypass -File "Sort-GameShortcuts.ps1"
```

Preview what would happen (recommended first run): add `-WhatIf`.

Restore everything to how it was:

```powershell
powershell -ExecutionPolicy Bypass -File "Sort-GameShortcuts.ps1" -Undo
```

### Options

| Switch | Description |
| --- | --- |
| `-TargetDir "C:\path"` | Fixed destination folder; every run sorts shortcuts there (root + studio subfolders) |
| `-WhatIf` | Preview only; no files are moved |
| `-Undo` | Restore all moved shortcuts (from every run) and remove empty folders |
| `-GamesFolderName` | Folder name when not using `-TargetDir` (default: `Games`) |

## Re-runs are safe and consistent

You can run the script as many times as you like:

- With `-TargetDir`, shortcuts ALWAYS land in that same folder and its studio subfolders, no matter which desktop they came from.
- Games already sorted into a studio folder stay where they are; the same folder is reused for new games from that studio.
- Games already in the root are counted too, so once a studio reaches 2+ games they are promoted into its folder.
- Nothing is moved if it is already in the right place.
- The undo log is appended across runs, so `-Undo` restores everything from every run.

## How it works

1. Scans your desktops (including the OneDrive/"Skrivebord" desktop and the public desktop) and the root of the destination folder.
2. Extracts the Steam app id from each `.url` / `.lnk` shortcut.
3. Looks up the developer (falling back to publisher) via the Steam store API.
4. Moves shortcuts into the destination, with a subfolder per studio that has 2+ games.

A cache file (`steam-studio-cache.csv`) remembers studio lookups so re-runs are fast, and `shortcut-sort-log.csv` enables `-Undo`.

## Notes

- Shortcuts that are not Steam games are left untouched.
- The script is polite to the Steam API (cached lookups, small delay between requests).
- Windows only (uses `WScript.Shell` COM objects and Windows paths).
