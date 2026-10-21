"""A restricted client registers the combat-log event.

On Retail/Midnight and WoW Forever, COMBAT_LOG_EVENT_UNFILTERED is
restricted: registering it is a policy violation and the client reports it.
"""
p = "main.lua"
s = open(p, encoding="utf-8").read()
old = "COMBAT_LOG_EVENT_UNFILTERED = not IsRestrictedCombat,"
new = "COMBAT_LOG_EVENT_UNFILTERED = true,"
assert old in s, "event registration pattern not found"
s = s.replace(old, new, 1)
open(p, "w", encoding="utf-8").write(s)
