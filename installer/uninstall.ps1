param(
    [string]$GameDir = '',
    [switch]$KeepData,
    [switch]$NoPause
)
$ErrorActionPreference = 'Continue'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath = Join-Path $env:TEMP ('PBZStats_uninstall_' + $stamp + '.log')

# ---------------------------------------------------------------------------
# Same status vocabulary as install.ps1: [n/total] steps, OK/WARN/FAIL lines
# and a final checklist, so it is obvious whether the mod is really gone.
# ---------------------------------------------------------------------------
$script:step = 0
$script:total = 8
$script:warnings = 0
$script:failures = 0
$script:checks = @()

function Write-Head([string]$text) {
    Write-Host ''
    Write-Host ('=' * 68) -ForegroundColor DarkGray
    Write-Host $text -ForegroundColor White
    Write-Host ('=' * 68) -ForegroundColor DarkGray
}
function Write-Step([string]$text) {
    $script:step++
    Write-Host ''
    Write-Host ('[{0}/{1}] {2}' -f $script:step, $script:total, $text) -ForegroundColor Cyan
}
function Write-Ok([string]$text) { Write-Host ('       OK    ' + $text) -ForegroundColor Green }
function Write-Info([string]$text) { Write-Host ('             ' + $text) -ForegroundColor DarkGray }
function Write-Warn([string]$text) { $script:warnings++; Write-Host ('       WARN  ' + $text) -ForegroundColor Yellow }
function Write-Fail([string]$text) { $script:failures++; Write-Host ('       FAIL  ' + $text) -ForegroundColor Red }
function Add-Check([string]$name, [bool]$ok, [string]$detail) {
    $script:checks += [pscustomobject]@{ Name = $name; Ok = $ok; Detail = $detail }
    if ($ok) { Write-Ok ($name + ': ' + $detail) } else { Write-Fail ($name + ': ' + $detail) }
}

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

function Wait-IfDoubleClicked {
    if ($NoPause) { return }
    try {
        $parentId = (Get-CimInstance Win32_Process -Filter ("ProcessId=$PID")).ParentProcessId
        $parent = Get-Process -Id $parentId -ErrorAction SilentlyContinue
        if ($parent -and $parent.ProcessName -eq 'explorer') {
            Write-Host ''
            Read-Host 'Press Enter to close this window'
        }
    } catch { }
}

$transcript = $false
try { Start-Transcript -Path $logPath -Force | Out-Null; $transcript = $true } catch { }

try {
    Write-Head 'PBZ Stats HUD - uninstaller / 卸载程序'
    Write-Host ('log file : ' + $logPath) -ForegroundColor DarkGray

    # --- 1) stop HUD + autostart -----------------------------------------
    Write-Step 'Stopping HUD and removing autostart / 关闭 HUD 与自启动'
    $hud = Get-Process PBZStatsHUD -ErrorAction SilentlyContinue
    if ($hud) {
        $hud | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 400
        if (Get-Process PBZStatsHUD -ErrorAction SilentlyContinue) { Write-Warn 'PBZStatsHUD.exe is still running' }
        else { Write-Ok 'HUD process stopped' }
    }

    # PowerShell host (no-exe overlay): stop any powershell.exe running our run.ps1
    $psHost = @()
    try {
        # Match only the real launcher form ("-File ...\run.ps1") and never the shell
        # running this uninstaller: a terminal whose command line merely mentions
        # run.ps1 (documentation, notes, another script) must not be killed.
        $psHost = Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
                  Where-Object {
                      $_.ProcessId -ne $PID -and
                      $_.CommandLine -and
                      $_.CommandLine -match '-File\s+"?[^"]*run\.ps1' -and
                      $_.CommandLine -notmatch 'install\.ps1|uninstall\.ps1'
                  }
    } catch { }
    if ($psHost) {
        foreach ($proc in $psHost) { Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Milliseconds 400
        Write-Ok ('PowerShell HUD host stopped (' + $psHost.Count + ')')
    } else {
        Write-Info 'PowerShell HUD host is not running'
    }
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $removedKeys = 0
    foreach ($name in @('PBZStatsHUD', 'PBZStatsHUDWatcher')) {
        try {
            $existing = Get-ItemProperty -Path $runKey -Name $name -ErrorAction SilentlyContinue
            if ($existing) { Remove-ItemProperty -Path $runKey -Name $name -ErrorAction SilentlyContinue; $removedKeys++ }
        } catch { }
    }
    if ($removedKeys -gt 0) { Write-Ok ("removed $removedKeys autostart entr(y/ies)") }
    else { Write-Info 'no autostart entries found' }

    # --- 2) locate the game ----------------------------------------------
    Write-Step 'Locating Phantom Blade Zero / 查找游戏目录'
    $game = Find-GameDir
    $plat = ''
    $modDir = ''
    if ($game) {
        $game = $game.TrimEnd('\')
        $plat = Join-Path $game 'platform\steam'
        $modDir = Join-Path $plat 'ue4ss\Mods\PBZStats'
        Write-Ok ('game folder: ' + $game)
    } else {
        Write-Warn 'game folder not found - only leftover data will be cleaned'
        Write-Warn '未找到游戏目录：只清理残留数据。可用 -GameDir 参数指定。'
    }

    $gameRunning = $false
    if ($plat -and (Get-Process PBZ -ErrorAction SilentlyContinue)) {
        $gameRunning = $true
        Write-Warn 'the game is still running - close it so the files can be removed'
        Write-Warn '游戏正在运行，关闭游戏后才能删除文件'
    }

    $modDirExisted = $false
    $ue4ssExisted = $false
    $markerExisted = $false
    $dwmapiExisted = $false
    $dwmapiRestored = $false
    $ue4ssKept = $false

    if ($plat -and (Test-Path $plat)) {
        $modDirExisted = Test-Path $modDir
        $ue4ssExisted = Test-Path (Join-Path $plat 'ue4ss')
        $markerExisted = Test-Path (Join-Path $plat '.pbzstats_version')
        $dwmapiExisted = Test-Path (Join-Path $plat 'dwmapi.dll')

        # --- 3) optional statistics backup --------------------------------
        Write-Step 'Statistics backup / 统计数据备份'
        if (-not $modDirExisted) {
            Write-Info 'no mod folder, nothing to back up'
        } elseif ($KeepData) {
            $backup = Join-Path $env:LOCALAPPDATA ('PBZStats_backup_' + $stamp)
            New-Item -ItemType Directory -Force $backup | Out-Null
            $statsDir = Join-Path $modDir 'data'
            if (-not (Test-Path $statsDir)) { $statsDir = $modDir }
            $copied = 0
            foreach ($n in @('stats.txt', 'stats.json', 'pbz_boss_deaths.txt', 'pbz_last_total.txt', 'pbz_last_boss.txt', 'pbzstats.log', 'hud.log')) {
                $f = Join-Path $statsDir $n
                if (Test-Path $f) { Copy-Item $f $backup -Force -ErrorAction SilentlyContinue; $copied++ }
            }
            if ($copied -gt 0) {
                Write-Ok ("$copied files copied, statistics kept at " + $backup)
            } else {
                Remove-Item $backup -Recurse -Force -ErrorAction SilentlyContinue
                Write-Warn 'no statistics files were found to keep'
            }
        } else {
            Write-Info 'statistics will be deleted (use -KeepData to keep a copy)'
        }

        # --- 4) remove the mod folder -------------------------------------
        Write-Step 'Removing mod files / 删除 mod 文件'
        if ($modDirExisted) {
            Remove-Item $modDir -Recurse -Force -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 200
            if (Test-Path $modDir) {
                Write-Fail ('could not delete ' + $modDir)
                if ($gameRunning) { Write-Info 'close the game and run the uninstaller again' }
            } else {
                Write-Ok 'removed ue4ss\Mods\PBZStats'
            }
        } else {
            Write-Info 'ue4ss\Mods\PBZStats does not exist'
        }

        # --- 5) ue4ss folder (only when no other mods) --------------------
        Write-Step 'Removing UE4SS injector / 删除 UE4SS 注入器'
        $ue = Join-Path $plat 'ue4ss'
        if (Test-Path $ue) {
            $builtin = @('shared', 'BPML_GenericFunctions', 'BPModLoaderMod',
                'CheatManagerEnablerMod', 'ConsoleCommandsMod', 'ConsoleEnablerMod',
                'Keybinds', 'LineTraceMod', 'SplitScreenMod')
            $other = Get-ChildItem (Join-Path $ue 'Mods') -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -ne 'PBZStats' -and $_.Name -notin $builtin }
            if ($other) {
                $ue4ssKept = $true
                Write-Warn ('kept ue4ss folder - other mods are installed: ' + (($other | ForEach-Object { $_.Name }) -join ', '))
                Write-Info '删除后会破坏其它 UE4SS mod，因此保留 ue4ss 目录'
            } else {
                Remove-Item $ue -Recurse -Force -ErrorAction SilentlyContinue
                if (Test-Path $ue) { Write-Fail 'could not delete the ue4ss folder' }
                else { Write-Ok 'removed ue4ss folder (no other mods found)' }
            }
        } else {
            Write-Info 'ue4ss folder does not exist'
        }

        # --- 6) marker ----------------------------------------------------
        Write-Step 'Removing install marker / 删除安装标记'
        $marker = Join-Path $plat '.pbzstats_version'
        if (Test-Path $marker) {
            Remove-Item $marker -Force -ErrorAction SilentlyContinue
            if (Test-Path $marker) { Write-Fail 'could not delete .pbzstats_version' }
            else { Write-Ok 'removed .pbzstats_version' }
        } else {
            Write-Info '.pbzstats_version does not exist'
        }

        # --- 7) restore the original dwmapi.dll ---------------------------
        Write-Step 'Restoring original dwmapi.dll / 还原原始 dwmapi.dll'
        $dll = Join-Path $plat 'dwmapi.dll'
        if (Test-Path $dll) {
            $bak = Get-ChildItem $plat -Filter 'dwmapi.dll.bak_*' -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            Remove-Item $dll -Force -ErrorAction SilentlyContinue
            if (Test-Path $dll) {
                Write-Fail 'could not delete dwmapi.dll (game still running?)'
            } elseif ($bak) {
                try {
                    Rename-Item $bak.FullName (Join-Path $plat 'dwmapi.dll')
                    $dwmapiRestored = $true
                    Write-Ok ('original dwmapi.dll restored from ' + $bak.Name)
                } catch {
                    Write-Fail ('could not restore ' + $bak.Name + ': ' + $_.Exception.Message)
                }
            } else {
                Write-Ok 'removed the mod dwmapi.dll (there was no original to restore)'
            }
        } else {
            Write-Info 'dwmapi.dll not present - already clean'
        }
    } else {
        Write-Step 'Statistics backup / 统计数据备份'
        Write-Step 'Removing mod files / 删除 mod 文件'
        Write-Step 'Removing UE4SS injector / 删除 UE4SS 注入器'
        Write-Step 'Removing install marker / 删除安装标记'
        Write-Step 'Restoring original dwmapi.dll / 还原原始 dwmapi.dll'
        Write-Info 'skipped - game folder unknown'
    }

    # --- 8) legacy data + verify ------------------------------------------
    Write-Step 'Cleaning legacy data and verifying / 清理旧数据并校验'
    $legacy = Join-Path $env:LOCALAPPDATA 'PBZStats'
    if ($KeepData) {
        Write-Info ('legacy data kept: ' + $legacy)
    } elseif (Test-Path $legacy) {
        Remove-Item $legacy -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $legacy) { Write-Warn 'could not delete legacy data folder' }
        else { Write-Ok ('removed legacy data: ' + $legacy) }
    } else {
        Write-Info 'no legacy data folder'
    }

    if ($plat -and (Test-Path $plat)) {
        $modStillThere = Test-Path $modDir
        Add-Check 'mod folder removed' (-not $modStillThere) $modDir
        Add-Check 'install marker removed' (-not (Test-Path (Join-Path $plat '.pbzstats_version'))) (Join-Path $plat '.pbzstats_version')
        if ($dwmapiExisted) {
            $dllNow = Test-Path (Join-Path $plat 'dwmapi.dll')
            if ($dwmapiRestored) {
                Add-Check 'dwmapi.dll' $dllNow 'original restored'
            } else {
                Add-Check 'dwmapi.dll' (-not $dllNow) 'mod version removed'
            }
        } else {
            Add-Check 'dwmapi.dll' (-not (Test-Path (Join-Path $plat 'dwmapi.dll'))) 'not present (nothing to remove)'
        }
        if ($ue4ssKept) {
            Write-Host '       INFO  ue4ss folder kept on purpose (other mods)' -ForegroundColor DarkGray
        } else {
            Add-Check 'ue4ss folder removed' (-not (Test-Path (Join-Path $plat 'ue4ss'))) (Join-Path $plat 'ue4ss')
        }
    }

    # --- summary ----------------------------------------------------------
    Write-Head 'UNINSTALL SUMMARY / 卸载结果'
    if ($script:checks.Count -gt 0) {
        foreach ($c in $script:checks) {
            $mark = if ($c.Ok) { '[ OK ]' } else { '[FAIL]' }
            Write-Host ('  {0} {1} - {2}' -f $mark, $c.Name, $c.Detail) -ForegroundColor $(if ($c.Ok) { 'Green' } else { 'Red' })
        }
    } else {
        Write-Host '  no game folder checks were possible' -ForegroundColor Yellow
    }
    Write-Host ''
    Write-Host ('  log : ' + $logPath)
    Write-Host ''
    if ($script:failures -gt 0) {
        Write-Host ('RESULT: FAILED - {0} check(s) failed, {1} warning(s). 卸载失败。' -f $script:failures, $script:warnings) -ForegroundColor Red
        if ($gameRunning) { Write-Host 'Close the game, then run uninstall.ps1 again. / 请先退出游戏后重试。' }
        exit 1
    } elseif ($script:warnings -gt 0) {
        Write-Host ('RESULT: UNINSTALLED WITH WARNINGS - {0} warning(s). 卸载完成，但有警告（见上）。' -f $script:warnings) -ForegroundColor Yellow
    } else {
        Write-Host 'RESULT: UNINSTALL SUCCESSFUL. 卸载成功。' -ForegroundColor Green
    }
    Write-Host ''
    Write-Host 'Game files (exe / paks / saves) were never modified.'
    Write-Host '游戏本体文件（exe / pak / 存档）从未被修改。'
    Write-Host ''
    Wait-IfDoubleClicked
    exit 0
} finally {
    if ($transcript) { try { Stop-Transcript | Out-Null } catch { } }
}
