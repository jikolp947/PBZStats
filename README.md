# PBZStats — Death Counter HUD for Phantom Blade Zero

Current release: **v3.2.1** — the HUD follows the in-game language live (switching the language in the options menu updates the overlay without a restart). User documentation: `docs/README.md`.

A HUD mod for **Phantom Blade Zero** that shows five lines at the right-middle of the screen:

- current cycle (NG+ count)
- current difficulty
- total deaths for the save
- current boss name
- deaths to that boss

Data is read from the game's own runtime state (including the per-boss records stored in the save data), so the numbers are historical, not "since you installed the mod".

## Repository layout

```
src/main.lua             UE4SS Lua mod (reads the game state, writes stats.txt)
src/PBZStatsHUD.cs       C# HUD overlay (WinForms, transparent, click-through)
installer/install.ps1    Installer for the traditional mod layout
installer/uninstall.ps1  Uninstaller
installer/PBZStatsHUD.ini Default HUD settings
docs/README.md           User documentation (English + Chinese)
build.ps1                Builds dist/PBZStatsHUD.exe and stages the mod folder
```

## Build

Requirements: Windows 10/11, .NET Framework 4.x (the `csc.exe` shipped with Windows is enough — no Visual Studio needed).

```powershell
powershell -ExecutionPolicy Bypass -File .\build.ps1
```

The script compiles `src\PBZStatsHUD.cs` with:

```
C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe /nologo /target:winexe /platform:anycpu /optimize+ /unsafe /r:System.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll /out:dist\PBZStatsHUD.exe src\PBZStatsHUD.cs
```

and copies `src\main.lua`, `installer\*.ps1` and `installer\PBZStatsHUD.ini` into `dist\`.

## Install

The mod uses **UE4SS** (Lua scripting for Unreal Engine games). Installer details are in `docs/README.md`.

## Third-party components

- **UE4SS** — MIT licensed, https://github.com/UE4SS-RE/RE-UE4SS (the release package bundles the official UE4SS build plus community signature fixes required by Phantom Blade Zero).
- Signature/offset fixes for Phantom Blade Zero are community-maintained configuration files (Lua signature scripts and `MemberVariableLayout.ini`), used with permission of their authors.

The C# HUD and the Lua mod in this repository are our own code, MIT licensed (see LICENSE).
