# PBZStats — Death Counter HUD for Phantom Blade Zero

Current release: **v3.7.1** — by default the HUD is drawn by a hidden PowerShell host (no `.exe` on disk, so antivirus tools have nothing to quarantine); `hud_mode=exe` still uses the shipped overlay, `none` disables the HUD. User documentation: `docs/README.md`.

### Downloads / 下载哪个包

| Asset | Contents | Use it if |
| --- | --- | --- |
| `PBZStatsHUD_v3.7.1_noexe.zip` | mod + UE4SS + `run.ps1` + `PBZStatsHUD.cs`, **no executable at all** | default; identical to the Nexus upload, nothing for an antivirus to quarantine |
| `PBZStatsHUD_v3.7.1.zip` | the same, **plus** the optional standalone `PBZStatsHUD.exe` (+ `hudbox.dat`) | you want the classic overlay process (`hud_mode=exe`) or an offline install |

| 资源 | 内容 | 什么时候用 |
| --- | --- | --- |
| `PBZStatsHUD_v3.7.1_noexe.zip` | mod + UE4SS + `run.ps1` + `PBZStatsHUD.cs`，**不含任何 exe** | 默认；与 N 网那份完全一致，杀软没有可隔离目标 |
| `PBZStatsHUD_v3.7.1.zip` | 同上，**另附**可选的独立 `PBZStatsHUD.exe`（+ `hudbox.dat`） | 想用旧的独立覆盖层（`hud_mode=exe`）或离线安装 |

Both archives install the same way (right-click `install.ps1` → Run with PowerShell). In the no-exe build the installer prints `HUD exe (optional): not shipped in this build - PowerShell host only` — that is expected, not an error.

两个包安装方式相同（右键 `install.ps1` → 用 PowerShell 运行）。纯 PowerShell 版会打印 `HUD exe (optional): not shipped in this build - PowerShell host only`，这是正常输出，不是错误。

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
- **默认不落地 exe（3.7.x）**：五行由隐藏的 PowerShell 宿主在内存里编译绘制，磁盘上没有任何可执行文件；独立覆盖层仍在 GitHub 完整包里，改 `hud_mode=exe` 使用
- **设置页面**：游戏内按 **Ctrl+F8**（可改）打开，逐行显示/隐藏、调字号、自由拖动 HUD 并保存位置
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
