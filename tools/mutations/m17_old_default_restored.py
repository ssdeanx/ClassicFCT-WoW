"""The default is put back to "unlimited".

The live example then fills the screen with numbers, which makes the options
panel impossible to read.
"""
p = "Presets/MoP.lua"
s = open(p, encoding="utf-8").read()
old = "maxDisplayed = 20,"
new = "maxDisplayed = 0,"
assert old in s, "preset default not found"
s = s.replace(old, new, 1)
open(p, "w", encoding="utf-8").write(s)
