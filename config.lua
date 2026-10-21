local addonName, CFCT = ...
local L = CFCT.L
local function noop() end
-- The imports are split over two statements purely for line length; the name
-- list and the value list are identical, in the same order.
local tinsert, format, strlen, strsub, gsub, floor, min, max = table.insert, string.format, string.len, string.sub, string.gsub, math.floor, math.min, math.max
local select, pairs, ipairs = select, pairs, ipairs

local GetSpellInfo_old = GetSpellInfo
-- Total shim, for the same reason as main.lua's: it returns an empty table
-- rather than raising if neither spell-info API is available.
local GetSpellInfo = (type(GetSpellInfo_old) == 'function') and function(id)
    local name, rank, icon, castTime, minRange, maxRange, spellID, originalIcon = GetSpellInfo_old(id)
    return {
        name = name,
        rank = rank,
        iconID = icon,
        originalIconID = originalIcon,
        castTime = castTime,
        minRange = minRange,
        maxRange = maxRange,
        spellID = spellID
    }
end or ((type(C_Spell) == 'table' and type(C_Spell.GetSpellInfo) == 'function') and C_Spell.GetSpellInfo
    or function() return {} end)

-- Restricted-combat clients (Retail/Midnight, WoW Forever, unrecognised IDs) cannot feed this
-- addon: keep the UI from hiding Blizzard's own combat text while the addon cannot replace it.
--
-- MATCHED PAIR -- keep in sync with main.lua:7-19 (the runtime half of the same predicate).
-- Both halves must be derived from the SAME two inputs: the project ID and the build's
-- interface version. main.lua:13 treats interface 16001 as WoW Forever, so a legacy project
-- ID shipping that interface is restricted there; deriving the flag from the project ID
-- alone (as this file used to) would let the two halves disagree, and the checkbox handler
-- below would then suppress Blizzard's combat text on a client where the addon produces none.
-- Do NOT try to share the implementation in a new file: every .toc load list is owned
-- elsewhere, and adding a shared module would change all five of them.
local _legacyProjects = { [2] = true, [5] = true, [11] = true } -- Classic, TBC, Wrath (incl. Titan)
local _tocVersion = (type(GetBuildInfo) == "function") and select(4, GetBuildInfo()) or 0
-- Equivalent to main.lua's `IsRetail or IsWoWForever or not IsLegacyClient`:
--   not _legacyProjects[project]  ==  not IsLegacyClient  (project not in {2,5,11})
--   project == 1 (Retail) and project == 18 (Camelot) are both outside {2,5,11}
--   _tocVersion == 16001          ==  the WoW Forever interface check
-- Unknown project IDs stay restricted (fail closed).
local IsRestrictedCombat = (not _legacyProjects[WOW_PROJECT_ID or 0]) or (_tocVersion == 16001)

-- Combat-text CVar names. The un-suffixed names ("floatingCombatTextCombatDamage") do not
-- exist on any supported client; the shipped names are the "_v2" variants (verified in
-- /home/sam/wow-ui-source: Blizzard_SettingsDefinitions_Frame/Classic/CombatOverrides.lua:117
-- and :135 on classic_era / classic_anniversary / classic_titan). Resolve at runtime instead
-- of assuming either spelling: prefer "_v2", fall back to the un-suffixed name, and treat
-- "neither exists" as "the feature is unavailable".
--
-- CROSS-FILE CONTRACT (config.lua <-> main.lua): config.lua loads BEFORE main.lua in every
-- .toc, so this is the only place both files can read the resolution from. main.lua MUST
-- read CFCT.CVarDamage / CFCT.CVarHealing from here and MUST NOT resolve the names again -
-- if the two halves resolve differently, the options panel and the runtime disagree about
-- whether Blizzard's combat text can be toggled.
--
-- Never hide Blizzard's combat text when the CVar cannot be found: we could not restore it.
local function ResolveCVar(base)
    if (GetCVarDefault(base .. "_v2") ~= nil) then return base .. "_v2" end
    if (GetCVarDefault(base) ~= nil) then return base end
    return nil
end
local CVarDamage = ResolveCVar("floatingCombatTextCombatDamage")
local CVarHealing = ResolveCVar("floatingCombatTextCombatHealing")
CFCT.CVarDamage = CVarDamage
CFCT.CVarHealing = CVarHealing

local UsesNewSettingsInterface = (Settings and (type(Settings.RegisterAddOnCategory) == 'function'))
local UsesNewColorPicker = OpacitySliderFrame == nil or ((type(OpacitySliderFrame.GetParent) == 'function') and OpacitySliderFrame:GetParent():GetName() ~= "ColorPickerFrame")
local DefaultPresets = CFCT:GetDefaultPresets()
local DefaultConfig = DefaultPresets["Mists of Pandaria"]
if (type(DefaultConfig) ~= 'table') then
    -- The ENTIRE config schema (every migration default and every widget default) is this
    -- one preset table. Name the failed preset here, where the failure is, instead of dying
    -- much later inside the config UI builder with an unrelated error. The preset name and
    -- the load order are load-bearing - see AGENTS.md "Load order".
    print("ClassicFCT: built-in preset \"Mists of Pandaria\" is missing - the config schema cannot be loaded.")
end
local DefaultVars = {
    enabled = true,
    hideBlizz = true,
    hideBlizzHeals = true,
    forceCVars = true,
    characterSpecificConfig = false,
    selectedPreset = "",
    lastVersion = ""
}
local DefaultCharVars = {
    enabled = true,
    hideBlizz = true,
    hideBlizzHeals = true,
    forceCVars = true,
    selectedPreset = "",
}
local DefaultTables = {
    mergeEventsIntervalOverrides = {},
    filterSpellBlacklist = {}
}
local ClassSpecificTables = {
    mergeEventsIntervalOverrides = true,
    filterSpellBlacklist = true
}
for i=1,GetNumClasses(),1 do
    local class = select(2, GetClassInfo(i))
    if (class) then
        for k,v in pairs(ClassSpecificTables) do
            if v then
                DefaultTables[k][class] = {}
            end
        end
    end
end

local DefaultCharTables = {
    mergeEventsIntervalOverrides = {},
    filterSpellBlacklist = {}
}

local AnimationDefaults = {
    Pow = {
        enabled = false,
        initScale = 0.25,
        midScale = 1.55,
        endScale = 1,
        duration = 0.3,
        inOutRatio = 0.7,
        overshoot = 0,
        settleRatio = 0.25
    },
    FadeIn = {
        enabled = false,
        duration = 0.07
    },
    FadeOut = {
        enabled = false,
        duration = 0.3
    },
    Scroll = {
        enabled = false,
        direction = "UP",
        distance = 32
    }
}

local function SetValue(path, value)
    local chain = { strsplit(".", path) }
    local depth = #chain
    local temp = CFCT
    for d, k in ipairs(chain) do
        if (d == depth) then
            -- A table value is assigned wholesale. The old code first copied the
            -- table's members into temp[k] and then overwrote temp[k] with the
            -- whole table, so the copy was discarded - it could only ever raise
            -- ("attempt to index a nil value") when temp[k] was not already a
            -- table. Assigning directly is behaviour-identical for every
            -- reachable value and removes the latent crash.
            temp[k] = value
            return true
        end
        temp = temp[k]
    end
    return false
end

local function GetValue(path)
    local chain = { strsplit(".", path) }
    local depth = #chain
    local temp = CFCT
    for d, k in ipairs(chain) do
        if (d == depth) then
            return temp[k]
        end
        temp = temp[k]
    end
end




local function UpdateTable(dest, source, template, overwrite)
    assert((type(dest) == 'table'), "UpdateTable: dest is not a table")
    assert((type(source) == 'table'), "UpdateTable: source is not a table")
    assert((type(template) == 'table'), "UpdateTable: template is not a table")
    local verbose = (CFCT.debug == true)
    if verbose then CFCT:Log("UpdateTable("..type(dest)..", "..type(source)..", "..type(template)..", "..tostring(overwrite)) end
    for k, t in pairs(template) do
        if verbose then CFCT:Log("["..tostring(k).."] dest("..tostring(dest[k])..") source("..tostring(source[k])..")") end
        if (type(t) == 'table') then
            if verbose then CFCT:Log("table "..tostring(k)) end
            dest[k] = (type(dest[k]) == 'table') and dest[k] or {}
            -- A missing key in the source is not an error: the template default
            -- is used, exactly like the scalar branch below. The old code
            -- asserted here, so a partially populated source crashed the whole
            -- merge instead of falling back to the default.
            UpdateTable(dest[k], (type(source[k]) == 'table') and source[k] or {}, t, overwrite)
        elseif ((type(t) ~= type(dest[k])) or (dest[k] == nil) or (overwrite and (dest[k] ~= source[k]))) then
            -- Explicit branch: the `and/or` idiom loses the default when `t` is false and
            -- `source[k]` is nil (false and nil are the only falsy values, so `(true and
            -- false) or nil` collapses to nil and the key never appears). Behaviour is
            -- unchanged for every other combination.
            --
            -- A FUNCTION value is never copied. It is not data, the client cannot
            -- serialise it, and a table that carried one either lost the whole
            -- SavedVariable or lost the function - silently (HF-04). The
            -- destination is left exactly as it is in that case.
            if (source[k] == nil) then
                if (type(t) ~= 'function') then
                    dest[k] = t
                end
            elseif (type(source[k]) ~= 'function') then
                dest[k] = source[k]
            end
            if verbose then CFCT:Log("write ("..tostring(source[k])..((source[k] == nil) and "  |> " or " <|  ")..tostring(t)..")") end
        end
    end
end
local function AttachTables(dest, source, template)
    local class = UnitClassBase('player')
    for k, t in pairs(template) do
        if (ClassSpecificTables[k] == true) then
            if source[k] == nil then source[k] = {} end
            if source[k][class] == nil then source[k][class] = {} end
            -- print("AttachTable", k, dest[k], class, source[k][class])
            dest[k] = source[k][class]
        else
            if source[k] == nil then source[k] = t or {} end
            -- print("AttachTable", k, dest[k], source[k])
            dest[k] = source[k]
        end
    end
end

CFCT._log = {}
-- The coloured addon prefix is added HERE. A caller must pass the bare
-- message: repeating "ClassicFCT: " in the message text prints the prefix
-- twice ("ClassicFCT: ClassicFCT: ..."), which is what every diagnostic in
-- main.lua used to do. tools/behavior-tests.lua asserts the prefix is not
-- repeated (see the secret-value probe checks).
function CFCT:Log(msg)
    msg = "|cffffff00ClassicFCT: |r|cffffff80"..(msg or "").."|r"
    print(msg)
    tinsert(self._log, msg)
end
function CFCT:DumpLog(n)
    local c = #self._log
    if (type(n) ~= 'number') or (n <= 0) then return "Invalid Log Range" end
    if (c <= 0) then return "Invalid Log Range" end
    n = floor(n)
    if (n > c) then n = c end
    -- Lua 5.1 table.concat(list, sep, i, j) is inclusive of j, so the last n entries
    -- start at c - n + 1. The old call passed (c - n, n), which concatenated the wrong
    -- slice (empty when n <= c/2, the middle of the log otherwise).
    return table.concat(self._log, "\n", c - n + 1, c)
end


--Input Popup Box
StaticPopupDialogs["CLASSICFCT_POPUPDIALOG"] = {
    text = "POPUPDIALOG_TITLE",
    button1 = L("OK"),
    button2 = L("Cancel"),
    OnShow = function() end,
    OnAccept = function() end,
    EditBoxOnEnterPressed = function() end,
    hasEditBox = true,
    timeout = 0,
    exclusive = true,
    hideOnEscape = true
}

function CFCT:ShowInputBox(title, default, OnAccept)
    noop(self)
    local pd = StaticPopupDialogs["CLASSICFCT_POPUPDIALOG"]
    pd.hasEditBox = true
    pd.text = title
    pd.OnShow = function(dialog) dialog.editBox:SetText(default) end
    pd.OnAccept = function(dialog) OnAccept(dialog.editBox:GetText()) end
    pd.EditBoxOnEnterPressed = function(editBox) OnAccept(editBox:GetText()) editBox:GetParent():Hide() end
    StaticPopup_Show("CLASSICFCT_POPUPDIALOG")
end

function CFCT:ConfirmAction(title, OnAccept)
    noop(self)
    local pd = StaticPopupDialogs["CLASSICFCT_POPUPDIALOG"]
    pd.hasEditBox = false
    pd.text = title
    pd.OnShow = function() end
    pd.OnAccept = function() OnAccept() end
    pd.EditBoxOnEnterPressed = function() end
    StaticPopup_Show("CLASSICFCT_POPUPDIALOG")
end

-- The default for "Max Simultaneous Numbers" was "unlimited" (0) and is now a
-- fixed 20, because an unlimited number of numbers fills the screen and makes
-- every other setting unreadable. A profile that still holds one of the OLD
-- defaults is moved to the new one. A value the user chose themselves is left
-- alone: only the defaults are migrated, never a deliberate setting.
local OLD_MAX_DISPLAYED_DEFAULTS = { [0] = true, [60] = true }
local function MigrateMaxDisplayed(config)
    if (type(config) ~= "table") then return false end
    local value = config.maxDisplayed
    if (type(value) ~= "number") then return false end
    if (not OLD_MAX_DISPLAYED_DEFAULTS[value]) then return false end
    config.maxDisplayed = DefaultConfig.maxDisplayed
    return true
end

CFCT.ConfigPanels = {}
CFCT.Presets = {}
CFCT.Config = {
    OnLoad = function(self)
        ClassicFCTCustomPresets = ClassicFCTCustomPresets or {}
        UpdateTable(CFCT.Presets, ClassicFCTCustomPresets, ClassicFCTCustomPresets, true)
        UpdateTable(CFCT.Presets, DefaultPresets, DefaultPresets, true)

        ClassicFCTVars = ClassicFCTVars or {}
        UpdateTable(ClassicFCTVars, DefaultVars, DefaultVars)
        UpdateTable(CFCT, ClassicFCTVars, DefaultVars, true)

        if (not CFCT.characterSpecificConfig) then
            -- print("Loading Global")
            ClassicFCTConfig = ClassicFCTConfig or {}
            UpdateTable(ClassicFCTConfig, DefaultConfig, DefaultConfig)
            UpdateTable(self, ClassicFCTConfig, DefaultConfig, true)

            ClassicFCTTables = ClassicFCTTables or {}
            UpdateTable(ClassicFCTTables, DefaultTables, DefaultTables)
            AttachTables(self, ClassicFCTTables, DefaultTables)
        else
            -- print("Loading Character")
            ClassicFCTCharVars = ClassicFCTCharVars or {}
            UpdateTable(ClassicFCTCharVars, DefaultCharVars, DefaultCharVars)
            UpdateTable(CFCT, ClassicFCTCharVars, DefaultCharVars, true)

            ClassicFCTCharConfig = ClassicFCTCharConfig or {}
            UpdateTable(ClassicFCTCharConfig, DefaultConfig, DefaultConfig)
            UpdateTable(self, ClassicFCTCharConfig, DefaultConfig, true)

            ClassicFCTCharTables = ClassicFCTCharTables or {}
            UpdateTable(ClassicFCTCharTables, DefaultCharTables, DefaultCharTables)
            AttachTables(self, ClassicFCTCharTables, DefaultCharTables)
        end

        -- The version-gated migration. It runs when the stored version differs
        -- from the running one, which is an upgrade, and only moves a value
        -- that is still one of the old defaults.
        local runningVersion = GetAddOnMetadata(addonName, "Version")
        if (runningVersion and CFCT.lastVersion and (runningVersion ~= CFCT.lastVersion)) then
            if MigrateMaxDisplayed(self) then
                -- Write the migrated value back into the store it came from, so
                -- it survives the next save.
                if (not CFCT.characterSpecificConfig) then
                    if (type(ClassicFCTConfig) == "table") then
                        ClassicFCTConfig.maxDisplayed = DefaultConfig.maxDisplayed
                    end
                else
                    if (type(ClassicFCTCharConfig) == "table") then
                        ClassicFCTCharConfig.maxDisplayed = DefaultConfig.maxDisplayed
                    end
                end
            end
        end
    end,
    OnSave = function(self)
        -- Only the genuinely CUSTOM presets are persisted. The built-ins ship
        -- with the addon and are rebuilt from DefaultPresets on every load, so
        -- writing them into the user's store would resurrect a renamed or
        -- removed built-in as a stale "custom" preset (HF-13).
        ClassicFCTCustomPresets = {}
        local customPresets = {}
        for presetName, preset in pairs(CFCT.Presets) do
            if (DefaultPresets[presetName] == nil) then
                customPresets[presetName] = preset
            end
        end
        UpdateTable(ClassicFCTCustomPresets, customPresets, customPresets, true)
        ClassicFCTVars.lastVersion = CFCT.lastVersion
        if (not CFCT.characterSpecificConfig) then
            -- print("Saving Global")
            UpdateTable(CFCT, ClassicFCTVars, DefaultVars)
            UpdateTable(ClassicFCTVars, CFCT, DefaultVars, true)

            UpdateTable(self, ClassicFCTConfig, DefaultConfig)
            UpdateTable(ClassicFCTConfig, self, DefaultConfig, true)
        else
            -- print("Saving Character")
            UpdateTable(CFCT, ClassicFCTCharVars, DefaultCharVars)
            UpdateTable(ClassicFCTCharVars, CFCT, DefaultCharVars, true)

            UpdateTable(self, ClassicFCTCharConfig, DefaultConfig)
            UpdateTable(ClassicFCTCharConfig, self, DefaultConfig, true)
        end
    end,
    LoadPreset = function(self, presetName)
        CFCT:ConfirmAction(L("This will overwrite your current configuration. Are you sure?"), function()
            if (CFCT.Presets[presetName] ~= nil) then
                UpdateTable(self, CFCT.Presets[presetName], CFCT.Presets[presetName], true)
                CFCT:Log(L("%s preset loaded.", presetName))
            elseif (DefaultPresets[presetName] ~= nil) then
                UpdateTable(self, DefaultPresets[presetName], DefaultPresets[presetName], true)
                CFCT:Log(L("%s preset loaded.", presetName))
            else
                -- The preset does not exist. The confirm dialog promised an
                -- overwrite and performed none, without a word (HF-05).
                CFCT:Log(L("the preset '%s' does not exist - nothing was loaded.", tostring(presetName)))
            end
            -- A preset can change the text strata, which live on the parent
            -- frame rather than in the persisted config.
            if (type(CFCT.ApplyTextStrata) == "function") then CFCT.ApplyTextStrata() end
            CFCT.ConfigPanel:refresh()
        end)
    end,
    SavePreset = function(self, presetName)
        noop(self)
        if (DefaultPresets[presetName] ~= nil) then
            -- Built-in presets are read-only. Say so instead of showing a confirm dialog
            -- that would silently do nothing.
            CFCT:Log("Built-in presets cannot be modified.")
        else
            CFCT:ConfirmAction(L("This will overwrite your the selected preset. Are you sure?"), function()
                if (CFCT.Presets[presetName] ~= nil) then
                    -- The SCHEMA (DefaultConfig) is the template, never CFCT.Config:
                    -- CFCT.Config holds the eleven preset methods, and UpdateTable
                    -- copies every non-table value it meets - functions included -
                    -- which is how eleven Lua function references used to reach
                    -- the ClassicFCTCustomPresets SavedVariable (HF-04).
                    UpdateTable(CFCT.Presets[presetName], CFCT.Config, DefaultConfig, true)
                    CFCT:Log(L("Config saved to %s preset.", presetName))
                else
                    -- The preset does not exist: the confirm dialog promised a
                    -- save and performed none, without a word (HF-05).
                    CFCT:Log(L("the preset '%s' does not exist - nothing was saved.", tostring(presetName)))
                end
            end)
        end
    end,
    NewPresetName = function(self, baseName)
        noop(self)
        for i=0, 10000, 1 do
            local name = format("%s%s", baseName, (i > 0) and tostring(i) or "")
            if (CFCT.Presets[name] == nil) then
                return name
            end
        end
    end,
    CreatePreset = function(self)
        local defaultName = self:NewPresetName(L("New preset"))
        CFCT:ShowInputBox(L("Preset Name"), defaultName, function(value)
            value = ((strlen(value) > 0) and value or defaultName)
            if (CFCT.Presets[value] == nil) then
                CFCT.Presets[value] = {}
                UpdateTable(CFCT.Presets[value], DefaultConfig, DefaultConfig)
                CFCT.selectedPreset = value
            else
                CFCT:Log(L("Preset %s already exists", value))
            end
            CFCT.ConfigPanel:refresh()
        end)
    end,
    CreatePresetCopy = function(self, presetName)
        local defaultName = self:NewPresetName(L("Copy of %s", presetName))
        CFCT:ShowInputBox(L("Preset Name"), defaultName, function(value)
            value = ((strlen(value) > 0) and value or defaultName)
            if (CFCT.Presets[value] == nil) then
                CFCT.Presets[value] = {}
                UpdateTable(CFCT.Presets[value], CFCT.Presets[presetName], CFCT.Presets[presetName])
                CFCT.selectedPreset = value
            else
                CFCT:Log(L("Preset %s already exists", value))
            end
            CFCT.ConfigPanel:refresh()
        end)
    end,
    RenamePreset = function(self, presetName)
        noop(self)
        if (DefaultPresets[presetName] ~= nil) then
            -- Built-in presets are read-only: renaming one would fork it into a duplicate
            -- custom preset and persist that duplicate into ClassicFCTCustomPresets.
            CFCT:Log("Built-in presets cannot be modified.")
        elseif (CFCT.Presets[presetName] == nil) then
            -- There is nothing to rename. The old code created an empty entry
            -- under the typed name and moved the selection to it, so the
            -- dropdown then showed a preset that did not exist (HF-05).
            CFCT:Log(L("the preset '%s' does not exist - nothing was renamed.", tostring(presetName)))
        else
            CFCT:ShowInputBox(L("Preset Name"), presetName, function(value)
                value = ((strlen(value) > 0) and value or presetName)
                if (CFCT.Presets[value] == nil) then
                    CFCT.Presets[value] = CFCT.Presets[presetName]
                    CFCT.Presets[presetName] = nil
                    CFCT.selectedPreset = value
                else
                    CFCT:Log(L("Preset %s already exists", value))
                end
                CFCT.ConfigPanel:refresh()
            end)
        end
    end,
    DeletePreset = function(self, presetName)
        noop(self)
        if (DefaultPresets[presetName] ~= nil) then
            -- Built-in presets are read-only: deleting one would remove it from
            -- CFCT.Presets and hide it from the dropdown until the next reload.
            CFCT:Log("Built-in presets cannot be modified.")
        else
            CFCT:ConfirmAction(L("This will delete the preset permanently. Are you sure?"), function()
                CFCT.Presets[presetName] = nil
                CFCT.ConfigPanel:refresh()
            end)
        end
    end,
    RestoreDefaults = function(self)
        UpdateTable(self, DefaultConfig, DefaultConfig, true)
        UpdateTable(CFCT, DefaultVars, DefaultVars, true)
        CFCT.ConfigPanel:refresh()
        CFCT:Log(L("Defaults restored."))
    end,
    Show = function(self)
        noop(self)
        if (UsesNewSettingsInterface) then
            Settings.OpenToCategory(CFCT.ConfigPanels[1].CategoryID)
        else
            InterfaceOptionsFrame_OpenToCategory(CFCT.ConfigPanels[1])
        end
    end
}

SLASH_CLASSICFCT1 = '/cfct'
-- WoW calls a slash handler as handler(msg). Neither command uses the text.
SlashCmdList['CLASSICFCT'] = function(msg) -- luacheck: ignore 212
    CFCT.Config:Show()
end
SLASH_CLASSICFCTFS1 = '/fs'
SlashCmdList['CLASSICFCTFS'] = function(msg) -- luacheck: ignore 212
    FrameStackTooltip_Toggle(0, 0, 0);
end

-- Latched once per session: a malformed colour in the configuration is a
-- configuration problem, not a reason to kill the combat text. Color2RGBA is
-- called from the render path, so a raise here used to abort the dispatch
-- loop and take every number on screen with it (HF-08).
local colorParseFailedLogged = false
function CFCT.Color2RGBA(color)
    local ok, r, g, b, a = pcall(function()
        return tonumber("0x"..strsub(color, 3, 4))/255,
               tonumber("0x"..strsub(color, 5, 6))/255,
               tonumber("0x"..strsub(color, 7, 8))/255,
               tonumber("0x"..strsub(color, 1, 2))/255
    end)
    if ok and r and g and b and a then
        return r, g, b, a
    end
    if not colorParseFailedLogged then
        colorParseFailedLogged = true
        if (type(CFCT.Log) == "function") then
            CFCT:Log(L("a colour value in the configuration could not be parsed - opaque white is used instead."))
        end
    end
    return 1, 1, 1, 1
end

function CFCT.RGBA2Color(r, g, b, a)
    return format("%02X%02X%02X%02X", floor(a*255+0.5), floor(r*255+0.5), floor(g*255+0.5), floor(b*255+0.5))
end


local function ValidateValue(rawVal, minVal, maxVal, step)
    local stepval = floor(rawVal / step) * step
    return min(max((((rawVal - stepval) >= (step / 2)) and stepval + step or stepval), minVal), maxVal)
end

local function WidgetConfigBridgeGet(self, default, ConfigPathOrFunc)
    if (type(ConfigPathOrFunc) == 'function') then
        return ConfigPathOrFunc(self, "Get", default)
    else
        local ret = GetValue(ConfigPathOrFunc)
        -- print("WidgetConfigBridgeGet", ConfigPathOrFunc, default, ret, (ret == nil) and default or ret)
        return (ret == nil) and default or ret -- value == default
    end
end

local function WidgetConfigBridgeSet(self, value, ConfigPathOrFunc)
    if (type(ConfigPathOrFunc) == 'function') then
        ConfigPathOrFunc(self, "Set", value)
    else
        SetValue(ConfigPathOrFunc, value)
    end
end

local AttachModesMenu = {
    {
        text = L("Screen Center"),
        value = "sc"
    },
    {
        text = L("Target Nameplate"),
        value = "tn"
    },
    {
        text = L("Every Nameplate"),
        value = "en"
    }
}
local MergeIntervalModeMenu = {
    {
        text = L("First Event"),
        value = "first"
    },
    {
        text = L("Last Event"),
        value = "last"
    }
}

local AnimationsMenu = {
    {
        text = L("Pow"),
        value = "Pow"
    },
    {
        text = L("Fade In"),
        value = "FadeIn"
    },
    {
        text = L("Fade Out"),
        value = "FadeOut"
    },
    {
        text = L("Scroll"),
        value = "Scroll"
    },
}

-- The menu tables used to carry a `Func` hook. Nothing ever read it: the
-- dropdown writes the picked value through WidgetConfigBridgeSet, and the
-- commented-out block in CreateDropDownMenu that would have called `Func` is
-- still commented out. The hook was dead code that looked live, so it is gone.
local FontStylesMenu = {
    {
        text = L("No Outline"),
        value = ""
    },
    {
        text = L("No Outline Monochrome"),
        value = "MONOCHROME"
    },
    {
        text = L("Outline"),
        value = "OUTLINE"
    },
    {
        text = L("Outline Monochrome"),
        value = "OUTLINE,MONOCHROME"
    },
    {
        text = L("Thick Outline"),
        value = "THICKOUTLINE"
    },
    {
        text = L("Thick Outline Monochrome"),
        value = "THICKOUTLINE,MONOCHROME"
    }
}

-- Global strings are supplied by the client at runtime; index _G directly so the
-- constants are not reported as undefined globals, and fall back to an English
-- label when a client/locale does not define them.
local function SchoolName(globalName, fallback)
    return _G[globalName] or fallback
end

local SCHOOL_NAMES = {
    -- Single Schools
    [Enum.Damageclass.MaskPhysical]	    = SchoolName("STRING_SCHOOL_PHYSICAL", "Physical"),
    [Enum.Damageclass.MaskHoly]		    = SchoolName("STRING_SCHOOL_HOLY", "Holy"),
    [Enum.Damageclass.MaskFire]		    = SchoolName("STRING_SCHOOL_FIRE", "Fire"),
    [Enum.Damageclass.MaskNature]	    = SchoolName("STRING_SCHOOL_NATURE", "Nature"),
    [Enum.Damageclass.MaskFrost]	    = SchoolName("STRING_SCHOOL_FROST", "Frost"),
    [Enum.Damageclass.MaskShadow]	    = SchoolName("STRING_SCHOOL_SHADOW", "Shadow"),
    [Enum.Damageclass.MaskArcane]	    = SchoolName("STRING_SCHOOL_ARCANE", "Arcane"),
    -- Physical and a Magical
    [Enum.Damageclass.MaskFlamestrike]	= SchoolName("STRING_SCHOOL_FLAMESTRIKE", "Flamestrike"),
    [Enum.Damageclass.MaskFroststrike]	= SchoolName("STRING_SCHOOL_FROSTSTRIKE", "Froststrike"),
    [Enum.Damageclass.MaskSpellstrike]	= SchoolName("STRING_SCHOOL_SPELLSTRIKE", "Spellstrike"),
    [Enum.Damageclass.MaskStormstrike]	= SchoolName("STRING_SCHOOL_STORMSTRIKE", "Stormstrike"),
    [Enum.Damageclass.MaskShadowstrike]	= SchoolName("STRING_SCHOOL_SHADOWSTRIKE", "Shadowstrike"),
    [Enum.Damageclass.MaskHolystrike]	= SchoolName("STRING_SCHOOL_HOLYSTRIKE", "Holystrike"),
    -- Two Magical Schools
    [Enum.Damageclass.MaskFrostfire]	= SchoolName("STRING_SCHOOL_FROSTFIRE", "Frostfire"),
    [Enum.Damageclass.MaskSpellfire]	= SchoolName("STRING_SCHOOL_SPELLFIRE", "Spellfire"),
    [Enum.Damageclass.MaskFirestorm]	= SchoolName("STRING_SCHOOL_FIRESTORM", "Firestorm"),
    [Enum.Damageclass.MaskShadowflame]	= SchoolName("STRING_SCHOOL_SHADOWFLAME", "Shadowflame"),
    [Enum.Damageclass.MaskHolyfire]		= SchoolName("STRING_SCHOOL_HOLYFIRE", "Holyfire"),
    [Enum.Damageclass.MaskSpellfrost]	= SchoolName("STRING_SCHOOL_SPELLFROST", "Spellfrost"),
    [Enum.Damageclass.MaskFroststorm]	= SchoolName("STRING_SCHOOL_FROSTSTORM", "Froststorm"),
    [Enum.Damageclass.MaskShadowfrost]	= SchoolName("STRING_SCHOOL_SHADOWFROST", "Shadowfrost"),
    [Enum.Damageclass.MaskHolyfrost]	= SchoolName("STRING_SCHOOL_HOLYFROST", "Holyfrost"),
    [Enum.Damageclass.MaskSpellstorm]	= SchoolName("STRING_SCHOOL_SPELLSTORM", "Spellstorm"),
    [Enum.Damageclass.MaskSpellshadow]	= SchoolName("STRING_SCHOOL_SPELLSHADOW", "Spellshadow"),
    [Enum.Damageclass.MaskDivine]		= SchoolName("STRING_SCHOOL_DIVINE", "Divine"),
    [Enum.Damageclass.MaskShadowstorm]	= SchoolName("STRING_SCHOOL_SHADOWSTORM", "Shadowstorm"),
    [Enum.Damageclass.MaskHolystorm]	= SchoolName("STRING_SCHOOL_HOLYSTORM", "Holystorm"),
    [Enum.Damageclass.MaskTwilight]	    = SchoolName("STRING_SCHOOL_SHADOWLIGHT", "Twilight"),
    -- Three or more schools
    [Enum.Damageclass.MaskElemental]	= SchoolName("STRING_SCHOOL_ELEMENTAL", "Elemental"),
    [Enum.Damageclass.MaskChromatic]    = SchoolName("STRING_SCHOOL_CHROMATIC", "Chromatic"),
    [Enum.Damageclass.MaskMagical]      = SchoolName("STRING_SCHOOL_MAGIC", "Magical"),
    [Enum.Damageclass.MaskChaos]        = SchoolName("STRING_SCHOOL_CHAOS", "Chaos")
}

function ShowColorPicker(parentFrame, r, g, b, a, changedCallback)
    --show color picker
    ColorPickerFrame:Hide()
    ColorPickerFrame:SetFrameStrata("FULLSCREEN_DIALOG")

    if (parentFrame) then
        ColorPickerFrame:SetFrameLevel(parentFrame:GetFrameLevel() + 10)
    end
    local flip_alpha = not UsesNewColorPicker
    local function fix_alpha(src_alpha)
        return (flip_alpha and (1 - src_alpha)) or src_alpha
    end
    ColorPickerFrame:SetupColorPickerAndShow({
        hasOpacity = true,
        r = r, g = g, b = b,
        opacity = fix_alpha(a),
        extraInfo = nil,
        opacityFunc = function()
            local cr, cg, cb = ColorPickerFrame:GetColorRGB()
            local ca = ColorPickerFrame:GetColorAlpha()
            changedCallback(cr, cg, cb, fix_alpha(ca))
        end,
        swatchFunc = function()
            local cr, cg, cb = ColorPickerFrame:GetColorRGB()
            local ca = ColorPickerFrame:GetColorAlpha()
            changedCallback(cr, cg, cb, fix_alpha(ca))
        end,
        cancelFunc = function()
            local cr, cg, cb, ca = ColorPickerFrame:GetPreviousValues()
            changedCallback(cr, cg, cb, fix_alpha(ca))
        end,
    })
end

local function CreateHeader(self, text, headerType, parent, point1, point2, x, y)
    local header = self:CreateFontString(nil, "ARTWORK", headerType)
    self:AddFrame(header)
    header:SetText(text)
    header:SetPoint(point1, parent, point2, x, y)
    return header
end
local function CreateCheckbox(self, label, tooltip, parent, point1, point2, x, y, defVal, ConfigPathOrFunc)
    local checkbox = CreateFrame("CheckButton", self:NewFrameID(), self, "InterfaceOptionsCheckButtonTemplate")
    self:AddFrame(checkbox)
    checkbox:SetPoint(point1, parent, point2, x, y)
    checkbox:SetScript("OnShow", function(checkboxSelf)
        local val = WidgetConfigBridgeGet(checkboxSelf, defVal, ConfigPathOrFunc)
        checkboxSelf:SetChecked(val)
    end)
    checkbox:SetScript("OnClick", function(checkboxSelf)
        local checked = checkboxSelf:GetChecked()
        PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        WidgetConfigBridgeSet(checkboxSelf, checked, ConfigPathOrFunc)
    end)
    checkbox.label = _G[checkbox:GetName() .. 'Text']
    checkbox.label:SetText(label)
    checkbox.tooltipText = tooltip
    checkbox.tooltipRequirement = L("Default: %s", (tostring(defVal) ~= "nil" and tostring(defVal) or ""))
    return checkbox
end
local function CreateButton(self, label, tooltip, parent, point1, point2, x, y, Func)
    local btn = CreateFrame("button", self:NewFrameID(), self, "UIPanelButtonTemplate")
    self:AddFrame(btn)
    btn:SetWidth(70)
    btn:SetPoint(point1, parent, point2, x, y)
    btn:SetText(label)
    btn.tooltipText = tooltip
    btn:SetScript("OnClick", function(frame, button, down)
        if (button == "LeftButton") and (type(Func) == 'function') then
            Func(frame)
        end
        noop(down)
    end)
    btn:Show()
    return btn
end
local function CreateSlider(self, label, tooltip, parent, point1, point2, x, y, minVal, maxVal, step, defVal, ConfigPathOrFunc)
    local slider = CreateFrame("Slider", self:NewFrameID(), self, "OptionsSliderTemplate")
    self:AddFrame(slider)
    slider:SetOrientation("HORIZONTAL")
    slider:SetPoint(point1, parent, point2, x, y)
    slider:SetWidth(270)
    slider.tooltipText = tooltip
    -- The same rendering as the checkbox path, so a `false` default shows as
    -- "false" here too instead of as an empty string (HF-16).
    slider.tooltipRequirement = L("Default: %s", (tostring(defVal) ~= "nil" and tostring(defVal) or ""))
    _G[slider:GetName() .. 'Low']:SetText(tostring(minVal))
    _G[slider:GetName() .. 'High']:SetText(tostring(maxVal))
    _G[slider:GetName() .. 'Text']:SetText(label)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)

    slider:SetScript("OnShow", function(sliderSelf)
        sliderSelf:SetValue(WidgetConfigBridgeGet(sliderSelf, defVal, ConfigPathOrFunc))
    end)
    slider:HookScript("OnValueChanged", function(sliderSelf, val, isUserInput)
        slider.valueBox:SetText(val)
        WidgetConfigBridgeSet(sliderSelf, val, ConfigPathOrFunc)
        noop(isUserInput)
    end)

    local valueBox = CreateFrame('editbox', nil, slider, BackdropTemplateMixin and "BackdropTemplate")
    valueBox:SetPoint('TOP', slider, 'BOTTOM', 0, 0)
    valueBox:SetSize(60, 14)
    valueBox:SetFontObject(GameFontHighlightSmall)
    valueBox:SetAutoFocus(false)
    valueBox:SetJustifyH('CENTER')
    valueBox:SetScript('OnEscapePressed', function(boxSelf)
        boxSelf:SetText(slider:GetValue() or defVal)
        boxSelf:ClearFocus()
    end)
    valueBox:SetScript('OnEnterPressed', function(boxSelf)
        local value = ValidateValue(tonumber(boxSelf:GetText()) or slider:GetValue() or defVal, minVal, maxVal, step)
        slider:SetValue(value)
        boxSelf:SetText(value)
        boxSelf:ClearFocus()
    end)
    slider:HookScript('OnValueChanged', function(sliderSelf, rawVal)
        local value = ValidateValue(rawVal, minVal, maxVal, step)
        sliderSelf.valueBox:SetText(value)
    end)
    valueBox:SetScript('OnChar', function(boxSelf)
        boxSelf:SetText(boxSelf:GetText():gsub('[^%.0-9]+', ''):gsub('(%..*)%.', '%1'))
    end)
    valueBox:SetMaxLetters(5)

    valueBox:SetBackdrop({
        bgFile = 'Interface/ChatFrame/ChatFrameBackground',
        edgeFile = 'Interface/ChatFrame/ChatFrameBackground',
        tile = true, edgeSize = 1, tileSize = 5,
    })
    valueBox:SetBackdropColor(0, 0, 0, 0.5)
    valueBox:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)

    slider.valueBox = valueBox
    return slider
end


local LSM = LibStub("LibSharedMedia-3.0")
local fontList = {[1]="Friz Quadrata TT"}
local fontPaths = {["Friz Quadrata TT"]="Fonts\\FRIZQT__.TTF"}
local fontObjects = {}
if LSM then
    local function updateFontList()
        for i, name in ipairs(LSM:List("font")) do
            local path = LSM:Fetch("font", name, true)
            if (path) then
                fontList[i] = name
                fontPaths[name] = path
                if (fontObjects[path] == nil) then
                    fontObjects[path] = CreateFont(name)
                    fontObjects[path]:SetFont(path, 14, "")
                end
            end
        end
    end
    updateFontList()
    -- The receiver is part of the method signature but the callback does not need it.
    function CFCT:UpdateUsedMedia(event, mediatype, key) -- luacheck: ignore 212
        if (mediatype == "font") then
            updateFontList()
        end
        noop(event, key)
    end
    LSM.RegisterCallback(CFCT, "LibSharedMedia_Registered", "UpdateUsedMedia")
end

local function CreateFontDropdown(self, label, tooltip, parent, point1, point2, x, y, defVal, ConfigPath)
    local dropdown = CreateFrame('Frame', self:NewFrameID(), self, "UIDropDownMenuTemplate")
    self:AddFrame(dropdown)
    dropdown:SetPoint(point1, parent, point2, x, y)
    dropdown.left = _G[dropdown:GetName() .. "Left"]
    dropdown.middle = _G[dropdown:GetName() .. "Middle"]
    dropdown.middle:SetWidth(150)
    dropdown.right = _G[dropdown:GetName() .. "Right"]
    dropdown.labelText = label
    dropdown.tooltipText = tooltip
    local function itemOnClick(clicked)
        SetValue(ConfigPath, clicked.value)
        UIDropDownMenu_SetSelectedValue(dropdown, clicked.value)
    end
    dropdown.initialize = function(dd)
        local curValue = GetValue(ConfigPath)
        local info = UIDropDownMenu_CreateInfo()
        for _,name in ipairs(fontList) do
            wipe(info)
            info.text = name
            info.value = fontPaths[name]
            info.fontObject = fontObjects[info.value]
            info.checked = (curValue == info.value)
            info.func = itemOnClick
            UIDropDownMenu_AddButton(info)
        end
        UIDropDownMenu_SetSelectedValue(dd, curValue or defVal)
    end
    dropdown:HookScript("OnShow", function(frame)
        DropDownList1:SetClampedToScreen(true)
        local curValue = GetValue(ConfigPath)
        for name, path in pairs(fontPaths) do
            if (path == curValue) then
                _G[frame:GetName().."Text"]:SetText(name)
            end
        end
    end)
    return dropdown
end

local function CreateDropDownMenu(self, label, tooltip, parent, point1, point2, x, y, menuItems, ConfigPathOrFunc)
    local dropdown = CreateFrame('Frame', self:NewFrameID(), self, "UIDropDownMenuTemplate")
    self:AddFrame(dropdown)
    dropdown:SetPoint(point1, parent, point2, x, y)
    dropdown.left = _G[dropdown:GetName() .. "Left"]
    dropdown.middle = _G[dropdown:GetName() .. "Middle"]
    dropdown.middle:SetWidth(150)
    dropdown.right = _G[dropdown:GetName() .. "Right"]
    dropdown.curValue = menuItems[1].value
    dropdown.labelText = label
    dropdown.tooltipText = tooltip

    -- if (ConfigPathOrFunc and (type(ConfigPathOrFunc) == 'function')) then
    --     dropdown.menuFunc = ConfigPathOrFunc
    -- else
    --     dropdown.configPath = ConfigPathOrFunc
    -- end

    -- UIDropDownMenu_SetAnchor(dropdown, 300, 0, "CENTER", UIParent, "LEFT")
    local function itemOnClick(clicked)
        for i = 1, #menuItems do
            local item = menuItems[i]
            if (item.value == clicked.value) then
                dropdown.curValue = item.value
                break
            end
        end
        WidgetConfigBridgeSet(dropdown, clicked.value, ConfigPathOrFunc)
        -- if (dropdown.menuFunc and (type(dropdown.menuFunc) == 'function')) then
        --     dropdown.menuFunc(self, dropdown)
        -- elseif (dropdown.configPath and (type(dropdown.configPath) == 'string')) then
        --     SetValue(dropdown.configPath, dropdown.curValue)
        -- end
        UIDropDownMenu_SetSelectedValue(dropdown, clicked.value)
    end
    dropdown.initialize = function(dd)
        local info = UIDropDownMenu_CreateInfo()
        for i = 1, #menuItems do
            local item = menuItems[i]
            wipe(info)
            info.text = item.text
            info.value = item.value
            info.checked = (info.value == dropdown.curValue)
            info.func = itemOnClick
            UIDropDownMenu_AddButton(info)
        end
        UIDropDownMenu_SetSelectedValue(dd, dd.curValue)
    end
    dropdown:HookScript("OnShow", function(dropdownSelf)
        dropdownSelf.curValue = WidgetConfigBridgeGet(dropdownSelf, dropdownSelf.curValue, ConfigPathOrFunc)
        for i = 1, #menuItems do
            local item = menuItems[i]
            if (item.value == dropdownSelf.curValue) then
                _G[dropdownSelf:GetName().."Text"]:SetText(item.text)
            end
        end
    end)
    return dropdown
end

-- The widget builders share one signature (self, label, tooltip, parent, ...).
-- The colour button renders no tooltip, so the slot is accepted and left unused
-- rather than removed - removing it would shift every later argument.
local function CreateColorOption(self, label, tooltip, parent, point1, point2, x, y, defVal, ConfigPathOrFunc) -- luacheck: ignore 212
    local btn = CreateFrame("Button", self:NewFrameID(), self)
    self:AddFrame(btn)

    btn:SetPoint(point1, parent, point2, x, y)
    btn:SetSize(110, 24)
    -- btn:Hide()
    btn:EnableMouse(true)

    if (ConfigPathOrFunc and (type(ConfigPathOrFunc) == 'function')) then
        btn.configFunc = ConfigPathOrFunc
    else
        btn.configPath = ConfigPathOrFunc
    end

    -- The `self` inside the button callbacks is the BUTTON, not the widget
    -- builder that owns it: the outer `self` is the builder. The shadowing is
    -- intentional and is the way the widget API is written everywhere else, so
    -- the inner name is kept and the shadowing is silenced per site.
    btn.SetColor = function(self, r, g, b, a) -- luacheck: ignore 432
        self.value = {a=a, r=r, g=g, b=b}
        self.preview:SetVertexColor(r, g, b, a)
    end
    btn:SetScript("OnEnter", function(self) -- luacheck: ignore 432
        --show tooltip
        self.preview.bg:SetColorTexture(1, 1, 1)
    end)
    btn:SetScript("OnLeave", function(self) -- luacheck: ignore 432
        --hide tooltip
        self.preview.bg:SetColorTexture(0.5, 0.5, 0.5)
    end)
    btn:SetScript("OnClick", function(self) -- luacheck: ignore 432
        --show color picker
        ShowColorPicker(self, self.value.r, self.value.g, self.value.b, self.value.a, function(r, g, b, a)
            WidgetConfigBridgeSet(self, CFCT.RGBA2Color(r, g, b, a), ConfigPathOrFunc)
            self:SetColor(r, g, b, a)
        end)
    end)
    btn:SetScript("OnShow", function(self) -- luacheck: ignore 432
        local r, g, b, a = CFCT.Color2RGBA(WidgetConfigBridgeGet(self, defVal, ConfigPathOrFunc))
        self:SetColor(r, g, b, a)
    end)

    ---@class ColorPreview : Texture
    ---@field bg Texture
    ---@field ch Texture
    local preview = btn:CreateTexture(nil, "OVERLAY")
    btn.preview = preview
    preview:SetSize(22, 22)
    preview:SetTexture(130939)
    preview:SetPoint("LEFT")

    local tex = btn:CreateTexture(nil, "BACKGROUND")
    preview.bg = tex
    tex:SetSize(18, 18)
    tex:SetColorTexture(0.5, 0.5, 0.5)
    tex:SetPoint("CENTER", preview)
    tex:Show()

    -- checkerboard alpha background
    local ch = btn:CreateTexture(nil, "BACKGROUND")
	preview.ch = ch
	ch:SetWidth(16)
	ch:SetHeight(16)
	ch:SetTexture(188523)
	ch:SetTexCoord(.25, 0, 0.5, .25)
	ch:SetDesaturated(true)
	ch:SetVertexColor(1, 1, 1, 0.75)
	ch:SetPoint("CENTER", preview)
    ch:Show()

    local lbl = btn:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    btn.label = lbl
	lbl:SetHeight(24)
	lbl:SetJustifyH("LEFT")
	lbl:SetTextColor(1, 1, 1)
	lbl:SetPoint("LEFT", preview, "RIGHT", 2, 0)
    lbl:SetPoint("RIGHT")
    lbl:SetText(label)

    btn._Disable = btn.Disable
    btn.Disable = function(self) -- luacheck: ignore 432
        self:_Disable()
        lbl:SetTextColor(0.5, 0.5, 0.5)
    end
    btn._Enable = btn.Enable
    btn.Enable = function(self) -- luacheck: ignore 432
        self:_Enable()
        lbl:SetTextColor(1, 1, 1)
    end

    return btn
end

local HEADER_TEXT = {
    auto = L("Auto Hits"),
    automiss = L("Auto Misses"),
    autocrit = L("Auto Crits"),
    petauto = L("Pet Auto Hits"),
    petautomiss = L("Pet Auto Misses"),
    petautocrit = L("Pet Auto Crits"),

    spell = L("Spell Hits"),
    spellmiss = L("Spell Misses"),
    spellcrit = L("Spell Crits"),
    spelltick = L("DoT Ticks"),
    spelltickmiss = L("DoT Miss Ticks"),
    spelltickcrit = L("DoT Crit Ticks"),

    petspell = L("Pet Spell Hits"),
    petspellmiss = L("Pet Spell Misses"),
    petspellcrit = L("Pet Spell Crits"),
    petspelltick = L("Pet DoT Ticks"),
    petspelltickmiss = L("Pet DoT Miss Ticks"),
    petspelltickcrit = L("Pet DoT Crit Ticks"),

    heal = L("Heals"),
    healmiss = L("Heal Misses"),
    healcrit = L("Heal Crits"),
    healtick = L("HoT Ticks"),
    healtickmiss = L("HoT Miss Ticks"),
    healtickcrit = L("HoT Crit Ticks"),

    petheal = L("Pet Heals"),
    pethealmiss = L("Pet Heal Misses"),
    pethealcrit = L("Pet Heal Crits"),
    pethealtick = L("Pet HoT Ticks"),
    pethealtickmiss = L("Pet HoT Miss Ticks"),
    pethealtickcrit = L("Pet HoT Crit Ticks"),
}
local function CreatePowAnimationPanel(self, cat, anchor, point1, point2, x, y)
    local f = self:CreateChildFrame(point1, point2, anchor, x, y, 612, 90)
    f:Hide()
    DefaultConfig[cat].Pow = DefaultConfig[cat].Pow or {}
    UpdateTable(DefaultConfig[cat].Pow, AnimationDefaults.Pow, AnimationDefaults.Pow)
    local enabledCheckbox = f:CreateCheckbox(L("Enable Pow"), L("Enables/Disables this animation type"), f, "TOPLEFT",
        "TOPLEFT", 170, -2, DefaultConfig[cat].Pow.enabled, "Config."..cat..".Pow.enabled")
    local c = f:CreateChildFrame(point1, point2, anchor, x, y, 612, 90)

    local duration = c:CreateSlider(L("Duration"), L("Animation duration relative to global duration"), f, "TOPLEFT",
        "TOPLEFT", 310, -12, 0.01, 1, 0.01, DefaultConfig[cat].Pow.duration, "Config."..cat..".Pow.duration")
    duration:SetFrameLevel(enabledCheckbox:GetFrameLevel()+1)
    local inOutRatio = c:CreateSlider(L("Duration Ratio"),
        L("Duration ratio between time spent in Start to Mid phase and time spent in Mid to End phase."), f, "TOPLEFT",
        "TOPLEFT", 460, -12, 0.01, 1, 0.01, DefaultConfig[cat].Pow.inOutRatio, "Config."..cat..".Pow.inOutRatio")

    local initScale = c:CreateSlider(L("Start Scale"), L("Initial text scale"), f, "TOPLEFT", "TOPLEFT", 160, -58, 0.1, 5, 0.01, DefaultConfig[cat].Pow.initScale, "Config."..cat..".Pow.initScale")
    local midScale = c:CreateSlider(L("Mid Scale"), L("Mid point text scale"), f, "TOPLEFT", "TOPLEFT", 310, -58, 0.1, 5, 0.01, DefaultConfig[cat].Pow.midScale, "Config."..cat..".Pow.midScale")
    local endScale = c:CreateSlider(L("End Scale"), L("Final text scale"), f, "TOPLEFT", "TOPLEFT", 460, -58, 0.1, 5, 0.01, DefaultConfig[cat].Pow.endScale, "Config."..cat..".Pow.endScale")
    -- The grid slots at (160,-12) and (16,-58) are free; a third row would
    -- overflow the 90px panel and collide with the next category panel.
    local overshoot = c:CreateSlider(L("Overshoot"), L("Extra scale added past the end scale before settling back"), f,
        "TOPLEFT", "TOPLEFT", 160, -12, 0, 1, 0.01, DefaultConfig[cat].Pow.overshoot, "Config."..cat..".Pow.overshoot")
    local settleRatio = c:CreateSlider(L("Settle Ratio"),
        L("Fraction of the second phase spent settling back to the end scale"), f, "TOPLEFT", "TOPLEFT", 16, -58, 0, 1,
        0.01, DefaultConfig[cat].Pow.settleRatio, "Config."..cat..".Pow.settleRatio")
    duration:SetWidth(140)
    inOutRatio:SetWidth(140)
    initScale:SetWidth(140)
    midScale:SetWidth(140)
    endScale:SetWidth(140)
    overshoot:SetWidth(140)
    settleRatio:SetWidth(140)
    enabledCheckbox:HookScript("OnShow", function(self) -- luacheck: ignore 432
        if self:GetChecked() then c:Show() else c:Hide() end
    end)
    enabledCheckbox:HookScript("OnClick", function(self) -- luacheck: ignore 432
        if self:GetChecked() then c:Show() else c:Hide() end
    end)
    f.enabledCheckbox = enabledCheckbox
    return f
end

local function CreateFadeInAnimationPanel(self, cat, anchor, point1, point2, x, y)
    local f = self:CreateChildFrame(point1, point2, anchor, x, y, 612, 90)
    f:Hide()
    DefaultConfig[cat].FadeIn = DefaultConfig[cat].FadeIn or {}
    UpdateTable(DefaultConfig[cat].FadeIn, AnimationDefaults.FadeIn, AnimationDefaults.FadeIn)
    local enabledCheckbox = f:CreateCheckbox(L("Enable Fade In"), L("Enables/Disables this animation type"), f,
        "TOPLEFT", "TOPLEFT", 170, -2, DefaultConfig[cat].FadeIn.enabled, "Config."..cat..".FadeIn.enabled")
    local c = f:CreateChildFrame(point1, point2, anchor, x, y, 612, 90)

    local duration = c:CreateSlider(L("Duration"), L("Animation duration relative to global duration"), f, "TOPLEFT",
        "TOPLEFT", 320, -12, 0.01, 1, 0.01, DefaultConfig[cat].FadeIn.duration, "Config."..cat..".FadeIn.duration")
    duration:SetFrameLevel(enabledCheckbox:GetFrameLevel()+1)
    duration:SetWidth(140)
    enabledCheckbox:HookScript("OnShow", function(self) -- luacheck: ignore 432
        if self:GetChecked() then c:Show() else c:Hide() end
    end)
    enabledCheckbox:HookScript("OnClick", function(self) -- luacheck: ignore 432
        if self:GetChecked() then c:Show() else c:Hide() end
    end)
    f.enabledCheckbox = enabledCheckbox
    return f
end

local function CreateFadeOutAnimationPanel(self, cat, anchor, point1, point2, x, y)
    local f = self:CreateChildFrame(point1, point2, anchor, x, y, 612, 90)
    f:Hide()
    DefaultConfig[cat].FadeOut = DefaultConfig[cat].FadeOut or {}
    UpdateTable(DefaultConfig[cat].FadeOut, AnimationDefaults.FadeOut, AnimationDefaults.FadeOut)
    local enabledCheckbox = f:CreateCheckbox(L("Enable Fade Out"), L("Enables/Disables this animation type"), f,
        "TOPLEFT", "TOPLEFT", 170, -2, DefaultConfig[cat].FadeOut.enabled, "Config."..cat..".FadeOut.enabled")
    local c = f:CreateChildFrame(point1, point2, anchor, x, y, 612, 90)

    local duration = c:CreateSlider(L("Duration"), L("Animation duration relative to global duration"), f, "TOPLEFT",
        "TOPLEFT", 320, -12, 0.01, 1, 0.01, DefaultConfig[cat].FadeOut.duration, "Config."..cat..".FadeOut.duration")
    duration:SetFrameLevel(enabledCheckbox:GetFrameLevel()+1)
    duration:SetWidth(140)
    enabledCheckbox:HookScript("OnShow", function(self) -- luacheck: ignore 432
        if self:GetChecked() then c:Show() else c:Hide() end
    end)
    enabledCheckbox:HookScript("OnClick", function(self) -- luacheck: ignore 432
        if self:GetChecked() then c:Show() else c:Hide() end
    end)
    f.enabledCheckbox = enabledCheckbox
    return f
end
local ScrollDirectionsMenu = {
    {
        text = L("Scroll Up"),
        value = "UP"
    },
    {
        text = L("Scroll Down"),
        value = "DOWN"
    },
    {
        text = L("Scroll Left"),
        value = "LEFT"
    },
    {
        text = L("Scroll Right"),
        value = "RIGHT"
    },
    {
        text = L("Scroll Up & Left"),
        value = "UPLEFT"
    },
    {
        text = L("Scroll Up & Right"),
        value = "UPRIGHT"
    },
    {
        text = L("Scroll Down & Left"),
        value = "DOWNLEFT"
    },
    {
        text = L("Scroll Down & Right"),
        value = "DOWNRIGHT"
    },
    {
        text = L("Random Direction"),
        value = "RANDOM"
    },
}

local function CreateScrollAnimationPanel(self, cat, anchor, point1, point2, x, y)
    local f = self:CreateChildFrame(point1, point2, anchor, x, y, 612, 90)
    f:Hide()
    DefaultConfig[cat].Scroll = DefaultConfig[cat].Scroll or {}
    UpdateTable(DefaultConfig[cat].Scroll, AnimationDefaults.Scroll, AnimationDefaults.Scroll)
    local enabledCheckbox = f:CreateCheckbox(L("Enable Scroll"), L("Enables/Disables this animation type"), f,
        "TOPLEFT", "TOPLEFT", 170, -2, DefaultConfig[cat].Scroll.enabled, "Config."..cat..".Scroll.enabled")
    local c = f:CreateChildFrame(point1, point2, anchor, x, y, 612, 90)

    local dirDropDown = c:CreateDropDownMenu(L("Direction"), L("Scroll direction"), f, "TOPLEFT", "TOPLEFT", 320-16, 0, ScrollDirectionsMenu, "Config."..cat..".Scroll.direction")
    dirDropDown.middle:SetWidth(120)
    local distance = c:CreateSlider(L("Distance"), L("Scroll distance"), f, "TOPLEFT", "TOPLEFT", 320, -40, 1,
        floor(WorldFrame:GetWidth()), 1, DefaultConfig[cat].Scroll.distance, "Config."..cat..".Scroll.distance")
    distance:SetFrameLevel(enabledCheckbox:GetFrameLevel()+1)
    distance:SetWidth(140)
    enabledCheckbox:HookScript("OnShow", function(self) -- luacheck: ignore 432
        if self:GetChecked() then c:Show() else c:Hide() end
    end)
    enabledCheckbox:HookScript("OnClick", function(self) -- luacheck: ignore 432
        if self:GetChecked() then c:Show() else c:Hide() end
    end)
    f.enabledCheckbox = enabledCheckbox
    return f
end

local function CreateCategoryPanel(self, cat, anchor, point1, point2, x, y)
    local f = self:CreateChildFrame(point1, point2, anchor, x, y, 612, 180)
    f:Show()

    self:CreateHeader(HEADER_TEXT[cat], "GameFontNormalLarge", f, "TOPLEFT", "TOPLEFT", 4, -2)
    local enabledCheckbox = self:CreateCheckbox(L("Enabled"), L("Enables/Disables this event type"), f, "TOPLEFT", "TOPLEFT", 143, 0, DefaultConfig[cat].enabled, "Config."..cat..".enabled")
    enabledCheckbox.label:SetWidth(80)
    enabledCheckbox:HookScript("OnShow", function(checkbox)
        if (checkbox:GetChecked()) then f:Show() else f:Hide() end
    end)
    enabledCheckbox:HookScript("OnClick", function(checkbox)
        if (checkbox:GetChecked()) then f:Show() else f:Hide() end
    end)
    local showIconsCheckbox = f:CreateCheckbox(L("Show Spell Icons"),
        L("Enables/Disables showing spell icons next to damage text"), f, "TOPLEFT", "TOPLEFT", 250, 0,
        DefaultConfig[cat].showIcons, "Config."..cat..".showIcons")
    showIconsCheckbox:SetFrameLevel(enabledCheckbox:GetFrameLevel() + 1)

    f:CreateFontDropdown(L("Font Face"), L("Font face used"), f, "TOPLEFT", "TOPLEFT", -16, -28, DefaultConfig[cat].fontPath, "Config."..cat..".fontPath")
    f:CreateDropDownMenu(L("Font Style"), L("Font style used"), f, "TOPLEFT", "TOPLEFT", 154, -28, FontStylesMenu, "Config."..cat..".fontStyle")
    local fontSizeSlider = f:CreateSlider(L("Font Size"), L("Font Size"), f, "TOPLEFT", "TOPLEFT", 170+180, -28, 10, 128, 1, DefaultConfig[cat].fontSize, "Config."..cat..".fontSize")
    fontSizeSlider:SetWidth(150)
    f:CreateColorOption(L("Text Color"), L("Custom text color for this event"), f, "TOPLEFT", "TOPLEFT", 170+180+160, -30, DefaultConfig[cat].fontColor, "Config."..cat..".fontColor")
    if (cat:find("heal") == nil) then
        f:CreateCheckbox(L("Color By Type"),
            L("Enables/Disables coloring damage text based on its type (alpha still taken from the text color below)"),
            f, "TOPLEFT", "TOPLEFT", 480, 0, DefaultConfig[cat].colorByType, "Config."..cat..".colorByType")
    end
    local animPanel = {}
    animPanel.Pow = CreatePowAnimationPanel(f, cat, f, "TOPLEFT", "TOPLEFT", 0, -70)
    animPanel.FadeIn = CreateFadeInAnimationPanel(f, cat, f, "TOPLEFT", "TOPLEFT", 0, -70)
    animPanel.FadeOut = CreateFadeOutAnimationPanel(f, cat, f, "TOPLEFT", "TOPLEFT", 0, -70)
    animPanel.Scroll = CreateScrollAnimationPanel(f, cat, f, "TOPLEFT", "TOPLEFT", 0, -70)
    local animStatus = L("init")
    local animStatusHeader = f:CreateHeader(L("Animation Status:")..animStatus, "GameFontHighlightSmall", f, "TOPLEFT", "TOPLEFT", 4, -100)
    animStatusHeader:SetJustifyH("LEFT")

    local function updateStatus()
        animStatus = ""
        for _,a in ipairs(AnimationsMenu) do
            local k = a.text
            animStatus = animStatus..(CFCT.Config[cat][a.value].enabled and "\n|cff00ff00"..k or "\n|cffff0000"..k).."|r"
        end
        animStatusHeader:SetText(L("Animation Status:")..animStatus)
    end

    for _,v in pairs(animPanel) do
        v.enabledCheckbox:HookScript("OnClick", function()
            updateStatus()
        end)
    end

    local function show(val)
        for k,v in pairs(animPanel) do
            if (k == val) then v:Show() else v:Hide() end
        end
    end

    f:CreateHeader(L("Animation Settings"), "GameFontHighlightSmall", f, "TOPLEFT", "TOPLEFT", 4, -60)

    local animDropDown = f:CreateDropDownMenu(L("Animations"), L("Animations"), f, "TOPLEFT", "TOPLEFT", -16, -70, AnimationsMenu, function(_, e, value)
        if (e == "Get") then
            return value
        elseif (e == "Set") then
            show(value)
        end
        updateStatus()
    end)
    animDropDown:HookScript("OnShow", function(dropdown)
        show(dropdown.curValue)
        updateStatus()
    end)

    return f
end

local function AddFrame(self, widget)
    local n = self.widgetCount + 1
    self.widgets[n] = widget
    self.widgetCount = n
end

local function NewFrameID(self)
    return self:GetName().."_Frame" .. tostring(self.widgetCount + 1)
end

local function Refresh(self)
    if (self:IsShown()) then
        self:Hide()
        self:Show()
    end
end

local function EnableFrameTree(self)
    for _, e in ipairs(self.widgets) do
        if type(e.Enable) == 'function' then e:Enable() end
    end
end
local function DisableFrameTree(self)
    for _, e in ipairs(self.widgets) do
        if type(e.Disable) == 'function' then e:Disable() end
    end
end

local function CreateChildFrame(self, point1, point2, anchor, x, y, w, h)
    local f = CreateFrame("frame", self:NewFrameID(), self)
    self:AddFrame(f)
    f:SetPoint(point1, anchor, point2, x, y)
    f:SetSize(w,h)
    f:SetFrameLevel(1)
    f.widgets = {}
    f.widgetCount = 0
    f.CreateChildFrame = CreateChildFrame
    f.CreateHeader = CreateHeader
    f.CreateCheckbox = CreateCheckbox
    f.CreateButton = CreateButton
    f.CreateFontDropdown = CreateFontDropdown
    f.CreateDropDownMenu = CreateDropDownMenu
    f.CreateSlider = CreateSlider
    f.CreateColorOption = CreateColorOption
    f.AddFrame = AddFrame
    f.NewFrameID = NewFrameID
    f.Enable = EnableFrameTree
    f.Disable = DisableFrameTree
    f.Refresh = Refresh
    return f
end

local ScrollUpBtnOffsetX = UsesNewSettingsInterface and -15 or -6
local ScrollUpBtnOffsetY = UsesNewSettingsInterface and 8 or -2
local ScrollDnBtnOffsetX = UsesNewSettingsInterface and -15 or -6
local ScrollDnBtnOffsetY = UsesNewSettingsInterface and -1 or 2
local function CreateConfigPanel(name, parent, height)
    local Container = CreateFrame('frame', "ClassicFCTConfigPanel_"..gsub(name, " ", ""), UIParent)

    Container.name = name
    Container.parent = parent
    Container.CategoryID = name
    Container.refresh = Refresh
	Container.okay = function() end
	Container.cancel = function() end

    local sf = CreateFrame('ScrollFrame', Container:GetName().."_ScrollFrame", Container, "UIPanelScrollFrameTemplate")
    local sfname = sf:GetName()
    sf.scrollbar = _G[sfname.."ScrollBar"]
    sf.scrollupbutton = _G[sfname.."ScrollBarScrollUpButton"]
    sf.scrolldownbutton = _G[sfname.."ScrollBarScrollDownButton"]

    sf.scrollupbutton:ClearAllPoints();
    sf.scrollupbutton:SetPoint("TOPLEFT", sf, "TOPRIGHT", ScrollUpBtnOffsetX, ScrollUpBtnOffsetY);

    sf.scrolldownbutton:ClearAllPoints();
    sf.scrolldownbutton:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", ScrollDnBtnOffsetX, ScrollDnBtnOffsetY);

    sf.scrollbar:ClearAllPoints();
    sf.scrollbar:SetPoint("TOP", sf.scrollupbutton, "BOTTOM", 0, -2);
    sf.scrollbar:SetPoint("BOTTOM", sf.scrolldownbutton, "TOP", 0, 2);

    if (UsesNewSettingsInterface) then
        Container.OnCommit = function()  end
        Container.OnDefault = function()  end
        Container.OnRefresh = function() Refresh(Container) end

        local Category
        if (parent == nil) then
            Category = Settings.RegisterCanvasLayoutCategory(Container, name)
            Settings.RegisterAddOnCategory(Category)
        else
            Category = Settings.RegisterCanvasLayoutSubcategory(Settings.GetCategory(parent), Container, name)
        end
        Container.CategoryID = Category:GetID()
    else
        InterfaceOptions_AddCategory(Container)
    end

    CFCT.ConfigPanels[#CFCT.ConfigPanels + 1] = Container
    -- Container:HookScript("OnShow")
    Container:SetAllPoints()
    Container:Hide()

    local p = CreateFrame("Frame", Container:GetName().."_ScrollChild")
    p.refresh = function() Container:refresh() end
    p.widgets = {}
    p.widgetCount = 0
    p.CreateSubPanel = function(_, subName, subHeight)
        return CreateConfigPanel(subName, Container.CategoryID, subHeight)
    end
    p.CreateChildFrame = CreateChildFrame
    p.CreateCategoryPanel = CreateCategoryPanel
    p.CreateHeader = CreateHeader
    p.CreateCheckbox = CreateCheckbox
    p.CreateButton = CreateButton
    p.CreateFontDropdown = CreateFontDropdown
    p.CreateDropDownMenu = CreateDropDownMenu
    p.CreateSlider = CreateSlider
    p.CreateColorOption = CreateColorOption
    p.AddFrame = AddFrame
    p.NewFrameID = NewFrameID
    Container.panel = p
    p.Container = Container
    sf:SetScrollChild(p)
    sf:SetAllPoints()
    -- The scroll child's height must cover the content. The content is built
    -- from anchored widgets whose heights come from the client's own templates
    -- (a slider is 17px tall, plus a 14px value box below it and a label
    -- above it), so the height the panel needs is MEASURED from the widgets
    -- instead of being hard-coded. A fixed height either clips the bottom of
    -- the panel - making those settings unreachable - or leaves empty space
    -- below it.
    --
    -- The measurement only ever GROWS the height, and a measurement that
    -- cannot be taken leaves the height alone, so a failed measurement can
    -- never make the panel smaller than it was.
    local function FitScrollHeight()
        local top = p:GetTop()
        if (not top) then return end
        local lowest
        for _, widget in ipairs(p.widgets or {}) do
            if (type(widget.GetBottom) == "function") then
                local bottom = widget:GetBottom()
                if bottom and ((not lowest) or (bottom < lowest)) then lowest = bottom end
            end
        end
        if (not lowest) then return end
        -- 24px of slack, so the last widget is not flush against the edge.
        local needed = (top - lowest) + 24
        if needed > (height or 0) then
            p:SetSize(p:GetWidth() or 0, needed)
        end
    end
    p.FitScrollHeight = FitScrollHeight
    p:HookScript("OnShow", function(self)
        self:SetSize(sf:GetWidth(), height or sf:GetHeight())
        FitScrollHeight()
    end)
    Container:HookScript("OnShow", FitScrollHeight)
    return p
end



--ConfigPanel Layout

local ConfigPanel = CreateConfigPanel("ClassicFCT", nil, 800)
CFCT.ConfigPanel = ConfigPanel
local headerGlobal = ConfigPanel:CreateHeader("", "GameFontNormalLarge", ConfigPanel, "TOPLEFT", "TOPLEFT", 16, -16)
local charSpecificCheckbox = ConfigPanel:CreateCheckbox(L("Character Specific Config"),
    L("Settings are saved per character. Presets stay global."), headerGlobal, "LEFT", "LEFT", 0, -2,
    DefaultVars.characterSpecificConfig,
    function(self, e, value) -- luacheck: ignore 212
        if (e == "Get") then
            return CFCT.characterSpecificConfig
        elseif (e == "Set") then
            CFCT.Config:OnSave()
            CFCT.characterSpecificConfig = value
            ClassicFCTVars.characterSpecificConfig = value
            if value then
                -- The character store is empty on the FIRST switch, so it used
                -- to be filled from the SCHEMA - which silently reverted the
                -- whole configuration to the defaults the moment the box was
                -- ticked. It is seeded from the CURRENT live configuration
                -- instead, so the switch keeps the settings the user can see.
                ClassicFCTCharConfig = ClassicFCTCharConfig or {}
                if next(ClassicFCTCharConfig) == nil then
                    UpdateTable(ClassicFCTCharConfig, CFCT.Config, DefaultConfig, true)
                    CFCT:Log(L("character-specific configuration enabled - the current settings were copied to this character."))
                else
                    CFCT:Log(L("character-specific configuration enabled - the saved settings for this character were restored."))
                end
            else
                CFCT:Log(L("account-wide configuration enabled - the account settings were restored."))
            end
            CFCT.Config:OnLoad()
            ConfigPanel:refresh()
        end
end)
local enabledCheckbox = ConfigPanel:CreateCheckbox(L("Enable ClassicFCT"), L("Enables/Disables the addon"), charSpecificCheckbox, "TOPLEFT", "BOTTOMLEFT", 0, -2, DefaultVars.enabled, "enabled")

-- These two were ALWAYS hidden before: the probe used the un-suffixed CVar name
-- ("floatingCombatTextCombatDamage"), which does not exist on any client, so
-- GetCVarDefault returned nil and both boxes were hidden on every client. The
-- CVar names are now resolved correctly, so the boxes are visible for the
-- first time - and they had never been laid out for that.
--
-- They are chained to the RIGHT of the previous box's LABEL rather than to the
-- previous box itself, with a fixed 150px offset. A fixed offset cannot work
-- here: the label width depends on the language, and these labels are wider
-- than the 150px the old chain allowed, so the boxes overlapped. Anchoring to
-- the label's right edge follows the text instead, so the gap is correct in
-- every language and the row needs no extra vertical space.
local hideBlizzDamageCheckbox = ConfigPanel:CreateCheckbox(L("Hide Blizzard Damage"),
    L("Enables/Disables the default Blizzard Floating Damage Text"), enabledCheckbox.label, "LEFT", "RIGHT", 8, 0,
    DefaultVars.hideBlizz, "hideBlizz")
hideBlizzDamageCheckbox:HookScript("OnClick", function(self)
    if IsRestrictedCombat then return end
    if (CVarDamage == nil) then return end
    SetCVar(CVarDamage, self:GetChecked() and "0" or "1")
end)
if (CVarDamage == nil) then hideBlizzDamageCheckbox:Hide() end

local hideBlizzHealingCheckbox = ConfigPanel:CreateCheckbox(L("Hide Blizzard Healing"),
    L("Enables/Disables the default Blizzard Floating Healing Text"), hideBlizzDamageCheckbox.label, "LEFT", "RIGHT", 8, 0,
    DefaultVars.hideBlizzHeals, "hideBlizzHeals")
hideBlizzHealingCheckbox:HookScript("OnClick", function(self)
    if IsRestrictedCombat then return end
    if (CVarHealing == nil) then return end
    SetCVar(CVarHealing, self:GetChecked() and "0" or "1")
end)
if (CVarHealing == nil) then hideBlizzHealingCheckbox:Hide() end
if IsRestrictedCombat then
    hideBlizzDamageCheckbox:Hide()
    hideBlizzHealingCheckbox:Hide()
end

local headerPresets = ConfigPanel:CreateHeader(L("Config Presets"), "GameFontNormalLarge", headerGlobal, "TOPLEFT", "BOTTOMLEFT", 0, -46)
local newPresetBtn = ConfigPanel:CreateButton(L("New"), L("Creates a new preset"), headerPresets, "TOPLEFT", "TOPRIGHT", 94, 0, function()
    CFCT.Config:CreatePreset()
end)
ConfigPanel:CreateButton(L("Copy"), L("Creates a copy of the selected preset"), newPresetBtn, "TOPLEFT", "BOTTOMLEFT", 0, 0, function()
    CFCT.Config:CreatePresetCopy(CFCT.selectedPreset)
end)



local PresetMenu = {{}}
-- Forward declarations: the dropdown's Set handler has to refresh the Save/Delete/Rename
-- state, but the buttons are created after the dropdown (they are anchored to it).
local savePresetBtn, deletePresetBtn, renamePresetBtn
-- Built-in presets are read-only. This state has to be recomputed whenever the SELECTION
-- changes, not only when the dropdown is opened - picking a built-in entry from the open
-- list used to leave the previous (custom) state on the buttons.
local function updatePresetButtons(presetName)
    if (presetName == nil) then presetName = CFCT.selectedPreset end
    if (DefaultPresets[presetName]) then
        savePresetBtn:Disable()
        deletePresetBtn:Disable()
        renamePresetBtn:Disable()
    else
        savePresetBtn:Enable()
        deletePresetBtn:Enable()
        renamePresetBtn:Enable()
    end
end
local presetDropDown = ConfigPanel:CreateDropDownMenu(L("Presets"), L("Configuration Presets"), newPresetBtn, "LEFT", "RIGHT", -10, 0, PresetMenu,
    function(self, e, value) -- luacheck: ignore 212
        if (e == "Get") then
            return CFCT.selectedPreset
        elseif (e == "Set") then
            CFCT.selectedPreset = value
            -- Same value the dropdown just showed; recompute the button state now.
            updatePresetButtons(value)
        end
end)

savePresetBtn = ConfigPanel:CreateButton(L("Save"), L("Saves current configuration into the selected preset"), presetDropDown.middle, "BOTTOMRIGHT", "BOTTOM", 0, -2, function()
    CFCT.Config:SavePreset(CFCT.selectedPreset)
end)
savePresetBtn:SetWidth(84)
local loadPresetBtn = ConfigPanel:CreateButton(L("Load"), L("Loads the selected preset, overwriting current configuration"), presetDropDown.middle, "BOTTOMLEFT", "BOTTOM", 0, -2, function()
    CFCT.Config:LoadPreset(CFCT.selectedPreset)
end)
loadPresetBtn:SetWidth(84)
deletePresetBtn = ConfigPanel:CreateButton(L("Delete"), L("Deletes the selected preset permanently"), presetDropDown, "LEFT", "RIGHT", presetDropDown.middle:GetWidth(), 0, function()
    CFCT.Config:DeletePreset(CFCT.selectedPreset)
end)
renamePresetBtn = ConfigPanel:CreateButton(L("Rename"), L("Renames the selected preset"), deletePresetBtn, "TOPLEFT", "BOTTOMLEFT", 0, 0, function()
    CFCT.Config:RenamePreset(CFCT.selectedPreset)
end)

presetDropDown:HookScript("OnShow", function(self)
    wipe(PresetMenu)
    for k in pairs(DefaultPresets) do
        table.insert(PresetMenu, {
            text = L("%s |cff808080built-in|r", k),
            value = k
        })
    end
    for k in pairs(CFCT.Presets) do
        if (DefaultPresets[k] == nil) then
            table.insert(PresetMenu, {
                text = k,
                value = k
            })
        end
    end
    if (CFCT.Presets[CFCT.selectedPreset] == nil) then
        CFCT.selectedPreset = PresetMenu[1].value
    end
    self.curValue = CFCT.selectedPreset
    local dropDownText
    for _,v in pairs(PresetMenu) do if (v.value == self.curValue) then dropDownText = v.text end end
    _G[self:GetName().."Text"]:SetText(dropDownText)
    updatePresetButtons(self.curValue)
end)

local headerGeneralSettings = ConfigPanel:CreateHeader(L("General Settings"), "GameFontNormalLarge", headerPresets, "TOPLEFT", "BOTTOMLEFT", 0, -32)

local animDurationSlider = ConfigPanel:CreateSlider(L("Animation Duration"), L("Animation length in seconds"),
    headerGeneralSettings, "TOPLEFT", "BOTTOMLEFT", 20, -24, 0.1, 5.0, 0.1, DefaultConfig.animDuration,
    "Config.animDuration")
ConfigPanel:CreateSlider(L("Max Simultaneous Numbers"),
    L("Maximum combat numbers visible at once. 0 = unlimited (current behavior). When the limit is reached the oldest number is removed so the newest stays visible."),
    animDurationSlider, "LEFT", "RIGHT", 16, 0, 0, 200, 1, DefaultConfig.maxDisplayed, "Config.maxDisplayed")
local textPosOptionsHeader = ConfigPanel:CreateHeader(L("Text Position Options"), "GameFontNormalLarge", headerGeneralSettings, "TOPLEFT", "BOTTOMLEFT", 0, -64)

local attachModeHeader = ConfigPanel:CreateHeader(L("Attach Text To"), "GameFontHighlightSmall", textPosOptionsHeader, "TOPLEFT", "BOTTOMLEFT", 20, -16)
local attachModeDropDown = ConfigPanel:CreateDropDownMenu(L("Attach Mode"), "", attachModeHeader, "LEFT", "LEFT", 64, -3, AttachModesMenu, "Config.attachMode")
attachModeDropDown.middle:SetWidth(110)

local fallbackCheckbox = ConfigPanel:CreateCheckbox(L("Attachment Fallback"),
    L("When a nameplate isnt available, the text will temporarily attach to the screen center instead"),
    attachModeDropDown.right, "LEFT", "RIGHT", -10, 0, DefaultConfig.attachModeFallback, "Config.attachModeFallback")
local overlapCheckbox = ConfigPanel:CreateCheckbox(L("Prevent Text Overlap"),
    L("Prevents damage text frames from overlapping each other"), fallbackCheckbox, "LEFT", "RIGHT", 132, 0,
    DefaultConfig.preventOverlap, "Config.preventOverlap")

ConfigPanel:CreateCheckbox(L("Nameplates In Front"), L("Show text behind the nameplates"), fallbackCheckbox, "TOPLEFT",
    "BOTTOMLEFT", 0, 0, DefaultConfig.dontOverlapNameplates, "Config.dontOverlapNameplates")
local inheritNameplatesCheckbox = ConfigPanel:CreateCheckbox(L("Inherit From Nameplates"),
    L("Text inherits some atributes from nameplates, like visibility and scale"), overlapCheckbox, "TOPLEFT",
    "BOTTOMLEFT", 0, 0, DefaultConfig.inheritNameplates, "Config.inheritNameplates")
-- Off-target dimming. The CHECKBOX stays here, in the Text Position Options
-- section, but the two sliders that control the dimming live at the BOTTOM of
-- the panel.
--
-- They used to sit directly under this checkbox, in the free right-hand
-- column. That column is the same column the "Screen Center Text", "Nameplate
-- Text" and "Anti-Overlap" sliders use for their second half, so the off-target
-- sliders were drawn straight over those sliders' labels and value boxes: the
-- panel could not be read, and the settings could not be checked.
ConfigPanel:CreateCheckbox(L("Dim Off-Target Text"),
    L("Dim numbers for units other than your current target"), inheritNameplatesCheckbox, "TOPLEFT", "BOTTOMLEFT", 0, 0,
    DefaultConfig.offTarget.enabled, "Config.offTarget.enabled")


local areaSliderX = ConfigPanel:CreateSlider(L("Screen Center Text X Offset"), L("Horizontal offset of animation area"),
    attachModeHeader, "TOPLEFT", "BOTTOMLEFT", 0, -48, -700, 700, 1, DefaultConfig.areaX, "Config.areaX")
ConfigPanel:CreateSlider(L("Screen Center Text Y Offset"), L("Vertical offset of animation area"), areaSliderX, "LEFT", "RIGHT", 16, 0, -400, 400, 1, DefaultConfig.areaY, "Config.areaY")
local areaSliderNX = ConfigPanel:CreateSlider(L("Nameplate Text X Offset"), L("Horizontal offset of animation area"),
    areaSliderX, "TOPLEFT", "BOTTOMLEFT", 0, -28, -400, 400, 1, DefaultConfig.areaNX, "Config.areaNX")
ConfigPanel:CreateSlider(L("Nameplate Text Y Offset"), L("Vertical offset of animation area"), areaSliderNX, "LEFT", "RIGHT", 16, 0, -400, 400, 1, DefaultConfig.areaNY, "Config.areaNY")
local spacingSliderX = ConfigPanel:CreateSlider(L("Anti-Overlap Horizontal Spacing"),
    L("Horizontal spacing between text"), areaSliderNX, "TOPLEFT", "BOTTOMLEFT", 0, -28, 0, 200, 1,
    DefaultConfig.preventOverlapSpacingX, "Config.preventOverlapSpacingX")
ConfigPanel:CreateSlider(L("Anti-Overlap Vertical Spacing"), L("Vertical spacing between text"), spacingSliderX, "LEFT",
    "RIGHT", 16, 0, 0, 200, 1, DefaultConfig.preventOverlapSpacingY, "Config.preventOverlapSpacingY")


-- Spell Icon Options - Credit: https://github.com/akbyrd
local spellIconOptionsHeader = ConfigPanel:CreateHeader(L("Spell Icon Options"), "GameFontNormalLarge", textPosOptionsHeader, "TOPLEFT", "BOTTOMLEFT", 0, -200)
local iconOffsetSliderX = ConfigPanel:CreateSlider(L("X Offset"), L("Horizontal offset of spell icon"),
    spellIconOptionsHeader, "TOPLEFT", "BOTTOMLEFT", 20, -24, -20, 20, 1, DefaultConfig.spellIconOffsetX,
    "Config.spellIconOffsetX")
ConfigPanel:CreateSlider(L("Y Offset"), L("Vertical offset of spell icon"), iconOffsetSliderX, "LEFT", "RIGHT", 16, 0, -20, 20, 1, DefaultConfig.spellIconOffsetY, "Config.spellIconOffsetY")
local iconZoomSlider = ConfigPanel:CreateSlider(L("Zoom"),
    L("Zoom in on the icon and trim to edge to give a more square appearance"), iconOffsetSliderX, "TOPLEFT",
    "BOTTOMLEFT", 0, -28, 1, 2, 0.01, DefaultConfig.spellIconZoom, "Config.spellIconZoom")
ConfigPanel:CreateSlider(L("Aspect Ratio"), L("Aspect ratio of spell icon"), iconZoomSlider, "LEFT", "RIGHT", 16, 0, 1, 2, 0.01, DefaultConfig.spellIconAspectRatio, "Config.spellIconAspectRatio")



local textFormatOptionsHeader = ConfigPanel:CreateHeader(L("Number Formatting Options"), "GameFontNormalLarge", spellIconOptionsHeader, "TOPLEFT", "BOTTOMLEFT", 0, -108)
local abbrevCheckbox = ConfigPanel:CreateCheckbox(L("Abbreviate Large Numbers"), L("Abbreviate large numbers (ex.1K)"),
    textFormatOptionsHeader, "TOPLEFT", "BOTTOMLEFT", 20, -8, DefaultConfig.abbreviateNumbers,
    "Config.abbreviateNumbers")
ConfigPanel:CreateCheckbox(L("Add Thousands Separator"), L("Add thousands separator (ex.100,000,000)"), abbrevCheckbox,
    "TOPLEFT", "BOTTOMLEFT", 0, 0, DefaultConfig.kiloSeparator, "Config.kiloSeparator")

local filteringOptionsHeader = ConfigPanel:CreateHeader(L("Filtering Options"), "GameFontNormalLarge", textFormatOptionsHeader, "TOPLEFT", "BOTTOMLEFT", 0, -64)
local absoluteFilterCheckbox = ConfigPanel:CreateCheckbox(L("Hide Below Absolute Threshold"),
    L("Hide numbers smaller than an absolute value"), filteringOptionsHeader, "TOPLEFT", "BOTTOMLEFT", 20, -8,
    DefaultConfig.filterAbsoluteEnabled, "Config.filterAbsoluteEnabled")
ConfigPanel:CreateSlider(L("Absolute Threshold"), L("Absolute Value"), absoluteFilterCheckbox, "LEFT", "RIGHT", 256, 0,
    0, 10000, 1, DefaultConfig.filterAbsoluteThreshold, "Config.filterAbsoluteThreshold")
local relativeFilterCheckbox = ConfigPanel:CreateCheckbox(L("Hide Below Relative Threshold"),
    L("Hide numbers smaller than a percentage of player health"), absoluteFilterCheckbox, "TOPLEFT", "BOTTOMLEFT", 0,
    -20, DefaultConfig.filterRelativeEnabled, "Config.filterRelativeEnabled")
local relativeThresholdSlider = ConfigPanel:CreateSlider(L("% of Max Player Health"),
    L("Percentage of Max Player Health"), relativeFilterCheckbox, "LEFT", "RIGHT", 256, 0, 0, 100, 0.1,
    DefaultConfig.filterRelativeThreshold, "Config.filterRelativeThreshold")
local relativeThresholdTimer = 0
relativeThresholdSlider:HookScript("OnUpdate", function(self)
    if not self:IsShown() then return end
    local now = GetTime()
    if ((now - relativeThresholdTimer) > 0.1) then
        _G[self:GetName() .. 'Text']:SetText(L("% of Max Player Health").." ("..tostring(floor(CFCT:UnitHealthMax('player') * 0.01 * CFCT.Config.filterRelativeThreshold))..")")
        relativeThresholdTimer = now
    end
end)
local averageFilterCheckbox = ConfigPanel:CreateCheckbox(L("Hide Below Average Threshold"),
    L("Hide numbers smaller than a percentage of average damage"), relativeFilterCheckbox, "TOPLEFT", "BOTTOMLEFT", 0,
    -20, DefaultConfig.filterAverageEnabled, "Config.filterAverageEnabled")
local averageThresholdSlider = ConfigPanel:CreateSlider(L("% of Average Damage/Healing"),
    L("Percentage of Average Damage/Healing"), averageFilterCheckbox, "LEFT", "RIGHT", 256, 0, 0, 200, 0.1,
    DefaultConfig.filterAverageThreshold, "Config.filterAverageThreshold")
local averageThresholdTimer = 0
averageThresholdSlider:HookScript("OnUpdate", function(self)
    if not self:IsShown() then return end
    local now = GetTime()
    if ((now - averageThresholdTimer) > 0.1) then
        _G[self:GetName() .. 'Text']:SetText(L("% of Average Damage/Healing").." ("..tostring(floor(CFCT:DamageRollingAverage() * 0.01 * CFCT.Config.filterAverageThreshold))..")")
        averageThresholdTimer = now
    end
end)
local demoteCritsCheckbox = ConfigPanel:CreateCheckbox(L("Demote Small Crits"),
    L("Show crits below the threshold with the normal (non-crit) styling"), averageFilterCheckbox, "TOPLEFT",
    "BOTTOMLEFT", 0, -20, DefaultConfig.demoteSmallCritsEnabled, "Config.demoteSmallCritsEnabled")
local demoteCritsSlider = ConfigPanel:CreateSlider(L("Small Crit Threshold"),
    L("Crits smaller than this amount lose the crit styling"), demoteCritsCheckbox, "LEFT", "RIGHT", 256, 0, 0, 10000,
    1, DefaultConfig.demoteSmallCritThreshold, "Config.demoteSmallCritThreshold")
ConfigPanel:CreateCheckbox(L("Hide Misses"),
    L("Hides Absorb, Block, Miss, Parry, Dodge, Deflect, Evade, Immune, Reflect and Resist."), demoteCritsCheckbox,
    "TOPLEFT", "BOTTOMLEFT", 0, -20, DefaultConfig.filterMissesEnabled, "Config.filterMissesEnabled")

local filteringBlacklistDropdown
local filteringBlacklistCheckbox
local FilteringBlacklistMenu = {{}}
-- A spell entry for the spell-id dropdowns. The key of CFCT.spellIdCache is the
-- RUNTIME key of a spell: a numeric spell id, or - on the legacy clients (Era,
-- TBC Anniversary, WotLK Titanforge), where the combat log reports spell id 0 -
-- the spell NAME. GetSpellInfo only resolves numeric ids, so a name key used
-- to vanish from the dropdown and could never be blacklisted; it is listed
-- with the name itself instead. The blacklist and the per-spell merge interval
-- are then keyed by exactly the key the runtime looks up (HF-06).
local function SpellMenuEntry(key, color)
    local spell = nil
    -- The legacy GetSpellInfo may or may not resolve a NAME (and it may reject
    -- one outright), so the lookup is contained and the name key is listed
    -- either way.
    local ok, res = pcall(GetSpellInfo, key)
    if ok then spell = res end
    if (spell and spell.name) then
        return {text = format("|T%s:12:12:0:0:120:120:10:110:10:110|t|cff%s%s(%s)|r", spell.iconID, color, spell.name, key), value = key}
    end
    if (type(key) == "string") and (key ~= "") then
        return {text = format("|cff%s%s|r", color, key), value = key}
    end
    return nil
end
local filteringBlacklistHeader = ConfigPanel:CreateHeader(L("SpellId Blacklist"), "GameFontHighlightSmall", demoteCritsSlider, "TOPLEFT", "BOTTOMLEFT", 0, -30)

filteringBlacklistDropdown = ConfigPanel:CreateDropDownMenu(L("SpellId Blacklist"), "", filteringBlacklistHeader, "LEFT", "LEFT", 68, -3, FilteringBlacklistMenu,
    function(self, e, value)
        if (e == "Get") then
            return value
        elseif (e == "Set") then
            for k,v in pairs(CFCT.Config.filterSpellBlacklist) do
                if (self.curValue == k) then
                    filteringBlacklistCheckbox:SetChecked(v)
                    return
                end
            end
            filteringBlacklistCheckbox:SetChecked(false)
        end
end)
filteringBlacklistDropdown.middle:SetWidth(170)

filteringBlacklistDropdown:HookScript("OnShow", function(self)
    wipe(FilteringBlacklistMenu)
    local spellIdTable = CFCT.Config.filterSpellBlacklist
    local color = "FFFFFF"
    for k in pairs(spellIdTable) do
        local entry = SpellMenuEntry(k, color)
        if entry then
            CFCT.spellIdCache[k] = true
            table.insert(FilteringBlacklistMenu, entry)
        end
    end
    color = "808080"
    for k in pairs(CFCT.spellIdCache) do
        if (spellIdTable[k] == nil) then
            local entry = SpellMenuEntry(k, color)
            if entry then
                table.insert(FilteringBlacklistMenu, entry)
            end
        end
    end
    -- next() returns the first key of the table, which is exactly the key the
    -- old "take the first entry and stop" loop picked. An empty table yields
    -- nil, which leaves curValue unchanged.
    if (self.curValue == nil) then
        self.curValue = next(spellIdTable)
    end
    if (self.curValue == nil) then
        self.curValue = next(CFCT.spellIdCache)
    end
    local dropDownText
    for _,v in pairs(FilteringBlacklistMenu) do
        if (v.value == self.curValue) then
            dropDownText = v.text
            break
        end
    end
    -- print(self.curValue, dropDownText)
    if (dropDownText) then
        self.Button:Enable()
        filteringBlacklistCheckbox:Enable()
    else
        self.Button:Disable()
        filteringBlacklistCheckbox:Disable()
    end
    _G[self:GetName().."Text"]:SetText(dropDownText or L("Empty: Attack a Dummy"))
end)
filteringBlacklistCheckbox = ConfigPanel:CreateCheckbox(L("Disable By SpellId"),
    L("Stop the selected spell from showing in the damage text"), filteringBlacklistDropdown, "TOPLEFT", "BOTTOMLEFT",
    16, 0, false,
    function(self, e, value) -- luacheck: ignore 212
        local spellIdTable = CFCT.Config.filterSpellBlacklist
        if (e == "Get") then
            local spellid = filteringBlacklistDropdown.curValue
            if spellid then
                local spellval = spellIdTable[spellid]
                if spellval then
                    return spellval
                end
            end
            return false
        elseif (e == "Set") then
            local spellid = filteringBlacklistDropdown.curValue
            if spellid then
                if (value == false) then
                    spellIdTable[spellid] = nil
                else
                    spellIdTable[spellid] = value
                end
                filteringBlacklistDropdown:Hide()
                filteringBlacklistDropdown:Show()
            end
        end
end)

-- -246 instead of -200: the Filtering section gained one 46px checkbox row
-- ("Demote Small Crits"), keeping the original clearance above this header.
local sortingOptionsHeader = ConfigPanel:CreateHeader(L("Sorting Options"), "GameFontNormalLarge", filteringOptionsHeader, "TOPLEFT", "BOTTOMLEFT", 0, -246)
ConfigPanel:CreateCheckbox(L("Sort By Damage/Healing in Descending Order"), L("Sort events by amount"),
    sortingOptionsHeader, "TOPLEFT", "BOTTOMLEFT", 20, -8, DefaultConfig.sortByDamage, "Config.sortByDamage")

local merginOptionsHeader = ConfigPanel:CreateHeader(L("Merging Options"), "GameFontNormalLarge", sortingOptionsHeader, "TOPLEFT", "BOTTOMLEFT", 0, -40)
local mergingEnabledCheckbox = ConfigPanel:CreateCheckbox(L("Merge Events"),
    L("Combine damage/healings events with the same spellid into one event"), merginOptionsHeader, "TOPLEFT",
    "BOTTOMLEFT", 20, -8, DefaultConfig.mergeEvents, "Config.mergeEvents")

local mergingIntervalOverrideDropdown
local mergingOverrideIntervalSlider
local mergingOverrideIntervalResetButton
local MergeIntervalOverrideMenu = {{}}
local mergingIntervalSlider = ConfigPanel:CreateSlider(L("Global Merge Interval"),
    L("Max time interval between events for a merge to happen (in seconds)"), mergingEnabledCheckbox, "LEFT", "RIGHT",
    256, 0, 0.01, 5, 0.01, DefaultConfig.mergeEventsInterval, function(_, e, value)
    if (e == "Get") then
        return CFCT.Config.mergeEventsInterval
    elseif (e == "Set") then
        CFCT.Config.mergeEventsInterval = value
        local id = mergingIntervalOverrideDropdown.curValue
        if id and (CFCT.Config.mergeEventsIntervalOverrides[id] == nil) then
            mergingOverrideIntervalSlider:SetValue(value)
        end
    end
end)
local mergingCountCheckbox = ConfigPanel:CreateCheckbox(L("Show Merge Count"),
    L("Add number of merged events next to the damage/healing (ex '1337 x5')"), mergingEnabledCheckbox, "TOPLEFT",
    "BOTTOMLEFT", 0, 0, DefaultConfig.mergeEventsCounter, "Config.mergeEventsCounter")
local intervalModeHeader = ConfigPanel:CreateHeader(L("Relative To"), "GameFontHighlightSmall", mergingIntervalSlider, "TOPLEFT", "BOTTOMLEFT", 0, -24)
local intervalModeDropDown = ConfigPanel:CreateDropDownMenu(L("Relative To"), "", intervalModeHeader, "LEFT", "LEFT", 68, -3, MergeIntervalModeMenu, "Config.mergeEventsIntervalMode")
intervalModeDropDown.middle:SetWidth(170)

local mergingIntervalOverrideHeader = ConfigPanel:CreateHeader(L("SpellId Override"), "GameFontHighlightSmall", mergingIntervalSlider, "TOPLEFT", "BOTTOMLEFT", 0, -60)



mergingIntervalOverrideDropdown = ConfigPanel:CreateDropDownMenu(L("SpellId Override"), "", mergingIntervalOverrideHeader, "LEFT", "LEFT", 68, -3, MergeIntervalOverrideMenu,
    function(self, e, value)
        if (e == "Get") then
            return value
        elseif (e == "Set") then
            for k,v in pairs(CFCT.Config.mergeEventsIntervalOverrides) do
                if (self.curValue == k) then
                    mergingOverrideIntervalSlider:SetValue(v)
                    return
                end
            end
            mergingOverrideIntervalSlider:SetValue(CFCT.Config.mergeEventsInterval)
        end
end)
mergingIntervalOverrideDropdown.middle:SetWidth(170)
mergingIntervalOverrideDropdown:HookScript("OnShow", function(self)
    wipe(MergeIntervalOverrideMenu)
    local spellIdTable = CFCT.Config.mergeEventsIntervalOverrides
    local color = "FFFFFF"
    for k in pairs(spellIdTable) do
        local entry = SpellMenuEntry(k, color)
        if entry then
            CFCT.spellIdCache[k] = true
            table.insert(MergeIntervalOverrideMenu, entry)
        end
    end
    color = "808080"
    for k in pairs(CFCT.spellIdCache) do
        if (spellIdTable[k] == nil)then
            local entry = SpellMenuEntry(k, color)
            if entry then
                table.insert(MergeIntervalOverrideMenu, entry)
            end
        end
    end
    -- next() returns the first key of the table, which is exactly the key the
    -- old "take the first entry and stop" loop picked. An empty table yields
    -- nil, which leaves curValue unchanged.
    if (self.curValue == nil) then
        self.curValue = next(spellIdTable)
    end
    if (self.curValue == nil) then
        self.curValue = next(CFCT.spellIdCache)
    end
    local dropDownText
    for _,v in pairs(MergeIntervalOverrideMenu) do
        if (v.value == self.curValue) then
            dropDownText = v.text
            break
        end
    end
    -- print(self.curValue, dropDownText)
    if (dropDownText) then
        self.Button:Enable()
        mergingOverrideIntervalSlider:Enable()
        mergingOverrideIntervalSlider.valueBox:Enable()
    else
        self.Button:Disable()
        mergingOverrideIntervalSlider:Disable()
        mergingOverrideIntervalSlider.valueBox:Disable()
        mergingOverrideIntervalResetButton:Disable()
    end
    _G[self:GetName().."Text"]:SetText(dropDownText or L("Empty: Attack a Dummy"))
end)

mergingOverrideIntervalSlider = ConfigPanel:CreateSlider(L("Override Merge Interval"),
    L("Max time interval between chosen spell events for a merge to happen (in seconds)"),
    mergingIntervalOverrideHeader, "TOPLEFT", "BOTTOMLEFT", 0, -20, 0.01, 5, 0.01, DefaultConfig.mergeEventsInterval,
    function(self, e, value) -- luacheck: ignore 212
        local spellIdTable = CFCT.Config.mergeEventsIntervalOverrides
        if (e == "Get") then
            local spellid = mergingIntervalOverrideDropdown.curValue
            if spellid then
                local spellval = spellIdTable[spellid]
                if spellval then
                    return spellval
                end
            end
            return CFCT.Config.mergeEventsInterval
        elseif (e == "Set") then
            local spellid = mergingIntervalOverrideDropdown.curValue
            if spellid then
                if (value == CFCT.Config.mergeEventsInterval) then
                    spellIdTable[spellid] = nil
                    mergingOverrideIntervalResetButton:Disable()
                else
                    spellIdTable[spellid] = value
                    mergingOverrideIntervalResetButton:Enable()
                end
                mergingIntervalOverrideDropdown:Hide()
                mergingIntervalOverrideDropdown:Show()
            end
        end
end)
mergingOverrideIntervalResetButton = ConfigPanel:CreateButton(L("Reset"),
    L("Restores chosen spell merge interval to a common setting"), mergingOverrideIntervalSlider, "TOPRIGHT",
    "BOTTOMRIGHT", -10, 3, function()
    local id = mergingIntervalOverrideDropdown.curValue
    if id then
        mergingOverrideIntervalSlider:SetValue(CFCT.Config.mergeEventsInterval)
    end
end)
mergingOverrideIntervalResetButton:SetFrameLevel(mergingOverrideIntervalSlider:GetFrameLevel()+1)


local mergingMissesCheckbox = ConfigPanel:CreateCheckbox(L("Separate Misses"),
    L("Dont merge dodges, parries, misses, and evades with damage events"), mergingCountCheckbox, "TOPLEFT",
    "BOTTOMLEFT", 0, 0, DefaultConfig.mergeEventsMisses, "Config.mergeEventsMisses")
local mergingByGuidCheckbox = ConfigPanel:CreateCheckbox(L("Separate By Target"),
    L("Dont merge damage done to different targets"), mergingMissesCheckbox, "TOPLEFT", "BOTTOMLEFT", 0, 0,
    DefaultConfig.mergeEventsByGuid, "Config.mergeEventsByGuid")
local mergingByIDCheckbox = ConfigPanel:CreateCheckbox(L("Separate By Spell ID"),
    L("Dont merge damage with different spellids"), mergingByGuidCheckbox, "TOPLEFT", "BOTTOMLEFT", 0, 0,
    DefaultConfig.mergeEventsBySpellID, "Config.mergeEventsBySpellID")
local mergingByIconCheckbox = ConfigPanel:CreateCheckbox(L("Separate By Spell Icon"),
    L("Dont merge damage with different icons"), mergingByIDCheckbox, "TOPLEFT", "BOTTOMLEFT", 0, 0,
    DefaultConfig.mergeEventsBySpellIcon, "Config.mergeEventsBySpellIcon")
ConfigPanel:CreateCheckbox(L("Separate By Damage Type"), L("Dont merge damage of different types"),
    mergingByIconCheckbox, "TOPLEFT", "BOTTOMLEFT", 0, 0, DefaultConfig.mergeEventsBySchool,
    "Config.mergeEventsBySchool")

-- damage type colors
local colorTableHeader = ConfigPanel:CreateHeader(L("Damage Type Colors"), "GameFontNormalLarge", merginOptionsHeader, "TOPLEFT", "TOPLEFT", 0, -220)
local colorTableFrame = ConfigPanel:CreateChildFrame("TOPLEFT", "BOTTOMLEFT", colorTableHeader, 0, 10, 500, 200)
local colorTableX, colorTableY, colorTableCounter = 20, 0, 0

for k,v in pairs(SCHOOL_NAMES) do
    colorTableCounter = colorTableCounter + 1
    if (colorTableY < -150) then
        colorTableX = colorTableX + 150
        colorTableY = 0
    end
    colorTableY = colorTableY - 20
    colorTableFrame:CreateColorOption(v, L("Custom text color for this type"), colorTableFrame, "TOPLEFT", "TOPLEFT", colorTableX, colorTableY, DefaultConfig.colorTable[k],
        function(self, e, value) -- luacheck: ignore 212
            if (e == "Get") then
                return CFCT.Config.colorTable[k]
            else
                CFCT.Config.colorTable[k] = value
            end
    end)
end

-- damage over time type colors
local colorTableDotHeader = ConfigPanel:CreateHeader(L("Override Type Colors for Damage Over Time"), "GameFontNormalLarge", colorTableHeader, "TOPLEFT", "TOPLEFT", 0, -200)
local colorTableDotFrame = ConfigPanel:CreateChildFrame("TOPLEFT", "BOTTOMLEFT", colorTableDotHeader, 0, -20, 500, 200)

local colorTableDotCheckbox = ConfigPanel:CreateCheckbox(L("Enabled"),
    L("Use separate type colors for damage over time"), colorTableDotHeader, "TOPLEFT", "BOTTOMLEFT", 20, -8,
    DefaultConfig.colorTableDotEnabled,
    function(self, e, value) -- luacheck: ignore 212
        if (e == "Get") then
            local val = CFCT.Config.colorTableDotEnabled
            if (val == true) then
                colorTableDotFrame:Enable()
            else
                colorTableDotFrame:Disable()
            end
            return val
        else
            if (value == true) then
                colorTableDotFrame:Enable()
            else
                colorTableDotFrame:Disable()
            end
            CFCT.Config.colorTableDotEnabled = value
        end
end)

local copyTypeColorsBtn = ConfigPanel:CreateButton(L("Copy From Above"), L("Copies color settings from the damage types above"), colorTableDotCheckbox, "LEFT", "RIGHT", 190, 0, function()
    CFCT:ConfirmAction(L("This will overwrite all color settings below."), function()
        for k in pairs(SCHOOL_NAMES) do
            CFCT.Config.colorTableDot[k] = CFCT.Config.colorTable[k]
        end
        colorTableDotFrame:Refresh()
    end)
end)


copyTypeColorsBtn:SetWidth(120)
local colorTableDotX, colorTableDotY, colorTableDotCounter = 20, 0, 0

for k,v in pairs(SCHOOL_NAMES) do
    colorTableDotCounter = colorTableDotCounter + 1
    if (colorTableDotY < -150) then
        colorTableDotX = colorTableDotX + 150
        colorTableDotY = 0
    end
    colorTableDotY = colorTableDotY - 20
    colorTableDotFrame:CreateColorOption(v, L("Custom text color for this type"), colorTableDotFrame, "TOPLEFT",
        "TOPLEFT", colorTableDotX, colorTableDotY, DefaultConfig.colorTableDot[k],
        function(self, e, value) -- luacheck: ignore 212
            if (e == "Get") then
                return CFCT.Config.colorTableDot[k]
            else
                CFCT.Config.colorTableDot[k] = value
            end
    end)
end

-- Off-target dimming, at the BOTTOM of the panel.
--
-- The "Dim Off-Target Text" checkbox stays up top with the other text-position
-- settings (see the note where it is created), and the two sliders that
-- control HOW MUCH the off-target text is dimmed live here, in a column of
-- their own. That column has nothing else in it, so nothing can be drawn over
-- these labels or their value boxes.
--
-- The sliders are 46 pixels apart: a slider's value box hangs below its track
-- and its label sits above it, so a row is about 43 pixels tall. A tighter
-- pitch put the value box of one slider over the label of the next.
local offTargetHeader = ConfigPanel:CreateHeader(L("Off-Target Dimming"), "GameFontNormalLarge", colorTableDotFrame,
    "TOPLEFT", "BOTTOMLEFT", 0, -24)
local offTargetSizeSlider = ConfigPanel:CreateSlider(L("Off-Target Size Scale"),
    L("Size multiplier for off-target numbers"), offTargetHeader, "TOPLEFT", "BOTTOMLEFT", 20, -20, 0.3, 1.0, 0.01,
    DefaultConfig.offTarget.sizeScale, "Config.offTarget.sizeScale")
offTargetSizeSlider:SetWidth(230)
local offTargetAlphaSlider = ConfigPanel:CreateSlider(L("Off-Target Alpha"),
    L("Opacity multiplier for off-target numbers"), offTargetSizeSlider, "TOPLEFT", "BOTTOMLEFT", 0, -46, 0.1, 1.0,
    0.05, DefaultConfig.offTarget.alpha, "Config.offTarget.alpha")
offTargetAlphaSlider:SetWidth(230)


local CONFIG_LAYOUT = {
    {
        catname = L("Auto Attacks"),
        subcatlist = {
            "auto",
            "autocrit",
            "automiss"
        }
    },
    {
        catname = L("Special Attacks"),
        subcatlist = {
            "spell",
            "spellcrit",
            "spellmiss"
        }
    },
    {
        catname = L("Damage Over Time"),
        subcatlist = {
            "spelltick",
            "spelltickcrit",
            "spelltickmiss"
        }
    },
    {
        catname = L("Heals"),
        subcatlist = {
            "heal",
            "healcrit",
            "healmiss"
        }
    },
    {
        catname = L("Heals Over Time"),
        subcatlist = {
            "healtick",
            "healtickcrit",
            "healtickmiss"
        }
    },
    {
        catname = L("Pet Auto Attacks"),
        subcatlist = {
            "petauto",
            "petautocrit",
            "petautomiss"
        }
    },
    {
        catname = L("Pet Special Attacks"),
        subcatlist = {
            "petspell",
            "petspellcrit",
            "petspellmiss"
        }
    },
    {
        catname = L("Pet Damage Over Time"),
        subcatlist = {
            "petspelltick",
            "petspelltickcrit",
            "petspelltickmiss"
        }
    },
    {
        catname = L("Pet Heals"),
        subcatlist = {
            "petheal",
            "pethealcrit",
            "pethealmiss"
        }
    },
    {
        catname = L("Pet Heals Over Time"),
        subcatlist = {
            "pethealtick",
            "pethealtickcrit",
            "pethealtickmiss"
        }
    }
}

ConfigPanel:HookScript("OnShow", function(self) if self then CFCT._testMode = true end end)
ConfigPanel:HookScript("OnHide", function(self) if self then CFCT._testMode = false end end)
for _, cat in ipairs(CONFIG_LAYOUT) do
    local subpanel = ConfigPanel:CreateSubPanel(cat.catname)
    subpanel:HookScript("OnShow", function(self) if self then CFCT._testMode = true end end)
    subpanel:HookScript("OnHide", function(self) if self then CFCT._testMode = false end end)
    local parent = nil
    for _, subcat in ipairs(cat.subcatlist) do
        if not parent then
            parent = subpanel:CreateCategoryPanel(subcat, subpanel, "TOPLEFT", "TOPLEFT", 6, -6)
        else
            parent = subpanel:CreateCategoryPanel(subcat, parent, "TOPLEFT", "BOTTOMLEFT", 0, -6)
        end
    end
end


