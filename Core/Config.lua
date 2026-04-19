--[[
    Config.lua
    SavedVariables schema, defaults, and accessor helpers.

    Two SavedVariables tables:
      DankWoWPlayerbotsDB      - account-wide (panel position, global prefs)
      DankWoWPlayerbotsCharDB  - per-character (bot-specific overrides)

    We don't use AceDB-3.0 here because the schema is small and loading
    order matters (Config must work before Ace3 is fully wired). Once the
    options panel exists we'll migrate the account-wide keys to AceDB so
    the existing profile/copy/delete UI works out of the box.
]]

local DWP = DankWoWPlayerbots
local Config = {}
DWP.Config = Config

-- Default account-wide settings. Anything missing from the saved table
-- falls back to these on load.
local DEFAULTS_ACCOUNT = {
    version        = DWP.VERSION,
    panel = {
        shown      = true,
        locked     = false,
        point      = "CENTER",
        relPoint   = "CENTER",
        xOfs       = 0,
        yOfs       = 0,
        width      = DWP.UI.PANEL_WIDTH,
        height     = DWP.UI.PANEL_HEIGHT,
        scale      = 0.8,
        alpha      = 1.0,
    },
    minimap = {
        shown      = true,
        angle      = 210,        -- degrees around the minimap
    },
    audio = {
        commandSound = true,     -- play sfx on command send
        eventSound   = true,     -- play sfx on bot events (died, levelup)
    },
    polling = {
        strategiesInterval = 15,  -- seconds between co?/nc? polls per bot
        identityInterval   = 60,  -- seconds between who polls per bot
        silentPolls        = true, -- hide poll traffic from chat frames
    },
    convenience = {
        autoOpenOnSummon       = false,
        defaultCombatPreset    = "none",   -- one of: none, dps, tank, healer, nuker
        defaultNonCombatPreset = "none",   -- one of: none, follow, stay, quest, dungeon, gather, auto
    },
    debug = {
        logMessages  = false,    -- print every protocol message to chat
    },
    actionBar = {
        shown      = false,
        locked     = false,
        point      = "CENTER",
        relPoint   = "CENTER",
        xOfs       = 0,
        yOfs       = -180,
    },
}

-- Per-character defaults.
local DEFAULTS_CHAR = {
    version    = DWP.VERSION,
    bots       = {},   -- keyed by bot name: per-bot user prefs
    knownAlts  = {},   -- ordered list of alt names previously added as bots
}

-- Deep-merge defaults into target. Modifies target in-place, returns it.
-- Non-recursive for arrays; recursive for maps.
local function ApplyDefaults(target, defaults)
    if type(target) ~= "table" then target = {} end
    for k, v in pairs(defaults) do
        if type(v) == "table" then
            target[k] = ApplyDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
    return target
end

-- Called from Core.lua on ADDON_LOADED. Populates DankWoWPlayerbotsDB /
-- DankWoWPlayerbotsCharDB with defaults and exposes them via Config.db/charDB.
function Config:Initialize()
    DankWoWPlayerbotsDB     = ApplyDefaults(DankWoWPlayerbotsDB     or {}, DEFAULTS_ACCOUNT)
    DankWoWPlayerbotsCharDB = ApplyDefaults(DankWoWPlayerbotsCharDB or {}, DEFAULTS_CHAR)
    self.db     = DankWoWPlayerbotsDB
    self.charDB = DankWoWPlayerbotsCharDB
end

-- Convenience accessors for common paths. The DB is a plain table so
-- direct access works too, but these keep call sites tidy.
function Config:GetPanelPos()
    local p = self.db.panel
    return p.point, p.relPoint, p.xOfs, p.yOfs
end

function Config:SetPanelPos(point, relPoint, xOfs, yOfs)
    local p = self.db.panel
    p.point, p.relPoint, p.xOfs, p.yOfs = point, relPoint, xOfs, yOfs
end

function Config:IsPanelLocked()
    return self.db.panel.locked
end

function Config:SetPanelLocked(v)
    self.db.panel.locked = not not v
end
