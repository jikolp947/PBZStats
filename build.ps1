param(
    [string]$Out = 'dist'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$dist = Join-Path $root $Out
New-Item -ItemType Directory -Force -Path $dist | Out-Null

$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) {
    $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
}
if (-not (Test-Path $csc)) {
    throw 'csc.exe (.NET Framework 4.x) not found'
}

& $csc /nologo /target:winexe /platform:anycpu /optimize+ /unsafe `
    /r:System.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll `
    "/out:$dist\PBZStatsHUD.exe" (Join-Path $root 'src\PBZStatsHUD.cs')

if ($LASTEXITCODE -ne 0) { throw "csc failed with exit code $LASTEXITCODE" }

# self-healing backup used by the Lua mod if antivirus removes the exe
Copy-Item (Join-Path $dist 'PBZStatsHUD.exe') (Join-Path $dist 'hudbox.dat') -Force

Copy-Item (Join-Path $root 'src\main.lua') $dist -Force
Copy-Item (Join-Path $root 'installer\install.ps1') $dist -Force
Copy-Item (Join-Path $root 'installer\uninstall.ps1') $dist -Force
Copy-Item (Join-Path $root 'installer\PBZStatsHUD.ini') $dist -Force

Write-Host "built: $dist"
Get-ChildItem $dist | Select-Object Name, Length
