# desks

One folder per desk. A desk is a workstream with its own frame —
its own history, its own priors (per the `desk-open` skill).

## what a desk contains (per `desk-open`)

```
desks/<desk-name>/      # short, descriptive, kebab-case
  journal.md            # persistent memory — read at start, written at end
  .signals/             # structured signal output (JSON) — dashboard reads this
```

## rules (per `desk-open`, `desk-journal`)

- One desk, one focus. Scope too broad → open two desks.
- If `journal.md` already exists, the desk is live: read it and resume.
  Never overwrite it. A fresh start needs rename or archive first.
- Session start: read the journal, most recent entry first — it holds
  current state and next step.
- Session end: append an entry — what was done, current state, next step.
  3–5 lines, always with a next step. Longer context goes on the bench
  as its own artifact.
- Signal emission and journal formats: see `signal-write`, `desk-journal`.
