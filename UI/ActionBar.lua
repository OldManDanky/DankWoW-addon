--[[
    ActionBar.lua

    A small floating bar of 5 preset shortcuts: Tank, Healer, DPS,
    Follow, Stay. Click any button to open a dropdown listing current
    party bots; pick one to apply that preset to that bot.

    Position is persistent (via SavedVariables). The bar can be dragged.

    Commands:
      /dwp bar       — toggle visibility
      /dwp bar reset — reset to default position

    Button → preset mapping:
      Tank    → DWP.Presets.COMBAT[tank]
      Healer  → DWP.Presets.COMBAT[healer]
      DPS     → DWP.Presets.COMBAT[dps]
      Follow  → DWP.Presets.NONCOMBAT[follow]
      Stay    → DWP.Presets.NONCOMBAT[stay]

    Applying a preset sends a batch of co +/- (or nc +/-) whispers via
    Comm:SendBotCommandBatch, which staggers them 200ms apart to avoid
    chat throttling. Only the minimal diff of whispers is sent (the
    preset's PlanApply skips strategies already in the target state).
]]

local DWP = DankWoWPlayerbots
local ActionBar = {}
DWP.ActionBar = ActionBar

local BUTTON_SIZE = 36
local BUTTON_GAP  = 3
local ROW_GAP     = 3
local BAR_PADDING = 5

-- Top-row buttons: set roles (preset application).
-- Clicking opens a bot-picker dropdown; selection applies that preset
-- to the chosen bot.
local PRESET_BUTTONS = {
    { label = "Tank",   category = "combat",    presetId = "tank",   tooltip = "Assign a bot to Tank role.",   clickHint = "Click to pick a bot." },
    { label = "Healer", category = "combat",    presetId = "healer", tooltip = "Assign a bot to Healer role.", clickHint = "Click to pick a bot." },
    { label = "DPS",    category = "combat",    presetId = "dps",    tooltip = "Assign a bot to DPS role.",    clickHint = "Click to pick a bot." },
    { label = "Follow", category = "noncombat", presetId = "follow", tooltip = "Set a bot to follow you.",     clickHint = "Click to pick a bot." },
    { label = "Stay",   category = "noncombat", presetId = "stay",   tooltip = "Tell a bot to hold position.", clickHint = "Click to pick a bot." },
}

-- Bottom-row buttons: group commands via /p chat with @selector prefix.
-- mod-playerbots parses party chat messages starting with @<role|group|class>
-- and routes the trailing command to matching bots. One message reaches
-- many bots at once, no whisper throttling.
local COMMAND_BUTTONS = {
    { label = "T-Atk",  message = "@tank attack",      tooltip = "Tell tank bots to attack your current target.",  clickHint = "Sends: /p @tank attack" },
    { label = "Assist", message = "@dps assist",       tooltip = "Tell DPS bots to assist (attack what the tank is attacking).", clickHint = "Sends: /p @dps assist" },
    { label = "H-Tank", message = "@heal focus tank",  tooltip = "Tell healer bots to focus heals on the tank.",   clickHint = "Sends: /p @heal focus tank" },
    { label = "Follow", message = "follow",            tooltip = "All bots follow you.",                            clickHint = "Sends: /p follow" },
    { label = "Stay",   message = "stay",              tooltip = "All bots hold position.",                         clickHint = "Sends: /p stay" },
}

-- Bar dimensions derived from the widest row.
local BUTTONS_PER_ROW = math.max(#PRESET_BUTTONS, #COMMAND_BUTTONS)
local BAR_WIDTH  = BUTTON_SIZE * BUTTONS_PER_ROW + BUTTON_GAP * (BUTTONS_PER_ROW - 1) + BAR_PADDING * 2
local BAR_HEIGHT = BUTTON_SIZE * 2 + ROW_GAP + BAR_PADDING * 2

-- Module-local state.
local _bar              -- the frame, memoized via Get()
local _dropdown         -- shared UIDropDownMenu frame

----------------------------------------------------------------------
-- Preset lookup
----------------------------------------------------------------------

local function FindPreset(category, presetId)
    local list = (category == "combat") and DWP.Presets.COMBAT or DWP.Presets.NONCOMBAT
    for _, p in ipairs(list) do
        if p.id == presetId then return p end
    end
    return nil
end

-- Apply a preset to a single bot. Sends the minimal diff of co +/- (or
-- nc +/-) whispers via the staggered batch sender.
local function ApplyPresetToBot(bot, category, presetId)
    if not bot or not bot.name then return end
    local preset = FindPreset(category, presetId)
    if not preset then return end

    local activeList, prefix_add, prefix_remove
    if category == "combat" then
        activeList    = bot.strategiesCombat
        prefix_add    = "co +"
        prefix_remove = "co -"
    else
        activeList    = bot.strategiesNonCombat
        prefix_add    = "nc +"
        prefix_remove = "nc -"
    end

    local whispers = DWP.Presets:PlanApply(preset, activeList, prefix_add, prefix_remove)
    if #whispers == 0 then
        DWP:Print(bot.name .. " already matches " .. preset.label .. ".")
        return
    end
    DWP.Comm:SendBotCommandBatch(bot.name, whispers, 0.2)
    DWP:Print(string.format("applying %s to %s (%d changes)...",
        preset.label, bot.name, #whispers))
end

-- Send an @-prefixed group command via party chat. If the player isn't
-- in a party, we can't send /p messages; fall back to a friendly notice.
-- We intentionally don't auto-fallback to /r or whispers; if the user
-- upgrades to a raid, we can revisit in a later version.
local function SendGroupCommand(message)
    if not message or message == "" then return end
    if GetNumPartyMembers() == 0 and GetNumRaidMembers() == 0 then
        DWP:Print("|cffFF9933no party\\/raid members to command.|r")
        return
    end
    -- Prefer PARTY (user's stated preference); if in a raid, PARTY won't
    -- reach raid members but we keep it simple per the design decision.
    SendChatMessage(message, "PARTY")
end

----------------------------------------------------------------------
-- Bot-picker dropdown
----------------------------------------------------------------------

local function EnsureDropdown()
    if _dropdown then return _dropdown end
    _dropdown = CreateFrame("Frame", "DankWoWPlayerbotsActionBarDropdown",
                            UIParent, "UIDropDownMenuTemplate")
    _dropdown:Hide()
    return _dropdown
end

-- Show a dropdown listing active bots. `onPick(bot)` is called when the
-- user selects one. `anchor` is the frame the dropdown anchors from.
local function ShowBotPicker(anchor, headerText, onPick)
    EnsureDropdown()

    local bots = DWP.BotRoster:GetOnlineBots()

    UIDropDownMenu_Initialize(_dropdown, function(self, level, menuList)
        -- Header (non-clickable).
        local header = UIDropDownMenu_CreateInfo()
        header.text    = headerText or "Select bot"
        header.isTitle = true
        header.notCheckable = true
        UIDropDownMenu_AddButton(header, level)

        if #bots == 0 then
            local info = UIDropDownMenu_CreateInfo()
            info.text = "|cff5A7090(no bots in party)|r"
            info.disabled = true
            info.notCheckable = true
            UIDropDownMenu_AddButton(info, level)
        else
            for _, bot in ipairs(bots) do
                local info = UIDropDownMenu_CreateInfo()
                -- Class-color the name.
                local classFile = bot.class or "WARRIOR"
                local color = (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile])
                    or { r = 1, g = 1, b = 1 }
                info.text = string.format("|cff%02x%02x%02x%s|r",
                    color.r * 255, color.g * 255, color.b * 255, bot.name)
                info.notCheckable = true
                info.func = function()
                    onPick(bot)
                    CloseDropDownMenus()
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end

        -- Cancel.
        local cancel = UIDropDownMenu_CreateInfo()
        cancel.text = "Cancel"
        cancel.notCheckable = true
        cancel.func = function() CloseDropDownMenus() end
        UIDropDownMenu_AddButton(cancel, level)
    end, "MENU")

    ToggleDropDownMenu(1, nil, _dropdown, anchor, 0, 0)
end

----------------------------------------------------------------------
-- Button style (matches existing ice-blue palette)
----------------------------------------------------------------------

local function StyleButton(btn, cfg)
    local skin = DWP.Skin.COLORS

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(btn)
    bg:SetTexture(skin.DEEP_GLACIAL[1], skin.DEEP_GLACIAL[2], skin.DEEP_GLACIAL[3], 0.9)
    btn._bg = bg

    btn:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    btn:SetBackdropBorderColor(
        skin.STEEL_BLUE[1], skin.STEEL_BLUE[2], skin.STEEL_BLUE[3], 0.9)

    local label = btn:CreateFontString(nil, "OVERLAY")
    label:SetFont(DWP.Skin.FONTS.HEADER, 10, "OUTLINE")
    label:SetPoint("CENTER", btn, "CENTER", 0, 0)
    label:SetTextColor(skin.ICY_WHITE[1], skin.ICY_WHITE[2], skin.ICY_WHITE[3], 1)
    label:SetText(cfg.label)
    btn._label = label

    btn:SetScript("OnEnter", function(self)
        self._bg:SetTexture(skin.FROST_BLUE[1], skin.FROST_BLUE[2], skin.FROST_BLUE[3], 0.95)
        self:SetBackdropBorderColor(
            skin.ICE_PRIMARY[1], skin.ICE_PRIMARY[2], skin.ICE_PRIMARY[3], 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(cfg.label, 1, 1, 1)
        GameTooltip:AddLine(cfg.tooltip, 0.9, 0.9, 0.9, true)
        if cfg.clickHint then
            GameTooltip:AddLine(cfg.clickHint,
                skin.MUTED[1], skin.MUTED[2], skin.MUTED[3], false)
        end
        GameTooltip:Show()
    end)

    btn:SetScript("OnLeave", function(self)
        self._bg:SetTexture(skin.DEEP_GLACIAL[1], skin.DEEP_GLACIAL[2], skin.DEEP_GLACIAL[3], 0.9)
        self:SetBackdropBorderColor(
            skin.STEEL_BLUE[1], skin.STEEL_BLUE[2], skin.STEEL_BLUE[3], 0.9)
        GameTooltip:Hide()
    end)

    btn:SetScript("OnMouseDown", function(self)
        self._bg:SetTexture(skin.VOID[1], skin.VOID[2], skin.VOID[3], 0.95)
    end)
    btn:SetScript("OnMouseUp", function(self)
        self._bg:SetTexture(skin.FROST_BLUE[1], skin.FROST_BLUE[2], skin.FROST_BLUE[3], 0.95)
    end)
end

----------------------------------------------------------------------
-- Bar construction
----------------------------------------------------------------------

local function BuildBar()
    local skin = DWP.Skin.COLORS

    local f = CreateFrame("Frame", "DankWoWPlayerbotsActionBar", UIParent)
    f:SetSize(BAR_WIDTH, BAR_HEIGHT)
    f:SetFrameStrata("MEDIUM")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self)
        if DWP.Config and DWP.Config.db.actionBar and DWP.Config.db.actionBar.locked then return end
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Persist position.
        local point, _, relPoint, xOfs, yOfs = self:GetPoint(1)
        if DWP.Config and DWP.Config.db.actionBar then
            DWP.Config.db.actionBar.point    = point
            DWP.Config.db.actionBar.relPoint = relPoint
            DWP.Config.db.actionBar.xOfs     = xOfs
            DWP.Config.db.actionBar.yOfs     = yOfs
        end
    end)

    -- Background panel.
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    f:SetBackdropColor(
        skin.VOID[1], skin.VOID[2], skin.VOID[3], 0.85)
    f:SetBackdropBorderColor(
        skin.ICE_PRIMARY[1], skin.ICE_PRIMARY[2], skin.ICE_PRIMARY[3], 0.7)

    -- Build top row: preset buttons (role assignment via dropdown).
    for i, cfg in ipairs(PRESET_BUTTONS) do
        local btn = CreateFrame("Button", nil, f)
        btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT",
            BAR_PADDING + (i - 1) * (BUTTON_SIZE + BUTTON_GAP),
            -BAR_PADDING)
        StyleButton(btn, cfg)

        btn:SetScript("OnClick", function(self)
            ShowBotPicker(self,
                string.format("Assign %s to...", cfg.label),
                function(bot)
                    ApplyPresetToBot(bot, cfg.category, cfg.presetId)
                end)
        end)
    end

    -- Build bottom row: command buttons (party-chat @selector commands).
    for i, cfg in ipairs(COMMAND_BUTTONS) do
        local btn = CreateFrame("Button", nil, f)
        btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT",
            BAR_PADDING + (i - 1) * (BUTTON_SIZE + BUTTON_GAP),
            -BAR_PADDING - BUTTON_SIZE - ROW_GAP)
        StyleButton(btn, cfg)

        btn:SetScript("OnClick", function(self)
            SendGroupCommand(cfg.message)
        end)
    end

    -- Apply saved position, or default to center-ish.
    f:ClearAllPoints()
    local p = DWP.Config and DWP.Config.db and DWP.Config.db.actionBar
    if p and p.point then
        f:SetPoint(p.point, UIParent, p.relPoint or "CENTER",
                   p.xOfs or 0, p.yOfs or 0)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
    end

    f:Hide()
    return f
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function ActionBar:Get()
    if not _bar then _bar = BuildBar() end
    return _bar
end

function ActionBar:Show()
    local f = self:Get()
    f:Show()
    if DWP.Config and DWP.Config.db.actionBar then
        DWP.Config.db.actionBar.shown = true
    end
end

function ActionBar:Hide()
    local f = self:Get()
    f:Hide()
    if DWP.Config and DWP.Config.db.actionBar then
        DWP.Config.db.actionBar.shown = false
    end
end

function ActionBar:Toggle()
    local f = self:Get()
    if f:IsShown() then self:Hide() else self:Show() end
end

function ActionBar:ResetPosition()
    local f = self:Get()
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", 0, -180)
    if DWP.Config and DWP.Config.db.actionBar then
        DWP.Config.db.actionBar.point    = "CENTER"
        DWP.Config.db.actionBar.relPoint = "CENTER"
        DWP.Config.db.actionBar.xOfs     = 0
        DWP.Config.db.actionBar.yOfs     = -180
    end
end
