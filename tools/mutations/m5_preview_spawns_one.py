"""The live example stops filling to the configured maximum.

Spawning a single number per tick is slower than the numbers expire, so the
example stabilises below the configured limit and moving the "Max Simultaneous
Numbers" slider has no visible effect.
"""
p = "main.lua"
s = open(p, encoding="utf-8").read()
old = "        local toSpawn = previewTarget - #anim"
new = "        local toSpawn = 1"
assert old in s, "preview spawn pattern not found"
s = s.replace(old, new, 1)
open(p, "w", encoding="utf-8").write(s)
