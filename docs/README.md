# PBZStats — Phantom Blade Zero death counter HUD (v3.2.1)

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

---

## Install

1. Close the game.
2. Extract the archive and run `install.ps1` from PowerShell:
   `powershell -ExecutionPolicy Bypass -File install.ps1`
3. The script auto-detects the Steam library. If it fails:
   `powershell -ExecutionPolicy Bypass -File install.ps1 -GameDir "G:\SteamLibrary\steamapps\common\PBZ"`
4. It installs `platform\steam\dwmapi.dll` (UE4SS injector) and `platform\steam\ue4ss\` (UE4SS + PBZStats mod). The mod folder also contains `PBZStatsHUD.exe`, `PBZStatsHUD.ini` and a `data\` folder.
5. Launch the game from Steam normally; load a save and the HUD appears on the right. The tray icon confirms it is running.

### Installer behaviour

* **First install**: if another `ue4ss\` or `dwmapi.dll` is present (another UE4SS mod), it is renamed to a backup before installing. At most two backups are kept, so nothing of yours is lost.
* **Reinstall / update**: a `.pbzstats_version` marker identifies our own installation; it is updated in place without creating backups.
* **`-NoBackup`**: for advanced users who explicitly want no backups at all (only when no other UE4SS mod is installed).
* **Updates keep your data**: reinstalling preserves the statistics and logs in `data\`.

Manual install: copy `files\dwmapi.dll` and `files\ue4ss` into `<game>\platform\steam\` (back up existing files first).

## Uninstall

Run `uninstall.ps1` (stops the HUD, removes `ue4ss\Mods\PBZStats` including `data\`, restores the renamed `dwmapi.dll`, removes `.pbzstats_version`). Use `-KeepData` to back up `stats.json`, `stats.txt` and logs to `%LOCALAPPDATA%\PBZStats_backup_<timestamp>` first.

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

## Configuration

`platform\steam\ue4ss\Mods\PBZStats\PBZStatsHUD.ini`

* `lang=auto` follows the game. Force one with `zh`, `zht`, `en`, `ja`, `ko`, `fr`, `de`, `es`, `pt`, `ru`, `it`, `th`, `vi`.
* `data_dir=` empty means `data\` next to `PBZStatsHUD.exe`.
* `max_value_width=620` — maximum pixel width of the value column (boss names); longer text is cut with “…”. Raise it if you want more characters.
* `font_size=26`, `line_gap=8`, `gap=26`, `margin_right=40`, `offset_y=0` control layout.
* `poll_ms=250`, `stale_ms=15000` control refresh.

## Compatibility

* Game: Phantom Blade Zero, UE 5.7.4, Steam appid 4115450 (tested on the October 2026 build).
* Works alongside pure pak resource mods (they load from `~mods` and do not use UE4SS).
* If you already use another **UE4SS** mod: the installer backs up its files before installing, but only one UE4SS base can be present. Restore the other mod with its own installer if needed.
* Read-only: no save edits, no game file edits, no network access.

## Antivirus note (important)

`PBZStatsHUD.exe` is a tiny unsigned helper. Some security suites (360 Total Security in particular) quarantine new unsigned executables. Symptoms: no HUD in game and the exe disappears from the mod folder.

Fix: add `<game>\platform\steam\ue4ss\Mods\PBZStats` to the whitelist and run `install.ps1` again. The mod also ships `hudbox.dat`, a copy of the HUD; the Lua script restores `PBZStatsHUD.exe` from it at every game start, so whitelisting is enough.

## FAQ

* **Double-clicking the exe does nothing**: without the game running the overlay stays hidden and only the tray icon is visible. Start the game to see it.
* **No HUD**: check `data\hud.log` and `data\pbzstats.log`. `HUD: start requested ok=true` with no process usually means antivirus blocking.
* **All zeros**: the HUD only reads real data after a save is loaded; the main menu shows placeholders.
* **Boss shows as a class name**: that boss bar does not expose localized text; the fallback is shown.
* **Boss name is shortened**: intended behaviour; raise `max_value_width` to show more.
* **Clean data**: with the game closed, delete the `data\` folder; it is recreated on the next launch.

## Changelog

* v3.2.1 — the HUD follows the in-game language live: the engine culture is re-read every few seconds, so switching the language in the options menu updates the overlay without a restart; boss names are shown in the language of the row they appear in.
* v3.2.0 — long boss names clamped by pixel width with an ellipsis (`max_value_width`); installer gains `-NoBackup`, own-install marker and backup deduplication; docs updated (compatibility, truncation, installer behaviour).
* v3.1.0 — tray icon + balloon startup feedback, tray menu to quit/open data folder; all data and logs moved into `data\`; fixed Simplified and Traditional Chinese showing at the same time.
* v3.0.0 — traditional layout (all files in the game folder; no autostart, no watcher, no Python); HUD started by in-game Lua and exits with the game; 13 languages following the game; new line order; `hudbox.dat` restore for antivirus cases.
* v2.0.0 — Python removed, C# HUD, boss name and cycle added.
* v1.1.0 — per-boss history from the save's `BossRecord` (attempts − kills).
* v1.0.x — initial releases (Python overlay).

## Credits

UE4SS and the PBZ community signature fixes (Muspelion et al.). All data is read from the game's own runtime state.
