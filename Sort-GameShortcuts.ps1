# Sort-GameShortcuts.ps1
# Sorts game shortcuts (.url / .lnk) from your desktop into a single "Games" folder.
# Studios that have 2+ games get their own subfolder (Games\<Studio>);
# studios with only one game just sit in the Games root.
#
# RE-RUNS ARE SAFE: games already inside the Games folder are taken into account,
# so a studio folder created earlier is reused, and games previously left in the
# Games root are promoted into their studio folder once that studio reaches 2+ games.
#
# The game's studio/publisher is detected AUTOMATICALLY via the Steam store API,
# based on the app id found in the shortcut (steam:// or store.steampowered.com links).
#
# USAGE:
#   powershell -ExecutionPolicy Bypass -File "Sort-GameShortcuts.ps1"            (sorts for real)
#   powershell -ExecutionPolicy Bypass -File "Sort-GameShortcuts.ps1" -WhatIf      (preview only)
#   powershell -ExecutionPolicy Bypass -File "Sort-GameShortcuts.ps1" -Undo        (restore everything)
#
# A cache file (steam-studio-cache.csv) remembers studio lookups so re-runs are fast,
# and shortcut-sort-log.csv enables -Undo (moves from ALL runs are kept in the log).

param(
    [switch]$WhatIf,
    [switch]$Undo,
    [string]$GamesFolderName = 'Games'
)

$ErrorActionPreference = 'Stop'

$LogFile  = Join-Path $PSScriptRoot 'shortcut-sort-log.csv'
$CacheFile = Join-Path $PSScriptRoot 'steam-studio-cache.csv'

# ---------- UNDO MODE ----------
if ($Undo) {
    if (-not (Test-Path $LogFile)) { Write-Host "No log file found - nothing to undo."; exit }
    foreach ($entry in (Import-Csv $LogFile)) {
        if (Test-Path -LiteralPath $entry.Destination) {
            Move-Item -LiteralPath $entry.Destination -Destination $entry.Original -Force
            Write-Host "Restored: $(Split-Path $entry.Destination -Leaf)"
        }
    }
    # clean up empty folders we created
    foreach ($entry in (Import-Csv $LogFile)) {
        $dir = Split-Path $entry.Destination -Parent
        if (Test-Path -LiteralPath $dir -and -not (Get-ChildItem -LiteralPath $dir -Recurse)) {
            Remove-Item -LiteralPath $dir -Force -ErrorAction SilentlyContinue
        }
    }
    Remove-Item $LogFile -Force
    Write-Host "`nUndo complete."
    exit
}

# ---------- LOCATE DESKTOPS ----------
# Includes the normal desktop, the OneDrive desktop ("Skrivebord" in Danish), and the public desktop
$DesktopDirs = @([Environment]::GetFolderPath('Desktop'))
$od = [Environment]::GetEnvironmentVariable('OneDrive')
if ($od) {
    foreach ($name in @('Skrivebord', 'Desktop')) {
        $p = Join-Path $od $name
        if ((Test-Path $p) -and $DesktopDirs -notcontains $p) { $DesktopDirs += $p }
    }
}
$pub = 'C:\Users\Public\Desktop'
if ((Test-Path $pub) -and $DesktopDirs -notcontains $pub) { $DesktopDirs += $pub }

Write-Host "Scanning desktop(s): $($DesktopDirs -join ' ; ')`n"

# ---------- HELPERS ----------
$shell = New-Object -ComObject WScript.Shell

# Load studio cache (appid -> studio)
$Cache = @{}
if (Test-Path $CacheFile) {
    Import-Csv $CacheFile | ForEach-Object { $Cache[$_.AppId] = $_.Studio }
}

function Save-Cache {
    $Cache.GetEnumerator() | ForEach-Object {
        [pscustomobject]@{ AppId = $_.Key; Studio = $_.Value }
    } | Export-Csv -Path $CacheFile -NoTypeInformation -Encoding UTF8
}

# Extract a Steam app id from any kind of shortcut string
function Get-SteamAppId([string]$s) {
    if (-not $s) { return $null }
    # only accept realistic Steam app ids (1-9 digits, no leading zero)
    if ($s -match 'store\.steampowered\.com/app/([1-9][0-9]{0,8})') { return $Matches[1] }
    if ($s -match 'steam://rungameid/([1-9][0-9]{0,8})')           { return $Matches[1] }
    if ($s -match 'steam://store/([1-9][0-9]{0,8})')               { return $Matches[1] }
    # a .url file that is actually a Steam shortcut ("steam.url" style)
    if ($s -match 'rungameid=([1-9][0-9]{0,8})')                    { return $Matches[1] }
    return $null
}

# Look up the studio (developer, falling back to publisher) via the Steam store API
function Get-SteamStudio([string]$appId) {
    if ($Cache.ContainsKey($appId)) { return $Cache[$appId] }
    $studio = $null
    try {
        $resp = Invoke-RestMethod -Uri "https://store.steampowered.com/api/appdetails?appids=$appId&l=english" -TimeoutSec 15
        $data = $resp.PSObject.Properties[$appId.ToString()].Value.data
        if ($data) {
            $studio = @($data.developers)[0]
            if (-not $studio) { $studio = @($data.publishers)[0] }
        }
        Start-Sleep -Milliseconds 350   # be polite to the API
    } catch {
        Write-Host "  (lookup failed for app $appId - will place in Games root)"
    }
    $Cache[$appId] = $studio
    return $studio
}

function Sanitize([string]$name) {
    if (-not $name) { return 'Other' }
    return ($name -replace '[\\/:*?"<>|]', '').Trim()
}

# ---------- PASS 1: COLLECT GAME SHORTCUTS & LOOK UP STUDIOS ----------
# We scan BOTH the desktops AND the root of each existing Games folder.
# Games already inside a studio subfolder stay put; games in the Games root
# can be promoted into their studio folder on a later run.
$items = New-Object System.Collections.Generic.List[object]

$scanDirs = New-Object System.Collections.Generic.List[object]
foreach ($desktop in ($DesktopDirs | Select-Object -Unique)) {
    $scanDirs.Add([pscustomobject]@{ Dir = $desktop; Kind = 'Desktop' })
    $gamesRoot = Join-Path $desktop $GamesFolderName
    if (Test-Path -LiteralPath $gamesRoot) {
        $scanDirs.Add([pscustomobject]@{ Dir = $gamesRoot; Kind = 'GamesRoot' })
    }
}

foreach ($scan in $scanDirs) {
    Get-ChildItem -LiteralPath $scan.Dir -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Extension -in '.url', '.lnk' } |
    ForEach-Object {
        $file = $_
        $linkString = ''
        if ($file.Extension -eq '.url') {
            # .url files are INI-style; grab the URL= line
            $line = Select-String -LiteralPath $file.FullName -Pattern '^URL\s*=\s*(.+)$' |
                    Select-Object -First 1
            if ($line) { $linkString = $line.Matches[0].Groups[1].Value.Trim() }
        } else {
            try { $linkString = $shell.CreateShortcut($file.FullName).TargetPath } catch {}
        }

        $appId = Get-SteamAppId $linkString
        if (-not $appId) { return }   # not a Steam game -> leave untouched

        Write-Host "Found Steam game: $($file.Name)  (app $appId)"
        $studio = Get-SteamStudio $appId
        if ($studio) { Write-Host "  Studio: $studio" }

        $items.Add([pscustomobject]@{
            File   = $file
            AppId  = $appId
            Studio = $studio
            Kind   = $scan.Kind   # 'Desktop' = new shortcut, 'GamesRoot' = already sorted into Games root
        })
    }
}

if ($items.Count -eq 0) { Write-Host "`nNo Steam game shortcuts found. Nothing to do."; exit }

# ---------- PASS 2: WHICH STUDIOS GET THEIR OWN FOLDER? ----------
# Counts include games already sitting in the Games folder, so studios that
# reached 2+ games since the last run get their folder, and everything stays consistent.
$studioCounts = @{}
foreach ($i in $items) {
    if ($i.Studio) {
        $key = $i.Studio.ToLower()
        if (-not $studioCounts[$key]) { $studioCounts[$key] = @{ Name = $i.Studio; Count = 0 } }
        $studioCounts[$key].Count++
    }
}
$multiGameStudios = $studioCounts.Values | Where-Object { $_.Count -ge 2 } |
                    ForEach-Object { $_.Name.ToLower() }

Write-Host "`nStudios with 2+ games (get their own folder): " $(($studioCounts.Values | Where-Object { $_.Count -ge 2 } | ForEach-Object { "$($_.Name) ($($_.Count))" }) -join ', ')

# ---------- PASS 3: MOVE ----------
$moved = New-Object System.Collections.Generic.List[object]

foreach ($scan in $scanDirs) {
    $desktop = $scan.Dir
    $gamesRoot = if ($scan.Kind -eq 'Desktop') { Join-Path $desktop $GamesFolderName } else { $desktop }

    foreach ($i in ($items | Where-Object { $_.File.DirectoryName -eq $scan.Dir })) {
        # decide destination folder
        if ($i.Studio -and $i.Studio.ToLower() -in $multiGameStudios) {
            $subfolder = Sanitize $i.Studio
        } else {
            $subfolder = ''   # stays in Games root
        }

        # shortcuts already in the Games root only need to move if they now belong in a studio folder
        if ($i.Kind -eq 'GamesRoot' -and -not $subfolder) { continue }

        $destDir = if ($subfolder) { Join-Path $gamesRoot $subfolder } else { $gamesRoot }
        $dest = Join-Path $destDir $i.File.Name

        # skip if the file is already exactly where it should be
        if ($i.File.FullName -eq $dest) { continue }

        $label = "$GamesFolderName$(if ($subfolder) { '\' + $subfolder } else { '' })"

        if ($WhatIf) {
            Write-Host "[PREVIEW] $($i.File.Name)  ->  $label\"
        } else {
            if (-not (Test-Path -LiteralPath $destDir)) { New-Item -ItemType Directory -Path $destDir | Out-Null }
            Move-Item -LiteralPath $i.File.FullName -Destination $dest -Force
            Write-Host "Moved: $($i.File.Name)  ->  $label\"
            $moved.Add([pscustomobject]@{
                Name        = $i.File.Name
                Studio      = $i.Studio
                AppId       = $i.AppId
                Original    = $i.File.FullName
                Destination = $dest
            })
        }
    }
}

if ($WhatIf) {
    Write-Host "`nPreview complete. Run without -WhatIf to actually move the files."
} else {
    # APPEND to the log so -Undo can restore moves from every run, not just the latest
    $allMoves = @()
    if (Test-Path $LogFile) { $allMoves = @(Import-Csv $LogFile) }
    $allMoves += $moved
    if ($moved.Count -gt 0) {
        $allMoves | Export-Csv -Path $LogFile -NoTypeInformation -Encoding UTF8
    }
    Save-Cache
    if ($moved.Count -gt 0) {
        Write-Host "`nDone! $($moved.Count) game shortcut(s) sorted into '$GamesFolderName'. Log updated for -Undo."
    } else {
        Write-Host "`nEverything already sorted - nothing to move."
    }
}
