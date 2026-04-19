--[[
    Locales/enUS.lua
    Localization table for US English. Other locales will drop in as
    separate files (deDE.lua, frFR.lua, etc.) and be TOC-gated by locale.

    Milestone 1 is structurally wired but unused — most strings are
    still inline in the UI code for rapid iteration. As text settles,
    we'll migrate to L[] lookups.

    Usage:
        local L = DWP.L
        button:SetText(L["Follow"])
]]

local DWP = DankWoWPlayerbots
DWP.L = DWP.L or {}
local L = DWP.L

-- UI labels
L["Follow"]          = "Follow"
L["Stay"]            = "Stay"
L["Attack"]          = "Attack"
L["Come"]            = "Come"
L["Reset"]           = "Reset"
L["Flee"]            = "Flee"

-- Status
L["No bots online"]  = "No playerbots active."
L["Bots online"]     = "%d bot%s online"

-- Tooltips
L["Left-click toggle"]  = "Left-click to toggle the panel"
L["Right-click menu"]   = "Right-click for options"
L["Drag reposition"]    = "Drag to reposition"

-- Commands
L["cmd help"]        = "Toggle the main panel"
L["cmd show"]        = "Show the panel"
L["cmd hide"]        = "Hide the panel"
L["cmd reset"]       = "Reset panel position"
L["cmd debug"]       = "Toggle protocol debug logging"
L["cmd version"]     = "Show version info"
