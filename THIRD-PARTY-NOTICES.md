# Third-party notices — ClassicFCT

ClassicFCT is licensed under the **GNU General Public License v3** (see `LICENSE`). It
redistributes the following third-party libraries under `Libs/`. Their terms are separate
from the GPL and apply to those files only.

| Library | Version | Upstream author | License | Status |
| :--- | :--- | :--- | :--- | :--- |
| LibStub | 2.x | Kaelten, Cladhaire, ckknight, Mikk, Ammo, Nevcairiel, joshborke | Public domain | Verified — stated in the vendored file header |
| CallbackHandler-1.0 | 1.0 (rev 7) | Nevcairiel | See "CallbackHandler-1.0" below | **Unverified — see note** |
| LibSharedMedia-3.0 | 8020003 | Elkano | LGPL v2.1 | Verified — stated in the vendored file header |

## LibStub

> LibStub is hereby placed in the Public Domain
> Credits: Kaelten, Cladhaire, ckknight, Mikk, Ammo, Nevcairiel, joshborke

Source: `Libs/LibStub/LibStub.lua` (header, lines 1–3).

## LibSharedMedia-3.0

> Name: LibSharedMedia-3.0
> Author: Elkano (elkano@gmx.de)
> Inspired By: SurfaceLib by Haste/Otravi (troeks@gmail.com)
> Website: http://www.wowace.com/projects/libsharedmedia-3-0/
> Description: Shared handling of media data (fonts, sounds, textures, ...)
>              between addons.
> Dependencies: LibStub, CallbackHandler-1.0
> License: LGPL v2.1

Source: `Libs/LibSharedMedia-3.0/LibSharedMedia-3.0.lua` (header, lines 1–9).

The full LGPL v2.1 text is reproduced in `LICENSE-LGPL-2.1.txt`.

### LGPL v2.1 compliance note

`LibSharedMedia-3.0` is LGPL v2.1. LGPL v2.1 section 3 permits a distributor to
"opt in" to the ordinary GNU General Public License by altering the notices that
refer to the LGPL. This distribution keeps the library under its own LGPL v2.1
terms and adds the compatibility permission, so the combined distribution
remains distributable under GPL v3 with the library's own terms preserved.

`LibSharedMedia` is a *library* in the LGPL sense (it provides shared media
registries consumed by addons via `LibStub`/`CallbackHandler`, not linked
object code), and the addon does not modify it — the vendored copy is
byte-identical to upstream. A recipient can therefore replace it with a
modified LGPL v2.1 version of the library without affecting this addon's own
GPL v3 code.

## CallbackHandler-1.0 — license not verifiable from the vendored copy

The vendored file `Libs/CallbackHandler-1.0/CallbackHandler-1.0.lua` **carries no
license header, copyright line, or license text**. Its first line is an RCS
identifier:

```
--[[ $Id: CallbackHandler-1.0.lua 1186 2018-07-21 14:19:18Z nevcairiel $ ]]
```

Upstream is the WowAce project `callbackhandler` by Nevcairiel. The upstream
project page and the CurseForge license page for this library did not expose a
specific license text when checked for this release (the CurseForge page renders
an unfilled BSD-style template with `<YEAR>` / `<OWNER>` placeholders, and the
WowAce project page carries no license block).

What is verifiable:

- The library is redistributed here **unmodified** — the vendored file is a
  verbatim copy of upstream revision 1186.
- It is widely vendored by major addon projects (e.g. BigWigs, ElvUI), which
  carry their own separate licenses over it.

What is **not** established: the exact SPDX license identifier and copyright
line for this library.

**Action required before publication:** obtain the upstream license terms
directly from the WowAce project owner (or the library's repository) and record
them here, then add the matching license text to the distribution. This is an
open compliance item, tracked as **RR-01a** in
`bench/findings-release-readiness.md`.

## Modifications to vendored libraries

None. Every file under `Libs/` is a verbatim upstream copy. The addon does not
patch, wrap, or monkey-patch any vendored library.
