# PBZStats — Phantom Blade Zero death counter HUD (v3.8.1)

Shows five lines at the right-middle of the screen, in the game's own language:

```
Cycle          Cycle 1
Difficulty     Hard
Total Deaths   112
Boss           金面具黑衣人
Boss Deaths    24
```

* Traditional mod layout: everything is installed inside the game folder. The HUD is started by the mod itself when the game loads — **no autostart entry, no background watcher, no Python**.
* The HUD exits together with the game (about 15 s after it closes).
* **Startup feedback**: a "PBZStats HUD" tray icon appears with a balloon tip; right-click it to quit or open the data folder.
* HUD language follows the game language automatically: English, Simplified Chinese, Traditional Chinese, Japanese, Korean, French, German, Spanish, Portuguese, Russian, Italian, Thai, Vietnamese (13 sets, covering all 15 store languages). The language is re-read from the engine every few seconds, so changing it in the game's options takes effect without restarting the game.
* **Long boss names are shortened** with an ellipsis when they would exceed the configured pixel width (`max_value_width`, 620 px by default) — Russian/German/French names no longer run off the right edge.
* **One data folder**: all generated data and logs live in `data\` inside the mod folder (`<game>\platform\steam\ue4ss\Mods\PBZStats\data\`); delete that folder to clean up.
* **Settings page**: press **Ctrl+F8** (configurable) in game to open a settings panel on top of the game — choose which rows are shown, change the font size, or drag the HUD to any position.
* **HUD (default)**: the Lua mod starts a hidden **PowerShell host** (`run.ps1`) that compiles `PBZStatsHUD.cs` in memory and draws the same overlay as before - no `.exe` is written to disk, so antivirus tools have nothing to quarantine. Set `hud_mode=exe` in `PBZStatsHUD.ini` to use the shipped standalone exe instead (optional, offline installs).

---

## Which download? / 下载哪个包

Since v3.8.0 the recommended download is the **lite** package: it contains only this mod, no injector, no DLL, no executable.

| Build | Contents | Best for |
| --- | --- | --- |
| **Lite** (Nexus download, `PBZStatsHUD_v3.8.1_lite.zip`) | Lua mod + `run.ps1` + `PBZStatsHUD.cs` + installers. **No UE4SS, no DLL, no .exe.** Requires the [PBZ UE4SS Framework](https://www.nexusmods.com/phantombladezero/mods/125) (files are listed as a requirement) | Default. Smallest download, nothing for an antivirus to quarantine. |
| **Full / all-in-one** (`PBZStatsHUD_v3.8.1_full.zip`) | Everything in Lite **plus** the UE4SS framework (`dwmapi.dll`, `ue4ss\`) and the optional `PBZStatsHUD.exe` + `hudbox.dat` | Machines where you cannot install the framework separately, or if you want the optional `hud_mode=exe` overlay. |
| **Full** (GitHub release only) | Everything above **plus** `PBZStatsHUD.exe` + `hudbox.dat` | Offline/locked-down machines, or if you want the optional `hud_mode=exe` overlay. |

* The default mode is `hud_mode=ps`: the mod starts a hidden PowerShell host that compiles `PBZStatsHUD.cs` in memory and draws the HUD. Nothing is written as an executable.
* `hud_mode=exe` only works in the full build (it needs `PBZStatsHUD.exe`).
* All builds install, update and uninstall the same way; the installer detects which one it is running from.

### 中文：下载哪个包

* **轻量包（N 网下载的 `PBZStatsHUD_v3.8.1_lite.zip`）**：只有本 mod，**不含注入器、不含 DLL、不含 exe**，需要先装 [PBZ UE4SS Framework](https://www.nexusmods.com/phantombladezero/mods/125)（文件页已把它列为前置依赖）。推荐用这个。
* **完整包（`PBZStatsHUD_v3.8.1_full.zip`）**：在轻量包基础上额外带 UE4SS 框架（`dwmapi.dll`、`ue4ss\`）和可选的 `PBZStatsHUD.exe` + `hudbox.dat`，适合没法单独装框架的机器，或想用 `hud_mode=exe` 老式覆盖层。
* 两个包版本相同、安装/更新/卸载方式相同（安装器按包内是否含 `ue4ss\UE4SS.dll` 自动识别包型），默认都走 `hud_mode=ps`。

---
## Install

**With the lite package there are two steps**, because the injector is not bundled:

1. Install the UE4SS framework first (free, virus scan: safe to use) and start the game once so the framework creates its folders:
   <https://www.nexusmods.com/phantombladezero/mods/125>
2. Close the game, extract this archive and run `install.ps1` from PowerShell:
   `powershell -ExecutionPolicy Bypass -File install.ps1`
   The script auto-detects the Steam library (registry, `libraryfolders.vdf`, `appmanifest_4115450.acf`, then a sweep of every fixed drive). If nothing is found it asks you to paste the game folder - paste it and press Enter, for example `G:\SteamLibrary\steamapps\common\PBZ`. You can also pass it up front:
   `powershell -ExecutionPolicy Bypass -File install.ps1 -GameDir "G:\SteamLibrary\steamapps\common\PBZ"`

The lite installer only adds `platform\steam\ue4ss\Mods\PBZStats\` (`Scripts\main.lua`, `run.ps1`, `PBZStatsHUD.cs`, `PBZStatsHUD.ini`) and enables `PBZStats : 1` in `ue4ss\Mods\mods.txt`. It **does not touch** the framework, `dwmapi.dll`, or the other mods listed there. If the framework is missing it stops with exit code `2` and tells you where to get it.

Then launch the game from Steam normally, load a save, and the HUD appears on the right; the tray icon confirms it is running.

The full build installs the framework as well: it copies `platform\steam\dwmapi.dll` and `platform\steam\ue4ss\`, and also ships `PBZStatsHUD.exe` + `hudbox.dat`. The installer detects the shape it is running from and reports `lite` or `full` in the marker and the summary.

### Installer behaviour

* **Visible status**: every step prints `[n/9]`, each action prints `OK` / `WARN` / `FAIL`, and the run ends with `RESULT: INSTALL SUCCESSFUL`, `INSTALLED WITH WARNINGS` or `FAILED`. Exit codes: `0` success, `1` failed (game running, verification failed, or no game folder was given), `2` the UE4SS framework is missing (lite package). A full transcript is written to `%TEMP%\PBZStats_install_<timestamp>.log`, and double-clicking the script keeps the window open so you can read the result.
* **Lite**: checks the framework (`ue4ss\UE4SS.dll` + `ue4ss\Mods`) and only replaces `ue4ss\Mods\PBZStats`.
* **All-in-one / full**: if another `ue4ss\` or `dwmapi.dll` is present (another UE4SS mod), it is renamed to a backup before installing. At most two backups are kept, so nothing of yours is lost.
* **Reinstall / update**: a `.pbzstats_version` marker identifies our own installation (`PBZStats HUD 3.8.1 (lite)` / `(full)`); it is updated in place without creating backups.
* **`-NoBackup`**: for advanced users who explicitly want no backups at all (only when no other UE4SS mod is installed).
* **Updates keep your data**: reinstalling preserves the statistics and logs in `data\`.

Manual install (lite): copy `files\ue4ss\Mods\PBZStats` into `<game>\platform\steam\ue4ss\Mods\` and add the line `PBZStats : 1` to `<game>\platform\steam\ue4ss\Mods\mods.txt` (above the `; Built-in keybinds` line). Manual install (all-in-one): additionally copy `files\dwmapi.dll` and the rest of `files\ue4ss` into `<game>\platform\steam\` (back up existing files first).

## Uninstall

Run `uninstall.ps1`. It stops the HUD, removes `ue4ss\Mods\PBZStats` including `data\`, deletes the `PBZStats : 1` line from `ue4ss\Mods\mods.txt` and removes `.pbzstats_version`. Use `-KeepData` to back up `stats.json`, `stats.txt` and logs to `%LOCALAPPDATA%\PBZStats_backup_<timestamp>` first.

* **Lite install**: the UE4SS framework and `dwmapi.dll` are **left in place** (you installed them, other mods may use them).
* **All-in-one / full install**: the renamed `dwmapi.dll` is restored and `ue4ss\` is removed only when no other UE4SS mod is left.

It prints the same `[n/8]` / `OK` / `WARN` / `FAIL` lines and ends with `RESULT: UNINSTALL SUCCESSFUL`, `UNINSTALLED WITH WARNINGS` or `FAILED` (exit code 0 / 1), with a transcript in `%TEMP%\PBZStats_uninstall_<timestamp>.log`.


## Data sources

| Line | Source |
| --- | --- |
| Cycle | `PBZGameSystem.CycleCount + 1` |
| Difficulty | `PBZGameSystem.DifficultModeByte` (0 Handicapped, 1 Easy, 2 Normal, 3 Hard, 4 Nightmare) |
| Total Deaths | `PBZGameSystem.DiedTimes` |
| Boss | localized text of the boss HP bar (`WB_BossHPBar.BossName`), falling back to the actor class name |
| Boss Deaths | save JSON `BossRecord[class].Records["<cycle>_<difficulty>"].AttemptCount − KillCount` |

* “Boss Deaths” uses the same formula as the community archive tools: attempts minus kills. While a fight is in progress the attempt has already been counted, so the value is shown with −1 (the unresolved attempt is excluded).
* If a boss has no record yet (first encounter, older save), the mod's own counter is used.
* The mod only reads game memory/state. It never modifies saves or game files.

## Startup feedback and how to close it

* **Is it running?** Look for the “PBZStats HUD” tray icon and its balloon tip. The five lines in-game are the other confirmation.
* **Close the overlay**: right-click the tray icon → “退出 HUD / Quit”; or quit the game (the HUD exits by itself after ~15 s); or run `PBZStatsHUD.exe --quit`.
* **Remove everything**: run `uninstall.ps1`.
* The tray menu also has “打开数据文件夹 / Open data folder”.

## Settings page (Ctrl+F8)

Press **Ctrl+F8** while the game runs (works in fullscreen, borderless and windowed mode) — or right-click the tray icon → *设置 / Settings*. The panel opens above the game:

* **Hotkey** — click the box and press a new combination (at least one modifier: Ctrl / Alt / Shift / Win). It is saved immediately and registered again; a hint below tells you whether it worked.
* **Visible rows** — untick a line to hide it completely. The other lines move up, no gap is left. Saved instantly.
* **Boss rows: auto / always** — the two boss lines carry two radio buttons next to the checkbox. `auto` (default) draws the row only while a boss fight is running, `always` keeps it on screen all the time. The checkbox still decides whether the row exists at all, and the two options are mutually exclusive.
* **Font size** — `−` / `+` between 8 and 72, or fine-tune it in the drag mode below.
* **Text align** — `Right` hugs the right edge (labels are pushed against the values), `Left` starts the labels at the left edge. Saved instantly and applied to the HUD right away.
* **No focus stealing** — opening the page no longer puts the caret into the hotkey box (the first key press used to be captured as a new shortcut): focus goes to a hidden 1×1 panel, so neither the hotkey box nor the first checkbox takes it.
* **Free position** — the panel closes and the HUD switches into drag mode: the five lines are drawn exactly at their real size, with a small `字体 / Font − N +` strip and a `完成 / Done` button underneath. Move the mouse over the lines — the cursor turns into a move cursor — hold the left button and drag the HUD anywhere. Click **完成 / Done** to save (`margin_right` / `offset_y` in the ini) and lock the position; press **Esc** instead to put it back where it was.

The settings page itself follows the in-game language (English, Chinese, Japanese, Korean, Russian, German, French, Spanish, Portuguese, Italian, Thai and Vietnamese), and it is rebuilt every time it opens, so it always matches the language the game is in right now. Start `PBZStatsHUD.exe --settings` to open it directly. Everything is written to `PBZStatsHUD.ini` immediately, so the layout survives restarts and game updates.

## Configuration

`platform\steam\ue4ss\Mods\PBZStats\PBZStatsHUD.ini`

* `lang=auto` follows the game. Force one with `zh`, `zht`, `en`, `ja`, `ko`, `fr`, `de`, `es`, `pt`, `ru`, `it`, `th`, `vi`.
* `hud_mode=ps` — `ps` (default) runs the overlay through the PowerShell host (no exe, full styling, Ctrl+F8 settings page included); `exe` uses the shipped `PBZStatsHUD.exe` instead; `both` runs both; `none` disables the HUD.
* `settings_hotkey=Ctrl+F8` — global hotkey that opens the settings page.
* `hidden_rows=` — comma-separated row indexes that are hidden (0 = first line, 4 = last). Empty means all five are shown.
* `auto_rows=3,4` — comma-separated row indexes that are only shown while a boss fight is active (3 = current boss, 4 = deaths to that boss). Empty means those rows are always visible. The settings page writes this key when you switch a boss row between `auto` and `always`.
* `ui_lang=os` — language of the **tray menu, tooltip and startup balloon only**: `os` (default) follows the Windows display language, `game` follows the in-game language, or force `en ru de fr es pt it ja ko zh zht th vi`. The HUD text and the settings page always follow the game language (`lang=auto`).
* `align=right` — text alignment inside the HUD: `right` hugs the right edge (label right before its value), `left` starts the labels at the left edge. `data\hud_diffnames.txt` can override the four difficulty names (one per line).
* `data_dir=` empty means `data\` next to `PBZStatsHUD.exe`.
* `max_value_width=620` — maximum pixel width of the value column (boss names); longer text is cut with “…”. Raise it if you want more characters.
* `font_size=26`, `line_gap=8`, `gap=14`, `margin_right=40`, `offset_y=0` control layout. `gap` is the space between a label and its value; smaller means tighter lines.
* `poll_ms=250`, `stale_ms=15000` control refresh.

## Compatibility

* Game: Phantom Blade Zero, UE 5.7.4, Steam appid 4115450 (tested on the October 2026 build).
* Works alongside pure pak resource mods (they load from `~mods` and do not use UE4SS).
* If you already use another **UE4SS** mod: the installer backs up its files before installing, but only one UE4SS base can be present. Restore the other mod with its own installer if needed.
* Read-only: no save edits, no game file edits, no network access.

## Antivirus note (important)

The default `hud_mode=ps` never runs an `.exe`: the overlay is compiled in memory by PowerShell from the shipped `PBZStatsHUD.cs` + `run.ps1`, so suites that quarantine new unsigned binaries have nothing to flag.

If you switch to `hud_mode=exe` you are back to the tiny unsigned `PBZStatsHUD.exe` (360 Total Security in particular quarantines new unsigned executables; symptom: no HUD and the exe disappears from the mod folder). Fix: whitelist `<game>\platform\steam\ue4ss\Mods\PBZStats` and run `install.ps1` again - the Lua script also restores the exe from `hudbox.dat` at every game start.

## FAQ

* **Double-clicking the exe does nothing**: without the game running the overlay stays hidden and only the tray icon is visible. Start the game to see it.
* **No HUD**: check `data\hud.log` and `data\pbzstats.log`. `HUD: start requested ok=true` with no process usually means antivirus blocking.
* **All zeros**: the HUD only reads real data after a save is loaded; the main menu shows placeholders.
* **Boss shows as a class name**: that boss bar does not expose localized text; the fallback is shown.
* **Boss name is shortened**: intended behaviour; raise `max_value_width` to show more.
* **Clean data**: with the game closed, delete the `data\` folder; it is recreated on the next launch.

## Changelog

### v3.8.1 (2026-11-03)

* **The installer no longer crashes on a PC without the hardcoded Steam drive.** v3.7.x / v3.8.0 probed `G:\SteamLibrary\...` with `Join-Path`, which throws `DriveNotFoundException` ("Cannot find drive. A drive with the name 'G' does not exist.") before `Test-Path` can say no, so setup aborted in step 1. Path building now uses `[IO.Path]::Combine` and a quiet `Test-Path` wrapper.
* **When the game folder is not found, the installer asks for it.** It prints an example path, accepts whatever you paste (quotes, trailing `\`, or even `...\PBZ.exe` are stripped) and gives you three tries; press Enter to skip. `-GameDir` still works for scripts, and `-NoPrompt` disables the question.
* **More places to look**: the registry `SteamPath`, every library in `libraryfolders.vdf` (its `\\` escapes are normalised), `steamapps\appmanifest_4115450.acf` (`installdir`), and finally a sweep of `SteamLibrary` / `Steam` / `Program Files (x86)\Steam` / `Games\SteamLibrary` on every fixed drive.
* **Two downloads**: `PBZStatsHUD_v3.8.1_lite.zip` (no UE4SS, for Nexus) and `PBZStatsHUD_v3.8.1_full.zip` (bundles UE4SS + `dwmapi.dll` + the optional exe). One installer handles both, decided by the presence of `ue4ss\UE4SS.dll`.
### v3.8.0 (2026-11-02)

* **The mod no longer ships the injector.** In v3.8.0 the Nexus download is a *lite* package: it contains only `ue4ss\Mods\PBZStats\` (Lua mod, `run.ps1`, `PBZStatsHUD.cs`, `PBZStatsHUD.ini`) plus the two installers and the docs. No `UE4SS.dll`, no `dwmapi.dll`, no `.exe`, no `.dat` - **zero binaries in the archive**.
* It requires the [PBZ UE4SS Framework](https://www.nexusmods.com/phantombladezero/mods/125) (listed as a file requirement). The installer checks for it, tells you where to get it and exits with code `2` if it is not there.
* Installer now handles both package shapes: it detects `lite` (adds the mod folder and enables `PBZStats : 1` in `ue4ss\Mods\mods.txt`, nothing else) or `full` (also installs `dwmapi.dll` + `ue4ss\`, with backups). Status steps are `[n/9]`, exit codes `0` / `1` / `2`.
* Uninstaller removes the mod folder, the `mods.txt` line and the marker; on a `lite` install the framework and `dwmapi.dll` are deliberately left in place (they are yours, other mods may need them).
* Same HUD as 3.7.1: hidden PowerShell host (default `hud_mode=ps`), Ctrl+F8 settings page, 13 languages, no data files outside `data\`.
* **New: the two boss rows can follow the fight.** In the settings page each boss row ("current boss" / "deaths to that boss") now has an `auto` / `always` switch next to its checkbox: `auto` (default) draws the row only while a boss fight is running, `always` keeps it on screen. The checkbox still decides whether the row exists at all. Stored as `auto_rows=3,4` in the ini, applied within one poll interval (~250 ms), no restart needed.
* **New: `ui_lang` for the tray.** The tray menu, tooltip and startup balloon now follow the Windows display language by default (`ui_lang=os`); `ui_lang=game` follows the game, any language code forces one. The HUD itself and the settings page keep following the game language.
* Fixed: the `auto` / `always` switches showed broken CJK glyphs (常显 lost its bottom stroke). WinForms buttons paint text from the font baseline and clip what falls below, so font size and padding only masked it — the switches are now **radio buttons whose label is painted with GDI+** (grid-fit antialiasing, 10.5 pt), so they read like normal text in all 13 languages.
* Fixed: the HUD could stay hidden ("unresponsive") for the rest of the session when the free-position edit panel was closed by Alt+F4 or a lost focus — the render loop now detects the disposed panel, resets the edit mode and restores the HUD (log: `edit mode auto-reset`).

### v3.7.1 (2026-11-01)

- Fixed: one Ctrl+F8 press could open the settings page several times in a row (Windows posted WM_HOTKEY repeatedly); the panel now ignores repeats inside 450 ms.
- Fixed: reading stats.txt no longer blocks the mod's own write. The overlay opened the file with FileShare.Read only, so the Lua side could log "cannot write stats.txt" and the HUD showed stale numbers. It now shares read/write/delete and retries.

### v3.7.0 (2026-11-01)

- **No more .exe by default.** The Lua mod now launches a hidden PowerShell host (run.ps1 + PBZStatsHUD.cs) that compiles the overlay in memory and draws exactly the same HUD and Ctrl+F8 settings page. Nothing is written to disk, so antivirus suites have nothing to quarantine.
- hud_mode values changed to ps (default) / exe / both / none; the standalone exe is still shipped and can be enabled with hud_mode=exe.
- The in-game UMG HUD and the in-game settings panel were removed (they could not match the original styling); the PowerShell host replaces them.
- Installer summary and closing hints now say which mode will start the HUD; the uninstaller also stops any leftover PowerShell host.

### v3.6.5 (2026-11-01)

- **In-game HUD now works.** The UMG rows are drawn by the mod itself: one container widget plus five text blocks added over ~5 seconds, so the game no longer crashes while the level is still loading.
- The HUD waits until a save is loaded, then shows the five rows on the right (or left) with the configured font size and margins.
- No external exe is started in the default `hud_mode=umg`; nothing to whitelist in antivirus software.


* v3.6.1 — hotfix for the in-game HUD not appearing: the level-name check no longer blocks the build when the game reports an empty level, and the UMG build now writes `hud: first build attempt…` / `hud tick error…` / `hud: UMG build failed…` into `data\pbzstats.log`. If the in-game HUD still does not show, set `hud_mode=exe` to use the overlay.
* v3.6.0 — **in-game HUD by default**: the Lua mod draws the five lines with UMG inside the game, so no external exe is started and antivirus tools have nothing to flag. The standalone overlay is still included and can be enabled with `hud_mode=exe` (that mode also provides the Ctrl+F8 settings page). New `hud_mode` ini key (`umg`/`exe`/`off`); the in-game HUD follows the game language and the `align`, `gap`, `font_size`, `margin_right`, `offset_y` settings from the same ini.
* v3.5.1 — hotfix: 3.5.0 could show nothing because the Lua script failed to compile (encoding damage in the shipped main.lua) and the new difficulty table read a forward-declared variable; the script is byte-clean again, the difficulty name is passed as a parameter.
* v3.5.0 — tighter HUD: a label and its value now sit next to each other with a single `gap` (default 14) instead of two far-apart columns; **difficulty names follow the game language** (13 languages) and can be overridden with `data\hud_diffnames.txt`. The settings panel is rebuilt on every open (so the title and the Text-align buttons switch language together), the title background is gone, the redundant “Done” hint next to Free position was removed, and `PBZStatsHUD.exe --settings` opens the panel directly.

* v3.4.0 — the settings page follows the in-game language (13 languages), and a new **Text align** setting (`align` ini key) switches the HUD lines between right-aligned and left-aligned; the settings panel is fully localised and shows the live version.
* v3.3.0 — new settings page (default **Ctrl+F8**, hotkey configurable): toggle each row on/off (hidden rows are not drawn at all), change the font size, and drag the HUD to any position with the mouse (`完成 / Done` saves it). Adds the `settings_hotkey` and `hidden_rows` ini keys and a *设置 / Settings* entry in the tray menu.
* v3.2.2 — the HUD version is now shown in the startup notification, the tray tooltip and the tray menu (read from `stats.txt`, so it always matches the installed files); installer and uninstaller print `[n/8]` step status with `OK` / `WARN` / `FAIL`, a final `RESULT:` verdict, an exit code and a transcript in `%TEMP%`; fixed the injector size check and the `-KeepData` backup folder.
* v3.2.2 (tray fix) — the tray right-click menu no longer freezes: the render loop runs on a worker thread while the main thread keeps a real WinForms message loop, so the menu opens, responds and closes normally.
* v3.2.1 — the HUD follows the in-game language live: the engine culture is re-read every few seconds, so switching the language in the options menu updates the overlay without a restart; boss names are shown in the language of the row they appear in.
* v3.2.0 — long boss names clamped by pixel width with an ellipsis (`max_value_width`); installer gains `-NoBackup`, own-install marker and backup deduplication; docs updated (compatibility, truncation, installer behaviour).
* v3.1.0 — tray icon + balloon startup feedback, tray menu to quit/open data folder; all data and logs moved into `data\`; fixed Simplified and Traditional Chinese showing at the same time.
* v3.0.0 — traditional layout (all files in the game folder; no autostart, no watcher, no Python); HUD started by in-game Lua and exits with the game; 13 languages following the game; new line order; `hudbox.dat` restore for antivirus cases.
* v2.0.0 — Python removed, C# HUD, boss name and cycle added.
* v1.1.0 — per-boss history from the save's `BossRecord` (attempts − kills).
* v1.0.x — initial releases (Python overlay).

## Credits

UE4SS and the PBZ community signature fixes (Muspelion et al.). All data is read from the game's own runtime state.
