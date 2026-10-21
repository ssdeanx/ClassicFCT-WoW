"""The merge bucket key drops the event type.

A heal and a damage then share a bucket, and the heal is summed into the
damage - which is what the event type in the key exists to prevent.
"""
p = "main.lua"
s = open(p, encoding="utf-8").read()
old = 'local id = tostring(pet).."|"..tostring(event).."|"..tostring(miss).."|"..tostring(missKey or "").."|"..tostring(periodic and 1 or 0)'
new = 'local id = tostring(pet).."|"..tostring(miss).."|"..tostring(missKey or "").."|"..tostring(periodic and 1 or 0)'
assert old in s, "bucket key pattern not found"
s = s.replace(old, new, 1)
open(p, "w", encoding="utf-8").write(s)
