"""The version-gated migration is removed.

A profile that still holds one of the old defaults keeps it, so the new
default of 20 never reaches the users who already have the addon.
"""
p = "config.lua"
s = open(p, encoding="utf-8").read()
old = """            if MigrateMaxDisplayed(self) then"""
new = """            if false and MigrateMaxDisplayed(self) then"""
assert old in s, "migration call not found"
s = s.replace(old, new, 1)
open(p, "w", encoding="utf-8").write(s)
