--[[
    BotManager.lua

    Altbot lifecycle: add, remove, forget. Maintains a per-character
    list of "known alts" — names that have been added as bots from this
    interface. Once remembered, an alt stays in the list forever until
    explicitly forgotten, so the user can quickly re-summon them.

    Backing state:
      DankWoWPlayerbotsCharDB.knownAlts = { "Alemid", "Vuulei", ... }

    Add/remove are issued as SAY-channel .playerbots commands (the same
    commands the user would type manually). We don't have a way to
    confirm success from the server; callers should watch the roster
    for the expected name to appear/disappear.
]]

local DWP = DankWoWPlayerbots
local BotManager = {}
DWP.BotManager = BotManager

-- Subscribers to notify when the known-alts list changes (UI list refresh).
local subs = {}

function BotManager:Subscribe(fn)
    table.insert(subs, fn)
end

local function Notify()
    for _, fn in ipairs(subs) do
        local ok, err = pcall(fn)
        if not ok then DWP:Debug("BotManager sub error: "..tostring(err)) end
    end
end

----------------------------------------------------------------------
-- Known alts list
----------------------------------------------------------------------

-- Returns the current list (never nil).
function BotManager:GetKnownAlts()
    if not DWP.Config or not DWP.Config.charDB then return {} end
    DWP.Config.charDB.knownAlts = DWP.Config.charDB.knownAlts or {}
    return DWP.Config.charDB.knownAlts
end

-- Test whether a name is in the list.
function BotManager:IsKnown(name)
    if not name then return false end
    for _, n in ipairs(self:GetKnownAlts()) do
        if n:lower() == name:lower() then return true end
    end
    return false
end

-- Add a name to the list if not already present. Keeps insertion order.
function BotManager:Remember(name)
    if not name or name == "" then return false end
    if self:IsKnown(name) then return false end
    local list = self:GetKnownAlts()
    table.insert(list, name)
    Notify()
    return true
end

-- Remove a name from the list entirely.
function BotManager:Forget(name)
    if not name then return false end
    local list = self:GetKnownAlts()
    for i, n in ipairs(list) do
        if n:lower() == name:lower() then
            table.remove(list, i)
            Notify()
            return true
        end
    end
    return false
end

----------------------------------------------------------------------
-- Server operations: add (summon), remove
----------------------------------------------------------------------

-- Sanitize and validate an alt name. Returns cleaned name or nil if bad.
-- Rules: letters only, 2-12 characters (WoW 3.3.5a name rules).
function BotManager:NormalizeName(name)
    if not name then return nil end
    name = name:match("^%s*(.-)%s*$")   -- trim
    if name == "" then return nil end
    if not name:match("^[A-Za-z]+$") then return nil end
    if #name < 2 or #name > 12 then return nil end
    -- Capitalize first letter (WoW convention).
    return name:sub(1,1):upper() .. name:sub(2):lower()
end

-- Summon an alt: issues `.playerbots bot add <Name>` and remembers the name.
-- Returns true on success (command sent), false if the name is invalid.
function BotManager:Summon(name)
    local clean = self:NormalizeName(name)
    if not clean then
        DWP:Print("|cffFF3838Invalid name:|r " .. tostring(name))
        return false
    end
    DWP.Comm:SendBotAdmin(".playerbots bot add " .. clean)
    self:Remember(clean)
    DWP:Print("summoning " .. clean .. "...")
    return true
end

-- Dismiss a bot: issues `.playerbots bot remove <Name>`.
-- Returns true on success.
function BotManager:Dismiss(name)
    local clean = self:NormalizeName(name)
    if not clean then
        DWP:Print("|cffFF3838Invalid name:|r " .. tostring(name))
        return false
    end
    DWP.Comm:SendBotAdmin(".playerbots bot remove " .. clean)
    DWP:Print("dismissing " .. clean .. "...")
    return true
end

-- Summon a random bot of a specific class. Issues
-- `.playerbots bot addclass <class>`. The server generates a random
-- bot of that class and summons it. We don't remember these in the
-- known-alts list since they're random, not persistent alts.
--
-- `classId` must be one of: warrior, paladin, hunter, rogue, priest,
-- deathknight, shaman, mage, warlock, druid.
local VALID_CLASSES = {
    warrior = true, paladin = true, hunter = true, rogue = true,
    priest = true, dk = true, shaman = true, mage = true,
    warlock = true, druid = true,
}

function BotManager:SummonClass(classId)
    if not classId or not VALID_CLASSES[classId] then
        DWP:Print("|cffFF3838Invalid class:|r " .. tostring(classId))
        return false
    end
    DWP.Comm:SendBotAdmin(".playerbots bot addclass " .. classId)
    DWP:Print("summoning random " .. classId .. "...")
    return true
end

----------------------------------------------------------------------
-- Status introspection (for UI display)
----------------------------------------------------------------------

-- Returns one of: "party", "online", "offline", "unknown"
-- "party"   = currently in our party/raid (roster knows about them)
-- "online"  = (future — can't detect from client alone)
-- "offline" = not in party
-- "unknown" = not in party
--
-- In practice we only distinguish "party" vs "not party" on the 3.3.5a
-- client. That's still useful.
function BotManager:GetStatus(name)
    if not name then return "unknown" end
    local bot = DWP.BotRoster:GetBot(name)
    if bot and bot.online then return "party" end
    return "offline"
end
