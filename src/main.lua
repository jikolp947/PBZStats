--[[==========================================================================
  PBZStats for Phantom Blade Zero (影之刃零)
  Shows, at the right-middle of the screen (via the bundled C# HUD,
  PBZStatsHUD.exe - no Python or any other runtime needed):
    1) total deaths (whole game / save)
    2) deaths to the current boss in the current scene
    3) current difficulty level
    4) current boss name
    5) current cycle (NG+ count)
  The HUD language follows the in-game language (Chinese / English).

  Data is read from the live game objects with UE4SS Lua:
    - PBZGameSystem.DiedTimes            -> total deaths
    - PBZGameSystem.DifficultModeByte    -> current difficulty
    - PBZHUDLayout:RegisterBossHPBar     -> boss fight detection / boss identity
    - PBZSaveLoadSubsystem:SaveJsonObjectToString -> the save JSON as the game
      itself builds it (plain text), whose top level "BossRecord" map holds, for
      every boss, Records["<cycle>_<difficulty>"] = { AttemptCount, KillCount,
      BestTimeMs }. Deaths to that boss = AttemptCount - KillCount, so the HUD can
      show the real historical number (including fights that happened before the
      mod was installed), exactly like the Heybox archive page does.
  The mod also keeps its own session counters (persisted to
    E:\PBZModOut\pbz_boss_deaths.txt) as a fallback for bosses that have no
  BossRecord yet (first encounter).

  Outputs (outside the game dir):
    <data dir>\stats.json        <- machine readable snapshot
    <data dir>\stats.txt         <- line protocol read by PBZStatsHUD.exe
    <data dir>\pbzstats.log      <- mod log
    <data dir>\cmd.txt           <- debug command inbox (optional)

  All reads are passive. No game data is modified.
============================================================================]]

-- Release version of the mod (shown in the tray notification and written to
-- stats.txt/json so the HUD exe can display it). Keep in sync with install.ps1
-- and the Nexus file version when publishing.
local MOD_VERSION = "3.7.1"

local OUT = "E:\\PBZModOut\\"
local STATS_PATH = OUT .. "stats.json"
local STATS_TXT = OUT .. "stats.txt"
local BOSS_PATH = OUT .. "pbz_boss_deaths.txt"
local LOG_PATH = OUT .. "pbzstats.log"
local CMD_PATH = OUT .. "cmd.txt"

-- The installer creates the data folder, but keep it self-healing in case a
-- player deletes it while the game is closed (all data lives in one folder).
pcall(function()
    local d = string.gsub(OUT, "\\+$", "")
    if d ~= "" then
        os.execute('if not exist "' .. d .. '" mkdir "' .. d .. '" >nul 2>nul')
    end
end)
local TOTAL_PATH = OUT .. "pbz_last_total.txt"
local LASTBOSS_PATH = OUT .. "pbz_last_boss.txt"

local DIFF_NAMES = {
    [0] = "入阵者",
    [1] = "入阵者",
    [2] = "破局者",
    [3] = "逆天者",
    [4] = "六十六天",
}

local DIFF_NAMES_EN = {
    [0] = "Easy",
    [1] = "Easy",
    [2] = "Normal",
    [3] = "Hard",
    [4] = "Nightmare",
}

-- Difficulty names per language. The game ships its own localized names; this
-- table mirrors them so the HUD shows exactly the word the game shows. If your
-- build words a difficulty differently, drop a plain text file
-- data\hud_diffnames.txt with four lines (easy / normal / hard / nightmare) and
-- the HUD uses those instead.
local DIFF_BY_LANG = {
    zh   = { [1] = "入阵者", [2] = "破局者", [3] = "逆天者", [4] = "六十六天" },
    zht  = { [1] = "入陣者", [2] = "破局者", [3] = "逆天者", [4] = "六十六天" },
    ja   = { [1] = "入陣者", [2] = "破局者", [3] = "逆天者", [4] = "六十六天" },
    ko   = { [1] = "입진자", [2] = "파국자", [3] = "역천자", [4] = "육십육천" },
    en   = DIFF_NAMES_EN,
    fr   = { [1] = "Facile", [2] = "Normal", [3] = "Difficile", [4] = "Cauchemar" },
    de   = { [1] = "Leicht", [2] = "Normal", [3] = "Schwer", [4] = "Albtraum" },
    es   = { [1] = "Fácil", [2] = "Normal", [3] = "Difícil", [4] = "Pesadilla" },
    pt   = { [1] = "Fácil", [2] = "Normal", [3] = "Difícil", [4] = "Pesadelo" },
    ru   = { [1] = "Легко", [2] = "Нормально", [3] = "Сложно", [4] = "Кошмар" },
    it   = { [1] = "Facile", [2] = "Normale", [3] = "Difficile", [4] = "Incubo" },
    th   = { [1] = "ง่าย", [2] = "ปกติ", [3] = "ยาก", [4] = "ฝันร้าย" },
    vi   = { [1] = "Dễ", [2] = "Thường", [3] = "Khó", [4] = "Ác mộng" },
}

local DIFF_OVERRIDE = {}
local diffOverrideLoaded = false
local DIFF_OVERRIDE_PATH = OUT .. "hud_diffnames.txt"

local function loadDiffOverride()
    if diffOverrideLoaded then return end
    diffOverrideLoaded = true
    local f = io.open(DIFF_OVERRIDE_PATH, "r")
    if not f then return end
    local idx = 0
    for line in f:lines() do
        local v = string.gsub(line, "^\239\187\191", "")
        v = string.gsub(v, "^%s+", "")
        v = string.gsub(v, "%s+$", "")
        if v ~= "" then
            idx = idx + 1
            if idx >= 1 and idx <= 4 then DIFF_OVERRIDE[idx] = v end
        end
    end
    f:close()
end

local function diffText(code, db, name)
    loadDiffOverride()
    if DIFF_OVERRIDE[db] then return DIFF_OVERRIDE[db] end
    local t = DIFF_BY_LANG[code] or DIFF_BY_LANG.en
    return t[db] or name
end

-- HUD copy for every language the game ships. Every set is written to stats.txt
-- and PBZStatsHUD.exe shows the one matching the language the game runs in.
local L10N = {
    zh   = { cycle = "当前周目", diff = "当前难度", total = "死亡总数", boss = "当前 Boss", bossdeaths = "本 Boss 死亡" },
    zht  = { cycle = "當前週目", diff = "當前難度", total = "死亡總數", boss = "當前 Boss", bossdeaths = "本 Boss 死亡" },
    en   = { cycle = "Cycle", diff = "Difficulty", total = "Total Deaths", boss = "Boss", bossdeaths = "Boss Deaths" },
    ja   = { cycle = "周回", diff = "難易度", total = "総死亡回数", boss = "現在のボス", bossdeaths = "ボスの死亡回数" },
    ko   = { cycle = "회차", diff = "난이도", total = "총 사망 횟수", boss = "현재 보스", bossdeaths = "보스 사망 횟수" },
    fr   = { cycle = "Cycle", diff = "Difficulté", total = "Morts totales", boss = "Boss", bossdeaths = "Morts du boss" },
    de   = { cycle = "Zyklus", diff = "Schwierigkeit", total = "Todesfälle gesamt", boss = "Boss", bossdeaths = "Boss-Todesfälle" },
    es   = { cycle = "Ciclo", diff = "Dificultad", total = "Muertes totales", boss = "Jefe", bossdeaths = "Muertes del jefe" },
    pt   = { cycle = "Ciclo", diff = "Dificuldade", total = "Mortes totais", boss = "Chefe", bossdeaths = "Mortes do chefe" },
    ru   = { cycle = "Цикл", diff = "Сложность", total = "Всего смертей", boss = "Босс", bossdeaths = "Смертей босса" },
    it   = { cycle = "Ciclo", diff = "Difficoltà", total = "Morte totali", boss = "Boss", bossdeaths = "Morti del boss" },
    th   = { cycle = "รอบ", diff = "ความยาก", total = "เสียชีวิตรวม", boss = "บอสปัจจุบัน", bossdeaths = "เสียชีวิตบอส" },
    vi   = { cycle = "Vòng", diff = "Độ khó", total = "Tổng số lần chết", boss = "Boss hiện tại", bossdeaths = "Số lần chết của boss" },
}
local LANG_ORDER = { "zh", "zht", "en", "ja", "ko", "fr", "de", "es", "pt", "ru", "it", "th", "vi" }
local CYCLE_FMT = {
    zh = function(n) return "第 " .. n .. " 周目" end,
    zht = function(n) return "第 " .. n .. " 週目" end,
    en = function(n) return "Cycle " .. n end,
    ja = function(n) return "第" .. n .. "周目" end,
    ko = function(n) return n .. "회차" end,
    fr = function(n) return "Cycle " .. n end,
    de = function(n) return "Zyklus " .. n end,
    es = function(n) return "Ciclo " .. n end,
    pt = function(n) return "Ciclo " .. n end,
    ru = function(n) return "Цикл " .. n end,
    it = function(n) return "Ciclo " .. n end,
    th = function(n) return "รอบที่ " .. n end,
    vi = function(n) return "Vòng " .. n end,
}

-- Chinese display names for bosses whose English class names the save uses.
-- Only used when the game runs in a language where the HP bar text is not CJK.
local BOSS_NAMES_ZH = {
    ["BP_Monster_MoTian_LongZhu_01"] = "摩天·龙柱",
}

local BOSS_NAMES_EN = {
    ["BP_Monster_MoTian_LongZhu_01"] = "MoTian, the Dragon Pillar",
}

local POLL_MS = 800
local STATS_MIN_INTERVAL = 1.0
local BAR_RECENT_SECS = 30
local RE_FIND_SECS = 5

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------
local function openlog()
    local f = io.open(LOG_PATH, "w")
    if f then f:close() end
    return io.open(LOG_PATH, "a")
end

local LOG = openlog()
local function log(msg)
    if LOG then
        local ok, line = pcall(string.format, "[%s] %s", (os.date and os.date("%H:%M:%S")) or "?", tostring(msg))
        if ok then
            LOG:write(line .. "\n")
            LOG:flush()
        end
    end
end

local function safe(fn, ...)
    local ok, res = pcall(fn, ...)
    if ok then
        return res
    end
    return nil, tostring(res)
end

local function readProp(obj, name)
    if not obj then return nil end
    local v = safe(function() return obj:GetPropertyValue(name) end)
    return v
end

local function asNumber(v)
    if type(v) == "number" then return v end
    if type(v) == "boolean" then return v and 1 or 0 end
    return nil
end

local function isValid(obj)
    if not obj then return false end
    local ok, res = pcall(function() return obj:IsValid() end)
    return ok and res == true
end

local function fmtValue(v)
    if v == nil then return "nil" end
    local t = type(v)
    if t == "number" or t == "boolean" or t == "string" then
        return tostring(v)
    end
    local ok, name = pcall(function() return v:GetFullName() end)
    if ok and type(name) == "string" then return name end
    return t
end

-- monotonic-ish seconds (os.time may be unavailable in some sandboxes)
local clockBase = os.time and os.time() or nil
local clockTicks = 0
local function nowSec()
    if os.time then
        local ok, t = pcall(os.time)
        if ok and type(t) == "number" then return t end
    end
    clockTicks = clockTicks + (POLL_MS / 1000.0)
    return (clockBase or 0) + math.floor(clockTicks)
end

-- ---------------------------------------------------------------------------
-- persistent boss death counters
-- ---------------------------------------------------------------------------
local bossCounts = {}
local bossCountsDirty = false

local function loadBossCounts()
    local f = io.open(BOSS_PATH, "r")
    if not f then return end
    for line in f:lines() do
        local k, n = string.match(line, "^([^=]+)=(-?%d+)$")
        if k and n then
            bossCounts[k] = tonumber(n) or 0
        end
    end
    f:close()
end

local function saveBossCounts()
    local keys = {}
    for k in pairs(bossCounts) do keys[#keys + 1] = k end
    table.sort(keys)
    local f = io.open(BOSS_PATH, "w")
    if not f then return end
    for _, k in ipairs(keys) do
        f:write(k .. "=" .. tostring(bossCounts[k]) .. "\n")
    end
    f:close()
    bossCountsDirty = false
end

-- Last total deaths we saw inside a real gameplay world. The title screen's
-- PBZGameSystem reports DiedTimes = 0 (no save loaded), which would wrongly show
-- "0" in the HUD; we keep showing the last real value until a save is loaded.
local function loadLastTotal()
    local f = io.open(TOTAL_PATH, "r")
    if not f then return nil end
    local txt = f:read("*a") or ""
    f:close()
    txt = string.gsub(txt, "%s+", "")
    local n = tonumber(txt)
    if n and n >= 0 then return math.floor(n) end
    return nil
end

local function saveLastTotal(n)
    if n == nil then return end
    local f = io.open(TOTAL_PATH, "w")
    if not f then return end
    f:write(tostring(math.floor(n)) .. "\n")
    f:close()
end

-- Last boss we displayed, so the HUD can still show which boss the death counter
-- belongs to after a restart (before the next boss fight starts).
-- The name is stored together with the language it was captured in, because the
-- game's boss bar text is already localized: showing a Chinese bar text in the
-- English row set was exactly the mixed-language bug this file used to produce.
local function loadLastBoss()
    local f = io.open(LASTBOSS_PATH, "r")
    if not f then return nil, nil, "" end
    local line = f:read("*l") or ""
    f:close()
    if line == "" then return nil, nil, "" end
    local key, lang, name = string.match(line, "^([^|]*)|([^|]*)|(.*)$")
    if key ~= nil and key ~= "" then return key, name, lang end
    -- legacy two-field line: key|name (no language tag)
    local oldKey, oldName = string.match(line, "^([^|]*)|(.*)$")
    if oldKey == nil or oldKey == "" then return nil, nil, "" end
    return oldKey, oldName, ""
end

local function saveLastBoss(key, lang, name)
    if key == nil or key == "" then return end
    local f = io.open(LASTBOSS_PATH, "w")
    if not f then return end
    f:write(key .. "|" .. tostring(lang or "") .. "|" .. tostring(name or "") .. "\n")
    f:close()
end

-- ---------------------------------------------------------------------------
-- state
-- ---------------------------------------------------------------------------
local S = {
    game = nil,
    hud = nil,
    fnBars = nil,
    fnLevel = nil,
    gameId = "",
    baseReady = false,
    lastGameFind = 0,
    lastHudFind = 0,
    total = nil,
    prevTotal = nil,
    -- displayed total: seeded from the last session so the title screen shows the
    -- cumulative count instead of the menu world's placeholder 0
    displayTotal = 0,
    menuWorld = false,
    -- Default for the boot/title screen (before a save is loaded): the game's
    -- standing difficulty setting is 破局者 (Normal, byte 2). This keeps the HUD
    -- from showing "未知" while the PBZGameSystem instance is not ready yet; a
    -- valid DifficultModeByte (1..4) always overrides it once a save is loaded.
    diffByte = 2,
    diffName = "破局者",
    level = "",
    cycleCount = 0,
    lang = "",
    langVerified = false,
    langTs = 0,
    langProbeLogged = false,
    langChanged = false,
    bossActive = false,
    bossKey = "",
    bossName = "",
    bossNameLang = "",
    lastBarTs = 0,
    bossDeaths = 0,
    lastStatsWrite = 0,
    lastCmd = "",
    stopped = false,
    deathEvents = 0,
    barsWidgets = 0,
    lastWidgetScan = 0,
    hookBarOk = false,
    hookDiedOk = false,
    -- historical per-boss deaths, read from the game's own save JSON
    saveSys = nil,
    fnSaveStr = nil,
    histDeaths = nil,
    histKey = "",
    histAttempts = nil,
    histKills = nil,
    histTs = 0,
    lastHistKey = "",
    histDirty = false,
    pendingBar = nil,
    needBar = false,
}

-- Remember the last boss we saw so the HUD can keep showing its death count
-- after a restart (until another boss fight starts).
local function setBossName(name)
    if name == nil or name == "" or name == S.bossName then return end
    S.bossName = name
    S.bossNameLang = S.lang or ""
    saveLastBoss(S.bossKey, S.bossNameLang, S.bossName)
end

local function setBossIdentity(key, name)
    if key == nil or key == "" then return end
    if key ~= S.bossKey then
        S.bossKey = key
        S.bossName = ""
        S.bossNameLang = ""
        setBossName(name)
        saveLastBoss(S.bossKey, S.bossNameLang, S.bossName)
        S.histDirty = true
        log("boss identity -> " .. key .. " (" .. tostring(S.bossName) .. ")")
    elseif name ~= nil and name ~= "" and name ~= S.bossName then
        setBossName(name)
    end
end

local function findGame()
    local t = nowSec()
    if isValid(S.game) then return S.game end
    if t - S.lastGameFind < RE_FIND_SECS then return nil end
    S.lastGameFind = t
    local list = safe(function() return FindAllOf("PBZGameSystem") end)
    if type(list) == "table" and #list > 0 then
        S.game = list[1]
        local id = fmtValue(S.game)
        if id ~= S.gameId then
            S.gameId = id
            S.baseReady = false
            -- StartMenu / ServerCheck worlds are not a loaded save: their
            -- PBZGameSystem reports placeholder values (DiedTimes = 0).
            local lower = string.lower(id)
            S.menuWorld = (string.find(lower, "startmenu", 1, true) ~= nil)
                or (string.find(lower, "servercheck", 1, true) ~= nil)
            log("found PBZGameSystem: " .. id)
        end
    end
    return S.game
end

local function findHud()
    local t = nowSec()
    if isValid(S.hud) then return S.hud end
    if t - S.lastHudFind < RE_FIND_SECS then return nil end
    S.lastHudFind = t
    local list = safe(function() return FindAllOf("W_FrontEndHUDLayout_C") end)
    if type(list) == "table" and #list > 0 then
        S.hud = list[1]
        log("found HUD layout: " .. fmtValue(S.hud))
    end
    return S.hud
end

local function ensureBarsFn()
    if S.fnBars and isValid(S.fnBars) then return S.fnBars end
    local fn = safe(function()
        return StaticFindObject("/Script/ProjectPBZ.PBZHUDLayout:GetBossHPBarInstances")
    end)
    if fn then
        S.fnBars = fn
        log("found GetBossHPBarInstances UFunction")
    end
    return S.fnBars
end

local function ensureLevelFn()
    if S.fnLevel and isValid(S.fnLevel) then return S.fnLevel end
    local fn = safe(function()
        return StaticFindObject("/Script/ProjectPBZ.PBZGameSystem:GetCurrentLevelName")
    end)
    if fn then
        S.fnLevel = fn
    end
    return S.fnLevel
end

local function readLevel(game)
    local fn = ensureLevelFn()
    if game and fn then
        local v = safe(function() return game:CallFunction(fn) end)
        if type(v) == "string" and v ~= "" and v ~= "None" then
            return v
        end
    end
    local lvl = readProp(game, "CurrentLevelName")
    if lvl ~= nil then
        if type(lvl) == "string" then
            if lvl ~= "" and lvl ~= "None" then return lvl end
            return ""
        end
        local ok, s = pcall(function() return lvl:ToString() end)
        if ok and type(s) == "string" and s ~= "" and s ~= "None" then return s end
    end
    return ""
end

-- Convert an FString (userdata) or plain string into a Lua string.
local function toLuaString(v)
    if v == nil then return nil end
    if type(v) == "string" then return v end
    local ok, s = pcall(function() return v:ToString() end)
    if ok and type(s) == "string" then return s end
    return nil
end

-- true when the string starts with a CJK character (UTF-8 lead byte E4..E9)
local function hasCJK(s)
    if type(s) ~= "string" or s == "" then return false end
    local b = string.byte(s, 1)
    return b ~= nil and b >= 0xE4 and b <= 0xE9
end

local function normalizeLang(s)
    if type(s) ~= "string" or s == "" then return nil end
    local l = string.lower(s):gsub("_", "-")
    if string.find(l, "hant", 1, true) or string.find(l, "traditional", 1, true)
        or string.find(l, "tw", 1, true) or string.find(l, "hk", 1, true) then
        return "zht"
    end
    local names = {
        chinese = "zh", english = "en", japanese = "ja", korean = "ko",
        french = "fr", german = "de", spanish = "es", portuguese = "pt",
        russian = "ru", italian = "it", thai = "th", vietnamese = "vi",
    }
    for name, code in pairs(names) do
        if string.find(l, name, 1, true) then return code end
    end
    local code = string.match(l, "^([a-z]+)")
    if code == "jp" then return "ja" end
    if code == "kr" then return "ko" end
    local known = { zh = true, zht = true, en = true, ja = true, ko = true, fr = true,
                    de = true, es = true, pt = true, ru = true, it = true, th = true, vi = true }
    if code and known[code] then return code end
    return nil
end

-- Ask the game itself which language it runs in. Blueprint function libraries
-- are static: FindAllOf returns their class default object.
local function libDefaultObject(cls, fnPath)
    local list = safe(function() return FindAllOf(cls) end)
    if type(list) == "table" and #list > 0 then return list[1] end
    local module = string.match(fnPath or "", "^/Script/([^%.]+)%.")
    if module then
        return safe(function() return StaticFindObject("/Script/" .. module .. ".Default__" .. cls) end)
    end
    return nil
end

local function callLibString(cls, fnPath, arg)
    local obj = libDefaultObject(cls, fnPath)
    if not obj then return nil, "no default object" end
    local fn = safe(function() return StaticFindObject(fnPath) end)
    if not fn then return nil, "no function" end
    local raw
    if arg ~= nil then
        raw = safe(function() return obj:CallFunction(fn, arg) end)
    else
        raw = safe(function() return obj:CallFunction(fn) end)
    end
    return toLuaString(raw)
end

local function languageCandidates()
    return {
        { "PBZBlueprintFunctionLibrary", "/Script/ProjectPBZ.PBZBlueprintFunctionLibrary:GetCurrentLanguage", true },
        { "ELTBlueprintLibrary", "/Script/EasyLocalizationTool.ELTBlueprintLibrary:GetCurrentLanguage", true },
        { "KismetInternationalizationLibrary", "/Script/Engine.KismetInternationalizationLibrary:GetCurrentLanguage", false },
    }
end

-- ---------------------------------------------------------------------------
-- language detection
-- The HUD has to speak the language the game is actually running in, and it has
-- to follow a change made in the options menu without a restart. The sources
-- are polled from the most authoritative to the most compatible one; a source
-- whose value we cannot recognize is skipped, so a broken probe can no longer
-- silently pin the HUD to the built-in default:
--   1. the engine's live culture (what the game's own FText uses right now)
--   2. the game's PBZSettingsLocal object (the selection saved by the game)
--   3. GameUserSettings.ini on disk (the game writes it whenever it saves)
--   4. a GetCurrentLanguage helper on one of the game's blueprint libraries
-- ---------------------------------------------------------------------------
local LANG_RECHECK_SECS = 3
local LANG_FALLBACK = "en"

local function cleanCulture(v)
    if type(v) ~= "string" then return nil end
    v = string.gsub(v, "^%s+", "")
    v = string.gsub(v, "%s+$", "")
    if v == "" or v == "None" then return nil end
    return v
end

local function cultureFromEngine()
    for _, fn in ipairs({ "GetCurrentCulture", "GetCurrentLanguage" }) do
        local raw = cleanCulture(callLibString("KismetInternationalizationLibrary",
            "/Script/Engine.KismetInternationalizationLibrary:" .. fn, nil))
        if normalizeLang(raw) then return raw, "engine:" .. fn end
    end
    return nil
end

local function cultureFromSettingsObject()
    local list = safe(function() return FindAllOf("PBZSettingsLocal") end)
    if type(list) ~= "table" then return nil end
    for _, obj in ipairs(list) do
        if isValid(obj) then
            for _, prop in ipairs({ "CultureName", "WwiseCultureName" }) do
                local v = cleanCulture(toLuaString(readProp(obj, prop)))
                if normalizeLang(v) then return v, "PBZSettingsLocal." .. prop end
            end
        end
    end
    return nil
end

local function cultureFromIni()
    if type(os.getenv) ~= "function" then return nil end
    local root = os.getenv("LOCALAPPDATA")
    if root == nil or root == "" then return nil end
    for _, dir in ipairs({ "ProjectPBZ", "PBZ", "ProjectPBZ_Win64_Shipping" }) do
        local path = root .. "\\" .. dir .. "\\Saved\\Config\\Windows\\GameUserSettings.ini"
        local f = io.open(path, "r")
        if f then
            local txt = f:read("*a") or ""
            f:close()
            -- Never match WwiseCultureName=..., which sits on the very next line.
            local v = string.match(txt, "[\r\n]CultureName=([^\r\n]+)")
            if v == nil then v = string.match(txt, "^CultureName=([^\r\n]+)") end
            v = cleanCulture(v)
            if normalizeLang(v) then return v, "GameUserSettings.ini" end
        end
    end
    return nil
end

local function cultureFromGameLibraries(game)
    for _, c in ipairs(languageCandidates()) do
        local raw = cleanCulture(callLibString(c[1], c[2], c[3] and game or nil))
        if normalizeLang(raw) then return raw, c[1] end
    end
    return nil
end

local function setLanguage(l)
    if l == nil or l == "" or l == S.lang then return end
    local prev = S.lang
    S.lang = l
    S.langChanged = true
    log("language: " .. (prev ~= "" and prev or "?") .. " -> " .. l)
end

local function detectLanguage(game)
    local t = nowSec()
    if t - S.langTs < LANG_RECHECK_SECS then return end
    S.langTs = t
    local raw, source = cultureFromEngine()
    if raw == nil then raw, source = cultureFromSettingsObject() end
    if raw == nil then raw, source = cultureFromIni() end
    if raw == nil and game ~= nil then raw, source = cultureFromGameLibraries(game) end
    local l = normalizeLang(raw)
    if l ~= nil then
        if not S.langVerified then
            S.langVerified = true
            log("language = " .. l .. " (culture " .. tostring(raw) .. " via " .. tostring(source) .. ")")
        end
        setLanguage(l)
        return
    end
    if S.lang ~= "" then return end
    -- Nothing usable: keep the HUD readable instead of silently staying on
    -- Chinese, and say so once in the log.
    if not S.langProbeLogged then
        S.langProbeLogged = true
        log("language: no culture found (engine/settings/ini), falling back to " .. LANG_FALLBACK)
    end
    setLanguage(LANG_FALLBACK)
end

-- Player facing boss name: the localized HP bar text when the game gave us one,
-- otherwise a readable name derived from the boss class name. The bar text is
-- already localized by the game itself, so it wins over our fallback tables.
local function bossNameEn(key, current)
    if current ~= nil and current ~= "" then return current end
    if BOSS_NAMES_EN[key] then return BOSS_NAMES_EN[key] end
    local s = string.gsub(key or "", "^BP_Monster_", "")
    s = string.gsub(s, "_C$", "")
    s = string.gsub(s, "_%d+$", "")
    s = string.gsub(s, "_", " ")
    if s == "" then return "Unknown" end
    return s
end

local function bossNameZh(key, current)
    if current ~= nil and current ~= "" then return current end
    if BOSS_NAMES_ZH[key] then return BOSS_NAMES_ZH[key] end
    return bossNameEn(key, current)
end

-- Boss name for one language row set. The live HP bar text is already localized
-- by the game, but it is captured in whatever language the game was in at that
-- moment; showing it in every row set is what produced e.g. a Chinese boss name
-- under the English "Current boss" label. Use it only in the row set of the
-- language it was captured in, otherwise fall back to the tables.
local function bossNameFor(code)
    if S.bossKey == nil or S.bossKey == "" then return "—" end
    local zhLike = (code == "zh" or code == "zht")
    local name = S.bossName or ""
    if name ~= "" then
        local tag = S.bossNameLang or ""
        if tag == code then return name end
        if tag == "" and hasCJK(name) == zhLike then return name end
    end
    if zhLike then return bossNameZh(S.bossKey, "") end
    return bossNameEn(S.bossKey, "")
end
-- ---------------------------------------------------------------------------
-- historical per-boss deaths from the game's own save JSON
-- The save JSON (as built by the game for saving) contains a top level
-- "BossRecord" map:  { "<BossClass>": { "ClassPath": ..., "Records": {
--     "<cycle>_<difficulty>": { "AttemptCount": N, "KillCount": M, "BestTimeMs": T } } } }
-- Deaths to that boss = AttemptCount - KillCount.
-- ---------------------------------------------------------------------------
local function readSaveJsonString()
    if not isValid(S.saveSys) then
        local list = safe(function() return FindAllOf("PBZSaveLoadSubsystem") end)
        if type(list) == "table" and #list > 0 then
            S.saveSys = list[1]
        end
    end
    if not isValid(S.saveSys) then return nil end
    if not S.fnSaveStr then
        S.fnSaveStr = safe(function()
            return StaticFindObject("/Script/ProjectPBZ.PBZSaveLoadSubsystem:SaveJsonObjectToString")
        end)
    end
    if not S.fnSaveStr then return nil end
    local raw = safe(function() return S.saveSys:CallFunction(S.fnSaveStr) end)
    return toLuaString(raw)
end

local function parseBossRecord(json, bossKey, cycle, diff)
    if type(json) ~= "string" or bossKey == "" then return nil end
    -- restrict to the BossRecord section: the boss class name also appears inside
    -- ClassPath values and other subsystems, so a global search could hit the
    -- wrong place
    local br = string.find(json, '"BossRecord"%s*:%s*{')
    if not br then return nil end
    local sec = string.sub(json, br)
    local i = string.find(sec, '"' .. bossKey .. '"', 1, true)
    if not i then return nil end
    local seg = string.sub(sec, i, i + 4000)
    local rk = tostring(cycle or 0) .. "_" .. tostring(diff or 2)
    local rj = string.find(seg, '"' .. rk .. '"', 1, true)
    if not rj then
        -- the save may only have records for another cycle/difficulty: use the
        -- first "<n>_<n>" record found for this boss
        local recs = string.find(seg, '"Records"%s*:%s*{')
        if recs then
            local block = string.sub(seg, recs, recs + 800)
            local first = string.match(block, '(%d+_%d+)"%s*:')
            if first then
                rj = string.find(seg, '"' .. first .. '"', 1, true)
            end
        end
    end
    if not rj then return nil end
    local block = string.sub(seg, rj, rj + 400)
    local attempts = tonumber(string.match(block, '"AttemptCount"%s*:%s*(%d+)'))
    local kills = tonumber(string.match(block, '"KillCount"%s*:%s*(%d+)')) or 0
    if not attempts then return nil end
    return attempts, kills
end

local function refreshBossHistory(force)
    local key = S.bossKey
    if key == "" then
        S.histDeaths = nil
        return
    end
    local t = nowSec()
    local due = force
        or S.histKey ~= key
        or S.histDeaths == nil
        or (t - S.histTs) > 60
    if not due then return end
    S.histTs = t
    S.histKey = key
    local json = readSaveJsonString()
    if type(json) ~= "string" or #json < 200 then
        log("boss history: save JSON unavailable (len=" .. tostring(json and #json or -1) .. ")")
        return
    end
    local attempts, kills = parseBossRecord(json, key, S.cycleCount, S.diffByte)
    if attempts then
        S.histAttempts = attempts
        S.histKills = kills
        S.histDeaths = math.max(0, attempts - kills)
        log(string.format("boss history: %s attempts=%d kills=%d deaths=%d",
            key, attempts, kills, S.histDeaths))
    else
        S.histAttempts = nil
        S.histKills = nil
        S.histDeaths = nil
        log("boss history: no BossRecord for " .. key)
    end
end

local function bossKeyOf(actor)
    if not actor then return "" end
    local ok, classObj = pcall(function() return actor:GetClass() end)
    if not (ok and classObj) then return "" end
    local key = ""
    local ok2, fname = pcall(function() return classObj:GetFName() end)
    if ok2 and fname then
        local ok3, s = pcall(function() return fname:ToString() end)
        if ok3 and type(s) == "string" then key = s end
    end
    if key == "" then
        local ok4, full = pcall(function() return classObj:GetFullName() end)
        if ok4 and type(full) == "string" then
            key = string.match(full, "([^%.%:]+)$") or full
        end
    end
    key = string.gsub(key, "_C$", "")
    return key
end

local function bossNameOf(actor)
    if not actor then return "" end
    local cands = { "AIAvatarName", "PlayerName", "DisplayName", "CharacterName" }
    for _, prop in ipairs(cands) do
        local v = readProp(actor, prop)
        if v ~= nil then
            if type(v) == "string" then return v end
            local ok, s = pcall(function() return v:ToString() end)
            if ok and type(s) == "string" and s ~= "" and s ~= "None" then
                return s
            end
        end
    end
    return ""
end

local function textOfWidget(w)
    if not w then return "" end
    local props = { "Text", "LocText", "TextContent", "LabelText", "BossName" }
    for _, p in ipairs(props) do
        local v = readProp(w, p)
        if v ~= nil and type(v) ~= "number" then
            local ok, s = pcall(function() return v:ToString() end)
            if ok and type(s) == "string" and s ~= "" and s ~= "None" then
                return s
            end
            if type(v) == "string" and v ~= "" then return v end
        end
    end
    return ""
end

-- Convert an FText (userdata) into a plain Lua string. FText is not an FString,
-- so :ToString() usually fails; fall back to the engine's own conversion node.
local function ftextToString(v)
    if v == nil then return "" end
    if type(v) == "string" then return v end
    local ok, s = pcall(function() return v:ToString() end)
    if ok and type(s) == "string" and s ~= "" and s ~= "None"
        and not string.find(s, "FText:", 1, true) then
        return s
    end
    local fn = safe(function()
        return StaticFindObject("/Script/Engine.KismetTextLibrary:Conv_TextToString")
    end)
    local lib = libDefaultObject("KismetTextLibrary",
        "/Script/Engine.KismetTextLibrary:Conv_TextToString")
    if fn and lib then
        local raw = safe(function() return lib:CallFunction(fn, v) end)
        local out = toLuaString(raw)
        if out ~= nil and out ~= "" and out ~= "None" then return out end
    end
    local t = tostring(v)
    if type(t) == "string" and t ~= "" and not string.find(t, "^FText: ") then
        return t
    end
    return ""
end

-- Boss display name straight from the HP bar's name label. The game localizes
-- this text itself, so it is right for both Chinese and English clients.
local function bossBarName(bar)
    if not bar then return "" end
    local w = readProp(bar, "BossName")
    if w ~= nil and isValid(w) then
        local ok, txt = pcall(function() return w:GetText() end)
        if ok and txt ~= nil then
            local s = ftextToString(txt)
            if s ~= "" then return s end
        end
        local propTxt = readProp(w, "Text")
        if propTxt ~= nil then
            local s = ftextToString(propTxt)
            if s ~= "" then return s end
        end
        local s = textOfWidget(w)
        if s ~= "" then return s end
    end
    return ""
end

local function bossFromBar(bar)
    if not bar then return nil end
    local actor = readProp(bar, "Character")
    if actor == nil then
        -- some builds expose the bound character under another name
        for _, p in ipairs({ "BossCharacter", "BossActor", "TargetCharacter" }) do
            actor = readProp(bar, p)
            if actor ~= nil then break end
        end
    end
    if actor ~= nil and not isValid(actor) then actor = nil end
    return actor
end

-- forward declaration: the death hook defined below needs this
local applyDeaths

local function refreshBoss()
    local t = nowSec()
    -- Boss fight start/end are signalled by RegisterBossHPBar / UnRegisterBossHPBar
    -- hooks, so no per-tick object scan is needed. The scan below is a cheap
    -- fallback used only when hook registration was unavailable.
    if not S.hookBarOk then
        if t - S.lastWidgetScan < 5 then
            return S.bossActive
        end
        S.lastWidgetScan = t
        local widgets = safe(function() return FindAllOf("WB_BossHPBar_C") end)
        S.barsWidgets = 0
        if type(widgets) == "table" then
            for _, w in ipairs(widgets) do
                if isValid(w) then
                    S.barsWidgets = S.barsWidgets + 1
                    local actor = bossFromBar(w)
                    if actor then
                        local key = bossKeyOf(actor)
                        local name = bossNameOf(actor)
                        local label = bossBarName(w)
                        if label ~= "" then name = label end
                        if key ~= "" then
                            if key ~= S.bossKey then
                                S.histDirty = true
                                S.bossKey = key
                                S.bossName = ""
                                S.bossNameLang = ""
                            end
                            setBossName(name)
                            saveLastBoss(S.bossKey, S.bossNameLang, S.bossName)
                        end
                    end
                    S.lastBarTs = t
                    S.bossActive = true
                    return true
                end
            end
        end
        return S.bossActive
    end
    if S.hookBarOk then
        -- fight start/end are both signalled by hooks (Register / UnRegister), so
        -- steady-state polling performs no object scans at all.
        return S.bossActive
    end
end

local function firstUObjectArg(...)
    local n = select("#", ...)
    for i = 1, n do
        local p = select(i, ...)
        local raw = p
        if type(p) == "userdata" then
            local ok, v = pcall(function() return p:get() end)
            if ok then raw = v end
        end
        if raw ~= nil and type(raw) == "userdata" then
            local ok2, cls = pcall(function() return raw:GetClass() end)
            if ok2 and cls ~= nil then return raw end
        end
    end
    return nil
end

local function argUObject(v)
    if v == nil then return nil end
    local raw = v
    if type(v) == "userdata" then
        local ok, got = pcall(function() return v:get() end)
        if ok and got ~= nil then raw = got end
    end
    if raw ~= nil and type(raw) == "userdata" then
        local ok2, cls = pcall(function() return raw:GetClass() end)
        if ok2 and cls ~= nil then return raw end
    end
    return nil
end

local function installHooks()
    if not RegisterHook then
        log("RegisterHook unavailable")
        return
    end

    S.hookBarOk = pcall(function()
        RegisterHook("/Script/ProjectPBZ.PBZHUDLayout:RegisterBossHPBar", function(...)
            -- UE4SS passes the hook context (the HUD layout object) as the first
            -- argument, followed by the real function parameters. The boss HP bar
            -- widget and/or boss actor is among the later arguments, so pick them
            -- out by class name instead of taking the first UObject blindly.
            local n = select("#", ...)
            local bar, actor
            for i = 1, n do
                local obj = argUObject(select(i, ...))
                if obj then
                    local cls = bossKeyOf(obj)
                    local lc = string.lower(cls)
                    if string.find(lc, "bosshpbar", 1, true) then
                        bar = obj
                    elseif cls ~= "" and not string.find(lc, "hudlayout", 1, true)
                        and not string.find(lc, "layout", 1, true) then
                        if not actor then actor = obj end
                    end
                end
            end
            if bar then
                local a2 = bossFromBar(bar)
                if a2 then actor = a2 end
            end
            S.lastBarTs = nowSec()
            S.bossActive = true
            if bar then S.pendingBar = bar end
            S.needBar = true
            if actor and isValid(actor) then
                local key = bossKeyOf(actor)
                local name = bossNameOf(actor)
                if bar then
                    if S.bossName ~= "" and name == "" then name = S.bossName end
                end
                if key ~= "" then
                    setBossIdentity(key, name)
                    log("boss fight start: key=" .. key .. " name=" .. tostring(S.bossName))
                end
            else
                log("boss fight start: (no actor argument found)")
            end
        end)
    end) and true or false
    log("hook RegisterBossHPBar: " .. tostring(S.hookBarOk))

    -- AddDiedTime fires on player death; attribute the death immediately instead
    -- of waiting for the next poll tick (the poll also catches any missed event).
    S.hookDiedOk = pcall(function()
        RegisterHook("/Script/ProjectPBZ.PBZGameSystem:AddDiedTime", function(...)
            log("hook AddDiedTime fired")
            S.histDirty = true
            local game = S.game
            if game and isValid(game) then
                local deaths = asNumber(readProp(game, "DiedTimes"))
                if deaths ~= nil and applyDeaths then applyDeaths(deaths) end
            end
        end)
    end) and true or false
    log("hook AddDiedTime: " .. tostring(S.hookDiedOk))

    S.hookBarEndOk = pcall(function()
        RegisterHook("/Script/ProjectPBZ.PBZHUDLayout:UnRegisterBossHPBar", function(...)
            if S.bossActive then log("boss fight ended (hook)") end
            S.bossActive = false
            S.histDirty = true
            -- keep S.bossKey and refresh the timestamp: when the player dies the
            -- bar is unregistered a moment before AddDiedTime fires, so the death
            -- must still be attributed to the boss that was just being fought.
            S.lastBarTs = nowSec()
        end)
    end) and true or false
    log("hook UnRegisterBossHPBar: " .. tostring(S.hookBarEndOk))
end

-- ---------------------------------------------------------------------------
-- stats.json writer
-- ---------------------------------------------------------------------------
local function jsonNum(v)
    if v == nil then return "null" end
    v = tonumber(v)
    if v == nil then return "null" end
    if v == math.floor(v) then return string.format("%d", v) end
    return string.format("%.3f", v)
end

local function jsonStr(v)
    if v == nil then return '""' end
    v = tostring(v)
    v = string.gsub(v, "\\", "\\\\")
    v = string.gsub(v, '"', '\\"')
    v = string.gsub(v, "\n", " ")
    v = string.gsub(v, "\r", " ")
    return '"' .. v .. '"'
end

local function currentBossDeaths()
    if S.histDeaths ~= nil then
        -- AttemptCount is bumped when the fight starts, KillCount only on a kill.
        -- While the current fight is still unresolved the difference is one higher
        -- than the true death count, so show deaths only for finished attempts.
        if S.bossActive and S.histDeaths > 0 then
            return S.histDeaths - 1
        end
        return S.histDeaths
    end
    if S.bossKey ~= "" then
        return bossCounts[S.bossKey] or 0
    end
    return 0
end

local function modBossDeaths()
    if S.bossKey ~= "" then
        return bossCounts[S.bossKey] or 0
    end
    return 0
end

local function cleanPipe(v)
    v = tostring(v or "")
    v = string.gsub(v, "|", "/")
    v = string.gsub(v, "[\r\n]+", " ")
    return v
end

-- stats.txt: the line protocol PBZStatsHUD.exe parses. Every language set is
-- always written; the HUD picks the set that matches the running game's
-- language (the lang= line), so switching language in the game menu switches the
-- overlay without a restart.
local function writeStatsTxt()
    local total = S.displayTotal or S.total or 0
    local bossDeaths = S.bossDeaths or 0
    local cyc = (S.cycleCount or 0) + 1
    local lang = S.lang
    if lang == nil or lang == "" then lang = LANG_FALLBACK end
    local f = io.open(STATS_TXT, "w")
    if not f then
        log("ERROR: cannot write " .. STATS_TXT)
        return
    end
    f:write("version=" .. MOD_VERSION .. "\n")
    f:write("lang=" .. tostring(lang) .. "\n")
    for _, code in ipairs(LANG_ORDER) do
        local t = L10N[code]
        if t and CYCLE_FMT[code] then
            local lines = {
                "row_" .. code .. "|" .. t.cycle .. "|" .. cleanPipe(CYCLE_FMT[code](cyc)),
                "row_" .. code .. "|" .. t.diff .. "|" .. cleanPipe(diffText(code, S.diffByte, S.diffName)),
                "row_" .. code .. "|" .. t.total .. "|" .. cleanPipe(total),
                "row_" .. code .. "|" .. t.boss .. "|" .. cleanPipe(bossNameFor(code)),
                "row_" .. code .. "|" .. t.bossdeaths .. "|" .. cleanPipe(bossDeaths),
            }
            for _, line in ipairs(lines) do
                f:write(line .. "\n")
            end
        end
    end
    f:close()
end

local function writeStats(force)
    local t = nowSec()
    if not force and (t - S.lastStatsWrite) < STATS_MIN_INTERVAL then
        return
    end
    S.lastStatsWrite = t
    S.bossDeaths = currentBossDeaths()
    local lang = S.lang
    if lang == nil or lang == "" then lang = LANG_FALLBACK end
    local f = io.open(STATS_PATH, "w")
    if not f then
        log("ERROR: cannot write " .. STATS_PATH)
        return
    end
    f:write("{\n")
    f:write("  \"mod_version\": " .. jsonStr(MOD_VERSION) .. ",\n")
    f:write("  \"ts\": " .. t .. ",\n")
    f:write("  \"total_deaths\": " .. jsonNum(S.total) .. ",\n")
    f:write("  \"boss_deaths\": " .. jsonNum(S.bossDeaths) .. ",\n")
    f:write("  \"boss_deaths_mod\": " .. jsonNum(modBossDeaths()) .. ",\n")
    f:write("  \"boss_deaths_source\": " .. jsonStr(S.histDeaths ~= nil and "save" or "mod") .. ",\n")
    f:write("  \"boss_attempts\": " .. jsonNum(S.histAttempts) .. ",\n")
    f:write("  \"boss_kills\": " .. jsonNum(S.histKills) .. ",\n")
    f:write("  \"boss_key\": " .. jsonStr(S.bossKey) .. ",\n")
    f:write("  \"boss_name\": " .. jsonStr(S.bossName) .. ",\n")
    f:write("  \"boss_active\": " .. (S.bossActive and "true" or "false") .. ",\n")
    f:write("  \"difficulty\": " .. jsonStr(S.diffName) .. ",\n")
    f:write("  \"difficulty_byte\": " .. jsonNum(S.diffByte) .. ",\n")
    f:write("  \"level\": " .. jsonStr(S.level) .. ",\n")
    f:write("  \"cycle\": " .. jsonNum(S.cycleCount) .. ",\n")
    f:write("  \"cycle_display\": " .. jsonNum((S.cycleCount or 0) + 1) .. ",\n")
    f:write("  \"lang\": " .. jsonStr(lang) .. ",\n")
    f:write("  \"boss_name_lang\": " .. jsonStr(S.bossNameLang) .. ",\n")
    f:write("  \"boss_name_en\": " .. jsonStr(bossNameFor("en")) .. ",\n")
    f:write("  \"death_events\": " .. jsonNum(S.deathEvents) .. "\n")
    f:write("}\n")
    f:close()
    writeStatsTxt()
end

-- ---------------------------------------------------------------------------
-- main tick
-- ---------------------------------------------------------------------------
local tick  -- forward declaration

local function handleCommand(content)
    log("cmd: " .. content)
    if content == "stats" then
        writeStats(true)
        log("stats forced: total=" .. tostring(S.total) ..
            " diff=" .. tostring(S.diffName) ..
            " boss=" .. tostring(S.bossKey) ..
            " bossDeaths=" .. tostring(currentBossDeaths()))
    elseif content == "bars" then
        local v = refreshBoss()
        log("bars present=" .. tostring(v) .. " widgets=" .. tostring(S.barsWidgets) ..
            " boss=" .. S.bossKey .. " name=" .. S.bossName ..
            " active=" .. tostring(S.bossActive) ..
            " hooks[bar=" .. tostring(S.hookBarOk) .. ",died=" .. tostring(S.hookDiedOk) .. "]")
    elseif content == "savestr" then
        local json = readSaveJsonString()
        if type(json) == "string" and #json > 0 then
            local f = io.open(OUT .. "savejson_str.txt", "w")
            if f then
                f:write(json)
                f:close()
            end
            log("savestr: OK len=" .. #json .. " (E:\\PBZModOut\\savejson_str.txt)")
        else
            log("savestr: no JSON (len=" .. tostring(json and #json or -1) .. ")")
        end
    elseif content == "refresh" then
        refreshBossHistory(true)
        writeStats(true)
        log("refresh: boss=" .. tostring(S.bossKey) ..
            " hist=" .. tostring(S.histDeaths) ..
            " deaths=" .. tostring(currentBossDeaths()))
    elseif content == "langprobe" then
        local er, esrc = cultureFromEngine()
        local sr, ssrc = cultureFromSettingsObject()
        local ir, isrc = cultureFromIni()
        log("langprobe: engine=" .. tostring(er) .. " (" .. tostring(esrc) .. ")" ..
            " settings=" .. tostring(sr) .. " (" .. tostring(ssrc) .. ")" ..
            " ini=" .. tostring(ir) .. " (" .. tostring(isrc) .. ")" ..
            " -> lang=" .. tostring(S.lang))
        for _, c in ipairs(languageCandidates()) do
            local raw, err = callLibString(c[1], c[2], c[3] and S.game or nil)
            log("langprobe: " .. c[1] .. " => " .. tostring(raw) .. " (" .. tostring(err) .. ")")
        end
    elseif content == "langdetect" then
        S.langTs = 0
        detectLanguage(S.game)
        writeStats(true)
        log("langdetect: lang=" .. tostring(S.lang) .. " verified=" .. tostring(S.langVerified))
    elseif content == "quit" then
        S.stopped = true
        writeStats(true)
        log("stopped by command")
        return false
    end
    return true
end

local function pollCommand()
    local cf = io.open(CMD_PATH, "r")
    if not cf then return true end
    local content = cf:read("*a") or ""
    cf:close()
    content = string.gsub(content, "^\239\187\191", "")  -- strip a UTF-8 BOM if the editor added one
    content = string.gsub(content, "^%s+", "")
    content = string.gsub(content, "%s+$", "")
    if content ~= "" and content ~= S.lastCmd then
        S.lastCmd = content
        return handleCommand(content)
    end
    return true
end

-- Apply a fresh DiedTimes sample. Shared by the 1 Hz poll and by the AddDiedTime
-- hook so a death is attributed immediately (and never counted twice: S.total is
-- moved forward by whoever sees the new value first).
applyDeaths = function(deaths)
    if deaths == nil then return end
    -- Title/menu worlds are not a loaded save: skip their placeholder values.
    if S.menuWorld then return end
    if not S.baseReady then
        S.total = deaths
        S.baseReady = true
        S.displayTotal = deaths
        saveLastTotal(deaths)
        log("baseline total deaths = " .. tostring(deaths))
        return
    end
    if deaths > S.total then
        local delta = deaths - S.total
        S.deathEvents = S.deathEvents + delta
        if S.bossKey ~= "" and (S.bossActive or (nowSec() - S.lastBarTs) <= BAR_RECENT_SECS) then
            bossCounts[S.bossKey] = (bossCounts[S.bossKey] or 0) + delta
            bossCountsDirty = true
            saveBossCounts()
            log(string.format("boss death attrib: %s +%d -> %d",
                S.bossKey, delta, bossCounts[S.bossKey]))
        else
            log(string.format("death (no boss) +%d", delta))
        end
    end
    S.total = deaths
end

local function readGameValues(game)
    local deaths = asNumber(readProp(game, "DiedTimes"))
    applyDeaths(deaths)

    -- Difficulty: only accept a sane Difficulty byte (1..4). During the logo /
    -- title screen the property can be absent or 0 (Handicapped sentinel), so we
    -- keep whatever we already have instead of blanking it out.
    local db = asNumber(readProp(game, "DifficultModeByte"))
    if db ~= nil and db >= 1 and db <= 4 then
        if S.diffByte ~= db then
            log("difficulty byte = " .. tostring(db) .. " (" .. tostring(DIFF_NAMES[db]) .. ")")
        end
        S.diffByte = db
        S.diffName = DIFF_NAMES[db] or ("未知(" .. db .. ")")
    elseif S.diffByte == nil then
        S.diffByte = 2
        S.diffName = "破局者"
    end

    local lvl = readLevel(game)
    if lvl ~= "" and lvl ~= S.level then
        if S.level ~= "" then
            -- different scene: the boss bar is gone, but keep the last boss identity
            -- so the HUD still shows the death count of the boss we last fought.
            S.bossActive = false
            log("level changed -> " .. lvl)
        end
        S.level = lvl
    end

    local cyc = asNumber(readProp(game, "CycleCount"))
    if cyc ~= nil and cyc ~= S.cycleCount then
        log("cycle changed -> " .. tostring(cyc) .. " (display 第 " .. tostring(cyc + 1) .. " 周目)")
        S.cycleCount = cyc
        S.histDirty = true
    end
end


local function tickBody()
    if S.stopped then return end

    if not pollCommand() then return end

    local game = findGame()
    -- Runs with or without a game object: the ini / engine culture sources work on
    -- the title screen too, where the language is actually changed.
    safe(detectLanguage, game)
    if game then
        safe(readGameValues, game)
        local present = refreshBoss()
        if not present then
            S.bossActive = false
        end
        -- Resolve the localized boss name outside the hook callback (calling
        -- engine UFUNCTIONs inside a hook can stall the game thread).
        -- Resolve the localized boss name outside the hook callback (calling
        -- engine UFUNCTIONs inside a hook can stall the game thread).
        if S.needBar then
            S.needBar = false
            local list = safe(function() return FindAllOf("WB_BossHPBar_C") end)
            if type(list) == "table" then
                for _, w in ipairs(list) do
                    if isValid(w) then
                        local nm = bossBarName(w)
                        if nm ~= "" then
                            if nm ~= S.bossName then
                                setBossName(nm)
                                log("boss name -> " .. nm .. " (" .. tostring(S.bossNameLang) .. ")")
                            end
                            break
                        end
                    end
                end
            end
        end
        if S.pendingBar ~= nil then
            local bar = S.pendingBar
            S.pendingBar = nil
            if isValid(bar) then
                local nm = bossBarName(bar)
                if nm ~= "" and nm ~= S.bossName then
                    setBossName(nm)
                    log("boss name -> " .. nm .. " (" .. tostring(S.bossNameLang) .. ")")
                end
            end
        end
        local forceHist = S.histDirty
        S.histDirty = false
        safe(refreshBossHistory, forceHist)
    end

    if S.langChanged then
        S.langChanged = false
        -- The language switch has to reach both HUDs immediately: stats.txt drives
        -- the exe overlay's label set, and the boss bar label has to be read again
        -- because the game redraws it in the new language.
        S.needBar = true
        writeStats(true)
    end

    if bossCountsDirty then saveBossCounts() end
    writeStats(false)
end

-- The poll body is wrapped in pcall and the next run is scheduled no matter what:
-- any unguarded line inside the body used to kill the whole poll loop (the game
-- simply stopped updating stats.txt). Errors are logged once per session.
tick = function()
    local ok, err = pcall(tickBody)
    if not ok and not S.tickErrLogged then
        S.tickErrLogged = true
        log("tick error: " .. tostring(err))
    end
    if S.stopped then return end
    safe(function() return ExecuteInGameThreadWithDelay(POLL_MS, tick) end, nil)
end

-- The HUD is launched by the game itself (no autostart entry, no watcher).
-- Some antivirus products delete unsigned exe files right after they start, so
-- a compressed-looking backup copy is kept next to it and restored when needed.
-- The HUD exe and its backup sit next to the data folder (the folder that holds
-- stats.txt); data stays inside OUT so players can delete it separately.
local HUD_DIR = string.gsub(OUT, "[^\\/]*[\\/]$", "")
local HUD_EXE = HUD_DIR .. "PBZStatsHUD.exe"
local HUD_BAK = HUD_DIR .. "hudbox.dat"
local hudStarted = false

local function blobCopy(src, dst)
    local fi = io.open(src, "rb")
    if not fi then return false end
    local data = fi:read("*a")
    fi:close()
    if not data then return false end
    local fo = io.open(dst, "wb")
    if not fo then return false end
    fo:write(data)
    fo:close()
    return true
end

local function ensureHudExe()
    local f = io.open(HUD_EXE, "rb")
    if f then f:close() return true end
    if blobCopy(HUD_BAK, HUD_EXE) then
        log("HUD: restored exe from backup copy")
        return true
    end
    return false
end

local function startHud()
    if hudStarted then return end
    hudStarted = true
    if not ensureHudExe() then
        log("HUD: exe not found at " .. HUD_EXE)
        return
    end
    local ok = pcall(os.execute, 'start "" "' .. HUD_EXE .. '"')
    log("HUD: start requested ok=" .. tostring(ok))
end

-- ---------------------------------------------------------------------------
-- HUD backend. The visible overlay is a separate process: the PowerShell host
-- (default, no exe on disk) or the optional compiled exe. Lua only writes
-- stats.txt - the overlay watches that file.
-- hud_mode in PBZStatsHUD.ini: ps (default) | exe | both | none
-- ---------------------------------------------------------------------------
local HUDCFG = { mode = "ps" }
local HUD_PS = HUD_DIR .. "run.ps1"
local HUD_CS = HUD_DIR .. "PBZStatsHUD.cs"
local psStarted = false

local function fileExists(p)
    local f = io.open(p, "rb")
    if f then f:close() return true end
    return false
end

local function readHudConfig()
    HUDCFG.mode = "ps"
    local f = io.open(HUD_DIR .. "PBZStatsHUD.ini", "rb")
    if not f then return end
    for line in f:lines() do
        local m = line:match("^%s*hud_mode%s*=%s*([%w_%-]+)")
        if m then HUDCFG.mode = string.lower(m) end
    end
    f:close()
    if HUDCFG.mode ~= "ps" and HUDCFG.mode ~= "exe" and HUDCFG.mode ~= "both"
       and HUDCFG.mode ~= "none" and HUDCFG.mode ~= "umg" then
        HUDCFG.mode = "ps"
    end
    -- "umg" was the old in-engine mode; the in-engine renderer is gone.
    if HUDCFG.mode == "umg" then HUDCFG.mode = "ps" end
end

local function startPsHud()
    if psStarted then return end
    psStarted = true
    if not fileExists(HUD_PS) or not fileExists(HUD_CS) then
        log("HUD: powershell host not installed (" .. tostring(HUD_PS) .. ")")
        return
    end
    local cmd = 'start "" powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'
        .. HUD_PS .. '"'
    local ok = pcall(os.execute, cmd)
    log("HUD: powershell host start requested ok=" .. tostring(ok))
end

-- ---------------------------------------------------------------------------
local function boot()
    log("========== PBZStats boot v" .. MOD_VERSION .. " (lua 8.0) ==========")
    loadBossCounts()
    local keys = {}
    for k in pairs(bossCounts) do keys[#keys + 1] = k end
    table.sort(keys)
    log("loaded boss counters: " .. #keys .. " (" .. table.concat(keys, ", ") .. ")")

    -- Seed the HUD with the last known grand total so the title screen shows the
    -- real cumulative number instead of the menu world's placeholder 0.
    local lastTotal = loadLastTotal()
    if lastTotal ~= nil then
        S.displayTotal = lastTotal
        S.total = lastTotal
        log("seeded total deaths = " .. tostring(lastTotal) .. " (from last session)")
    end

    local lastKey, lastName, lastLang = loadLastBoss()
    if lastKey ~= nil and lastKey ~= "" then
        S.bossKey = lastKey
        S.bossName = lastName or ""
        S.bossNameLang = lastLang or ""
        S.histDirty = true
        log("restored last boss: " .. lastKey .. " (" .. tostring(S.bossName) ..
            " [" .. tostring(S.bossNameLang) .. "])")
    end

    if EngineTickAvailable == false then
        log("WARNING: EngineTickAvailable == false, delays may not run")
    end
    installHooks()
    -- Resolve the language before the first stats write, so the HUD never starts
    -- out in the wrong language and has to be corrected a second later.
    safe(detectLanguage, S.game)
    writeStats(true)
    safe(readHudConfig)

    if HUDCFG.mode == "ps" or HUDCFG.mode == "both" then safe(startPsHud) end

    if HUDCFG.mode == "exe" or HUDCFG.mode == "both" then safe(startHud) end

    if HUDCFG.mode == "none" then log("HUD: disabled by hud_mode=none") end
    safe(function() return ExecuteInGameThreadWithDelay(200, tick) end, nil)
    log("polling started, interval " .. tostring(POLL_MS) .. " ms")
end

safe(function() return ExecuteInGameThreadWithDelay(500, boot) end, nil)
log("PBZStats main.lua loaded")
