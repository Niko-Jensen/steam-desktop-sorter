# steam-desktop-sorter

A PowerShell script that tidies up your desktop by sorting Steam game shortcuts (`.url` / `.lnk`) into a single **Games** folder.

Studios that have **2 or more** games get their own subfolder (`Games\<Studio>`); studios with only one game simply sit in the `Games` root. The studio/publisher is detected **automatically** via the Steam store API, based on the app id found in the shortcut (`steam://` or `store.steampowered.com` links).

## Usage

Preview what would happen (recommended first run):

```powershell
powershell -ExecutionPolicy Bypass -File "Sort-GameShortcuts.ps1" -WhatIf
```

Sort for real:

```powershell
powershell -ExecutionPolicy Bypass -File "Sort-GameShortcuts.ps1"
```

Restore everything to how it was:

```powershell
powershell -ExecutionPolicy Bypass -File "Sort-GameShortcuts.ps1" -Undo
```

### Options

| Switch | Description |
| --- | --- |
| `-WhatIf` | Preview only; no files are moved |
| `-Undo` | Restore all moved shortcuts (from every run) and remove empty folders |
| `-GamesFolderName` | Folder name (default: `Games`) |

## Re-runs are safe and consistent

You can run the script as many times as you like:

- Games already sorted into a studio folder stay where they are; the same folder is reused for new games from that studio.
- Games already in the `Games` root are counted too, so once a studio reaches 2+ games they are promoted into its folder.
- Nothing is moved if it is already in the right place.
- The undo log is appended across runs, so `-Undo` restores everything from every run.

## How it works

1. Scans your desktops (including the OneDrive/"Skrivebord" desktop and the public desktop) and the root of each existing `Games` folder.
2. Extracts the Steam app id from each `.url` / `.lnk` shortcut.
3. Looks up the developer (falling back to publisher) via the Steam store API.
4. Moves shortcuts into `Games\`, with a subfolder per studio that has 2+ games.

A cache file (`steam-studio-cache.csv`) remembers studio lookups so re-runs are fast, and `shortcut-sort-log.csv` enables `-Undo`.

## Notes

- Shortcuts that are not Steam games are left untouched.
- The script is polite to the Steam API (cached lookups, small delay between requests).
- Windows only (uses `WScript.Shell` COM objects and Windows paths).
