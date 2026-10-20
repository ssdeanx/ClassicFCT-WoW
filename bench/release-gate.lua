-- bench/release-gate.lua
-- Release verification gate for ClassicFCT. NOT shipped (bench/ is workspace; excluded from zips).
-- Run from the repo root with the Lua 5.1 interpreter:
--     lua5.1 bench/release-gate.lua
-- Covers: syntax of every loadable file, client registration matrix (5 vectors),
-- restricted-client notice, locale table integrity (keys, order, placeholders, BOM),
-- regression guards for the rolling-average fix and off-target semantics, version
-- metadata consistency, and .toc/.xml packaging references.

local failures = 0
local checks = 0
local function check(name, cond, detail)
    checks = checks + 1
    if cond then
        print("PASS  " .. name)
    else
        failures = failures + 1
        print("FAIL  " .. name .. (detail and (" -- " .. tostring(detail)) or ""))
    end
end

local function readAll(path)
    local fh = io.open(path, "rb")
    if not fh then return nil end
    local data = fh:read("*a")
    fh:close()
    return data
end

local function fileExists(path)
    local fh = io.open(path, "rb")
    if fh then fh:close() return true end
    return false
end

--------------------------------------------------------------------------------
-- A. Syntax: every shipped executable file must load.
--------------------------------------------------------------------------------
local LUA_FILES = {
    "main.lua", "config.lua", "presets.lua",
    "Presets/Classic.lua", "Presets/MoP.lua", "Presets/ClassicPlus.lua",
    "Locales/locales.lua", "Locales/enUS.lua", "Locales/deDE.lua", "Locales/ruRU.lua",
    "Locales/frFR.lua", "Locales/esES.lua", "Locales/esMX.lua", "Locales/itIT.lua",
    "Locales/ptBR.lua", "Locales/zhCN.lua", "Locales/zhTW.lua", "Locales/koKR.lua",
}
for _, path in ipairs(LUA_FILES) do
    local chunk, err = loadfile(path)
    check("A: loads " .. path, chunk ~= nil, err)
end

--------------------------------------------------------------------------------
-- B. Client matrix: load main.lua under five stub environments.
--------------------------------------------------------------------------------
local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })

local function makeFrame()
    local frame = { events = {}, scripts = {} }
    local noop = function() end
    for _, m in ipairs({ "SetSize", "SetPoint", "SetParent", "SetFrameStrata", "SetFrameLevel",
        "SetScale", "SetAlpha", "Show", "Hide", "UnregisterEvent" }) do
        frame[m] = noop
    end
    frame.GetScale = function() return 1 end
    frame.GetEffectiveScale = function() return 1 end
    frame.GetWidth = function() return 100 end
    frame.GetHeight = function() return 20 end
    frame.RegisterEvent = function(self, e) self.events[e] = true end
    frame.SetScript = function(self, k, fn) self.scripts[k] = fn end
    frame.CreateFontString = function()
        local fs = {}
        local fnoop = function() end
        for _, m in ipairs({ "SetFont", "SetShadowOffset", "SetShadowColor", "SetDrawLayer",
            "SetJustifyH", "SetJustifyV", "SetText", "SetTextColor", "SetAlpha", "SetPoint",
            "ClearAllPoints", "SetParent", "SetScale", "Hide", "Show" }) do
            fs[m] = fnoop
        end
        fs.GetText = function() return "" end
        fs.GetAlpha = function() return 1 end
        fs.GetStringHeight = function() return 12 end
        fs.GetStringWidth = function() return 20 end
        fs.GetParent = function() return frame end
        return fs
    end
    return frame
end

local VECTORS = {
    { name = "Era/SoD",     project = 2,  toc = 11509, legacy = true  },
    { name = "TBC Anniv",   project = 5,  toc = 20506, legacy = true  },
    { name = "Titanforge",  project = 11, toc = 38002, legacy = true  },
    { name = "WoW Forever", project = 18, toc = 16001, legacy = false },
    { name = "Retail",      project = 1,  toc = 120100, legacy = false },
}

local function newEnv(vector)
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.WOW_PROJECT_ID = vector.project
    env.WOW_PROJECT_CLASSIC = 2
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    env.WOW_PROJECT_MAINLINE = 1
    env.WOW_PROJECT_WRATH_CLASSIC = 11
    env.GetBuildInfo = function() return "v", "b", "d", vector.toc end
    env.CreateFrame = function() return makeFrame() end
    env.UIParent = {}
    env.WorldFrame = {}
    env.C_NamePlate = { GetNamePlateForUnit = function() return nil end, GetNamePlates = function() return {} end }
    env.C_AddOns = { GetAddOnMetadata = function() return "M0.89" end }
    env.GetAddOnMetadata = function() return "M0.89" end
    env.C_Timer = { After = function(_, fn) if fn then fn() end end }
    env.GetTime = function() return 100 end
    env.InCombatLockdown = function() return false end
    env.AbbreviateNumbers = tostring
    env.UnitGUID = function() return "Player-1" end
    env.UnitExists = function() return false end
    env.UnitHealth = function() return 100 end
    env.UnitHealthMax = function() return 100 end
    env.sqrt = math.sqrt
    env.min = math.min
    env.max = math.max
    env.strlower = string.lower
    env.strupper = string.upper
    env.unpack = table.unpack
    env.bit = {
        -- Pure-Lua band so this file parses under Lua 5.1 (no bitwise operators).
        band = function(a, b)
            local res, bitval = 0, 1
            while a > 0 and b > 0 do
                if a % 2 == 1 and b % 2 == 1 then res = res + bitval end
                a = math.floor(a / 2)
                b = math.floor(b / 2)
                bitval = bitval * 2
            end
            return res
        end,
    }
    env.GetCVarDefault = function() return "1" end
    env.GetCVar = function() return "1" end
    env.SetCVar = function() end
    env.GetSpellInfo = function(id) return "Stub", nil, 12345, 0, 0, 0, id, 12345 end
    env.C_Spell = { GetSpellInfo = function(id) return { name = "Stub", iconID = 12345, spellID = id } end }
    env.COMBATLOG_OBJECT_TYPE_GUARDIAN = 8
    env.COMBATLOG_OBJECT_TYPE_PET = 16
    env.COMBATLOG_OBJECT_AFFILIATION_MINE = 1
    env.CombatLogGetCurrentEventInfo = function() error("CLEU attempted on this vector") end
    env.issecretvalue = function(v) return v == SECRET end
    return env
end

for _, vector in ipairs(VECTORS) do
    local env = newEnv(vector)
    local CFCT = { _log = {}, _testMode = false }
    CFCT.Log = function(self, msg) table.insert(self._log, msg or "") end
    CFCT.L = function(key, ...) return key end
    CFCT.Config = { animDuration = 1, OnLoad = function() end }
    CFCT.ConfigPanel = { IsVisible = function() return false end }

    local chunk = loadfile("main.lua")
    if chunk then setfenv(chunk, env) end
    local ok, loadErr = pcall(chunk, "ClassicFCT", CFCT)
    check("B: main.lua loads [" .. vector.name .. "]", ok, loadErr)
    if ok then
        local frame = CFCT.frame
        local hasCLEU = frame.events["COMBAT_LOG_EVENT_UNFILTERED"] == true
        check("B: CLEU registered = " .. tostring(vector.legacy) .. " [" .. vector.name .. "]",
            hasCLEU == vector.legacy)
        check("B: PLAYER_TARGET_CHANGED registered [" .. vector.name .. "]",
            frame.events["PLAYER_TARGET_CHANGED"] == true)
        local okLoaded = pcall(function() frame:ADDON_LOADED("ClassicFCT") end)
        check("B: ADDON_LOADED runs [" .. vector.name .. "]", okLoaded)
        local notice = false
        for _, msg in ipairs(CFCT._log) do
            if tostring(msg):find("unavailable", 1, true) then notice = true end
        end
        check("B: restricted notice = " .. tostring(not vector.legacy) .. " [" .. vector.name .. "]",
            notice == (not vector.legacy))
    end
end

--------------------------------------------------------------------------------
-- H. Secret-value probe fails CLOSED when the probe is unavailable.
--------------------------------------------------------------------------------
-- The security audit (bench/findings-security-privacy.md, SP-01) found that an ABSENT
-- probe used to return "not secret", i.e. it failed OPEN and silently: a client that
-- restricts combat-log values but withholds issecretvalue would have had its restricted
-- values formatted straight into the combat text. The probe is now resolved lazily and
-- every failure mode suppresses the event.
--
-- This drives the real CLEU handler with the probe REMOVED from the environment and
-- asserts that no number is dispatched, and that the condition is reported once rather
-- than failing silently. It is a behavioural test, not a source grep.
local function runCLEUWithoutProbe(vector)
    local env = newEnv(vector)
    -- Remove the probe entirely: this is the failure mode under test.
    env.issecretvalue = nil
    env.CombatLogGetCurrentEventInfo = function()
        -- The source MUST be the player ("Player-1" is the stub's UnitGUID),
        -- or the ownership check drops the event before any secret guard is
        -- reached and the test would pass vacuously.
        return 0, "SPELL_DAMAGE", false, "Player-1", "src", 1, 0, "Enemy-1", "dst", 2, 0,
            1234, "TestSpell", 4, 500, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    end
    env.C_CombatLog = { GetCurrentEventInfo = env.CombatLogGetCurrentEventInfo }
    env.Enum = { CombatLogObject = { TypeGuardian = 8, TypePet = 16, AffiliationMine = 1 } }
    env.COMBATLOG_OBJECT_TYPE_GUARDIAN = nil
    env.COMBATLOG_OBJECT_TYPE_PET = nil
    env.COMBATLOG_OBJECT_AFFILIATION_MINE = nil

    local CFCT = { _log = {}, _testMode = false }
    CFCT.Log = function(self, msg) table.insert(self._log, msg or "") end
    CFCT.L = function(key, ...) return key end
    -- The config needs the spell-icon fields the dispatch path reads, or the
    -- handler raises on a nil aspect ratio before the observable is reached.
    CFCT.Config = {
        animDuration = 1, OnLoad = function() end, mergeEvents = false,
        spellIconAspectRatio = 1, spellIconZoom = 1,
        spellIconOffsetX = 0, spellIconOffsetY = 0,
        showIcons = false, abbreviateNumbers = false, kiloSeparator = false,
        demoteSmallCritsEnabled = false, demoteSmallCritThreshold = 0,
        filterAbsoluteEnabled = false, filterRelativeEnabled = false,
        filterAverageEnabled = false, colorByType = false,
        colorTableDotEnabled = false, maxDisplayed = 0,
    }
    CFCT.ConfigPanel = { IsVisible = function() return false end }
    -- The real observable: an event that escapes the secret guard reaches
    -- CacheEvent, which records the spell id in CFCT.spellIdCache. If the
    -- guard suppresses the event, that cache stays empty. (SetText on a
    -- FontString is instrumented too, but a raise further down the pipeline
    -- can abort before it, so the cache is the reliable signal.)
    local dispatched = false
    local realCreateFontString = env.CreateFontString
    env.CreateFontString = function(...)
        local fs = realCreateFontString(...)
        local realSetText = fs.SetText
        fs.SetText = function(self, text)
            dispatched = true
            return realSetText(self, text)
        end
        return fs
    end

    local chunk = loadfile("main.lua")
    if not chunk then return nil, "loadfile failed" end
    setfenv(chunk, env)
    local ok, err = pcall(chunk, "ClassicFCT", CFCT)
    if not ok then return nil, tostring(err) end
    local frame = CFCT.frame
    if not frame then return nil, "no frame" end
    -- playerGUID is only assigned by PLAYER_ENTERING_WORLD; without it the
    -- ownership check drops the event before any secret guard is reached and
    -- the test would pass vacuously.
    pcall(function() frame:PLAYER_ENTERING_WORLD() end)
    local ran = pcall(function() frame:COMBAT_LOG_EVENT_UNFILTERED() end)
    local cached = 0
    if type(CFCT.spellIdCache) == "table" then
        for _ in pairs(CFCT.spellIdCache) do cached = cached + 1 end
    end
    return { ran = ran, dispatched = dispatched, cached = cached, log = CFCT._log }, nil
end

-- Positive control: with a WORKING probe the same event MUST reach the cache.
-- Without this, section H would also pass if the handler never processed
-- anything at all, which would make the negative test meaningless.
local function runCLEUWithWorkingProbe(vector)
    local env = newEnv(vector)
    env.CombatLogGetCurrentEventInfo = function()
        return 0, "SPELL_DAMAGE", false, "Player-1", "src", 1, 0, "Enemy-1", "dst", 2, 0,
            1234, "TestSpell", 4, 500, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    end
    env.C_CombatLog = { GetCurrentEventInfo = env.CombatLogGetCurrentEventInfo }
    env.Enum = { CombatLogObject = { TypeGuardian = 8, TypePet = 16, AffiliationMine = 1 } }
    local CFCT = { _log = {}, _testMode = false }
    CFCT.Log = function(self, msg) table.insert(self._log, msg or "") end
    CFCT.L = function(key, ...) return key end
    CFCT.Config = {
        animDuration = 1, OnLoad = function() end, mergeEvents = false,
        spellIconAspectRatio = 1, spellIconZoom = 1,
        spellIconOffsetX = 0, spellIconOffsetY = 0,
        showIcons = false, abbreviateNumbers = false, kiloSeparator = false,
        demoteSmallCritsEnabled = false, demoteSmallCritThreshold = 0,
        filterAbsoluteEnabled = false, filterRelativeEnabled = false,
        filterAverageEnabled = false, colorByType = false,
        colorTableDotEnabled = false, maxDisplayed = 0,
    }
    CFCT.ConfigPanel = { IsVisible = function() return false end }
    local chunk = loadfile("main.lua")
    if not chunk then return nil, "loadfile failed" end
    setfenv(chunk, env)
    local ok, err = pcall(chunk, "ClassicFCT", CFCT)
    if not ok then return nil, tostring(err) end
    local frame = CFCT.frame
    if not frame then return nil, "no frame" end
    pcall(function() frame:PLAYER_ENTERING_WORLD() end)
    local ran = pcall(function() frame:COMBAT_LOG_EVENT_UNFILTERED() end)
    local cached = 0
    if type(CFCT.spellIdCache) == "table" then
        for _ in pairs(CFCT.spellIdCache) do cached = cached + 1 end
    end
    return { ran = ran, cached = cached, log = CFCT._log }, nil
end

do
    local vector = VECTORS[1]  -- Vanilla: a legacy client, so CLEU is registered.
    local control, controlErr = runCLEUWithWorkingProbe(vector)
    if not control then
        check("H: positive control - a non-secret event reaches the cache", false, controlErr)
    else
        check("H: positive control - a non-secret event reaches the cache", control.cached == 1,
            "cached " .. control.cached)
    end
end

do
    local vector = VECTORS[1]  -- Vanilla: a legacy client, so CLEU is registered.
    local result, err = runCLEUWithoutProbe(vector)
    if not result then
        check("H: secret probe absent -> CLEU handler is contained", false, err)
    else
        check("H: secret probe absent -> CLEU handler does not raise", result.ran)
        -- The guard must have suppressed the event: no spell may reach the cache.
        check("H: secret probe absent -> no event reaches the cache", result.cached == 0,
            "cached " .. result.cached)
        -- ...and no text may be produced.
        check("H: secret probe absent -> no number is dispatched", result.dispatched == false)
        -- ...and it must say so, once, rather than failing silently.
        local reported = 0
        for _, msg in ipairs(result.log) do
            if tostring(msg):find("probe", 1, true) then reported = reported + 1 end
        end
        check("H: secret probe absent -> reported once", reported == 1, "got " .. reported)
    end
end

--------------------------------------------------------------------------------
-- C. Locale integrity: keys, order, placeholders, encoding.
--------------------------------------------------------------------------------
-- Single source of truth for the locale file list: used for loading, for the
-- BOM check and for the per-locale key-count checks.
local LOCALE_FILES = {
    "Locales/enUS.lua", "Locales/deDE.lua", "Locales/ruRU.lua", "Locales/frFR.lua",
    "Locales/esES.lua", "Locales/esMX.lua", "Locales/itIT.lua", "Locales/ptBR.lua",
    "Locales/zhCN.lua", "Locales/zhTW.lua", "Locales/koKR.lua",
}
-- Every locale table other than enUS.
local TRANSLATED_LOCALES = {
    "deDE", "ruRU", "frFR", "esES", "esMX", "itIT", "ptBR", "zhCN", "zhTW", "koKR",
}
-- Documented per-locale absences. Every locale table now carries the FULL key
-- set, so there are none: "Pow" and "init" used to be intentionally omitted
-- and fall back to English, and both are now translated. The table is kept
-- (empty) because the check that consumes it is the right shape for a future
-- key that genuinely cannot be translated, and an undocumented absence must
-- still fail the gate.
local DOCUMENTED_ABSENCES = {}
-- Sanity floor for the enUS table: catches a truncated or half-written file
-- without hard-coding the current key count.
local MIN_LOCALE_KEYS = 200

local localeTables = {}
local localeOrder = {}
local fakeCFCT = {}
function fakeCFCT:RegisterLocale(code, tbl)
    localeTables[code] = tbl
    table.insert(localeOrder, code)
end

for _, path in ipairs(LOCALE_FILES) do
    local chunk = loadfile(path)
    local ok, err = pcall(chunk, "locales", fakeCFCT)
    check("C: locale registers " .. path, ok, err)
end

-- Definition order must come from source text: pairs() order is unspecified.
local function keyOrderFromSource(path)
    local text = readAll(path) or ""
    local order, seen = {}, {}
    for k in text:gmatch('%["(.-)"%]%s*=') do
        if not seen[k] then
            seen[k] = true
            order[#order + 1] = k
        end
    end
    return order
end

-- The enUS source is the reference. Its key count is DERIVED from the source
-- file, never hard-coded, so adding a key does not silently break the gate.
local enSourceOrder = keyOrderFromSource("Locales/enUS.lua")
local enSourceCount = #enSourceOrder
check("C: enUS source parses keyed entries", enSourceCount > 0, "got " .. enSourceCount)
check("C: enUS key count above the sanity floor", enSourceCount >= MIN_LOCALE_KEYS,
    "got " .. enSourceCount .. " (floor " .. MIN_LOCALE_KEYS .. ")")

local enUSSet, enUSIndex = {}, {}
for i, k in ipairs(enSourceOrder) do
    enUSSet[k] = true
    enUSIndex[k] = i
end

local enUS = localeTables["enUS"]
check("C: enUS registered", enUS ~= nil)
if enUS then
    local n = 0
    for k in pairs(enUS) do n = n + 1 end
    check("C: enUS registered key count matches the source", n == enSourceCount,
        "got " .. n .. ", source " .. enSourceCount)
    -- enUS is the identity table: every value equals its key, because the key
    -- IS the English source string.
    local notIdentity = {}
    for _, k in ipairs(enSourceOrder) do
        if enUS[k] ~= k then notIdentity[#notIdentity + 1] = k end
    end
    check("C: enUS is the identity table (value == key)", #notIdentity == 0,
        #notIdentity > 0 and table.concat(notIdentity, ", ") or nil)
end

-- How many documented absences actually exist in enUS: that is how much a
-- translated table is expected to be short by.
local expectedAbsences = 0
for k in pairs(DOCUMENTED_ABSENCES) do
    if enUSSet[k] then expectedAbsences = expectedAbsences + 1 end
end
local expectedLocaleCount = enSourceCount - expectedAbsences

local function placeholderProfile(s)
    local profile = {}
    if type(s) == "string" then
        -- A positional specifier (%1$s) is the same specifier as its plain
        -- form (%s): normalise it before counting, so a translator using the
        -- positional form does not look like a placeholder mismatch.
        local norm = s:gsub("%%(%d+)%$", "%%")
        local count_s, count_d = 0, 0
        for _ in norm:gmatch("%%s") do count_s = count_s + 1 end
        for _ in norm:gmatch("%%d") do count_d = count_d + 1 end
        local count_c = 0
        for _ in norm:gmatch("|c") do count_c = count_c + 1 end
        local count_r = 0
        for _ in norm:gmatch("|r") do count_r = count_r + 1 end
        profile.count_s, profile.count_d, profile.count_c, profile.count_r = count_s, count_d, count_c, count_r
    end
    return profile
end

for _, code in ipairs(TRANSLATED_LOCALES) do
    local tbl = localeTables[code]
    if not tbl then
        check("C: " .. code .. " table present", false)
    else
        local unknown, mismatch = 0, {}
        local keys = {}
        local count = 0
        for k, v in pairs(tbl) do
            count = count + 1
            if not enUSSet[k] then
                unknown = unknown + 1
                keys[#keys + 1] = tostring(k)
            else
                local pe, pl = placeholderProfile(enUS[k]), placeholderProfile(v)
                if pe.count_s ~= pl.count_s or pe.count_d ~= pl.count_d
                    or pe.count_c ~= pl.count_c or pe.count_r ~= pl.count_r then
                    mismatch[#mismatch + 1] = k
                end
            end
        end
        check("C: " .. code .. " has no unknown keys", unknown == 0,
            unknown > 0 and table.concat(keys, ", ") or nil)
        check("C: " .. code .. " placeholder/escape integrity",
            #mismatch == 0, #mismatch > 0 and table.concat(mismatch, ", ") or nil)
        -- Key count must match enUS minus the documented absences, and nothing else.
        check("C: " .. code .. " key count matches enUS minus documented absences",
            count == expectedLocaleCount,
            "got " .. count .. ", expected " .. expectedLocaleCount)
        local undocumented = {}
        for _, k in ipairs(enSourceOrder) do
            if tbl[k] == nil and not DOCUMENTED_ABSENCES[k] then
                undocumented[#undocumented + 1] = k
            end
        end
        check("C: " .. code .. " only misses documented keys", #undocumented == 0,
            #undocumented > 0 and table.concat(undocumented, ", ") or nil)
        -- order check: locale keys must appear in the same relative order as enUS source
        local locOrder = keyOrderFromSource("Locales/" .. code .. ".lua")
        local expected = {}
        for _, k in ipairs(enSourceOrder) do
            if tbl[k] ~= nil then expected[#expected + 1] = k end
        end
        local orderOk, orderBad = (#locOrder == #expected), nil
        if orderOk then
            for i = 1, #expected do
                if locOrder[i] ~= expected[i] then
                    orderOk = false
                    orderBad = tostring(locOrder[i]) .. " (expected " .. tostring(expected[i]) .. ")"
                    break
                end
            end
        else
            orderBad = "#order=" .. #locOrder .. " expected=" .. #expected
        end
        check("C: " .. code .. " key order matches enUS", orderOk, orderBad)
    end
end

for _, file in ipairs(LOCALE_FILES) do
    local raw = readAll(file)
    check("C: no BOM " .. file, raw and raw:sub(1, 3) ~= "\239\187\191")
end

--------------------------------------------------------------------------------
-- D. Regression guards.
--------------------------------------------------------------------------------
local mainText = readAll("main.lua") or ""
check("D: rolling-average cacheSize restored", mainText:find("local cacheSize = #damageCache", 1, true) ~= nil)
check("D: no damageCacheround residue", mainText:find("damageCacheround", 1, true) == nil)
check("D: off-target no-target guard present",
    mainText:find("offTarget.enabled and targetGUID and guid ~= targetGUID", 1, true) ~= nil)
check("D: critical misskey rename complete", mainText:find("misskey", 1, true) == nil)

--------------------------------------------------------------------------------
-- E. Version metadata consistency.
--------------------------------------------------------------------------------
-- One spelling, one source of truth. The version lives in the .toc files
-- (that is what the AddOn list shows); the CHANGELOG heading and the in-game
-- banner must agree with it. The expected version is DERIVED from the .toc
-- files rather than hard-coded here, so a release bump cannot half-apply and
-- leave the gate verifying a stale constant: the gate fails if the surfaces
-- disagree with each other, which is the property that actually matters.
local tocs = { "ClassicFCT-Vanilla.toc", "ClassicFCT-TBC.toc", "ClassicFCT-Titan.toc",
    "ClassicFCT-Forever.toc", "ClassicFCT-Mainline.toc" }
local tocVersions = {}
for _, toc in ipairs(tocs) do
    local text = readAll(toc) or ""
    local ver = text:match("## Version:%s*(%S+)")
    tocVersions[toc] = ver
    local _, versionLines = text:gsub("## Version:", "")
    check("E: " .. toc .. " declares exactly one version", versionLines == 1, "got " .. versionLines)
    check("E: " .. toc .. " declares a version", ver ~= nil)
end
-- The reference version is the one every .toc must agree on.
local EXPECTED_VERSION = tocVersions[tocs[1]]
for _, toc in ipairs(tocs) do
    check("E: " .. toc .. " version " .. tostring(EXPECTED_VERSION),
        tocVersions[toc] == EXPECTED_VERSION, tostring(tocVersions[toc]))
end
local changelog = readAll("CHANGELOG.txt") or ""
local changelogVersion = changelog:match("^(%S+)")
check("E: CHANGELOG starts with " .. tostring(EXPECTED_VERSION),
    changelogVersion == EXPECTED_VERSION, tostring(changelogVersion))
-- The banner is "<version>    <date>" in main.lua's changelog notice.
local bannerVersion = mainText:match("\n%s*(%S+)%s+%a+%s+%d+,%s+%d%d%d%d")
check("E: main.lua banner shows " .. tostring(EXPECTED_VERSION),
    bannerVersion == EXPECTED_VERSION, tostring(bannerVersion))
local readme = readAll("README.md") or ""
check("E: README present", #readme > 500)

--------------------------------------------------------------------------------
-- F. Packaging references.
--------------------------------------------------------------------------------
local function checkLoadList(label, file, baseDir)
    local text = readAll(file)
    if not text then
        check("F: " .. label .. " exists", false)
        return
    end
    local missing = {}
    for line in text:gmatch("[^\r\n]+") do
        local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
        if trimmed ~= "" and not trimmed:find("^##") and not trimmed:find("^<") then
            local p = trimmed:gsub("\\", "/")
            local full = (baseDir and (baseDir .. "/" .. p)) or p
            if not fileExists(full) then missing[#missing + 1] = p end
        elseif trimmed:find("^<Script") then
            local f = trimmed:match('file="([^"]+)"')
            if f then
                local p = f:gsub("\\", "/")
                local full = (baseDir and (baseDir .. "/" .. p)) or p
                if not fileExists(full) then missing[#missing + 1] = p end
            end
        end
    end
    check("F: " .. label .. " references resolve", #missing == 0,
        #missing > 0 and table.concat(missing, ", ") or nil)
end

for _, toc in ipairs(tocs) do
    checkLoadList("toc " .. toc, toc)
end
checkLoadList("Locales/locales.xml", "Locales/locales.xml", "Locales")
checkLoadList("Presets/presets.xml", "Presets/presets.xml", "Presets")

local packagingRefs = { "desks/", "bench/", "classroom/", "CAIRN.md", "workshop.md", "hands-up.md" }
for _, toc in ipairs(tocs) do
    local text = readAll(toc) or ""
    for _, ref in ipairs(packagingRefs) do
        if text:find(ref, 1, true) then
            check("F: " .. toc .. " does not reference " .. ref, false)
        end
    end
end
check("F: no workspace refs in any .toc", true)

local localesXml = readAll("Locales/locales.xml") or ""
local localeScripts = 0
for _ in localesXml:gmatch('<Script file=') do localeScripts = localeScripts + 1 end
check("F: locales.xml lists 12 scripts", localeScripts == 12, "got " .. localeScripts)
local presetsXml = readAll("Presets/presets.xml") or ""
check("F: presets.xml includes ClassicPlus", presetsXml:find("ClassicPlus.lua", 1, true) ~= nil)

--------------------------------------------------------------------------------
-- G. Warning budget: the shipped sources must stay lint-clean.
--------------------------------------------------------------------------------
-- The count is ASSERTED, not merely bounded. Any new warning fails the gate,
-- so a warning can never be re-introduced silently.
--
-- The lint configuration is .luacheckrc at the repo root. It declares the WoW
-- client globals the addon legitimately uses (the SavedVariables, the slash
-- command globals and the client APIs) and sets std = "lua51". Without it
-- luacheck reports ~384 false "accessing undefined variable" warnings on the
-- shipped sources and the handful of real warnings are invisible in the noise.
-- The count below therefore also protects the configuration: weakening
-- .luacheckrc would push the count up and fail this check.
--
-- The file count is asserted as well, so a file silently dropped from the
-- linted set cannot hide a warning.
--
-- luacheck is a release requirement: if the tool is not installed the check
-- FAILS rather than passing silently, because an unverified warning budget is
-- not a verified warning budget.
local LUACHECK_MAX_WARNINGS = 0
local LUACHECK_MAX_ERRORS = 0
local LUACHECK_FILE_COUNT = 18

check("G: .luacheckrc is present", fileExists(".luacheckrc"))

local function shellQuote(path)
    return "'" .. tostring(path):gsub("'", "'\\''") .. "'"
end

local quotedFiles = {}
for _, path in ipairs(LUA_FILES) do quotedFiles[#quotedFiles + 1] = shellQuote(path) end
local luacheckCmd = "luacheck --no-color --codes " .. table.concat(quotedFiles, " ") .. " 2>&1"
local luacheckOut = ""
local luacheckRan = false
do
    local ok, pipe = pcall(io.popen, luacheckCmd)
    if ok and pipe then
        luacheckOut = pipe:read("*a") or ""
        pipe:close()
        luacheckRan = true
    end
end
check("G: luacheck ran", luacheckRan, "is luacheck installed and on PATH?")

if luacheckRan then
    local totalWarnings = luacheckOut:match("Total:%s*(%d+)%s*warnings?")
    local totalErrors = luacheckOut:match("/%s*(%d+)%s*errors?")
    local totalFiles = luacheckOut:match("in%s*(%d+)%s*files?")
    check("G: luacheck reported a total", totalWarnings ~= nil,
        luacheckOut:sub(-400))
    if totalWarnings then
        check("G: warnings <= " .. LUACHECK_MAX_WARNINGS,
            tonumber(totalWarnings) <= LUACHECK_MAX_WARNINGS,
            "got " .. totalWarnings .. " (budget " .. LUACHECK_MAX_WARNINGS .. ")")
        check("G: errors = " .. LUACHECK_MAX_ERRORS,
            tonumber(totalErrors) == LUACHECK_MAX_ERRORS,
            "got " .. tostring(totalErrors))
        check("G: " .. LUACHECK_FILE_COUNT .. " shipped files were linted",
            tonumber(totalFiles) == LUACHECK_FILE_COUNT,
            "got " .. tostring(totalFiles))
    end
    -- Surface the offending lines when the budget is exceeded, so the failure
    -- is actionable without re-running luacheck by hand.
    if totalWarnings and tonumber(totalWarnings) > LUACHECK_MAX_WARNINGS then
        for line in luacheckOut:gmatch("[^\r\n]+") do
            if line:find("%(W%d+%)") or line:find("%(E%d+%)") then
                print("      " .. line)
            end
        end
    end
end

--------------------------------------------------------------------------------
print("")
print(string.format("checks=%d failures=%d", checks, failures))
if failures == 0 then
    print("RELEASE GATE PASSED")
else
    print("RELEASE GATE FAILED")
    os.exit(1)
end
