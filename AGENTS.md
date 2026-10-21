# ClassicFCT

WoW Lua 5.1 addon for floating combat text. No build system, test runner, or CI.

## Supported clients

Maintainer intent and interface mapping. Keep this list aligned with every `.toc` `## Interface` value (`ClassicFCT-Vanilla/TBC/Titan/Forever/Mainline.toc`; the Titan and Forever files were renamed from Wrath and Mists, and the Cata `.toc` was dropped). Runtime flavor checks live in `main.lua` / `config.lua` and use `WOW_PROJECT_ID` with numeric fallbacks: `IsClassic` (2), `IsBCC` (5), `IsRetail` (1), `IsTitan` (`WOW_PROJECT_WRATH_CLASSIC` or 11), `IsWoWForever` (`WOW_PROJECT_CAMELOT` = 18, or interface `16001`). WoW Forever is a Camelot project, not Mists.

| Client | Interface | `## AllowLoadGameType:` |
| :--- | :--- | :--- |
| Classic Era / Season of Discovery | `11509` | `vanilla` |
| The Burning Crusade Classic Anniversary | `20506` | `tbc` |
| WotLK Titanforge | `38002` | `wrath` |
| WoW Forever | `16001` | `camelot` |
| Retail / Live (Midnight) | `120100` | *(none - see below)* |

The four classic-family `.toc` files carry the game type of the client they target. The token is
Blizzard's own game-type vocabulary, verified against the client mirror: `vanilla`, `tbc`, `wrath`
and `camelot` are the game types whose own constants files define `WOW_PROJECT_ID` 2, 5, 11 and 18
respectively - the same project IDs the flavour checks above use. The game type is an *additional*
constraint on top of the exact `## Interface` match, so it can only ever exclude a client that was
never a candidate.

The retail `.toc` deliberately carries **no** game type: the retail client is realm-dependent and
ships both a default (`mainline`) and a `mists` game type, so a single token would stop the addon
from loading for players on a Mists realm, who load it today. A missing token is safe; a wrong one
is not.

## Load order (every `.toc`)

`Libs\libs.xml` -> `Locales\locales.xml` -> `presets.lua` -> `Presets\presets.xml` -> `config.lua` -> `main.lua`

- `presets.lua` only defines `CFCT._DefaultPresets` / `AddDefaultPreset`. `config.lua` reads `DefaultPresets["Mists of Pandaria"]` as `DefaultConfig`, so do not rename or remove that preset and keep preset files loaded before `config.lua`.
- `Libs/` is vendored (LibStub, CallbackHandler, LibSharedMedia). Do not edit.
- New presets need both a `Presets/*.lua` file calling `CFCT:AddDefaultPreset` and an entry in `Presets/presets.xml`.
- `Locales\locales.xml` MUST load before `presets.lua`: `presets.lua` reads `CFCT.L` at file scope, and `CFCT.L` is defined in `Locales/locales.lua`. Dropping the locale step from a `.toc` makes `local L = CFCT.L` bind `nil` and breaks every `L()` call in the addon.

## Locale system

- `Locales/locales.lua` is the registry. It defines `CFCT:RegisterLocale`, resolves the client's locale from `GetLocale()`, and defines `CFCT.L(key, ...)`.
- `Locales/locales.xml` is the load list: the registry first, then `enUS.lua`, then the ten translation tables.
- There are 11 locale tables: `enUS` plus `deDE`, `ruRU`, `frFR`, `esES`, `esMX`, `itIT`, `ptBR`, `zhCN`, `zhTW`, `koKR`.
- The key IS the English source string. `Locales/enUS.lua` is the identity table - every value equals its key - so a translation can never drift away from its own source string.
- Fallback chain: a missing key falls back to the `enUS` table; a key missing everywhere falls back to the key itself (which is already the English string); a client locale with no table falls back to `enUS` entirely. `CFCT.L` never returns `nil` and never throws (a bad format argument is swallowed and logged once per key).
- `enUS` is loaded unconditionally and first, ahead of every translation, so the fallback table always exists.
- `presets.lua`, `config.lua` and `main.lua` each bind `local L = CFCT.L` at file scope, so `Locales\locales.xml` has to be loaded before them.
- The non-English tables are machine-assisted and carry a "native review recommended" marker in their headers.

## Runtime APIs and compatibility

- Cross-flavor shims already exist and should be followed instead of calling flavor-specific APIs directly: `GetSpellInfo` vs `C_Spell.GetSpellInfo`, `GetAddOnMetadata` vs `C_AddOns.GetAddOnMetadata`.
- On the legacy clients (Classic Era, TBC Anniversary, WotLK Titanforge) a spell id can be `0`; those are mapped to the spell NAME (`if (spellid == 0 and IsLegacyClient) then spellid = spellname end`). The name is the runtime key, so the spell blacklist and the per-spell merge interval are keyed by it too; the numeric id is carried alongside so a numeric blacklist entry still matches.
- UI uses retail `Settings` when `Settings.RegisterAddOnCategory` exists, otherwise `InterfaceOptionsFrame`.
- Color picker code supports both legacy and modern pickers; check `UsesNewColorPicker` / `UsesNewColorPicker` before changing that flow.
- `IsRestrictedCombat = IsRetail or IsWoWForever`. On those clients `COMBAT_LOG_EVENT_UNFILTERED` is restricted (`HasRestrictions=true`) and no public API exposes outgoing damage for arbitrary targets: `C_CombatText` only covers the active unit's (player/vehicle) incoming damage/heals, with secret returns and no source/dest GUID or spell id. Do not try to rebuild CLEU parsing from it.
- Restricted-client behavior: CLEU is never registered or handled (`events` table plus early-return guard), `ADDON_LOADED` logs a one-time notice, `checkCvars` is skipped, and config.lua computes the same `IsRestrictedCombat` flag to hide both "Hide Blizzard Damage/Healing" checkboxes and short-circuit their OnClick handlers on those clients, so Blizzard's combat text cannot be suppressed there (on top of the existing CVar-availability hide). Options, presets and previews still work.
- Secret values: `IsSecretValue` in `main.lua` resolves `_G.issecretvalue` **lazily on every call** (the client may export it after this file loads) and **fails closed in both probe-failure modes**: if the probe is absent, or if the probe raises, the value is treated as secret and the event is skipped, never formatted. Both modes report themselves exactly once via `CFCT:Log`. Every operation on the probe result stays inside the pcall, so a restricted boolean can never escape into a caller's `if`. Guards run at CLEU entry (event, source/dest GUID, flags), per branch before the `spellid == 0 and IsLegacyClient` conversion (spellid/amount/school/crit/misstype), in `DamageEvent` / `MissEvent` / `HealingEvent`, and in `CacheEvent`; restricted events are skipped, never formatted. The `spellid = spellname` remap happens before the handler guard, and the handler guard re-tests the remapped value, so a substituted name is covered too.

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

### Reaching the API mirror from a read-only desk

`/home/sam/wow-ui-source` is OUTSIDE the workspace, and the `read` and `grep` tools reject it as an external directory ("permission denied: external_directory"). That restriction is tool-specific, not filesystem-specific: **`ast_grep_search` reads outside the workspace successfully.** A read-only desk (`hunter`, `paladin`, `proctor`, `janitor`, `documenter`) with no shell can therefore still verify API availability against the mirror - do not conclude "unverifiable" without trying ast-grep first.

```bash
ast_grep_search(pattern="<pattern>", lang="lua", paths=["/home/sam/wow-ui-source/..."])
```

**The pattern must be a COMPLETE AST node.** This is the single most important rule, and it is not obvious: a pattern that looks like it should work can silently match nothing.

- `local $F = $G` - WORKS. Matches any local assignment.
- `$F = $G` - WORKS. Matches any assignment, including table-constructor fields.
- `local $F = $G.$H` - WORKS. Matches a local bound to a field access.
- `Name = "GetSpellInfo"` - **DOES NOT WORK.** Inside a table constructor, `Name = "..."` is a *field*, not a standalone node, so it is never a match. Use `$F = $G` instead, or anchor the pattern to a node that IS complete (`local $X = Enum.CombatLogObject.TypeGuardian`).

Verified working examples against the mirror:

- `CombatLogGetCurrentEventInfo = $X` (lua) -> exactly 1 hit, `Blizzard_DeprecatedCombatLog/Deprecated_CombatLog.lua:18`, i.e. the legacy global is defined ONLY by the CVar-gated deprecation shim.
- `$F = Enum.CombatLogObject.$G` (lua) over `Blizzard_CombatLog/Classic/` -> 19 hits, lines 233-253, showing Blizzard resolves the `COMBATLOG_OBJECT_*` constants from `Enum` as LOCALS - it no longer relies on the globals.

Limits worth knowing before you plan around it:

- **`lang` must be a language ast-grep parses.** `.lua` works. `.toc` and `.xml` are NOT in ast-grep's language list, so `.toc` metadata (`## Interface`, `## AllowLoadGameType`) and `.xml` load lists are NOT reachable this way - use `git -C ... show <branch>:<path>` for those, which needs a shell.
- **ast-grep reads the FILESYSTEM, not git history.** The mirror has ONE branch checked out at a time (`classic_era` at the time of writing), so ast-grep sees that branch's content ONLY. Per-branch verification of the other four clients needs `git -C /home/sam/wow-ui-source show <branch>:<path>`, which needs a shell. A desk without a shell must say so explicitly rather than reporting the checked-out branch's answer for all five clients.
- **The generated API-doc files are one huge table constructor**, so a table-field pattern will not match them. Anchor on a complete node instead (e.g. `local $X = ...`), or use `git show` + `grep` for those files.
- ast-grep matches by AST, so a plain-text search for a string inside a `.lua` file may not match the way `grep` would. It is strongest for "where is this identifier assigned/declared" questions, which is the common API-availability question.
- **A no-match result means "no match under this pattern", NOT "the API does not exist".** Before concluding an API is absent, re-check the pattern against a file you know contains the construct, and corroborate with a second pattern or the generated API docs. A pattern that silently matches nothing is the most likely cause of a wrong conclusion.

### The two ast-grep tools

| tool | purpose | writes? |
| :--- | :--- | :--- |
| `ast_grep_search` | find AST-matching code; supports `pattern`, `lang`, `paths`, `globs`, `context` | no |
| `ast_grep_replace` | rewrite matched code; supports `pattern`, `rewrite`, `lang`, `paths`, `globs`, `dryRun` | **see below** |

Useful details, all verified:

- `paths` accepts a file OR a directory and is **recursive by default** - a directory path already covers subdirectories. A `**` glob inside `paths` does NOT work the way a shell glob does; use the separate `globs` parameter (`["**/*.lua"]`) to filter by filename.
- `lang` selects the parser and also filters which files are scanned, so a `.lua` pattern does not match `.txt` files.
- `$$$ARGS` captures a variadic argument list; `$F`/`$G` capture single nodes; `$F` on the `rewrite` side refers back to the captured node.
- `dryRun` defaults to `true` for `ast_grep_replace`, which is what you want for a preview.

**`ast_grep_replace` does not actually write in this environment.** It reports `[APPLIED] N replacements` and shows the before/after lines, but the file on disk is unchanged - verified twice on a scratch file and once on `main.lua` (the sentinel text never appeared; mtime and size were identical). Treat its output as a **preview**: use it to see what a rewrite WOULD do, then apply the change with the `edit` tool and verify with `git diff`. Never rely on `[APPLIED]` as evidence that a change landed.

For the same reason it is still useful for **read-only** work: a dry run over the API mirror shows exactly which lines a proposed pattern would touch, without touching them.


## Key architecture

- `CFCT` is the addon table and is published as `_G[addonName]`.
- `main.lua`: registers the `events` table (`COMBAT_LOG_EVENT_UNFILTERED`, `ADDON_LOADED`, `PLAYER_LOGOUT`, `PLAYER_ENTERING_WORLD`, `NAME_PLATE_UNIT_ADDED`, `NAME_PLATE_UNIT_REMOVED`, `UNIT_MAXHEALTH`, `PLAYER_TARGET_CHANGED`) inside `pcall`, logging per-event failures instead of aborting; CLEU is left unregistered on restricted clients. Drives animation/cache processing from `OnUpdate`; handles CLEU via `DamageEvent` / `MissEvent` / `HealingEvent` -> `CacheEvent`.
- `PLAYER_TARGET_CHANGED` (and `PLAYER_ENTERING_WORLD`) refresh the current target GUID that the off-target dimming feature compares against.
- Off-target contract: **no target selected means nothing is dimmed** - numbers render normally. This is the decided behaviour, not an incidental nil-guard: with no target there is no off-target unit to distinguish, so every number is treated as on-target and the dimming multipliers are not applied.
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
- Miss filters and merging depend on spell ids; preserve the legacy-client `spellid == 0 -> spellname` handling (Era, TBC Anniversary, WotLK Titanforge).
- The changelog string inside `ADDON_LOADED` in `main.lua` and `## Version` in every `.toc` are version metadata; update both when cutting a release. For this repo's multi-client shipping, compare against the supported-client table above before editing interface versions.
- `desks/`, `bench/`, and `classroom/` are agent workspace, not addon code: never reference them from any `.toc` load list, and exclude them from release zips. Same exclusion applies to `CAIRN.md`, `workshop.md`, and `hands-up.md`.
- `tools/` is verification code, not addon code: it is excluded from release zips by the explicit manifest in `tools/package.sh`, and nothing in a `.toc` may reference it. `tools/` IS tracked in git, unlike `bench/`.
- **The crit flag is a boolean, and Lua's truthiness is the trap.** The client delivers `critical` as `true`/`false` (Blizzard's own parser tests it with `if critical then` on every branch). Lua treats the NUMBER `0` as *true*, so a client that delivered `0/1` would make every hit read as a crit. `IsCritFlag()` in `main.lua` normalises the value to a real boolean, and it must be called only AFTER the `IsSecretValue` guard — comparing a secret value raises, and a secret value must never be inspected. Do not remove the normalisation and do not move it above the guard.

## Options panel layout

- **A slider row is about 43 pixels tall.** The slider frame is 17px (the client's `OptionsSliderTemplate`), its value box hangs 14px BELOW the track, and its label sits ~12px ABOVE it. Two sliders stacked with a pitch under 43px put the upper one's value box over the lower one's label. Use a pitch of 46px.
- **The second column of the text-position sliders starts at x=286** (two 270px sliders plus a 16px gap). Anything placed at x=296 in that section lands on top of it. The off-target sliders used to sit there, which is why they are now in their own section at the bottom of the panel.
- **The scroll child sizes itself to its content** (`FitScrollHeight` in `config.lua`). The widgets' heights come from the client's templates, so the required height is measured from the widgets rather than hard-coded. The measurement only grows the height and never shrinks it, so a failed measurement cannot make the panel smaller.
- **A section header needs a locale key in all eleven tables.** The enUS table is the identity table; a key that exists only in enUS fails the release gate's locale checks.

## Verification (`tools/`)

- `tools/release-gate.lua` is the release gate (178 checks). Run it from the repo root: `lua5.1 tools/release-gate.lua`. It asserts, rather than merely bounds, the warning budget and the file counts, so a warning or a dropped file cannot re-enter silently. It shells out to `luacheck` and to the behaviour suite; if either tool is missing the check FAILS instead of passing silently.
- `tools/behavior-tests.lua` is the behavioural suite (71 checks) and `tools/harness.lua` is the stub client it drives. The suite covers the combat-text pipeline, the secret-value guard in all four probe modes, the merge rules, the number limit and the saved configuration, across all five supported clients. It loads the addon in the real order (`presets.lua` -> preset files -> `config.lua` -> `main.lua`) and calls `CFCT.Config:OnLoad()` before anything else: the config VALUES only exist after `OnLoad` has run, which is what the client's `ADDON_LOADED` does.
- `tools/mutation-tests.sh` proves the suite is not vacuous. Each file in `tools/mutations/` breaks one protected behaviour; the runner asserts the suite FAILS for each one. **A mutation that survives is a blind spot in the suite** — add a check, or tighten the mutation. Add a mutation with every new protected behaviour.
- `tools/.luacheckrc` lints the verification tools with their own configuration (they use `io` and `os`, which the addon sources must not). The gate asserts the tools are lint-clean too.
- The tools' harness must model the client faithfully: the combat-log API is resolved ONCE and cached, so a test must swap a *mutable payload*, never the function. The clock must be mutable from the start, because `main.lua` captures `GetTime` into a local at load time.
- **The combat-log argument layout differs per event type.** Verify any change against Blizzard's own parser (`Blizzard_CombatLog.lua` on every branch) rather than by analogy:

  | event | amount | school | crit | miss type |
  | :-- | :-- | :-- | :-- | :-- |
  | `SWING_DAMAGE` | `arg12` | `arg14` | `arg18` | — |
  | `SPELL_DAMAGE` | `arg15` | `arg14` | `arg21` | — |
  | `SPELL_HEAL` | `arg15` | `arg14` | `arg18` | — |
  | `SWING_MISSED` | `arg14` | — | — | `arg12` |
  | `SPELL_MISSED` | `arg17` | `arg14` | — | `arg15` |

  A swing carries no spell id, so its amount is the FIRST event-specific argument. Reading a spell event's argument positions for a swing (or the reverse) shows the school as a damage number.

## Workshop (desks, bench, cairn)

- This repo root is a workshop. `desks/` holds one folder per desk (parallel agent work lands in its own desk folder); `bench/` is the shared workspace for labeled handoffs between desks; `CAIRN.md` is the operating disposition every desk reads before starting.
- Agents (including parallel subagents) must read `CAIRN.md` first, then work from their own desk: read `desks/<name>/journal.md` newest-first, write `journal.md` + `.signals/` per the `desk-open` / `desk-journal` / `signal-write` skills, and leave shared findings/verdicts/drafts/reports in `bench/` per `bench-read`. Full map: `workshop.md`.