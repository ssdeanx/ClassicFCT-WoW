"""The CLEU damage amount is read from the wrong argument.

arg15 is the amount (Blizzard: select(4,...) -> amount, overkill, school, ...).
Reading arg14 (the school) instead silently renders the wrong number.
"""
p = "main.lua"
s = open(p, encoding="utf-8").read()
old = "local spellid,spellname,school1,amount,_,_,_,_,_,crit,_,_,_ = arg12,arg13,arg14,arg15,arg16,arg17,arg18,arg19,arg20,arg21,arg22,arg23,arg24"
new = "local spellid,spellname,school1,amount,_,_,_,_,_,crit,_,_,_ = arg12,arg13,arg14,arg14,arg16,arg17,arg18,arg19,arg20,arg21,arg22,arg23,arg24"
assert old in s, "amount unpack pattern not found"
s = s.replace(old, new, 1)
open(p, "w", encoding="utf-8").write(s)
