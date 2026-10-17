local addonName, CFCT = ...
local L = CFCT.L
CFCT._DefaultPresets = {}
function CFCT:GetDefaultPresets()
    return self._DefaultPresets
end
function CFCT:AddDefaultPreset(name, config)
    if self._DefaultPresets[name] == nil then
        self._DefaultPresets[name] = config
    else
        -- config.lua (which defines CFCT:Log) loads after this file; fall back to a raw
        -- diagnostic so a duplicate built-in name is never silent.
        if (type(CFCT.Log) == 'function') then
            CFCT:Log(L("Preset '%s' already exists.", name))
        else
            print("ClassicFCT: preset '"..tostring(name).."' already exists.")
        end
    end
end
