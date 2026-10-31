param(
    [string]$GameDir = '',
    [switch]$NoBackup,
    [switch]$NoPause
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$src  = Join-Path $here 'files'
$version = '3.2.2'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath = Join-Path $env:TEMP ('PBZStats_install_' + $stamp + '.log')

# ---------------------------------------------------------------------------
# Status helpers: every phase prints [n/total] + OK / WARN / FAIL, and the
# final block repeats a checklist so the result is obvious even if the window
# scrolled.  Colours are only cosmetic; the log file keeps the same text.
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
function Write-Ok([string]$text) {
    Write-Host ('       OK    ' + $text) -ForegroundColor Green
}
function Write-Info([string]$text) {
    Write-Host ('             ' + $text) -ForegroundColor DarkGray
}
function Write-Warn([string]$text) {
    $script:warnings++
    Write-Host ('       WARN  ' + $text) -ForegroundColor Yellow
}
function Write-Fail([string]$text) {
    $script:failures++
    Write-Host ('       FAIL  ' + $text) -ForegroundColor Red
}
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

# The window closes by itself when the script is started from Explorer; keep it
# open in that case so the result checklist can be read.
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
    Write-Head ("PBZ Stats HUD v{0} - installer / 安装程序" -f $version)
    Write-Host ('log file : ' + $logPath) -ForegroundColor DarkGray

    # --- 1) locate the game -------------------------------------------------
    Write-Step 'Locating Phantom Blade Zero / 查找游戏目录'
    $game = Find-GameDir
    if (-not $game) {
        Write-Host ''
        Write-Host 'RESULT: FAILED - Phantom Blade Zero was not found.' -ForegroundColor Red
        Write-Host 'Run again with the game folder, for example:' -ForegroundColor Yellow
        Write-Host '  .\install.ps1 -GameDir "G:\SteamLibrary\steamapps\common\PBZ"'
        Write-Host '安装失败：未找到游戏目录。可加 -GameDir 参数指定。'
        exit 1
    }
    $game = $game.TrimEnd('\')
    $plat = Join-Path $game 'platform\steam'
    if (-not (Test-Path (Join-Path $plat 'PBZ.exe'))) {
        Write-Host ''
        Write-Host ("RESULT: FAILED - {0}\PBZ.exe not found." -f $plat) -ForegroundColor Red
        exit 1
    }
    Write-Ok ("game folder: " + $game)
    if (Get-Process PBZ -ErrorAction SilentlyContinue) {
        Write-Host ''
        Write-Host 'RESULT: FAILED - Phantom Blade Zero is running.' -ForegroundColor Red
        Write-Host 'Close the game first, then run this installer again.'
        Write-Host '安装失败：游戏正在运行，请先完全退出游戏再安装。'
        exit 1
    }
    Write-Ok 'game is not running'

    $modDir = Join-Path $plat 'ue4ss\Mods\PBZStats'
    $marker = Join-Path $plat '.pbzstats_version'
    $isOurs = Test-Path $marker
    Write-Info ("mod dir  : " + $modDir)
    if ($isOurs) { Write-Info 'previous PBZStats install detected / 检测到旧版本，将直接升级' }

    # --- 2) preserve data, prepare the target ------------------------------
    Write-Step 'Preparing target folder / 准备安装目录'
    $savedData = ''
    $dataDirOld = Join-Path $modDir 'data'
    if (Test-Path $dataDirOld) {
        $savedData = Join-Path $env:TEMP ('pbzstats_data_' + $stamp)
        Copy-Item $dataDirOld $savedData -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path $savedData) { Write-Ok 'saved current statistics/logs for migration' }
        else { Write-Warn 'could not read the current data folder (it will be recreated empty)' }
    } else {
        Write-Info 'no existing data folder, nothing to migrate'
    }
    if ($isOurs) {
        Get-ChildItem $plat -Directory -Filter 'ue4ss_backup_*' -ErrorAction SilentlyContinue |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Get-ChildItem $plat -Filter 'dwmapi.dll.bak_*' -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
        Remove-Item (Join-Path $plat 'ue4ss') -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item (Join-Path $plat 'dwmapi.dll') -Force -ErrorAction SilentlyContinue
        Write-Ok 'old mod files cleared (in-place update, no backup needed)'
    } elseif ($NoBackup) {
        Write-Warn 'NoBackup given: existing ue4ss / dwmapi.dll will NOT be backed up'
        Remove-Item (Join-Path $plat 'ue4ss') -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item (Join-Path $plat 'dwmapi.dll') -Force -ErrorAction SilentlyContinue
    } else {
        if (Test-Path (Join-Path $plat 'ue4ss')) {
            $bak = Join-Path $plat ('ue4ss_backup_' + $stamp)
            Move-Item (Join-Path $plat 'ue4ss') $bak
            Write-Ok ("other ue4ss install backed up to " + $bak)
        }
        if (Test-Path (Join-Path $plat 'dwmapi.dll')) {
            $dllBak = 'dwmapi.dll.bak_' + $stamp
            Rename-Item (Join-Path $plat 'dwmapi.dll') $dllBak
            Write-Ok ("other dwmapi.dll backed up as " + $dllBak)
        }
        Get-ChildItem $plat -Directory -Filter 'ue4ss_backup_*' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -Skip 2 |
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Get-ChildItem $plat -Filter 'dwmapi.dll.bak_*' -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -Skip 2 |
            Remove-Item -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path (Join-Path $plat 'ue4ss')) -and -not (Test-Path (Join-Path $plat 'dwmapi.dll'))) {
            Write-Info 'no other UE4SS install present - clean install'
        }
    }

    # --- 3) copy injector + Lua mod ---------------------------------------
    Write-Step 'Copying UE4SS injector and mod files / 复制注入器与脚本'
    try {
        Copy-Item (Join-Path $src 'dwmapi.dll') $plat -Force
        Copy-Item (Join-Path $src 'ue4ss') $plat -Recurse -Force
        $dllDst = Join-Path $plat 'dwmapi.dll'
        $ue4ssDll = Join-Path $plat 'ue4ss\UE4SS.dll'
        if ((Test-Path $dllDst) -and (Test-Path $ue4ssDll)) {
            $dllMb = [math]::Round((Get-Item $dllDst).Length / 1MB, 1)
            $ue4ssMb = [math]::Round(((Get-ChildItem (Join-Path $plat 'ue4ss') -Recurse -File | Measure-Object Length -Sum).Sum) / 1MB, 1)
            Write-Ok ("dwmapi.dll ({0} MB) + ue4ss\ ({1} MB)" -f $dllMb, $ue4ssMb)
        } else {
            Write-Fail 'injector files are missing after the copy'
        }
    } catch {
        Write-Fail ('copy failed: ' + $_.Exception.Message)
    }

    # --- 4) marker --------------------------------------------------------
    Write-Step 'Writing install marker / 写入安装标记'
    try {
        Set-Content -Path $marker -Value ('PBZStats HUD ' + $version) -Encoding ASCII
        if (Test-Path $marker) { Write-Ok ('.pbzstats_version = PBZStats HUD ' + $version) }
        else { Write-Fail 'marker file was not written' }
    } catch {
        Write-Fail ('marker write failed: ' + $_.Exception.Message)
    }

    # --- 5) point Lua + ini at the mod data folder -------------------------
    Write-Step 'Configuring data path / 配置数据目录'
    $dataDir = Join-Path $modDir 'data'
    try {
        New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
        if ($savedData -and (Test-Path $savedData)) {
            Copy-Item (Join-Path $savedData '*') $dataDir -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item $savedData -Recurse -Force -ErrorAction SilentlyContinue
            Write-Ok 'previous statistics and logs restored / 已迁移旧数据'
        }
        $luaDst = Join-Path $modDir 'Scripts\main.lua'
        $luaOut = ($dataDir + '\').Replace('\', '\\')
        $txt = [IO.File]::ReadAllText($luaDst)
        $txt = [Text.RegularExpressions.Regex]::Replace($txt, '(?m)^local OUT\s*=\s*".*"\s*$', ('local OUT = "' + $luaOut + '"'))
        [IO.File]::WriteAllText($luaDst, $txt, (New-Object System.Text.UTF8Encoding($false)))
        Write-Ok ('main.lua OUT -> ' + $dataDir)

        $iniPath = Join-Path $modDir 'PBZStatsHUD.ini'
        if (Test-Path $iniPath) {
            $ini = [IO.File]::ReadAllText($iniPath)
            $ini = [Text.RegularExpressions.Regex]::Replace($ini, '(?m)^data_dir=.*$', 'data_dir=')
            [IO.File]::WriteAllText($iniPath, $ini, (New-Object System.Text.UTF8Encoding($false)))
            Write-Ok 'PBZStatsHUD.ini data_dir cleared (uses the mod folder)'
        } else {
            Write-Warn 'PBZStatsHUD.ini missing (the HUD will use its defaults)'
        }
    } catch {
        Write-Fail ('configuration failed: ' + $_.Exception.Message)
    }

    # --- 6) HUD exe + blob copy -------------------------------------------
    Write-Step 'Installing HUD executable / 安装 HUD 程序'
    $hudDst = Join-Path $modDir 'PBZStatsHUD.exe'
    $hudBak = Join-Path $modDir 'hudbox.dat'
    try {
        if (Test-Path (Join-Path $here 'PBZStatsHUD.exe')) {
            for ($i = 1; $i -le 3; $i++) {
                try { [System.IO.File]::Copy((Join-Path $here 'PBZStatsHUD.exe'), $hudDst, $true) } catch { }
                Start-Sleep -Milliseconds 300
                if (Test-Path $hudDst) { break }
            }
        }
        if (Test-Path $hudDst) {
            try { [System.IO.File]::Copy($hudDst, $hudBak, $true) } catch { }
            Write-Ok ("PBZStatsHUD.exe ({0:N0} bytes) + hudbox.dat backup" -f (Get-Item $hudDst).Length)
        } elseif (Test-Path (Join-Path $here 'hudbox.dat')) {
            try { [System.IO.File]::Copy((Join-Path $here 'hudbox.dat'), $hudBak, $true) } catch { }
            Write-Warn 'PBZStatsHUD.exe could not be written; the game will restore it from hudbox.dat'
        } else {
            Write-Fail 'neither PBZStatsHUD.exe nor hudbox.dat could be installed'
        }
    } catch {
        Write-Fail ('HUD copy failed: ' + $_.Exception.Message)
    }

    # --- 7) remove leftovers from the old autostart releases ---------------
    Write-Step 'Cleaning legacy autostart entries / 清理旧版自启动项'
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    $cleaned = 0
    foreach ($name in @('PBZStatsHUD', 'PBZStatsHUDWatcher')) {
        try {
            $existing = Get-ItemProperty -Path $runKey -Name $name -ErrorAction SilentlyContinue
            if ($existing) { Remove-ItemProperty -Path $runKey -Name $name -ErrorAction SilentlyContinue; $cleaned++ }
        } catch { }
    }
    $strayHud = Get-Process PBZStatsHUD -ErrorAction SilentlyContinue
    if ($strayHud) {
        $strayHud | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-Ok 'stopped a running PBZStatsHUD.exe from an older session'
    }
    if ($cleaned -gt 0) { Write-Ok ("removed $cleaned autostart entr(y/ies)") }
    else { Write-Info 'nothing to clean (no autostart entries from v1.x/2.x)' }

    # --- 8) verify --------------------------------------------------------
    Write-Step 'Verifying installation / 校验安装结果'
    $dll = Join-Path $plat 'dwmapi.dll'
    $ue4ssDll = Join-Path $plat 'ue4ss\UE4SS.dll'
    $luaDst = Join-Path $modDir 'Scripts\main.lua'

    $dllOk = $false; $dllDetail = 'missing'
    $dllSrc = Join-Path $src 'dwmapi.dll'
    if (Test-Path $dll) {
        $dllSize = (Get-Item $dll).Length
        if (Test-Path $dllSrc) {
            $srcSize = (Get-Item $dllSrc).Length
            $dllOk = ($dllSize -eq $srcSize)
            if ($dllOk) {
                $dllDetail = ('{0:N0} bytes, matches the bundled injector' -f $dllSize)
            } else {
                $dllDetail = ('{0:N0} bytes, expected {1:N0}' -f $dllSize, $srcSize)
            }
        } else {
            $dllOk = $dllSize -gt 0
            $dllDetail = ('{0:N0} bytes' -f $dllSize)
        }
    }
    Add-Check 'injector dwmapi.dll' $dllOk $dllDetail

    $ue4ssOk = Test-Path $ue4ssDll
    if ($ue4ssOk) { $ue4ssDetail = ('{0:N0} bytes' -f (Get-Item $ue4ssDll).Length) } else { $ue4ssDetail = 'missing' }
    Add-Check 'UE4SS.dll' $ue4ssOk $ue4ssDetail

    $luaOk = $false
    $luaHint = 'missing'
    if (Test-Path $luaDst) {
        $luaText = [IO.File]::ReadAllText($luaDst)
        $luaOk = $luaText.Contains('local OUT = "' + $dataDir.Replace('\', '\\'))
        if ($luaOk) { $luaHint = 'data path configured for the mod folder' }
        else { $luaHint = 'OUT does not point at the mod folder' }
    }
    Add-Check 'Lua mod main.lua' $luaOk $luaHint

    $markerOk = Test-Path $marker
    if ($markerOk) { $markerDetail = 'PBZStats HUD ' + $version } else { $markerDetail = 'missing' }
    Add-Check 'install marker' $markerOk $markerDetail

    Add-Check 'data folder' (Test-Path $dataDir) $dataDir
    if (Test-Path $hudDst) {
        Add-Check 'HUD exe' $true ('{0:N0} bytes' -f (Get-Item $hudDst).Length)
    } else {
        Write-Host '       WARN  HUD exe: missing - antivirus may have quarantined it' -ForegroundColor Yellow
        $script:warnings++
        Write-Host ("             Add {0} to your antivirus whitelist and copy PBZStatsHUD.exe there." -f $modDir) -ForegroundColor Yellow
        Write-Host '             杀毒软件可能拦截了 PBZStatsHUD.exe：请把上面这个目录加入白名单。' -ForegroundColor Yellow
    }

    # --- summary ----------------------------------------------------------
    Write-Head 'INSTALL SUMMARY / 安装结果'
    foreach ($c in $script:checks) {
        $mark = if ($c.Ok) { '[ OK ]' } else { '[FAIL]' }
        Write-Host ('  {0} {1} - {2}' -f $mark, $c.Name, $c.Detail) -ForegroundColor $(if ($c.Ok) { 'Green' } else { 'Red' })
    }
    Write-Host ''
    Write-Host ('  injector : ' + $dll)
    Write-Host ('  script   : ' + $luaDst)
    Write-Host ('  HUD      : ' + $hudDst + ' (started by the game)')
    Write-Host ('  data     : ' + $dataDir)
    Write-Host ('  log      : ' + $logPath)
    Write-Host ''
    if ($script:failures -gt 0) {
        Write-Host ('RESULT: FAILED - {0} check(s) failed, {1} warning(s). 安装失败。' -f $script:failures, $script:warnings) -ForegroundColor Red
        exit 1
    } elseif ($script:warnings -gt 0) {
        Write-Host ('RESULT: INSTALLED WITH WARNINGS - {0} warning(s). 安装完成，但有警告（见上）。' -f $script:warnings) -ForegroundColor Yellow
    } else {
        Write-Host 'RESULT: INSTALL SUCCESSFUL. 安装成功。' -ForegroundColor Green
    }
    Write-Host ''
    Write-Host 'Start the game from Steam. The HUD appears on the right side and closes with the game.'
    Write-Host '启动游戏后右侧会出现数据 HUD，退出游戏后自动关闭。'
    Write-Host 'No Python, no autostart entry, no background watcher is installed.'
    Write-Host 'HUD language follows the game language automatically (edit lang= in PBZStatsHUD.ini to force one).'
    Write-Host 'Uninstall: run uninstall.ps1'
    Write-Host ''
    Wait-IfDoubleClicked
    exit 0
} finally {
    if ($transcript) { try { Stop-Transcript | Out-Null } catch { } }
}
