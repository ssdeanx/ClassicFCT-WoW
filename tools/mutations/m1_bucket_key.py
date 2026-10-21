"""The merge bucket key loses the miss distinction.

The key is pet|event|miss|missKey|periodic. Dropping BOTH the miss flag and
the miss key lets a HIT and a MISS share a bucket, so the miss overwrites the
hit's identity and the two are dispatched as one number.
"""
p = "main.lua"
s = open(p, encoding="utf-8").read()
old = 'local id = tostring(pet).."|"..tostring(event).."|"..tostring(miss).."|"..tostring(missKey or "").."|"..tostring(periodic and 1 or 0)'
new = 'local id = tostring(pet).."|"..tostring(event).."|"..tostring(periodic and 1 or 0)'
assert old in s, "bucket key pattern not found"
s = s.replace(old, new, 1)
open(p, "w", encoding="utf-8").write(s)
