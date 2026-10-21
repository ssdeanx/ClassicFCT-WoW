--  tools/harness.lua — a reusable WoW-client stub for exercising the addon.
--
-- The addon runs inside the WoW client, whose Lua environment the release gate
-- has to imitate closely enough to drive real code paths. This module builds
-- that environment: frames, fonts, timers, CVars, the combat log and the
-- locale system.
--
-- It is NOT shipped (tools/ is excluded from the release zip by the explicit
-- manifest in tools/package.sh).
--
-- Usage:
--   local harness = dofile("tools/harness.lua")
--   local env, CFCT = harness.load({ project = 5, interface = 20506 })

local M = {}

M.SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })

-- ----------------------------------------------------------------------------
-- Frames
-- ----------------------------------------------------------------------------
-- Any method the client template would provide but the stub does not model
-- explicitly is a no-op. The client behaves the same way for a method a
-- template does not use, and it keeps the stub from having to enumerate the
-- whole client surface.
local function withNoopMethods(obj)
    return setmetatable(obj, {
        __index = function(t, k)
            local noop = function() end
            rawset(t, k, noop)
            return noop
        end,
    })
end

local function makeFontString(parent)
    local fs = { __isFontString = true }
    local noop = function() end
    for _, m in ipairs({
        "SetFont", "SetShadowOffset", "SetShadowColor", "SetDrawLayer", "SetJustifyH",
        "SetJustifyV", "SetText", "SetTextColor", "SetAlpha", "SetPoint", "ClearAllPoints",
        "SetParent", "SetScale", "Hide", "Show", "SetHeight", "SetWidth", "SetAllPoints",
    }) do fs[m] = noop end
    fs.text = ""
    fs.GetText = function(self) return self.text end
    fs.GetAlpha = function() return 1 end
    fs.GetStringHeight = function() return 12 end
    fs.GetStringWidth = function() return 20 end
    fs.GetParent = function() return parent end
    fs.GetName = function() return "FCTFontString" end
    return withNoopMethods(fs)
end

local function makeFrame(env)
    local frame = { events = {}, scripts = {}, children = {} }
    local noop = function() end
    for _, m in ipairs({
        "SetSize", "SetPoint", "SetParent", "SetFrameStrata", "SetFrameLevel", "SetScale",
        "SetAlpha", "Show", "Hide", "UnregisterEvent", "SetDrawLayer", "SetTextColor",
        "SetShadowColor", "SetJustifyH", "SetJustifyV", "SetFont", "SetShadowOffset",
        "ClearAllPoints", "SetHeight", "SetWidth", "SetAllPoints", "SetClampedToScreen",
        "SetChecked", "Enable", "Disable", "GetChecked", "GetValue", "SetValue",
        "SetMinMaxValues", "SetValueStep", "SetObeyStepOnDrag", "SetOrientation",
        -- A UIPanelButtonTemplate can carry a caption, and the options panel
        -- sets one on every button it creates.
        "SetText", "SetFontObject", "SetWordWrap", "SetNonSpaceWrap", "SetMaxLines",
        "SetTextColor", "SetNormalTexture", "SetHighlightTexture", "SetPushedTexture",
    }) do frame[m] = noop end
    frame.GetScale = function() return 1 end
    frame.GetEffectiveScale = function() return 1 end
    frame.GetWidth = function() return 100 end
    frame.GetHeight = function() return 20 end
    -- The frame level and strata are numbers the options panel does
    -- arithmetic on.
    frame.GetFrameLevel = function() return 1 end
    frame.GetFrameStrata = function() return "MEDIUM" end
    frame.GetName = function() return "" end
    frame.RegisterEvent = function(self, e) self.events[e] = true end
    frame.UnregisterEvent = function(self, e) self.events[e] = nil end
    frame.SetScript = function(self, k, fn) self.scripts[k] = fn end
    frame.HookScript = function(self, k, fn)
        local prev = self.scripts[k]
        self.scripts[k] = function(...)
            if prev then prev(...) end
            return fn(...)
        end
    end
    frame.CreateFontString = function(_, ...) return makeFontString(frame) end -- luacheck: ignore 212
    -- Textures (the colour preview swatch the options panel draws).
    frame.CreateTexture = function(_, ...) -- luacheck: ignore 212
        local tex = {}
        local tnoop = function() end
        for _, m in ipairs({ "SetSize", "SetTexture", "SetPoint", "SetTexCoord",
            "SetDesaturated", "SetVertexColor", "SetBlendMode", "SetDrawLayer",
            "SetAllPoints", "ClearAllPoints", "SetAlpha" }) do tex[m] = tnoop end
        tex.GetWidth = function() return 22 end
        tex.GetHeight = function() return 22 end
        tex.GetName = function() return "FCTTexture" end
        return withNoopMethods(tex)
    end
    -- Any frame method the client template would provide but the stub does
    -- not model explicitly is a no-op. A metatable keeps the stub from
    -- having to enumerate the whole client surface: an unknown method returns
    -- a no-op instead of raising, which is what the client does for a method
    -- the template does not use.
    withNoopMethods(frame)
    frame.GetParent = function() return env.UIParent end
    frame.CreateFont = function()
        local ff = {}
        local fnoop = function() end
        for _, m in ipairs({ "SetFont", "SetText", "SetTextColor", "SetPoint",
            "SetJustifyH", "SetHeight", "SetWidth", "SetFontObject", "SetAlpha" }) do ff[m] = fnoop end
        ff.GetStringWidth = function() return 20 end
        ff.GetName = function() return "FCTFont" end
        return ff
    end
    frame.GetObjectType = function() return "Frame" end
    frame.IsShown = function() return true end
    frame.IsVisible = function() return true end
    frame.GetChecked = function() return false end
    frame.SetChecked = function() end
    -- The UIPanelScrollFrameTemplate methods the options panel uses.
    frame.GetID = function() return 1 end
    frame.GetScrollChild = function() return nil end
    frame.GetVerticalScroll = function() return 0 end
    frame.SetVerticalScroll = function() end
    frame.UpdateScrollChildRect = function() end
    frame.SetScrollChild = function() end
    return frame
end

-- ----------------------------------------------------------------------------
-- The environment
-- ----------------------------------------------------------------------------
-- options:
--   project     WOW_PROJECT_ID (2 classic, 5 tbc, 11 titan, 18 forever, 1 retail)
--   interface   the client interface number, for the 16001 Forever fallback
--   restricted  force the restricted-combat path on/off (default: derived)
--   hasCVar     function(name) -> boolean, to model a client's CVar set
--   probe       "function" | "absent" | "raising" | "nonboolean"
--   spellInfo   function(id) -> table|nil
-- Publishes the named child frames the options panel looks up. "Text" and the
-- slider's "Low"/"High" are FontStrings; the rest are frames. The client
-- creates every named frame as a global, so the stub has to as well.
local function publishParts(env, realName, parent)
    for _, suffix in ipairs({ "Text", "Low", "High" }) do
        if (env[realName .. suffix] == nil) then
            env[realName .. suffix] = makeFontString(parent)
        end
    end
    for _, suffix in ipairs({ "Left", "Middle", "Right", "ScrollBarScrollUpButton",
        "ScrollBarScrollDownButton", "ScrollBar" }) do
        if (env[realName .. suffix] == nil) then
            env[realName .. suffix] = makeFrame(env)
        end
    end
end

function M.newEnv(options)
    options = options or {}
    local env = setmetatable({}, { __index = _G })
    env._G = env

    local project = options.project or 2
    local interface = options.interface or 11509
    local isLegacy = (project == 2) or (project == 5) or (project == 11)
    local restricted = options.restricted
    if restricted == nil then
        restricted = (not isLegacy) or (interface == 16001)
    end

    env.WOW_PROJECT_ID = project
    env.WOW_PROJECT_CLASSIC = 2
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    env.WOW_PROJECT_MAINLINE = 1
    env.WOW_PROJECT_WRATH_CLASSIC = 11
    env.WOW_PROJECT_CAMELOT = 18
    env.GetBuildInfo = function() return "1.0", "0", "0", interface end

    -- The client creates every named frame as a global. The options panel
    -- looks its parts up by name ("<name>Middle", "<name>ScrollBarScrollUpButton"),
    -- so a frame that gets a name must also publish the named children the
    -- panel expects.
    local frameCounter = 0
    env.CreateFrame = function(frameType, name, parent, template) -- luacheck: ignore 212
        local f = makeFrame(env)
        frameCounter = frameCounter + 1
        local realName = name or ("FCTFrame" .. frameCounter)
        f.GetName = function() return realName end
        f.__name = realName
        publishParts(env, realName, f)
        if (env[realName] == nil) then env[realName] = f end
        return f
    end
    env.UIParent = makeFrame(env)
    env.WorldFrame = makeFrame(env)

    env.C_NamePlate = {
        GetNamePlateForUnit = function() return nil end,
        GetNamePlates = function() return {} end,
    }
    env.C_AddOns = { GetAddOnMetadata = function() return "M0.89" end }
    env.GetAddOnMetadata = function() return "M0.89" end
    env.C_Timer = { After = function(_, fn) if fn then fn() end end }
    env.C_Spell = { GetSpellInfo = function(id)
        return { name = "Stub " .. tostring(id), iconID = 12345, spellID = id }
    end }
    env.C_CombatLog = { GetCurrentEventInfo = function() return nil end }

    -- The clock is mutable: main.lua captures GetTime into a local at load
    -- time, so replacing env.GetTime later would have no effect. The stub
    -- therefore reads a variable the test can advance.
    local CLOCK = { now = 100 }
    env.__clock = CLOCK
    env.GetTime = function() return CLOCK.now end
    env.InCombatLockdown = function() return false end
    env.AbbreviateNumbers = tostring
    env.UnitGUID = function(u) return (u == "player") and "Player-1" or "Target-1" end
    env.UnitExists = function() return false end
    env.UnitHealth = function() return 100 end
    env.UnitHealthMax = function() return 100 end
    env.UnitClassBase = function() return "MAGE" end
    env.GetNumClasses = function() return 13 end
    env.GetClassInfo = function(i) return "Class" .. i, "CLASS" .. i end
    env.GetLocale = function() return "enUS" end
    env.IsShiftKeyDown = function() return false end
    env.IsControlKeyDown = function() return false end
    env.IsModifierKeyDown = function() return false end
    -- `wipe` and `strsplit` are WoW client globals, not Lua ones. A stock
    -- PUC Lua has neither, so assigning them directly would silently put nil
    -- in the environment.
    env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    env.strsplit = function(sep, str)
        local out = {}
        for piece in string.gmatch(str, "([^" .. sep .. "]+)") do out[#out + 1] = piece end
        return unpack(out)
    end
    env.sqrt = math.sqrt
    env.min = math.min
    env.max = math.max
    env.floor = math.floor
    env.sin = math.sin
    env.cos = math.cos
    env.asin = math.asin
    env.acos = math.acos
    env.random = math.random
    env.select = select
    env.pairs = pairs
    env.ipairs = ipairs
    env.unpack = unpack
    env.strlower = string.lower
    env.strupper = string.upper
    env.format = string.format
    env.gsub = string.gsub
    env.strsub = string.sub
    env.strlen = string.len
    env.tinsert = table.insert
    env.tremove = table.remove
    env.sort = table.sort
    env.abs = math.abs
    env.StrictColor = function() end
    env.bit = { band = function(a, b)
        local res, bitval = 0, 1
        while a > 0 and b > 0 do
            if a % 2 == 1 and b % 2 == 1 then res = res + bitval end
            a = math.floor(a / 2); b = math.floor(b / 2); bitval = bitval * 2
        end
        return res
    end }
    env.Enum = {
        CombatLogObject = { TypeGuardian = 8, TypePet = 16, AffiliationMine = 1, TypeNpc = 4, TypePlayer = 1 },
        Damageclass = {
            MaskNone = 0, MaskPhysical = 1, MaskHoly = 2, MaskFire = 4, MaskNature = 8,
            MaskFrost = 16, MaskShadow = 32, MaskArcane = 64, MaskChaos = 128,
            MaskDivine = 256, MaskElemental = 512, MaskMagical = 1024, MaskChromatic = 2048,
            MaskSpellfire = 4096, MaskSpellfrost = 8192, MaskSpellshadow = 16384,
            MaskFirestorm = 32768, MaskFroststorm = 65536, MaskHolyfire = 131072,
            MaskFrostfire = 262144, MaskShadowflame = 524288, MaskFroststrike = 1048576,
            MaskHolystrike = 2097152, MaskHolystorm = 4194304, MaskSpellstorm = 8388608,
            MaskTwilight = 16777216, MaskFlamestrike = 33554432, MaskSpellstrike = 67108864,
            MaskStormstrike = 134217728, MaskShadowstorm = 268435456, MaskShadowstrike = 536870912,
            MaskShadowfrost = 1073741824, MaskHolystorm2 = 0, MaskHolyfrost = 0, MaskFroststrike2 = 0,
        },
    }
    env.SCHOOL_MASK_PHYSICAL = 1
    env.GetCVarDefault = function(name)
        if options.hasCVar and options.hasCVar(name) then return "1" end
        return nil
    end
    env.GetCVar = function() return "1" end
    env.SetCVar = function() end

    -- The secret-value probe, in the four states the audit has to cover.
    local probeMode = options.probe or "function"
    if probeMode == "absent" then
        env.issecretvalue = nil
    elseif probeMode == "raising" then
        env.issecretvalue = function() error("probe failed") end
    elseif probeMode == "nonboolean" then
        env.issecretvalue = function() return "yes" end
    else
        env.issecretvalue = function(v) return v == M.SECRET end
    end

    -- The vendored libraries (Libs\libs.xml) load first in the real .toc.
    -- Only config.lua's font dropdown needs LibSharedMedia, and only for the
    -- FONT LIST - so a light stub is enough for the behaviour tests, and the
    -- real libraries are exercised by the release gate's load check.
    env.LibStub = function(name)
        if name == "LibSharedMedia-3.0" then
            return {
                List = function() return { "Fonts\\FRIZQT__.TTF" } end,
                Fetch = function(_, key) return key end,
                RegisterCallback = function() end,
                UnregisterCallback = function() end,
                MediaType = "Font",
                DefaultMedia = "Fonts\\FRIZQT__.TTF",
                HashTable = function(t) return t end,
            }
        end
        return nil
    end

    -- The options panel: the addon builds its whole UI at load time, so the
    -- stub has to provide the client frames the panel is built from.
    env.StaticPopupDialogs = {}
    env.StaticPopup_Show = function() end
    env.UIDropDownMenu_CreateInfo = function() return { } end
    env.UIDropDownMenu_AddButton = function() end
    env.UIDropDownMenu_SetSelectedValue = function() end
    env.DropDownList1 = makeFrame(env)
    env.ColorPickerFrame = makeFrame(env)
    env.OpacitySliderFrame = makeFrame(env)
    env.GameFontHighlightSmall = "font"
    env.GameFontNormalLarge = "font"
    env.GameFontNormal = "font"
    env.GameFontHighlight = "font"
    -- CreateFont returns a font object the options panel writes to.
    env.CreateFont = function()
        local f = {}
        local noop = function() end
        for _, m in ipairs({ "SetFont", "SetText", "SetTextColor", "SetPoint",
            "SetJustifyH", "SetHeight", "SetWidth", "SetFontObject", "SetAlpha" }) do f[m] = noop end
        f.GetStringWidth = function() return 20 end
        f.GetStringHeight = function() return 12 end
        f.GetName = function() return "FCTFont" end
        return f
    end
    env.InterfaceOptions_AddCategory = function() return {} end
    env.InterfaceOptionsFrame_OpenToCategory = function() end
    -- The Settings API returns category objects; the options panel reads
    -- GetID() off them.
    local function category()
        local c = {}
        c.GetID = function() return 1 end
        c.ID = 1
        c.SetName = function() end
        c.RegisterCallback = function() end
        c.UnregisterCallback = function() end
        return c
    end
    env.Settings = {
        RegisterCanvasLayoutCategory = function() return category() end,
        RegisterAddOnCategory = function() return category() end,
        RegisterCanvasLayoutSubcategory = function() return category() end,
        GetCategory = function() return category() end,
        OpenToCategory = function() end,
    }
    env.SlashCmdList = {}
    env.SLASH_CLASSICFCT1 = "CLASSICFCT"
    env.SLASH_CLASSICFCTFS1 = "CLASSICFCTFS"

    env.SetScript = env.SetScript
    env.print = print
    env.PlaySound = function() end
    env.SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1, IG_MAINMENU_OPTION_CHECKBOX_OFF = 2 }
    env.GetSpellInfo = options.spellInfo or function(id)
        return "Stub " .. tostring(id), nil, 12345, 0, 0, 0, id, 12345
    end

    env.__harness = { restricted = restricted, isLegacy = isLegacy, project = project }
    return env
end

-- ----------------------------------------------------------------------------
-- A realistic configuration
-- ----------------------------------------------------------------------------
-- The dispatcher reads CFCT.Config[cat] for every category, so a stub that
-- only provides a bare config makes every event fail with "attempt to perform
-- arithmetic on local 'aspectRatio'". The category list is derived from
-- config.lua's HEADER_TEXT so this cannot drift from the source.
M.CATEGORIES = (function()
    local cats = {}
    local fh = io.open("config.lua", "rb")
    if not fh then return { "auto", "spell", "heal" } end
    local text = fh:read("*a"); fh:close()
    local inBlock = false
    for line in text:gmatch("[^\n]+") do
        if line:find("local HEADER_TEXT") then inBlock = true
        elseif inBlock and line:find("^}") then inBlock = false
        elseif inBlock then
            local k = line:match("^%s*([%a_]+)%s*=")
            if k then cats[#cats+1] = k end
        end
    end
    if #cats == 0 then return { "auto", "spell", "heal" } end
    return cats
end)()

-- Builds a config with every category present, so the dispatch path runs.
function M.makeConfig(overrides)
    local cfg = {
        animDuration = 1.5,
        maxDisplayed = 0,
        mergeEvents = false,
        mergeEventsCounter = false,
        mergeEventsByGuid = false,
        mergeEventsBySpellID = false,
        mergeEventsBySpellIcon = false,
        mergeEventsBySchool = false,
        mergeEventsInterval = 0.1,
        mergeEventsIntervalOverrides = {},
        mergeEventsMisses = false,
        preventOverlap = false,
        sortByDamage = false,
        sortMissPrio = false,
        attachMode = "sc",
        perspectiveScale = true,
        areaX = 0, areaY = 0, areaNX = 0, areaNY = 0,
        showIcons = false,
        abbreviateNumbers = false,
        kiloSeparator = false,
        filterSpellBlacklist = {},
        filterMissesEnabled = false,
        filterAbsoluteEnabled = false,
        filterRelativeEnabled = false,
        filterAverageEnabled = false,
        demoteSmallCritsEnabled = false,
        demoteSmallCritThreshold = 0,
        colorByType = false,
        colorTableDotEnabled = false,
        colorTable = {},
        colorTableDot = {},
        -- The spell-icon geometry is read from the top level of the config.
        spellIconAspectRatio = 1,
        spellIconZoom = 1,
        spellIconOffsetX = 0,
        spellIconOffsetY = 0,
    }
    for _, cat in ipairs(M.CATEGORIES) do
        cfg[cat] = {
            enabled = true,
            fontSize = 12,
            showIcons = false,
            colorByType = false,
            fontColor = "FFFFFFFF",
            fontPath = "Fonts\\FRIZQT__.TTF",
            missStyle = { enabled = false },
            Pow = { enabled = false },
            FadeIn = { enabled = false },
            FadeOut = { enabled = false },
            Scroll = { enabled = false },
        }
    end
    if overrides then
        for k, v in pairs(overrides) do cfg[k] = v end
    end
    return cfg
end

-- ----------------------------------------------------------------------------
-- Loading the addon
-- ----------------------------------------------------------------------------
-- Builds a CFCT table the way the real addon expects, loads main.lua (and
-- optionally config.lua) into the environment, and returns both.
function M.load(options)
    options = options or {}
    local env = M.newEnv(options)

    local CFCT = { _log = {}, _testMode = false }
    CFCT.Log = function(self, msg) table.insert(self._log, msg or "") end
    CFCT.L = function(key, ...) return key end -- luacheck: ignore 212
    CFCT.Config = M.makeConfig(options.config)
    CFCT.ConfigPanel = { IsVisible = function() return false end }

    local chunk = assert(loadfile(options.file or "main.lua"))
    setfenv(chunk, env)
    local ok, err = pcall(chunk, "ClassicFCT", CFCT)
    if not ok then return nil, err, env, CFCT end

    if options.loadConfig then
        local cfg = assert(loadfile("config.lua"))
        setfenv(cfg, env)
        local cfgOk, cfgErr = pcall(cfg, "ClassicFCT", CFCT)
        if not cfgOk then return nil, cfgErr, env, CFCT end
    end

    if options.presets then
        -- The preset files are what carry the file-scope Enum.Damageclass
        -- lookups, so loading them is the check that they cannot raise.
        for _, p in ipairs(options.presets) do
            local pc = assert(loadfile(p))
            setfenv(pc, env)
            local pok, perr = pcall(pc, "ClassicFCT", CFCT)
            if not pok then return nil, perr, env, CFCT end
        end
    end

    return CFCT, nil, env, CFCT
end

-- ----------------------------------------------------------------------------
-- Driving the combat log
-- ----------------------------------------------------------------------------
-- Builds a CLEU payload. The argument order is the classic one, verified
-- against Blizzard's own parser (Blizzard_CombatLog.lua on every branch):
--   1 timestamp  2 event  3 hideCaster  4 sourceGUID  5 sourceName
--   6 sourceFlags  7 sourceRaidFlags  8 destGUID  9 destName
--   10 destFlags  11 destRaidFlags  12.. event specific
function M.cleuPayload(event, sourceGUID, destGUID, extra)
    local p = {
        100, event, false, sourceGUID or "Player-1", "Source", 1, 0,
        destGUID or "Target-1", "Dest", 2, 0,
    }
    -- The event-specific values start at arg12. Fill every slot so the
    -- positional mapping is exact: a missing slot would shift everything
    -- after it and silently corrupt the payload.
    --
    -- A `false` value is preserved rather than replaced by 0: the crit flag
    -- is a BOOLEAN on every supported client, and `false or 0` would quietly
    -- turn it into the number 0, which is TRUTHY in Lua.
    for i = 12, 25 do
        local v = extra and extra[i - 11]
        if v == nil then v = 0 end
        p[i] = v
    end
    return p
end

-- Installs a payload as the client's combat-log source.
function M.setCLEU(env, payload)
    -- The addon resolves the combat-log API ONCE and caches the function
    -- reference, so the stub has to hand out a function that reads a
    -- MUTABLE payload. Replacing env.CombatLogGetCurrentEventInfo after the
    -- first event would have no effect, and every event would replay the
    -- first payload.
    env.__cleuPayload = payload
    if (not env.__cleuFn) then
        local fn = function() return unpack(env.__cleuPayload) end
        env.__cleuFn = fn
        env.CombatLogGetCurrentEventInfo = fn
        env.C_CombatLog = { GetCurrentEventInfo = fn }
    end
    env.__cleuPayload = payload
end

-- Fires the CLEU event through the addon's own event frame.
function M.fireCLEU(CFCT)
    local frame = CFCT.frame
    local onEvent = frame.scripts and frame.scripts.OnEvent
    if not onEvent then return false, "no OnEvent script" end
    return pcall(onEvent, frame, "COMBAT_LOG_EVENT_UNFILTERED")
end

-- Fires the addon's OnUpdate, advancing a mutable clock.
function M.tick(CFCT, env, elapsed)
    if env.__clock then env.__clock.now = env.__clock.now + (elapsed or 0.1) end
    local frame = CFCT.frame
    local onUpdate = frame.scripts and frame.scripts.OnUpdate
    if not onUpdate then return false, "no OnUpdate script" end
    return pcall(onUpdate, frame, elapsed or 0.1)
end

-- Counts the live numbers.
function M.liveCount(CFCT)
    local n = 0
    for _ in pairs(CFCT.Animating or {}) do n = n + 1 end
    return n
end

-- Collects the text of every live number.
function M.liveTexts(CFCT)
    local out = {}
    for _, frame in pairs(CFCT.Animating or {}) do
        local st = frame.state
        out[#out + 1] = st and st.text or "?"
    end
    return out
end

return M
