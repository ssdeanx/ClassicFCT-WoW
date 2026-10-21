"""A raising secret-value probe fails OPEN.

The pcall around the probe is the second fail-closed path: a probe that
raises must suppress the combat text, not let it through.
"""
p = "main.lua"
s = open(p, encoding="utf-8").read()
old = '''    if not ok then
        -- Fail closed exactly as before, but report the probe failure once: a broken
        -- probe suppresses every combat event, and silence would look like a
        -- configuration problem instead of a client problem.
        if not secretProbeFailed then
            secretProbeFailed = true
            if (type(CFCT.Log) == "function") then
                CFCT:Log("the secret-value probe failed, so all combat text is suppressed. This is a client problem, not a configuration one.")
            end
        end
        return true
    end'''
new = '''    if not ok then
        return false
    end'''
assert old in s, "raising-probe pattern not found"
s = s.replace(old, new, 1)
open(p, "w", encoding="utf-8").write(s)
