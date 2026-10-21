"""The CLEU crit flag is read from the wrong argument.

arg21 is the crit flag. Reading arg20 (glancing) instead changes the
classification of every hit.
"""
p = "main.lua"
s = open(p, encoding="utf-8").read()
old = "local spellid,spellname,school1,amount,_,_,_,_,_,crit,_,_,_ = arg12,arg13,arg14,arg15,arg16,arg17,arg18,arg19,arg20,arg21,arg22,arg23,arg24"
new = "local spellid,spellname,school1,amount,_,_,_,_,_,crit,_,_,_ = arg12,arg13,arg14,arg15,arg16,arg17,arg18,arg19,arg20,arg20,arg22,arg23,arg24"
assert old in s, "crit unpack pattern not found"
s = s.replace(old, new, 1)
open(p, "w", encoding="utf-8").write(s)
