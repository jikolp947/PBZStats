# PBZStats — Phantom Blade Zero death counter HUD (v3.7.1)

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
* **One data folder**: all generated data and logs live in `data\` next to `PBZStatsHUD.exe`; delete that folder to clean up.
* **Settings page**: press **Ctrl+F8** (configurable) in game to open a settings panel on top of the game — choose which rows are shown, change the font size, or drag the HUD to any position.
* **HUD (default)**: the Lua mod starts a hidden **PowerShell host** (`run.ps1`) that compiles `PBZStatsHUD.cs` in memory and draws the same overlay as before - no `.exe` is written to disk, so antivirus tools have nothing to quarantine. Set `hud_mode=exe` in `PBZStatsHUD.ini` to use the shipped standalone exe instead (optional, offline installs).

---

## Which download? / 下载哪个包

This mod ships in two builds. Both are the same version and the same in-game result; they only differ in whether the optional standalone overlay executable is included.

| Build | Contents | Best for |
| --- | --- | --- |
| **PowerShell-only** (Nexus download, `*_noexe.zip` on GitHub) | Lua mod + UE4SS + `run.ps1` + `PBZStatsHUD.cs`; **no .exe** on disk | Default. Antivirus-safe: nothing to quarantine, no unsigned binary. |
| **Full** (GitHub release, `PBZStatsHUD_v3.7.1.zip`) | Everything above **plus** `PBZStatsHUD.exe` + `hudbox.dat` | Offline/locked-down machines, or if you want the optional `hud_mode=exe` overlay. |

* The default mode is `hud_mode=ps`: the mod starts a hidden PowerShell host that compiles `PBZStatsHUD.cs` in memory and draws the HUD. Nothing is written as an executable.
* `hud_mode=exe` only works in the full build (it needs `PBZStatsHUD.exe`).
* Both builds install, update and uninstall the same way.

### 中文：下载哪个包

* **PowerShell 版（N 网下载的包、GitHub 的 `*_noexe.zip`）**：不含任何 exe，默认就用这个版本——杀毒软件没有可隔离的目标。
* **完整版（GitHub release 的 `PBZStatsHUD_v3.7.1.zip`）**：额外带 `PBZStatsHUD.exe` + `hudbox.dat`，只有想用 `hud_mode=exe` 的老式覆盖层才需要。
* 两个包版本相同、安装/更新/卸载方式相同，默认都走 `hud_mode=ps`。

---
## Install

1. Close the game.
2. Extract the archive and run `install.ps1` from PowerShell:
   `powershell -ExecutionPolicy Bypass -File install.ps1`
3. The script auto-detects the Steam library. If it fails:
   `powershell -ExecutionPolicy Bypass -File install.ps1 -GameDir "G:\SteamLibrary\steamapps\common\PBZ"`
4. It installs `platform\steam\dwmapi.dll` (UE4SS injector) and `platform\steam\ue4ss\` (UE4SS + PBZStats mod). The mod folder also contains `run.ps1`, `PBZStatsHUD.cs`, `PBZStatsHUD.ini` and a `data\` folder. The full build additionally ships `PBZStatsHUD.exe` + `hudbox.dat`; the PowerShell-only build ships neither (the installer then reports `HUD exe (optional): not shipped in this build`).
5. Launch the game from Steam normally; load a save and the HUD appears on the right. The tray icon confirms it is running.

### Installer behaviour

* **Visible status**: every step prints `[n/8]`, each action prints `OK` / `WARN` / `FAIL`, and the run ends with `RESULT: INSTALL SUCCESSFUL`, `INSTALLED WITH WARNINGS` or `FAILED` (exit code 0 / 1). A full transcript is written to `%TEMP%\PBZStats_install_<timestamp>.log`, and double-clicking the script keeps the window open so you can read the result.
* **First install**: if another `ue4ss\` or `dwmapi.dll` is present (another UE4SS mod), it is renamed to a backup before installing. At most two backups are kept, so nothing of yours is lost.
* **Reinstall / update**: a `.pbzstats_version` marker identifies our own installation; it is updated in place without creating backups.
* **`-NoBackup`**: for advanced users who explicitly want no backups at all (only when no other UE4SS mod is installed).
* **Updates keep your data**: reinstalling preserves the statistics and logs in `data\`.

Manual install: copy `files\dwmapi.dll` and `files\ue4ss` into `<game>\platform\steam\` (back up existing files first).

## Uninstall

Run `uninstall.ps1` (stops the HUD, removes `ue4ss\Mods\PBZStats` including `data\`, restores the renamed `dwmapi.dll`, removes `.pbzstats_version`). Use `-KeepData` to back up `stats.json`, `stats.txt` and logs to `%LOCALAPPDATA%\PBZStats_backup_<timestamp>` first. It prints the same `[n/8]` / `OK` / `WARN` / `FAIL` lines and ends with `RESULT: UNINSTALL SUCCESSFUL`, `UNINSTALLED WITH WARNINGS` or `FAILED` (exit code 0 / 1), with a transcript in `%TEMP%\PBZStats_uninstall_<timestamp>.log`.


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
* **Font size** — `−` / `+` between 8 and 72, or fine-tune it in the drag mode below.
* **Text align** — `Right` hugs the right edge (labels are pushed against the values), `Left` starts the labels at the left edge. Saved instantly and applied to the HUD right away.
* **Free position** — the panel closes and the HUD switches into drag mode: the five lines are drawn exactly at their real size, with a small `字体 / Font − N +` strip and a `完成 / Done` button underneath. Move the mouse over the lines — the cursor turns into a move cursor — hold the left button and drag the HUD anywhere. Click **完成 / Done** to save (`margin_right` / `offset_y` in the ini) and lock the position; press **Esc** instead to put it back where it was.

The settings page itself follows the in-game language (English, Chinese, Japanese, Korean, Russian, German, French, Spanish, Portuguese, Italian, Thai and Vietnamese), and it is rebuilt every time it opens, so it always matches the language the game is in right now. Start `PBZStatsHUD.exe --settings` to open it directly. Everything is written to `PBZStatsHUD.ini` immediately, so the layout survives restarts and game updates.

## Configuration

`platform\steam\ue4ss\Mods\PBZStats\PBZStatsHUD.ini`

* `lang=auto` follows the game. Force one with `zh`, `zht`, `en`, `ja`, `ko`, `fr`, `de`, `es`, `pt`, `ru`, `it`, `th`, `vi`.
* `hud_mode=ps` — `ps` (default) runs the overlay through the PowerShell host (no exe, full styling, Ctrl+F8 settings page included); `exe` uses the shipped `PBZStatsHUD.exe` instead; `both` runs both; `none` disables the HUD.
* `settings_hotkey=Ctrl+F8` — global hotkey that opens the settings page.
* `hidden_rows=` — comma-separated row indexes that are hidden (0 = first line, 4 = last). Empty means all five are shown.
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
