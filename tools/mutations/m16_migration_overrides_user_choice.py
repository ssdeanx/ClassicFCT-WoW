"""The migration overrides a value the user chose.

The migration must only move a value that is still one of the old DEFAULTS.
A limit the user picked themselves is their setting, not a default.
"""
p = "config.lua"
s = open(p, encoding="utf-8").read()
old = """    if (not OLD_MAX_DISPLAYED_DEFAULTS[value]) then return false end"""
new = """    -- The guard that spares a value the user chose."""
assert old in s, "migration guard not found"
s = s.replace(old, new, 1)
open(p, "w", encoding="utf-8").write(s)
