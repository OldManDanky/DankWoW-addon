--[[
    BotRoster.lua (chat-fallback version)

    Scans the player's party/raid and identifies bots. Reads their live
    state (HP, mana, level, class, target, combat flag) directly from WoW's
    UnitXxx API. Strategies and gearscore come from Comm.lua via chat polls.

    A "bot" is defined as any party/raid member who:
      1. Is not you
      2. Isn't a "real" player — we use the simple heuristic that any
         party member we see is treated as a bot candidate. Most players
         who install this addon are running their own alts as bots via
         mod-playerbots, so this works out.

    Events driving updates:
      - GROUP_ROSTER_UPDATE       — party/raid composition changed
      - PARTY_MEMBERS_CHANGED     — pre-3.3.5 signal for party changes
      - UNIT_HEALTH               — HP changed (fires per-unit)
      - UNIT_POWER                — mana/rage/etc changed
      - UNIT_MAXHEALTH/MAXPOWER   — max values changed (rare)
      - UNIT_TARGET               — target changed
      - UNIT_FLAGS                — combat flag might have changed
      - PLAYER_REGEN_DISABLED/ENABLED — combat entered/left

    Roster entry shape:
      {
        name,              -- bot name
        unit,              -- "party1" / "raid3" etc.
        class,             -- "WARRIOR", "MAGE", etc (file name)
        classLocalized,    -- "Warrior", "Mage", etc.
        race,
        level,
        hp, hpm,
        mp, mpm,
        powerType,         -- numeric power type from UnitPowerType
        target,
        targetHp,          -- 0-100 percentage
        combat,            -- bool
        gs, ilvl, spec,    -- from chat polls
        strategiesCombat,
        strategiesNonCombat,
        zone, master,
        lastUpdate,
        online,
      }

    Subscribers get notified of changes via Subscribe(fn). The callback
    receives (botName, changeType) where changeType is one of:
      "roster"  — bot added or removed from party
      "state"   — HP/mana/target/combat changed
      "strategies" — co/nc poll response received
      "identity"   — who poll response received
]]

local DWP = DankWoWPlayerbots
local Roster = {}
DWP.BotRoster = Roster

Roster.bots = {}

local subs = {}

function Roster:Subscribe(fn)
    table.insert(subs, fn)
end

local function Notify(botName, changeType)
    for _, fn in ipairs(subs) do
        local ok, err = pcall(fn, botName, changeType)
        if not ok then DWP:Debug("Roster sub error: "..tostring(err)) end
    end
end

----------------------------------------------------------------------
-- Party scanning
----------------------------------------------------------------------

-- Iterate current party/raid members and return a list of unit IDs
-- (skipping the player). Handles both party (max 4) and raid (max 40).
local function EnumerateUnits()
    local units = {}
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local u = "raid"..i
            if UnitExists(u) and not UnitIsUnit(u, "player") then
                table.insert(units, u)
            end
        end
    else
        local n = (GetNumPartyMembers and GetNumPartyMembers()) or 0
        for i = 1, n do
            local u = "party"..i
            if UnitExists(u) then
                table.insert(units, u)
            end
        end
    end
    return units
end

-- Read live state from a unit into the bot record. Returns true if anything
-- actually changed (to decide whether to Notify).
local function ReadUnitState(bot)
    local u = bot.unit
    if not u or not UnitExists(u) then return false end

    local changed = false
    local function setField(key, val)
        if bot[key] ~= val then bot[key] = val; changed = true end
    end

    setField("hp",       UnitHealth(u))
    setField("hpm",      UnitHealthMax(u))
    setField("mp",       UnitPower(u))
    setField("mpm",      UnitPowerMax(u))
    setField("powerType",UnitPowerType(u))
    setField("combat",   UnitAffectingCombat(u) and true or false)

    local targetUnit = u .. "target"
    if UnitExists(targetUnit) then
        setField("target", UnitName(targetUnit))
        local thp = UnitHealth(targetUnit)
        local thpm = UnitHealthMax(targetUnit)
        if thpm and thpm > 0 then
            setField("targetHp", math.floor((thp / thpm) * 100))
        else
            setField("targetHp", 0)
        end
    else
        setField("target", "")
        setField("targetHp", 0)
    end

    bot.lastUpdate = GetTime()
    return changed
end

-- Full party scan: detect joins and leaves, refresh all state.
function Roster:ScanParty()
    local units = EnumerateUnits()
    local seen = {}

    for _, u in ipairs(units) do
        local name = UnitName(u)
        if name then
            seen[name] = true

            local bot = self.bots[name]
            local isNewBot = not bot
            if isNewBot then
                bot = { name = name, online = true }
                self.bots[name] = bot
            end

            -- Static-ish data (refresh on every scan is cheap).
            bot.unit = u
            local classLocalized, classFile = UnitClass(u)
            bot.class = classFile
            bot.classLocalized = classLocalized
            bot.race = UnitRace(u)
            bot.level = UnitLevel(u)
            bot.online = true

            ReadUnitState(bot)

            if isNewBot then
                Notify(name, "roster")
                -- Convenience hooks: run whatever was configured in the options.
                if DWP.Config and DWP.Config.db and DWP.Config.db.convenience then
                    local c = DWP.Config.db.convenience
                    if c.autoOpenOnSummon and DWP.MainFrame and DWP.MainFrame.Show then
                        DWP.MainFrame:Show()
                    end
                    -- Queue the default presets to apply once we know this bot's
                    -- strategy state (after the first poll response arrives).
                    if c.defaultCombatPreset and c.defaultCombatPreset ~= "none" then
                        bot._pendingCombatPreset = c.defaultCombatPreset
                    end
                    if c.defaultNonCombatPreset and c.defaultNonCombatPreset ~= "none" then
                        bot._pendingNonCombatPreset = c.defaultNonCombatPreset
                    end
                end
            end
        end
    end

    -- Anyone in roster but not seen is no longer in the party.
    for name, bot in pairs(self.bots) do
        if bot.online and not seen[name] then
            bot.online = false
            DWP.Comm:ForgetBot(name)
            Notify(name, "roster")
        end
    end
end

-- Called for unit-specific events (UNIT_HEALTH etc.). Finds the bot
-- matching the unitID and refreshes its state.
function Roster:RefreshUnit(unitId)
    if not unitId then return end
    local name = UnitName(unitId)
    if not name then return end
    local bot = self.bots[name]
    if not bot or not bot.online then return end
    if ReadUnitState(bot) then
        Notify(name, "state")
    end
end

----------------------------------------------------------------------
-- Comm event handlers
----------------------------------------------------------------------

function Roster:OnStrategies(botName, payload)
    local bot = self.bots[botName]
    if not bot then return end

    if payload.which == "combat" then
        bot.strategiesCombat = payload.strategies
    elseif payload.which == "noncombat" then
        bot.strategiesNonCombat = payload.strategies
    else
        -- Couldn't determine which — assume combat as fallback.
        bot.strategiesCombat = payload.strategies
    end

    -- Apply any pending default-preset from the convenience settings.
    -- We do this once we know the current state so we only send the
    -- minimal diff of whispers.
    if payload.which == "combat" and bot._pendingCombatPreset then
        local presetId = bot._pendingCombatPreset
        bot._pendingCombatPreset = nil
        for _, p in ipairs(DWP.Presets.COMBAT) do
            if p.id == presetId then
                local msgs = DWP.Presets:PlanApply(p, bot.strategiesCombat, "co +", "co -")
                if #msgs > 0 then
                    DWP:Print(string.format("applying default preset '%s' to %s...", p.label, bot.name))
                    DWP.Comm:SendBotCommandBatch(bot.name, msgs, 0.2)
                end
                break
            end
        end
    end
    if payload.which == "noncombat" and bot._pendingNonCombatPreset then
        local presetId = bot._pendingNonCombatPreset
        bot._pendingNonCombatPreset = nil
        for _, p in ipairs(DWP.Presets.NONCOMBAT) do
            if p.id == presetId then
                local msgs = DWP.Presets:PlanApply(p, bot.strategiesNonCombat, "nc +", "nc -")
                if #msgs > 0 then
                    DWP:Print(string.format("applying default preset '%s' to %s...", p.label, bot.name))
                    DWP.Comm:SendBotCommandBatch(bot.name, msgs, 0.2)
                end
                break
            end
        end
    end

    Notify(botName, "strategies")
end

function Roster:OnIdentity(botName, payload)
    local bot = self.bots[botName]
    if not bot then return end

    bot.spec = payload.spec
    bot.specTalents = payload.specTalents
    bot.gs = payload.gs
    bot.ilvl = payload.ilvl
    bot.zone = payload.zone
    bot.master = payload.master
    -- race/class/level from whisper might differ from UnitXxx; don't overwrite.

    Notify(botName, "identity")
end

----------------------------------------------------------------------
-- Public helpers
----------------------------------------------------------------------

function Roster:GetBot(name)
    return self.bots[name]
end

function Roster:GetOnlineBots()
    local out = {}
    for _, b in pairs(self.bots) do
        if b.online then table.insert(out, b) end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

function Roster:Clear()
    for name, _ in pairs(self.bots) do
        DWP.Comm:ForgetBot(name)
    end
    self.bots = {}
    Notify("*", "clear")
end

----------------------------------------------------------------------
-- Ticker — drives the poll cadence in Comm.
----------------------------------------------------------------------

local tickFrame
function Roster:StartTicker()
    if tickFrame then return end
    tickFrame = CreateFrame("Frame")
    local acc = 0
    tickFrame:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + elapsed
        if acc >= 0.5 then
            acc = 0
            DWP.Comm:Tick()
        end
    end)
end
