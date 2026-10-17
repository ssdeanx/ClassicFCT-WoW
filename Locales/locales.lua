-- luacheck: globals GetLocale
local _, CFCT = ...
local format = string.format

-- Locale registry. Locale files call CFCT:RegisterLocale(code, tbl) with the
-- exact enUS source string as key. Resolution is lazy: every registration is
-- complete before the first CFCT.L call (Locales\locales.xml loads before
-- presets.lua / config.lua / main.lua in every .toc).
CFCT.Locales = CFCT.Locales or {}
local activeTable
local resolved = false

function CFCT:RegisterLocale(code, tbl)
    if (type(code) == "string") and (type(tbl) == "table") then
        self.Locales[code] = tbl
        if resolved and (self.localeCode == code) then
            resolved = false
            activeTable = nil
        end
    end
end

local function resolveActiveLocale()
    local code = (type(GetLocale) == "function") and GetLocale() or nil
    if (type(code) ~= "string") or (CFCT.Locales[code] == nil) then
        code = "enUS"
    end
    CFCT.localeCode = code
    activeTable = CFCT.Locales[code]
    resolved = true
    return activeTable
end

function CFCT:GetActiveLocale()
    if (not resolved) then resolveActiveLocale() end
    return self.localeCode
end

-- CFCT.L(key[, ...]): display string for key. Missing locale -> enUS table;
-- missing key -> the key itself (keys are the enUS source strings). Extra
-- arguments are applied with string.format, guarded: a bad translator value
-- can never throw, it falls back to the unformatted string.
function CFCT.L(key, ...)
    local tbl = activeTable
    if (not resolved) then tbl = resolveActiveLocale() end
    local str = key
    if (type(key) == "string") then
        str = (tbl and tbl[key]) or (CFCT.Locales.enUS and CFCT.Locales.enUS[key]) or key
    end
    if (type(str) == "string") and (select("#", ...) > 0) then
        local ok, res = pcall(format, str, ...)
        if ok then return res end
    end
    return str
end
