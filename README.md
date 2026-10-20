[![](http://img.youtube.com/vi/gNMEFNtfaEQ/0.jpg)](http://www.youtube.com/watch?v=gNMEFNtfaEQ "Youtube link")
# ClassicFCT [![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/Y8Y66XZTG)

Highly customizable "Floating Combat Text" for World of Warcraft Classic clients, with the text
anti-overlap behaviour of the original game: numbers are styled per event category, animated, and
laid out so that heavy combat stays readable.

Use `/cfct` to open the options interface.

## Screenshots

> **Placeholders - these image files do not exist yet.** The paths below mark where the
> screenshots belong. The images still have to be captured and added under `docs/screenshots/`
> before the project is published.

![Options panel](docs/screenshots/options-panel.png)
![Combat text in action](docs/screenshots/combat-text.png)
![Preset comparison](docs/screenshots/preset-comparison.png)

## Supported clients

| Client | Interface | Combat text |
| :--- | :--- | :--- |
| Classic Era / Season of Discovery | `11509` | Yes |
| The Burning Crusade Classic Anniversary | `20506` | Yes |
| WotLK Titanforge | `38002` | Yes |
| WoW Forever | `16001` | No - options only |
| Retail / Live (Midnight) | `120100` | No - options only |

On Retail and WoW Forever the modern combat log is restricted and no public API exposes outgoing
damage, so ClassicFCT cannot show numbers there. The addon still loads on those clients: options,
presets and previews work, and a one-time chat notice explains the missing text. Blizzard's own
floating combat text is left untouched on those clients - the "Hide Blizzard Damage/Healing"
options are not offered and no CVars are written.

## Features

### Text display
- **Attach modes:** screen center (with X/Y offsets), target nameplate, or every nameplate.
- **Attachment fallback:** when a nameplate is not available, text temporarily attaches to the
  screen center instead of disappearing.
- **Anti-overlap layout:** a hand-authored grid with a square-spiral overflow fallback, separate
  horizontal/vertical spacing sliders, and a three-pass overlap resolve for text that grows while
  animating. Can be switched off.
- **Nameplate interaction:** optional "Nameplates In Front" and "Inherit From Nameplates"
  (visibility and scale) behaviour.
- **Max Simultaneous Numbers:** slider from 0 to 200, where `0` means unlimited. When the limit is
  reached, the oldest number is removed so the newest stays visible.
- **Off-target dimming:** size and alpha multipliers for numbers from units other than your current
  target. With no target selected, nothing is dimmed.

### Styling
- 30 styling categories in 10 groups - auto attacks, special attacks, damage over time, heals,
  heals over time, and the same four groups for your pet - each with hit, crit and miss variants.
- Per category: enable/disable, font face, font style, font size, colour, spell icon and animation
  set.
- Colours by damage school, with a separate colour table for damage-over-time ticks.
- Four animations per category: **Pow** (scale pop, with optional Overshoot and Settle Ratio),
  **Fade In**, **Fade Out** and **Scroll** (eight directions plus random).
- Spell icons with offset, zoom and aspect-ratio options.
- Small-crit demotion: crits below a threshold can be shown with the normal (non-crit) styling.

### Filtering, sorting and merging
- Hide numbers below an absolute value, below a percentage of your maximum health, or below a
  percentage of your recent damage/healing average.
- Hide misses (absorb, block, miss, parry, dodge, deflect, evade, immune, reflect, resist), and
  blacklist individual spell IDs.
- Sort by damage/healing in descending order.
- Merge events into a single number with an optional counter (`1337 x5`), a configurable interval,
  per-spell interval overrides, and separation by target, spell ID, icon, damage type or miss.
- Abbreviate large numbers (`1K`) or add thousands separators (`100,000,000`).

### Presets and configuration
- Three built-in presets: **Classic**, **Mists of Pandaria** and **Classic Plus** (see below).
- Create, copy, rename, save, load and delete your own presets. Built-in presets cannot be
  overwritten, renamed or deleted.
- Account-wide settings, or per-character settings with a single checkbox.
- The options panel previews numbers while it is open, so styling changes are visible immediately
  (including on clients where combat text itself is unavailable).

## Presets

| Preset | Behaviour |
| :--- | :--- |
| Classic | Original-client behaviour: numbers fade in and scroll up, crits scale up into place, no event merging and no limit on simultaneous numbers. |
| Mists of Pandaria | The same layout with a punchier crit: crits start large and shrink into place over a short animation. |
| Classic Plus | Classic defaults tuned for busier fights: 60 simultaneous numbers, sorted by amount, with event merging and merge counters enabled. |

Loading a preset overwrites the current configuration, so save your own preset first if you want to
keep it. Custom presets are stored in the `ClassicFCTCustomPresets` SavedVariables.

## Installation

1. Install through your addon manager, or extract the release into your client's
   `Interface/AddOns/` folder. The addon folder must be named `ClassicFCT`.
2. The package ships one `.toc` per supported client (see the table above).

## Usage

- `/cfct` - open the options interface.

Settings are saved when you log out: `ClassicFCTConfig`, `ClassicFCTVars`, `ClassicFCTTables` and
`ClassicFCTCustomPresets` are account-wide, while `ClassicFCTCharConfig`, `ClassicFCTCharVars` and
`ClassicFCTCharTables` are per character.

## Localization

The interface is translated through an in-house locale table system:

- `Locales/enUS.lua` is the source of truth - keys are the English strings themselves.
- A missing key falls back to English; a locale with no table falls back to English entirely.
- Shipped locales: German (`deDE`), Russian (`ruRU`), French (`frFR`), Spanish (`esES`/`esMX`),
  Italian (`itIT`), Portuguese (`ptBR`), Chinese (`zhCN`/`zhTW`) and Korean (`koKR`).

The current translations are machine-assisted and marked "native review recommended" in their
headers, so corrections from native speakers are welcome. Combat text itself (numbers and miss
text) is never translated.

## Known limitations

- Combat text does not exist on Retail/Midnight or WoW Forever (see "Supported clients").
- Client behaviour is only confirmed in game - offline checks cannot cover the client API. When
  reporting a client-specific problem, include the output of
  `/run print(WOW_PROJECT_ID, select(4, GetBuildInfo()))`.

## License

ClassicFCT is licensed under the **GNU General Public License v3.0 only** (`GPL-3.0-only`).
The full license text is in [`LICENSE`](LICENSE).

The addon redistributes three vendored libraries under `Libs/`, each under its own terms:

- **LibStub** - public domain.
- **LibSharedMedia-3.0** - **LGPL v2.1**. The full text is in
  [`LICENSE-LGPL-2.1.txt`](LICENSE-LGPL-2.1.txt). The vendored copy is unmodified and the
  library is replaceable, so a modified LGPL v2.1 version can be substituted without affecting
  this addon's own GPL v3 code.
- **CallbackHandler-1.0** - **its license is not confirmed yet.** The vendored file carries no
  license header, so the exact terms are still being checked against the upstream project. This
  is an open compliance item, not a claim that the library is unlicensed.

[`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md) has the full third-party detail, including
the upstream sources.

## Credits and links

- Author: `Discord @tehypno` (addon metadata).
- Contributor credits are listed per release in `CHANGELOG.txt`.
- Project page: [ClassicFCT on CurseForge](https://www.curseforge.com/wow/classic/addons/classicfct)
  - *placeholder link - the CurseForge project page is not published yet.*
- Issues / support: [github.com/ssdeanx/ClassicFCT-WoW/issues](https://github.com/ssdeanx/ClassicFCT-WoW/issues).
- Source: [github.com/ssdeanx/ClassicFCT-WoW](https://github.com/ssdeanx/ClassicFCT-WoW).
- [ClassicFCT on YouTube](http://www.youtube.com/watch?v=gNMEFNtfaEQ) - feature overview.
- Support development: [ko-fi](https://ko-fi.com/Y8Y66XZTG).
- License: GPL-3.0-only - see [License](#license).
