# PBZStats — Death Counter HUD for Phantom Blade Zero

Current release: **v3.2.1** — the HUD follows the in-game language live (switching the language in the options menu updates the overlay without a restart). User documentation: `docs/README.md`.

A HUD mod for **Phantom Blade Zero** that shows five lines at the right-middle of the screen:

- current cycle (NG+ count)
- current difficulty
- total deaths for the save
- current boss name
- deaths to that boss

Data is read from the game's own runtime state (including the per-boss records stored in the save data), so the numbers are historical, not "since you installed the mod".

## 中文简介

影之刃零（Phantom Blade Zero）画面右侧中部的五行 HUD：**当前周目、当前难度、死亡总数、当前 Boss、本 Boss 死亡数**。

数据读取游戏自身的运行时状态与存档记录（Boss 死亡 = 尝试次数 − 击杀次数），显示的是历史累计值，而不是"装了这个 mod 之后的次数"。不修改存档，不注入游戏进程。

- **13 种语言自动跟随**游戏内语言：切换语言后几秒内自动刷新，无需重启游戏
- 透明、鼠标穿透、不抢焦点，随游戏启动与退出，无后台进程、无 Python
- 长 Boss 名自动省略号，不会超出屏幕
- 只读：不修改存档与游戏文件

**安装**：关闭游戏 → 解压 → 右键 `install.ps1` → 用 PowerShell 运行 → 从 Steam 正常启动游戏。
**卸载**：运行 `uninstall.ps1`（加 `-KeepData` 可保留统计数据）。

发布页与更新日志：https://www.nexusmods.com/phantombladezero/mods/268
完整中文说明：`docs/README.md`

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
