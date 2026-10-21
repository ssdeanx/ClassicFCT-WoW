"""The crit-flag normalisation is removed.

Lua treats the NUMBER 0 as true, so a client that delivered 0/1 would make
every hit read as a crit. The normalisation is what prevents that.
"""
p = "main.lua"
s = open(p, encoding="utf-8").read()
old = "    crit = IsCritFlag(crit)\n"
assert s.count(old) == 2, f"expected 2 normalisation sites, found {s.count(old)}"
s = s.replace(old, "")
open(p, "w", encoding="utf-8").write(s)
