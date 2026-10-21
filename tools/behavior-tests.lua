--  tools/behavior-tests.lua — behavioural coverage for the addon's core paths.
--
-- The release gate proves the addon LOADS and that its metadata is consistent.
-- It does not prove the addon BEHAVES: the combat-text pipeline, the
-- secret-value guard and the config persistence had no coverage at all
-- (findings TC-04, TC-05, TC-06).
--
-- This file closes that gap. It drives the real addon code - the same
-- functions the client calls - through the stub client in bench/harness.lua
-- and asserts observable behaviour.
--
-- NOT shipped: tools/ is excluded from the release zip (explicit manifest
-- in tools/package.sh), so the suite can be tracked and run in CI.
--
-- Run:  lua5.1 tools/behavior-tests.lua

local harness = dofile("tools/harness.lua")

local failures = 0
local checks = 0
local function section(name)
    print("")
    print("== " .. name .. " ==")
end

local function check(name, cond, detail)
    checks = checks + 1
    if cond then
        print("  PASS  " .. name)
    else
        failures = failures + 1
        print("  FAIL  " .. name .. (detail and (" -- " .. tostring(detail)) or ""))
    end
end

-- =============================================================================
section("CLEU pipeline: a damage event produces a number")
-- =============================================================================
-- Loads the addon the way the client does: the preset files, then config.lua
-- (which owns CFCT.Config and its OnLoad), then main.lua. config.lua must
-- come first because main.lua reads CFCT.Config[cat] for every category.
local function loadedEnv(options)
    options = options or {}
    local env = harness.newEnv(options)
    local CFCT = { _log = {}, _testMode = false }
    CFCT.Log = function(self, msg) table.insert(self._log, msg or "") end -- luacheck: ignore 212
    CFCT.L = function(key, ...) return key end -- luacheck: ignore 212
    CFCT.ConfigPanel = { IsVisible = function() return false end }
    CFCT.Presets = {}
    CFCT.AddDefaultPreset = function(self, name, tbl) return tbl end -- luacheck: ignore 212

    -- The SavedVariables are plain globals in the client. A test can seed
    -- them to model an EXISTING profile.
    env.ClassicFCTConfig = env.ClassicFCTConfig or nil
    env.ClassicFCTVars = env.ClassicFCTVars or nil
    env.ClassicFCTTables = env.ClassicFCTTables or nil
    env.ClassicFCTCustomPresets = env.ClassicFCTCustomPresets or nil
    env.ClassicFCTCharConfig = env.ClassicFCTCharConfig or nil
    env.ClassicFCTCharVars = env.ClassicFCTCharVars or nil
    env.ClassicFCTCharTables = env.ClassicFCTCharTables or nil
    if (type(options.savedVars) == "table") then
        for name, value in pairs(options.savedVars) do env[name] = value end
    end

    local ok, e = true, nil

    -- The real load order is: presets.lua, then the preset files, then
    -- config.lua, then main.lua. presets.lua defines CFCT:AddDefaultPreset
    -- and CFCT:GetDefaultPresets, which config.lua calls for the schema.
    local prc = assert(loadfile("presets.lua"))
    setfenv(prc, env)
    local prok, prerr = pcall(prc, "ClassicFCT", CFCT)
    if not prok then ok, e = false, prerr end

    -- The preset files carry the file-scope Enum.Damageclass lookups and
    -- provide the schema config.lua needs.
    for _, p in ipairs({ "Presets/MoP.lua", "Presets/Classic.lua", "Presets/ClassicPlus.lua" }) do
        local chunk = assert(loadfile(p))
        setfenv(chunk, env)
        local pok, perr = pcall(chunk, "ClassicFCT", CFCT)
        if not pok then ok, e = false, perr break end
    end

    if ok then
        local cfg = assert(loadfile("config.lua"))
        setfenv(cfg, env)
        local cok, cerr = pcall(cfg, "ClassicFCT", CFCT)
        if not cok then ok, e = false, cerr end
    end

    if ok then
        -- The config VALUES only exist after Config:OnLoad() has run, which
        -- is what the client's ADDON_LOADED does. Without it the config
        -- holds only the method table and every dispatch fails on a nil
        -- value.
        local loadOk, loadErr = pcall(function() CFCT.Config:OnLoad() end)
        if not loadOk then ok, e = false, loadErr end
    end

    if ok then
        -- The config is now the real one. Test overrides are applied on TOP
        -- of the values the config actually holds, so a test that changes one
        -- setting does not silently drop the others (an override that replaced
        -- a whole category table made the dispatch fail with a nil
        -- aspectRatio).
        if options.config then
            for k, v in pairs(options.config) do
                if (type(v) == "table") and (type(CFCT.Config[k]) == "table") then
                    for k2, v2 in pairs(v) do CFCT.Config[k][k2] = v2 end
                else
                    CFCT.Config[k] = v
                end
            end
        end
        local chunk = assert(loadfile("main.lua"))
        setfenv(chunk, env)
        local mok, merr = pcall(chunk, "ClassicFCT", CFCT)
        if not mok then ok, e = false, merr end
    end

    return CFCT, env, ok, e
end

do
    local CFCT, env, ok, err = loadedEnv({ project = 2, interface = 11509 })
    check("main.lua loads under a classic client", ok, err)
    if ok then
        CFCT.frame:PLAYER_ENTERING_WORLD()
        -- SPELL_DAMAGE: arg12=spellId arg13=spellName arg14=school arg15=amount
        -- arg21=crit (Blizzard's own parser: the 7th value of select(4,...)).
        -- arg12=spellId arg13=spellName arg14=school arg15=amount
        -- arg16=overkill arg17=resisted arg18=blocked arg19=absorbed
        -- arg20=glancing arg21=CRITICAL
        harness.setCLEU(env, harness.cleuPayload("SPELL_DAMAGE", "Player-1", "Target-1", {
            1234, "Fireball", 4, 500, 0, 0, 0, 0, 0, true,
        }))
        local fired, ferr = harness.fireCLEU(CFCT)
        check("the CLEU handler does not raise", fired, ferr)
        -- The event is cached, not dispatched immediately.
        local cached = 0
        for _ in pairs(CFCT.Animating or {}) do cached = cached + 1 end
        check("the event is cached rather than shown instantly", cached == 0,
            "cached=" .. cached)
        -- Drive a frame so ProcessCachedEvents dispatches it.
        harness.tick(CFCT, env, 0.2)
        check("a number is shown for the damage event", harness.liveCount(CFCT) == 1,
            "live=" .. harness.liveCount(CFCT))
        local texts = harness.liveTexts(CFCT)
        check("the number carries the damage amount", tostring(texts[1]):find("500", 1, true) ~= nil,
            tostring(texts[1]))
    end
end

-- =============================================================================
section("CLEU pipeline: the arg12..arg24 layout is what the addon expects")
-- =============================================================================
do
    -- Blizzard's own parser (Blizzard_CombatLog.lua, every branch) reads
    -- select(4, ...) for a spell damage event as:
    --   amount, overkill, school, resisted, blocked, absorbed, critical,
    --   glancing, crushing, isOffHand
    -- The addon unpacks arg12=spellId arg13=spellName arg14=school arg15=amount
    -- and arg21=crit. Verify BOTH the amount and the crit land correctly.
    local CFCT, env, ok = loadedEnv({ project = 2, interface = 11509 })
    if ok then
        CFCT.frame:PLAYER_ENTERING_WORLD()
        -- amount=500 (arg15), crit=1 (arg21)
        -- arg12=spellId arg13=spellName arg14=school arg15=amount
        -- arg16=overkill arg17=resisted arg18=blocked arg19=absorbed
        -- arg20=glancing arg21=CRITICAL
        harness.setCLEU(env, harness.cleuPayload("SPELL_DAMAGE", "Player-1", "Target-1", {
            1234, "Fireball", 4, 500, 0, 0, 0, 0, 0, true,
        }))
        harness.fireCLEU(CFCT)
        harness.tick(CFCT, env, 0.2)
        local texts = harness.liveTexts(CFCT)
        check("arg15 is read as the amount", tostring(texts[1]):find("500", 1, true) ~= nil,
            tostring(texts[1]))
        -- The crit is arg21. If the layout were off by one the crit flag
        -- would land on arg20 (glancing) and the number would be filed under
        -- the plain "spell" category instead of "spellcrit". The category is
        -- what carries the crit.
        local state = nil
        for _, f in pairs(CFCT.Animating) do state = f.state end
        check("arg21 is read as the crit flag", state and state.cat == "spellcrit",
            state and tostring(state.cat) or "no state")
    end
end

-- =============================================================================
section("The crit flag is read correctly in every form a client can deliver it")
-- =============================================================================
do
    -- Every supported client delivers the crit flag as a BOOLEAN (Blizzard's
    -- own parser tests it with `if critical then`). Lua treats the NUMBER 0
    -- as true, so a numeric 0/1 flag must not be read as "every hit is a
    -- crit". Both forms have to classify correctly.
    local function categoryOf(critValue)
        local CFCT, env, ok = loadedEnv({ project = 2, interface = 11509 })
        if not ok then return nil, "load failed" end
        CFCT.frame:PLAYER_ENTERING_WORLD()
        harness.setCLEU(env, harness.cleuPayload("SPELL_DAMAGE", "Player-1", "Target-1", {
            1234, "Fireball", 4, 500, 0, 0, 0, 0, 0, critValue,
        }))
        harness.fireCLEU(CFCT)
        harness.tick(CFCT, env, 0.2)
        local state = nil
        for _, f in pairs(CFCT.Animating) do state = f.state end
        return state and state.cat or "no number"
    end

    check("a boolean crit flag is read as a crit", categoryOf(true) == "spellcrit",
        tostring(categoryOf(true)))
    check("a boolean non-crit flag is read as a non-crit",
        categoryOf(false) == "spell", tostring(categoryOf(false)))
    -- The numeric form: 1 is a crit, 0 is NOT. In Lua 0 is truthy, so a
    -- client delivering 0/1 would otherwise mark every hit as a crit.
    check("a numeric 1 crit flag is read as a crit", categoryOf(1) == "spellcrit",
        tostring(categoryOf(1)))
    check("a numeric 0 crit flag is read as a NON-crit", categoryOf(0) == "spell",
        tostring(categoryOf(0)))
end

-- =============================================================================
section("Every combat-log branch reads its arguments the way the client sends them")
-- =============================================================================
-- The argument layouts differ per event type, and they are verified against
-- Blizzard's own parser (Blizzard_CombatLog.lua on every branch):
--
--   SWING_DAMAGE  arg12=amount arg14=school arg18=critical
--                 (Blizzard: amount, overkill, school, ... = ...)
--   SPELL_DAMAGE  arg12=spellId arg13=spellName arg14=school arg15=amount
--                 arg21=critical
--                 (Blizzard: amount, overkill, school, ... = select(4, ...))
--   SPELL_HEAL    arg12=spellId arg13=spellName arg14=school arg15=amount
--                 arg18=critical
--                 (Blizzard: amount, overhealing, absorbed, critical = select(4, ...))
--   SWING_MISSED  arg12=missType arg13=isOffHand arg14=amountMissed
--   SPELL_MISSED  arg12=spellId arg13=spellName arg14=school arg15=missType
--                 arg17=amountMissed
do
    -- Fires one event and returns the category of the single number it made.
    local function categoryOf(event, extra)
        local CFCT, env, ok = loadedEnv({ project = 2, interface = 11509 })
        if not ok then return nil, "load failed" end
        CFCT.frame:PLAYER_ENTERING_WORLD()
        harness.setCLEU(env, harness.cleuPayload(event, "Player-1", "Target-1", extra))
        harness.fireCLEU(CFCT)
        harness.tick(CFCT, env, 0.2)
        local state, count = nil, 0
        for _, f in pairs(CFCT.Animating) do state = f.state; count = count + 1 end
        if count ~= 1 then return "expected 1 number, got " .. count end
        return state and state.cat or "no number"
    end

    -- A swing carries no spell id: the amount is the FIRST event-specific
    -- argument, not the fourth. Reading arg15 would show the swing's school
    -- as if it were a damage number.
    check("a swing reads its amount from arg12",
        categoryOf("SWING_DAMAGE", { 250, 0, 1, 0, 0, 0, false, 0, 0, 0 }) == "auto",
        tostring(categoryOf("SWING_DAMAGE", { 250, 0, 1, 0, 0, 0, false, 0, 0, 0 })))
    check("a swing's amount is the number that is shown",
        (function()
            local CFCT, env, ok = loadedEnv({ project = 2, interface = 11509 })
            if not ok then return false end
            CFCT.frame:PLAYER_ENTERING_WORLD()
            harness.setCLEU(env, harness.cleuPayload("SWING_DAMAGE", "Player-1", "Target-1",
                { 250, 0, 1, 0, 0, 0, false, 0, 0, 0 }))
            harness.fireCLEU(CFCT)
            harness.tick(CFCT, env, 0.2)
            local texts = harness.liveTexts(CFCT)
            return tostring(texts[1]):find("250", 1, true) ~= nil
        end)(), "the swing amount was not shown")

    -- A heal is a different category, and it reads its amount from arg15.
    check("a heal is filed under the heal category",
        categoryOf("SPELL_HEAL", { 1234, "Heal", 2, 800, 0, 0, false }) == "heal",
        tostring(categoryOf("SPELL_HEAL", { 1234, "Heal", 2, 800, 0, 0, false })))
    check("a heal's amount is the number that is shown",
        (function()
            local CFCT, env, ok = loadedEnv({ project = 2, interface = 11509 })
            if not ok then return false end
            CFCT.frame:PLAYER_ENTERING_WORLD()
            harness.setCLEU(env, harness.cleuPayload("SPELL_HEAL", "Player-1", "Target-1",
                { 1234, "Heal", 2, 800, 0, 0, false }))
            harness.fireCLEU(CFCT)
            harness.tick(CFCT, env, 0.2)
            local texts = harness.liveTexts(CFCT)
            return tostring(texts[1]):find("800", 1, true) ~= nil
        end)(), "the heal amount was not shown")

    -- A periodic damage is a damage over time: it gets its own category.
    check("a periodic damage is filed under the tick category",
        categoryOf("SPELL_PERIODIC_DAMAGE", { 1234, "Fireball", 4, 90, 0, 0, 0, 0, 0, false })
            == "spelltick",
        tostring(categoryOf("SPELL_PERIODIC_DAMAGE", { 1234, "Fireball", 4, 90, 0, 0, 0, 0, 0, false })))

    -- A swing miss carries its miss type FIRST (arg12).
    check("a swing miss reads its miss type from arg12",
        categoryOf("SWING_MISSED", { "DODGE", 0, 0 }) == "automiss",
        tostring(categoryOf("SWING_MISSED", { "DODGE", 0, 0 })))

    -- A spell miss carries the miss type at arg15.
    check("a spell miss reads its miss type from arg15",
        categoryOf("SPELL_MISSED", { 1234, "Fireball", 4, "PARRY", 0, 0 }) == "spellmiss",
        tostring(categoryOf("SPELL_MISSED", { 1234, "Fireball", 4, "PARRY", 0, 0 })))
end

-- =============================================================================
section("Merged events: a miss is never merged with a hit")
-- =============================================================================
do
    -- The merge path is the one the audit found the worst bug in: a broken
    -- `and/or` ternary made a merged group take the LAST event's miss flag,
    -- so a real hit could be relabelled as a Dodge and dropped by the
    -- threshold filters. The merge is off by default, so it has to be
    -- switched on explicitly or the test proves nothing.
    local CFCT, env, ok = loadedEnv({ project = 2, interface = 11509,
        config = { mergeEvents = true, mergeEventsInterval = 5,
                   mergeEventsBySpellID = false, mergeEventsBySpellIcon = true,
                   mergeEventsBySchool = true, mergeEventsByGuid = false } })
    if ok then
        CFCT.frame:PLAYER_ENTERING_WORLD()
        -- A hit and a miss of the SAME spell, close together. With the merge
        -- on they share a bucket (same icon, same school, same pet flag).
        local function spellPayload(event, amount, extra)
            local p = harness.cleuPayload(event, "Player-1", "Target-1", {
                1234, "Fireball", 4, amount, 0, 0, 0, 0, 0, 0,
            })
            for k, v in pairs(extra or {}) do p[k] = v end
            return p
        end
        -- The hit: SPELL_DAMAGE, amount 500.
        harness.setCLEU(env, spellPayload("SPELL_DAMAGE", 500))
        harness.fireCLEU(CFCT)
        -- The miss: SPELL_MISSED. The miss branch reads
        --   arg12=spellId arg13=spellName arg14=school arg15=misstype arg17=amount
        -- (Blizzard's own parser: select(4,...) gives missType, isOffHand, amountMissed).
        local missPayload = harness.cleuPayload("SPELL_MISSED", "Player-1", "Target-1", {
            1234, "Fireball", 4, "DODGE", 0, 0, 0, 0, 0, 0,
        })
        harness.setCLEU(env, missPayload)
        harness.fireCLEU(CFCT)
        -- Let the merge window expire.
        harness.tick(CFCT, env, 6)
        local live = harness.liveCount(CFCT)
        local texts = harness.liveTexts(CFCT)
        local sawDodge = false
        local sawHit = false
        for _, t in ipairs(texts) do
            if tostring(t):find("Dodge", 1, true) then sawDodge = true end
            if tostring(t):find("500", 1, true) then sawHit = true end
        end
        -- The two events are DIFFERENT categories (a hit and a miss), so the
        -- merge key must keep them apart: the hit keeps its own amount and
        -- the miss is labelled as a miss. Before the merge key carried the
        -- event type and the miss flag, the two shared a bucket and the hit
        -- was relabelled as a Dodge.
        check("a hit and a miss stay separate numbers", live == 2,
            "live=" .. live .. " texts=" .. table.concat(texts, ", "))
        check("the hit keeps its own amount", sawHit,
            "texts=" .. table.concat(texts, ", "))
        check("the miss is labelled as a Dodge", sawDodge,
            "texts=" .. table.concat(texts, ", "))
    end
end

do
    -- A heal must never be summed into a damage. The merge key carries the
    -- event type precisely so the two cannot share a bucket.
    local CFCT, env, ok = loadedEnv({ project = 2, interface = 11509,
        config = { mergeEvents = true, mergeEventsInterval = 5,
                   mergeEventsBySpellIcon = false, mergeEventsBySchool = false } })
    if ok then
        CFCT.frame:PLAYER_ENTERING_WORLD()
        harness.setCLEU(env, harness.cleuPayload("SPELL_DAMAGE", "Player-1", "Target-1", {
            1234, "Fireball", 4, 500, 0, 0, 0, 0, 0, false,
        }))
        harness.fireCLEU(CFCT)
        harness.setCLEU(env, harness.cleuPayload("SPELL_HEAL", "Player-1", "Target-1", {
            1234, "Heal", 2, 800, 0, 0, false,
        }))
        harness.fireCLEU(CFCT)
        harness.tick(CFCT, env, 6)
        local texts = harness.liveTexts(CFCT)
        check("a heal is never summed into a damage", harness.liveCount(CFCT) == 2,
            "live=" .. harness.liveCount(CFCT) .. " texts=" .. table.concat(texts, ", "))
    end
end

-- =============================================================================
section("IsSecretValue fails closed in every failure mode")
-- =============================================================================
do
    -- A probe that is present and reports "not secret" -> the event is shown.
    local CFCT, env, ok = loadedEnv({ project = 2, interface = 11509 })
    if ok then
        CFCT.frame:PLAYER_ENTERING_WORLD()
        harness.setCLEU(env, harness.cleuPayload("SPELL_DAMAGE", "Player-1", "Target-1", {
            1234, "Fireball", 4, 500, 0, 0, 0, 0, 0,
        }))
        harness.fireCLEU(CFCT)
        harness.tick(CFCT, env, 0.2)
        check("a non-secret event is shown", harness.liveCount(CFCT) == 1,
            "live=" .. harness.liveCount(CFCT))
    end
end

do
    -- A probe that reports the value IS secret -> the event is suppressed.
    local CFCT, env, ok = loadedEnv({ project = 2, interface = 11509 })
    if ok then
        CFCT.frame:PLAYER_ENTERING_WORLD()
        -- Mark the payload's secret field so the probe reports it as secret.
        local payload = harness.cleuPayload("SPELL_DAMAGE", "Player-1", "Target-1", {
            1234, "Fireball", 4, 500, 0, 0, 0, 0, 0,
        })
        payload[4] = harness.SECRET
        harness.setCLEU(env, payload)
        harness.fireCLEU(CFCT)
        harness.tick(CFCT, env, 0.2)
        check("a secret event is suppressed", harness.liveCount(CFCT) == 0,
            "live=" .. harness.liveCount(CFCT))
    end
end

do
    -- An ABSENT probe: the addon must fail CLOSED (suppress), not open.
    local CFCT, env, ok = loadedEnv({ project = 2, interface = 11509, probe = "absent" })
    if ok then
        CFCT.frame:PLAYER_ENTERING_WORLD()
        harness.setCLEU(env, harness.cleuPayload("SPELL_DAMAGE", "Player-1", "Target-1", {
            1234, "Fireball", 4, 500, 0, 0, 0, 0, 0,
        }))
        harness.fireCLEU(CFCT)
        harness.tick(CFCT, env, 0.2)
        check("an absent probe suppresses the event (fails closed)",
            harness.liveCount(CFCT) == 0, "live=" .. harness.liveCount(CFCT))
        -- The REPORT is what proves the GUARD fired. Without it the event
        -- could be suppressed by some unrelated error, and the test would
        -- pass for the wrong reason.
        local reported = false
        for _, m in ipairs(CFCT._log) do
            if tostring(m):find("probe is unavailable", 1, true) then reported = true end
        end
        check("an absent probe is reported as the cause", reported,
            table.concat(CFCT._log, " | "))
        -- CFCT:Log already prepends the coloured "ClassicFCT: " prefix, so a
        -- caller that repeats it in the message text prints it twice
        -- ("ClassicFCT: ClassicFCT: ..."), which is what every main.lua
        -- diagnostic used to do. Compare against the real CFCT:Log output,
        -- which is how the entry is stored here: the prefix is not at
        -- position 1, it is behind the colour codes, so count it.
        local doubled = false
        for _, m in ipairs(CFCT._log) do
            local _, count = tostring(m):gsub("ClassicFCT: ", "")
            if (count > 1) then doubled = true end
        end
        check("the log does not repeat the addon prefix", not doubled,
            table.concat(CFCT._log, " | "))
    end
end

do
    -- A probe that RAISES: also fails closed, and reports once.
    local CFCT, env, ok = loadedEnv({ project = 2, interface = 11509, probe = "raising" })
    if ok then
        CFCT.frame:PLAYER_ENTERING_WORLD()
        harness.setCLEU(env, harness.cleuPayload("SPELL_DAMAGE", "Player-1", "Target-1", {
            1234, "Fireball", 4, 500, 0, 0, 0, 0, 0,
        }))
        harness.fireCLEU(CFCT)
        harness.tick(CFCT, env, 0.2)
        check("a raising probe suppresses the event (fails closed)",
            harness.liveCount(CFCT) == 0, "live=" .. harness.liveCount(CFCT))
        local reported = false
        for _, m in ipairs(CFCT._log) do
            if tostring(m):find("probe failed", 1, true) then reported = true end
        end
        check("a raising probe is reported as the cause", reported,
            table.concat(CFCT._log, " | "))
        local doubled = false
        for _, m in ipairs(CFCT._log) do
            local _, count = tostring(m):gsub("ClassicFCT: ", "")
            if (count > 1) then doubled = true end
        end
        check("the log does not repeat the addon prefix", not doubled,
            table.concat(CFCT._log, " | "))
    end
end

do
    -- A probe that returns a NON-BOOLEAN. The addon compares the result to
    -- `true`, so a non-boolean is not "secret" and the event is allowed
    -- through. That is the documented behaviour: the probe answers a
    -- yes/no question, and anything that is not `true` means "not secret".
    -- What must NOT happen is a crash or a mis-read of the value.
    local CFCT, env, ok = loadedEnv({ project = 2, interface = 11509, probe = "nonboolean" })
    if ok then
        CFCT.frame:PLAYER_ENTERING_WORLD()
        harness.setCLEU(env, harness.cleuPayload("SPELL_DAMAGE", "Player-1", "Target-1", {
            1234, "Fireball", 4, 500, 0, 0, 0, 0, 0, false,
        }))
        local fired, ferr = harness.fireCLEU(CFCT)
        check("a non-boolean probe result does not raise", fired, ferr)
        harness.tick(CFCT, env, 0.2)
        check("a non-boolean probe result is read as 'not secret'",
            harness.liveCount(CFCT) == 1, "live=" .. harness.liveCount(CFCT))
    end
end

-- =============================================================================
section("Cross-client: the addon loads and behaves on every supported client")
-- =============================================================================
local CLIENTS = {
    { name = "Classic Era / SoD", project = 2, interface = 11509, legacy = true },
    { name = "TBC Anniversary", project = 5, interface = 20506, legacy = true },
    { name = "WotLK Titanforge", project = 11, interface = 38002, legacy = true },
    { name = "WoW Forever", project = 18, interface = 16001, legacy = false },
    { name = "Retail / Midnight", project = 1, interface = 120100, legacy = false },
}

for _, client in ipairs(CLIENTS) do
    local CFCT, env, ok, err = loadedEnv({
        project = client.project, interface = client.interface,
    })
    check(client.name .. ": main.lua loads", ok, err)
    if ok then
        -- The CLEU event is registered only on a legacy client.
        local registered = CFCT.frame.events["COMBAT_LOG_EVENT_UNFILTERED"] == true
        check(client.name .. ": CLEU registered = " .. tostring(client.legacy),
            registered == client.legacy)
        -- PLAYER_TARGET_CHANGED is registered everywhere.
        check(client.name .. ": PLAYER_TARGET_CHANGED registered",
            CFCT.frame.events["PLAYER_TARGET_CHANGED"] == true)
        -- On a legacy client a damage event shows a number.
        CFCT.frame:PLAYER_ENTERING_WORLD()
        harness.setCLEU(env, harness.cleuPayload("SPELL_DAMAGE", "Player-1", "Target-1", {
            1234, "Fireball", 4, 500, 0, 0, 0, 0, 0,
        }))
        harness.fireCLEU(CFCT)
        harness.tick(CFCT, env, 0.2)
        if client.legacy then
            check(client.name .. ": a damage event shows a number",
                harness.liveCount(CFCT) == 1, "live=" .. harness.liveCount(CFCT))
        else
            check(client.name .. ": a damage event is NOT shown (restricted client)",
                harness.liveCount(CFCT) == 0, "live=" .. harness.liveCount(CFCT))
        end
    end
end

-- =============================================================================
section("The preset files load on every client (the Enum.Damageclass trap)")
-- =============================================================================
do
    -- The three preset files reference Enum.Damageclass members at FILE
    -- SCOPE. If a client does not define one of them, the file raises
    -- "table index is nil" at load and the whole addon fails to load.
    for _, client in ipairs(CLIENTS) do
        local env = harness.newEnv({ project = client.project, interface = client.interface })
        local CFCT = { _log = {}, _testMode = false }
        CFCT.Log = function(self, msg) table.insert(self._log, msg or "") end -- luacheck: ignore 212
        CFCT.L = function(key, ...) return key end -- luacheck: ignore 212
        CFCT.Config = {}
        CFCT.ConfigPanel = { IsVisible = function() return false end }
        -- The preset files call CFCT:AddDefaultPreset.
        local adds = {}
        CFCT.AddDefaultPreset = function(self, name, tbl) adds[#adds+1] = name; return tbl end -- luacheck: ignore 212
        local allOk, err = true, nil
        for _, p in ipairs({ "Presets/MoP.lua", "Presets/Classic.lua", "Presets/ClassicPlus.lua" }) do
            local chunk = assert(loadfile(p))
            setfenv(chunk, env)
            local ok, e = pcall(chunk, "ClassicFCT", CFCT)
            if not ok then allOk, err = false, e break end
        end
        check(client.name .. ": the three preset files load", allOk, err)
    end
end

-- =============================================================================
section("Restricted clients: the CVar is never written")
-- =============================================================================
do
    -- On a restricted client the addon must not touch Blizzard's own combat
    -- text CVar, because it cannot replace that text.
    for _, client in ipairs(CLIENTS) do
        if not client.legacy then
            -- The stub records every SetCVar call, so any write is visible.
            local written = false
            local env = harness.newEnv({ project = client.project, interface = client.interface })
            env.SetCVar = function() written = true end
            local CFCT = { _log = {}, _testMode = false }
            CFCT.Log = function(self, msg) table.insert(self._log, msg or "") end -- luacheck: ignore 212 -- luacheck: ignore 212
            CFCT.L = function(key, ...) return key end -- luacheck: ignore 212 -- luacheck: ignore 212
            CFCT.ConfigPanel = { IsVisible = function() return false end }
            CFCT.Presets = {}
            local prc = assert(loadfile("presets.lua"))
            setfenv(prc, env)
            pcall(prc, "ClassicFCT", CFCT)
            for _, pf in ipairs({ "Presets/MoP.lua", "Presets/Classic.lua", "Presets/ClassicPlus.lua" }) do
                local c = assert(loadfile(pf))
                setfenv(c, env)
                pcall(c, "ClassicFCT", CFCT)
            end
            local cfg = assert(loadfile("config.lua"))
            setfenv(cfg, env)
            local ok = pcall(cfg, "ClassicFCT", CFCT)
            if ok then
                pcall(function() CFCT.Config:OnLoad() end)
                local chunk = assert(loadfile("main.lua"))
                setfenv(chunk, env)
                local mok = pcall(chunk, "ClassicFCT", CFCT)
                if mok then
                    CFCT.frame:ADDON_LOADED("ClassicFCT")
                    -- checkCvars runs on a timer; step past it.
                    harness.tick(CFCT, env, 0.2)
                    harness.tick(CFCT, env, 6)
                    check(client.name .. ": the combat-text CVar is never written",
                        written == false)
                end
            end
        end
    end
end

-- =============================================================================
section("The maximum number of numbers on screen: default and migration")
-- =============================================================================
do
    -- A fresh profile gets the new default: 20 numbers on screen. "Unlimited"
    -- filled the screen and made the options panel unreadable.
    local CFCT, _, ok = loadedEnv({ project = 2, interface = 11509 })
    check("a fresh profile gets the new default of 20",
        ok and CFCT.Config.maxDisplayed == 20,
        ok and tostring(CFCT.Config.maxDisplayed) or "load failed")

    -- An EXISTING profile that still holds one of the old defaults is moved
    -- to the new one when the addon is upgraded.
    for _, oldDefault in ipairs({ 0, 60 }) do
        local CFCT2, env2, ok2 = loadedEnv({ project = 2, interface = 11509,
            savedVars = {
                ClassicFCTVars = { lastVersion = "0.88" },
                ClassicFCTConfig = { maxDisplayed = oldDefault },
            } })
        check("an upgraded profile moves the old default " .. oldDefault .. " to 20",
            ok2 and CFCT2.Config.maxDisplayed == 20,
            ok2 and tostring(CFCT2.Config.maxDisplayed) or "load failed")
        check("the migrated value is written back to the saved store",
            ok2 and env2.ClassicFCTConfig and env2.ClassicFCTConfig.maxDisplayed == 20,
            ok2 and tostring(env2.ClassicFCTConfig and env2.ClassicFCTConfig.maxDisplayed) or "no store")
    end

    -- A value the user chose themselves is NOT touched, on an upgrade or not.
    local CFCT3, _, ok3 = loadedEnv({ project = 2, interface = 11509,
        savedVars = {
            ClassicFCTVars = { lastVersion = "0.88" },
            ClassicFCTConfig = { maxDisplayed = 150 },
        } })
    check("a value the user chose is left alone on an upgrade",
        ok3 and CFCT3.Config.maxDisplayed == 150,
        ok3 and tostring(CFCT3.Config.maxDisplayed) or "load failed")

    -- The migration is version-gated: the same profile on the SAME version
    -- keeps its stored value.
    local CFCT4, _, ok4 = loadedEnv({ project = 2, interface = 11509,
        savedVars = {
            ClassicFCTVars = { lastVersion = "M0.89" },
            ClassicFCTConfig = { maxDisplayed = 0 },
        } })
    check("a profile on the current version keeps its stored value",
        ok4 and CFCT4.Config.maxDisplayed == 0,
        ok4 and tostring(CFCT4.Config.maxDisplayed) or "load failed")
end

-- =============================================================================
section("Config persistence: OnLoad / OnSave round-trip")
-- =============================================================================
do
    -- A round trip: set a value, save, and check the SavedVariables hold the
    -- data - and hold no function values.
    local CFCT, env, ok, err = loadedEnv({ project = 2, interface = 11509 })
    check("config.lua loads", ok, err)
    if ok then
        local saved = false
        local ok2, e2 = pcall(function()
            CFCT.Config:OnLoad()
            CFCT.Config.auto = CFCT.Config.auto or {}
            CFCT.Config.auto.fontSize = 17
            CFCT.Config:OnSave()
            saved = true
        end)
        check("Config:OnLoad() and Config:OnSave() run", ok2, e2)
        check("OnSave ran", saved)
        check("ClassicFCTConfig is written", type(env.ClassicFCTConfig) == "table",
            type(env.ClassicFCTConfig))
        check("ClassicFCTVars is written", type(env.ClassicFCTVars) == "table",
            type(env.ClassicFCTVars))
        check("the saved config keeps the value",
            env.ClassicFCTConfig and env.ClassicFCTConfig.auto
            and env.ClassicFCTConfig.auto.fontSize == 17,
            env.ClassicFCTConfig and env.ClassicFCTConfig.auto
            and tostring(env.ClassicFCTConfig.auto.fontSize) or "missing")
        -- No function value may reach a SavedVariable.
        local function findFunction(t, path, found)
            if type(t) == "table" then
                for k, v in pairs(t) do
                    if type(v) == "function" then
                        found[#found+1] = path .. "." .. tostring(k)
                    else
                        findFunction(v, path .. "." .. tostring(k), found)
                    end
                end
            end
        end
        local found = {}
        for _, v in pairs({ "ClassicFCTConfig", "ClassicFCTVars", "ClassicFCTTables",
            "ClassicFCTCustomPresets", "ClassicFCTCharConfig", "ClassicFCTCharVars",
            "ClassicFCTCharTables" }) do
            if type(env[v]) == "table" then findFunction(env[v], v, found) end
        end
        check("no function value reaches a SavedVariable", #found == 0,
            table.concat(found, ", "))
    end
end

-- =============================================================================
section("The simultaneous-number limit is a ceiling, even when it is lowered")
-- =============================================================================
do
    -- The options panel applies a new "Max Simultaneous Numbers" immediately,
    -- while numbers may already be on screen. The limit is a ceiling, so the
    -- live count has to land ON it, never above it.
    local CFCT, env, ok = loadedEnv({ project = 2, interface = 11509,
        config = { maxDisplayed = 10 } })
    if ok then
        CFCT.frame:PLAYER_ENTERING_WORLD()
        for i = 1, 10 do
            harness.setCLEU(env, harness.cleuPayload("SPELL_DAMAGE", "Player-1", "Target-1", {
                1234, "Fireball", 4, 100 + i, 0, 0, 0, 0, 0, false,
            }))
            harness.fireCLEU(CFCT)
        end
        harness.tick(CFCT, env, 0.2)
        check("10 numbers are on screen under a limit of 10",
            harness.liveCount(CFCT) == 10, "live=" .. harness.liveCount(CFCT))
        -- Lower the limit, as the options panel would.
        CFCT.Config.maxDisplayed = 3
        -- One more event arrives.
        harness.setCLEU(env, harness.cleuPayload("SPELL_DAMAGE", "Player-1", "Target-1", {
            1234, "Fireball", 4, 999, 0, 0, 0, 0, 0, false,
        }))
        harness.fireCLEU(CFCT)
        harness.tick(CFCT, env, 0.2)
        check("the live count lands exactly on the lowered limit",
            harness.liveCount(CFCT) == 3, "live=" .. harness.liveCount(CFCT))
    end
end

-- =============================================================================
section("The live example honours the Max Simultaneous Numbers limit")
-- =============================================================================
for _, target in ipairs({ 1, 3, 5, 12, 30 }) do
    local CFCT, env, ok = loadedEnv({ project = 2, interface = 11509 })
    if ok then
        CFCT.Config.maxDisplayed = target
        CFCT.Config.animDuration = 1.5
        CFCT.Config.mergeEvents = false
        CFCT.Config.preventOverlap = false
        CFCT.Config.sortByDamage = false
        CFCT.Config.sortMissPrio = false
        CFCT.Config.attachMode = "sc"
        CFCT.Config.perspectiveScale = true
        CFCT.Config.areaX, CFCT.Config.areaY = 0, 0
        CFCT.Config.areaNX, CFCT.Config.areaNY = 0, 0
        CFCT.Config.filterSpellBlacklist = {}
        CFCT.Config.filterMissesEnabled = false
        CFCT.Config.filterAbsoluteEnabled = false
        CFCT.Config.filterRelativeEnabled = false
        CFCT.Config.filterAverageEnabled = false
        CFCT.Config.demoteSmallCritsEnabled = false
        CFCT.Config.demoteSmallCritThreshold = 0
        CFCT.Config.colorByType = false
        CFCT.Config.colorTableDotEnabled = false
        CFCT.Config.showIcons = false
        CFCT.Config.abbreviateNumbers = false
        CFCT.Config.kiloSeparator = false
        CFCT.Config.colorTable = {}
        CFCT.Config.colorTableDot = {}
        CFCT.Config.mergeEventsCounter = false
        CFCT.Config.mergeEventsByGuid = false
        CFCT.Config.mergeEventsBySpellID = false
        CFCT.Config.mergeEventsBySpellIcon = false
        CFCT.Config.mergeEventsBySchool = false
        CFCT.Config.mergeEventsInterval = 0.1
        CFCT.Config.mergeEventsIntervalOverrides = {}
        for _, cat in ipairs({ "auto", "spell", "heal" }) do
            CFCT.Config[cat] = {
                enabled = true, fontSize = 12, showIcons = false, colorByType = false,
                fontColor = "FFFFFFFF", fontPath = "Fonts\\FRIZQT__.TTF",
                missStyle = { enabled = false }, Pow = { enabled = false },
                FadeIn = { enabled = false }, FadeOut = { enabled = false }, Scroll = { enabled = false },
            }
        end
        CFCT.frame:PLAYER_ENTERING_WORLD()
        CFCT._testMode = true
        for _ = 1, 200 do harness.tick(CFCT, env, 0.2) end
        check("the live example shows exactly " .. target .. " numbers",
            harness.liveCount(CFCT) == target, "live=" .. harness.liveCount(CFCT))
    end
end

-- =============================================================================
print("")
print(string.format("checks=%d failures=%d", checks, failures))
if failures == 0 then
    print("BEHAVIOUR TESTS PASSED")
    os.exit(0)
else
    print("BEHAVIOUR TESTS FAILED")
    os.exit(1)
end
