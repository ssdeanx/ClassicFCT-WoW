"""The periodic flag is ignored.

A damage over time is then filed under the plain spell category instead of
the tick category, and the tick-specific styling and filters never apply.
"""
p = "main.lua"
s = open(p, encoding="utf-8").read()
old = 'local periodic = (cleuEvent:find("SPELL_PERIODIC", 1, true) ~= nil)'
new = 'local periodic = false'
assert s.count(old) == 3, f"expected 3 periodic sites, found {s.count(old)}"
s = s.replace(old, new)
open(p, "w", encoding="utf-8").write(s)
