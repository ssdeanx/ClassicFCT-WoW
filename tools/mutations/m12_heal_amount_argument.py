"""The healing branch reads its amount from the wrong argument.

A heal carries its amount at arg15 (Blizzard: amount, overhealing, absorbed,
critical = select(4, ...)). Reading arg14 shows the heal's school instead.
"""
p = "main.lua"
s = open(p, encoding="utf-8").read()
old = "local spellid,spellname,school1,amount,_,_,crit = arg12,arg13,arg14,arg15,arg16,arg17,arg18"
new = "local spellid,spellname,school1,amount,_,_,crit = arg12,arg13,arg14,arg14,arg16,arg17,arg18"
assert old in s, "heal unpack pattern not found"
s = s.replace(old, new, 1)
open(p, "w", encoding="utf-8").write(s)
