--[[
    MainFrame.lua
    The main dockable panel: logo header, draggable/resizable body, scroll
    area for bot portrait tiles, footer status bar.

    Milestone 1 scope: structurally complete but visually empty body.
    Portraits get added in milestone 3 by BotPortrait.lua, which creates
    tiles as children of self.content (the ScrollFrame's content widget).

    The panel:
      - Is draggable by its header.
      - Saves position on drag-stop.
      - Can be locked via slash command / right-click menu.
      - Resizable by a corner grip (optional, gated on Config.panel.locked).
      - Pops onto screen at the saved position / size on PLAYER_ENTERING_WORLD.

    Magnetic screen-edge snapping is a nice-to-have; deferred to later.
]]

local DWP = DankWoWPlayerbots
local MainFrame = {}
DWP.MainFrame = MainFrame

-- The Lua "frame object" this module manages. Created lazily on first
-- Toggle/Show call so ADDON_LOADED doesn't pay for frame creation before
-- we know we'll actually display it.
local frame

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

local function BuildFrame()
    local f = CreateFrame("Frame", "DankWoWPlayerbotsMainFrame", UIParent)
    f:SetFrameStrata("MEDIUM")
    f:SetSize(DWP.UI.PANEL_WIDTH, DWP.UI.PANEL_HEIGHT)
    f:SetMovable(true)
    f:SetResizable(true)
    f:SetMinResize(320, 320)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:Hide()

    -- Backdrop: dark frozen-navy with ice-blue border.
    DWP.Skin:ApplyPanelLook(f)

    ------------------------------------------------------------------
    -- Header: logo on the left, close button on the right, drag anywhere.
    ------------------------------------------------------------------
    local header = CreateFrame("Frame", nil, f)
    header:SetHeight(DWP.UI.HEADER_HEIGHT)
    header:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 0)
    header:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        if not DWP.Config:IsPanelLocked() then
            f:StartMoving()
        end
    end)
    header:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local point, _, relPoint, xOfs, yOfs = f:GetPoint(1)
        DWP.Config:SetPanelPos(point, relPoint, xOfs, yOfs)
    end)
    f.header = header

    -- Header background: a darker strip to visually anchor the logo. Thin
    -- ice-blue divider along the bottom edge.
    local headerBg = header:CreateTexture(nil, "BACKGROUND")
    headerBg:SetTexture(0, 0, 0, 0.6)
    headerBg:SetAllPoints(header)

    local divider = header:CreateTexture(nil, "BORDER")
    divider:SetTexture(DWP.Skin.COLORS.ICE_PRIMARY[1],
                       DWP.Skin.COLORS.ICE_PRIMARY[2],
                       DWP.Skin.COLORS.ICE_PRIMARY[3], 0.8)
    divider:SetHeight(1)
    divider:SetPoint("BOTTOMLEFT",  header, "BOTTOMLEFT",  4, 0)
    divider:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", -4, 0)

    -- Logo texture: sits on the left, vertically centered, scaled to fit.
    -- Our header asset is 512x256 (2:1). At header height 64 it renders 128
    -- wide. That leaves plenty of room for the close button and future
    -- header controls on the right.
    local logoHeight = DWP.UI.HEADER_HEIGHT - 8
    local logoWidth  = logoHeight * 2
    local logo = header:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(DWP.TEX.LOGO_HEADER)
    logo:SetSize(logoWidth, logoHeight)
    logo:SetPoint("LEFT", header, "LEFT", 8, 0)
    f.logo = logo

    -- Subtitle text to the right of the logo.
    local subtitle = header:CreateFontString(nil, "OVERLAY")
    DWP.Skin:StyleLabelText(subtitle, DWP.Skin.FONT_SIZES.SUBTITLE)
    subtitle:SetText("PLAYERBOTS")
    subtitle:SetPoint("LEFT", logo, "RIGHT", 6, 0)
    f.subtitle = subtitle

    -- Close button (top-right corner, minimal).
    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", header, "TOPRIGHT", -6, -6)
    closeBtn:EnableMouse(true)
    local closeText = closeBtn:CreateFontString(nil, "OVERLAY")
    DWP.Skin:StyleBodyText(closeText, 16)
    closeText:SetText("X")
    closeText:SetPoint("CENTER", closeBtn, "CENTER", 0, 1)
    closeBtn:SetScript("OnEnter", function()
        local c = DWP.Skin.COLORS.DANGER
        closeText:SetTextColor(c[1], c[2], c[3], 1)
    end)
    closeBtn:SetScript("OnLeave", function()
        local c = DWP.Skin.COLORS.ICY_WHITE
        closeText:SetTextColor(c[1], c[2], c[3], 1)
    end)
    closeBtn:SetScript("OnClick", function() f:Hide() end)
    f.closeBtn = closeBtn

    -- Lock toggle button, left of close.
    local lockBtn = CreateFrame("Button", nil, header)
    lockBtn:SetSize(20, 20)
    lockBtn:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)
    local lockText = lockBtn:CreateFontString(nil, "OVERLAY")
    DWP.Skin:StyleBodyText(lockText, 12)
    lockBtn:SetScript("OnShow", function()
        lockText:SetText(DWP.Config:IsPanelLocked() and "[L]" or "[ ]")
    end)
    lockText:SetPoint("CENTER", lockBtn, "CENTER", 0, 0)
    lockBtn:SetScript("OnEnter", function()
        local c = DWP.Skin.COLORS.GLACIAL_CYAN
        lockText:SetTextColor(c[1], c[2], c[3], 1)
    end)
    lockBtn:SetScript("OnLeave", function()
        local c = DWP.Skin.COLORS.ICY_WHITE
        lockText:SetTextColor(c[1], c[2], c[3], 1)
    end)
    lockBtn:SetScript("OnClick", function()
        DWP.Config:SetPanelLocked(not DWP.Config:IsPanelLocked())
        lockText:SetText(DWP.Config:IsPanelLocked() and "[L]" or "[ ]")
    end)
    f.lockBtn = lockBtn

    -- Bots management button (left of lock).
    local botsBtn = CreateFrame("Button", nil, header)
    botsBtn:SetSize(48, 20)
    botsBtn:SetPoint("RIGHT", lockBtn, "LEFT", -4, 0)
    local botsBtnBg = botsBtn:CreateTexture(nil, "BACKGROUND")
    botsBtnBg:SetAllPoints(botsBtn)
    botsBtnBg:SetTexture(
        DWP.Skin.COLORS.DEEP_GLACIAL[1],
        DWP.Skin.COLORS.DEEP_GLACIAL[2],
        DWP.Skin.COLORS.DEEP_GLACIAL[3], 0.8)
    botsBtn:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    botsBtn:SetBackdropBorderColor(
        DWP.Skin.COLORS.STEEL_BLUE[1],
        DWP.Skin.COLORS.STEEL_BLUE[2],
        DWP.Skin.COLORS.STEEL_BLUE[3], 0.8)
    local botsBtnText = botsBtn:CreateFontString(nil, "OVERLAY")
    botsBtnText:SetFont(DWP.Skin.FONTS.HEADER, 11, "OUTLINE")
    botsBtnText:SetTextColor(
        DWP.Skin.COLORS.ICY_WHITE[1],
        DWP.Skin.COLORS.ICY_WHITE[2],
        DWP.Skin.COLORS.ICY_WHITE[3], 1)
    botsBtnText:SetPoint("CENTER", botsBtn, "CENTER", 0, 0)
    botsBtnText:SetText("Bots")
    botsBtn:SetScript("OnClick", function()
        if DWP.BotManagerFrame then DWP.BotManagerFrame:Toggle() end
    end)
    botsBtn:SetScript("OnEnter", function(self)
        botsBtnBg:SetTexture(
            DWP.Skin.COLORS.FROST_BLUE[1],
            DWP.Skin.COLORS.FROST_BLUE[2],
            DWP.Skin.COLORS.FROST_BLUE[3], 0.9)
        self:SetBackdropBorderColor(
            DWP.Skin.COLORS.ICE_PRIMARY[1],
            DWP.Skin.COLORS.ICE_PRIMARY[2],
            DWP.Skin.COLORS.ICE_PRIMARY[3], 1)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Manage playerbots", 1, 1, 1)
        GameTooltip:AddLine("Add, summon, or dismiss altbots.", 0.9, 0.9, 0.9)
        GameTooltip:Show()
    end)
    botsBtn:SetScript("OnLeave", function(self)
        botsBtnBg:SetTexture(
            DWP.Skin.COLORS.DEEP_GLACIAL[1],
            DWP.Skin.COLORS.DEEP_GLACIAL[2],
            DWP.Skin.COLORS.DEEP_GLACIAL[3], 0.8)
        self:SetBackdropBorderColor(
            DWP.Skin.COLORS.STEEL_BLUE[1],
            DWP.Skin.COLORS.STEEL_BLUE[2],
            DWP.Skin.COLORS.STEEL_BLUE[3], 0.8)
        GameTooltip:Hide()
    end)
    f.botsBtn = botsBtn

    -- Options gear button (left of Bots button).
    local optsBtn = CreateFrame("Button", nil, header)
    optsBtn:SetSize(24, 20)
    optsBtn:SetPoint("RIGHT", botsBtn, "LEFT", -4, 0)
    local optsBtnBg = optsBtn:CreateTexture(nil, "BACKGROUND")
    optsBtnBg:SetAllPoints(optsBtn)
    optsBtnBg:SetTexture(
        DWP.Skin.COLORS.DEEP_GLACIAL[1],
        DWP.Skin.COLORS.DEEP_GLACIAL[2],
        DWP.Skin.COLORS.DEEP_GLACIAL[3], 0.8)
    optsBtn:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    optsBtn:SetBackdropBorderColor(
        DWP.Skin.COLORS.STEEL_BLUE[1],
        DWP.Skin.COLORS.STEEL_BLUE[2],
        DWP.Skin.COLORS.STEEL_BLUE[3], 0.8)
    local optsBtnText = optsBtn:CreateFontString(nil, "OVERLAY")
    optsBtnText:SetFont(DWP.Skin.FONTS.HEADER, 12, "OUTLINE")
    optsBtnText:SetTextColor(
        DWP.Skin.COLORS.ICY_WHITE[1],
        DWP.Skin.COLORS.ICY_WHITE[2],
        DWP.Skin.COLORS.ICY_WHITE[3], 1)
    optsBtnText:SetPoint("CENTER", optsBtn, "CENTER", 0, 0)
    optsBtnText:SetText("⚙")
    optsBtn:SetScript("OnClick", function()
        if DWP.OptionsPanel then DWP.OptionsPanel:Show() end
    end)
    optsBtn:SetScript("OnEnter", function(self)
        optsBtnBg:SetTexture(
            DWP.Skin.COLORS.FROST_BLUE[1],
            DWP.Skin.COLORS.FROST_BLUE[2],
            DWP.Skin.COLORS.FROST_BLUE[3], 0.9)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Options", 1, 1, 1)
        GameTooltip:AddLine("Open the settings panel.", 0.9, 0.9, 0.9)
        GameTooltip:Show()
    end)
    optsBtn:SetScript("OnLeave", function(self)
        optsBtnBg:SetTexture(
            DWP.Skin.COLORS.DEEP_GLACIAL[1],
            DWP.Skin.COLORS.DEEP_GLACIAL[2],
            DWP.Skin.COLORS.DEEP_GLACIAL[3], 0.8)
        GameTooltip:Hide()
    end)
    f.optsBtn = optsBtn

    ------------------------------------------------------------------
    -- Body: scroll frame that will contain bot portrait tiles.
    ------------------------------------------------------------------
    local scroll = CreateFrame("ScrollFrame", "DankWoWPlayerbotsScroll", f,
                               "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     header, "BOTTOMLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", f,      "BOTTOMRIGHT", -28, 24)
    f.scroll = scroll

    -- Skin the scroll bar: the template provides one, but it's Blizzard
    -- gold. Re-tint its handle to ice-blue.
    local scrollBar = _G[scroll:GetName() .. "ScrollBar"]
    if scrollBar then
        local thumb = scrollBar:GetThumbTexture()
        if thumb then
            thumb:SetVertexColor(DWP.Skin.COLORS.ICE_PRIMARY[1],
                                 DWP.Skin.COLORS.ICE_PRIMARY[2],
                                 DWP.Skin.COLORS.ICE_PRIMARY[3], 1)
        end
    end

    -- Content frame that holds the tiles. The ScrollFrame needs a child to
    -- actually scroll; its width matches the scroll area, height grows with
    -- content.
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)  -- will be resized by the tile layout.
    scroll:SetScrollChild(content)
    f.content = content

    -- Empty-state message: shown when no bots are known.
    local empty = content:CreateFontString(nil, "OVERLAY")
    DWP.Skin:StyleLabelText(empty, DWP.Skin.FONT_SIZES.BODY)
    empty:SetText("No playerbots active.\n\nAdd an alt with |cff98E8F8.playerbots bot add <name>|r\nor invite a random bot from the world.")
    empty:SetJustifyH("CENTER")
    empty:SetJustifyV("MIDDLE")
    empty:SetPoint("CENTER", scroll, "CENTER", 0, 0)
    f.emptyLabel = empty

    ------------------------------------------------------------------
    -- Footer: status line at the bottom.
    ------------------------------------------------------------------
    local footer = CreateFrame("Frame", nil, f)
    footer:SetHeight(20)
    footer:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",  0, 0)
    footer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)

    local footerBg = footer:CreateTexture(nil, "BACKGROUND")
    footerBg:SetTexture(0, 0, 0, 0.5)
    footerBg:SetAllPoints(footer)

    local footerDiv = footer:CreateTexture(nil, "BORDER")
    footerDiv:SetTexture(DWP.Skin.COLORS.STEEL_BLUE[1],
                         DWP.Skin.COLORS.STEEL_BLUE[2],
                         DWP.Skin.COLORS.STEEL_BLUE[3], 0.8)
    footerDiv:SetHeight(1)
    footerDiv:SetPoint("TOPLEFT",  footer, "TOPLEFT",  4, 0)
    footerDiv:SetPoint("TOPRIGHT", footer, "TOPRIGHT", -4, 0)

    local status = footer:CreateFontString(nil, "OVERLAY")
    DWP.Skin:StyleLabelText(status, DWP.Skin.FONT_SIZES.LABEL)
    status:SetPoint("LEFT", footer, "LEFT", 8, 0)
    f.statusLeft = status

    local version = footer:CreateFontString(nil, "OVERLAY")
    DWP.Skin:StyleLabelText(version, DWP.Skin.FONT_SIZES.LABEL)
    version:SetText("v" .. DWP.VERSION)
    version:SetPoint("RIGHT", footer, "RIGHT", -8, 0)
    f.statusRight = version

    ------------------------------------------------------------------
    -- Resize grip (bottom-right).
    ------------------------------------------------------------------
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    grip:EnableMouse(true)
    grip:RegisterForDrag("LeftButton")
    local gripTex = grip:CreateTexture(nil, "OVERLAY")
    gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    gripTex:SetAllPoints(grip)
    gripTex:SetVertexColor(DWP.Skin.COLORS.ICE_PRIMARY[1],
                           DWP.Skin.COLORS.ICE_PRIMARY[2],
                           DWP.Skin.COLORS.ICE_PRIMARY[3], 0.8)
    grip:SetScript("OnDragStart", function()
        if not DWP.Config:IsPanelLocked() then
            f:StartSizing("BOTTOMRIGHT")
        end
    end)
    grip:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        DWP.Config.db.panel.width  = f:GetWidth()
        DWP.Config.db.panel.height = f:GetHeight()
    end)

    ------------------------------------------------------------------
    -- Roster subscription: coalesce rapid updates into one refresh per
    -- frame via an OnUpdate debouncer. Many unit events can fire in the
    -- same tick (UNIT_HEALTH, UNIT_POWER, UNIT_TARGET all at once when
    -- a bot takes damage mid-combat) — we want one layout pass, not N.
    ------------------------------------------------------------------
    local refreshPending = false
    local debounceFrame = CreateFrame("Frame", nil, f)
    debounceFrame:Hide()
    debounceFrame:SetScript("OnUpdate", function(self)
        self:Hide()
        refreshPending = false
        MainFrame:Refresh()
    end)

    DWP.BotRoster:Subscribe(function(botName, changeType)
        if refreshPending then return end
        refreshPending = true
        debounceFrame:Show()   -- next OnUpdate tick will fire Refresh once
    end)

    return f
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function MainFrame:Get()
    if not frame then
        frame = BuildFrame()
        self:ApplyPosition()
        self:ApplySize()
    end
    return frame
end

function MainFrame:ApplyPosition()
    local f = self:Get()
    local point, relPoint, x, y = DWP.Config:GetPanelPos()
    f:ClearAllPoints()
    f:SetPoint(point, UIParent, relPoint, x, y)
end

function MainFrame:ApplySize()
    local f = self:Get()
    local p = DWP.Config.db.panel
    f:SetSize(p.width or DWP.UI.PANEL_WIDTH, p.height or DWP.UI.PANEL_HEIGHT)
    f:SetScale(p.scale or 1.0)
    f:SetAlpha(p.alpha or 1.0)
end

function MainFrame:Show()
    local f = self:Get()
    f:Show()
    DWP.Config.db.panel.shown = true
    self:Refresh()
end

function MainFrame:Hide()
    if frame then frame:Hide() end
    DWP.Config.db.panel.shown = false
end

function MainFrame:Toggle()
    local f = self:Get()
    if f:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-- Called by the roster subscription and directly from Show().
-- Builds/updates/releases tiles to reflect the current roster state,
-- then stacks them vertically in the scroll content area.
function MainFrame:Refresh()
    if not frame then return end

    local bots = DWP.BotRoster:GetOnlineBots()
    local count = #bots

    -- Status line.
    if count == 0 then
        frame.emptyLabel:Show()
        frame.statusLeft:SetText("|cff5A7090awaiting playerbots...|r")
    else
        frame.emptyLabel:Hide()
        frame.statusLeft:SetText(string.format("|cff98E8F8%d|r bot%s online",
            count, count == 1 and "" or "s"))
    end

    -- Nothing more to do without the portrait module.
    if not DWP.BotPortrait then return end

    -- Release tiles for bots that are no longer online.
    -- First, build a set of currently-online names.
    local onlineSet = {}
    for _, b in ipairs(bots) do onlineSet[b.name] = true end

    -- Walk the roster table (which includes offline entries the UI may
    -- still be holding) and release any whose tile is stale.
    for name, _ in pairs(DWP.BotRoster.bots) do
        if not onlineSet[name] then
            DWP.BotPortrait:Release(name)
        end
    end

    -- Acquire + position tiles for online bots.
    -- Tiles can have variable heights when the strategy panel is expanded,
    -- so we track an accumulator y-offset instead of using a fixed row height.
    local gap = DWP.UI.TILE_GAP
    local baseH = DWP.BotPortrait.TILE_HEIGHT
    local scrollWidth = frame.scroll:GetWidth()
    local yOffset = 0

    for i, bot in ipairs(bots) do
        local tile = DWP.BotPortrait:Acquire(frame.content, bot)
        tile:ClearAllPoints()
        tile:SetPoint("TOPLEFT",  frame.content, "TOPLEFT",  0, -yOffset)
        tile:SetPoint("TOPRIGHT", frame.content, "TOPRIGHT", 0, -yOffset)
        tile:Update()

        -- Use the tile's actual height (which the tile itself sets based
        -- on its expand state). Default to baseH if height is unset.
        local th = tile:GetHeight()
        if not th or th <= 0 then th = baseH end
        yOffset = yOffset + th + gap
    end

    -- Resize the scroll content so the scrollbar knows the full height.
    frame.content:SetWidth(scrollWidth)
    frame.content:SetHeight(math.max(1, yOffset))
end
