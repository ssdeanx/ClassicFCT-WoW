"""The secret-value probe fails OPEN when the probe is absent.

The probe is the guard that keeps a restricted (secret) value out of the
combat text. Failing open formats restricted values onto the screen.
"""
p = "main.lua"
s = open(p, encoding="utf-8").read()
old = '''    local probe = _G.issecretvalue
    if (type(probe) ~= "function") then
        if not secretProbeFailed then
            secretProbeFailed = true
            if (type(CFCT.Log) == "function") then
                CFCT:Log("ClassicFCT: the secret-value probe is unavailable, so all combat text is suppressed. This is a client problem, not a configuration one.")
            end
        end
        return true
    end'''
new = '''    local probe = _G.issecretvalue
    if (type(probe) ~= "function") then
        return false
    end'''
assert old in s, "probe pattern not found"
s = s.replace(old, new, 1)
open(p, "w", encoding="utf-8").write(s)
