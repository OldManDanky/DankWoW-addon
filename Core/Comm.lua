--[[
    Comm.lua (chat-fallback version)

    Now that we've moved off the addon-message protocol, this module:
      - Periodically whispers polling commands to each known bot
      - Parses whispered responses into structured data
      - Suppresses our polling chatter from the default chat frame
      - Exposes outbound command helpers (SendBotCommand, SendBotAdmin)

    Real-time data (HP, mana, target, combat state, class, level, name) comes
    from WoW's party API in BotRoster.lua. This module handles only what
    isn't available through UnitXxx calls — strategies, gearscore, zone,
    spec — via periodic whispers.

    Poll cadence:
      - co ? + nc ?   every 5s per bot (strategy changes)
      - who           every 30s per bot (rarely-changing identity info)

    Silencing: our poll requests AND bot responses to those polls are
    filtered out of DEFAULT_CHAT_FRAME via AddMessageEventFilter, so
    players don't see the chatter. When debug mode is on, they show up
    in the addon's own log line instead.
]]

local DWP = DankWoWPlayerbots
local Comm = {}
DWP.Comm = Comm

-- Poll intervals (seconds). Defaults are used only if Config isn't loaded
-- yet; normally DWP.Config.db.polling drives these via the options panel.
-- Long intervals because mod-playerbots throttles whisper responses when
-- a bot is spammed.
local DEFAULT_STRATEGIES_INTERVAL = 15
local DEFAULT_IDENTITY_INTERVAL   = 60

local function GetStrategiesInterval()
    local c = DWP.Config and DWP.Config.db and DWP.Config.db.polling
    return (c and c.strategiesInterval) or DEFAULT_STRATEGIES_INTERVAL
end

local function GetIdentityInterval()
    local c = DWP.Config and DWP.Config.db and DWP.Config.db.polling
    return (c and c.identityInterval) or DEFAULT_IDENTITY_INTERVAL
end

-- Per-bot poll state, keyed by bot name.
local pollState = {}

-- Set of commands WE sent recently. Used to match incoming whisper responses
-- back to our polls so we can suppress them in chat and route them to the parser.
local outstandingPolls = {}
local OUTSTANDING_TTL = 10  -- seconds before giving up on a response

-- Public callback registry.
-- Events fired:
--   "strategies"    — (botName, {which = "combat"|"noncombat", strategies = {...}})
--   "identity"      — (botName, {race, gender, spec, specTalents, class, level, gs, ilvl, zone, master})
local handlers = {}

----------------------------------------------------------------------
-- Registration
----------------------------------------------------------------------

function Comm:RegisterHandler(event, fn)
    handlers[event] = handlers[event] or {}
    table.insert(handlers[event], fn)
end

local function Fire(event, ...)
    local list = handlers[event]
    if not list then return end
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, ...)
        if not ok then DWP:Debug("handler error ("..event.."): "..tostring(err)) end
    end
end

----------------------------------------------------------------------
-- Chat frame filtering
----------------------------------------------------------------------

-- Commands that, when WE whisper them, should be hidden.
local SILENT_OUT_COMMANDS = {
    ["co ?"] = true,
    ["nc ?"] = true,
    ["who"]  = true,
}

local function IsSilentOutgoing(msg)
    if not msg then return false end
    return SILENT_OUT_COMMANDS[msg] == true
end

-- Returns true if this incoming whisper is a response to a poll we recently
-- sent to the same bot. Based on timing + outstandingPolls bookkeeping.
local function IsSilentIncoming(sender)
    if not sender then return false end
    local pending = outstandingPolls[sender]
    if not pending then return false end
    local now = GetTime()
    for cmd, expire in pairs(pending) do
        if now <= expire then return true end
    end
    return false
end

-- Recently-processed messages (to prevent double-processing when the
-- filter runs multiple times per message across chat frames).
-- Keyed by "sender|msg" with timestamp value. Entries expire after 2s.
local recentlyProcessed = {}

local function AlreadyProcessed(sender, msg)
    local key = (sender or "").."|"..(msg or "")
    local now = GetTime()
    -- Clean stale entries opportunistically.
    for k, t in pairs(recentlyProcessed) do
        if now - t > 2 then recentlyProcessed[k] = nil end
    end
    if recentlyProcessed[key] then return true end
    recentlyProcessed[key] = now
    return false
end

local function IsSilentEnabled()
    local c = DWP.Config and DWP.Config.db and DWP.Config.db.polling
    if c and c.silentPolls == false then return false end
    return true  -- default true
end

-- Filter for incoming whispers from bots.
local function ChatFilter_Whisper(self, event, msg, sender, ...)
    if IsSilentIncoming(sender) then
        -- WoW runs this filter once per chat frame (7 frames = 7 calls).
        -- Only process on the first call; subsequent calls just suppress.
        if not AlreadyProcessed(sender, msg) then
            Comm:ParseWhisperResponse(sender, msg)
        end
        if IsSilentEnabled() then
            return true  -- eat it; don't show in chat
        end
        -- Otherwise let it through so the user sees their poll responses.
        return false
    end
    return false
end

-- Filter for outgoing whispers (CHAT_MSG_WHISPER_INFORM).
-- Args: (self, event, msg, recipient, ...)
local function ChatFilter_WhisperInform(self, event, msg, recipient, ...)
    if IsSilentOutgoing(msg) and IsSilentEnabled() then return true end
    return false
end

-- Register filters once. Core.lua calls this after ADDON_LOADED.
function Comm:InstallChatFilters()
    ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER", ChatFilter_Whisper)
    ChatFrame_AddMessageEventFilter("CHAT_MSG_WHISPER_INFORM", ChatFilter_WhisperInform)
end

----------------------------------------------------------------------
-- Polling
----------------------------------------------------------------------

local lastPollSlot = 0  -- round-robin index

-- Called every 0.5s from BotRoster's ticker. Iterates known bots and
-- sends polls whose intervals have elapsed, rate-limited to avoid bursts.
function Comm:Tick()
    local bots = DWP.BotRoster:GetOnlineBots()
    if #bots == 0 then return end

    local now = GetTime()
    local sent = 0
    local maxPerTick = 2

    lastPollSlot = lastPollSlot + 1
    if lastPollSlot > #bots then lastPollSlot = 1 end

    for offset = 0, #bots - 1 do
        if sent >= maxPerTick then break end
        local idx = ((lastPollSlot - 1 + offset) % #bots) + 1
        local bot = bots[idx]
        local ps = pollState[bot.name] or {}
        pollState[bot.name] = ps

        if (not ps.lastStrat) or (now - ps.lastStrat >= GetStrategiesInterval()) then
            -- Send combat strategies poll. Non-combat will follow on next eligible tick.
            if ps._pendingNc then
                self:SendPoll(bot.name, "nc ?")
                ps._pendingNc = false
                ps.lastStrat = now
            else
                self:SendPoll(bot.name, "co ?")
                ps._pendingNc = true
            end
            sent = sent + 1
        elseif (not ps.lastIdent) or (now - ps.lastIdent >= GetIdentityInterval()) then
            self:SendPoll(bot.name, "who")
            ps.lastIdent = now
            sent = sent + 1
        end
    end

    self:ExpireOutstanding()
end

-- Send a polling whisper and record it as outstanding.
function Comm:SendPoll(botName, cmd)
    if not botName or not cmd then return end
    outstandingPolls[botName] = outstandingPolls[botName] or {}
    outstandingPolls[botName][cmd] = GetTime() + OUTSTANDING_TTL
    SendChatMessage(cmd, "WHISPER", nil, botName)
    DWP:Debug("poll -> "..botName..": "..cmd)
end

-- Clear expired outstanding polls.
function Comm:ExpireOutstanding()
    local now = GetTime()
    for bot, pending in pairs(outstandingPolls) do
        for cmd, expire in pairs(pending) do
            if now > expire then pending[cmd] = nil end
        end
    end
end

-- Clear poll state for a bot that left.
function Comm:ForgetBot(botName)
    pollState[botName] = nil
    outstandingPolls[botName] = nil
end

----------------------------------------------------------------------
-- Response parsing
----------------------------------------------------------------------

-- Parses a whispered response from a bot and fires the appropriate event.
function Comm:ParseWhisperResponse(botName, msg)
    if not msg or msg == "" then return end
    DWP:Debug("parse <- "..botName..": "..msg)

    -- "Strategies: a, b, c, ..."
    local stratList = msg:match("^Strategies:%s*(.+)$")
    if stratList then
        local list = {}
        for item in string.gmatch(stratList, "([^,]+)") do
            local trimmed = item:match("^%s*(.-)%s*$")
            if trimmed ~= "" then list[#list + 1] = trimmed end
        end

        -- Match to the first pending poll (co? or nc?).
        local pending = outstandingPolls[botName]
        local which = nil
        if pending then
            if pending["co ?"] then
                which = "combat"
                pending["co ?"] = nil
            elseif pending["nc ?"] then
                which = "noncombat"
                pending["nc ?"] = nil
            end
        end
        Fire("strategies", botName, { which = which, strategies = list })
        return
    end

    -- "who" response parsing.  [parser build: v4-nomatch 2026-04-17]
    -- Avoids %( and %) patterns entirely because they appear to fail on
    -- this client's Lua 5.1 pattern engine. Uses plain-text string.find
    -- and manual substring extraction instead.
    do
        local race, gender, spec, class, level, gs, ilvl, zone, master

        -- Race and gender: "Foo [M]" or "Foo [F]" at the start.
        -- %[ and %] work fine (verified), only parens have the issue.
        race, gender = msg:match("^(%S+)%s+%[(%a)%]")

        -- Spec: word right after "]" (and before the next space).
        spec = msg:match("%]%s+(%S+)")

        -- Level: find the substring " lvl)" with plain-text find, then
        -- walk backward to read the digits.
        local lvlEnd = string.find(msg, " lvl)", 1, true)  -- plain find
        if lvlEnd then
            -- lvlEnd is the start index of " lvl)". Walk backward through digits.
            local i = lvlEnd - 1
            while i > 0 and msg:sub(i, i):match("%d") do
                i = i - 1
            end
            -- i is now on the char before the digits (should be "(").
            local digitsStart = i + 1
            level = msg:sub(digitsStart, lvlEnd - 1)

            -- Now find the class: the word right before "(<level> lvl)".
            -- i points at the "(". Walk back past any whitespace.
            local j = i - 1
            while j > 0 and msg:sub(j, j):match("%s") do
                j = j - 1
            end
            -- j is now on the last char of the class word. Walk back to find start.
            local classEnd = j
            while j > 0 and msg:sub(j, j):match("%a") do
                j = j - 1
            end
            -- j is now on the char before the class word.
            class = msg:sub(j + 1, classEnd)
        end

        -- Talents: find " (N/N/N)" using plain find for the key "(" then parse forward.
        -- Actually simpler: find the " (" that precedes "<digit>/" and extract digits.
        local t1, t2, t3
        do
            local slashPos = string.find(msg, "/", 1, true)
            if slashPos then
                -- Walk backward through digits.
                local i = slashPos - 1
                while i > 0 and msg:sub(i, i):match("%d") do
                    i = i - 1
                end
                local t1Str = msg:sub(i + 1, slashPos - 1)
                -- Now parse forward through second slash to find t2 and t3.
                local t2Start = slashPos + 1
                local t2End = t2Start
                while t2End <= #msg and msg:sub(t2End, t2End):match("%d") do
                    t2End = t2End + 1
                end
                local t2Str = msg:sub(t2Start, t2End - 1)
                if msg:sub(t2End, t2End) == "/" then
                    local t3Start = t2End + 1
                    local t3End = t3Start
                    while t3End <= #msg and msg:sub(t3End, t3End):match("%d") do
                        t3End = t3End + 1
                    end
                    local t3Str = msg:sub(t3Start, t3End - 1)
                    if t1Str ~= "" and t2Str ~= "" and t3Str ~= "" then
                        t1, t2, t3 = t1Str, t2Str, t3Str
                    end
                end
            end
        end

        -- GS: look for " GS " substring, walk back to get N, walk forward past "(" to get iLvl.
        local gsPos = string.find(msg, " GS ", 1, true)
        if gsPos then
            -- Walk back for the GS number.
            local i = gsPos - 1
            while i > 0 and msg:sub(i, i):match("%d") do
                i = i - 1
            end
            gs = msg:sub(i + 1, gsPos - 1)

            -- Walk forward past "GS (" to get ilvl.
            local afterGs = gsPos + 4  -- skip " GS "
            if msg:sub(afterGs, afterGs) == "(" then
                local ilvlStart = afterGs + 1
                local ilvlEnd = ilvlStart
                while ilvlEnd <= #msg and msg:sub(ilvlEnd, ilvlEnd):match("%d") do
                    ilvlEnd = ilvlEnd + 1
                end
                ilvl = msg:sub(ilvlStart, ilvlEnd - 1)
                if ilvl == "" then ilvl = nil end
            end
            if gs == "" then gs = nil end
        end

        -- Zone and master: find "playing with" and extract zone before it, master after.
        local pwPos = string.find(msg, "playing with ", 1, true)
        if pwPos then
            master = msg:sub(pwPos + 13)   -- past "playing with "
            -- Trim trailing whitespace.
            master = master:match("^(.-)%s*$")

            -- Zone is in parens right before "playing with". Walk back from pwPos.
            -- Skip back past comma and space.
            local i = pwPos - 1
            while i > 0 and msg:sub(i, i):match("[%s,]") do
                i = i - 1
            end
            -- i should now be on ")".
            if msg:sub(i, i) == ")" then
                -- Walk back to matching "(".
                local zoneEnd = i - 1
                local j = zoneEnd
                while j > 0 and msg:sub(j, j) ~= "(" do
                    j = j - 1
                end
                if msg:sub(j, j) == "(" then
                    zone = msg:sub(j + 1, zoneEnd)
                end
            end
        end

        if race and class and level then
            Fire("identity", botName, {
                race = race, gender = gender, spec = spec,
                specTalents = t1 and { tonumber(t1), tonumber(t2), tonumber(t3) } or nil,
                class = class, level = tonumber(level),
                gs = gs and tonumber(gs) or nil,
                ilvl = ilvl and tonumber(ilvl) or nil,
                zone = zone, master = master,
            })
            local pending = outstandingPolls[botName]
            if pending then pending["who"] = nil end
            return
        else
            DWP:Debug(string.format(
                "[v4-nomatch] who-parse fail: race=%s gender=%s spec=%s talents=%s,%s,%s class=%s level=%s gs=%s ilvl=%s zone=%s master=%s",
                tostring(race), tostring(gender), tostring(spec),
                tostring(t1), tostring(t2), tostring(t3),
                tostring(class), tostring(level),
                tostring(gs), tostring(ilvl),
                tostring(zone), tostring(master)))
        end
    end

    -- Unknown format — quietly log in debug.
    DWP:Debug("unrecognized whisper from "..botName..": "..msg)
end

----------------------------------------------------------------------
-- Outbound command helpers (visible, for user-triggered actions)
----------------------------------------------------------------------

-- Send a visible command to a bot (shows in chat).
function Comm:SendBotCommand(botName, cmd, args)
    if not botName or not cmd then return end
    local msg = args and (cmd .. " " .. args) or cmd
    SendChatMessage(msg, "WHISPER", nil, botName)
end

-- Send a batch of whispers, staggered over time to avoid chat throttling.
-- msgs is a list of strings to whisper in order. interval is optional
-- (seconds between sends, default 0.2).
local batchQueue = {}       -- { { bot, msg, fireAt }, ... }
local batchFrame
function Comm:SendBotCommandBatch(botName, msgs, interval)
    if not botName or not msgs or #msgs == 0 then return end
    interval = interval or 0.2
    local now = GetTime()
    for i, m in ipairs(msgs) do
        table.insert(batchQueue, {
            bot = botName,
            msg = m,
            fireAt = now + (i - 1) * interval,
        })
    end

    if not batchFrame then
        batchFrame = CreateFrame("Frame")
        batchFrame:SetScript("OnUpdate", function(self)
            local t = GetTime()
            local i = 1
            while i <= #batchQueue do
                local item = batchQueue[i]
                if t >= item.fireAt then
                    SendChatMessage(item.msg, "WHISPER", nil, item.bot)
                    table.remove(batchQueue, i)
                else
                    i = i + 1
                end
            end
            if #batchQueue == 0 then self:Hide() end
        end)
    end
    batchFrame:Show()
end

-- Send a server dot-command.
function Comm:SendBotAdmin(cmd)
    if not cmd then return end
    SendChatMessage(cmd, "SAY")
end

-- Utility: split comma-separated strategy list.
function Comm:SplitStrategies(s)
    local out = {}
    if not s or s == "" then return out end
    for item in string.gmatch(s, "([^,]+)") do
        local trimmed = item:match("^%s*(.-)%s*$")
        if trimmed ~= "" then out[#out + 1] = trimmed end
    end
    return out
end
