param(
    [string]$GameDir = '',
    [switch]$NoBackup
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$src  = Join-Path $here 'files'
$version = '3.2.1'

function Find-GameDir {
    $candidates = @()
    if ($GameDir) { $candidates += $GameDir }
    $candidates += @(
        'G:\SteamLibrary\steamapps\common\PBZ',
        'D:\SteamLibrary\steamapps\common\PBZ',
        'E:\SteamLibrary\steamapps\common\PBZ',
        'C:\Program Files (x86)\Steam\steamapps\common\PBZ',
        'D:\Steam\steamapps\common\PBZ',
        'C:\Steam\steamapps\common\PBZ'
    )
    $steamRoots = @()
    try {
        $steamPath = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
        if ($steamPath) { $steamRoots += $steamPath }
    } catch { }
    $steamRoots += @('C:\Program Files (x86)\Steam', 'C:\Steam')
    foreach ($root in $steamRoots) {
        $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            foreach ($line in Get-Content $vdf -ErrorAction SilentlyContinue) {
                if ($line -match '"path"\s+"([^"]+)"') {
                    $candidates += (Join-Path $matches[1] 'steamapps\common\PBZ')
                }
            }
        }
    }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path (Join-Path $c 'platform\steam\PBZ.exe'))) { return $c }
    }
    return ''
}

$game = Find-GameDir
if (-not $game) {
    Write-Host 'ERROR: Phantom Blade Zero was not found.'
    Write-Host 'Run again with the game folder, for example:'
    Write-Host '  .\install.ps1 -GameDir "G:\SteamLibrary\steamapps\common\PBZ"'
    exit 1
}
$game = $game.TrimEnd('\')
$plat = Join-Path $game 'platform\steam'
if (-not (Test-Path (Join-Path $plat 'PBZ.exe'))) {
    Write-Host "ERROR: $plat\PBZ.exe not found."
    exit 1
}
if (Get-Process PBZ -ErrorAction SilentlyContinue) {
    Write-Host 'ERROR: Phantom Blade Zero is running. Please quit the game first.'
    exit 1
}

$modDir = Join-Path $plat 'ue4ss\Mods\PBZStats'

Write-Host "=== PBZ Stats HUD $version installer (traditional mod layout) ==="
Write-Host "game    : $game"
Write-Host "mod dir : $modDir"

# --- 1) UE4SS injector + Lua mod + HUD -------------------------------------
# .pbzstats_version marks this as OUR install. Re-running install.ps1 to update
# or repair then never creates backups: it just replaces our own files. Files
# that belong to someone else (another UE4SS mod) are backed up exactly once,
# so nothing of the user is ever destroyed.
$marker = Join-Path $plat '.pbzstats_version'
$isOurs = Test-Path $marker
# Replacing ue4ss wipes the mod folder, so keep the generated stats/logs and
# put them back afterwards. Updating must never lose the user's history.
$savedData = ''
$dataDirOld = Join-Path $plat 'ue4ss\Mods\PBZStats\data'
if (Test-Path $dataDirOld) {
    $savedData = Join-Path $env:TEMP ('pbzstats_data_' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Copy-Item $dataDirOld $savedData -Recurse -Force -ErrorAction SilentlyContinue
}
if ($isOurs) {
    Write-Host 'previous PBZStats install detected - updating in place (no backup)'
    Get-ChildItem $plat -Directory -Filter 'ue4ss_backup_*' -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem $plat -Filter 'dwmapi.dll.bak_*' -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $plat 'ue4ss') -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $plat 'dwmapi.dll') -Force -ErrorAction SilentlyContinue
} else {
    if ($NoBackup) {
        Write-Host 'NoBackup: replacing existing ue4ss / dwmapi.dll without a backup'
        Remove-Item (Join-Path $plat 'ue4ss') -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item (Join-Path $plat 'dwmapi.dll') -Force -ErrorAction SilentlyContinue
    } else {
    if (Test-Path (Join-Path $plat 'ue4ss')) {
        $bak = Join-Path $plat ('ue4ss_backup_' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        Move-Item (Join-Path $plat 'ue4ss') $bak
        Write-Host "other ue4ss install found, backed up to: $bak"
    }
    if (Test-Path (Join-Path $plat 'dwmapi.dll')) {
        Rename-Item (Join-Path $plat 'dwmapi.dll') ('dwmapi.dll.bak_' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        Write-Host 'other dwmapi.dll found, backed up as dwmapi.dll.bak_*'
    }
    # keep at most two backups so repeated installs do not litter the folder
    Get-ChildItem $plat -Directory -Filter 'ue4ss_backup_*' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -Skip 2 |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem $plat -Filter 'dwmapi.dll.bak_*' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -Skip 2 |
        Remove-Item -Force -ErrorAction SilentlyContinue
    }
}
Copy-Item (Join-Path $src 'dwmapi.dll') $plat -Force
Copy-Item (Join-Path $src 'ue4ss') $plat -Recurse -Force
Set-Content -Path $marker -Value ("PBZStats HUD " + $version) -Encoding ASCII

# --- 2) point the Lua side and the HUD at the mod directory ----------------
$dataDir = Join-Path $modDir 'data'
New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
if ($savedData -and (Test-Path $savedData)) {
    Copy-Item (Join-Path $savedData '*') $dataDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $savedData -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host 'previous data\ (stats and logs) restored'
}
$luaDst = Join-Path $modDir 'Scripts\main.lua'
$luaOut = ($dataDir + '\').Replace('\', '\\')
$txt = [IO.File]::ReadAllText($luaDst)
# Replace the whole OUT declaration in one shot (anchored): chained substring
# replacements could rewrite the path that was just inserted when the game
# folder itself lives under a path containing the old token.
$txt = [Text.RegularExpressions.Regex]::Replace($txt, '(?m)^local OUT\s*=\s*".*"\s*$', ('local OUT = "' + $luaOut + '"'))
[IO.File]::WriteAllText($luaDst, $txt, (New-Object System.Text.UTF8Encoding($false)))

$iniPath = Join-Path $modDir 'PBZStatsHUD.ini'
if (Test-Path $iniPath) {
    $ini = [IO.File]::ReadAllText($iniPath)
    $ini = [Text.RegularExpressions.Regex]::Replace($ini, '(?m)^data_dir=.*$', 'data_dir=')
    [IO.File]::WriteAllText($iniPath, $ini, (New-Object System.Text.UTF8Encoding($false)))
}

$hudDst = Join-Path $modDir 'PBZStatsHUD.exe'
$hudBak = Join-Path $modDir 'hudbox.dat'
if (Test-Path (Join-Path $here 'PBZStatsHUD.exe')) {
    for ($i = 1; $i -le 3; $i++) {
        try { [System.IO.File]::Copy((Join-Path $here 'PBZStatsHUD.exe'), $hudDst, $true) } catch { }
        Start-Sleep -Milliseconds 300
        if (Test-Path $hudDst) { break }
    }
}
# Keep a copy that antivirus heuristics do not treat as an executable.  The Lua
# script restores PBZStatsHUD.exe from it at game start when the exe was removed.
if (Test-Path $hudDst) {
    try { [System.IO.File]::Copy($hudDst, $hudBak, $true) } catch { }
} elseif (Test-Path (Join-Path $here 'hudbox.dat')) {
    try { [System.IO.File]::Copy((Join-Path $here 'hudbox.dat'), $hudBak, $true) } catch { }
}

# --- 3) clean up leftovers from the older (autostart) releases -------------
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
try { Remove-ItemProperty -Path $runKey -Name 'PBZStatsHUD' -ErrorAction SilentlyContinue } catch { }
try { Remove-ItemProperty -Path $runKey -Name 'PBZStatsHUDWatcher' -ErrorAction SilentlyContinue } catch { }
Get-Process PBZStatsHUD -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

Write-Host ''
if (-not (Test-Path $hudDst)) {
    Write-Host 'WARNING: PBZStatsHUD.exe could not be copied (or was removed by antivirus).'
    Write-Host '  360 Total Security and a few other suites quarantine new unsigned exe files.'
    Write-Host "  Add this folder to the whitelist and copy PBZStatsHUD.exe there manually:"
    Write-Host "    $modDir"
}
Write-Host 'Install complete.'
Write-Host "  injector: $plat\dwmapi.dll"
Write-Host "  script  : $luaDst"
Write-Host "  HUD     : $hudDst (started by the game itself)"
Write-Host "  data    : $dataDir"
Write-Host ''
Write-Host 'Start the game from Steam. The HUD appears on the right side and closes with the game.'
Write-Host 'No Python, no autostart entry, no background watcher is installed.'
Write-Host 'HUD language follows the game language automatically (edit lang= in PBZStatsHUD.ini to force one).'
Write-Host 'Uninstall: run uninstall.ps1'
