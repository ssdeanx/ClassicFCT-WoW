# hands-up

no hands-up raised yet.

A hands-up is how desks escalate: two desks disagree and can't settle it
against external facts. This is the system working, not failing.

## how one is raised (per `signal-write` — not in this file)

A hands-up is a JSON signal in the raising desk's `.signals/` folder
(`signal_type: "escalation"`, `subtype: "hands-up"`) plus a
`[signal:hands-up]` marker in that desk's journal. This file exists as
the workshop marker; the signal itself lives with the desk that raised it.
