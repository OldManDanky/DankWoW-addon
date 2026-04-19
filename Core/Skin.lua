--[[
    Skin.lua
    Centralized visual styling for DankWoW Playerbots.

    Every color, border, and font treatment lives here. Other files call
    Skin:* helpers rather than hard-coding textures/colors, so that the
    entire addon's look can be retuned from one place.

    Design language: "Frozen throne war room" — cold iron, glacier blue,
    weighty borders, frost-glow accents. Not neon, not cartoony.
]]

local DWP = DankWoWPlayerbots

-- The Skin namespace lives under DWP.
local Skin = {}
DWP.Skin = Skin

----------------------------------------------------------------------
-- COLOR PALETTE
-- Extracted from the DankWoW "Wrath of the Lich King" logo. These hex
-- values are locked — don't introduce new ones; compose from these.
----------------------------------------------------------------------

-- Colors are stored as {r, g, b, a} tables in 0-1 range (WoW API format).
local function rgb(r, g, b, a)
    return { r / 255, g / 255, b / 255, a or 1 }
end

Skin.COLORS = {
    -- Backgrounds (darkest to lightest)
    VOID          = rgb(0,   0,   0),       -- #000000 pure black, deepest bg
    FROZEN_NAVY   = rgb(0,   16,  48),      -- #001030 panel base
    DEEP_GLACIAL  = rgb(16,  32,  64),      -- #102040 panel body (elevated)

    -- Borders / structural
    STEEL_BLUE    = rgb(16,  64,  128),     -- #104080 default border
    FROST_BLUE    = rgb(24,  88,  160),     -- #1858A0 secondary accent / hover

    -- Primary accent family
    ICE_PRIMARY   = rgb(63,  169, 255),     -- #3FA9FF main brand accent
    GLACIAL_CYAN  = rgb(152, 232, 248),     -- #98E8F8 highlights
    ICY_WHITE     = rgb(216, 248, 248),     -- #D8F8F8 body text on dark
    PURE_ICE      = rgb(240, 248, 248),     -- #F0F8F8 headlines

    -- Semantic
    HEALTH_GOOD   = rgb(79,  255, 107),     -- #4FFF6B plague-green, healthy
    HEALTH_MID    = rgb(255, 200, 64),      -- #FFC840 amber, 30-60% HP
    DANGER        = rgb(255, 56,  56),      -- #FF3838 low HP / errors
    MUTED         = rgb(90,  112, 144),     -- #5A7090 inactive labels
}

-- Class colors (standard WoW RAID_CLASS_COLORS is available at runtime, but
-- we keep a local copy as a fallback in case the addon loads before
-- RAID_CLASS_COLORS is populated, or for use in login-time UI setup).
Skin.CLASS_COLORS = {
    WARRIOR      = rgb(199, 156, 110),
    PALADIN      = rgb(245, 140, 186),
    HUNTER       = rgb(171, 212, 115),
    ROGUE        = rgb(255, 245, 105),
    PRIEST       = rgb(255, 255, 255),
    DEATHKNIGHT  = rgb(196,  30,  59),
    SHAMAN       = rgb(  0, 112, 221),
    MAGE         = rgb( 64, 199, 235),
    WARLOCK      = rgb(135, 135, 237),
    DRUID        = rgb(255, 125,  10),
}

----------------------------------------------------------------------
-- FONT
-- WoW 3.3.5 ships a handful of usable fonts. "Morpheus" has the chunky
-- fantasy feel we want for headers; "Friz Quadrata" (the default) works
-- for body text but is a bit generic. We'll swap to a bundled font file
-- once we pick one with compatible licensing.
----------------------------------------------------------------------

Skin.FONTS = {
    HEADER = "Fonts\\MORPHEUS.TTF",
    BODY   = "Fonts\\FRIZQT__.TTF",
    NUMBER = "Fonts\\ARIALN.TTF",  -- tabular digits for HP/mana readouts
}

Skin.FONT_SIZES = {
    TITLE      = 18,
    SUBTITLE   = 13,
    BOT_NAME   = 14,
    LABEL      = 10,
    BODY       = 12,
    BAR_TEXT   = 10,
    BUTTON     = 11,
}

----------------------------------------------------------------------
-- BACKDROPS
-- Backdrop tables are reused across panels. Defined once and referenced.
-- The actual texture paths use Blizzard's shipping UI textures so the
-- addon doesn't need to ship its own backdrop tiles.
----------------------------------------------------------------------

Skin.BACKDROPS = {
    -- The main panel: solid-ish dark tile with a thin ice-blue border.
    MAIN_PANEL = {
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    },

    -- A bot portrait tile: slightly lighter than the main panel, with a
    -- double-stroke border (outer dark, inner ice-blue).
    TILE = {
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    },

    -- Bars (HP, mana, target HP): black channel with a thin border.
    BAR = {
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false, tileSize = 0, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    },
}

----------------------------------------------------------------------
-- HELPERS
----------------------------------------------------------------------

-- Apply a standard panel look to a frame: dark fill, frost-blue border,
-- optional inset highlight.
function Skin:ApplyPanelLook(frame, opts)
    opts = opts or {}
    frame:SetBackdrop(self.BACKDROPS.MAIN_PANEL)
    local bg = opts.bgColor or self.COLORS.FROZEN_NAVY
    frame:SetBackdropColor(bg[1], bg[2], bg[3], opts.bgAlpha or 0.92)
    local br = opts.borderColor or self.COLORS.STEEL_BLUE
    frame:SetBackdropBorderColor(br[1], br[2], br[3], 1)
end

-- Apply a "bot tile" look (slightly brighter body, double-stroke border).
function Skin:ApplyTileLook(frame)
    frame:SetBackdrop(self.BACKDROPS.TILE)
    local bg = self.COLORS.DEEP_GLACIAL
    frame:SetBackdropColor(bg[1], bg[2], bg[3], 0.85)
    local br = self.COLORS.STEEL_BLUE
    frame:SetBackdropBorderColor(br[1], br[2], br[3], 1)
end

-- Make a FontString use the standard header treatment: large, icy-white,
-- soft outer shadow to fake the logo's "ice glow".
function Skin:StyleHeaderText(fs)
    fs:SetFont(self.FONTS.HEADER, self.FONT_SIZES.TITLE, "OUTLINE")
    local c = self.COLORS.PURE_ICE
    fs:SetTextColor(c[1], c[2], c[3], 1)
    fs:SetShadowColor(self.COLORS.ICE_PRIMARY[1], self.COLORS.ICE_PRIMARY[2],
                      self.COLORS.ICE_PRIMARY[3], 0.6)
    fs:SetShadowOffset(0, 0)
end

-- Standard body-text treatment.
function Skin:StyleBodyText(fs, size)
    fs:SetFont(self.FONTS.BODY, size or self.FONT_SIZES.BODY, "")
    local c = self.COLORS.ICY_WHITE
    fs:SetTextColor(c[1], c[2], c[3], 1)
end

-- Muted/inactive label treatment (e.g., "TARGET", "CO:", etc.).
function Skin:StyleLabelText(fs, size)
    fs:SetFont(self.FONTS.BODY, size or self.FONT_SIZES.LABEL, "")
    local c = self.COLORS.GLACIAL_CYAN
    fs:SetTextColor(c[1], c[2], c[3], 0.7)
end

-- Class-color a FontString based on a class file name ("WARRIOR", "MAGE", etc.).
function Skin:ApplyClassColor(fs, classFile)
    local c = (RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile])
              or self.CLASS_COLORS[classFile]
    if not c then
        c = { r = self.COLORS.ICY_WHITE[1], g = self.COLORS.ICY_WHITE[2],
              b = self.COLORS.ICY_WHITE[3] }
    end
    -- RAID_CLASS_COLORS uses .r/.g/.b fields; our local copy uses indices.
    local r = c.r or c[1]; local g = c.g or c[2]; local b = c.b or c[3]
    fs:SetTextColor(r, g, b, 1)
end

-- Convenience: create a texture with the brand logo header pre-sized to
-- a parent frame. Returns the texture object.
function Skin:CreateLogoHeader(parent, width, height)
    local tex = parent:CreateTexture(nil, "ARTWORK")
    tex:SetTexture(DWP.TEX.LOGO_HEADER)
    tex:SetWidth(width)
    tex:SetHeight(height)
    return tex
end
