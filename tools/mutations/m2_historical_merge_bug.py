"""The historical merge bug: the bucket key loses the miss distinction AND the
merge rule reverts to the `and/or` ternary.

`merge.miss and e.miss or e.miss` always resolves to the LAST event's miss
flag, so a real hit that lands in a bucket with a miss is relabelled as a
Dodge - and the threshold filters then drop it.
"""
p = "main.lua"
s = open(p, encoding="utf-8").read()
old_key = 'local id = tostring(pet).."|"..tostring(event).."|"..tostring(miss).."|"..tostring(missKey or "").."|"..tostring(periodic and 1 or 0)'
new_key = 'local id = tostring(pet).."|"..tostring(event).."|"..tostring(periodic and 1 or 0)'
assert old_key in s, "bucket key pattern not found"
s = s.replace(old_key, new_key, 1)
old_rule = "merge.miss = merge.miss and e.miss"
new_rule = "merge.miss = merge.miss and e.miss or e.miss"
assert old_rule in s, "merge rule pattern not found"
s = s.replace(old_rule, new_rule, 1)
open(p, "w", encoding="utf-8").write(s)
