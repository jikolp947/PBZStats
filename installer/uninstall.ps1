param(
    [string]$GameDir = '',
    [switch]$KeepData
)
$ErrorActionPreference = 'Continue'

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
    try {
        $steamPath = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
        if ($steamPath) {
            $vdf = Join-Path $steamPath 'steamapps\libraryfolders.vdf'
            if (Test-Path $vdf) {
                foreach ($line in Get-Content $vdf -ErrorAction SilentlyContinue) {
                    if ($line -match '"path"\s+"([^"]+)"') {
                        $candidates += (Join-Path $matches[1] 'steamapps\common\PBZ')
                    }
                }
            }
        }
    } catch { }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path (Join-Path $c 'platform\steam\PBZ.exe'))) { return $c }
    }
    return ''
}

$game = Find-GameDir
$plat = ''
if ($game) { $plat = Join-Path $game.TrimEnd('\') 'platform\steam' }
$modDir = ''
if ($plat) { $modDir = Join-Path $plat 'ue4ss\Mods\PBZStats' }

Write-Host '=== PBZ Stats HUD uninstaller ==='

Get-Process PBZStatsHUD -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
try { Remove-ItemProperty -Path $runKey -Name 'PBZStatsHUD' -ErrorAction SilentlyContinue } catch { }
try { Remove-ItemProperty -Path $runKey -Name 'PBZStatsHUDWatcher' -ErrorAction SilentlyContinue } catch { }

if ($plat -and (Test-Path $plat)) {
    if (Get-Process PBZ -ErrorAction SilentlyContinue) {
        Write-Host 'NOTE: the game is still running; close it first so the mod files can be removed.'
    }
    if ($KeepData -and $modDir -and (Test-Path $modDir)) {
        $backup = Join-Path $env:LOCALAPPDATA ('PBZStats_backup_' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        New-Item -ItemType Directory -Force $backup | Out-Null
        foreach ($n in @('stats.txt', 'stats.json', 'pbz_boss_deaths.txt', 'pbz_last_total.txt', 'pbz_last_boss.txt', 'pbzstats.log')) {
            $f = Join-Path $modDir $n
            if (Test-Path $f) { Copy-Item $f $backup -Force }
        }
        Write-Host "kept statistics copy: $backup"
    }
    if ($modDir -and (Test-Path $modDir)) {
        Remove-Item $modDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host 'removed: Mods\PBZStats'
    }
    $ue = Join-Path $plat 'ue4ss'
    if (Test-Path $ue) {
        $builtin = @('shared', 'BPML_GenericFunctions', 'BPModLoaderMod',
            'CheatManagerEnablerMod', 'ConsoleCommandsMod', 'ConsoleEnablerMod',
            'Keybinds', 'LineTraceMod', 'SplitScreenMod')
        $other = Get-ChildItem (Join-Path $ue 'Mods') -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne 'PBZStats' -and $_.Name -notin $builtin }
        if (-not $other) {
            Remove-Item $ue -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host 'removed: ue4ss folder (no other mods found)'
        } else {
            Write-Host 'kept: ue4ss folder (other mods present)'
        }
    }
    $marker = Join-Path $plat '.pbzstats_version'
    if (Test-Path $marker) { Remove-Item $marker -Force -ErrorAction SilentlyContinue }
    $dll = Join-Path $plat 'dwmapi.dll'
    if (Test-Path $dll) {
        $bak = Get-ChildItem $plat -Filter 'dwmapi.dll.bak_*' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        Remove-Item $dll -Force -ErrorAction SilentlyContinue
        if ($bak) {
            Rename-Item $bak.FullName (Join-Path $plat 'dwmapi.dll')
            Write-Host 'restored: original dwmapi.dll'
        } else {
            Write-Host 'removed: dwmapi.dll'
        }
    }
    Write-Host ''
    Write-Host 'Game files were restored (exe / paks / saves are never modified).'
} else {
    Write-Host 'Game folder not found.'
}

# clean legacy data directory from the 2.x releases
$legacy = Join-Path $env:LOCALAPPDATA 'PBZStats'
if ((-not $KeepData) -and (Test-Path $legacy)) {
    Remove-Item $legacy -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "removed legacy data: $legacy"
}
