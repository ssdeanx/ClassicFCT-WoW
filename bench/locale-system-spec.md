# ClassicFCT locale system — inventory + implementation spec

- **Status:** DRAFT for writer lane. Read-only analysis; no addon code changed.
- **Date:** 2026-10-17
- **Repo state:** working tree = `eaa840f` + uncommitted feature work (off-target dim, small-crit demotion, missStyle engine, `Presets/ClassicPlus.lua`). All `file:line` refs below are against this working tree.
- **Validation owner:** parent session (hands this spec to a writer lane).
- **Target design constraints (given):** lightweight built-in locale tables; NOT LibStub/AceLocale; `Libs/` is vendored and must not change.
- **Validated in /tmp (outside the repo):** draft `locales.lua`, `enUS.lua`, `deDE.lua` pass `luac5.1 -p`, `luacheck` (0 warnings / 0 errors) and a 15-check fallback-chain harness; the 242-key enUS draft is identity-clean. See §3.6.

---

## 0. Decision summary

| # | Decision | Evidence / rationale |
|---|---|---|
| D1 | In-house tables under `Locales/`, no external locale lib | `Libs/` vendored (`AGENTS.md`), no Ace dependency; `Libs/libs.xml` untouched |
| D2 | Key = exact enUS source string (including `%s` placeholders). Missing key -> key itself. Missing locale -> enUS table. `GetLocale()` unsupported -> enUS | Fallback contract requested; keys double as the enUS source, so English can never be lost |
| D3 | `Locales\locales.xml` loads immediately after `Libs\libs.xml`, before `presets.lua`, in all five `.toc` | `CFCT.L` must exist before any `config.lua` file-scope `L()` call (menu tables from `config.lua:406`, `HEADER_TEXT` at `config.lua:927`, UI build from `config.lua:1308`) and is available to `presets.lua` too; `config.lua:29` reads `DefaultPresets` at file scope so preset registration order must not change |
| D4 | Preset names `"Classic"`, `"Mists of Pandaria"`, `"Classic Plus"` are **frozen load-bearing keys** — do not translate, do not rename | §1(d): they are `DefaultPresets`/`CFCT.Presets` keys, `selectedPreset` SavedVariable values, and persisted into `ClassicFCTCustomPresets`; renaming leaves stale duplicates and can nil the schema template (`config.lua:30`) |
| D5 | No SavedVariables change; no language option; locale derived from `GetLocale()` only | Zero migration; existing users unchanged |
| D6 | Combat text, category keys, config values, font names/paths, CVar names, SavedVariables names, slash commands, addon name, debug logs stay enUS | §1(e) explicit exclusion list |

---

## 1. Inventory

Counts from mechanical extraction over the current tree (recipe in §3.6):

- widget-builder string **occurrences**: 263; unique mechanical keys: 239 (checkbox 66, slider 62, button 16, dropdown 16, font-dropdown 2, color-option 4, header 17, input box 3, confirm 4, menu `text` 33, `HEADER_TEXT` 30, `CONFIG_LAYOUT` catnames 10).
- non-mechanical strings added by hand: 13 (7 log messages, `"New preset"`, `"Copy of %s"`, `"Default: %s"`, `"Empty: Attack a Dummy"`, `"%s |cff808080built-in|r"`, `"init"`).
- mechanical extras that are **excluded**: `""` empty header (`config.lua:1310`), `"POPUPDIALOG_TITLE"` (`config.lua:180`, overwritten before display), 8 dead `TextStrataMenu` strings (`config.lua:433-466`).
- **net enUS key set = 242 unique keys** (full paste-ready list in Appendix A).

### (a) Widget labels, tooltips, headers — `config.lua`

**Checkbox label / tooltip** (33 sites)

- L968: "Enable Pow" / "Enables/Disables this animation type"
- L1004: "Enable Fade In" / "Enables/Disables this animation type"
- L1025: "Enable Fade Out" / "Enables/Disables this animation type"
- L1084: "Enable Scroll" / "Enables/Disables this animation type"
- L1107: "Enabled" / "Enables/Disables this event type"
- L1115: "Show Spell Icons" / "Enables/Disables showing spell icons next to damage text"
- L1124: "Color By Type" / "Enables/Disables coloring damage text based on its type (alpha still taken from the text color below)"
- L1311: "Character Specific Config" / "Settings are saved per character. Presets stay global."
- L1322: "Enable ClassicFCT" / "Enables/Disables the addon"
- L1324: "Hide Blizzard Damage" / "Enables/Disables the default Blizzard Floating Damage Text"
- L1331: "Hide Blizzard Healing" / "Enables/Disables the default Blizzard Floating Healing Text"
- L1422: "Attachment Fallback" / "When a nameplate isnt available, the text will temporarily attach to the screen center instead"
- L1423: "Prevent Text Overlap" / "Prevents damage text frames from overlapping each other"
- L1425: "Nameplates In Front" / "Show text behind the nameplates"
- L1426: "Inherit From Nameplates" / "Text inherits some atributes from nameplates, like visibility and scale"
- L1429: "Dim Off-Target Text" / "Dim numbers for units other than your current target"
- L1454: "Abbreviate Large Numbers" / "Abbreviate large numbers (ex.1K)"
- L1455: "Add Thousands Separator" / "Add thousands separator (ex.100,000,000)"
- L1458: "Hide Below Absolute Threshold" / "Hide numbers smaller than an absolute value"
- L1460: "Hide Below Relative Threshold" / "Hide numbers smaller than a percentage of player health"
- L1471: "Hide Below Average Threshold" / "Hide numbers smaller than a percentage of average damage"
- L1482: "Demote Small Crits" / "Show crits below the threshold with the normal (non-crit) styling"
- L1484: "Hide Misses" / "Hides Absorb, Block, Miss, Parry, Dodge, Deflect, Evade, Immune, Reflect and Resist."
- L1561: "Disable By SpellId" / "Stop the selected spell from showing in the damage text"
- L1589: "Sort By Damage/Healing in Descending Order" / "Sort events by amount"
- L1592: "Merge Events" / "Combine damage/healings events with the same spellid into one event"
- L1609: "Show Merge Count" / "Add number of merged events next to the damage/healing (ex '1337 x5')"
- L1726: "Separate Misses" / "Dont merge dodges, parries, misses, and evades with damage events"
- L1727: "Separate By Target" / "Dont merge damage done to different targets"
- L1728: "Separate By Spell ID" / "Dont merge damage with different spellids"
- L1729: "Separate By Spell Icon" / "Dont merge damage with different icons"
- L1730: "Separate By Damage Type" / "Dont merge damage of different types"
- L1757: "Enabled" / "Use separate type colors for damage over time"

**Slider label / tooltip** (31 sites)

- L971: "Duration" / "Animation duration relative to global duration"
- L973: "Duration Ratio" / "Duration ratio between time spent in Start to Mid phase and time spent in Mid to End phase."
- L975: "Start Scale" / "Initial text scale"
- L976: "Mid Scale" / "Mid point text scale"
- L977: "End Scale" / "Final text scale"
- L980: "Overshoot" / "Extra scale added past the end scale before settling back"
- L981: "Settle Ratio" / "Fraction of the second phase spent settling back to the end scale"
- L1007: "Duration" / "Animation duration relative to global duration"
- L1028: "Duration" / "Animation duration relative to global duration"
- L1089: "Distance" / "Scroll distance"
- L1120: "Font Size" / "Font Size"
- L1414: "Animation Duration" / "Animation length in seconds"
- L1415: "Max Simultaneous Numbers" / "Maximum combat numbers visible at once. 0 = unlimited (current behavior). When the limit is reached the oldest number is removed so the newest stays visible."
- L1430: "Off-Target Size Scale" / "Size multiplier for off-target numbers"
- L1432: "Off-Target Alpha" / "Opacity multiplier for off-target numbers"
- L1436: "Screen Center Text X Offset" / "Horizontal offset of animation area"
- L1437: "Screen Center Text Y Offset" / "Vertical offset of animation area"
- L1438: "Nameplate Text X Offset" / "Horizontal offset of animation area"
- L1439: "Nameplate Text Y Offset" / "Vertical offset of animation area"
- L1440: "Anti-Overlap Horizontal Spacing" / "Horizontal spacing between text"
- L1441: "Anti-Overlap Vertical Spacing" / "Vertical spacing between text"
- L1446: "X Offset" / "Horizontal offset of spell icon"
- L1447: "Y Offset" / "Vertical offset of spell icon"
- L1448: "Zoom" / "Zoom in on the icon and trim to edge to give a more square appearance"
- L1449: "Aspect Ratio" / "Aspect ratio of spell icon"
- L1459: "Absolute Threshold" / "Absolute Value"
- L1461: "% of Max Player Health" / "Percentage of Max Player Health"
- L1472: "% of Average Damage/Healing" / "Percentage of Average Damage/Healing"
- L1483: "Small Crit Threshold" / "Crits smaller than this amount lose the crit styling"
- L1598: "Global Merge Interval" / "Max time interval between events for a merge to happen (in seconds)"
- L1691: "Override Merge Interval" / "Max time interval between chosen spell events for a merge to happen (in seconds)"

**Button label / tooltip** (8 sites)

- L1343: "New" / "Creates a new preset"
- L1346: "Copy" / "Creates a copy of the selected preset"
- L1361: "Save" / "Saves current configuration into the selected preset"
- L1365: "Load" / "Loads the selected preset, overwriting current configuration"
- L1369: "Delete" / "Deletes the selected preset permanently"
- L1372: "Rename" / "Renames the selected preset"
- L1717: "Reset" / "Restores chosen spell merge interval to a common setting"
- L1776: "Copy From Above" / "Copies color settings from the damage types above"

**Dropdown label / tooltip (`labelText`/`tooltipText` — inert: no reader found)** (8 sites)

- L1087: "Direction" / "Scroll direction"
- L1119: "Font Style" / "Font style used"
- L1158: "Animations" / "Animations"
- L1353: "Presets" / "Configuration Presets"
- L1419: "Attach Mode" / ""
- L1491: "SpellId Blacklist" / ""
- L1611: "Relative To" / ""
- L1618: "SpellId Override" / ""

**Font dropdown label / tooltip (inert)** (1 site)

- L1118: "Font Face" / "Font face used"

**Color option label / tooltip** (3 sites)

- L1122: "Text Color" / "Custom text color for this event"
- L1744: v / "Custom text color for this type"
- L1796: v / "Custom text color for this type"

**Headers** (17 sites)

- L1132: "Animation Status:"
- L1156: "Animation Settings"
- L1310: ""
- L1342: "Config Presets"
- L1412: "General Settings"
- L1416: "Text Position Options"
- L1418: "Attach Text To"
- L1445: "Spell Icon Options"
- L1453: "Number Formatting Options"
- L1457: "Filtering Options"
- L1489: "SpellId Blacklist"
- L1588: "Sorting Options"
- L1591: "Merging Options"
- L1610: "Relative To"
- L1614: "SpellId Override"
- L1733: "Damage Type Colors"
- L1754: "Override Type Colors for Damage Over Time"

**Input box titles** (3 sites)

- L302: "Preset Name"
- L316: "Preset Name"
- L330: "Preset Name"

**Confirm dialogs** (4 sites)

- L271: "This will overwrite your current configuration. Are you sure?"
- L284: "This will overwrite your the selected preset. Are you sure?"
- L344: "This will delete the preset permanently. Are you sure?"
- L1777: "This will overwrite all color settings below."

**Menu item `text` fields** (33 sites)

- L180: "POPUPDIALOG_TITLE"
- L408: "Screen Center"
- L412: "Target Nameplate"
- L416: "Every Nameplate"
- L422: "First Event"
- L426: "Last Event"
- L437: "Background"
- L441: "Low"
- L445: "Medium"
- L449: "High"
- L453: "Dialog"
- L457: "Fullscreen"
- L461: "Fullscreen Dialog"
- L465: "Tooltip"
- L475: "Pow"
- L479: "Fade In"
- L483: "Fade Out"
- L487: "Scroll"
- L500: "No Outline"
- L504: "No Outline Monochrome"
- L508: "Outline"
- L512: "Outline Monochrome"
- L516: "Thick Outline"
- L520: "Thick Outline Monochrome"
- L1042: "Scroll Up"
- L1046: "Scroll Down"
- L1050: "Scroll Left"
- L1054: "Scroll Right"
- L1058: "Scroll Up & Left"
- L1062: "Scroll Up & Right"
- L1066: "Scroll Down & Left"
- L1070: "Scroll Down & Right"
- L1074: "Random Direction"

**`HEADER_TEXT` values (display-only; keys stay enUS)** (30 sites, L928-L961)

- L928: `auto` -> "Auto Hits"
- L929: `automiss` -> "Auto Misses"
- L930: `autocrit` -> "Auto Crits"
- L931: `petauto` -> "Pet Auto Hits"
- L932: `petautomiss` -> "Pet Auto Misses"
- L933: `petautocrit` -> "Pet Auto Crits"
- L935: `spell` -> "Spell Hits"
- L936: `spellmiss` -> "Spell Misses"
- L937: `spellcrit` -> "Spell Crits"
- L938: `spelltick` -> "DoT Ticks"
- L939: `spelltickmiss` -> "DoT Miss Ticks"
- L940: `spelltickcrit` -> "DoT Crit Ticks"
- L942: `petspell` -> "Pet Spell Hits"
- L943: `petspellmiss` -> "Pet Spell Misses"
- L944: `petspellcrit` -> "Pet Spell Crits"
- L945: `petspelltick` -> "Pet DoT Ticks"
- L946: `petspelltickmiss` -> "Pet DoT Miss Ticks"
- L947: `petspelltickcrit` -> "Pet DoT Crit Ticks"
- L949: `heal` -> "Heals"
- L950: `healmiss` -> "Heal Misses"
- L951: `healcrit` -> "Heal Crits"
- L952: `healtick` -> "HoT Ticks"
- L953: `healtickmiss` -> "HoT Miss Ticks"
- L954: `healtickcrit` -> "HoT Crit Ticks"
- L956: `petheal` -> "Pet Heals"
- L957: `pethealmiss` -> "Pet Heal Misses"
- L958: `pethealcrit` -> "Pet Heal Crits"
- L959: `pethealtick` -> "Pet HoT Ticks"
- L960: `pethealtickmiss` -> "Pet HoT Miss Ticks"
- L961: `pethealtickcrit` -> "Pet HoT Crit Ticks"

**`CONFIG_LAYOUT` catnames (sub-panel display names)** (10 sites)

- L1808: "Auto Attacks"
- L1816: "Special Attacks"
- L1824: "Damage Over Time"
- L1832: "Heals"
- L1840: "Heals Over Time"
- L1848: "Pet Auto Attacks"
- L1856: "Pet Special Attacks"
- L1864: "Pet Damage Over Time"
- L1872: "Pet Heals"
- L1880: "Pet Heals Over Time"

**Dynamic/misc UI strings**

- L628: `"Default: "` prefix (tooltip requirement)
- L654: `"Default: "` prefix (tooltip requirement)
- L1131: `"init"` (animation status placeholder)
- L1380: `" |cff808080built-in|r"` (built-in preset suffix)
- L1467: dynamic `% of ...` label rebuilt in OnUpdate (literal `%` — see format rules)
- L1478: dynamic `% of ...` label rebuilt in OnUpdate (literal `%` — see format rules)
- L1559: `"Empty: Attack a Dummy"` (dropdown placeholder when no spell cached)
- L1688: `"Empty: Attack a Dummy"` (dropdown placeholder when no spell cached)

**Inert note:** the `label` argument of `CreateDropDownMenu` and `CreateFontDropdown` is only stored as `dropdown.labelText` (`config.lua:745`, `config.lua:786`); a repo-wide search finds no reader, and live dropdown text comes from the selected item / `getglobal(name.."Text")` (`config.lua:770`, `config.lua:830`, `config.lua:1398`, `config.lua:1559`, `config.lua:1688`). Wrapping them in `L()` is harmless and future-proof, but changes nothing on screen today.

**Dead strings:** `TextStrataMenu` (`config.lua:431-468`) is never referenced (only `textStrata` config values exist in presets, e.g. `Presets/MoP.lua:31`, and the consumer is commented out at `main.lua:682`). Do not translate or wire it.

**School-name labels:** `CreateColorOption(v, ...)` at `config.lua:1744` and `config.lua:1796` pass `v` from `SCHOOL_NAMES` (`config.lua:525-569`), which already resolves client-localized `STRING_SCHOOL_*` globals via `_G[globalName] or EnglishFallback`. Leave untouched this pass (non-goal §4.2).

### (b) Chat/log messages (`CFCT:Log` call sites)

| Ref | Current text | Notes |
|---|---|---|
| `config.lua:274`, `config.lua:277` | `presetName.." preset loaded."` | becomes `L("%s preset loaded.", presetName)` |
| `config.lua:287` | `"Config saved to "..presetName.." preset."` | becomes `L("Config saved to %s preset.", presetName)` |
| `config.lua:309`, `config.lua:323`, `config.lua:337` | `"Preset "..value.." already exists"` | becomes `L("Preset %s already exists", value)` (no trailing period today — preserve) |
| `config.lua:353` | `"Defaults restored."` | `L("Defaults restored.")` |
| `presets.lua:10` | `"Preset '"..name.."' already exists."` | becomes `L("Preset '%s' already exists.", name)` |
| `main.lua:1067` | `"Could not register event "..tostring(e)..": "..tostring(err)` | becomes `L("Could not register event %s: %s", tostring(e), tostring(err))` |
| `main.lua:1157` | restricted-client notice (full sentence) | becomes `L(...)`; only visible on Retail/Forever |

**Excluded (dev/debug/release):** verbose `UpdateTable` logs `config.lua:136-145` (gated by `CFCT.debug`), `UpdateTable` asserts `config.lua:131-134`, `"Invalid Log Range"` `config.lua:173`, the addon prefix `"|cffffff00ClassicFCT: |r|cffffff80"` `config.lua:166-170` (brand), and the version/changelog message `main.lua:1147-1151` (release notes; English by intent).

### (c) Slash-command help/error text

None exists. `/cfct` (`config.lua:365-368`) opens the options directly; `/fs` (`config.lua:369-372`) toggles FrameStackTooltip. No usage/error strings to translate — group intentionally empty. Slash names stay as-is.

### (d) Preset display names — the critical migration question

Registered names:

- `presets.lua:6` `CFCT:AddDefaultPreset(name, config)`; registrations at `Presets/Classic.lua:2` `"Classic"`, `Presets/ClassicPlus.lua:2` `"Classic Plus"`, `Presets/MoP.lua:23` `"Mists of Pandaria"`.

Every use of these strings as **keys** (all load-bearing):

1. `config.lua:29-30` — `DefaultPresets = CFCT:GetDefaultPresets()`, `DefaultConfig = DefaultPresets["Mists of Pandaria"]`. `DefaultConfig` is the **entire config schema template** for `OnLoad`/`OnSave`/`RestoreDefaults` (`config.lua:229-230`, `config.lua:242-243`, `config.lua:259-260`, `config.lua:266-267`, `config.lua:350`) and for new presets (`config.lua:306`), plus per-category default seeding (`config.lua:966`, `config.lua:1002`, `config.lua:1023`, `config.lua:1082`). If the key went missing, `DefaultConfig` = nil and `UpdateTable` asserts at `config.lua:132` during `ADDON_LOADED` (`main.lua:1143`).
2. `config.lua:219-220` — `CFCT.Presets` receives `ClassicFCTCustomPresets` **then** `DefaultPresets`; built-in names collide by design.
3. `config.lua:270-281` — `LoadPreset` looks up `CFCT.Presets[presetName]` / `DefaultPresets[presetName]`.
4. `config.lua:284-288` — `SavePreset` uses `DefaultPresets[presetName] == nil` as the built-in vs custom discriminator.
5. `config.lua:291-299` — `NewPresetName` collision check `CFCT.Presets[name] == nil`.
6. `config.lua:1376-1410` — dropdown builds `value = k` from both tables, `text = k.." |cff808080built-in|r"` for built-ins, and disables Save/Delete/Rename when `DefaultPresets[self.curValue]` (`config.lua:1399-1409`). Selection fallback `CFCT.selectedPreset = PresetMenu[1].value` (`config.lua:1392-1394`).
7. **Persistence:**
   - `selectedPreset` is in `DefaultVars`/`DefaultCharVars` (`config.lua:37`, `config.lua:45`), saved to `ClassicFCTVars`/`ClassicFCTCharVars` (`config.lua:256-257`, `config.lua:263-264`) — its value is a preset name.
   - `OnSave` writes **all** of `CFCT.Presets` (including the three built-ins) into `ClassicFCTCustomPresets` with overwrite (`config.lua:251-252`), so built-in names also become **table keys inside SavedVariables**.
   - `OnLoad` re-merges them (`config.lua:219-220`), then overwrites built-in content from defaults.

**Consequence:** renaming a built-in preset would (a) break the schema lookup at `config.lua:30` unless `config.lua:30` is also changed, (b) leave the old-name preset in `ClassicFCTCustomPresets` treated as a *custom* preset (dropdown shows a duplicate, Save/Delete/Rename become enabled), and (c) break `selectedPreset` for every existing user. **Verdict: load-bearing keys — keep enUS, never rename.**

**Display-translation path (optional, later):** only the dropdown `text` and log strings may be localized. Minimal-churn separation already exists: `text` vs `value` are separate fields at `config.lua:1379-1390`. To localize display without touching keys, keep `value = k` and set `text = L("%s |cff808080built-in|r", k)`; a per-preset display map (e.g. `CFCT.L("preset:Mists of Pandaria")` falling back to `k`) is the only extra step. Not part of this pass — the three names are recognizable product/expansion names.

### (e) Explicit exclusion list (must NOT be translated)

| # | Items | Refs |
|---|---|---|
| E1 | Combat text content: miss text from CLEU (`strlower(misstype)` -> "Dodged", "Missed", ...); preview literal `"Miss"`; merge counter suffix `" x"`; `AbbreviateNumbers` output; icon-texture escape `\|T...\|t` | `main.lua:1326-1327`, `main.lua:1010`, `main.lua:806`, `main.lua:747` |
| E2 | Category/event keys: `cat` composition (`pet`/`tick`/`crit`/`miss`), `"auto"`/`"spell"`/`"heal"`, attach-mode `"sc"/"tn"/"en"`, sort `"target"`, CLEU event-name tables | `main.lua:764-765`, `main.lua:1078-1081`, `main.lua:1317`, `main.lua:1324`, `main.lua:1332`, `main.lua:1208-1248` |
| E3 | Miss-style lookup keys (`"MISS"` default, CLEU misstype tokens DODGE/PARRY/BLOCK/...) | `main.lua:825-829`, `main.lua:1326` |
| E4 | Menu/config **values** (only `text` is translatable): `"sc"/"tn"/"en"`, `"first"/"last"`, `""/"MONOCHROME"/"OUTLINE"/"OUTLINE,MONOCHROME"/"THICKOUTLINE"/"THICKOUTLINE,MONOCHROME"`, `"UP".../"RANDOM"`, `"Pow"/"FadeIn"/"FadeOut"/"Scroll"`; `textStrata = "MEDIUM"` | `config.lua:406-490`, `config.lua:499-523`, `config.lua:1040-1077`, `Presets/MoP.lua:31` |
| E5 | `"Config.*"` path strings passed to `WidgetConfigBridgeGet/Set` / `SetValue` | `config.lua:97-126`, e.g. `config.lua:968-1730` |
| E6 | Font identifiers/paths (`"Friz Quadrata TT"`, `"Fonts\\FRIZQT__.TTF"`, LibSharedMedia names) | `config.lua:709-735` |
| E7 | CVar names (`floatingCombatTextCombatDamage/Healing`) | `config.lua:1327-1336`, `main.lua:1027-1045` |
| E8 | SavedVariables names (`.toc` lines 6-7), frame/global names (`"ClassicFCT.frame"`, `"CLASSICFCT_POPUPDIALOG"`, `"ClassicFCTConfigPanel_"..name`), Settings category brand `"ClassicFCT"` | `main.lua:54`, `config.lua:179`, `config.lua:1231`, `config.lua:1308` |
| E9 | Slash commands `/cfct`, `/fs` | `config.lua:365`, `config.lua:369` |
| E10 | Addon log prefix, version/changelog block, debug logs/asserts | `config.lua:166-173`, `main.lua:1147-1151`, `config.lua:131-145` |
| E11 | `SCHOOL_NAMES` global names + English fallbacks (client-localized already) | `config.lua:525-569` |
| E12 | Dead `TextStrataMenu` strings; `"POPUPDIALOG_TITLE"` placeholder; empty `""` header; `"OK"` literal popup button (`config.lua:181`; `button2 = "Cancel"` at `config.lua:182` is optional — see §4.3) | `config.lua:431-468`, `config.lua:180`, `config.lua:1310`, `config.lua:181-182` |
| E13 | Number formatting itself (thousands separator is always `,`) | `main.lua:113-118` (behavior lock; non-goal) |

---

## 2. File/API design

### 2.1 Files to add (all under `Locales/`)

```
Locales/
  locales.xml    -- script list only (pattern: Presets/presets.xml)
  locales.lua    -- registry + CFCT.L + lazy locale resolution
  enUS.lua       -- authoritative enUS table (242 identity entries, Appendix A)
  deDE.lua       -- German table (may start as a subset; fallback covers the rest)
  ruRU.lua       -- Russian table (may start as a subset)
```

`Locales/` **is addon content and must ship in release zips** (unlike `desks/`, `bench/`, `classroom/`, excluded per `AGENTS.md`).

### 2.2 Load order and `.toc` change (all five files)

Current block is identical in all five `.toc` files (`ClassicFCT-Vanilla.toc:10-12`, `ClassicFCT-TBC.toc:10-12`, `ClassicFCT-Titan.toc:10-12`, `ClassicFCT-Forever.toc:10-12`, `ClassicFCT-Mainline.toc:10-12`):

```
Libs\libs.xml

presets.lua
```

Change to (insert one line; keep blank lines and backslash style):

```
Libs\libs.xml
Locales\locales.xml

presets.lua
```

Resulting documented order: `Libs\libs.xml -> Locales\locales.xml -> presets.lua -> Presets\presets.xml -> config.lua -> main.lua`. This satisfies the two hard constraints: `config.lua:29-30` still reads fully-registered `DefaultPresets`, and every file-scope `L()` call in `config.lua` (menu tables from `config.lua:406`, `HEADER_TEXT` at `config.lua:927`, UI build from `config.lua:1308`) has `CFCT.L` available. `main.lua` reads `CFCT.Config` only inside runtime functions (e.g. `main.lua:1141-1161`), so it has no ordering constraint beyond "after config.lua", unchanged.

`Locales/locales.xml` (mirror `Presets/presets.xml`):

```xml
<Ui xmlns="http://www.blizzard.com/wow/ui/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.blizzard.com/wow/ui/..\FrameXML\UI.xsd">
    <Script file="locales.lua"/>
    <Script file="enUS.lua"/>
    <Script file="deDE.lua"/>
    <Script file="ruRU.lua"/>
</Ui>
```

`locales.lua` must be first; enUS is unconditional so English always exists.

### 2.3 API — `Locales/locales.lua` (validated draft, Lua 5.1)

```lua
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
```

### 2.4 Exact fallback chain

1. active code = `GetLocale()` when it is a function, else `"enUS"`;
2. if `CFCT.Locales[code]` is nil (unsupported locale, e.g. `frFR`, `zhCN`) -> code = `"enUS"`;
3. `str = activeTable[key] or CFCT.Locales.enUS[key] or key`;
4. if extra args were passed, `str = pcall(string.format, str, ...)`; on failure return the unformatted `str`;
5. resolution is cached: `GetLocale()` is called at most once per session; `CFCT.localeCode` exposes the resolved code.

- **Missing locale:** step 2 -> enUS entirely.
- **Missing key:** step 3 -> the key, which *is* the enUS source string.
- **enUS always loads:** unconditional `<Script file="enUS.lua"/>`; even if the table were absent, step 3 still yields English. Runtime cannot error on a missing translation.
- **Unsupported `GetLocale()`:** normal path, English UI.
- **Restricted clients (Retail 120100 / Forever 16001):** no interaction with `IsRestrictedCombat` (`main.lua:9-18`); `GetLocale()` exists on all five supported branches (verified in `/home/sam/wow-ui-source`: `GetLocale` is declared in `Interface/AddOns/Blizzard_APIDocumentationGenerated/LocaleDocumentation.lua` on `classic_era`, `classic_anniversary`, `classic_titan`, `origin/forever`, `live`). The restricted notice (`main.lua:1157`) is translated like any message.

### 2.5 Representative entries (same 12 keys in all three files)

`Locales/enUS.lua` opens with `-- luacheck: no max line length`, `local _, CFCT = ...`, then registers. Excerpt:

| Key (enUS identity) | deDE | ruRU |
|---|---|---|
| `"Screen Center"` | `"Bildschirmmitte"` | `"Центр экрана"` |
| `"Target Nameplate"` | `"Zielnamensplakette"` | `"Табличка цели"` |
| `"Config Presets"` | `"Konfigurationsprofile"` | `"Профили настроек"` |
| `"General Settings"` | `"Allgemeine Einstellungen"` | `"Общие настройки"` |
| `"Merge Events"` | `"Ereignisse zusammenfassen"` | `"Объединять события"` |
| `"Defaults restored."` | `"Standardeinstellungen wiederhergestellt."` | `"Настройки по умолчанию восстановлены."` |
| `"%s preset loaded."` | `"Profil %s geladen."` | `"Профиль %s загружен."` |
| `"Preset %s already exists"` | `"Profil %s ist bereits vorhanden"` | `"Профиль %s уже существует"` |
| `"Custom text color for this type"` | `"Benutzerdefinierte Textfarbe für diesen Typ"` | `"Свой цвет текста для этого типа"` |
| `"This will overwrite your current configuration. Are you sure?"` | `"Die aktuelle Konfiguration wird überschrieben. Fortfahren?"` | `"Текущая конфигурация будет перезаписана. Продолжить?"` |
| `"Default: %s"` | `"Standard: %s"` | `"По умолчанию: %s"` |
| `"%s \|cff808080built-in\|r"` | `"%s \|cff808080integriert\|r"` | `"%s \|cff808080встроенный\|r"` |

Translation rules for locale files: keep `%s` placeholders and their count; keep `|cff......|r` escape codes; UTF-8 without BOM; no locale file may define a key that is not in enUS (typo guard, §3.6).

### 2.6 Format-string audit (`format()` with user text)

| Site | Current | Change | Rule |
|---|---|---|---|
| `config.lua:294` | `format("%s%s", baseName, i)` in `NewPresetName` | `baseName` becomes `L("New preset")` / `L("Copy of %s", presetName)` at `config.lua:301` / `config.lua:315` | only affects default names of **new** custom presets; enUS output byte-identical |
| `config.lua:628` | `"Default: " .. (tostring(defVal) ~= "nil" and tostring(defVal) or "")` | `L("Default: %s", ...)` | enUS output identical |
| `config.lua:654` | `"Default: " .. (defVal or "")` | `L("Default: %s", defVal or "")` | enUS output identical |
| `config.lua:1467`, `config.lua:1478` | `"% of Max Player Health ("..tostring(n)..")"`, `"% of Average Damage/Healing ("..n..")"` | `L("% of Max Player Health").." ("..tostring(n)..")"` | **never pass these keys to `L` with args** — the literal `%` is not a valid format spec; the pcall guard would silently drop the number. Keep concatenation for these two. |
| `config.lua:1515`, `config.lua:1526`, `config.lua:1641`, `config.lua:1652` | icon + localized client spell name + id | untouched | no translatable words |
| `main.lua:1067` | `"Could not register event "..` | `L("Could not register event %s: %s", ...)` | key = format string |
| `main.lua:806` | `text.." x"..count` | untouched | combat text (E1) |

`CFCT.L` is the only new `format()` call site. All format keys and their placeholders are in Appendix A (8 of them).

---

## 3. Migration / behavior safety + verification plan

### 3.1 SavedVariables

- No new SavedVariables; `.toc` lines 6-7 unchanged; `UpdateTable` templates (`config.lua:31-69`) unchanged.
- Locale selection is never persisted — it is derived from `GetLocale()` each session.
- Existing users: `ClassicFCTVars.selectedPreset` / `ClassicFCTCharVars.selectedPreset` keep their enUS keys (`config.lua:37`, `config.lua:45`); dropdown `value` stays the key (`config.lua:1381`, `config.lua:1388`), so selection resolves exactly as today (`config.lua:1392-1394`).
- `ClassicFCTCustomPresets` (which also holds built-in-name entries from `config.lua:251-252`) is read/written exactly as before; no renames -> no stale duplicates.

### 3.2 Preset keys

Frozen (D4). The only preset-related behavior change: **new** custom presets created on a non-enUS client get a localized default name (`L("New preset")`, `L("Copy of %s", ...)`); names are user-editable, collision-handled (`config.lua:291-299`), and never treated as built-ins (`config.lua:284-285`). Existing presets keep their names.

### 3.3 Combat text

Zero `L()` calls in the dispatch path (`main.lua:764-883`) and in `CacheEvent`/`ProcessCachedEvents` (`main.lua:889-983`); miss text, category keys, merge suffix, markup and colors unchanged. Category names (`HEADER_TEXT` keys, `cat` values) stay enUS as required.

### 3.4 What changes on screen for an enUS user

Nothing, if the replacement rule is followed: every `L("X")` resolves to `"X"` through the identity enUS table. The mechanical completeness check in §3.6 exists to prove that.

### 3.5 Checks (offline)

Baselines (current tree, before the change):

- `luac5.1 -p config.lua main.lua presets.lua Presets/*.lua` -> clean.
- `luacheck main.lua config.lua` -> **523 warnings / 0 errors in 2 files** (all warnings pre-existing: WoW globals, line length, unused args). Gate: **0 errors and no new warning count in these two files**.
- `luacheck presets.lua` -> 1 pre-existing warning (`presets.lua:1` unused `addonName`).
- Full-tree `luacheck` -> 721 warnings / 0 errors in 6 files (reference only; `Enum` etc. are client globals).

New-file rule: `Locales/*.lua` should be 0 warnings / 0 errors using the inline directives shown in §2.3/§2.5 (`-- luacheck: globals GetLocale`, `-- luacheck: no max line length`).

### 3.6 Stub harness (extend `/tmp/opencode/fct_harness.lua`, lua5.1)

The existing harness pattern (extract real files verbatim + stub env; `/tmp/opencode/fct_harness.lua:66-73`) is reused. Add a section E:

1. **Fallback chain** (validated draft already passes these 15 checks in /tmp):
   - enUS identity: `L("Screen Center") == "Screen Center"`;
   - missing key: `L("no such key") == "no such key"`;
   - deDE table: translated key -> translation; untranslated key -> English;
   - `GetLocale()` = `"frFR"` (no table) -> enUS entirely, `GetActiveLocale() == "enUS"`;
   - `GetLocale` absent -> enUS;
   - `deDE` requested but deDE table absent -> enUS;
   - format: `L("Default: %s", 5)` -> formatted; `L("Default: %s")` (no args) -> raw key; bad translator value (`"%d"` with a string arg) -> unformatted, no throw;
   - caching: `GetLocale` call count == 1 across repeated calls.
2. **Full enUS identity + coverage**: load `locales.lua` + `enUS.lua`; assert all 242 entries are identity (`L(k) == k`), and that each of the 8 format keys resolves with the right arg count.
3. **Completeness vs pre-change snapshot** (uses a validator-made snapshot of the current working tree, since `/tmp/opencode/fct_baseline/config.lua` is **stale** — it predates the off-target/demote UI strings and must not be used):
   - extract candidate display strings from the pre-change `config.lua` with the builder regexes used for §1 (checkbox/slider/button/dropdown/font-dropdown/color-option/header/input-box/confirm + `text = "..."` + `HEADER_TEXT` + `CONFIG_LAYOUT` catnames);
   - remove the explicit exclusions `""`, `"POPUPDIALOG_TITLE"`, the 8 `TextStrataMenu` strings;
   - extract all `L("...")` string literals from the post-change `config.lua`, `main.lua`, `presets.lua`;
   - assert every non-excluded pre-change string is wrapped, and every new `L()` key exists in the loaded enUS table (catches typos: a typo'd key would otherwise silently render the typo).
4. **`.toc` order guard**: for all five `.toc`, assert `Locales\locales.xml` appears after `Libs\libs.xml` and before `presets.lua`.
5. **Regression**: existing sections A-D must keep their current result: `checks=719 failures=1` — see §3.7. No locale-related change may alter that delta.

Run: `lua5.1 /tmp/opencode/fct_harness.lua` (uses `FCT_REPO` / `FCT_BASE` env for mutation/parity runs).

### 3.7 Pre-existing harness caveat (unrelated to locales)

Current tree result: `checks=719 failures=1`, the failure is `off-target: no target -> all dimmed` at `/tmp/opencode/fct_harness.lua:564-566`. Cause: the working tree added the `targetGUID and` guard (`main.lua:846-852`, `targetGUID` declared `main.lua:760-763`), so with no target nothing is dimmed, while the stale harness still expects dimming. This delta predates the locale task (it is the "no-target dim semantics" open intent question). Do not "fix" it as part of locale work; the validator should decide whether code or harness is authoritative.

### 3.8 In-game checklist (operator)

Per supported client (`ClassicFCT-Vanilla.toc:1` 11509, TBC 20506, Titan 38002, Forever 16001, Mainline 120100):

1. `/cfct` opens; every label/tooltip/header renders (no blanks, no `%s` leakage, no `nil`).
2. enUS client: spot-check 12 strings byte-identical to pre-change (list in §2.5 samples).
3. deDE/ruRU client (if available): sample strings localized; untranslated keys fall back to English.
4. Presets: create (dialog title + default name localized), rename, delete, save custom, load built-in; built-in badge localized; Save/Delete/Rename stay disabled for built-ins; `/reload` -> selection persists; built-in names still `"Classic"`, `"Mists of Pandaria"`, `"Classic Plus"` in the dropdown.
5. Chat log: load preset / restore defaults -> localized `CFCT:Log` lines; prefix still `ClassicFCT:`.
6. Retail + Forever: options work; after ~7s the restricted notice appears localized; no ClassicFCT combat numbers.
7. Legacy clients: `InterfaceOptions` panel list shows localized sub-panel names; Retail/Forever: Settings subcategories localized.

---

## 4. Ordered implementation steps (writer lane)

Do not start until the validator has snapshotted the pre-change tree (recommended: `mkdir -p /tmp/opencode/locale_baseline && cp config.lua main.lua presets.lua /tmp/opencode/locale_baseline/` plus a `git diff` stash of the current tree for diff review).

1. **Create `Locales/locales.lua`** — paste §2.3 verbatim.
2. **Create `Locales/enUS.lua`** — header lines from §2.5, then register all 242 keys from Appendix A as identity entries (`["K"] = "K",`). Keep the section comments.
3. **Create `Locales/deDE.lua` and `Locales/ruRU.lua`** — header + `CFCT:RegisterLocale("<code>", { ... })` with the §2.5 sample entries (initial subset is fine; fallback covers the rest). Add a `-- todo: remaining keys fall back to enUS` comment.
4. **Create `Locales/locales.xml`** — paste §2.2; script order `locales.lua`, `enUS.lua`, `deDE.lua`, `ruRU.lua`.
5. **Edit all five `.toc`** — insert `Locales\locales.xml` per §2.2 (one line, after `Libs\libs.xml`, blank lines preserved).
6. **Edit `config.lua`**:
   - add `local L = CFCT.L` after line 1 (`local addonName, CFCT = ...`);
   - wrap every §1(a) string, every §1(b) message, and the §2.6 sites with `L(...)` — **display positions only**;
   - never touch an adjacent `value =`, `Config.*` path, `text =` menu `value` field, font name/path, CVar or SavedVariables name;
   - dynamic `%`-labels follow the `config.lua:1467`/`config.lua:1478` rule (concatenate the number, no format args);
   - preset dropdown: `text = L("%s |cff808080built-in|r", k)` is **not** this pass — leave `config.lua:1380` text as-is unless D4's optional display path is separately approved;
   - keep `"ClassicFCT"` at `config.lua:1308` and all values in E2-E6 untouched.
7. **Edit `main.lua`** — add `local L = CFCT.L` after line 1; replace only `main.lua:1067` and `main.lua:1157`. Do not touch the dispatch path, CLEU, or the changelog block.
8. **Edit `presets.lua`** — add `local L = CFCT.L` after line 1; `presets.lua:10` becomes `CFCT:Log(L("Preset '%s' already exists.", name))`.
9. **Edit `.vscode/settings.json`** — add `"GetLocale"` to `Lua.diagnostics.globals` (repo convention; `GetLocale` is already in `.luarc.json:182`). No other config change needed — `CFCT.L` is a table field, not a new global.
10. **Offline checks** — run §3.5 commands; require 0 errors and no new warnings in `config.lua`/`main.lua`; `Locales/*.lua` 0/0 with the inline directives.
11. **Harness** — validator extends `/tmp/opencode/fct_harness.lua` with §3.6 section E and re-runs `lua5.1 /tmp/opencode/fct_harness.lua`; expected: all new locale checks pass, existing A-D result unchanged (`checks=719 failures=1` per §3.7).
12. **Diff review** — confirm the replacement rule mechanically: no plain display literal remains in a display position; no `value`/key/path changed; `git diff` shows only `L(...)` wrappings plus the new files, five `.toc` lines, and the `.vscode/settings.json` entry.

### 4.1 Non-goals (explicit)

- No translation of: combat text or miss text, category keys, preset names/keys, menu `value` fields, `Config.*` paths, font names/paths, CVars, SavedVariables/frame/global names, slash commands, addon name/prefix, debug logs/asserts, version changelog.
- No language selector UI; no SavedVariables language override; no runtime locale switching.
- No LibStub/AceLocale; no `Libs/` or `Libs/libs.xml` changes.
- No SchoolName conversion (client `_G` already localizes; §1(a) note).
- No `TextStrataMenu` resurrection; no `textStrata` wiring.
- No number-format localization (thousands separator stays `,`; E13).
- No `.toc` metadata localization (`## Title-deDE`/`## Notes-deDE` are a valid future no-code option but out of scope).
- No README/CHANGELOG/docs/version updates in this pass (release-time tasks).
- No fix for the pre-existing harness delta in §3.7.

### 4.2 Optional follow-ups (not this pass)

- Follow-up 1: school-name fallbacks via `L()` so classic clients without `STRING_SCHOOL_*` get a translated label (touches `config.lua:528-530` + ~32 keys).
- Follow-up 2: built-in preset **display** names via a display map (D4) — only after the schema/key guarantees above are accepted.
- Follow-up 3: `.toc` `## Notes-deDE`/`## Notes-ruRU` metadata.

---

## Appendix A — full enUS table (242 keys, paste-ready)

```lua
-- luacheck: no max line length
local _, CFCT = ...

CFCT:RegisterLocale("enUS", {
    -- Checkbox labels
    ["Enable Pow"] = "Enable Pow",
    ["Enable Fade In"] = "Enable Fade In",
    ["Enable Fade Out"] = "Enable Fade Out",
    ["Enable Scroll"] = "Enable Scroll",
    ["Enabled"] = "Enabled",
    ["Show Spell Icons"] = "Show Spell Icons",
    ["Color By Type"] = "Color By Type",
    ["Character Specific Config"] = "Character Specific Config",
    ["Enable ClassicFCT"] = "Enable ClassicFCT",
    ["Hide Blizzard Damage"] = "Hide Blizzard Damage",
    ["Hide Blizzard Healing"] = "Hide Blizzard Healing",
    ["Attachment Fallback"] = "Attachment Fallback",
    ["Prevent Text Overlap"] = "Prevent Text Overlap",
    ["Nameplates In Front"] = "Nameplates In Front",
    ["Inherit From Nameplates"] = "Inherit From Nameplates",
    ["Dim Off-Target Text"] = "Dim Off-Target Text",
    ["Abbreviate Large Numbers"] = "Abbreviate Large Numbers",
    ["Add Thousands Separator"] = "Add Thousands Separator",
    ["Hide Below Absolute Threshold"] = "Hide Below Absolute Threshold",
    ["Hide Below Relative Threshold"] = "Hide Below Relative Threshold",
    ["Hide Below Average Threshold"] = "Hide Below Average Threshold",
    ["Demote Small Crits"] = "Demote Small Crits",
    ["Hide Misses"] = "Hide Misses",
    ["Disable By SpellId"] = "Disable By SpellId",
    ["Sort By Damage/Healing in Descending Order"] = "Sort By Damage/Healing in Descending Order",
    ["Merge Events"] = "Merge Events",
    ["Show Merge Count"] = "Show Merge Count",
    ["Separate Misses"] = "Separate Misses",
    ["Separate By Target"] = "Separate By Target",
    ["Separate By Spell ID"] = "Separate By Spell ID",
    ["Separate By Spell Icon"] = "Separate By Spell Icon",
    ["Separate By Damage Type"] = "Separate By Damage Type",
    -- Checkbox tooltips
    ["Enables/Disables this animation type"] = "Enables/Disables this animation type",
    ["Enables/Disables this event type"] = "Enables/Disables this event type",
    ["Enables/Disables showing spell icons next to damage text"] = "Enables/Disables showing spell icons next to damage text",
    ["Enables/Disables coloring damage text based on its type (alpha still taken from the text color below)"] = "Enables/Disables coloring damage text based on its type (alpha still taken from the text color below)",
    ["Settings are saved per character. Presets stay global."] = "Settings are saved per character. Presets stay global.",
    ["Enables/Disables the addon"] = "Enables/Disables the addon",
    ["Enables/Disables the default Blizzard Floating Damage Text"] = "Enables/Disables the default Blizzard Floating Damage Text",
    ["Enables/Disables the default Blizzard Floating Healing Text"] = "Enables/Disables the default Blizzard Floating Healing Text",
    ["When a nameplate isnt available, the text will temporarily attach to the screen center instead"] = "When a nameplate isnt available, the text will temporarily attach to the screen center instead",
    ["Prevents damage text frames from overlapping each other"] = "Prevents damage text frames from overlapping each other",
    ["Show text behind the nameplates"] = "Show text behind the nameplates",
    ["Text inherits some atributes from nameplates, like visibility and scale"] = "Text inherits some atributes from nameplates, like visibility and scale",
    ["Dim numbers for units other than your current target"] = "Dim numbers for units other than your current target",
    ["Abbreviate large numbers (ex.1K)"] = "Abbreviate large numbers (ex.1K)",
    ["Add thousands separator (ex.100,000,000)"] = "Add thousands separator (ex.100,000,000)",
    ["Hide numbers smaller than an absolute value"] = "Hide numbers smaller than an absolute value",
    ["Hide numbers smaller than a percentage of player health"] = "Hide numbers smaller than a percentage of player health",
    ["Hide numbers smaller than a percentage of average damage"] = "Hide numbers smaller than a percentage of average damage",
    ["Show crits below the threshold with the normal (non-crit) styling"] = "Show crits below the threshold with the normal (non-crit) styling",
    ["Hides Absorb, Block, Miss, Parry, Dodge, Deflect, Evade, Immune, Reflect and Resist."] = "Hides Absorb, Block, Miss, Parry, Dodge, Deflect, Evade, Immune, Reflect and Resist.",
    ["Stop the selected spell from showing in the damage text"] = "Stop the selected spell from showing in the damage text",
    ["Sort events by amount"] = "Sort events by amount",
    ["Combine damage/healings events with the same spellid into one event"] = "Combine damage/healings events with the same spellid into one event",
    ["Add number of merged events next to the damage/healing (ex '1337 x5')"] = "Add number of merged events next to the damage/healing (ex '1337 x5')",
    ["Dont merge dodges, parries, misses, and evades with damage events"] = "Dont merge dodges, parries, misses, and evades with damage events",
    ["Dont merge damage done to different targets"] = "Dont merge damage done to different targets",
    ["Dont merge damage with different spellids"] = "Dont merge damage with different spellids",
    ["Dont merge damage with different icons"] = "Dont merge damage with different icons",
    ["Dont merge damage of different types"] = "Dont merge damage of different types",
    ["Use separate type colors for damage over time"] = "Use separate type colors for damage over time",
    -- Slider labels
    ["Duration"] = "Duration",
    ["Duration Ratio"] = "Duration Ratio",
    ["Start Scale"] = "Start Scale",
    ["Mid Scale"] = "Mid Scale",
    ["End Scale"] = "End Scale",
    ["Overshoot"] = "Overshoot",
    ["Settle Ratio"] = "Settle Ratio",
    ["Distance"] = "Distance",
    ["Font Size"] = "Font Size",
    ["Animation Duration"] = "Animation Duration",
    ["Max Simultaneous Numbers"] = "Max Simultaneous Numbers",
    ["Off-Target Size Scale"] = "Off-Target Size Scale",
    ["Off-Target Alpha"] = "Off-Target Alpha",
    ["Screen Center Text X Offset"] = "Screen Center Text X Offset",
    ["Screen Center Text Y Offset"] = "Screen Center Text Y Offset",
    ["Nameplate Text X Offset"] = "Nameplate Text X Offset",
    ["Nameplate Text Y Offset"] = "Nameplate Text Y Offset",
    ["Anti-Overlap Horizontal Spacing"] = "Anti-Overlap Horizontal Spacing",
    ["Anti-Overlap Vertical Spacing"] = "Anti-Overlap Vertical Spacing",
    ["X Offset"] = "X Offset",
    ["Y Offset"] = "Y Offset",
    ["Zoom"] = "Zoom",
    ["Aspect Ratio"] = "Aspect Ratio",
    ["Absolute Threshold"] = "Absolute Threshold",
    ["% of Max Player Health"] = "% of Max Player Health",
    ["% of Average Damage/Healing"] = "% of Average Damage/Healing",
    ["Small Crit Threshold"] = "Small Crit Threshold",
    ["Global Merge Interval"] = "Global Merge Interval",
    ["Override Merge Interval"] = "Override Merge Interval",
    -- Slider tooltips
    ["Animation duration relative to global duration"] = "Animation duration relative to global duration",
    ["Duration ratio between time spent in Start to Mid phase and time spent in Mid to End phase."] = "Duration ratio between time spent in Start to Mid phase and time spent in Mid to End phase.",
    ["Initial text scale"] = "Initial text scale",
    ["Mid point text scale"] = "Mid point text scale",
    ["Final text scale"] = "Final text scale",
    ["Extra scale added past the end scale before settling back"] = "Extra scale added past the end scale before settling back",
    ["Fraction of the second phase spent settling back to the end scale"] = "Fraction of the second phase spent settling back to the end scale",
    ["Scroll distance"] = "Scroll distance",
    ["Animation length in seconds"] = "Animation length in seconds",
    ["Maximum combat numbers visible at once. 0 = unlimited (current behavior). When the limit is reached the oldest number is removed so the newest stays visible."] = "Maximum combat numbers visible at once. 0 = unlimited (current behavior). When the limit is reached the oldest number is removed so the newest stays visible.",
    ["Size multiplier for off-target numbers"] = "Size multiplier for off-target numbers",
    ["Opacity multiplier for off-target numbers"] = "Opacity multiplier for off-target numbers",
    ["Horizontal offset of animation area"] = "Horizontal offset of animation area",
    ["Vertical offset of animation area"] = "Vertical offset of animation area",
    ["Horizontal spacing between text"] = "Horizontal spacing between text",
    ["Vertical spacing between text"] = "Vertical spacing between text",
    ["Horizontal offset of spell icon"] = "Horizontal offset of spell icon",
    ["Vertical offset of spell icon"] = "Vertical offset of spell icon",
    ["Zoom in on the icon and trim to edge to give a more square appearance"] = "Zoom in on the icon and trim to edge to give a more square appearance",
    ["Aspect ratio of spell icon"] = "Aspect ratio of spell icon",
    ["Absolute Value"] = "Absolute Value",
    ["Percentage of Max Player Health"] = "Percentage of Max Player Health",
    ["Percentage of Average Damage/Healing"] = "Percentage of Average Damage/Healing",
    ["Crits smaller than this amount lose the crit styling"] = "Crits smaller than this amount lose the crit styling",
    ["Max time interval between events for a merge to happen (in seconds)"] = "Max time interval between events for a merge to happen (in seconds)",
    ["Max time interval between chosen spell events for a merge to happen (in seconds)"] = "Max time interval between chosen spell events for a merge to happen (in seconds)",
    -- Headers
    ["Animation Status:"] = "Animation Status:",
    ["Animation Settings"] = "Animation Settings",
    ["Config Presets"] = "Config Presets",
    ["General Settings"] = "General Settings",
    ["Text Position Options"] = "Text Position Options",
    ["Attach Text To"] = "Attach Text To",
    ["Spell Icon Options"] = "Spell Icon Options",
    ["Number Formatting Options"] = "Number Formatting Options",
    ["Filtering Options"] = "Filtering Options",
    ["SpellId Blacklist"] = "SpellId Blacklist",
    ["Sorting Options"] = "Sorting Options",
    ["Merging Options"] = "Merging Options",
    ["Relative To"] = "Relative To",
    ["SpellId Override"] = "SpellId Override",
    ["Damage Type Colors"] = "Damage Type Colors",
    ["Override Type Colors for Damage Over Time"] = "Override Type Colors for Damage Over Time",
    -- Buttons
    ["New"] = "New",
    ["Copy"] = "Copy",
    ["Save"] = "Save",
    ["Load"] = "Load",
    ["Delete"] = "Delete",
    ["Rename"] = "Rename",
    ["Reset"] = "Reset",
    ["Copy From Above"] = "Copy From Above",
    ["Creates a new preset"] = "Creates a new preset",
    ["Creates a copy of the selected preset"] = "Creates a copy of the selected preset",
    ["Saves current configuration into the selected preset"] = "Saves current configuration into the selected preset",
    ["Loads the selected preset, overwriting current configuration"] = "Loads the selected preset, overwriting current configuration",
    ["Deletes the selected preset permanently"] = "Deletes the selected preset permanently",
    ["Renames the selected preset"] = "Renames the selected preset",
    ["Restores chosen spell merge interval to a common setting"] = "Restores chosen spell merge interval to a common setting",
    ["Copies color settings from the damage types above"] = "Copies color settings from the damage types above",
    -- Color option labels and tooltips
    ["Text Color"] = "Text Color",
    ["Custom text color for this event"] = "Custom text color for this event",
    ["Custom text color for this type"] = "Custom text color for this type",
    -- Dropdown labels (inert in current build) and menu item texts
    ["Direction"] = "Direction",
    ["Scroll direction"] = "Scroll direction",
    ["Font Face"] = "Font Face",
    ["Font face used"] = "Font face used",
    ["Font Style"] = "Font Style",
    ["Font style used"] = "Font style used",
    ["Animations"] = "Animations",
    ["Presets"] = "Presets",
    ["Configuration Presets"] = "Configuration Presets",
    ["Attach Mode"] = "Attach Mode",
    ["Screen Center"] = "Screen Center",
    ["Target Nameplate"] = "Target Nameplate",
    ["Every Nameplate"] = "Every Nameplate",
    ["First Event"] = "First Event",
    ["Last Event"] = "Last Event",
    ["Pow"] = "Pow",
    ["Fade In"] = "Fade In",
    ["Fade Out"] = "Fade Out",
    ["Scroll"] = "Scroll",
    ["No Outline"] = "No Outline",
    ["No Outline Monochrome"] = "No Outline Monochrome",
    ["Outline"] = "Outline",
    ["Outline Monochrome"] = "Outline Monochrome",
    ["Thick Outline"] = "Thick Outline",
    ["Thick Outline Monochrome"] = "Thick Outline Monochrome",
    ["Scroll Up"] = "Scroll Up",
    ["Scroll Down"] = "Scroll Down",
    ["Scroll Left"] = "Scroll Left",
    ["Scroll Right"] = "Scroll Right",
    ["Scroll Up & Left"] = "Scroll Up & Left",
    ["Scroll Up & Right"] = "Scroll Up & Right",
    ["Scroll Down & Left"] = "Scroll Down & Left",
    ["Scroll Down & Right"] = "Scroll Down & Right",
    ["Random Direction"] = "Random Direction",
    -- Category panel headers (HEADER_TEXT values)
    ["Auto Hits"] = "Auto Hits",
    ["Auto Misses"] = "Auto Misses",
    ["Auto Crits"] = "Auto Crits",
    ["Pet Auto Hits"] = "Pet Auto Hits",
    ["Pet Auto Misses"] = "Pet Auto Misses",
    ["Pet Auto Crits"] = "Pet Auto Crits",
    ["Spell Hits"] = "Spell Hits",
    ["Spell Misses"] = "Spell Misses",
    ["Spell Crits"] = "Spell Crits",
    ["DoT Ticks"] = "DoT Ticks",
    ["DoT Miss Ticks"] = "DoT Miss Ticks",
    ["DoT Crit Ticks"] = "DoT Crit Ticks",
    ["Pet Spell Hits"] = "Pet Spell Hits",
    ["Pet Spell Misses"] = "Pet Spell Misses",
    ["Pet Spell Crits"] = "Pet Spell Crits",
    ["Pet DoT Ticks"] = "Pet DoT Ticks",
    ["Pet DoT Miss Ticks"] = "Pet DoT Miss Ticks",
    ["Pet DoT Crit Ticks"] = "Pet DoT Crit Ticks",
    ["Heals"] = "Heals",
    ["Heal Misses"] = "Heal Misses",
    ["Heal Crits"] = "Heal Crits",
    ["HoT Ticks"] = "HoT Ticks",
    ["HoT Miss Ticks"] = "HoT Miss Ticks",
    ["HoT Crit Ticks"] = "HoT Crit Ticks",
    ["Pet Heals"] = "Pet Heals",
    ["Pet Heal Misses"] = "Pet Heal Misses",
    ["Pet Heal Crits"] = "Pet Heal Crits",
    ["Pet HoT Ticks"] = "Pet HoT Ticks",
    ["Pet HoT Miss Ticks"] = "Pet HoT Miss Ticks",
    ["Pet HoT Crit Ticks"] = "Pet HoT Crit Ticks",
    -- Sub-panel category names (CONFIG_LAYOUT catnames)
    ["Auto Attacks"] = "Auto Attacks",
    ["Special Attacks"] = "Special Attacks",
    ["Damage Over Time"] = "Damage Over Time",
    ["Heals Over Time"] = "Heals Over Time",
    ["Pet Auto Attacks"] = "Pet Auto Attacks",
    ["Pet Special Attacks"] = "Pet Special Attacks",
    ["Pet Damage Over Time"] = "Pet Damage Over Time",
    ["Pet Heals Over Time"] = "Pet Heals Over Time",
    -- Dialogs and preset naming
    ["Preset Name"] = "Preset Name",
    ["This will overwrite your current configuration. Are you sure?"] = "This will overwrite your current configuration. Are you sure?",
    ["This will overwrite your the selected preset. Are you sure?"] = "This will overwrite your the selected preset. Are you sure?",
    ["This will delete the preset permanently. Are you sure?"] = "This will delete the preset permanently. Are you sure?",
    ["This will overwrite all color settings below."] = "This will overwrite all color settings below.",
    ["New preset"] = "New preset",
    ["Copy of %s"] = "Copy of %s",
    -- Misc UI
    ["Default: %s"] = "Default: %s",
    ["Empty: Attack a Dummy"] = "Empty: Attack a Dummy",
    ["%s |cff808080built-in|r"] = "%s |cff808080built-in|r",
    ["init"] = "init",
    -- Log / chat messages
    ["%s preset loaded."] = "%s preset loaded.",
    ["Config saved to %s preset."] = "Config saved to %s preset.",
    ["Preset %s already exists"] = "Preset %s already exists",
    ["Defaults restored."] = "Defaults restored.",
    ["Preset '%s' already exists."] = "Preset '%s' already exists.",
    ["Could not register event %s: %s"] = "Could not register event %s: %s",
    ["Combat text is unavailable on this client: the modern combat log is restricted and no public API exposes outgoing damage. Options, presets and previews still work."] = "Combat text is unavailable on this client: the modern combat log is restricted and no public API exposes outgoing damage. Options, presets and previews still work.",
})
```

## Appendix B — extraction recipe used for counts

```bash
# occurrence counts by builder (current tree)
grep -c 'CreateCheckbox(' config.lua   # etc. — see §1 counts
# enUS identity check (lua5.1):
lua5.1 /tmp/opencode/locale_draft/verify_enus.lua   # keys=242 bad=0
# fallback chain check:
lua5.1 /tmp/opencode/locale_draft/run_test.lua      # checks=15 failures=0
```

Raw bodies of the mechanical extraction are reproducible with the regexes in §3.6 item 3; the generated inventory listing in §1(a) was produced from the current `config.lua` (263 occurrences / 239 unique mechanical keys; − 10 excluded + 13 non-mechanical = 242 enUS keys).
