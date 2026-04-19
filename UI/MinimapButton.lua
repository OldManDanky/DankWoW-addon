--[[
    MinimapButton.lua
    A standard draggable circular minimap button using the DankWoW skull
    icon. Click to toggle the main panel; right-click for a simple menu;
    drag to reposition around the minimap perimeter.

    No LibDBIcon dependency — hand-rolled for minimal deps. If the player
    has LibDBIcon installed via another addon, we'll add LDB support in a
    later milestone; for now a single button is enough.
]]

local DWP = DankWoWPlayerbots
local MMB = {}
DWP.MinimapButton = MMB

local button

----------------------------------------------------------------------
-- Position math: given an angle in degrees, place the button on the
-- minimap's perimeter. Uses Minimap's actual dimensions so it adapts to
-- UIs that resize the minimap.
----------------------------------------------------------------------

local function UpdatePosition(angle)
    if not button then return end
    local radius = (Minimap:GetWidth() / 2) + 10
    local rad = math.rad(angle)
    local x = math.cos(rad) * radius
    local y = math.sin(rad) * radius
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Convert cursor position to an angle relative to minimap center.
local function CursorAngle()
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    local dx, dy = cx - mx, cy - my
    return math.deg(math.atan2(dy, dx))
end

----------------------------------------------------------------------
-- Construction
----------------------------------------------------------------------

local function Build()
    local b = CreateFrame("Button", "DankWoWPlayerbotsMinimapButton", Minimap)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:SetSize(32, 32)
    b:SetMovable(true)
    b:EnableMouse(true)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")

    -- Background: a subtle frost-blue circular glow.
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetAllPoints(b)
    bg:SetVertexColor(DWP.Skin.COLORS.ICE_PRIMARY[1],
                      DWP.Skin.COLORS.ICE_PRIMARY[2],
                      DWP.Skin.COLORS.ICE_PRIMARY[3], 0.6)

    -- Icon: the DankWoW skull. Clipped with a circular mask via the
    -- Blizzard TrackingFrameRoundHighlight texture trick would be ideal,
    -- but the simplest path is just using the icon as-is since it already
    -- has transparency.
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(DWP.TEX.ICON_MINIMAP)
    icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    icon:SetSize(22, 22)
    b.icon = icon

    -- Border ring (the classic Blizzard minimap button border).
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)

    -- Highlight on hover.
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    ------------------------------------------------------------------
    -- Interaction
    ------------------------------------------------------------------
    b:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "LeftButton" then
            DWP.MainFrame:Toggle()
        elseif mouseButton == "RightButton" then
            -- Simple right-click menu: toggle lock + reset position.
            -- A proper dropdown comes later. For now, just print options.
            DWP:Print("right-click menu coming in a later milestone.")
        end
    end)

    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cff3FA9FFDankWoW Playerbots|r")
        GameTooltip:AddLine("|cffD8F8F8Left-click|r to toggle the panel", 1, 1, 1)
        GameTooltip:AddLine("|cffD8F8F8Right-click|r for options", 1, 1, 1)
        GameTooltip:AddLine("|cff5A7090Drag|r to reposition", 1, 1, 1)
        local count = #DWP.BotRoster:GetOnlineBots()
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(string.format("|cff98E8F8%d|r bot%s online",
            count, count == 1 and "" or "s"))
        GameTooltip:Show()
    end)

    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Drag: update angle, save to config.
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local angle = CursorAngle()
            DWP.Config.db.minimap.angle = angle
            UpdatePosition(angle)
        end)
    end)

    b:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    return b
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function MMB:Get()
    if not button then
        button = Build()
    end
    return button
end

function MMB:Show()
    local b = self:Get()
    b:Show()
    UpdatePosition(DWP.Config.db.minimap.angle or 210)
    DWP.Config.db.minimap.shown = true
end

function MMB:Hide()
    if button then button:Hide() end
    DWP.Config.db.minimap.shown = false
end
