--[[
    BotManagerFrame.lua

    Compact dialog for managing altbots. Attaches to the main panel's
    header "Bots" button (see MainFrame.lua). Provides:

      - Text input: type a name, Enter or [Add] to summon
      - List of known alts: name, status, action button
      - Close button

    Layout (roughly 280×320):

        ┌─ Playerbots ─────────── [×] ┐
        │                             │
        │  Add by name:               │
        │  [_____________]  [Add]     │
        │                             │
        │  ── Known alts ──           │
        │  ╭─────────────────────╮    │
        │  │ Alemid (party) [out]│    │
        │  │ Vuulei (offline)[in]│    │
        │  │ Myhealer       [in] │    │
        │  ╰─────────────────────╯    │
        │                             │
        │  [Close]                    │
        └─────────────────────────────┘

    Style: matches the ice-blue/frost palette used throughout.
]]

local DWP = DankWoWPlayerbots
local BotManagerFrame = {}
DWP.BotManagerFrame = BotManagerFrame

local FRAME_WIDTH    = 280
local FRAME_HEIGHT   = 380
local ROW_HEIGHT     = 22
local ROW_GAP        = 2

local _frame

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

local function BuildFrame()
    local skin = DWP.Skin.COLORS
    local f = CreateFrame("Frame", "DankWoWPlayerbotsBotManagerFrame", UIParent)
    f:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)

    -- Background & border.
    f:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    f:SetBackdropColor(
        skin.VOID[1], skin.VOID[2], skin.VOID[3], 0.95)
    f:SetBackdropBorderColor(
        skin.ICE_PRIMARY[1], skin.ICE_PRIMARY[2], skin.ICE_PRIMARY[3], 0.9)

    -- Dragging.
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

    -- Title bar.
    local titleBg = f:CreateTexture(nil, "ARTWORK")
    titleBg:SetTexture(skin.FROZEN_NAVY[1], skin.FROZEN_NAVY[2], skin.FROZEN_NAVY[3], 1)
    titleBg:SetPoint("TOPLEFT",  f, "TOPLEFT",  2, -2)
    titleBg:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    titleBg:SetHeight(26)

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont(DWP.Skin.FONTS.HEADER, 13, "OUTLINE")
    title:SetTextColor(
        skin.ICE_PRIMARY[1], skin.ICE_PRIMARY[2], skin.ICE_PRIMARY[3], 1)
    title:SetPoint("LEFT", titleBg, "LEFT", 10, 0)
    title:SetText("Playerbots")

    -- Close button.
    local closeBtn = CreateFrame("Button", nil, f)
    closeBtn:SetSize(16, 16)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    local closeText = closeBtn:CreateFontString(nil, "OVERLAY")
    closeText:SetFont(DWP.Skin.FONTS.HEADER, 14, "OUTLINE")
    closeText:SetTextColor(
        skin.DANGER[1], skin.DANGER[2], skin.DANGER[3], 1)
    closeText:SetPoint("CENTER", closeBtn, "CENTER", 0, 1)
    closeText:SetText("×")
    closeBtn:SetScript("OnClick", function() f:Hide() end)
    closeBtn:SetScript("OnEnter", function(self)
        closeText:SetTextColor(1, 0.4, 0.4, 1)
    end)
    closeBtn:SetScript("OnLeave", function(self)
        closeText:SetTextColor(skin.DANGER[1], skin.DANGER[2], skin.DANGER[3], 1)
    end)

    ----------------------------------------------------------------
    -- Body
    ----------------------------------------------------------------

    -- "Add by name:" label.
    local addLabel = f:CreateFontString(nil, "OVERLAY")
    addLabel:SetFont(DWP.Skin.FONTS.BODY, 11, "")
    addLabel:SetTextColor(
        skin.GLACIAL_CYAN[1], skin.GLACIAL_CYAN[2], skin.GLACIAL_CYAN[3], 1)
    addLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -36)
    addLabel:SetText("Add by name:")

    -- EditBox for alt name.
    local edit = CreateFrame("EditBox", nil, f)
    edit:SetSize(FRAME_WIDTH - 90, 22)
    edit:SetPoint("TOPLEFT", addLabel, "BOTTOMLEFT", 0, -4)
    edit:SetFontObject("ChatFontNormal")
    edit:SetTextInsets(6, 6, 2, 2)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(12)
    edit:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    edit:SetBackdropColor(
        skin.VOID[1], skin.VOID[2], skin.VOID[3], 0.95)
    edit:SetBackdropBorderColor(
        skin.STEEL_BLUE[1], skin.STEEL_BLUE[2], skin.STEEL_BLUE[3], 0.9)
    edit:SetTextColor(
        skin.ICY_WHITE[1], skin.ICY_WHITE[2], skin.ICY_WHITE[3], 1)
    f.edit = edit

    -- Add button.
    local function DoAdd()
        local name = edit:GetText()
        if name and name ~= "" then
            if DWP.BotManager:Summon(name) then
                edit:SetText("")
            end
        end
        edit:ClearFocus()
    end

    edit:SetScript("OnEnterPressed", DoAdd)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local addBtn = CreateFrame("Button", nil, f)
    addBtn:SetSize(60, 22)
    addBtn:SetPoint("LEFT", edit, "RIGHT", 6, 0)
    local addBtnBg = addBtn:CreateTexture(nil, "BACKGROUND")
    addBtnBg:SetAllPoints(addBtn)
    addBtnBg:SetTexture(
        skin.FROST_BLUE[1], skin.FROST_BLUE[2], skin.FROST_BLUE[3], 0.9)
    addBtn:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    addBtn:SetBackdropBorderColor(
        skin.ICE_PRIMARY[1], skin.ICE_PRIMARY[2], skin.ICE_PRIMARY[3], 1)
    local addBtnText = addBtn:CreateFontString(nil, "OVERLAY")
    addBtnText:SetFont(DWP.Skin.FONTS.HEADER, 11, "OUTLINE")
    addBtnText:SetTextColor(1, 1, 1, 1)
    addBtnText:SetPoint("CENTER", addBtn, "CENTER", 0, 0)
    addBtnText:SetText("Add")
    addBtn:SetScript("OnClick", DoAdd)
    addBtn:SetScript("OnEnter", function(self)
        addBtnBg:SetTexture(
            skin.ICE_PRIMARY[1], skin.ICE_PRIMARY[2], skin.ICE_PRIMARY[3], 0.9)
    end)
    addBtn:SetScript("OnLeave", function(self)
        addBtnBg:SetTexture(
            skin.FROST_BLUE[1], skin.FROST_BLUE[2], skin.FROST_BLUE[3], 0.9)
    end)

    -- "Add by class" section.
    local classLabel = f:CreateFontString(nil, "OVERLAY")
    classLabel:SetFont(DWP.Skin.FONTS.BODY, 11, "")
    classLabel:SetTextColor(
        skin.GLACIAL_CYAN[1], skin.GLACIAL_CYAN[2], skin.GLACIAL_CYAN[3], 1)
    classLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -95)
    classLabel:SetText("Add random bot by class:")

    -- Row of class icons. 10 WotLK-era classes (no Monk on 3.3.5a).
    local CLASSES = {
        { id = "warrior",     file = "WARRIOR",     label = "Warrior" },
        { id = "paladin",     file = "PALADIN",     label = "Paladin" },
        { id = "hunter",      file = "HUNTER",      label = "Hunter" },
        { id = "rogue",       file = "ROGUE",       label = "Rogue" },
        { id = "priest",      file = "PRIEST",      label = "Priest" },
        { id = "dk",          file = "DEATHKNIGHT", label = "Death Knight" },
        { id = "shaman",      file = "SHAMAN",      label = "Shaman" },
        { id = "mage",        file = "MAGE",        label = "Mage" },
        { id = "warlock",     file = "WARLOCK",     label = "Warlock" },
        { id = "druid",       file = "DRUID",       label = "Druid" },
    }

    local CLASS_ICON_SIZE = 22
    local CLASS_ICON_GAP  = 2
    local classIconsY     = -112

    for i, cls in ipairs(CLASSES) do
        local btn = CreateFrame("Button", nil, f)
        btn:SetSize(CLASS_ICON_SIZE, CLASS_ICON_SIZE)
        btn:SetPoint("TOPLEFT", f, "TOPLEFT",
            14 + (i - 1) * (CLASS_ICON_SIZE + CLASS_ICON_GAP),
            classIconsY)

        -- Thin border (applied first, because SetBackdrop on some 3.3.5a
        -- clients clears existing textures on the frame if called after).
        btn:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        btn:SetBackdropBorderColor(
            skin.STEEL_BLUE[1], skin.STEEL_BLUE[2], skin.STEEL_BLUE[3], 0.8)

        -- Class icon using Blizzard's class-icon atlas. This is the
        -- texture party frames use; it's always present on 3.3.5a.
        -- CLASS_ICON_TCOORDS keys are the uppercase class file names.
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT",     btn, "TOPLEFT",     1, -1)
        icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
        icon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        local tc = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[cls.file]
        if tc then
            icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
        else
            -- Fallback: try the loose ClassIcon file (works for most).
            -- If neither works, the icon just won't render but the
            -- button (with its label in tooltip) still functions.
            icon:SetTexture("Interface\\Icons\\ClassIcon_" .. cls.file)
            icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        end

        -- Hover highlight overlay (on top of the icon).
        local hover = btn:CreateTexture(nil, "OVERLAY")
        hover:SetAllPoints(btn)
        hover:SetTexture(
            skin.ICE_PRIMARY[1], skin.ICE_PRIMARY[2], skin.ICE_PRIMARY[3], 0.35)
        hover:Hide()

        btn:SetScript("OnEnter", function(self)
            hover:Show()
            self:SetBackdropBorderColor(
                skin.ICE_PRIMARY[1], skin.ICE_PRIMARY[2], skin.ICE_PRIMARY[3], 1)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText("Summon " .. cls.label, 1, 1, 1)
            GameTooltip:AddLine(".playerbots bot addclass " .. cls.id,
                skin.MUTED[1], skin.MUTED[2], skin.MUTED[3], false)
            GameTooltip:AddLine("Summons a random bot of this class.", 0.9, 0.9, 0.9, true)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function(self)
            hover:Hide()
            self:SetBackdropBorderColor(
                skin.STEEL_BLUE[1], skin.STEEL_BLUE[2], skin.STEEL_BLUE[3], 0.8)
            GameTooltip:Hide()
        end)
        btn:SetScript("OnClick", function(self)
            DWP.BotManager:SummonClass(cls.id)
        end)
    end

    -- Known alts section header.
    local listLabel = f:CreateFontString(nil, "OVERLAY")
    listLabel:SetFont(DWP.Skin.FONTS.BODY, 11, "")
    listLabel:SetTextColor(
        skin.GLACIAL_CYAN[1], skin.GLACIAL_CYAN[2], skin.GLACIAL_CYAN[3], 1)
    listLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -148)
    listLabel:SetText("Known alts:")

    -- Divider line under section header.
    local dividerTex = f:CreateTexture(nil, "ARTWORK")
    dividerTex:SetTexture(
        skin.STEEL_BLUE[1], skin.STEEL_BLUE[2], skin.STEEL_BLUE[3], 0.5)
    dividerTex:SetHeight(1)
    dividerTex:SetPoint("TOPLEFT",  listLabel, "BOTTOMLEFT",  0, -2)
    dividerTex:SetPoint("TOPRIGHT", f,         "TOPRIGHT",   -14, -151)

    -- Scroll frame for the alt list.
    -- UIPanelScrollFrameTemplate requires a non-nil name so it can
    -- create named child frames (<name>ScrollBar, etc.) internally.
    local scroll = CreateFrame("ScrollFrame", "DankWoWPlayerbotsBotManagerScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",     f, "TOPLEFT",     14, -159)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 44)
    f.scroll = scroll

    local scrollContent = CreateFrame("Frame", nil, scroll)
    scrollContent:SetSize(1, 1)  -- will expand as rows are added
    scroll:SetScrollChild(scrollContent)
    f.scrollContent = scrollContent

    -- Empty-state label (shown when the list is empty).
    local empty = scrollContent:CreateFontString(nil, "OVERLAY")
    empty:SetFont(DWP.Skin.FONTS.BODY, 10, "")
    empty:SetTextColor(
        skin.MUTED[1], skin.MUTED[2], skin.MUTED[3], 1)
    empty:SetPoint("TOP", scrollContent, "TOP", 0, -10)
    empty:SetText("No alts yet. Add one above.")
    f.emptyLabel = empty

    -- Close button (bottom).
    local closeBtm = CreateFrame("Button", nil, f)
    closeBtm:SetSize(70, 22)
    closeBtm:SetPoint("BOTTOM", f, "BOTTOM", 0, 14)
    local closeBtmBg = closeBtm:CreateTexture(nil, "BACKGROUND")
    closeBtmBg:SetAllPoints(closeBtm)
    closeBtmBg:SetTexture(
        skin.DEEP_GLACIAL[1], skin.DEEP_GLACIAL[2], skin.DEEP_GLACIAL[3], 0.9)
    closeBtm:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    closeBtm:SetBackdropBorderColor(
        skin.STEEL_BLUE[1], skin.STEEL_BLUE[2], skin.STEEL_BLUE[3], 0.9)
    local closeBtmText = closeBtm:CreateFontString(nil, "OVERLAY")
    closeBtmText:SetFont(DWP.Skin.FONTS.HEADER, 11, "OUTLINE")
    closeBtmText:SetTextColor(
        skin.ICY_WHITE[1], skin.ICY_WHITE[2], skin.ICY_WHITE[3], 1)
    closeBtmText:SetPoint("CENTER", closeBtm, "CENTER", 0, 0)
    closeBtmText:SetText("Close")
    closeBtm:SetScript("OnClick", function() f:Hide() end)
    closeBtm:SetScript("OnEnter", function(self)
        closeBtmBg:SetTexture(
            skin.FROST_BLUE[1], skin.FROST_BLUE[2], skin.FROST_BLUE[3], 0.9)
    end)
    closeBtm:SetScript("OnLeave", function(self)
        closeBtmBg:SetTexture(
            skin.DEEP_GLACIAL[1], skin.DEEP_GLACIAL[2], skin.DEEP_GLACIAL[3], 0.9)
    end)

    ----------------------------------------------------------------
    -- Row pool for the alt list.
    ----------------------------------------------------------------

    f._rowPool = {}

    local function ReleaseRows()
        for _, row in ipairs(f._rowPool) do row:Hide() end
    end

    local function AcquireRow(name, parent)
        -- Find a free one in the pool first.
        for _, row in ipairs(f._rowPool) do
            if not row:IsShown() then
                row._name = name
                row._nameText:SetText(name)
                row:Show()
                return row
            end
        end
        -- Build a new row.
        local row = CreateFrame("Frame", nil, parent)
        row:SetHeight(ROW_HEIGHT)
        row:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
        })
        row:SetBackdropColor(
            skin.DEEP_GLACIAL[1], skin.DEEP_GLACIAL[2], skin.DEEP_GLACIAL[3], 0.4)

        row._name = name

        -- Name label.
        local nameText = row:CreateFontString(nil, "OVERLAY")
        nameText:SetFont(DWP.Skin.FONTS.BODY, 11, "")
        nameText:SetTextColor(
            skin.ICY_WHITE[1], skin.ICY_WHITE[2], skin.ICY_WHITE[3], 1)
        nameText:SetPoint("LEFT", row, "LEFT", 8, 0)
        nameText:SetText(name)
        row._nameText = nameText

        -- Action button.
        local actionBtn = CreateFrame("Button", nil, row)
        actionBtn:SetSize(58, 18)
        actionBtn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        local abg = actionBtn:CreateTexture(nil, "BACKGROUND")
        abg:SetAllPoints(actionBtn)
        actionBtn:SetBackdrop({
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
        })
        local atxt = actionBtn:CreateFontString(nil, "OVERLAY")
        atxt:SetFont(DWP.Skin.FONTS.HEADER, 10, "OUTLINE")
        atxt:SetPoint("CENTER", actionBtn, "CENTER", 0, 0)
        row._actionBtn = actionBtn
        row._actionBg  = abg
        row._actionText = atxt

        -- Forget button (tiny × at the far-right, to the left of action).
        local forgetBtn = CreateFrame("Button", nil, row)
        forgetBtn:SetSize(14, 14)
        forgetBtn:SetPoint("RIGHT", actionBtn, "LEFT", -4, 0)
        local forgetText = forgetBtn:CreateFontString(nil, "OVERLAY")
        forgetText:SetFont(DWP.Skin.FONTS.HEADER, 12, "OUTLINE")
        forgetText:SetPoint("CENTER", forgetBtn, "CENTER", 0, 0)
        forgetText:SetTextColor(skin.MUTED[1], skin.MUTED[2], skin.MUTED[3], 0.8)
        forgetText:SetText("×")
        forgetBtn:SetScript("OnClick", function(self)
            DWP.BotManager:Forget(row._name)
        end)
        forgetBtn:SetScript("OnEnter", function(self)
            forgetText:SetTextColor(skin.DANGER[1], skin.DANGER[2], skin.DANGER[3], 1)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText("Forget", 1, 1, 1)
            GameTooltip:AddLine("Remove from known-alts list.", 0.9, 0.9, 0.9)
            GameTooltip:AddLine("(Does not dismiss an active bot.)", 0.9, 0.9, 0.9)
            GameTooltip:Show()
        end)
        forgetBtn:SetScript("OnLeave", function(self)
            forgetText:SetTextColor(skin.MUTED[1], skin.MUTED[2], skin.MUTED[3], 0.8)
            GameTooltip:Hide()
        end)

        table.insert(f._rowPool, row)
        return row
    end

    -- Update a row's action button state based on current status.
    local function UpdateRow(row)
        local status = DWP.BotManager:GetStatus(row._name)
        if status == "party" then
            -- In party → "Dismiss"
            row._actionBg:SetTexture(0.6, 0.2, 0.2, 0.9)
            row._actionText:SetText("Dismiss")
            row._actionText:SetTextColor(1, 0.9, 0.9, 1)
            row:SetBackdropColor(
                skin.FROST_BLUE[1] * 0.5, skin.FROST_BLUE[2] * 0.5, skin.FROST_BLUE[3] * 0.5, 0.5)
            row._actionBtn:SetScript("OnClick", function(self)
                DWP.BotManager:Dismiss(row._name)
            end)
            row._actionBtn:SetBackdropBorderColor(
                skin.DANGER[1], skin.DANGER[2], skin.DANGER[3], 0.8)
        else
            -- Not in party → "Summon"
            row._actionBg:SetTexture(
                skin.FROST_BLUE[1], skin.FROST_BLUE[2], skin.FROST_BLUE[3], 0.9)
            row._actionText:SetText("Summon")
            row._actionText:SetTextColor(1, 1, 1, 1)
            row:SetBackdropColor(
                skin.DEEP_GLACIAL[1], skin.DEEP_GLACIAL[2], skin.DEEP_GLACIAL[3], 0.4)
            row._actionBtn:SetScript("OnClick", function(self)
                DWP.BotManager:Summon(row._name)
            end)
            row._actionBtn:SetBackdropBorderColor(
                skin.ICE_PRIMARY[1], skin.ICE_PRIMARY[2], skin.ICE_PRIMARY[3], 0.8)
        end
    end

    ----------------------------------------------------------------
    -- Refresh: repopulate the list from BotManager + roster state.
    ----------------------------------------------------------------

    function f:Refresh()
        ReleaseRows()
        local alts = DWP.BotManager:GetKnownAlts()

        if #alts == 0 then
            self.emptyLabel:Show()
            self.scrollContent:SetHeight(40)
            return
        end
        self.emptyLabel:Hide()

        local usedWidth = scroll:GetWidth()
        local y = 0
        for _, name in ipairs(alts) do
            local row = AcquireRow(name, self.scrollContent)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT",  self.scrollContent, "TOPLEFT",  0, -y)
            row:SetPoint("TOPRIGHT", self.scrollContent, "TOPRIGHT", 0, -y)
            UpdateRow(row)
            y = y + ROW_HEIGHT + ROW_GAP
        end

        self.scrollContent:SetWidth(usedWidth)
        self.scrollContent:SetHeight(math.max(1, y))
    end

    ----------------------------------------------------------------
    -- Auto-refresh on roster changes and list changes.
    ----------------------------------------------------------------

    DWP.BotRoster:Subscribe(function() if f:IsShown() then f:Refresh() end end)
    DWP.BotManager:Subscribe(function() if f:IsShown() then f:Refresh() end end)

    f:SetScript("OnShow", function(self) self:Refresh() end)
    f:Hide()
    return f
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function BotManagerFrame:Get()
    if not _frame then _frame = BuildFrame() end
    return _frame
end

function BotManagerFrame:Show()
    self:Get():Show()
end

function BotManagerFrame:Hide()
    self:Get():Hide()
end

function BotManagerFrame:Toggle()
    local f = self:Get()
    if f:IsShown() then f:Hide() else f:Show() end
end
