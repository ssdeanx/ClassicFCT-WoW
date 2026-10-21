local addonName, CFCT = ...
local L = CFCT.L
_G[addonName] = CFCT
-- Client flavor detection.
-- WOW_PROJECT_CAMELOT (18) is WoW Forever; origin/forever ships interface 16001 and has no
-- FrameXML constants file of its own (Blizzard_ProjectConstants/Camelot/ProjectConstants.lua).
local WOW_PROJECT_CAMELOT = _G.WOW_PROJECT_CAMELOT or 18
local IsClassic = (WOW_PROJECT_ID == (WOW_PROJECT_CLASSIC or 2))
local IsBCC = (WOW_PROJECT_ID == (WOW_PROJECT_BURNING_CRUSADE_CLASSIC or 5))
local IsRetail = (WOW_PROJECT_ID == (WOW_PROJECT_MAINLINE or 1))
local _tocVersion = (type(GetBuildInfo) == "function") and select(4, GetBuildInfo()) or 0
local IsTitan = (WOW_PROJECT_ID == (WOW_PROJECT_WRATH_CLASSIC or 11))
local IsWoWForever = (WOW_PROJECT_ID == WOW_PROJECT_CAMELOT) or (_tocVersion == 16001)
-- Clients that still hand the legacy combat log to addons: vanilla/SoD, TBC and Wrath.
local IsLegacyClient = IsClassic or IsBCC or IsTitan
-- Combat is restricted on Retail/Midnight and WoW Forever: COMBAT_LOG_EVENT_UNFILTERED is
-- unavailable to tainted addons and no public API exposes outgoing damage for arbitrary targets.
-- Unrecognised project IDs are treated as restricted too (fail closed).
local IsRestrictedCombat = IsRetail or IsWoWForever or not IsLegacyClient
-- Latched once per session: the probe itself failing is a different failure mode
-- from "this value happens to be secret", and only the former silently disables
-- every number on screen.
local secretProbeFailed = false
local function IsSecretValue(v)
    -- Resolve the probe LAZILY, every time. The client may export
    -- `_G.issecretvalue` after this file has loaded, so a probe captured at
    -- file scope would be stuck at nil for the whole session.
    --
    -- If there is no probe we cannot prove the value is safe to use, so this
    -- branch FAILS CLOSED: treat the value as secret and suppress it. The
    -- opposite direction (treating it as safe) would silently format
    -- restricted values into the combat text. Both probe-failure modes
    -- (absent, and present-but-raising) therefore suppress combat text, and
    -- both report themselves exactly once.
    local probe = _G.issecretvalue
    if (type(probe) ~= "function") then
        if not secretProbeFailed then
            secretProbeFailed = true
            if (type(CFCT.Log) == "function") then
                CFCT:Log("the secret-value probe is unavailable, so all combat text is suppressed. This is a client problem, not a configuration one.")
            end
        end
        return true
    end
    -- Keep every operation on the result inside the protected call so a restricted boolean
    -- can never escape into a caller's `if`. If the probe cannot be reduced to a plain
    -- boolean, fail closed (treat as secret) instead of using the value.
    local ok, res = pcall(function()
        if probe(v) == true then return 1 end
        return 0
    end)
    if not ok then
        -- Fail closed exactly as before, but report the probe failure once: a broken
        -- probe suppresses every combat event, and silence would look like a
        -- configuration problem instead of a client problem.
        if not secretProbeFailed then
            secretProbeFailed = true
            if (type(CFCT.Log) == "function") then
                CFCT:Log("the secret-value probe failed, so all combat text is suppressed. This is a client problem, not a configuration one.")
            end
        end
        return true
    end
    return res == 1
end

-- The crit flag arrives from the combat log as a BOOLEAN on every supported
-- client: Blizzard's own parser tests it with `if critical then`
-- (Blizzard_CombatLogBase/CombatLogUtil.lua on every branch), which only
-- works for a boolean or nil.
--
-- Lua, however, treats the NUMBER 0 as true. A client that delivered 0/1
-- would therefore make EVERY hit read as a crit: the numbers would all be
-- styled as crits, the small-crit demotion would apply to all of them, and
-- the crit-specific filters would swallow non-crit hits. The flag is
-- normalised to a real boolean here so the value cannot be misread whichever
-- form a client delivers.
--
-- This runs AFTER the secret-value guard above: comparing a secret value
-- raises, and a secret value must never be inspected.
local function IsCritFlag(value)
    return (value == true) or (value == 1)
end

-- Imported explicitly instead of relying on the client exposing math/string
-- helpers as globals (sqrt/min/max/strlower/strupper were implicit globals).
-- The imports are split over three statements purely for line length; the name
-- list and the value list are identical to the original single statement, in
-- the same order.
local tinsert, tremove, format, strlen, strsub, gsub, floor = table.insert, table.remove, string.format, string.len, string.sub, string.gsub, math.floor
local sin, cos, asin, acos, sqrt, min, max, random = math.sin, math.cos, math.asin, math.acos, math.sqrt, math.min, math.max, math.random
local select, pairs, ipairs, unpack, bitband = select, pairs, ipairs, unpack, bit.band
local lower, upper = string.lower, string.upper
local InCombatLockdown = InCombatLockdown
local AbbreviateNumbers = AbbreviateNumbers
local GetTime = GetTime
local GetAddOnMetadata = GetAddOnMetadata or C_AddOns.GetAddOnMetadata

local GetSpellInfo_old = GetSpellInfo
-- The shim is TOTAL: it never raises and never returns nil. If the legacy
-- global is gone AND C_Spell is missing, it returns an empty table, so a
-- caller gets "no spell data" rather than a load-time crash. (C_Spell is
-- present on all five supported clients, so this is defence in depth.)
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

CFCT.frame = CreateFrame("Frame", "ClassicFCT.frame", UIParent)
CFCT.Animating = {}
CFCT.fontStringCache = {}
-- CFCT.Debug = true

local now = GetTime()
local f = CFCT.frame
f:SetSize(1,1)

-- The `textStrata` preset key (Presets/Classic.lua, Presets/ClassicPlus.lua,
-- Presets/MoP.lua) is applied to the PARENT frame, not to a FontString.
-- SetFrameStrata is a Frame method: Region/FontString only expose
-- Get/SetDrawLayer (see Blizzard_APIDocumentationGenerated/SimpleFrameAPIDocumentation.lua
-- and SimpleRegionAPIDocumentation.lua on classic_era and live), so the old
-- per-FontString call could never have worked and would have raised on every
-- number. The parent frame is a Frame, and its strata are inherited by the
-- FontStrings it creates, so this is where the setting belongs.
-- Re-applied whenever the config is loaded or the preset changes, because the
-- frame's strata are not part of the persisted config.
local function ApplyTextStrata()
    local strata = CFCT.Config and CFCT.Config.textStrata
    if (type(strata) ~= "string" or strata == "") then strata = "MEDIUM" end
    -- Only a frame we own is touched, and only with a real strata name.
    pcall(function() f:SetFrameStrata(strata) end)
end
-- config.lua owns the config lifecycle, so it calls this after any change
-- that could alter the setting (load, preset apply, defaults restore).
CFCT.ApplyTextStrata = ApplyTextStrata
f:SetPoint("CENTER", 0, 0)

local anim = CFCT.Animating
local fsc = CFCT.fontStringCache

-- Angle of a 2D vector (atan2 substitute rebuilt from the wrapped trig helpers).
local function VectorAngle(x, y)
    local len = sqrt(x * x + y * y)
    if (len == 0) then return 0 end
    local rx = max(-1, min(1, x / len))
    local ry = max(-1, min(1, y / len))
    if (rx >= 0) then return asin(ry) end
    return (ry < 0) and -acos(rx) or acos(rx)
end

local damageRollingAverage = 0
-- The receiver is part of the method signature but the getter does not need it.
function CFCT:DamageRollingAverage() -- luacheck: ignore 212
    return damageRollingAverage
end

local ROLLING_AVERAGE_LENGTH = 10
local rollingAverageTimer = 0
local damageCache = {}
local function AddToAverage(value)
    -- Test-mode numbers are synthetic. They must never enter the rolling average,
    -- because that average drives the real "Hide Below Average Threshold" filter.
    if CFCT._testMode then return end
    tinsert(damageCache, {
        value = value,
        time = now
    })
end
local ROLLINGAVERAGE_UPDATE_INTERVAL = 0.5
local function CalculateRollingAverage()
    local cacheSize = #damageCache
    local damage, count = 0, 0
    -- The average is a ROLLING_AVERAGE_LENGTH window, so entries are aged out on
    -- every pass regardless of how many are cached (the old `cacheSize > 200` gate
    -- meant a quiet session averaged every hit ever recorded).
    -- Iterate backwards: tremove shifts the tail down, so removing while ipairs()
    -- walks forward would skip the element that moved into the freed slot.
    for k = cacheSize, 1, -1 do
        local v = damageCache[k]
        if v and ((now - v.time) > ROLLING_AVERAGE_LENGTH) then
            tremove(damageCache, k)
        else
            damage = damage + v.value
            count = count + 1
        end
    end
    damageRollingAverage = count > 0 and damage / count or 0
end


local function FormatThousandSeparator(v)
    local s = format("%d", floor(v))
    local pos = strlen(s) % 3
    if pos == 0 then pos = 3 end
    return strsub(s, 1, pos)..gsub(strsub(s, pos+1), "(...)", ",%1")
end

local function InitFont(self, state)
    local fontOptions = state.fontOptions
    self:SetFont(fontOptions.fontPath, fontOptions.fontSize, fontOptions.fontStyle)
    self:SetShadowOffset(fontOptions.fontSize/14, fontOptions.fontSize/14)
    self:SetDrawLayer("OVERLAY")
    self:SetJustifyH("CENTER")
    self:SetJustifyV("MIDDLE")
    -- self:SetPoint("BOTTOM", 0, 0)
    self:SetText(state.text)
    self:SetTextColor(unpack(fontOptions.fontColor))
    self:SetAlpha(fontOptions.fontAlpha)
    self:SetShadowColor(0,0,0,fontOptions.fontAlpha/2)
    state.initialTime = now
    state.strHeight = self:GetStringHeight()
    state.strWidth = self:GetStringWidth()
    state.posX = 0
    state.posY = 0
    state.direction = 0
    self.state = state
    self:Hide()
    return self
end

local function ReleaseFont(self)
    self.state = nil
    self:Hide()
    tinsert(fsc, self)
end

local function CheckCollision(x1, y1, w1, h1, x2, y2, w2, h2)
    local overlapX = x1 < x2 and w1 - (x2 - x1) or w2 -( x1 - x2)
    local overlapY = y1 < y2 and h1 - (y2 - y1) or h2 - (y1 - y2)
    if (overlapX > 0 and overlapY > 0) then
        return overlapX, overlapY
    end
end

local GRID = {
    false,
    {y={o=1, p=1}},
    {x={o=1, p=1}},
    {y={o=-1, p=1}},
    {x={o=-1, p=1}},
    {x={o=1, p=2}, y={o=1, p=3}},
    {x={o=1, p=4}, y={o=-1, p=3}},
    {x={o=-1, p=2}, y={o=1, p=5}},
    {x={o=-1, p=4}, y={o=-1, p=5}},
    {y={o=1, p=2}},
    {x={o=1, p=3}},
    {y={o=-1, p=4}},
    {x={o=-1, p=5}},
    {x={o=1, p=6}, y={o=1, p=11}},
    {x={o=1, p=7}, y={o=-1, p=11}},
    {x={o=-1, p=8}, y={o=1, p=13}},
    {x={o=-1, p=9}, y={o=-1, p=13}},
    {x={o=1, p=10}, y={o=1, p=6}},
    {x={o=1, p=12}, y={o=-1, p=7}},
    {x={o=-1, p=10}, y={o=1, p=8}},
    {x={o=-1, p=12}, y={o=-1, p=9}},
    {y={o=1, p=10}},
    {x={o=1, p=11}},
    {y={o=-1, p=12}},
    {x={o=-1, p=13}},
    {x={o=1, p=18}, y={o=1, p=14}},
    {x={o=1, p=19}, y={o=-1, p=15}},
    {x={o=-1, p=20}, y={o=1, p=16}},
    {x={o=-1, p=21}, y={o=-1, p=17}},
    {x={o=1, p=22}, y={o=1, p=18}},
    {x={o=1, p=14}, y={o=1, p=23}},
    {x={o=1, p=15}, y={o=-1, p=23}},
    {x={o=1, p=24}, y={o=-1, p=19}},
    {x={o=-1, p=24}, y={o=-1, p=21}},
    {x={o=-1, p=16}, y={o=1, p=25}},
    {x={o=-1, p=17}, y={o=-1, p=25}},
    {x={o=-1, p=22}, y={o=1, p=20}},
    {y={o=1, p=22}},
    {x={o=1, p=23}},
    {y={o=-1, p=24}},
    {x={o=-1, p=25}},
    {x={o=1, p=30}, y={o=1, p=26}},
    {x={o=1, p=33}, y={o=-1, p=27}},
    {x={o=-1, p=34}, y={o=-1, p=29}},
    {x={o=-1, p=37}, y={o=1, p=28}},
    {x={o=1, p=26}, y={o=1, p=31}},
    {x={o=1, p=27}, y={o=-1, p=32}},
    {x={o=-1, p=28}, y={o=1, p=35}},
    {x={o=-1, p=29}, y={o=-1, p=36}},
    {x={o=1, p=38}, y={o=1, p=30}},
    {x={o=1, p=31}, y={o=1, p=39}},
    {x={o=1, p=32}, y={o=-1, p=39}},
    {x={o=1, p=40}, y={o=-1, p=33}},
    {x={o=-1, p=40}, y={o=-1, p=34}},
    {x={o=-1, p=35}, y={o=1, p=41}},
    {x={o=-1, p=36}, y={o=-1, p=41}},
    {x={o=-1, p=38}, y={o=1, p=37}},
    {y={o=1, p=38}},
    {x={o=1, p=39}},
    {y={o=-1, p=40}},
    {x={o=-1, p=41}},
    {x={o=1, p=50}, y={o=1, p=42}},
    {x={o=1, p=53}, y={o=-1, p=43}},
    {x={o=-1, p=57}, y={o=1, p=45}},
    {x={o=-1, p=54}, y={o=-1, p=44}},
    {x={o=1, p=42}, y={o=1, p=46}},
    {x={o=1, p=43}, y={o=-1, p=47}},
    {x={o=-1, p=45}, y={o=1, p=48}},
    {x={o=-1, p=44}, y={o=-1, p=49}},
    {x={o=1, p=46}, y={o=1, p=51}},
    {x={o=1, p=47}, y={o=-1, p=52}},
    {x={o=-1, p=48}, y={o=1, p=55}},
    {x={o=-1, p=49}, y={o=-1, p=56}},
    {x={o=1, p=58}, y={o=1, p=50}},
    {x={o=1, p=51}, y={o=1, p=59}},
    {x={o=1, p=52}, y={o=-1, p=59}},
    {x={o=1, p=60}, y={o=-1, p=53}},
    {x={o=-1, p=60}, y={o=-1, p=54}},
    {x={o=-1, p=55}, y={o=1, p=61}},
    {x={o=-1, p=56}, y={o=-1, p=61}},
    {x={o=-1, p=58}, y={o=1, p=57}},
    {y={o=1, p=58}},
    {x={o=1, p=59}},
    {y={o=-1, p=60}},
    {x={o=-1, p=61}},
    {x={o=1, p=62}, y={o=1, p=66}},
    {x={o=1, p=63}, y={o=-1, p=67}},
    {x={o=-1, p=65}, y={o=-1, p=69}},
    {x={o=-1, p=64}, y={o=1, p=68}},
    {x={o=1, p=66}, y={o=1, p=70}},
    {x={o=1, p=67}, y={o=-1, p=71}},
    {x={o=-1, p=68}, y={o=1, p=72}},
    {x={o=-1, p=69}, y={o=-1, p=73}},
    {x={o=1, p=74}, y={o=1, p=62}},
    {x={o=1, p=77}, y={o=-1, p=63}},
    {x={o=-1, p=81}, y={o=1, p=64}},
    {x={o=-1, p=78}, y={o=-1, p=65}},
    {x={o=1, p=70}, y={o=1, p=75}},
    {x={o=1, p=71}, y={o=-1, p=76}},
    {x={o=-1, p=72}, y={o=1, p=79}},
    {x={o=-1, p=73}, y={o=-1, p=80}},
    {x={o=1, p=82}, y={o=1, p=74}},
    {x={o=1, p=84}, y={o=-1, p=77}},
    {x={o=-1, p=84}, y={o=-1, p=78}},
    {x={o=-1, p=82}, y={o=1, p=81}},
    {x={o=1, p=75}, y={o=1, p=83}},
    {x={o=1, p=76}, y={o=-1, p=83}},
    {x={o=-1, p=79}, y={o=1, p=85}},
    {x={o=-1, p=80}, y={o=-1, p=85}},
    {y={o=1, p=82}},
    {x={o=1, p=83}},
    {y={o=-1, p=84}},
    {x={o=-1, p=85}},
    {x={o=1, p=86}, y={o=1, p=90}},
    {x={o=1, p=87}, y={o=-1, p=91}},
    {x={o=-1, p=89}, y={o=1, p=92}},
    {x={o=-1, p=88}, y={o=-1, p=93}},
    {x={o=1, p=94}, y={o=1, p=86}},
    {x={o=1, p=95}, y={o=-1, p=87}},
    {x={o=-1, p=96}, y={o=1, p=89}},
    {x={o=-1, p=97}, y={o=-1, p=88}},
    {x={o=1, p=102}, y={o=1, p=94}},
    {x={o=1, p=103}, y={o=-1, p=95}},
    {x={o=-1, p=105}, y={o=1, p=96}},
    {x={o=-1, p=104}, y={o=-1, p=97}},
    {x={o=1, p=90}, y={o=1, p=98}},
    {x={o=1, p=91}, y={o=-1, p=99}},
    {x={o=-1, p=92}, y={o=1, p=100}},
    {x={o=-1, p=93}, y={o=-1, p=101}},
    {x={o=1, p=110}, y={o=1, p=102}},
    {x={o=1, p=112}, y={o=-1, p=103}},
    {x={o=-1, p=110}, y={o=1, p=105}},
    {x={o=-1, p=112}, y={o=-1, p=104}},
    {x={o=1, p=98}, y={o=1, p=106}},
    {x={o=1, p=99}, y={o=-1, p=107}},
    {x={o=-1, p=100}, y={o=1, p=108}},
    {x={o=-1, p=101}, y={o=-1, p=109}},
    {x={o=1, p=106}, y={o=1, p=111}},
    {x={o=1, p=107}, y={o=-1, p=111}},
    {x={o=-1, p=108}, y={o=1, p=113}},
    {x={o=-1, p=109}, y={o=-1, p=113}},
    {x={o=1, p=118}, y={o=1, p=114}},
    {x={o=1, p=119}, y={o=-1, p=115}},
    {x={o=-1, p=120}, y={o=1, p=116}},
    {x={o=-1, p=121}, y={o=-1, p=117}},
    {x={o=1, p=122}, y={o=1, p=118}},
    {x={o=1, p=123}, y={o=-1, p=119}},
    {x={o=-1, p=124}, y={o=1, p=120}},
    {x={o=-1, p=125}, y={o=-1, p=121}},
    {x={o=1, p=114}, y={o=1, p=126}},
    {x={o=1, p=115}, y={o=-1, p=127}},
    {x={o=-1, p=116}, y={o=1, p=128}},
    {x={o=-1, p=117}, y={o=-1, p=129}},
    {x={o=1, p=126}, y={o=1, p=134}},
    {x={o=1, p=127}, y={o=-1, p=135}},
    {x={o=-1, p=128}, y={o=1, p=136}},
    {x={o=-1, p=129}, y={o=-1, p=137}},
    {x={o=1, p=130}, y={o=1, p=122}},
    {x={o=1, p=131}, y={o=-1, p=123}},
    {x={o=-1, p=132}, y={o=1, p=124}},
    {x={o=-1, p=133}, y={o=-1, p=125}},
    {x={o=1, p=134}, y={o=1, p=138}},
    {x={o=1, p=135}, y={o=-1, p=139}},
    {x={o=-1, p=136}, y={o=1, p=140}},
    {x={o=-1, p=137}, y={o=-1, p=141}},
    {x={o=1, p=142}, y={o=1, p=150}},
    {x={o=1, p=143}, y={o=-1, p=151}},
    {x={o=-1, p=144}, y={o=1, p=152}},
    {x={o=-1, p=145}, y={o=-1, p=153}},
    {x={o=1, p=146}, y={o=1, p=142}},
    {x={o=1, p=147}, y={o=-1, p=143}},
    {x={o=-1, p=148}, y={o=1, p=144}},
    {x={o=-1, p=149}, y={o=-1, p=145}},
    {x={o=1, p=150}, y={o=1, p=154}},
    {x={o=1, p=151}, y={o=-1, p=155}},
    {x={o=-1, p=152}, y={o=1, p=156}},
    {x={o=-1, p=153}, y={o=-1, p=157}},
    {x={o=1, p=158}, y={o=1, p=146}},
    {x={o=1, p=159}, y={o=-1, p=147}},
    {x={o=-1, p=160}, y={o=1, p=148}},
    {x={o=-1, p=161}, y={o=-1, p=149}},
    {x={o=1, p=154}, y={o=1, p=162}},
    {x={o=1, p=155}, y={o=-1, p=163}},
    {x={o=-1, p=156}, y={o=1, p=164}},
    {x={o=-1, p=157}, y={o=-1, p=165}},
    {x={o=1, p=170}, y={o=1, p=166}},
    {x={o=1, p=171}, y={o=-1, p=167}},
    {x={o=-1, p=172}, y={o=1, p=168}},
    {x={o=-1, p=173}, y={o=-1, p=169}},
    {x={o=1, p=178}, y={o=1, p=170}},
    {x={o=1, p=179}, y={o=-1, p=171}},
    {x={o=-1, p=180}, y={o=1, p=172}},
    {x={o=-1, p=181}, y={o=-1, p=173}},
    {x={o=1, p=166}, y={o=1, p=174}},
    {x={o=1, p=167}, y={o=-1, p=175}},
    {x={o=-1, p=168}, y={o=1, p=176}},
    {x={o=-1, p=169}, y={o=-1, p=177}},
    {x={o=1, p=174}, y={o=1, p=182}},
    {x={o=1, p=175}, y={o=-1, p=183}},
    {x={o=-1, p=176}, y={o=1, p=184}},
    {x={o=-1, p=177}, y={o=-1, p=185}},
    {x={o=1, p=186}, y={o=1, p=194}},
    {x={o=-1, p=188}, y={o=1, p=196}},
    {x={o=1, p=187}, y={o=-1, p=195}},
    {x={o=1, p=190}, y={o=1, p=186}},
    {x={o=1, p=191}, y={o=-1, p=187}},
    {x={o=-1, p=192}, y={o=1, p=188}},
    {x={o=-1, p=193}, y={o=-1, p=189}},
    {x={o=1, p=194}, y={o=1, p=198}},
    {x={o=1, p=195}, y={o=-1, p=199}},
    {x={o=-1, p=196}, y={o=1, p=200}},
    {x={o=-1, p=197}, y={o=-1, p=201}},
    {x={o=1, p=205}, y={o=1, p=202}},
    {x={o=1, p=206}, y={o=-1, p=204}},
    {x={o=-1, p=207}, y={o=1, p=203}},
    {x={o=-1, p=208}, y={o=-1, p=204}},
    {x={o=1, p=202}, y={o=1, p=209}},
    {x={o=1, p=204}, y={o=-1, p=210}},
    {x={o=-1, p=203}, y={o=1, p=211}},
    {x={o=-1, p=204}, y={o=-1, p=212}},
    {x={o=1, p=213}, y={o=1, p=217}},
    {x={o=1, p=214}, y={o=-1, p=218}},
    {x={o=-1, p=215}, y={o=1, p=219}},
    {x={o=-1, p=216}, y={o=-1, p=220}},
}


-- local gapX = 30
-- local gapY = 50
-- Per-animation-area state for the overlap resolve. `count` is the number of
-- frames the area held the last time the resolve ran; the per-frame sizes are
-- stored on the frame state itself (resolvedWidth / resolvedHeight).
local layoutAreas = {}
local function GridLayout(unsortedFrames, areaKey)
    local fctConfig = CFCT.Config
    local frames = {}
    if fctConfig.sortByDamage then
        local missPrio = fctConfig.sortMissPrio
        local count = 0
        for k,v in ipairs(unsortedFrames) do
            if (k == 1) then
                tinsert(frames, v)
                count = count + 1
            else
                local s1 = v.state
                for i,e in ipairs(frames) do
                    local s2 = e.state
                    if (not s2.miss and not s1.miss) and (s2.amount < s1.amount) then
                        tinsert(frames, i, v)
                        count = count + 1
                        break
                    elseif (s1.miss ~= s2.miss) and ((s1.miss and missPrio) or not s1.miss) then
                        tinsert(frames, i, v)
                        count = count + 1
                        break
                    elseif (i == count) then
                        tinsert(frames, i + 1, v)
                        count = count + 1
                        break
                    end
                end
            end
        end
    else
        frames = unsortedFrames
    end
    local gapX = fctConfig.preventOverlapSpacingX
    local gapY = fctConfig.preventOverlapSpacingY
    for k, e in ipairs(frames) do
        -- frame mode
        -- local gapX, gapY = gapX * e.state.baseScale, gapY * e.state.baseScale
        local gridCell = GRID[k]
        local gridX = gridCell and (gridCell.x and frames[gridCell.x.p].state.gridX
            + gridCell.x.o * (gapX + frames[gridCell.x.p].state.width + 0.5*(e.state.width - frames[gridCell.x.p].state.width)))
            or 0
        local gridY = gridCell and (gridCell.y and frames[gridCell.y.p].state.gridY + gridCell.y.o * (gapY + (gridCell.y.o < 0 and e.state.height or frames[gridCell.y.p].state.height))) or 0
        if gridCell or k == 1 then
            if (e.state.gridIdx and (e.state.gridIdx ~= k)) then
                e.state.scrollReset = true
            end
            e.state.gridIdx = k
            -- e:SetText(format("%03d",e.state.gridIdx))
            e.state.posX = e.state.posX + gridX - (e.state.gridX or 0)
            e.state.posY = e.state.posY + gridY - (e.state.gridY or 0)
            e.state.gridX = gridX
            e.state.gridY = gridY
        else
            -- Procedural square-spiral fallback for frames beyond the hand-
            -- authored GRID table (k > #GRID) so overflow numbers stay on
            -- screen instead of being pushed to (9999, 9999). Ring r holds
            -- 8r positions; the computed coordinates are absolute, which the
            -- delta-based accumulation below turns into a stable on-screen
            -- position.
            local ring = floor((sqrt(k - 1) + 1) / 2)
            local side = 2 * ring
            local t = k - (2 * ring - 1) * (2 * ring - 1) - 1
            local sx, sy
            if t < side then
                sx, sy = ring - t, -ring
            elseif t < 2 * side then
                sx, sy = -ring, -ring + (t - side)
            elseif t < 3 * side then
                sx, sy = -ring + (t - 2 * side), ring
            else
                sx, sy = ring, ring - (t - 3 * side)
            end
            gridX = sx * (gapX + e.state.width)
            gridY = sy * (gapY + e.state.height)
            e.state.posX = e.state.posX + gridX - (e.state.gridX or 0)
            e.state.posY = e.state.posY + gridY - (e.state.gridY or 0)
            e.state.gridX = gridX
            e.state.gridY = gridY
        end
    end
    -- Resolve any overlaps the grid could not prevent, e.g. when frames grow
    -- during their scale animation. Only the rendered position is adjusted so
    -- the grid layout stays consistent on the next update.
    --
    -- The resolve is the dominant per-frame cost of the layout (O(n^2) collision
    -- tests per pass, 3 passes), and it can only ever change something when a
    -- frame's measured size changed (text grew while scaling) or when the set of
    -- frames changed (a number was added or removed, which shifts every other
    -- number's grid slot). When neither happened the previous pass already
    -- resolved the overlaps, so re-running it would be a no-op and is skipped.
    local area = layoutAreas[areaKey] or {count = 0}
    local needsResolve = (#frames ~= area.count)
    if not needsResolve then
        for _, e in ipairs(frames) do
            local s = e.state
            if (s.resolvedWidth ~= s.width) or (s.resolvedHeight ~= s.height) then
                needsResolve = true
                break
            end
        end
    end
    if needsResolve then
        for _ = 1, 3 do
            local resolved = false
            for i = 1, #frames - 1 do
                local a = frames[i].state
                for j = i + 1, #frames do
                    local b = frames[j].state
                    local overlapX, overlapY = CheckCollision(
                        a.posX, a.posY, a.width, a.height,
                        b.posX, b.posY, b.width, b.height
                    )
                    if (overlapX and overlapY) then
                        if (overlapX < overlapY) then
                            b.posX = b.posX + overlapX * ((a.posX <= b.posX) and 1 or -1)
                        else
                            b.posY = b.posY + overlapY * ((a.posY <= b.posY) and 1 or -1)
                        end
                        resolved = true
                    end
                end
            end
            if not resolved then break end
        end
        -- Remember the sizes the resolve ran against, so the next pass can tell
        -- whether anything that can create an overlap actually changed.
        for _, e in ipairs(frames) do
            e.state.resolvedWidth = e.state.width
            e.state.resolvedHeight = e.state.height
        end
        area.count = #frames
        layoutAreas[areaKey] = area
    end
    return frames
end

local function AnimateLinearAbsolute(startTime, duration, minval, maxval)
    local prog = min(max((now - startTime) / duration, 0), 1)
    return (maxval - minval) * prog + minval
end

-- Every animation in ANIMATIONS shares one signature:
--     animFunc(self, catConfig, animConfig)
-- `catConfig` is the category configuration (the font size, colour and the
-- per-animation settings) and `animConfig` the settings of the single
-- animation being run. The uniform signature is deliberate: the call site
-- passes all three arguments, and the table is designed to be extended with
-- further animation types that need the same context.
--
-- `catConfig` is currently unused by all four animation functions. The
-- commented-out `SetTextHeight(catConfig.fontSize * ...)` lines below are a
-- REVERTED experiment, not a missing feature: the Pow scale is applied to the
-- whole FontString through SetScale (see ApplyFontUpdate), and the string
-- metrics the anti-overlap grid uses are measured at the base font size and
-- scaled by powScale (see CalculateStringSize). Changing the text height as
-- well would apply the scale twice to the glyphs and would desynchronise the
-- measured height from the rendered one, so the parameter is kept as part of
-- the signature and the argument is left unused on purpose.
local ANIMATIONS = {
    -- catConfig is part of the uniform animation signature (see the comment above).
    Pow = function(self, catConfig, animConfig) -- luacheck: ignore 212
        local duration = animConfig.duration * CFCT.Config.animDuration
        local midTime = self.state.initialTime + (duration * animConfig.inOutRatio)
        local overshoot = animConfig.overshoot or 0
        if (now < midTime) then
            self.state.powScale = AnimateLinearAbsolute(self.state.initialTime, midTime - self.state.initialTime, animConfig.initScale, animConfig.midScale)
            -- self:SetTextHeight(catConfig.fontSize * AnimateLinearAbsolute(self.state.initialTime, midTime - self.state.initialTime, animConfig.initScale, animConfig.midScale))
        elseif (overshoot ~= 0) then
            -- Split the second phase into a push up to endScale + overshoot and a
            -- settle back to endScale. settleRatio is the fraction of the second
            -- phase spent settling; degenerate ratios fall back to the legacy
            -- single-lerp phase so no zero-length leg is ever evaluated.
            local settleTime = duration * (1 - animConfig.inOutRatio)
            local settleRatio = max(0, min(1, animConfig.settleRatio or 0.25))
            local pushTime = settleTime * (1 - settleRatio)
            local fallTime = settleTime * settleRatio
            if (pushTime <= 0) or (fallTime <= 0) then
                self.state.powScale = AnimateLinearAbsolute(midTime, settleTime, animConfig.midScale, animConfig.endScale)
            elseif (now < midTime + pushTime) then
                self.state.powScale = AnimateLinearAbsolute(midTime, pushTime, animConfig.midScale, animConfig.endScale + overshoot)
            else
                self.state.powScale = AnimateLinearAbsolute(midTime + pushTime, fallTime, animConfig.endScale + overshoot, animConfig.endScale)
            end
        else
            self.state.powScale = AnimateLinearAbsolute(midTime, duration * (1 - animConfig.inOutRatio), animConfig.midScale, animConfig.endScale)
            -- self:SetTextHeight(catConfig.fontSize * AnimateLinearAbsolute(midTime, duration * (1 - animConfig.inOutRatio), animConfig.midScale, animConfig.endScale))
        end
    end,
    -- catConfig is part of the uniform animation signature (see the comment above).
    FadeIn = function(self, catConfig, animConfig) -- luacheck: ignore 212
        local duration = animConfig.duration * CFCT.Config.animDuration
        local endTime = self.state.initialTime + duration
        if (now <= endTime) then
            local fadeInAlpha = AnimateLinearAbsolute(self.state.initialTime, duration, 0, self.state.fontOptions.fontAlpha)
            self.state.fadeAlpha = (fadeInAlpha + (self.state.fadeOutAlpha or fadeInAlpha)) * 0.5
            self.state.fadeInAlpha = fadeInAlpha
        else
            self.state.fadeInAlpha = nil
        end
    end,
    -- catConfig is part of the uniform animation signature (see the comment above).
    FadeOut = function(self, catConfig, animConfig) -- luacheck: ignore 212
        local duration = animConfig.duration
        local startTime = self.state.initialTime + CFCT.Config.animDuration - duration
        if (now >= startTime) then
            local fadeOutAlpha = AnimateLinearAbsolute(startTime, duration, self.state.fontOptions.fontAlpha, 0)
            self.state.fadeAlpha = (fadeOutAlpha + (self.state.fadeInAlpha or fadeOutAlpha)) * 0.5
            self.state.fadeOutAlpha = fadeOutAlpha
        else
            self.state.fadeOutAlpha = nil
        end
    end,
    -- catConfig is part of the uniform animation signature (see the comment above).
    Scroll = function(self, catConfig, animConfig) -- luacheck: ignore 212
        local duration = CFCT.Config.animDuration
        local state, dir, dist, scrollX, scrollY = self.state, animConfig.direction, animConfig.distance, 0, 0

        if dir:find("RANDOM") then
            if (state.randomX == nil) and (state.randomY == nil) then
                local a = random(1,628) / 100
                -- Re-derive the angle so the scroll direction is normalised to a
                -- unit vector and always travels exactly `dist`.
                local ra = VectorAngle(cos(a), sin(a))
                state.randomX, state.randomY = cos(ra) * dist, sin(ra) * dist
            end
            scrollX = AnimateLinearAbsolute(state.initialTime, duration, 0, state.randomX)
            scrollY = AnimateLinearAbsolute(state.initialTime, duration, 0, state.randomY)
        elseif dir:find("RIGHT") then
            scrollX = AnimateLinearAbsolute(state.initialTime, duration, 0, dist)
        elseif dir:find("LEFT") then
            scrollX = AnimateLinearAbsolute(state.initialTime, duration, 0, -dist)
        end
        if dir:find("UP") then
            scrollY = AnimateLinearAbsolute(state.initialTime, duration, 0, dist)
        elseif dir:find("DOWN") then
            scrollY = AnimateLinearAbsolute(state.initialTime, duration, 0, -dist)
        end
        if state.scrollOriginX == nil then
            state.scrollOriginX = 0
            state.scrollOriginY = 0
        elseif state.scrollReset then
            state.scrollOriginX = -scrollX
            state.scrollOriginY = -scrollY
            state.scrollReset = nil
        end
        scrollX = scrollX + state.scrollOriginX
        scrollY = scrollY + state.scrollOriginY
        -- substract old scroll pos and add new scroll pos
        state.posX = state.posX + scrollX - (state.scrollX or 0)
        state.posY = state.posY + scrollY - (state.scrollY or 0)
        -- save current scroll pos for next call
        state.scrollX = scrollX
        state.scrollY = scrollY
    end,
    -- Map

}

local UIParent = UIParent
local WorldFrame = WorldFrame
local GetNamePlateForUnit = C_NamePlate.GetNamePlateForUnit
local function UpdateFontParent(self)
    local fctConfig = CFCT.Config
    local nameplate = UnitExists(self.state.unit) and GetNamePlateForUnit(self.state.unit) or false
    local attach
    if ((fctConfig.attachMode == "tn") or (fctConfig.attachMode == "en")) and nameplate then
        attach = nameplate
    elseif (fctConfig.attachMode == "sc") or (fctConfig.attachModeFallback == true) then
        attach = f
    else
        attach = false
    end
    local inheritNameplates = fctConfig.inheritNameplates
    if fctConfig.dontOverlapNameplates then
        self:SetParent(WorldFrame)
        self.state.baseScale = inheritNameplates and (attach and attach == nameplate) and attach:GetEffectiveScale() * UIParent:GetScale() or UIParent:GetScale()
    else
        self:SetParent(UIParent)
        self.state.baseScale = inheritNameplates and (attach and attach == nameplate) and attach:GetEffectiveScale() or 1
    end
    self.state.attach = attach
end

local function CalculateStringSize(self)
    -- frame mode
    -- self.state.height = self.state.strHeight * self.state.baseScale * self.state.powScale
    -- self.state.width = self.state.strWidth * self.state.baseScale * self.state.powScale
    self.state.height = self.state.strHeight * self.state.powScale
    self.state.width = self.state.strWidth * self.state.powScale
end

local function ValidateFont(self)
    local fctConfig = CFCT.Config
    if ((now - self.state.initialTime) > fctConfig.animDuration) then
        return false
    end
    local catConfig = fctConfig[self.state.cat]
    if not (catConfig and catConfig.enabled) then
        return false
    end
    self.state.catConfig = catConfig
    return true
end

local function UpdateFontAnimations(self)
    local catConfig = self.state.catConfig
    CalculateStringSize(self)
    for animName, animFunc in pairs(ANIMATIONS) do
        local animConfig = catConfig[animName]
        if (animConfig and (type(animConfig) == 'table')) and animConfig.enabled then
            animFunc(self, catConfig, animConfig)
        end
    end
    CalculateStringSize(self)
end

local function UpdateFontPos(self)
    local fctConfig = CFCT.Config
    local attach = self.state.attach
    if attach then
        local isNamePlate = attach.namePlateUnitToken ~= nil
        local areaX = isNamePlate and fctConfig.areaNX or fctConfig.areaX
        local areaY = isNamePlate and fctConfig.areaNY or fctConfig.areaY
        if fctConfig.perspectiveScale then
            self:SetPoint("CENTER", attach, "CENTER", areaX + self.state.posX, areaY + self.state.posY)
        else
            -- local scaleFactor = 1 / (self.state.baseScale * self.state.powScale)
            local scaleFactor = 1 / self.state.powScale
            self:SetPoint("CENTER", attach, "CENTER", (areaX + self.state.posX) * scaleFactor, (areaY + self.state.posY) * scaleFactor)
        end
        self:Show()
    else
        self:Hide()
    end
end

local function ApplyFontUpdate(self)
    local alpha = self.state.baseAlpha * self.state.fadeAlpha
    local scale = self.state.baseScale * self.state.powScale
    -- local scale = self.state.powScale
    self:SetAlpha(alpha)
    self:SetShadowColor(0, 0, 0, alpha / 2)
    -- if CFCT.Config.perspectiveScale then
        self:SetScale(scale)
    -- else
        -- self.font:SetScale(scale)
    -- end
end

---@class FCTFontString : FontString
---@field Init fun(self: FCTFontString, state: table)
---@field UpdateParent fun(self: FCTFontString)
---@field UpdateAnimation fun(self: FCTFontString)
---@field UpdatePosition fun(self: FCTFontString)
---@field Validate fun(self: FCTFontString): boolean
---@field Release fun(self: FCTFontString)
---@field ApplyUpdate fun(self: FCTFontString)
---@field state table

local function GrabFontString()
    if (#fsc > 0) then return tremove(fsc) end
    local frame = f:CreateFontString()
    ---@cast frame FCTFontString

    frame.Init = InitFont
    frame.UpdateParent = UpdateFontParent
    frame.UpdateAnimation = UpdateFontAnimations
    frame.UpdatePosition = UpdateFontPos
    frame.Validate = ValidateFont
    frame.Release = ReleaseFont
    frame.ApplyUpdate = ApplyFontUpdate

    return frame
end

local iconCache = {}
-- A negative lookup (no icon) is cached for the rest of the session: the lookup
-- happens on every combat event, so re-probing a spell that cannot be resolved
-- is the wrong trade-off. The FIRST failure per spell is reported, so a missing
-- icon is no longer a completely silent degradation - but the report is capped,
-- because a client that resolves no spell at all (the legacy clients key
-- id-0 spells by NAME) must not flood the chat frame.
local iconNegativeLogged = {}
local ICON_NEGATIVE_LOG_LIMIT = 5
local iconNegativeLogCount = 0
local function SpellIconText(spell) -- spellid or spellname
    local fctConfig = CFCT.Config
    local tx = iconCache[spell]
    if (tx == nil) then
        local info = nil
        if (type(GetSpellInfo) == "function") then
            -- The lookup can fail with a bad argument (a spell NAME on a client
            -- that only resolves ids). That must abort the LOOKUP, never the
            -- combat event.
            local ok, res = pcall(GetSpellInfo, spell)
            if ok then info = res end
        end
        tx = (type(info) == "table") and info.iconID or false
        iconCache[spell] = tx -- cache negative lookups too
        if (tx == false) and (not iconNegativeLogged[spell]) then
            iconNegativeLogged[spell] = true
            if (iconNegativeLogCount < ICON_NEGATIVE_LOG_LIMIT) then
                iconNegativeLogCount = iconNegativeLogCount + 1
                if (type(CFCT.Log) == "function") then
                    CFCT:Log(L("no icon could be resolved for '%s' - the number is shown without an icon.", tostring(spell)))
                end
            end
        end
    end
    if tx then
        local aspectRatio = fctConfig.spellIconAspectRatio
        local zoom = fctConfig.spellIconZoom
        local offsetX, offsetY = fctConfig.spellIconOffsetX, fctConfig.spellIconOffsetY
        local height, width = 12 / aspectRatio, 12
        local txSize = zoom * 100
        local txMinX = (zoom - 1) * 100 / 2
        local txMaxX = (zoom + 1) * 100 / 2
        local txMinY = (zoom - (1 / aspectRatio)) * 100 / 2
        local txMaxY = (zoom + (1 / aspectRatio)) * 100 / 2
        return format("|T%s:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d|t",
            tx, height, width, offsetX, offsetY, txSize, txSize, txMinX, txMaxX, txMinY, txMaxY)
    end
    return false
end

local function GetDamageTypeColor(school)
    return CFCT.Config.colorTable[school]
end
local function GetDotTypeColor(school)
    return CFCT.Config.colorTableDot[school]
end

-- GUID of the player's current target, refreshed on PLAYER_TARGET_CHANGED and
-- PLAYER_ENTERING_WORLD. Declared before DispatchText so that function captures
-- it as an upvalue instead of reading a global.
local targetGUID
-- Latched once per session: the "Dim Off-Target Text" notice is a one-time
-- diagnostic, never a per-frame log.
local offTargetNoTargetNoticeShown = false
-- DispatchText is a 13-argument POSITIONAL signature called from five sites
-- (the merged path, the unmerged path, the separate-miss path and the test
-- spawner). The argument order is part of the contract, so no argument may be
-- removed or reordered.
--
-- `spellid` is deliberately not read in the body: the icon is pre-resolved by
-- the caller and passed as `spellicon` (SpellIconText(spellid)). The parameter
-- is kept because it documents the fifth slot of the signature.
local function DispatchText(guid, event, text, amount, spellid, spellicon, periodic, crit, miss, pet, school, count, missKey) -- luacheck: ignore 212
    local cat = (pet and "pet" or "")..event..(periodic and "tick" or "")..(crit and "crit" or miss and "miss" or "")
    local fctConfig = CFCT.Config
    local catConfig = fctConfig[cat]

    -- Demote small crits to their non-crit sibling category before filtering and
    -- styling. If that category is missing or disabled, keep the original crit
    -- category rather than dropping the number.
    if (crit and not miss and fctConfig.demoteSmallCritsEnabled)
    and (fctConfig.demoteSmallCritThreshold > 0)
    and ((amount or 0) < fctConfig.demoteSmallCritThreshold) then
        local baseCat = gsub(cat, "crit$", "")
        local baseConfig = fctConfig[baseCat]
        if (baseConfig and baseConfig.enabled) then
            cat = baseCat
            catConfig = baseConfig
            crit = false
        end
    end

    -- An event with neither a text nor a usable amount would otherwise render
    -- the literal string "nil" on screen.
    text = text or tostring(amount or 0)
    -- TODO put fctConfig and catConfig into state

    count = count or 1
    if (not miss) then
        -- The three "Hide Below ... Threshold" filters are PER-HIT limits, so
        -- they are compared against the per-event amount - the same value the
        -- rolling average is fed. Comparing the merged SUM against a per-hit
        -- threshold silently defeated the user's own filters whenever merging
        -- was on: five 30-damage hits were summed to 150 and displayed even
        -- though every one of them was a hit the user configured to be hidden.
        local perHitAmount = (type(amount) == "number") and (amount / count) or 0
        if (not crit) then
            AddToAverage(perHitAmount)
        end
        if (fctConfig.filterAbsoluteEnabled and (fctConfig.filterAbsoluteThreshold > perHitAmount))
        or (fctConfig.filterRelativeEnabled and ((fctConfig.filterRelativeThreshold * 0.01 * CFCT:UnitHealthMax('player')) > perHitAmount))
        or (fctConfig.filterAverageEnabled and ((fctConfig.filterAverageThreshold * 0.01 * CFCT:DamageRollingAverage()) > perHitAmount)) then
            return false
        end

        if (fctConfig.abbreviateNumbers) then
            text = AbbreviateNumbers(amount)
        elseif (fctConfig.kiloSeparator) then
            text = FormatThousandSeparator(amount)
        end
    end

    if (count > 1) and fctConfig.mergeEventsCounter then
        text = text.." x"..tostring(count)
    end

    if (spellicon and catConfig.showIcons) then text = spellicon..text end

    local fontColor, fontAlpha
    local fontSize = catConfig.fontSize
    -- The dot colour falls back to the damage colour explicitly: the old
    -- `and/or` chain collapsed to the damage colour whenever the dot table had
    -- no entry for the school (and for every swing heal, which has no school).
    local typeColor = GetDamageTypeColor(school)
    if periodic and fctConfig.colorTableDotEnabled then
        typeColor = GetDotTypeColor(school) or typeColor
    end
    if (catConfig.colorByType == true) and typeColor then
        local r, g, b, a = CFCT.Color2RGBA((strlen(typeColor) == 6) and "FF"..typeColor or typeColor)
        -- The alpha of a type-coloured number is the SMALLER of the type colour's
        -- alpha and the font colour's alpha: the font alpha is the ceiling. The
        -- result used to be written to a second `local a`, which shadowed the
        -- first one - the arithmetic was right but the shadowing hid it.
        local typeAlpha = min(a, select(4, CFCT.Color2RGBA(catConfig.fontColor)))
        fontColor = {r, g, b, typeAlpha}
        fontAlpha = typeAlpha
    else
        local r, g, b, a = CFCT.Color2RGBA(catConfig.fontColor)
        fontColor = {r, g, b, a}
        fontAlpha = a
    end

    -- Per-miss-type styling. Unknown miss keys (and keys without an override)
    -- inherit the category color/scale, and the alpha never exceeds the value
    -- resolved above.
    if (miss and catConfig.missStyle and catConfig.missStyle.enabled) then
        -- The "MISS" fallback is NOT dead code. Every combat-log miss carries a
        -- miss key (MissEvent always sets one), but the TEST spawner calls
        -- DispatchText with eleven arguments - no miss key - and it can spawn a
        -- miss. The fallback is what keeps that path looking up a style
        -- instead of indexing the table with nil.
        local style = catConfig.missStyle[missKey or "MISS"]
        if style then
            if style.color then
                local r, g, b, a = CFCT.Color2RGBA((strlen(style.color) == 6) and "FF"..style.color or style.color)
                a = min(a, fontAlpha)
                fontColor = {r, g, b, a}
                fontAlpha = a
            end
            if (style.scale and style.scale ~= 1) then
                fontSize = fontSize * style.scale
            end
        end
    end

    -- Off-target dimming. The multiplier is baked into the size/alpha passed to
    -- Init so string measurement and the anti-overlap grid see the final values.
    -- isOffTarget is reserved for future per-frame off-target logic; no consumer yet.
    --
    -- EXPLICIT CONTRACT: with no target selected, NOTHING is dimmed - every
    -- number renders at full size and alpha. The dimming branch below is
    -- therefore guarded by `targetGUID`, which is nil while the player has no
    -- target (it is refreshed on PLAYER_ENTERING_WORLD / PLAYER_TARGET_CHANGED).
    -- A user who enables "Dim Off-Target Text" and expects dimming gets a
    -- one-time notice explaining why nothing is dimmed, instead of a feature
    -- that silently does nothing.
    local isOffTarget = false
    local offTarget = fctConfig.offTarget
    if (offTarget and offTarget.enabled) and (targetGUID == nil) then
        if not offTargetNoTargetNoticeShown then
            offTargetNoTargetNoticeShown = true
            if (type(CFCT.Log) == "function") then
                CFCT:Log("\"Dim Off-Target Text\" is enabled but there is no target, so nothing is dimmed.")
            end
        end
    end
    if (offTarget and offTarget.enabled and targetGUID and guid ~= targetGUID) then
        fontSize = fontSize * (offTarget.sizeScale or 1)
        fontAlpha = max(0, min(1, fontAlpha * (offTarget.alpha or 1)))
        isOffTarget = true
    end

    if (fctConfig.maxDisplayed and fctConfig.maxDisplayed > 0) then
        -- The limit is a CEILING, so the number of live numbers has to land
        -- on it exactly - not above it.
        --
        -- Releasing a single oldest number per dispatch is enough while the
        -- count is at or below the limit, because the check runs before every
        -- insert. It is NOT enough when the limit is LOWERED at runtime (the
        -- options panel applies a new "Max Simultaneous Numbers" immediately)
        -- while more numbers are on screen than the new limit allows: one
        -- release per dispatch left the screen above the new limit, and the
        -- surplus was only worked off one number at a time. Releasing until
        -- the count is under the limit brings the screen back to the ceiling
        -- in a single dispatch.
        while (#anim >= fctConfig.maxDisplayed) do
            local oldest = anim[#anim]
            if not oldest then break end
            oldest:Release()
            tremove(anim)
        end
    end
    tinsert(anim, 1, GrabFontString():Init({
        cat = cat,
        guid = guid,
        icon = spellicon,
        text = text,
        amount = amount,
        miss = miss,
        isOffTarget = isOffTarget,
        baseAlpha = 1,
        baseScale = 1,
        fadeAlpha = 1,
        powScale = 1,
        fontOptions = {
            fontPath = catConfig.fontPath,
            fontSize = fontSize,
            fontStyle = catConfig.fontStyle,
            fontColor = fontColor,
            fontAlpha = fontAlpha
        },
    }))
    -- Consistent result: true = a number was dispatched, false = the event was
    -- filtered out. No caller consumes it today, but a filter decision is now
    -- observable and assertable.
    return true
end

local spellIdCache = {}
CFCT.spellIdCache = spellIdCache
local eventCache = {}
CFCT.eventCache = eventCache
-- Latched once per session: an unknown merge-interval mode is reported once.
local mergeIntervalModeReported = false
local function CacheEvent(guid, event, amount, text, spellid, spellicon, periodic, crit, miss, pet, school, missKey, spellIdNumeric)
    if IsSecretValue(amount) or IsSecretValue(spellid) or IsSecretValue(school) or IsSecretValue(guid) or IsSecretValue(spellicon) or IsSecretValue(crit) then return end
    if (spellid and not spellIdCache[spellid]) then
        spellIdCache[spellid] = true
        if CFCT.ConfigPanel:IsVisible() then
            CFCT.ConfigPanel:refresh()
        end
    end

    local fctConfig = CFCT.Config
    -- The blacklist is keyed by the SAME key the runtime uses. On the legacy
    -- clients (Era, TBC Anniversary, WotLK Titanforge) a spell whose combat-log
    -- id is 0 is keyed by its NAME (see the mapping in the combat-log handler),
    -- so the name is what the lookup has to use. The numeric id is carried in
    -- the event record as well, so a blacklist entry keyed by the numeric id
    -- still matches.
    if fctConfig.filterSpellBlacklist[spellid] == true
    or ((spellIdNumeric ~= nil) and (spellIdNumeric ~= spellid) and (fctConfig.filterSpellBlacklist[spellIdNumeric] == true))
    or (fctConfig.filterMissesEnabled and miss) then
        return
    end

    local mergeConfig = {
        {fctConfig.mergeEventsByGuid, guid},
        {fctConfig.mergeEventsBySpellID, spellid},
        {fctConfig.mergeEventsBySpellIcon, spellicon},
        {fctConfig.mergeEventsBySchool, school}
    }
    -- Merge bucket key. The event type (auto / spell / heal), the miss flag,
    -- the MISS TYPE and the PERIODIC flag are part of the key, so a bucket can
    -- never mix categories: a heal is never summed into a damage, a miss is
    -- never summed into a hit (the merged group is dispatched under the FIRST
    -- event's category), a Block is never summed into a Dodge, and a DoT tick
    -- is never summed into a direct hit of the same spell (which would strip
    -- the tick's styling). The enabled merge dimensions (guid / spell id /
    -- spell icon / school) are appended after that.
    --
    -- Splitting the buckets further reduces how much can be merged - that is the
    -- deliberate trade-off, see bench/findings-fix-fallbacks.md (J-02).
    local id = tostring(pet).."|"..tostring(event).."|"..tostring(miss).."|"..tostring(missKey or "").."|"..tostring(periodic and 1 or 0)
    for _, e in ipairs(mergeConfig) do
        if e[1] == true then id = id .. tostring(e[2]) end
    end
    local mergeTime = fctConfig.mergeEventsIntervalOverrides[spellid] or fctConfig.mergeEventsInterval or 0.1
    -- The event timestamp is taken fresh here instead of using the file-level
    -- `now` (which is only refreshed once per frame in OnUpdate): the cached
    -- event time and the merge expiry must be measured from the same instant.
    local cacheNow = GetTime()
    local record = eventCache[id] or {
        events = {},
        expiry = nil
    }
    tinsert(record.events, {
        time = cacheNow,
        guid = guid,
        event = event,
        amount = amount,
        text = text,
        spellid = spellid,
        spellIdNumeric = spellIdNumeric,
        spellicon = spellicon,
        periodic = periodic,
        crit = crit,
        miss = miss,
        missKey = missKey,
        pet = pet,
        school = school,
        count = 1
    })
    if fctConfig.mergeEventsIntervalMode == "first" then
        record.expiry = record.expiry or (cacheNow + mergeTime)
    elseif fctConfig.mergeEventsIntervalMode == "last" then
        record.expiry = cacheNow + mergeTime
    else
        -- An UNKNOWN interval mode (a hand-edited SavedVariable, a value from a
        -- future version) falls back to "first". The behaviour is unchanged, but
        -- it is now explicit and it is reported once instead of being silent:
        -- the user's "Relative To: Last Event" selection used to become
        -- "First Event" without a word.
        if not mergeIntervalModeReported then
            mergeIntervalModeReported = true
            if (type(CFCT.Log) == "function") then
                CFCT:Log(L("unknown merge interval mode '%s' - '%s' is used instead.",
                    tostring(fctConfig.mergeEventsIntervalMode), L("First Event")))
            end
        end
        record.expiry = record.expiry or (cacheNow + mergeTime)
    end
    record.expiry = record.expiry or (cacheNow + mergeTime)
    eventCache[id] = record
end

local function ProcessCachedEvents()
    local mergingEnabled = CFCT.Config.mergeEvents
    local separateMisses = CFCT.Config.mergeEventsMisses

    for id,record in pairs(eventCache) do
        if mergingEnabled then
            if (now > record.expiry) then
                local merge
                for _,e in ipairs(record.events) do
                    if e.miss and separateMisses then
                        DispatchText(e.guid, e.event, e.text, e.amount, e.spellid, e.spellicon, e.periodic, e.crit, e.miss, e.pet, e.school, nil, e.missKey)
                    elseif not merge then
                        merge = e
                    else
                        merge.amount = merge.amount + e.amount
                        merge.text = merge.text or e.text
                        merge.count = merge.count + 1
                        -- Merge rule: a merged group is a MISS only if EVERY member
                        -- of the group is a miss. A single real hit in the group
                        -- keeps the group a hit, so a hit is never swallowed or
                        -- relabelled as a miss (the old `and/or` ternary always
                        -- yielded the LAST event's flag, whatever the order).
                        -- AND is order independent, so the result is deterministic.
                        merge.miss = merge.miss and e.miss
                        merge.missKey = merge.missKey or e.missKey
                        merge.crit = merge.crit or e.crit
                        merge.periodic = merge.periodic and e.periodic
                    end
                end
                -- The record is dropped BEFORE the dispatch. A raise inside
                -- DispatchText used to abort this loop before the record was
                -- cleared, so the record was retried EVERY frame, the same
                -- error was logged once and all combat text was dead for the
                -- rest of the session. Dropping it first means a bad event can
                -- cost one number, never the whole session.
                eventCache[id] = nil
                if merge then
                    local text = (merge.amount ~= 0) and merge.amount or merge.text
                    DispatchText(merge.guid, merge.event, text, merge.amount, merge.spellid, merge.spellicon,
                        merge.periodic, merge.crit, merge.miss, merge.pet, merge.school, merge.count, merge.missKey)
                end
            end
        else
            local events = record.events
            eventCache[id] = nil
            for _,e in ipairs(events) do
                local text = (e.amount ~= 0) and e.amount or e.text
                DispatchText(e.guid, e.event, text, e.amount, e.spellid, e.spellicon, e.periodic, e.crit, e.miss, e.pet, e.school, nil, e.missKey)
            end
        end
    end
end

CFCT._testMode = false
local testModeTimer = 0
-- The receiver is part of the method signature but the spawner does not need it.
function CFCT:Test(n) -- luacheck: ignore 212
    local cats = {
        "auto",
        "spell",
        "heal"
    }
    local nameplates = C_NamePlate.GetNamePlates()
    local numplates = #nameplates
    local it = (numplates > 0) and (n*numplates) or n
    for _ = 1, it do
        local spellinfo
        local attempts = 0
        repeat
            spellinfo = GetSpellInfo(random(1,32767))
            attempts = attempts + 1
        until (spellinfo and spellinfo.iconID) or attempts >= 50

        local school = random(1,128)
        local pet = (random(1,3) == 1)
        local crit = (random(1,3) == 1)
        local miss = not crit and (random(1,2) == 1)
        local event = cats[random(1,#cats)]
        local text = miss and "Miss" or nil
        local periodic = (random(1,3) == 1) and event == "spell"
        local amount = crit and 2674 or miss and 0 or 1337
        local guid = (numplates > 0) and UnitGUID(nameplates[random(1,numplates)].UnitFrame.unit) or UnitGUID("target")
        local spellid = (spellinfo and spellinfo.spellID) or nil
        local spellicon = spellid and SpellIconText(spellid) or ""
        DispatchText(guid, event, text, amount, spellid, spellicon, periodic, crit, miss, pet, school)
    end
end



local CVAR_CHECK_INTERVAL = 5
-- Live-example tunables. The options panel spawns preview numbers until the
-- "Max Simultaneous Numbers" limit is reached, so the setting can be seen
-- working instead of having to be taken on faith.
local PREVIEW_DEFAULT_COUNT = 10
local PREVIEW_SPAWN_PER_TICK = 20
local PREVIEW_TICK_INTERVAL = 0.15
local cvarTimer = 0
-- Blizzard's own combat-text CVar names. On the supported clients only the
-- "_v2" variants exist, so they are preferred and the un-suffixed names are
-- kept as a fallback. The resolution is done at runtime, never assumed.
--
-- Cross-file contract: config.lua uses the same names for the options panel
-- and MUST resolve them identically, otherwise the panel and the runtime
-- disagree about whether the feature is available. config.lua loads before
-- main.lua, so it resolves the names at file scope and publishes them on the
-- shared addon table as CFCT.CVarDamage / CFCT.CVarHealing; main.lua reads
-- those and only falls back to its own resolution when they are not published.
-- A name that resolves to nothing means the feature is unavailable, and
-- Blizzard's combat text is then left alone: text that cannot be restored must
-- never be hidden.
local function ResolveCombatTextCVar(published, base)
    if (type(published) == "string") and (published ~= "") then return published end
    if GetCVarDefault(base.."_v2") then return base.."_v2" end
    if GetCVarDefault(base) then return base end
    return nil
end
local function checkCvars()
    -- Restricted clients must not hide Blizzard's combat text: this addon cannot replace it.
    if IsRestrictedCombat then return end
    local cvarDamage = ResolveCombatTextCVar(CFCT.CVarDamage, "floatingCombatTextCombatDamage")
    if cvarDamage and GetCVarDefault(cvarDamage) then
        local varHideDamage = CFCT.hideBlizz and "0" or "1"
        local cvarHideDamage = GetCVar(cvarDamage)
        if cvarHideDamage ~= varHideDamage then
            if CFCT.forceCVars then
                SetCVar(cvarDamage, varHideDamage)
            else
                CFCT.hideBlizz = (cvarHideDamage == "0")
            end
        end
    end
    local cvarHealing = ResolveCombatTextCVar(CFCT.CVarHealing, "floatingCombatTextCombatHealing")
    if cvarHealing and GetCVarDefault(cvarHealing) then
        local varHideHealing = CFCT.hideBlizzHeals and "0" or "1"
        local cvarHideHealing = GetCVar(cvarHealing)
        if cvarHideHealing ~= varHideHealing then
            if CFCT.forceCVars then
                SetCVar(cvarHealing, varHideHealing)
            else
                CFCT.hideBlizzHeals = (cvarHideHealing == "0")
            end
        end
    end
end



-- Error containment for the event dispatch and the frame loop. Only the
-- registration of an event was protected before: one raising handler aborted
-- the rest of that event's work, and an error inside the frame loop aborted
-- the remaining steps of the frame - including PrepareAnimatingFonts, which is
-- the only thing that releases expired frames, so a repeating error would leak
-- frames forever. Each step is now contained on its own.
--
-- The log is rate limited: one line per DISTINCT message, so a persistent fault
-- cannot flood the chat frame.
local reportedErrors = {}
local function LogErrorOnce(context, err)
    local msg = ("ClassicFCT error in %s: %s"):format(tostring(context), tostring(err))
    if not reportedErrors[msg] then
        reportedErrors[msg] = true
        if (type(CFCT.Log) == "function") then
            CFCT:Log(msg)
        end
    end
end
local function RunProtected(context, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        LogErrorOnce(context, err)
    end
    return ok
end

local events = {
    COMBAT_LOG_EVENT_UNFILTERED = not IsRestrictedCombat,
    UNIT_MAXHEALTH = true,
    ADDON_LOADED = true,
    PLAYER_LOGOUT = true,
    PLAYER_ENTERING_WORLD = true,
    PLAYER_TARGET_CHANGED = true,
    NAME_PLATE_UNIT_ADDED = true,
    NAME_PLATE_UNIT_REMOVED = true
}
for e, enabled in pairs(events) do
    if enabled then
        local ok, err = pcall(f.RegisterEvent, f, e)
        if not ok then
            CFCT:Log(L("Could not register event %s: %s", tostring(e), tostring(err)))
        end
    end
end
f:SetScript("OnEvent", function(self, event, ...)
    -- The event name and the error are both reported, so a failing handler can
    -- be identified from the chat frame alone.
    RunProtected(tostring(event), self[event], self, ...)
end)

local function SortByUnit(allFrames)
    local fctConfig = CFCT.Config
    local animAreas = {target={}}
    for _, frame in ipairs(allFrames) do
        local state = frame.state
        if (fctConfig.attachMode == "en") then
            state.unit = CFCT:GetNamePlateUnitByGUID(state.guid) or ""
        else
            state.unit = "target"
        end
        animAreas[state.unit] = animAreas[state.unit] or {}
        tinsert(animAreas[state.unit], frame)
    end
    return animAreas
end

local function PrepareAnimatingFonts()
    local c = #anim
    local i = 1
    while (i <= c) do
        local frame = anim[i]
        if (frame:Validate() == false) then
            frame:Release()
            tremove(anim, i)
            c = c - 1
        else
            i = i + 1
        end
    end
end

local function UpdateAnimatingFonts()
    local animAreas = SortByUnit(anim)
    for k, animArea in pairs(animAreas) do
        for _, frame in ipairs(animArea) do
            frame:UpdateParent(animArea)
            frame:UpdateAnimation()
        end
        if CFCT.Config.preventOverlap then
            GridLayout(animArea, k)
        end
        for _, e in pairs(animArea) do
            e:UpdatePosition()
            e:ApplyUpdate()
        end
    end
    -- Drop the layout state of animation areas that no longer exist, so the
    -- table cannot grow without bound over a long session.
    for areaKey in pairs(layoutAreas) do
        if (animAreas[areaKey] == nil) then layoutAreas[areaKey] = nil end
    end
end

-- The OnUpdate callback receives the frame and the frame time. Neither is used:
-- the handler reads the clock itself (GetTime) and the frame through the closure.
f:SetScript("OnUpdate", function(self, elapsed) -- luacheck: ignore 212
    now = GetTime()
    -- Every step of the frame loop is contained on its own: a failure in one of
    -- them must not stop the others. PrepareAnimatingFonts in particular is the
    -- only thing that releases expired frames, so skipping it would leak frames
    -- and repeat the error every frame.
    if CFCT._testMode and (now > testModeTimer) and not InCombatLockdown() then
        -- The live example demonstrates the "Max Simultaneous Numbers" setting:
        -- it fills up to the configured maximum, so moving the slider visibly
        -- changes how many numbers are on screen. With the maximum at 0
        -- (unlimited) a small default is used, because "unlimited" cannot be
        -- shown literally. The spawn count is the shortfall, capped per tick so
        -- the frame cost stays bounded, and the tick is frequent enough that
        -- the example converges on the target within a second or two.
        local previewTarget = CFCT.Config.maxDisplayed
        if (not previewTarget) or (previewTarget <= 0) then previewTarget = PREVIEW_DEFAULT_COUNT end
        local toSpawn = previewTarget - #anim
        if (toSpawn < 0) then toSpawn = 0 end
        -- Spawn fast enough that the example reaches any target before the
        -- first numbers start expiring. A fixed per-tick cap could not: at a
        -- target of 30 the example topped out at 23, because the fill rate was
        -- slower than the expiry rate. The cap scales with the shortfall, so
        -- the example converges whatever the target is.
        local perTick = math.max(PREVIEW_SPAWN_PER_TICK, math.ceil(previewTarget / 2))
        if (toSpawn > perTick) then toSpawn = perTick end
        if (toSpawn > 0) then
            RunProtected("OnUpdate: test numbers", CFCT.Test, CFCT, toSpawn)
        end
        testModeTimer = now + PREVIEW_TICK_INTERVAL
    end
    if (now > rollingAverageTimer) then
        RunProtected("OnUpdate: rolling average", CalculateRollingAverage)
        rollingAverageTimer = now + ROLLINGAVERAGE_UPDATE_INTERVAL
    end
    -- The CVar poll lives here, not inside the per-area render loop, so it also
    -- runs when no number is on screen (otherwise the "hide Blizzard combat
    -- text" state drifts out of sync until the next number appears).
    if (now > cvarTimer) then
        RunProtected("OnUpdate: CVar poll", checkCvars)
        cvarTimer = now + CVAR_CHECK_INTERVAL
    end
    RunProtected("OnUpdate: cached events", ProcessCachedEvents)
    RunProtected("OnUpdate: release expired", PrepareAnimatingFonts)
    RunProtected("OnUpdate: animate", UpdateAnimatingFonts)
end)
f:Show()

-- WoW event handler: the frame receiver is part of the calling convention.
function f:ADDON_LOADED(name) -- luacheck: ignore 212
    if (name == addonName) then
        CFCT.Config:OnLoad()
        -- The frame strata are not part of the persisted config, so they must be
        -- applied every time the config is (re)loaded.
        CFCT.ApplyTextStrata()
        local version = GetAddOnMetadata(addonName, "Version")
        if (version ~= CFCT.lastVersion) then
            -- The version is captured in the closure: re-reading it inside the
            -- timer callback could return nil, and concatenating nil raises an
            -- error inside a timer and loses the changelog without a trace.
            C_Timer.After(5,function()
                CFCT:Log(tostring(version or "?")..[[

Recent changes:
    M0.89   Oct 20, 2026
        - Fixed merged events mislabelling a hit as a miss, and damage/heals/misses of different
          kinds being merged into one number
        - Fixed every hit being shown as a crit when the client reports the crit flag as a number
        - Fixed "Max Simultaneous Numbers" leaving extra numbers on screen when the limit was
          lowered
        - Event handling is contained: one failure no longer aborts the frame or leaks numbers
        - The "Hide Blizzard Combat Text" option works now - it used CVar names no client has
        - Fixed the rolling average, the spell-without-name case, and the preset Save/Delete/
          Rename buttons keeping a stale state
        - Fixed the options panel drawing the off-target sliders over the text-position sliders,
          and it now sizes itself to its content so the bottom of the panel is reachable
        - "Max Simultaneous Numbers" now defaults to 20 instead of unlimited, so the example
          does not fill the screen
        - GPL v3 license, third-party notices and a reproducible packaging script
    0.88    Oct 17, 2026
        - Supported clients aligned: Classic Era, TBC Anniversary, WotLK Titanforge, WoW Forever
          and Retail, with restricted-client handling and secret-value guards
        - Max Simultaneous Numbers slider, off-target dimming, small-crit demotion, Pow overshoot
        - Classic Plus preset and a built-in locale system (10 locales, English fallback)
    0.87u   Aug 16, 2024
        - Fixed miss filter, ColorPicker and Config panels for The War Within]])
            end)
        end
        CFCT.lastVersion = version
        if IsRestrictedCombat then
            C_Timer.After(7, function()
                CFCT:Log(L("Combat text is unavailable on this client: the modern combat log is restricted and no public API exposes outgoing damage. Options, presets and previews still work."))
            end)
        end
    end
end

-- Cached max health, filled by f:UNIT_MAXHEALTH for 'player'. Declared before
-- f:PLAYER_LOGOUT so the logout handler can clear it (a stale value from the
-- previous character must not survive a character switch).
local unitHealthMax = {}
-- WoW event handler: the frame receiver is part of the calling convention.
function f:PLAYER_LOGOUT() -- luacheck: ignore 212
    CFCT.Config:OnSave()
    -- Clear the cached max health: on a character switch the value of the
    -- previous character must not be used by the relative threshold filter.
    unitHealthMax = {}
end

local playerGUID
-- WoW event handler: the frame receiver is part of the calling convention.
function f:PLAYER_ENTERING_WORLD() -- luacheck: ignore 212
    playerGUID = UnitGUID("player")
    targetGUID = UnitGUID("target")
end
-- WoW event handler: the frame receiver is part of the calling convention.
function f:PLAYER_TARGET_CHANGED() -- luacheck: ignore 212
    targetGUID = UnitGUID("target")
end

local nameplates = {}
-- WoW event handler: the frame receiver is part of the calling convention.
function f:NAME_PLATE_UNIT_ADDED(unit) -- luacheck: ignore 212
    local guid = UnitGUID(unit)
    nameplates[unit] = guid
    if (guid) then
        nameplates[guid] = unit
    end
end
-- WoW event handler: the frame receiver is part of the calling convention.
function f:NAME_PLATE_UNIT_REMOVED(unit) -- luacheck: ignore 212
    local guid = nameplates[unit]
    nameplates[unit] = nil
    if (guid) then
        nameplates[guid] = nil
    end
end
-- The receiver is part of the method signature but the lookup does not need it.
function CFCT:GetNamePlateUnitByGUID(guid) -- luacheck: ignore 212
    if (guid) then
        return nameplates[guid]
    end
    return nil
end

-- Cached max health, filled by f:UNIT_MAXHEALTH for 'player'.
-- WoW event handler: the frame receiver is part of the calling convention.
function f:UNIT_MAXHEALTH(unit) -- luacheck: ignore 212
    if (unit == 'player') then
        unitHealthMax[unit] = UnitHealthMax(unit)
    end
end
-- The receiver is part of the method signature but the lookup does not need it.
function CFCT:UnitHealthMax(unit) -- luacheck: ignore 212
    return unitHealthMax[unit] or UnitHealthMax(unit)
end

-- The swing events: the ones whose payload carries NO spell id, so the spell
-- branch cannot be used for them.
--
-- "SWING_LEECH" used to be in this table, but it is not a client event. The
-- client's own event list (Blizzard's COMBATLOG_EVENT_LIST) contains
-- SPELL_LEECH and SPELL_PERIODIC_LEECH, and no SWING_LEECH; the string does
-- not occur anywhere in the FrameXML of any supported client. The entry could
-- therefore never be consulted: the dispatch is driven by CLEU_DAMAGE_EVENT /
-- CLEU_MISS_EVENT / CLEU_HEALING_EVENT, and SWING_LEECH is in none of them, so
-- the event was silently dropped. The key is removed rather than routed: a
-- leech is a POWER GAIN for the source, not damage dealt to the destination,
-- and its payload has its own layout (amount, powerType, extraAmount,
-- alternatePowerType) - the swing damage branch would show a wrong number.
local CLEU_SWING_EVENT = {
    SWING_DAMAGE = true,
    SWING_HEAL = true,
    SWING_MISSED = true
}
-- CLEU_SPELL_EVENT used to live here. It was a redundant superset: every one of
-- its ten keys is already in CLEU_DAMAGE_EVENT (the six damage events) or in
-- CLEU_MISS_EVENT (the four miss events), and the dispatch is driven by those
-- two tables plus CLEU_HEALING_EVENT. The table was never referenced, so it is
-- gone rather than kept as a second source of truth.
local CLEU_MISS_EVENT = {
    SWING_MISSED = true,
    RANGE_MISSED = true,
    SPELL_MISSED = true,
    SPELL_PERIODIC_MISSED = true,
    SPELL_BUILDING_MISSED = true,
}
local CLEU_DAMAGE_EVENT = {
    SWING_DAMAGE = true,
    DAMAGE_SHIELD = true,
    DAMAGE_SPLIT = true,
    RANGE_DAMAGE = true,
    SPELL_DAMAGE = true,
    SPELL_BUILDING_DAMAGE = true,
    SPELL_PERIODIC_DAMAGE = true
}
local CLEU_HEALING_EVENT = {
    SWING_HEAL = true,
    RANGE_HEAL = true,
    SPELL_HEAL = true,
    SPELL_BUILDING_HEAL = true,
    SPELL_PERIODIC_HEAL = true,
}

-- Combat-log API resolution.
--
-- The legacy globals (CombatLogGetCurrentEventInfo and the COMBATLOG_OBJECT_*
-- constants) are only defined while Blizzard's deprecated-combat-log shim is
-- loaded, so the modern API is preferred and the legacy names are the fallback.
-- The resolution is LAZY - it runs inside the CLEU handler, never at file scope
-- - because the deprecated shim can be assigned after this file has loaded, and
-- a file-scope capture would cache nil forever. A successful resolution is
-- cached; a failed one is retried on the next event and reported once.
local cleuApi = nil
local cleuApiReported = false
local function ResolveCombatLogApi()
    if cleuApi then return cleuApi end
    local getEventInfo
    local cCombatLog = C_CombatLog
    if (type(cCombatLog) == "table") and (type(cCombatLog.GetCurrentEventInfo) == "function") then
        getEventInfo = cCombatLog.GetCurrentEventInfo
    elseif (type(CombatLogGetCurrentEventInfo) == "function") then
        getEventInfo = CombatLogGetCurrentEventInfo
    end
    local typeGuardian, typePet, affiliationMine
    local enumGlobal = Enum
    local combatLogObject = (type(enumGlobal) == "table") and enumGlobal.CombatLogObject or nil
    if (type(combatLogObject) == "table") then
        typeGuardian = combatLogObject.TypeGuardian
        typePet = combatLogObject.TypePet
        affiliationMine = combatLogObject.AffiliationMine
    end
    -- Fall back to the legacy constants one by one, so a partially available
    -- modern enumeration still works.
    if (type(typeGuardian) ~= "number") then typeGuardian = COMBATLOG_OBJECT_TYPE_GUARDIAN end
    if (type(typePet) ~= "number") then typePet = COMBATLOG_OBJECT_TYPE_PET end
    if (type(affiliationMine) ~= "number") then affiliationMine = COMBATLOG_OBJECT_AFFILIATION_MINE end
    -- A nil constant must never reach bitband: when one of them is still
    -- missing the pet test cannot be evaluated, so no event can be classified
    -- and the handler returns instead of raising.
    if (type(getEventInfo) ~= "function")
    or (type(typeGuardian) ~= "number")
    or (type(typePet) ~= "number")
    or (type(affiliationMine) ~= "number") then
        if not cleuApiReported then
            cleuApiReported = true
            if (type(CFCT.Log) == "function") then
                CFCT:Log("no combat-log API is available on this client, so no combat text can be shown.")
            end
        end
        return nil
    end
    cleuApi = {getEventInfo, typeGuardian, typePet, affiliationMine}
    return cleuApi
end

function f:COMBAT_LOG_EVENT_UNFILTERED()
    if CFCT.enabled == false then return end
    if IsRestrictedCombat then return end
    local cleu = ResolveCombatLogApi()
    if not cleu then return end
    local getEventInfo, typeGuardian, typePet, affiliationMine = cleu[1], cleu[2], cleu[3], cleu[4]
    -- The combat-log payload is POSITIONAL. The layout is the client's own:
    --   arg1  timestamp      arg7  sourceRaidFlags   arg13 spellName
    --   arg2  subevent       arg8  destGUID         arg14 spellSchool
    --   arg3  hideCaster     arg9  destName         arg15 amount
    --   arg4  sourceGUID     arg10 destFlags        arg16 overkill
    --   arg5  sourceName     arg11 destRaidFlags    arg17 school
    --   arg6  sourceFlags                           arg18..arg25 event specific
    -- (verified against Blizzard's own parser, e.g.
    --  Blizzard_CombatLog/Classic/Blizzard_CombatLog.lua and
    --  Blizzard_ChatFrame/Classic/ChatConfigFrame_Shared.lua on classic_era and live).
    --
    -- The values this addon does not use are named `_`. A name may never be
    -- REMOVED from the list: every name to its right would shift one position
    -- and silently corrupt the mapping. `_` keeps the slot and the position.
    local _, cleuEvent, _, sourceGUID, _, sourceFlags, _, destGUID, _, destFlags, _, arg12, arg13, arg14, arg15, arg16, arg17, arg18, arg19, arg20, arg21, arg22, arg23, arg24, _ = getEventInfo()
    if IsSecretValue(cleuEvent) or IsSecretValue(sourceGUID) or IsSecretValue(destGUID) or IsSecretValue(sourceFlags) or IsSecretValue(destFlags) then return end
    local playerEvent, petEvent = (playerGUID == sourceGUID), false
    if not playerEvent then petEvent = (bitband(sourceFlags, typeGuardian) > 0 or bitband(sourceFlags, typePet) > 0) and (bitband(sourceFlags, affiliationMine) > 0) end
    if not (playerEvent or petEvent) then return end
    if (destGUID == playerGUID) then return end
    local guid = destGUID
    if CLEU_DAMAGE_EVENT[cleuEvent] then
        if CLEU_SWING_EVENT[cleuEvent] then
            local amount,_,school,_,_,_,crit,_,_,_ = arg12,arg13,arg14,arg15,arg16,arg17,arg18,arg19,arg20,arg21
            -- A swing carries no spell id: the auto-attack id is passed here, so
            -- a spell event without a usable id can no longer be mistaken for one.
            self:DamageEvent(guid, 6603, amount, false, crit, petEvent, school, 6603) -- 6603 = Auto Attack
        else --its a SPELL event
            -- `periodic` is a BOOLEAN, not the index string.find returned.
            local periodic = (cleuEvent:find("SPELL_PERIODIC", 1, true) ~= nil)
            local spellid,spellname,school1,amount,_,_,_,_,_,crit,_,_,_ = arg12,arg13,arg14,arg15,arg16,arg17,arg18,arg19,arg20,arg21,arg22,arg23,arg24
            if IsSecretValue(spellid) or IsSecretValue(amount) or IsSecretValue(school1) or IsSecretValue(crit) then return end
            -- The numeric id is kept before the classic remap, so the record can
            -- carry both: the runtime key (the name, for an id-0 spell) and the
            -- numeric id the persistence layers are keyed by.
            local spellIdNumeric = spellid
            -- A spell id of 0 is not a usable id: Era, TBC Anniversary and
            -- WotLK Titanforge all report 0 and identify the spell by its NAME
            -- instead. The name is therefore the runtime key on every legacy
            -- client, and it is the key the blacklist and the per-spell merge
            -- interval are looked up with. The numeric id is kept alongside it
            -- so a blacklist entry keyed by the numeric id still matches.
            if (spellid == 0 and IsLegacyClient) then spellid = spellname end
            self:DamageEvent(guid, spellid, amount, periodic, crit, petEvent, school1, spellIdNumeric)
        end
    elseif CLEU_MISS_EVENT[cleuEvent] then
        if CLEU_SWING_EVENT[cleuEvent] then
            local misstype,_,amount = arg12,arg13,arg14
            self:MissEvent(guid, 6603, amount, false, misstype, petEvent, SCHOOL_MASK_PHYSICAL, 6603) -- 6603 = Auto Attack
        else --its a SPELL event
            local periodic = (cleuEvent:find("SPELL_PERIODIC", 1, true) ~= nil)
            local spellid,spellname,school1,misstype,_,amount = arg12,arg13,arg14,arg15,arg16,arg17
            if IsSecretValue(spellid) or IsSecretValue(amount) or IsSecretValue(school1) or IsSecretValue(misstype) then return end
            local spellIdNumeric = spellid
            if (spellid == 0 and IsLegacyClient) then spellid = spellname end
            self:MissEvent(guid, spellid, amount, periodic, misstype, petEvent, school1, spellIdNumeric)
        end
    elseif CLEU_HEALING_EVENT[cleuEvent] then
        if CLEU_SWING_EVENT[cleuEvent] then
            local amount,_,_,crit = arg12,arg13,arg14,arg15
            self:HealingEvent(guid, nil, amount, false, crit, petEvent, nil, nil)
        else --its a SPELL event
            local periodic = (cleuEvent:find("SPELL_PERIODIC", 1, true) ~= nil)
            local spellid,spellname,school1,amount,_,_,crit = arg12,arg13,arg14,arg15,arg16,arg17,arg18
            if IsSecretValue(spellid) or IsSecretValue(amount) or IsSecretValue(school1) or IsSecretValue(crit) then return end
            local spellIdNumeric = spellid
            if (spellid == 0 and IsLegacyClient) then spellid = spellname end
            self:HealingEvent(guid, spellid, amount, periodic, crit, petEvent, school1, spellIdNumeric)
        end
    end
end




-- Latched once per session: a spell event without a usable id is reported once.
local spellIdMissingLogged = false
local function ReportMissingSpellId()
    if spellIdMissingLogged then return end
    spellIdMissingLogged = true
    if (type(CFCT.Log) == "function") then
        CFCT:Log("a spell event arrived without a usable spell id - it is shown as a spell without an icon instead of being treated as an auto attack.")
    end
end

-- WoW event handler: the frame receiver is part of the calling convention.
-- `spellIdNumeric` is the numeric spell id from the combat log, carried
-- alongside the runtime key (`spellid`, which is the spell NAME for a Classic
-- Era spell whose id is 0) so the persistence layers can be looked up by
-- either key.
function f:DamageEvent(guid, spellid, amount, periodic, crit, pet, school, spellIdNumeric) -- luacheck: ignore 212
    if IsSecretValue(amount) or IsSecretValue(spellid) or IsSecretValue(school) or IsSecretValue(guid) or IsSecretValue(crit) then return end
    crit = IsCritFlag(crit)
    -- A classic client can report spell id 0 with an empty name; an empty id is
    -- as unusable as a missing one.
    --
    -- A ZERO id is just as unusable. On every legacy client the id is
    -- remapped to the spell name before this point (see the combat-log
    -- handler), so a zero id can only reach here on a client that does not
    -- apply that mapping. Unnormalised it would be treated as a real spell
    -- id: the icon lookup would run on 0, its negative result would be
    -- cached for the session, and the number would be rendered with no icon
    -- and no diagnostic at all. Normalising it here gives a zero id the
    -- same one-shot report as a missing one.
    if (spellid == 0 or spellid == "") then spellid = nil end
    -- The event type is derived from the spell id and the id itself is left
    -- alone: a missing id used to become 6603 (auto attack), which silently
    -- relabelled a spell event as an auto attack. The swing branch passes 6603
    -- explicitly, so a missing id here means a spell event we cannot name.
    if (spellid == nil) then ReportMissingSpellId() end
    local event = ((spellid == 75) or (spellid == 6603)) and "auto" or "spell" -- 75 = autoshot
    local spellicon = spellid and SpellIconText(spellid) or ""
    CacheEvent(guid, event, amount, nil, spellid, spellicon, periodic, crit, false, pet, school, nil, spellIdNumeric)
end
-- WoW event handler: the frame receiver is part of the calling convention.
function f:MissEvent(guid, spellid, amount, periodic, misstype, pet, school, spellIdNumeric) -- luacheck: ignore 212
    if IsSecretValue(amount) or IsSecretValue(spellid) or IsSecretValue(school) or IsSecretValue(guid) or IsSecretValue(misstype) then return end
    if (spellid == 0 or spellid == "") then spellid = nil end
    if (spellid == nil) then ReportMissingSpellId() end
    local event = ((spellid == 75) or (spellid == 6603)) and "auto" or "spell" -- 75 = autoshot
    local spellicon = spellid and SpellIconText(spellid) or ""
    local missKey = (type(misstype) == "string") and upper(misstype) or "MISS"
    -- An EMPTY miss type would produce an empty text, and an empty string is
    -- TRUTHY in Lua, so the `text or tostring(amount)` fallback in
    -- DispatchText would not rescue it - an invisible number would be
    -- dispatched. An unknown or empty miss type is shown as "Miss".
    local missText = "Miss"
    if (type(misstype) == "string") and (misstype ~= "") then
        missText = lower(misstype):gsub("^%l", upper)
    end
    CacheEvent(guid, event, 0, missText, spellid, spellicon, periodic, false, true, pet, school, missKey, spellIdNumeric)
end
-- WoW event handler: the frame receiver is part of the calling convention.
function f:HealingEvent(guid, spellid, amount, periodic, crit, pet, school, spellIdNumeric) -- luacheck: ignore 212
    if IsSecretValue(amount) or IsSecretValue(spellid) or IsSecretValue(school) or IsSecretValue(guid) or IsSecretValue(crit) then return end
    crit = IsCritFlag(crit)
    local event = "heal"
    local spellicon = spellid and SpellIconText(spellid) or ""
    CacheEvent(guid, event, amount, nil, spellid, spellicon, periodic, crit, false, pet, school, nil, spellIdNumeric)
end
























