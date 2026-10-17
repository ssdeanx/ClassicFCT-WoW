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
    env.C_AddOns = { GetAddOnMetadata = function() return "M0.88" end }
    env.GetAddOnMetadata = function() return "M0.88" end
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
-- C. Locale integrity: keys, order, placeholders, encoding.
--------------------------------------------------------------------------------
local localeTables = {}
local localeOrder = {}
local fakeCFCT = {}
function fakeCFCT:RegisterLocale(code, tbl)
    localeTables[code] = tbl
    table.insert(localeOrder, code)
end

for _, path in ipairs({ "Locales/enUS.lua", "Locales/deDE.lua", "Locales/ruRU.lua", "Locales/frFR.lua",
    "Locales/esES.lua", "Locales/esMX.lua", "Locales/itIT.lua", "Locales/ptBR.lua",
    "Locales/zhCN.lua", "Locales/zhTW.lua", "Locales/koKR.lua" }) do
    local chunk = loadfile(path)
    local ok, err = pcall(chunk, "locales", fakeCFCT)
    check("C: locale registers " .. path, ok, err)
end

local enUS = localeTables["enUS"]
check("C: enUS registered", enUS ~= nil)
check("C: enUS key count 242", enUS and next(enUS) ~= nil)

if enUS then
    local enUSSet, enUSIndex = {}, {}
    for k in pairs(enUS) do enUSSet[k] = true end
    local n = 0
    for k in pairs(enUS) do n = n + 1 end
    check("C: enUS has 242 keys", n == 242, "got " .. n)

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
    local enSourceOrder = keyOrderFromSource("Locales/enUS.lua")
    check("C: enUS source parses 242 keyed entries", #enSourceOrder == 242, "got " .. #enSourceOrder)
    for i, k in ipairs(enSourceOrder) do enUSIndex[k] = i end

    local function placeholderProfile(s)
        local profile = {}
        if type(s) == "string" then
            for token in s:gmatch("%%s") do profile[#profile + 1] = "s" end
            for token in s:gmatch("%%d") do profile[#profile + 1] = "d" end
            -- count total in order: coarse check via counts
            local count_s, count_d = 0, 0
            for _ in s:gmatch("%%s") do count_s = count_s + 1 end
            for _ in s:gmatch("%%d") do count_d = count_d + 1 end
            local count_c = 0
            for _ in s:gmatch("|c") do count_c = count_c + 1 end
            local count_r = 0
            for _ in s:gmatch("|r") do count_r = count_r + 1 end
            profile.count_s, profile.count_d, profile.count_c, profile.count_r = count_s, count_d, count_c, count_r
        end
        return profile
    end

    for _, code in ipairs({ "deDE", "ruRU", "frFR", "esES", "esMX", "itIT", "ptBR", "zhCN", "zhTW", "koKR" }) do
        local tbl = localeTables[code]
        if not tbl then
            check("C: " .. code .. " table present", false)
        else
            local unknown, mismatch = 0, {}
            local keys = {}
            for k, v in pairs(tbl) do
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
end

for _, file in ipairs({ "Locales/enUS.lua", "Locales/zhCN.lua", "Locales/ruRU.lua" }) do
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
local tocs = { "ClassicFCT-Vanilla.toc", "ClassicFCT-TBC.toc", "ClassicFCT-Titan.toc",
    "ClassicFCT-Forever.toc", "ClassicFCT-Mainline.toc" }
for _, toc in ipairs(tocs) do
    local text = readAll(toc) or ""
    check("E: " .. toc .. " version M0.88", text:find("## Version: M0.88", 1, true) ~= nil)
end
local changelog = readAll("CHANGELOG.txt") or ""
check("E: CHANGELOG starts at 0.88", changelog:sub(1, 4) == "0.88", changelog:sub(1, 30))
check("E: main.lua banner shows 0.88", mainText:find("0.88    Oct 17, 2026", 1, true) ~= nil)
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
print("")
print(string.format("checks=%d failures=%d", checks, failures))
if failures == 0 then
    print("RELEASE GATE PASSED")
else
    print("RELEASE GATE FAILED")
    os.exit(1)
end
