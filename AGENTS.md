# ClassicFCT

WoW Lua 5.1 addon for floating combat text. No build system, test runner, or CI.

## Supported clients

Maintainer intent and interface mapping. Keep this list aligned with every `.toc` `## Interface` value. Runtime flavor checks currently use `WOW_PROJECT_ID` (`IsClassic`, `IsBCC`, `IsRetail`).

| Client | Interface |
| :--- | :--- |
| Classic Era / Season of Discovery | `11509` |
| The Burning Crusade Classic Anniversary | `20506` |
| WotLK Titanforge | `38002` |
| WoW Forever | `16001` |
| Retail / Live (Midnight) | `120100` |

## Load order (every `.toc`)

`Libs\libs.xml` -> `presets.lua` -> `Presets\presets.xml` -> `config.lua` -> `main.lua`

- `presets.lua` only defines `CFCT._DefaultPresets` / `AddDefaultPreset`. `config.lua` reads `DefaultPresets["Mists of Pandaria"]` as `DefaultConfig`, so do not rename or remove that preset and keep preset files loaded before `config.lua`.
- `Libs/` is vendored (LibStub, CallbackHandler, LibSharedMedia). Do not edit.
- New presets need both a `Presets/*.lua` file calling `CFCT:AddDefaultPreset` and an entry in `Presets/presets.xml`.

## Runtime APIs and compatibility

- Cross-flavor shims already exist and should be followed instead of calling flavor-specific APIs directly: `GetSpellInfo` vs `C_Spell.GetSpellInfo`, `GetAddOnMetadata` vs `C_AddOns.GetAddOnMetadata`.
- Vanilla classic spell ids can be `0`; those are mapped to the spell name (`if (spellid == 0 and IsClassic) then spellid = spellname end`).
- UI uses retail `Settings` when `Settings.RegisterAddOnCategory` exists, otherwise `InterfaceOptionsFrame`.
- Color picker code supports both legacy and modern pickers; check `UsesNewColorPicker` / `UsesNewColorPicker` before changing that flow.
- Retail/Midnight and WoW Forever restrict or remove `COMBAT_LOG_EVENT_UNFILTERED`; those paths need the `C_CombatText` / `COMBAT_TEXT_UPDATE` pipeline instead of current CLEU parsing. Verify exact payloads/secret-value behavior in the WoW UI source before implementing.
- Modern retail damage values may be secret (`_G.issecretvalue`); guard numeric handling so restricted events are skipped instead of causing arithmetic/comparison errors.

## WoW API verification

Use `/home/sam/wow-ui-source` rather than guesses. It tracks one branch per client:
`classic_era`, `classic_anniversary`, `classic_titan`, `origin/forever`, `live`.

```bash
git -C /home/sam/wow-ui-source show <branch>:Interface/AddOns/...
git -C /home/sam/wow-ui-source diff <branch-a>..<branch-b> -- Interface/AddOns/
```
Read `SKILL.md` in that repo for the branch/version/API matrix and API restrictions. Before relying on branch-specific APIs, check that branch's `Blizzard_APIDocumentationGenerated` files.

## Key architecture

- `CFCT` is the addon table and is published as `_G[addonName]`.
- `main.lua`: registers `COMBAT_LOG_EVENT_UNFILTERED`, `ADDON_LOADED`, `PLAYER_LOGOUT`, `PLAYER_ENTERING_WORLD`, `NAME_PLATE_UNIT_ADDED`, `NAME_PLATE_UNIT_REMOVED`, `UNIT_MAXHEALTH`; drives animation/cache processing from `OnUpdate`; handles CLEU via `DamageEvent` / `MissEvent` / `HealingEvent` -> `CacheEvent`.
- `config.lua`: persistence (`CFCT.Config:OnLoad` / `OnSave`), defaults/migration, widget builders, slash-command entry (`/cfct`).
- Test/debug helpers: `CFCT._testMode`, `CFCT:Test(n)`, `CFCT:Log`, `CFCT:DumpLog`.

## Persistence

Account-level SavedVariables: `ClassicFCTConfig`, `ClassicFCTVars`, `ClassicFCTTables`, `ClassicFCTCustomPresets`.
Character-level: `ClassicFCTCharConfig`, `ClassicFCTCharVars`, `ClassicFCTCharTables`.
`characterSpecificConfig` selects active set. Save occurs on `PLAYER_LOGOUT`.

## "More numbers at once"

- `Config.maxDisplayed` (UI: "Max Simultaneous Numbers") caps visible numbers; `0` means unlimited and values up to 200 are supported. When the cap is reached, the oldest number is removed so the newest stays visible.
- Density can also be increased by reducing `preventOverlapSpacingX` / `preventOverlapSpacingY`, which control the anti-overlap layout grid.
- Adapted collision behavior from ClassicNumbers can be evaluated for tighter packing, but preserve `recycleFontString` / init-field parity if adding per-frame collision state.

## Conventions and gotchas

- Lua 5.1 only; `.luarc.json` disables `io`, `os`, `package`, `debug`, and `utf8`. Do not use them.
- New WoW API globals used in code should also be added to `.luarc.json` and `.vscode/settings.json` globals lists for LuaLS cleanliness.
- LuaLS WoW annotations come from `~/.vscode/extensions/ketho.wow-api-...`, a machine-specific path.
- Miss filters and merging depend on spell ids; preserve classic `spellid == 0 -> spellname` handling.
- The changelog string inside `ADDON_LOADED` in `main.lua` and `## Version` in every `.toc` are version metadata; update both when cutting a release. For this repo's multi-client shipping, compare against the supported-client table above before editing interface versions.