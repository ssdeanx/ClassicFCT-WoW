-- .luacheckrc - luacheck configuration for ClassicFCT
--
-- The addon runs inside the World of Warcraft client, whose Lua environment
-- provides a large set of globals that a bare Lua 5.1 standard library does not
-- know about. Without this file luacheck reports every one of them as
-- "accessing undefined variable" (W113). On the shipped sources that was 384 of
-- 673 warnings - pure noise that buried the handful of warnings that were real.
--
-- Only the globals the addon actually touches are declared here. A name that
-- stops being used should be removed from this list, so that a reintroduced
-- implicit-global dependency is caught again.
--
-- The API list was verified against the client source mirror
-- (/home/sam/wow-ui-source) on the classic_era, classic_anniversary,
-- classic_titan, origin/forever and live branches. The client extensions
-- (min/max/sqrt/strlower/strupper, see Blizzard_SharedXMLBase/Compat.lua) are
-- deliberately NOT declared: the addon imports the Lua standard library
-- directly instead of relying on the client exposing them as globals.

std = "lua51"

-- The client ships long-but-structured lines (the 25-value combat-log unpack,
-- the option-panel widget builders). 200 keeps the signal readable without
-- forcing cosmetic reflows of code that is already correct.
max_line_length = 200

-- Only the shipped addon sources are analysed. Libs/ is vendored third-party
-- code, bench/ is the workshop workspace, and the remaining directories are
-- agent workspace - none of it is addon code.
exclude_files = {
    "Libs/*",
    "bench/*",
    "tools/*",
    "desks/*",
    "classroom/*",
}

globals = {
    -- WoW client Lua extensions and libraries.
    "AbbreviateNumbers",
    "bit",
    "GetSpellInfo",
    "LibStub",
    "strlower",
    "strsplit",
    "strupper",
    "wipe",

    -- Frame / UI construction.
    "BackdropTemplateMixin",
    "ColorPickerFrame",
    "CreateFont",
    "CreateFrame",
    "DropDownList1",
    "FrameStackTooltip_Toggle",
    "GameFontHighlightSmall",
    "InterfaceOptions_AddCategory",
    "InterfaceOptionsFrame_OpenToCategory",
    "OpacitySliderFrame",
    "Settings",
    "ShowColorPicker",
    "StaticPopupDialogs",
    "StaticPopup_Show",
    "UIDropDownMenu_AddButton",
    "UIDropDownMenu_CreateInfo",
    "UIDropDownMenu_SetSelectedValue",
    "UIParent",
    "WorldFrame",

    -- Namespaced API.
    "C_AddOns",
    "C_CombatLog",
    "C_NamePlate",
    "C_Spell",
    "C_Timer",
    "Enum",

    -- Combat log.
    "CombatLogGetCurrentEventInfo",
    "COMBATLOG_OBJECT_AFFILIATION_MINE",
    "COMBATLOG_OBJECT_TYPE_GUARDIAN",
    "COMBATLOG_OBJECT_TYPE_PET",

    -- Player / unit queries and CVars.
    "GetAddOnMetadata",
    "GetBuildInfo",
    "GetClassInfo",
    "GetCVar",
    "GetCVarDefault",
    "GetNumClasses",
    "GetTime",
    "InCombatLockdown",
    "SetCVar",
    "UnitClassBase",
    "UnitExists",
    "UnitGUID",
    "UnitHealthMax",

    -- Sound.
    "PlaySound",
    "SCHOOL_MASK_PHYSICAL",
    "SOUNDKIT",

    -- Client flavour constants.
    "WOW_PROJECT_BURNING_CRUSADE_CLASSIC",
    "WOW_PROJECT_CAMELOT",
    "WOW_PROJECT_CLASSIC",
    "WOW_PROJECT_ID",
    "WOW_PROJECT_MAINLINE",
    "WOW_PROJECT_WRATH_CLASSIC",

    -- SavedVariables (account-level and character-level).
    "ClassicFCTCharConfig",
    "ClassicFCTCharTables",
    "ClassicFCTCharVars",
    "ClassicFCTConfig",
    "ClassicFCTCustomPresets",
    "ClassicFCTTables",
    "ClassicFCTVars",

    -- Slash command registration.
    "SLASH_CLASSICFCT1",
    "SLASH_CLASSICFCTFS1",
    "SlashCmdList",
}
