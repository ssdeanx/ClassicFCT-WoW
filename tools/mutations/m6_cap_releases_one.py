"""The simultaneous-number limit releases only one number per dispatch.

Lowering the limit at runtime (the options panel applies it immediately) then
leaves the screen above the new limit, worked off one number at a time.
"""
p = "main.lua"
s = open(p, encoding="utf-8").read()
old = """        while (#anim >= fctConfig.maxDisplayed) do
            local oldest = anim[#anim]
            if not oldest then break end
            oldest:Release()
            tremove(anim)
        end"""
new = """        if (#anim >= fctConfig.maxDisplayed) then
            local oldest = anim[#anim]
            if oldest then
                oldest:Release()
                tremove(anim)
            end
        end"""
assert old in s, "cap pattern not found"
s = s.replace(old, new, 1)
open(p, "w", encoding="utf-8").write(s)
