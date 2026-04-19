--[[
    CommandBar.lua

    A compact row of text buttons that attach to a bot portrait tile.
    Each button whispers a command to the associated bot when clicked.

    Design:
      - Buttons share space equally across the bar's width
      - DankWoW ice-blue palette for normal / hover / pressed states
      - Each button stores its own command string so the bar itself
        is bot-agnostic — the tile calls :SetBot(name) to wire up
        which character the whispers get sent to
      - Tooltips show exactly what will be whispered

    Typical use (from BotPortrait.lua):
      local bar = DWP.CommandBar:Build(parentTile)
      bar:SetPoint("BOTTOMLEFT", parentTile, "BOTTOMLEFT", pad, pad)
      bar:SetPoint("BOTTOMRIGHT", parentTile, "BOTTOMRIGHT", -pad, pad)
      bar:SetHeight(BUTTON_H)
      ...
      bar:SetBot(bot.name)   -- on tile refresh
]]

local DWP = DankWoWPlayerbots
local CommandBar = {}
DWP.CommandBar = CommandBar

local BUTTON_HEIGHT = 20
local BUTTON_GAP = 3

-- Canonical command set. Order here is the order on the bar.
-- `whisper` is the text sent to the bot.
-- `tooltip` describes the action to the player.
local COMMANDS = {
    { label = "Attack", whisper = "attack",    tooltip = "Bot attacks your current target." },
    { label = "Follow", whisper = "follow",    tooltip = "Bot follows you." },
    { label = "Stay",   whisper = "stay",      tooltip = "Bot holds position." },
    { label = "Reset",  whisper = "reset botAI", tooltip = "Resets bot AI (unsticks confused bots)." },
}

-- Style a button into the DankWoW frost palette.
-- We apply colors as inline textures rather than a shared Blizzard template
-- so the look stays consistent with the rest of the branded UI.
local function StyleButton(btn)
    local skin = DWP.Skin.COLORS

    -- Background texture (normal state).
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(btn)
    bg:SetTexture(skin.DEEP_GLACIAL[1], skin.DEEP_GLACIAL[2], skin.DEEP_GLACIAL[3], 0.9)
    btn._bg = bg

    -- Border (1px ice-blue edge).
    btn:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    btn:SetBackdropBorderColor(
        skin.STEEL_BLUE[1], skin.STEEL_BLUE[2], skin.STEEL_BLUE[3], 0.8)

    -- Label text.
    local fs = btn:CreateFontString(nil, "OVERLAY")
    fs:SetFont(DWP.Skin.FONTS.BODY, 11, "OUTLINE")
    fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
    fs:SetTextColor(skin.ICY_WHITE[1], skin.ICY_WHITE[2], skin.ICY_WHITE[3], 1)
    btn._label = fs

    -- Hover: lighten background, brighten border to frost-primary.
    btn:SetScript("OnEnter", function(self)
        self._bg:SetTexture(skin.FROST_BLUE[1], skin.FROST_BLUE[2], skin.FROST_BLUE[3], 0.95)
        self:SetBackdropBorderColor(
            skin.ICE_PRIMARY[1], skin.ICE_PRIMARY[2], skin.ICE_PRIMARY[3], 1)
        if self._tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self._label:GetText(), 1, 1, 1)
            GameTooltip:AddLine(self._tooltip, 0.9, 0.9, 0.9, true)
            if self._whisper then
                GameTooltip:AddLine(
                    "/w " .. (self._botName or "?") .. " " .. self._whisper,
                    skin.MUTED[1], skin.MUTED[2], skin.MUTED[3], false)
            end
            GameTooltip:Show()
        end
    end)

    btn:SetScript("OnLeave", function(self)
        self._bg:SetTexture(skin.DEEP_GLACIAL[1], skin.DEEP_GLACIAL[2], skin.DEEP_GLACIAL[3], 0.9)
        self:SetBackdropBorderColor(
            skin.STEEL_BLUE[1], skin.STEEL_BLUE[2], skin.STEEL_BLUE[3], 0.8)
        GameTooltip:Hide()
    end)

    -- Pressed: dim background briefly.
    btn:SetScript("OnMouseDown", function(self)
        self._bg:SetTexture(skin.VOID[1], skin.VOID[2], skin.VOID[3], 0.95)
    end)
    btn:SetScript("OnMouseUp", function(self)
        self._bg:SetTexture(skin.FROST_BLUE[1], skin.FROST_BLUE[2], skin.FROST_BLUE[3], 0.95)
    end)

    -- Disabled visual (for when bot is offline/not in party).
    function btn:SetEnabledLook(enabled)
        if enabled then
            self._label:SetTextColor(skin.ICY_WHITE[1], skin.ICY_WHITE[2], skin.ICY_WHITE[3], 1)
            self._bg:SetTexture(skin.DEEP_GLACIAL[1], skin.DEEP_GLACIAL[2], skin.DEEP_GLACIAL[3], 0.9)
            self:EnableMouse(true)
        else
            self._label:SetTextColor(skin.MUTED[1], skin.MUTED[2], skin.MUTED[3], 0.7)
            self._bg:SetTexture(skin.VOID[1], skin.VOID[2], skin.VOID[3], 0.7)
            self:EnableMouse(false)
        end
    end
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

-- Build a command bar as a child of `parent`. Returns a frame that
-- callers can anchor wherever they want. Call :SetBot(name) on it
-- each time the owning tile's bot changes.
function CommandBar:Build(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(BUTTON_HEIGHT)
    bar._buttons = {}
    bar._botName = nil

    for i, cmd in ipairs(COMMANDS) do
        local btn = CreateFrame("Button", nil, bar)
        StyleButton(btn)
        btn._label:SetText(cmd.label)
        btn._whisper = cmd.whisper
        btn._tooltip = cmd.tooltip

        btn:SetScript("OnClick", function(self)
            if not bar._botName or bar._botName == "" then return end
            DWP.Comm:SendBotCommand(bar._botName, self._whisper)
        end)

        bar._buttons[i] = btn
    end

    -- Relayout: distribute buttons evenly across the bar width.
    bar:SetScript("OnSizeChanged", function(self, w, h)
        local n = #self._buttons
        if n == 0 or not w or w <= 0 then return end
        local totalGap = BUTTON_GAP * (n - 1)
        local btnW = math.floor((w - totalGap) / n)
        for i, btn in ipairs(self._buttons) do
            btn:ClearAllPoints()
            btn:SetSize(btnW, h)
            btn:SetPoint("LEFT", self, "LEFT", (i - 1) * (btnW + BUTTON_GAP), 0)
        end
    end)

    -- Bind the bar to a specific bot. All future clicks whisper to this bot.
    function bar:SetBot(botName)
        self._botName = botName
        local enabled = (botName and botName ~= "")
        for _, btn in ipairs(self._buttons) do
            btn._botName = botName
            btn:SetEnabledLook(enabled)
        end
    end

    -- Disable the whole bar (e.g. when bot goes offline).
    function bar:SetEnabled(enabled)
        for _, btn in ipairs(self._buttons) do
            btn:SetEnabledLook(enabled)
        end
    end

    return bar
end

-- Exposed for testing / debugging.
function CommandBar:GetCommands()
    return COMMANDS
end
