--[[
    Constants.lua
    Shared constants for DankWoW Playerbots. Loaded before all other files.

    This file defines the addon's global namespace and contains values that
    don't change at runtime. It deliberately avoids depending on Ace3 or any
    library so it can load at the very top of the TOC.
]]

-- Create the addon's top-level namespace. Nothing in the rest of the addon
-- touches _G directly except this single global.
DankWoWPlayerbots = DankWoWPlayerbots or {}
local DWP = DankWoWPlayerbots

-- Short internal alias for brevity in cross-file references.
DWP.SHORT = "DWP"

-- Semver of the client addon. Bump on every meaningful change.
DWP.VERSION = "0.8.1"

-- Transport mode. Kept as a constant so future versions can switch back
-- to a protocol-based approach if one is ever implemented server-side.
DWP.TRANSPORT = "chat"   -- "chat" = whisper polling; "addon" = future protocol

-- Slash command triggers. The first one is the canonical form.
DWP.SLASH_COMMANDS = { "/dwp", "/dankbots", "/dankwowbots" }

-- Role enum values from the server. Matches DankProtocol's role field.
DWP.ROLE_TANK   = "tank"
DWP.ROLE_HEAL   = "heal"
DWP.ROLE_DPS    = "dps"
DWP.ROLE_CASTER = "caster"
DWP.ROLE_AUTO   = "auto"

-- Bot command strings (what we SendChatMessage as whispers to bots).
-- Centralized here so we never typo one in multiple places.
DWP.CMD = {
    FOLLOW = "follow",
    STAY   = "stay",
    ATTACK = "attack",
    COME   = "come",
    RESET  = "reset",
    FLEE   = "flee",
    RTI    = "rti",
    RTSC   = "rtsc",
    -- Bot-admin (the .playerbots command set, not whispers):
    BOT_ADD    = ".playerbots bot add",
    BOT_REMOVE = ".playerbots bot remove",
    BOT_INIT   = ".playerbots bot init",
    BOT_LIST   = ".playerbots bot list",
}

-- Texture paths (relative to the AddOn root).
DWP.TEX = {
    LOGO_HEADER       = "Interface\\AddOns\\DankWoW_Playerbots\\Media\\Textures\\logo_header",
    LOGO_HEADER_SMALL = "Interface\\AddOns\\DankWoW_Playerbots\\Media\\Textures\\logo_header_small",
    ICON_MINIMAP      = "Interface\\AddOns\\DankWoW_Playerbots\\Media\\Textures\\icon_minimap",
    ICON_APP          = "Interface\\AddOns\\DankWoW_Playerbots\\Media\\Textures\\icon_app",
}

-- Default dimensions for the main panel. Players can resize; these are the
-- initial values on first load and the "reset position" target.
DWP.UI = {
    PANEL_WIDTH   = 380,
    PANEL_HEIGHT  = 520,
    HEADER_HEIGHT = 64,
    TILE_HEIGHT   = 132,  -- portrait area + command row
    TILE_GAP      = 6,
}
