--[[
    Core.lua (chat-fallback version)

    Addon bootstrap. Wires together Config, Comm, BotRoster, and the UI
    into a working whole. Registers all WoW events and dispatches them
    to the right modules.

    Key event flow:
      - On ADDON_LOADED:   init SavedVariables, register chat filters,
                           hook Comm callbacks into Roster, register
                           slash commands.
      - On PLAYER_ENTERING_WORLD: first party scan, start ticker, show
                           panel if configured.
      - On GROUP_ROSTER_UPDATE / PARTY_MEMBERS_CHANGED: rescan party.
      - On UNIT_HEALTH, UNIT_POWER, UNIT_TARGET, etc.: refresh the
        matching bot's state.
]]

local DWP = DankWoWPlayerbots

----------------------------------------------------------------------
-- Logging helpers (used by every module)
----------------------------------------------------------------------

function DWP:Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff3FA9FF[DankBots]|r " .. tostring(msg))
end

function DWP:Debug(msg)
    if DWP.Config and DWP.Config.db and DWP.Config.db.debug.logMessages then
        DEFAULT_CHAT_FRAME:AddMessage("|cff98E8F8[DankBots:dbg]|r " .. tostring(msg))
    end
end

----------------------------------------------------------------------
-- Event frame
----------------------------------------------------------------------

local eventFrame = CreateFrame("Frame", "DankWoWPlayerbotsEventFrame")

local function OnEvent(self, event, arg1, arg2, arg3, arg4, arg5)
    if event == "ADDON_LOADED" then
        if arg1 == "DankWoW_Playerbots" then
            DWP:OnAddonLoaded()
        end

    elseif event == "PLAYER_LOGIN" then
        DWP:OnPlayerLogin()

    elseif event == "PLAYER_ENTERING_WORLD" then
        DWP:OnPlayerEnteringWorld()

    elseif event == "GROUP_ROSTER_UPDATE"
        or event == "PARTY_MEMBERS_CHANGED"
        or event == "RAID_ROSTER_UPDATE" then
        DWP.BotRoster:ScanParty()

    -- Unit events — refresh the specific unit.
    elseif event == "UNIT_HEALTH"
        or event == "UNIT_MAXHEALTH"
        or event == "UNIT_POWER"
        or event == "UNIT_MAXPOWER"
        or event == "UNIT_DISPLAYPOWER"
        or event == "UNIT_TARGET"
        or event == "UNIT_FLAGS"
        or event == "UNIT_COMBAT" then
        DWP.BotRoster:RefreshUnit(arg1)

    elseif event == "PLAYER_REGEN_ENABLED"
        or event == "PLAYER_REGEN_DISABLED" then
        -- Scan all bots since UNIT_FLAGS doesn't always fire reliably on
        -- party members when their combat state changes.
        for _, u in ipairs({"party1","party2","party3","party4"}) do
            DWP.BotRoster:RefreshUnit(u)
        end
    end
end

eventFrame:SetScript("OnEvent", OnEvent)
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

-- Party/raid composition.
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")

-- Unit state.
eventFrame:RegisterEvent("UNIT_HEALTH")
eventFrame:RegisterEvent("UNIT_MAXHEALTH")
eventFrame:RegisterEvent("UNIT_POWER")
eventFrame:RegisterEvent("UNIT_MAXPOWER")
eventFrame:RegisterEvent("UNIT_DISPLAYPOWER")
eventFrame:RegisterEvent("UNIT_TARGET")
eventFrame:RegisterEvent("UNIT_FLAGS")
eventFrame:RegisterEvent("UNIT_COMBAT")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")

----------------------------------------------------------------------
-- Lifecycle handlers
----------------------------------------------------------------------

function DWP:OnAddonLoaded()
    -- SavedVariables first.
    self.Config:Initialize()

    -- Install chat filters (hides our poll traffic).
    self.Comm:InstallChatFilters()

    -- Wire Comm -> Roster callbacks.
    self.Comm:RegisterHandler("strategies", function(name, payload)
        self.BotRoster:OnStrategies(name, payload)
    end)
    self.Comm:RegisterHandler("identity", function(name, payload)
        self.BotRoster:OnIdentity(name, payload)
    end)

    -- Slash commands.
    for i, name in ipairs(DWP.SLASH_COMMANDS) do
        _G["SLASH_DANKWOWPLAYERBOTS" .. i] = name
    end
    SlashCmdList["DANKWOWPLAYERBOTS"] = function(input) DWP:OnSlashCommand(input) end
end

function DWP:OnPlayerLogin()
    -- Nothing special.
end

function DWP:OnPlayerEnteringWorld()
    -- Initial party scan.
    self.BotRoster:ScanParty()

    -- Start the polling ticker.
    self.BotRoster:StartTicker()

    -- Show UI if it was up last session.
    if self.Config.db.panel.shown and self.MainFrame then
        self.MainFrame:Show()
    end
    if self.Config.db.minimap.shown and self.MinimapButton then
        self.MinimapButton:Show()
    end
    if self.Config.db.actionBar and self.Config.db.actionBar.shown and self.ActionBar then
        self.ActionBar:Show()
    end

    -- Session greeting (once).
    if not self._greeted then
        self._greeted = true
        self:Print(string.format(
            "v%s loaded. Type |cff98E8F8%s|r to open, or click the minimap button.",
            DWP.VERSION, DWP.SLASH_COMMANDS[1]))
    end
end

----------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------

function DWP:OnSlashCommand(input)
    input = string.lower(string.gsub(input or "", "^%s+", ""))
    input = string.gsub(input, "%s+$", "")

    if input == "" or input == "toggle" then
        if self.MainFrame then self.MainFrame:Toggle() end

    elseif input == "show" then
        if self.MainFrame then self.MainFrame:Show() end

    elseif input == "hide" then
        if self.MainFrame then self.MainFrame:Hide() end

    elseif input == "reset" then
        local p = self.Config.db.panel
        p.point, p.relPoint, p.xOfs, p.yOfs = "CENTER", "CENTER", 0, 0
        p.scale = 0.8
        p.alpha = 1.0
        if self.MainFrame then
            self.MainFrame:ApplyPosition()
            local f = self.MainFrame:Get()
            f:SetScale(p.scale)
            f:SetAlpha(p.alpha)
        end
        self:Print("panel position, scale, and opacity reset.")

    elseif input == "debug" then
        local d = self.Config.db.debug
        d.logMessages = not d.logMessages
        self:Print("debug logging: " .. (d.logMessages and "|cff4FFF6Bon|r" or "|cffFF3838off|r"))

    elseif input:match("^scale") then
        -- `/dwp scale` with no arg prints current; `/dwp scale 0.8` sets it.
        local val = input:match("^scale%s+([%d%.]+)$")
        if val then
            local n = tonumber(val)
            if n and n >= 0.3 and n <= 2.0 then
                self.Config.db.panel.scale = n
                if self.MainFrame then self.MainFrame:Get():SetScale(n) end
                self:Print(string.format("panel scale: %.2f", n))
            else
                self:Print("scale must be between 0.3 and 2.0")
            end
        else
            self:Print(string.format("panel scale: %.2f (use |cff98E8F8%s scale 0.8|r to change)",
                self.Config.db.panel.scale or 1.0, DWP.SLASH_COMMANDS[1]))
        end

    elseif input == "scan" then
        -- Force an immediate rescan and show what's in the roster.
        self.BotRoster:ScanParty()
        local bots = self.BotRoster:GetOnlineBots()
        self:Print(string.format("roster has %d bot%s:", #bots, #bots == 1 and "" or "s"))
        for _, b in ipairs(bots) do
            self:Print(string.format("  %s (%s, level %d)",
                b.name, b.classLocalized or "?", b.level or 0))
        end

    elseif input == "bots" then
        if self.BotManagerFrame then self.BotManagerFrame:Toggle() end

    elseif input == "options" or input == "config" then
        if self.OptionsPanel then self.OptionsPanel:Show() end

    elseif input == "bar" then
        if self.ActionBar then self.ActionBar:Toggle() end

    elseif input == "bar reset" then
        if self.ActionBar then
            self.ActionBar:ResetPosition()
            self:Print("action bar position reset.")
        end

    elseif input == "version" or input == "v" then
        self:Print(string.format("v%s (chat-fallback transport)", DWP.VERSION))

    elseif input == "help" or input == "?" then
        self:Print("commands:")
        self:Print("  " .. DWP.SLASH_COMMANDS[1] .. "           toggle main panel")
        self:Print("  " .. DWP.SLASH_COMMANDS[1] .. " show      show panel")
        self:Print("  " .. DWP.SLASH_COMMANDS[1] .. " hide      hide panel")
        self:Print("  " .. DWP.SLASH_COMMANDS[1] .. " reset     reset panel position, scale, opacity")
        self:Print("  " .. DWP.SLASH_COMMANDS[1] .. " scale N   set panel scale (0.3 - 2.0)")
        self:Print("  " .. DWP.SLASH_COMMANDS[1] .. " bots      open bot add/remove dialog")
        self:Print("  " .. DWP.SLASH_COMMANDS[1] .. " bar       toggle action bar (tank/healer/dps/follow/stay)")
        self:Print("  " .. DWP.SLASH_COMMANDS[1] .. " bar reset reset action bar position")
        self:Print("  " .. DWP.SLASH_COMMANDS[1] .. " options   open the settings panel")
        self:Print("  " .. DWP.SLASH_COMMANDS[1] .. " scan      force rescan of party for bots")
        self:Print("  " .. DWP.SLASH_COMMANDS[1] .. " debug     toggle protocol debug logging")
        self:Print("  " .. DWP.SLASH_COMMANDS[1] .. " version   show version info")

    else
        self:Print("unknown command. type |cff98E8F8" .. DWP.SLASH_COMMANDS[1] .. " help|r")
    end
end
