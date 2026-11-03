param(
    [string]$GameDir = '',
    [switch]$KeepData,
    [switch]$NoPause,
    [switch]$NoPrompt
)
$ErrorActionPreference = 'Continue'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath = Join-Path $env:TEMP ('PBZStats_uninstall_' + $stamp + '.log')

# ---------------------------------------------------------------------------
# Same status vocabulary as install.ps1: [n/total] steps, OK/WARN/FAIL lines
# and a final checklist, so it is obvious whether the mod is really gone.
#
# The installer writes "(lite)" or "(full)" into .pbzstats_version, and the
# uninstaller follows it:
#   lite -> only ue4ss\Mods\PBZStats + the mods.txt line are removed; the UE4SS
#           framework belongs to the user and is never touched.
#   full -> the injector files this mod installed are removed again (ue4ss kept
#           when other mods live there, dwmapi.dll restored from its backup).
# A missing marker is treated conservatively: the framework stays.
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

# Join-Path throws when the path names a drive that does not exist on this PC
# ("Cannot find drive. A drive with the name 'G' does not exist."). The probe
# must never throw, otherwise a machine without a G: drive aborts the script.
function Join-SafePath {
    param([string]$Base, [string]$Child)
    if (-not $Base) { return '' }
    try { return [IO.Path]::Combine($Base, $Child) } catch { return '' }
}

function Test-PathQuiet {
    param([string]$Path)
    if (-not $Path) { return $false }
    try { return (Test-Path -LiteralPath $Path) } catch { return $false }
}

# "-GameDir" is typed by hand, so accept every shape a user may paste (see the
# same helper in install.ps1).
function Resolve-GameDir {
    param([string]$Path)
    if (-not $Path) { return '' }
    $p = $Path.Trim()
    $p = $p.Trim('"').Trim("'").Trim()
    if (-not $p) { return '' }
    $p = $p.Replace('\\', '\')
    $p = $p.TrimEnd('\')
    if ($p -match '^[A-Za-z]:$') { return '' }
    if ($p -match '(?i)\\platform\\steam\\PBZ\.exe$') { $p = $p -replace '(?i)\\platform\\steam\\PBZ\.exe$', '' }
    elseif ($p -match '(?i)\\platform\\steam$') { $p = $p -replace '(?i)\\platform\\steam$', '' }
    elseif ($p -match '(?i)\\platform$') { $p = $p -replace '(?i)\\platform$', '' }
    elseif ($p -match '(?i)\\PBZ\.exe$') { $p = $p -replace '(?i)\\PBZ\.exe$', '' }
    return $p.TrimEnd('\')
}

function Find-GameDir {
    $candidates = @()
    $explicit = Resolve-GameDir $GameDir
    if ($explicit) { $candidates += $explicit }

    # 1) every Steam library registered in libraryfolders.vdf
    $steamRoots = @()
    try {
        $steamPath = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
        if ($steamPath) { $steamRoots += ($steamPath.Replace('/', '\').TrimEnd('\')) }
    } catch { }
    $steamRoots += @('C:\Program Files (x86)\Steam', 'C:\Steam')
    $libraries = @()
    foreach ($root in $steamRoots) {
        $vdf = Join-SafePath $root 'steamapps\libraryfolders.vdf'
        if (-not (Test-PathQuiet $vdf)) { continue }
        $libraries += $root
        foreach ($line in Get-Content -LiteralPath $vdf -ErrorAction SilentlyContinue) {
            if ($line -match '"path"\s+"([^"]+)"') {
                # VDF stores "D:\\SteamLibrary": undo the escaping and any trailing slash.
                $lib = $matches[1].Replace('\\', '\').TrimEnd('\')
                if ($lib) { $libraries += $lib }
            }
        }
    }
    foreach ($lib in $libraries) {
        $candidates += (Join-SafePath $lib 'steamapps\common\PBZ')
        # 2) the appmanifest knows the real folder name
        $acf = Join-SafePath $lib 'steamapps\appmanifest_4115450.acf'
        if (Test-PathQuiet $acf) {
            foreach ($line in Get-Content -LiteralPath $acf -ErrorAction SilentlyContinue) {
                if ($line -match '"installdir"\s+"([^"]+)"') {
                    $candidates += (Join-SafePath $lib ('steamapps\common\' + $matches[1]))
                }
            }
        }
    }

    # 3) last sweep: the usual folder names on every fixed drive
    $common = @('SteamLibrary', 'Steam', 'Program Files (x86)\Steam', 'Games\SteamLibrary', 'SteamLibrary2')
    foreach ($d in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        if ($d.Name -notmatch '^[A-Za-z]$') { continue }
        foreach ($c in $common) {
            $candidates += ('{0}:\{1}\steamapps\common\PBZ' -f $d.Name.ToUpper(), $c)
        }
    }

    foreach ($c in $candidates) {
        if (-not $c) { continue }
        if (Test-PathQuiet (Join-SafePath $c 'platform\steam\PBZ.exe')) { return $c.TrimEnd('\') }
    }
    return ''
}

# Ask instead of failing with a cryptic error (the mod may already be gone, so
# this only runs when nothing was detected).
function Ask-GameDir {
    if ($NoPrompt) { return '' }
    $attempts = 0
    while ($attempts -lt 3) {
        Write-Host ''
        Write-Host 'Phantom Blade Zero was not found automatically.' -ForegroundColor Yellow
        Write-Host '没找到游戏目录，请把游戏文件夹粘贴到这里。' -ForegroundColor Yellow
        Write-Host '  example / 例如: G:\SteamLibrary\steamapps\common\PBZ' -ForegroundColor DarkGray
        Write-Host '  (right-click pastes / 右键粘贴; press Enter with nothing to skip)'
        $answer = ''
        try { $answer = Read-Host 'Game folder / 游戏目录' } catch { return '' }
        if (-not $answer -or -not $answer.Trim()) { return '' }
        $resolved = Resolve-GameDir $answer
        if (Test-PathQuiet (Join-SafePath $resolved 'platform\steam\PBZ.exe')) { return $resolved }
        Write-Host ('  not a game folder: ' + $resolved) -ForegroundColor Red
        Write-Host '  这个目录里没有 platform\steam\PBZ.exe' -ForegroundColor Red
        $attempts++
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

# Removes the "PBZStats : ..." line from the framework's mods.txt and leaves
# every other line byte-for-byte alone (including comments and blank lines).
function Disable-ModInModsTxt([string]$modsTxt) {
    if (-not (Test-Path $modsTxt)) { return $false }
    $lines = @(Get-Content $modsTxt -Encoding UTF8 -ErrorAction SilentlyContinue)
    $kept = New-Object System.Collections.Generic.List[string]
    $removed = $false
    foreach ($line in $lines) {
        if ($line -match '^\s*PBZStats\s*:') { $removed = $true }
        else { $kept.Add($line) | Out-Null }
    }
    if ($removed) {
        [IO.File]::WriteAllText($modsTxt, ($kept -join "`r`n") + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
    }
    return $removed
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
        Write-Info 'automatic detection failed / 自动查找失败，改为手动输入'
        $game = Ask-GameDir
        if ($game) {
            $game = $game.TrimEnd('\')
            $plat = Join-Path $game 'platform\steam'
            $modDir = Join-Path $plat 'ue4ss\Mods\PBZStats'
            Write-Ok ('game folder: ' + $game)
        } else {
            Write-Warn 'game folder not found - only leftover data will be cleaned'
            Write-Warn '未找到游戏目录：只清理残留数据。可重新运行并粘贴路径，或加 -GameDir 参数。'
        }
    }

    $gameRunning = $false
    if ($plat -and (Get-Process PBZ -ErrorAction SilentlyContinue)) {
        $gameRunning = $true
        Write-Warn 'the game is still running - close it so the files can be removed'
        Write-Warn '游戏正在运行，关闭游戏后才能删除文件'
    }

    $modDirExisted = $false
    $markerExisted = $false
    $dwmapiExisted = $false
    $dwmapiRestored = $false
    $ue4ssKept = $false
    $wasLite = $false
    $markerKind = 'unknown'

    if ($plat -and (Test-Path $plat)) {
        $modDirExisted = Test-Path $modDir
        $marker = Join-Path $plat '.pbzstats_version'
        $markerExisted = Test-Path $marker
        $dwmapiExisted = Test-Path (Join-Path $plat 'dwmapi.dll')
        if ($markerExisted) {
            $markerText = (Get-Content $marker -Raw -ErrorAction SilentlyContinue)
            $wasLite = ($markerText -match '\(lite\)')
            if ($markerText -match '\(lite\)') { $markerKind = 'lite' }
            elseif ($markerText -match '\(full\)') { $markerKind = 'full' }
            Write-Info ('previous install: ' + $markerText.Trim())
        } else {
            $markerKind = 'unknown (no marker: the UE4SS framework is kept)'
            Write-Info $markerKind
        }

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

        # --- 5) framework / injector --------------------------------------
        Write-Step 'Cleaning the injector / 清理注入器'
        $modsTxt = Join-Path $plat 'ue4ss\Mods\mods.txt'
        $lineRemoved = $false
        try { $lineRemoved = Disable-ModInModsTxt $modsTxt } catch { }
        if ($lineRemoved) { Write-Ok 'removed the PBZStats line from ue4ss\Mods\mods.txt' }
        else { Write-Info 'mods.txt had no PBZStats line' }

        if ($wasLite -or $markerKind -like 'unknown*') {
            $ue4ssKept = $true
            if ($wasLite) {
                Write-Ok 'UE4SS framework kept (lite install: it was installed by you, not by this mod)'
                Write-Info 'UE4SS 框架保留：轻量包从未安装它，卸载也不动它'
            } else {
                Write-Info 'no install marker: keeping ue4ss\ and dwmapi.dll untouched'
                Write-Info '没有安装标记：保留 ue4ss\ 与 dwmapi.dll 不动'
            }
        } else {
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

            # restore the original dwmapi.dll this mod replaced (full installs only)
            $dll = Join-Path $plat 'dwmapi.dll'
            if (Test-Path $dll) {
                $bak = Get-ChildItem $plat -Filter 'dwmapi.dll.bak_*' -ErrorAction SilentlyContinue |
                    Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if (-not $ue4ssKept) {
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
                    Write-Info 'dwmapi.dll kept together with the ue4ss folder'
                }
            } else {
                Write-Info 'dwmapi.dll not present - already clean'
            }
        }

        # --- 6) marker ----------------------------------------------------
        Write-Step 'Removing install marker / 删除安装标记'
        if (Test-Path $marker) {
            Remove-Item $marker -Force -ErrorAction SilentlyContinue
            if (Test-Path $marker) { Write-Fail 'could not delete .pbzstats_version' }
            else { Write-Ok 'removed .pbzstats_version' }
        } else {
            Write-Info '.pbzstats_version does not exist'
        }
    } else {
        Write-Step 'Statistics backup / 统计数据备份'
        Write-Step 'Removing mod files / 删除 mod 文件'
        Write-Step 'Cleaning the injector / 清理注入器'
        Write-Step 'Removing install marker / 删除安装标记'
        Write-Info 'skipped - game folder unknown'
    }

    # --- 7) legacy data ----------------------------------------------------
    Write-Step 'Cleaning legacy data / 清理旧数据'
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

    # --- 8) verify ---------------------------------------------------------
    Write-Step 'Verifying / 校验卸载结果'
    if ($plat -and (Test-Path $plat)) {
        Add-Check 'mod folder removed' (-not (Test-Path $modDir)) $modDir
        Add-Check 'install marker removed' (-not (Test-Path (Join-Path $plat '.pbzstats_version'))) (Join-Path $plat '.pbzstats_version')
        $modsTxt = Join-Path $plat 'ue4ss\Mods\mods.txt'
        if (Test-Path $modsTxt) {
            $stillListed = [bool](Select-String -Path $modsTxt -Pattern '^\s*PBZStats\s*:' -ErrorAction SilentlyContinue | Select-Object -First 1)
            Add-Check 'mods.txt cleaned' (-not $stillListed) $(if ($stillListed) { 'PBZStats line still present' } else { 'no PBZStats line left' })
        }
        if ($ue4ssKept) {
            if ($wasLite) {
                Add-Check 'UE4SS framework kept' (Test-Path (Join-Path $plat 'ue4ss\UE4SS.dll')) 'installed by you, untouched'
                Write-Host '       INFO  the framework is still there on purpose: other UE4SS mods may need it' -ForegroundColor DarkGray
            } else {
                Write-Host '       INFO  ue4ss folder kept on purpose (other mods or unknown install)' -ForegroundColor DarkGray
            }
        } else {
            Add-Check 'ue4ss folder removed' (-not (Test-Path (Join-Path $plat 'ue4ss'))) (Join-Path $plat 'ue4ss')
            if ($dwmapiExisted) {
                $dllNow = Test-Path (Join-Path $plat 'dwmapi.dll')
                if ($dwmapiRestored) { Add-Check 'dwmapi.dll' $dllNow 'original restored' }
                else { Add-Check 'dwmapi.dll' (-not $dllNow) 'mod version removed' }
            }
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
    Write-Host ('  previous install : ' + $markerKind)
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
    if ($transcript) { try { Stop-Transcript -Out-Null } catch { } }
}
