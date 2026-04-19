--[[
    StrategyPanel.lua

    An expandable panel that attaches to a bot portrait tile and shows
    the bot's active combat / non-combat strategies as clickable pills.

    Interaction:
      - Collapsed by default; caret button toggles expand/collapse
      - Left-click a pill to remove that strategy (whispers `co -name`
        or `nc -name`)
      - Right-click the panel (or the small [+] button) to open a
        dropdown of common strategies to add (whispers `co +name`
        or `nc +name`)

    Data source: DWP.BotRoster maintains bot.strategiesCombat and
    bot.strategiesNonCombat from the periodic `co ?` and `nc ?` polls.

    Layout:
      When expanded, the panel grows the tile's height and shows:

        Combat:
          [aoe x] [avoid aoe x] [behind x] ... [+]

        Non-combat:
          [chat x] [default x] [dps assist x] ... [+]

      Pills wrap to multiple lines when there are many strategies.
]]

local DWP = DankWoWPlayerbots
local StrategyPanel = {}
DWP.StrategyPanel = StrategyPanel

----------------------------------------------------------------------
-- Known strategies (used for the add-dropdown)
----------------------------------------------------------------------
-- From mod-playerbots' `help` output. Not exhaustive but covers the
-- strategies most players interact with. Class-specific ones are
-- intentionally included in both lists where applicable; the player
-- can add whatever they want.

local COMMON_COMBAT = {
    "aoe", "arms", "avoid aoe", "behind", "cast time", "chat",
    "default", "dps aoe", "dps assist", "duel", "flee", "focus",
    "formation", "fury", "grind", "heal", "kite", "passive",
    "potions", "pull", "racials", "ranged", "save mana", "tank",
    "tank assist", "tank face", "threat",
}

local COMMON_NONCOMBAT = {
    "attack tagged", "chat", "close", "collision", "default",
    "duel", "emote", "explore", "flee", "follow", "food",
    "gather", "grind", "group", "guard", "loot", "maintenance",
    "map", "mount", "move from group", "move random", "nc",
    "passive", "pvp", "quest", "ranged", "return", "rpg",
    "runaway", "save mana", "sit", "stay", "tank assist",
}

----------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------

local PILL_HEIGHT = 16
local PILL_PAD_X = 8
local PILL_GAP = 4
local ROW_GAP = 4
local SECTION_GAP = 6
local HEADER_HEIGHT = 14

----------------------------------------------------------------------
-- Utility: measure the width a pill needs for its text
----------------------------------------------------------------------

-- Shared hidden font string for measuring text width. Much cheaper
-- than creating a new FontString per measurement.
local measurerFrame, measurerFS

local function MeasurePillWidth(text)
    if not measurerFrame then
        measurerFrame = CreateFrame("Frame", nil, UIParent)
        measurerFrame:Hide()
        measurerFS = measurerFrame:CreateFontString(nil, "OVERLAY")
        measurerFS:SetFont(DWP.Skin.FONTS.BODY, 10, "")
    end
    measurerFS:SetText(text)
    -- padding: 8px left + text + 4px gap + 8px for × + 6px right
    return math.ceil(measurerFS:GetStringWidth()) + PILL_PAD_X + 4 + 8 + 6
end

----------------------------------------------------------------------
-- Pill construction
----------------------------------------------------------------------

-- Style a single pill button.
-- onLeftClick(stratName) removes; onRightClick unused (reserved).
local function BuildPill(parent, stratName, category, onLeftClick)
    local skin = DWP.Skin.COLORS
    local pill = CreateFrame("Button", nil, parent)
    pill:SetHeight(PILL_HEIGHT)
    pill:SetWidth(MeasurePillWidth(stratName))
    pill:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Background.
    local bg = pill:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(pill)
    bg:SetTexture(skin.STEEL_BLUE[1], skin.STEEL_BLUE[2], skin.STEEL_BLUE[3], 0.75)
    pill._bg = bg

    -- Border.
    pill:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    pill:SetBackdropBorderColor(
        skin.ICE_PRIMARY[1], skin.ICE_PRIMARY[2], skin.ICE_PRIMARY[3], 0.6)

    -- Strategy name label — anchored left, leaves room for the × on the right.
    local label = pill:CreateFontString(nil, "OVERLAY")
    label:SetFont(DWP.Skin.FONTS.BODY, 10, "")
    label:SetTextColor(skin.ICY_WHITE[1], skin.ICY_WHITE[2], skin.ICY_WHITE[3], 1)
    label:SetPoint("LEFT", pill, "LEFT", PILL_PAD_X, 0)
    label:SetText(stratName)
    pill._label = label

    -- × indicator (fixed on right edge). Not a separate button — the whole
    -- pill is the click target — but visually distinct so the action is clear.
    local xMark = pill:CreateFontString(nil, "OVERLAY")
    xMark:SetFont(DWP.Skin.FONTS.HEADER, 12, "OUTLINE")
    xMark:SetTextColor(1, 0.4, 0.4, 0.8)  -- dimmer red by default
    xMark:SetPoint("RIGHT", pill, "RIGHT", -6, 0)
    xMark:SetText("×")
    pill._xMark = xMark

    -- Hover: brighter border; tooltip.
    pill:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(
            skin.ICE_PRIMARY[1], skin.ICE_PRIMARY[2], skin.ICE_PRIMARY[3], 1)
        self._bg:SetTexture(skin.FROST_BLUE[1], skin.FROST_BLUE[2], skin.FROST_BLUE[3], 0.85)
        self._xMark:SetTextColor(1, 0.2, 0.2, 1)  -- bright red on hover
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(stratName, 1, 1, 1)
        GameTooltip:AddLine("Left-click to remove.", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("Right-click panel to add.", 0.9, 0.9, 0.9)
        GameTooltip:Show()
    end)

    pill:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(
            skin.ICE_PRIMARY[1], skin.ICE_PRIMARY[2], skin.ICE_PRIMARY[3], 0.6)
        self._bg:SetTexture(skin.STEEL_BLUE[1], skin.STEEL_BLUE[2], skin.STEEL_BLUE[3], 0.75)
        self._xMark:SetTextColor(1, 0.4, 0.4, 0.8)  -- dim red idle
        GameTooltip:Hide()
    end)

    pill:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            if onLeftClick then onLeftClick(stratName, category) end
        end
    end)

    return pill
end

----------------------------------------------------------------------
-- Add-strategy dropdown (right-click menu)
----------------------------------------------------------------------

-- Shared dropdown frame. We use Blizzard's UIDropDownMenu helpers.
local dropdown

local function EnsureDropdown()
    if dropdown then return dropdown end
    dropdown = CreateFrame("Frame", "DankWoWPlayerbotsAddStrategyDropdown", UIParent, "UIDropDownMenuTemplate")
    dropdown:Hide()
    return dropdown
end

-- `category` is "combat" or "noncombat". `botName` is the target.
-- `activeList` is the list of already-active strategies (to filter out
-- of the menu so we don't duplicate).
local function ShowAddDropdown(botName, category, activeList, anchor)
    EnsureDropdown()

    local sourceList = (category == "combat") and COMMON_COMBAT or COMMON_NONCOMBAT
    local prefix     = (category == "combat") and "co +" or "nc +"

    -- Build a set of active strats for quick membership test.
    local activeSet = {}
    if activeList then
        for _, s in ipairs(activeList) do activeSet[s] = true end
    end

    -- Populate the dropdown.
    UIDropDownMenu_Initialize(dropdown, function(self, level, menuList)
        local categoryLabel = (category == "combat") and "Add Combat Strategy" or "Add Non-Combat Strategy"

        -- Header (non-clickable).
        local header = UIDropDownMenu_CreateInfo()
        header.text = categoryLabel
        header.isTitle = true
        header.notCheckable = true
        UIDropDownMenu_AddButton(header, level)

        for _, strat in ipairs(sourceList) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = strat
            info.notCheckable = true
            if activeSet[strat] then
                -- Already active — dim and disable.
                info.disabled = true
                info.text = strat .. " |cff5A7090(active)|r"
            else
                info.func = function()
                    DWP.Comm:SendBotCommand(botName, prefix .. strat)
                    CloseDropDownMenus()
                end
            end
            UIDropDownMenu_AddButton(info, level)
        end

        -- Close button.
        local close = UIDropDownMenu_CreateInfo()
        close.text = "Cancel"
        close.notCheckable = true
        close.func = function() CloseDropDownMenus() end
        UIDropDownMenu_AddButton(close, level)
    end, "MENU")

    ToggleDropDownMenu(1, nil, dropdown, anchor, 0, 0)
end

----------------------------------------------------------------------
-- Preset bar builder: row of preset role/mode buttons
----------------------------------------------------------------------

local PRESET_BTN_HEIGHT = 18
local PRESET_BAR_GAP = 4
local PRESET_BAR_HEIGHT = PRESET_BTN_HEIGHT  -- alias

-- Build a horizontal row of preset buttons. `presets` is the list from
-- DWP.Presets.COMBAT or .NONCOMBAT. `category` is "combat" or "noncombat".
-- Returns a frame with an :SetActivePreset(id) method to highlight one.
local function BuildPresetBar(parent, presets, category, onClick)
    local skin = DWP.Skin.COLORS
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(PRESET_BTN_HEIGHT)
    bar._buttons = {}

    for _, preset in ipairs(presets) do
        local btn = CreateFrame("Button", nil, bar)
        btn:SetHeight(PRESET_BTN_HEIGHT)
        -- Width auto-sized from text below.
        btn._preset = preset

        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(btn)
        bg:SetTexture(skin.DEEP_GLACIAL[1], skin.DEEP_GLACIAL[2], skin.DEEP_GLACIAL[3], 0.85)
        btn._bg = bg

        btn:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        btn:SetBackdropBorderColor(
            skin.STEEL_BLUE[1], skin.STEEL_BLUE[2], skin.STEEL_BLUE[3], 0.8)

        local label = btn:CreateFontString(nil, "OVERLAY")
        label:SetFont(DWP.Skin.FONTS.HEADER, 10, "OUTLINE")
        label:SetPoint("CENTER", btn, "CENTER", 0, 0)
        label:SetText(preset.label)
        label:SetTextColor(skin.ICY_WHITE[1], skin.ICY_WHITE[2], skin.ICY_WHITE[3], 1)
        btn._label = label

        -- Auto-size to text width with padding.
        btn:SetWidth(math.max(40, math.ceil(label:GetStringWidth()) + 16))

        btn:SetScript("OnEnter", function(self)
            if not self._active then
                self._bg:SetTexture(skin.FROST_BLUE[1], skin.FROST_BLUE[2], skin.FROST_BLUE[3], 0.9)
            end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(preset.label, 1, 1, 1)
            GameTooltip:AddLine(preset.tooltip, 0.9, 0.9, 0.9, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function(self)
            if self._active then
                self._bg:SetTexture(skin.ICE_PRIMARY[1], skin.ICE_PRIMARY[2], skin.ICE_PRIMARY[3], 0.85)
            else
                self._bg:SetTexture(skin.DEEP_GLACIAL[1], skin.DEEP_GLACIAL[2], skin.DEEP_GLACIAL[3], 0.85)
            end
            GameTooltip:Hide()
        end)
        btn:SetScript("OnClick", function(self)
            if onClick then onClick(preset, category) end
        end)

        table.insert(bar._buttons, btn)
    end

    -- Layout: pack buttons left-to-right with small gaps.
    local x = 0
    for _, btn in ipairs(bar._buttons) do
        btn:ClearAllPoints()
        btn:SetPoint("LEFT", bar, "LEFT", x, 0)
        x = x + btn:GetWidth() + 3
    end

    -- Highlight the active preset by id.
    function bar:SetActivePreset(activeId)
        for _, btn in ipairs(self._buttons) do
            local isActive = (btn._preset.id == activeId)
            btn._active = isActive
            if isActive then
                btn._bg:SetTexture(skin.ICE_PRIMARY[1], skin.ICE_PRIMARY[2], skin.ICE_PRIMARY[3], 0.85)
                btn:SetBackdropBorderColor(
                    skin.GLACIAL_CYAN[1], skin.GLACIAL_CYAN[2], skin.GLACIAL_CYAN[3], 1)
                btn._label:SetTextColor(1, 1, 1, 1)
            else
                btn._bg:SetTexture(skin.DEEP_GLACIAL[1], skin.DEEP_GLACIAL[2], skin.DEEP_GLACIAL[3], 0.85)
                btn:SetBackdropBorderColor(
                    skin.STEEL_BLUE[1], skin.STEEL_BLUE[2], skin.STEEL_BLUE[3], 0.8)
                btn._label:SetTextColor(skin.ICY_WHITE[1], skin.ICY_WHITE[2], skin.ICY_WHITE[3], 1)
            end
        end
    end

    return bar
end

----------------------------------------------------------------------
-- The panel itself
----------------------------------------------------------------------

-- Build a collapsed strategy panel. Returns the container frame plus
-- helpful methods attached to it:
--   panel:SetBot(bot)     — bind to a bot record
--   panel:Refresh()       — re-layout pills from current bot state
--   panel:Toggle()        — expand/collapse
--   panel:IsExpanded()    — bool
--   panel:GetExpandedHeight() — total height when expanded (for tile sizing)
function StrategyPanel:Build(parent)
    local skin = DWP.Skin.COLORS
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetHeight(0)
    panel._bot = nil
    panel._expanded = false
    panel._pillsCombat = {}
    panel._pillsNC = {}

    -- Helper to open the add-dropdown for a specific category.
    local function OpenAddForCategory(category)
        if not panel._bot then return end
        local activeList = (category == "combat")
            and panel._bot.strategiesCombat
            or  panel._bot.strategiesNonCombat
        ShowAddDropdown(panel._bot.name, category, activeList, panel)
    end

    -- Enable mouse on the panel so it has some hit area for right-click,
    -- but the primary affordances are the per-section handlers below.
    panel:EnableMouse(true)

    -- Helper: when a preset button is clicked, dispatch to Comm.
    local function OnPresetClick(preset, category)
        if not panel._bot then return end
        local prefix_add    = (category == "combat") and "co +" or "nc +"
        local prefix_remove = (category == "combat") and "co -" or "nc -"
        local activeList = (category == "combat")
            and panel._bot.strategiesCombat
            or  panel._bot.strategiesNonCombat
        local whispers = DWP.Presets:PlanApply(preset, activeList, prefix_add, prefix_remove)
        if #whispers == 0 then
            DWP:Print("already set to " .. preset.label .. ".")
            return
        end
        DWP.Comm:SendBotCommandBatch(panel._bot.name, whispers, 0.2)
        DWP:Print(string.format("applying %s (%d changes)...", preset.label, #whispers))
    end

    -- Combat section.
    local combatSection = CreateFrame("Frame", nil, panel)
    combatSection:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, 0)
    combatSection:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    combatSection:EnableMouse(true)
    combatSection:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then OpenAddForCategory("combat") end
    end)
    panel._combatSection = combatSection

    local combatHeader = combatSection:CreateFontString(nil, "OVERLAY")
    combatHeader:SetFont(DWP.Skin.FONTS.HEADER, 10, "OUTLINE")
    combatHeader:SetTextColor(skin.GLACIAL_CYAN[1], skin.GLACIAL_CYAN[2], skin.GLACIAL_CYAN[3], 1)
    combatHeader:SetPoint("TOPLEFT", combatSection, "TOPLEFT", 0, 0)
    combatHeader:SetText("COMBAT")

    -- Preset bar below the header.
    local combatPresetBar = BuildPresetBar(combatSection, DWP.Presets.COMBAT, "combat", OnPresetClick)
    combatPresetBar:SetPoint("TOPLEFT",  combatSection, "TOPLEFT",  0, -HEADER_HEIGHT)
    combatPresetBar:SetPoint("TOPRIGHT", combatSection, "TOPRIGHT", -40, -HEADER_HEIGHT)  -- reserve room for "+ add"
    panel._combatPresetBar = combatPresetBar

    -- Small "+ add" button at the end of the header row.
    local combatAddBtn = CreateFrame("Button", nil, combatSection)
    combatAddBtn:SetSize(36, HEADER_HEIGHT - 2)
    combatAddBtn:SetPoint("TOPRIGHT", combatSection, "TOPRIGHT", 0, 0)
    local combatAddBg = combatAddBtn:CreateTexture(nil, "BACKGROUND")
    combatAddBg:SetAllPoints(combatAddBtn)
    combatAddBg:SetTexture(skin.DEEP_GLACIAL[1], skin.DEEP_GLACIAL[2], skin.DEEP_GLACIAL[3], 0.8)
    local combatAddText = combatAddBtn:CreateFontString(nil, "OVERLAY")
    combatAddText:SetFont(DWP.Skin.FONTS.HEADER, 10, "OUTLINE")
    combatAddText:SetPoint("CENTER", combatAddBtn, "CENTER", 0, 0)
    combatAddText:SetTextColor(skin.ICY_WHITE[1], skin.ICY_WHITE[2], skin.ICY_WHITE[3], 1)
    combatAddText:SetText("+ add")
    combatAddBtn:SetScript("OnClick", function() OpenAddForCategory("combat") end)
    combatAddBtn:SetScript("OnEnter", function(self)
        combatAddBg:SetTexture(skin.FROST_BLUE[1], skin.FROST_BLUE[2], skin.FROST_BLUE[3], 0.9)
    end)
    combatAddBtn:SetScript("OnLeave", function(self)
        combatAddBg:SetTexture(skin.DEEP_GLACIAL[1], skin.DEEP_GLACIAL[2], skin.DEEP_GLACIAL[3], 0.8)
    end)

    -- Pill container: below the preset bar.
    local combatPillContainer = CreateFrame("Frame", nil, combatSection)
    combatPillContainer:SetPoint("TOPLEFT",
        combatSection, "TOPLEFT",  0, -(HEADER_HEIGHT + PRESET_BAR_HEIGHT + PRESET_BAR_GAP))
    combatPillContainer:SetPoint("TOPRIGHT",
        combatSection, "TOPRIGHT", 0, -(HEADER_HEIGHT + PRESET_BAR_HEIGHT + PRESET_BAR_GAP))
    combatPillContainer:SetHeight(PILL_HEIGHT)
    combatPillContainer:EnableMouse(true)
    combatPillContainer:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then OpenAddForCategory("combat") end
    end)
    panel._combatPillContainer = combatPillContainer

    -- Non-combat section.
    local ncSection = CreateFrame("Frame", nil, panel)
    ncSection:SetPoint("TOPLEFT",  combatSection, "BOTTOMLEFT",  0, -SECTION_GAP)
    ncSection:SetPoint("TOPRIGHT", combatSection, "BOTTOMRIGHT", 0, -SECTION_GAP)
    ncSection:EnableMouse(true)
    ncSection:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then OpenAddForCategory("noncombat") end
    end)
    panel._ncSection = ncSection

    local ncHeader = ncSection:CreateFontString(nil, "OVERLAY")
    ncHeader:SetFont(DWP.Skin.FONTS.HEADER, 10, "OUTLINE")
    ncHeader:SetTextColor(skin.GLACIAL_CYAN[1], skin.GLACIAL_CYAN[2], skin.GLACIAL_CYAN[3], 1)
    ncHeader:SetPoint("TOPLEFT", ncSection, "TOPLEFT", 0, 0)
    ncHeader:SetText("NON-COMBAT")

    -- Non-combat preset bar.
    local ncPresetBar = BuildPresetBar(ncSection, DWP.Presets.NONCOMBAT, "noncombat", OnPresetClick)
    ncPresetBar:SetPoint("TOPLEFT",  ncSection, "TOPLEFT",  0, -HEADER_HEIGHT)
    ncPresetBar:SetPoint("TOPRIGHT", ncSection, "TOPRIGHT", -40, -HEADER_HEIGHT)
    panel._ncPresetBar = ncPresetBar

    -- Small "+ add" button for non-combat row.
    local ncAddBtn = CreateFrame("Button", nil, ncSection)
    ncAddBtn:SetSize(36, HEADER_HEIGHT - 2)
    ncAddBtn:SetPoint("TOPRIGHT", ncSection, "TOPRIGHT", 0, 0)
    local ncAddBg = ncAddBtn:CreateTexture(nil, "BACKGROUND")
    ncAddBg:SetAllPoints(ncAddBtn)
    ncAddBg:SetTexture(skin.DEEP_GLACIAL[1], skin.DEEP_GLACIAL[2], skin.DEEP_GLACIAL[3], 0.8)
    local ncAddText = ncAddBtn:CreateFontString(nil, "OVERLAY")
    ncAddText:SetFont(DWP.Skin.FONTS.HEADER, 10, "OUTLINE")
    ncAddText:SetPoint("CENTER", ncAddBtn, "CENTER", 0, 0)
    ncAddText:SetTextColor(skin.ICY_WHITE[1], skin.ICY_WHITE[2], skin.ICY_WHITE[3], 1)
    ncAddText:SetText("+ add")
    ncAddBtn:SetScript("OnClick", function() OpenAddForCategory("noncombat") end)
    ncAddBtn:SetScript("OnEnter", function(self)
        ncAddBg:SetTexture(skin.FROST_BLUE[1], skin.FROST_BLUE[2], skin.FROST_BLUE[3], 0.9)
    end)
    ncAddBtn:SetScript("OnLeave", function(self)
        ncAddBg:SetTexture(skin.DEEP_GLACIAL[1], skin.DEEP_GLACIAL[2], skin.DEEP_GLACIAL[3], 0.8)
    end)

    local ncPillContainer = CreateFrame("Frame", nil, ncSection)
    ncPillContainer:SetPoint("TOPLEFT",
        ncSection, "TOPLEFT",  0, -(HEADER_HEIGHT + PRESET_BAR_HEIGHT + PRESET_BAR_GAP))
    ncPillContainer:SetPoint("TOPRIGHT",
        ncSection, "TOPRIGHT", 0, -(HEADER_HEIGHT + PRESET_BAR_HEIGHT + PRESET_BAR_GAP))
    ncPillContainer:SetHeight(PILL_HEIGHT)
    ncPillContainer:EnableMouse(true)
    ncPillContainer:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then OpenAddForCategory("noncombat") end
    end)
    panel._ncPillContainer = ncPillContainer

    -- Track the last-built height so the tile knows how much to grow.
    panel._contentHeight = 0

    ----------------------------------------------------------------
    -- Pill-pool helpers. Reusing pill frames avoids churn on refresh.
    ----------------------------------------------------------------

    -- Release all pills in a list (hide + mark free).
    local function ReleasePills(list)
        for _, pill in ipairs(list) do pill:Hide() end
    end

    -- Either pull an unused pill from the list or create a new one.
    local function AcquirePill(list, parent, strat, category, onClick)
        for _, pill in ipairs(list) do
            if not pill:IsShown() then
                -- Re-configure this pill for the new strategy.
                pill._label:SetText(strat)
                pill:SetWidth(MeasurePillWidth(strat))
                pill:SetParent(parent)
                pill:ClearAllPoints()
                pill:SetScript("OnClick", function(self, button)
                    if button == "LeftButton" then
                        if onClick then onClick(strat, category) end
                    end
                end)
                pill:Show()
                return pill
            end
        end
        local pill = BuildPill(parent, strat, category, onClick)
        table.insert(list, pill)
        return pill
    end

    -- Lay out pills in a container using left-to-right wrap.
    -- Returns the final height of the pill area.
    local function LayoutPills(container, pills)
        local w = container:GetWidth()
        if not w or w <= 0 then w = 240 end  -- fallback before size is known

        local cursorX, cursorY = 0, 0
        for _, pill in ipairs(pills) do
            local pw = pill:GetWidth()
            if cursorX > 0 and cursorX + pw > w then
                cursorX = 0
                cursorY = cursorY - (PILL_HEIGHT + ROW_GAP)
            end
            pill:ClearAllPoints()
            pill:SetPoint("TOPLEFT", container, "TOPLEFT", cursorX, cursorY)
            cursorX = cursorX + pw + PILL_GAP
        end

        local rowCount = (cursorY == 0 and 1 or (-cursorY / (PILL_HEIGHT + ROW_GAP) + 1))
        local heightUsed = rowCount * PILL_HEIGHT + (rowCount - 1) * ROW_GAP
        container:SetHeight(math.max(PILL_HEIGHT, heightUsed))
        return heightUsed
    end

    ----------------------------------------------------------------
    -- Public methods
    ----------------------------------------------------------------

    function panel:SetBot(bot)
        self._bot = bot
        if self._expanded then
            self:Refresh()
        end
    end

    function panel:Refresh()
        if not self._bot then return end

        local function RemoveHandler(category)
            return function(stratName, _)
                if not self._bot then return end
                local prefix = (category == "combat") and "co -" or "nc -"
                DWP.Comm:SendBotCommand(self._bot.name, prefix .. stratName)
            end
        end

        ReleasePills(self._pillsCombat)
        local combatStrats = self._bot.strategiesCombat or {}
        local builtCombat = {}
        for _, s in ipairs(combatStrats) do
            table.insert(builtCombat,
                AcquirePill(self._pillsCombat, self._combatPillContainer, s, "combat", RemoveHandler("combat")))
        end
        local combatHeight = LayoutPills(self._combatPillContainer, builtCombat)

        ReleasePills(self._pillsNC)
        local ncStrats = self._bot.strategiesNonCombat or {}
        local builtNC = {}
        for _, s in ipairs(ncStrats) do
            table.insert(builtNC,
                AcquirePill(self._pillsNC, self._ncPillContainer, s, "noncombat", RemoveHandler("noncombat")))
        end
        local ncHeight = LayoutPills(self._ncPillContainer, builtNC)

        -- Update preset highlighting based on the best-matching preset.
        if self._combatPresetBar then
            local id = DWP.Presets:MatchCombat(combatStrats)
            self._combatPresetBar:SetActivePreset(id)
        end
        if self._ncPresetBar then
            local id = DWP.Presets:MatchNonCombat(ncStrats)
            self._ncPresetBar:SetActivePreset(id)
        end

        -- Each section's content: header + preset bar + gap + pill area.
        local combatSectionH = HEADER_HEIGHT + PRESET_BAR_HEIGHT + PRESET_BAR_GAP + combatHeight
        local ncSectionH     = HEADER_HEIGHT + PRESET_BAR_HEIGHT + PRESET_BAR_GAP + ncHeight
        self._combatSection:SetHeight(combatSectionH)
        self._ncSection:SetHeight(ncSectionH)

        self._contentHeight = combatSectionH + SECTION_GAP + ncSectionH
        self:SetHeight(self._contentHeight)
    end

    function panel:Expand()
        self._expanded = true
        self:Show()
        self:Refresh()
        if self._onExpandChanged then self._onExpandChanged(true) end
    end

    function panel:Collapse()
        self._expanded = false
        self:Hide()
        if self._onExpandChanged then self._onExpandChanged(false) end
    end

    function panel:Toggle()
        if self._expanded then self:Collapse() else self:Expand() end
    end

    function panel:IsExpanded() return self._expanded end

    function panel:GetContentHeight() return self._contentHeight or 0 end

    -- The tile wires this up to resize itself when the panel expands.
    function panel:SetOnExpandChanged(fn) self._onExpandChanged = fn end

    panel:Hide()
    return panel
end
