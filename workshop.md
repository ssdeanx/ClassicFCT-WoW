# workshop map

Root: `/home/sam/ClassicFCT-WoW` (Path A — existing directory, local-only).

Skill family (upstream `github/awesome-copilot/skills`, loaded per use —
`workshop-create` arrived the same way):
- `workshop-create` — this scaffold.
- `desk-open` — create and resume desks (`journal.md` + `.signals/`).
- `desk-journal` — write and read journal entries.
- `bench-read` — read shared artifacts.
- `signal-write` — emit structured signals: hands-up, blocked, done,
  checkpoint, partnership.

## layout

- `desks/` — one folder per desk: `journal.md` + `.signals/`
  (see `desks/README.md`).
- `classroom/` — purpose undefined by the skill family; operator-owned
  (see `classroom/README.md`).
- `bench/` — shared files: findings, verdicts, drafts, reports
  (see `bench/README.md`).
- `hands-up.md` — marker only. Real hands-ups are `signal-write`
  escalation signals in the raising desk's `.signals/` plus a journal
  marker.
- `CAIRN.md` — operating disposition, verbatim from `workshop-create`.
- `README.md` — the addon readme (not the map; this file is).
- `AGENTS.md` — repo instructions, including the Workshop section.

## opening a desk (per `desk-open`)

1. Name it: short, descriptive, kebab-case.
2. If `desks/<name>/journal.md` exists, the desk is live — read it and
   resume, never overwrite.
3. Otherwise create `journal.md` + `.signals/` and write the first entry:
   purpose, scope, next step.

## sessions (per `desk-open`, `desk-journal`, `signal-write`)

1. Start: read the journal newest-first, check the bench.
2. Work. Emit signals for state changes that affect the room
   (escalation sorts above execution on the dashboard).
3. End: append a journal entry — done, state, next step.

## release hygiene

`desks/`, `bench/`, and `classroom/` are agent workspace, not addon code:
never reference them from any `.toc` load list, and exclude them from
release zips. Same exclusion applies to `CAIRN.md`, `workshop.md`, and
`hands-up.md`.
