"""The swing branch reads its amount from the wrong argument.

A swing carries no spell id, so its amount is the FIRST event-specific
argument (arg12). Reading arg15 shows the swing's school as a damage number.
"""
p = "main.lua"
s = open(p, encoding="utf-8").read()
old = "local amount,_,school,_,_,_,crit,_,_,_ = arg12,arg13,arg14,arg15,arg16,arg17,arg18,arg19,arg20,arg21"
new = "local amount,_,school,_,_,_,crit,_,_,_ = arg15,arg13,arg14,arg15,arg16,arg17,arg18,arg19,arg20,arg21"
assert old in s, "swing unpack pattern not found"
s = s.replace(old, new, 1)
open(p, "w", encoding="utf-8").write(s)
