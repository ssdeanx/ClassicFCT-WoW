# ClassicFCT

WoW Lua 5.1 addon for floating combat text. No build system, test runner, or CI.

## Supported clients

Maintainer intent and interface mapping. Keep this list aligned with every `.toc` `## Interface` value (`ClassicFCT-Vanilla/TBC/Titan/Forever/Mainline.toc`; the Titan and Forever files were renamed from Wrath and Mists, and the Cata `.toc` was dropped). Runtime flavor checks live in `main.lua` / `config.lua` and use `WOW_PROJECT_ID` with numeric fallbacks: `IsClassic` (2), `IsBCC` (5), `IsRetail` (1), `IsTitan` (`WOW_PROJECT_WRATH_CLASSIC` or 11), `IsWoWForever` (`WOW_PROJECT_CAMELOT` = 18, or interface `16001`). WoW Forever is a Camelot project, not Mists.

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
- `IsRestrictedCombat = IsRetail or IsWoWForever`. On those clients `COMBAT_LOG_EVENT_UNFILTERED` is restricted (`HasRestrictions=true`) and no public API exposes outgoing damage for arbitrary targets: `C_CombatText` only covers the active unit's (player/vehicle) incoming damage/heals, with secret returns and no source/dest GUID or spell id. Do not try to rebuild CLEU parsing from it.
- Restricted-client behavior: CLEU is never registered or handled (`events` table plus early-return guard), `ADDON_LOADED` logs a one-time notice, `checkCvars` is skipped, and config.lua computes the same `IsRestrictedCombat` flag to hide both "Hide Blizzard Damage/Healing" checkboxes and short-circuit their OnClick handlers on those clients, so Blizzard's combat text cannot be suppressed there (on top of the existing CVar-availability hide). Options, presets and previews still work.
- Secret values: `IsSecretValue` in `main.lua` returns false when `_G.issecretvalue` is absent and fails closed: every operation on the probe result stays inside the pcall, and if the probe cannot be reduced to a plain boolean it returns true (treat as secret). Guards run at CLEU entry (event, source/dest GUID, flags), per branch before the `spellid == 0 and IsClassic` conversion (spellid/amount/school/crit/misstype), in `DamageEvent` / `MissEvent` / `HealingEvent`, and in `CacheEvent`; restricted events are skipped, never formatted.

## WoW API verification

Use `/home/sam/wow-ui-source` rather than guesses. It tracks one branch per client:
`classic_era`, `classic_anniversary`, `classic_titan`, `origin/forever`, `live`.

```bash
git -C /home/sam/wow-ui-source show <branch>:Interface/AddOns/...
git -C /home/sam/wow-ui-source diff <branch-a>..<branch-b> -- Interface/AddOns/
```
Read `SKILL.md` in that repo for the branch/version/API matrix and API restrictions. Before relying on branch-specific APIs, check that branch's `Blizzard_APIDocumentationGenerated` files.

- Offline checks: `luac -p main.lua config.lua` and `luacheck main.lua config.lua` (errors are regressions; warnings are pre-existing).
- In-game matrix: record `/run print(WOW_PROJECT_ID, select(4, GetBuildInfo()))` on each supported client. Restricted clients should log the availability notice and show no ClassicFCT numbers; Vanilla/TBC/Titan should show normal combat text.

## Key architecture

- `CFCT` is the addon table and is published as `_G[addonName]`.
- `main.lua`: registers the `events` table (`COMBAT_LOG_EVENT_UNFILTERED`, `ADDON_LOADED`, `PLAYER_LOGOUT`, `PLAYER_ENTERING_WORLD`, `NAME_PLATE_UNIT_ADDED`, `NAME_PLATE_UNIT_REMOVED`, `UNIT_MAXHEALTH`) inside `pcall`, logging per-event failures instead of aborting; CLEU is left unregistered on restricted clients. Drives animation/cache processing from `OnUpdate`; handles CLEU via `DamageEvent` / `MissEvent` / `HealingEvent` -> `CacheEvent`.
- `config.lua`: persistence (`CFCT.Config:OnLoad` / `OnSave`), defaults/migration, widget builders, slash-command entry (`/cfct`).
- Test/debug helpers: `CFCT._testMode`, `CFCT:Test(n)` (uses `UnitGUID("target")` when there are no nameplates, reads icons from `spellinfo.spellID`, and bounds the spell lookup to 50 attempts), `CFCT:Log`, `CFCT:DumpLog`.

## Persistence

Account-level SavedVariables: `ClassicFCTConfig`, `ClassicFCTVars`, `ClassicFCTTables`, `ClassicFCTCustomPresets`.
Character-level: `ClassicFCTCharConfig`, `ClassicFCTCharVars`, `ClassicFCTCharTables`.
`characterSpecificConfig` selects active set. Save occurs on `PLAYER_LOGOUT`.

## "More numbers at once"

- `Config.maxDisplayed` (UI: "Max Simultaneous Numbers", slider 0-200) caps visible numbers; `0` is the default and means unlimited. When the cap is reached, the oldest number is removed so the newest stays visible.
- Density can also be increased by reducing `preventOverlapSpacingX` / `preventOverlapSpacingY`, which control the anti-overlap layout grid.
- ClassicNumbers' per-frame `GetCollisionOffsets` / `collisionBounce` and per-target caps (`maxHitNumbersPerTarget` / `maxCritNumbersPerTarget`) were deliberately not ported: a separation pass would fight the existing `GRID` + spiral overflow + 3-pass overlap resolution, and the caps would reduce simultaneous numbers rather than increase them. Keep the `recycleFontString` / init-field parity warning if per-frame collision state is ever added.

## Conventions and gotchas

- Lua 5.1 only; `.luarc.json` disables `io`, `os`, `package`, `debug`, and `utf8`. Do not use them.
- New WoW API globals used in code should also be added to `.luarc.json` and `.vscode/settings.json` globals lists for LuaLS cleanliness.
- LuaLS WoW annotations come from `~/.vscode/extensions/ketho.wow-api-...`, a machine-specific path.
- Miss filters and merging depend on spell ids; preserve classic `spellid == 0 -> spellname` handling.
- The changelog string inside `ADDON_LOADED` in `main.lua` and `## Version` in every `.toc` are version metadata; update both when cutting a release. For this repo's multi-client shipping, compare against the supported-client table above before editing interface versions.
- `desks/`, `bench/`, and `classroom/` are agent workspace, not addon code: never reference them from any `.toc` load list, and exclude them from release zips. Same exclusion applies to `CAIRN.md`, `workshop.md`, and `hands-up.md`.

## Workshop (desks, bench, cairn)

- This repo root is a workshop. `desks/` holds one folder per desk (parallel agent work lands in its own desk folder); `bench/` is the shared workspace for labeled handoffs between desks; `CAIRN.md` is the operating disposition every desk reads before starting.
- Agents (including parallel subagents) must read `CAIRN.md` first, then work from their own desk: read `desks/<name>/journal.md` newest-first, write `journal.md` + `.signals/` per the `desk-open` / `desk-journal` / `signal-write` skills, and leave shared findings/verdicts/drafts/reports in `bench/` per `bench-read`. Full map: `workshop.md`.