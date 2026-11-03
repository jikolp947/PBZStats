param(
    [string]$GameDir = '',
    [switch]$NoBackup,
    [switch]$NoPause,
    [switch]$NoPrompt
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$src  = Join-Path $here 'files'
$version = '3.8.1'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath = Join-Path $env:TEMP ('PBZStats_install_' + $stamp + '.log')

# ---------------------------------------------------------------------------
# Two package shapes are supported by this single installer:
#   * lite  - no injector inside: PBZStats only, on top of an existing UE4SS
#             framework (Nexus "PBZ UE4SS Framework", mod 125).  Nothing binary
#             is installed, so the mod folder is just Lua + ini + sources.
#   * full  - ships ue4ss\ + dwmapi.dll (the GitHub build).  Kept for people
#             who want one download and no dependency.
# Both print the same [n/total] + OK / WARN / FAIL vocabulary and finish with a
# checklist, the injector line and a RESULT line with an exit code.
# ---------------------------------------------------------------------------
$script:step = 0
$script:total = 9
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

# Join-Path throws when the path names a drive that does not exist on this PC
# ("Cannot find drive. A drive with the name 'G' does not exist."). The probe
# below must never throw, otherwise a machine without a G: drive aborts the
# whole installer at step 1. [IO.Path]::Combine does not touch the file system.
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

# "-GameDir" is typed by hand, so accept every shape a user may paste:
#   G:\SteamLibrary\steamapps\common\PBZ        <- the folder we want
#   "G:\...\common\PBZ\"                        <- quotes / trailing slash
#   G:\\SteamLibrary\\steamapps\\common\\PBZ    <- escaped backslashes from VDF
#   G:\...\common\PBZ\platform\steam            <- too deep
#   G:\...\common\PBZ\platform\steam\PBZ.exe    <- the exe itself
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
        # 3) the appmanifest knows the real folder name, so a renamed folder still works
        $acf = Join-SafePath $lib 'steamapps\appmanifest_4115450.acf'
        if (Test-PathQuiet $acf) {
            foreach ($line in Get-Content -LiteralPath $acf -ErrorAction SilentlyContinue) {
                if ($line -match '"installdir"\s+"([^"]+)"') {
                    $candidates += (Join-SafePath $lib ('steamapps\common\' + $matches[1]))
                }
            }
        }
    }

    # 4) last sweep: the usual folder names on every fixed drive.  Cheap because
    #    Test-Path on a missing drive simply returns False.
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

# Last resort: ask the user for the folder instead of failing with a cryptic
# error.  Accepts the folder, the platform folder or the exe; validates before
# returning.  Returns '' when the user gives up (or when input is redirected).
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

# Adds (or repairs) the "PBZStats : 1" line in the framework's mods.txt without
# touching any other entry.  UE4SS only loads what is listed there, so without
# this line a lite install would copy the files and still never run.
function Enable-ModInModsTxt([string]$modsTxt) {
    $lines = @()
    if (Test-Path $modsTxt) {
        $lines = @(Get-Content $modsTxt -Encoding UTF8 -ErrorAction SilentlyContinue)
    }
    $found = $false
    $out = New-Object System.Collections.Generic.List[string]
    foreach ($line in $lines) {
        if ($line -match '^\s*PBZStats\s*:') {
            $out.Add('PBZStats : 1') | Out-Null
            $found = $true
        } else {
            $out.Add($line) | Out-Null
        }
    }
    if (-not $found) {
        $insertAt = -1
        for ($i = 0; $i -lt $out.Count; $i++) {
            if ($out[$i] -match '^\s*;\s*Built-in keybinds') { $insertAt = $i; break }
        }
        if ($insertAt -ge 0) {
            $out.Insert($insertAt, '')
            $out.Insert($insertAt + 1, 'PBZStats : 1')
            $out.Insert($insertAt + 2, '')
        } else {
            if ($out.Count -gt 0 -and $out[$out.Count - 1].Trim() -ne '') { $out.Add('') | Out-Null }
            $out.Add('PBZStats : 1') | Out-Null
        }
    }
    [IO.File]::WriteAllText($modsTxt, ($out -join "`r`n") + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
    return $found
}

$transcript = $false
try { Start-Transcript -Path $logPath -Force | Out-Null; $transcript = $true } catch { }

try {
    $isFull = Test-Path (Join-Path $src 'ue4ss\UE4SS.dll')
    $shape = if ($isFull) { 'full' } else { 'lite' }

    Write-Head ("PBZ Stats HUD v{0} - installer / 安装程序 ({1})" -f $version, $shape)
    Write-Host ('log file : ' + $logPath) -ForegroundColor DarkGray
    if (-not $isFull) {
        Write-Host 'lite package: PBZStats only, it uses an already installed UE4SS framework.' -ForegroundColor DarkGray
        Write-Host '轻量包：本包不含注入器，需要先安装 UE4SS 框架（Nexus mod 125）。' -ForegroundColor DarkGray
    }

    # --- 1) locate the game -------------------------------------------------
    Write-Step 'Locating Phantom Blade Zero / 查找游戏目录'
    $game = Find-GameDir
    if (-not $game) {
        Write-Info 'automatic detection failed / 自动查找失败，改为手动输入'
        $game = Ask-GameDir
    }
    if (-not $game) {
        Write-Host ''
        Write-Host 'RESULT: FAILED - Phantom Blade Zero was not found.' -ForegroundColor Red
        Write-Host 'Run again and paste the game folder when asked, or pass it directly:' -ForegroundColor Yellow
        Write-Host '  .\install.ps1 -GameDir "G:\SteamLibrary\steamapps\common\PBZ"'
        Write-Host '安装失败：未找到游戏目录。重新运行并粘贴游戏文件夹，或加 -GameDir 参数。'
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
    $modsTxt = Join-Path $plat 'ue4ss\Mods\mods.txt'
    $isOurs = Test-Path $marker
    Write-Info ("mod dir  : " + $modDir)
    if ($isOurs) { Write-Info 'previous PBZStats install detected / 检测到旧版本，将直接升级' }

    # --- 2) framework check (lite) / target preparation (full) -------------
    if (-not $isFull) {
        Write-Step 'Checking the UE4SS framework / 检查 UE4SS 框架'
        $fwDll = Join-Path $plat 'ue4ss\UE4SS.dll'
        $fwLoader = Join-Path $plat 'dwmapi.dll'
        $fwMods = Join-Path $plat 'ue4ss\Mods'
        $fwOk = (Test-Path $fwDll) -and (Test-Path $fwMods)
        if (-not $fwOk) {
            Write-Host ''
            Write-Host 'RESULT: FAILED - the UE4SS framework is not installed in this game folder.' -ForegroundColor Red
            Write-Host ''
            Write-Host '安装失败：这个游戏目录里没有 UE4SS 框架。本轻量包必须依赖它。'
            Write-Host ''
            Write-Host 'How to fix / 怎么解决（1 分钟）:' -ForegroundColor Yellow
            Write-Host '  1. Install the framework first (free, Nexus, virus scan: safe to use):'
            Write-Host '     https://www.nexusmods.com/phantombladezero/mods/125'
            Write-Host '     (PBZ UE4SS Framework - run its installMOD.exe and point it at Steam)'
            Write-Host '  2. Start the game once so the framework launches, then close it.'
            Write-Host '  3. Run this installer again.'
            Write-Host ''
            Write-Host ('expected files: ' + $fwDll)
            Write-Host ('                ' + $fwMods)
            exit 2
        }
        Add-Check 'UE4SS framework' $true ('{0:N0} bytes' -f (Get-Item $fwDll).Length)
        if (Test-Path $fwLoader) {
            Write-Ok ('dwmapi.dll loader: {0:N0} bytes' -f (Get-Item $fwLoader).Length)
        } else {
            Write-Warn 'dwmapi.dll not found - the framework may not start (Nexus mod 125 installs it)'
        }
        Write-Info 'the framework is left untouched; only ue4ss\Mods\PBZStats is replaced'
    } else {
        Write-Step 'Preparing target folder / 准备安装目录'
        if ($isOurs) {
            Get-ChildItem $plat -Directory -Filter 'ue4ss_backup_*' -ErrorAction SilentlyContinue |
                Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            Get-ChildItem $plat -Filter 'dwmapi.dll.bak_*' -ErrorAction SilentlyContinue |
                Remove-Item -Force -ErrorAction SilentlyContinue
            Write-Ok 'old backup files cleared (in-place update)'
        } elseif ($NoBackup) {
            Write-Warn 'NoBackup given: existing ue4ss / dwmapi.dll will NOT be backed up'
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
    }

    # --- 3) preserve data, then copy the mod -------------------------------
    Write-Step 'Copying mod files / 复制 mod 文件'
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
    try {
        if ($isFull) {
            Copy-Item (Join-Path $src 'dwmapi.dll') $plat -Force
            if (Test-Path (Join-Path $plat 'ue4ss')) { Remove-Item (Join-Path $plat 'ue4ss') -Recurse -Force -ErrorAction SilentlyContinue }
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
        } else {
            if (Test-Path $modDir) { Remove-Item $modDir -Recurse -Force -ErrorAction SilentlyContinue }
            Copy-Item (Join-Path $src 'ue4ss\Mods\PBZStats') (Split-Path $modDir -Parent) -Recurse -Force
            $luaSrc = Join-Path $modDir 'Scripts\main.lua'
            if (Test-Path $luaSrc) {
                Write-Ok ('ue4ss\Mods\PBZStats ({0} files, {1:N0} bytes)' -f `
                    (Get-ChildItem $modDir -Recurse -File).Count, `
                    (Get-ChildItem $modDir -Recurse -File | Measure-Object Length -Sum).Sum)
            } else {
                Write-Fail 'mod files are missing after the copy'
            }
        }
    } catch {
        Write-Fail ('copy failed: ' + $_.Exception.Message)
    }

    # --- 4) marker --------------------------------------------------------
    Write-Step 'Writing install marker / 写入安装标记'
    try {
        Set-Content -Path $marker -Value ('PBZStats HUD ' + $version + ' (' + $shape + ')') -Encoding ASCII
        if (Test-Path $marker) { Write-Ok ('.pbzstats_version = PBZStats HUD ' + $version + ' (' + $shape + ')') }
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
    $packHasExe = (Test-Path (Join-Path $here 'PBZStatsHUD.exe')) -or (Test-Path (Join-Path $here 'hudbox.dat'))
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
        } elseif (-not $packHasExe) {
            Write-Ok 'no overlay exe in this package - the PowerShell host draws the HUD'
            Write-Info 'this build is PowerShell only; grab the GitHub release if you want the optional exe'
        } else {
            Write-Fail 'neither PBZStatsHUD.exe nor hudbox.dat could be installed'
        }
    } catch {
        Write-Fail ('HUD copy failed: ' + $_.Exception.Message)
    }

    # --- 7) register the mod in the framework's mods.txt (lite) ------------
    if (-not $isFull) {
        Write-Step 'Registering PBZStats in mods.txt / 在 mods.txt 里启用'
        try {
            if (-not (Test-Path (Split-Path $modsTxt -Parent))) {
                New-Item -ItemType Directory -Path (Split-Path $modsTxt -Parent) -Force | Out-Null
            }
            $repaired = Enable-ModInModsTxt $modsTxt
            if (Test-Path $modsTxt) {
                $line = Select-String -Path $modsTxt -Pattern '^\s*PBZStats\s*:\s*1' | Select-Object -First 1
                if ($line) {
                    if ($repaired) { Write-Ok 'PBZStats : 1 (already listed, kept enabled)' }
                    else { Write-Ok 'PBZStats : 1 added to ue4ss\Mods\mods.txt' }
                    Write-Info 'other mods.txt entries were left exactly as they were'
                } else {
                    Write-Fail 'mods.txt does not contain PBZStats : 1'
                }
            } else {
                Write-Fail 'mods.txt could not be written'
            }
        } catch {
            Write-Fail ('mods.txt update failed: ' + $_.Exception.Message)
        }
    } else {
        Write-Step 'Registering PBZStats in mods.txt / 在 mods.txt 里启用'
        Write-Ok 'shipped inside the package (ue4ss\Mods\mods.txt)'
    }

    # --- 8) remove leftovers from the old autostart releases ---------------
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

    # --- 9) verify --------------------------------------------------------
    Write-Step 'Verifying installation / 校验安装结果'
    $luaDst = Join-Path $modDir 'Scripts\main.lua'

    if ($isFull) {
        $dll = Join-Path $plat 'dwmapi.dll'
        $dllOk = $false; $dllDetail = 'missing'
        $dllSrc = Join-Path $src 'dwmapi.dll'
        if (Test-Path $dll) {
            $dllSize = (Get-Item $dll).Length
            if (Test-Path $dllSrc) {
                $dllOk = ($dllSize -eq (Get-Item $dllSrc).Length)
                $dllDetail = if ($dllOk) { ('{0:N0} bytes, matches the bundled injector' -f $dllSize) } else { ('{0:N0} bytes, unexpected size' -f $dllSize) }
            } else {
                $dllOk = $dllSize -gt 0
                $dllDetail = ('{0:N0} bytes' -f $dllSize)
            }
        }
        Add-Check 'injector dwmapi.dll' $dllOk $dllDetail
        $ue4ssDll = Join-Path $plat 'ue4ss\UE4SS.dll'
        Add-Check 'UE4SS.dll' (Test-Path $ue4ssDll) $(if (Test-Path $ue4ssDll) { '{0:N0} bytes' -f (Get-Item $ue4ssDll).Length } else { 'missing' })
    } else {
        $fwDll = Join-Path $plat 'ue4ss\UE4SS.dll'
        Add-Check 'UE4SS framework (external)' (Test-Path $fwDll) $(if (Test-Path $fwDll) { '{0:N0} bytes, not modified by this installer' -f (Get-Item $fwDll).Length } else { 'missing' })
        $enabled = $false
        if (Test-Path $modsTxt) {
            $enabled = [bool](Select-String -Path $modsTxt -Pattern '^\s*PBZStats\s*:\s*1' -ErrorAction SilentlyContinue | Select-Object -First 1)
        }
        Add-Check 'mods.txt entry' $enabled $(if ($enabled) { 'PBZStats : 1' } else { 'missing in ' + $modsTxt })
    }

    $luaOk = $false
    $luaHint = 'missing'
    if (Test-Path $luaDst) {
        $luaText = [IO.File]::ReadAllText($luaDst)
        $luaOk = $luaText.Contains('local OUT = "' + $dataDir.Replace('\', '\\'))
        if ($luaOk) { $luaHint = 'data path configured for the mod folder' }
        else { $luaHint = 'OUT does not point at the mod folder' }
    }
    Add-Check 'Lua mod main.lua' $luaOk $luaHint

    Add-Check 'install marker' (Test-Path $marker) ('PBZStats HUD ' + $version + ' (' + $shape + ')')
    Add-Check 'data folder' (Test-Path $dataDir) $dataDir

    if (Test-Path $hudDst) {
        Add-Check 'HUD exe' $true ('{0:N0} bytes' -f (Get-Item $hudDst).Length)
    } elseif (-not $packHasExe) {
        Add-Check 'HUD exe (optional)' $true 'not shipped in this build - PowerShell host only'
    } else {
        Write-Host '       WARN  HUD exe: missing - antivirus may have quarantined it' -ForegroundColor Yellow
        $script:warnings++
        Write-Host ("             Add {0} to your antivirus whitelist and copy PBZStatsHUD.exe there." -f $modDir) -ForegroundColor Yellow
        Write-Host '             杀毒软件可能拦截了 PBZStatsHUD.exe：请把上面这个目录加入白名单。' -ForegroundColor Yellow
    }

    # --- summary ----------------------------------------------------------
    $hudMode = 'ps'
    $iniDst = Join-Path $modDir 'PBZStatsHUD.ini'
    if (Test-Path $iniDst) {
        $mm = Select-String -Path $iniDst -Pattern '^\s*hud_mode\s*=\s*(\w+)' | Select-Object -First 1
        if ($mm) { $hudMode = $mm.Matches[0].Groups[1].Value.ToLowerInvariant() }
    }

    Write-Head 'INSTALL SUMMARY / 安装结果'
    foreach ($c in $script:checks) {
        $mark = if ($c.Ok) { '[ OK ]' } else { '[FAIL]' }
        Write-Host ('  {0} {1} - {2}' -f $mark, $c.Name, $c.Detail) -ForegroundColor $(if ($c.Ok) { 'Green' } else { 'Red' })
    }
    Write-Host ''
    Write-Host ('  package  : ' + $shape + ' (PBZStats HUD ' + $version + ')')
    if ($isFull) { Write-Host ('  injector : ' + (Join-Path $plat 'dwmapi.dll')) }
    else { Write-Host ('  framework: ' + (Join-Path $plat 'ue4ss') + ' (installed separately, untouched)') }
    Write-Host ('  script   : ' + $luaDst)
    if ($hudMode -eq 'exe') { Write-Host ('  HUD      : ' + $hudDst + ' (started by the game)') }
    elseif (Test-Path $hudDst) { Write-Host ('  HUD      : ' + $hudDst + ' (optional; PowerShell host is used by default)') }
    else { Write-Host '  HUD      : not included (PowerShell host only, no exe on disk)' }
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
    if ($hudMode -eq 'exe') {
        Write-Host 'Start the game from Steam. The overlay exe starts with the game and exits with it.'
        Write-Host '启动游戏后右侧会出现数据 HUD（exe 版），退出游戏后自动关闭。'
    } else {
        Write-Host 'Start the game from Steam. The HUD is drawn by a PowerShell host that the mod starts for you - no exe, nothing to run manually.'
        Write-Host '启动游戏后右侧会出现数据 HUD（PowerShell 宿主，无需 exe、无需额外操作），退出游戏后自动关闭。'
    }
    if (-not $isFull) {
        Write-Host 'The UE4SS framework was installed by you and is left untouched; this mod only adds ue4ss\Mods\PBZStats.'
        Write-Host 'UE4SS 框架是你自己装的，本 mod 只新增 ue4ss\Mods\PBZStats 并在 mods.txt 里启用它。'
    }
    Write-Host 'No Python, no autostart entry, no background watcher is installed.'
    Write-Host 'HUD language follows the game language automatically (edit lang= in PBZStatsHUD.ini to force one).'
    Write-Host 'Uninstall: run uninstall.ps1'
    Write-Host ''
    Wait-IfDoubleClicked
    exit 0
} finally {
    if ($transcript) { try { Stop-Transcript | Out-Null } catch { } }
}
