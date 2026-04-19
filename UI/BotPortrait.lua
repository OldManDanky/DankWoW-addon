--[[
    BotPortrait.lua
    A single bot portrait tile. Renders one bot's:
      - 3D model (or class/race fallback icon if model unavailable)
      - Name (class-colored) + level badge
      - Role pill (Tank / Heal / DPS)
      - HP bar (animated, color-shifts with HP%)
      - Power bar (mana/rage/focus/energy/runic, colored per power type)
      - Target row: target name (danger-red) + target HP bar

    Architecture:
      - Tiles are created via BotPortrait.Acquire() from a pool and released
        back via Release() — not created/destroyed on every roster update.
      - Each tile exposes SetBot(botObj) / Update() methods.
      - Bars animate via a shared OnUpdate handler (one per tile).

    Milestone 3 scope: everything above is live.
    Milestone 4 will add a command row below each tile (follow/attack/etc).
    Milestone 10 will add low-HP shake + event flash animations.
]]

local DWP = DankWoWPlayerbots
local BotPortrait = {}
DWP.BotPortrait = BotPortrait

-- Layout constants (pulled from DWP.UI where possible, overridden here
-- for portrait-specific dimensions).
local TILE_H          = DWP.UI.TILE_HEIGHT
local MODEL_SIZE      = 64      -- square 3D model viewport
local MODEL_PAD       = 8       -- padding inside the tile around the model
local BAR_HP_H        = 14      -- HP bar height
local BAR_POW_H       = 10      -- power bar height
local BAR_TGT_H       = 5       -- target HP bar (thin)
local BAR_GAP         = 3
local TILE_PADDING    = 8

-- Animation constants.
local BAR_ANIM_SECONDS = 0.22
local LOW_HP_THRESHOLD = 0.30
local CRIT_HP_THRESHOLD = 0.15
local LOW_HP_PULSE_HZ  = 1.8

-- Power-type color lookup. Keys are the numeric power types returned by
-- UnitPowerType() in 3.3.5a:
--   0 = Mana, 1 = Rage, 2 = Focus, 3 = Energy, 4 = Happiness (pet),
--   6 = RunicPower
local POWER_COLORS = {
    [0] = DWP.Skin.COLORS.ICE_PRIMARY,     -- mana (blue)
    [1] = { 0.90, 0.18, 0.18, 1 },          -- rage (red)
    [2] = { 0.90, 0.55, 0.20, 1 },          -- focus (orange)
    [3] = { 0.95, 0.90, 0.35, 1 },          -- energy (yellow)
    [6] = DWP.Skin.COLORS.GLACIAL_CYAN,    -- runic (pale cyan)
}
local POWER_COLOR_DEFAULT = DWP.Skin.COLORS.MUTED

local POWER_NAMES = {
    [0] = "mana",
    [1] = "rage",
    [2] = "focus",
    [3] = "energy",
    [6] = "runic",
}

-- Role badge colors. Matches standard WoW role iconography.
local ROLE_COLORS = {
    [DWP.ROLE_TANK]   = { 0.40, 0.70, 1.00, 1 },   -- light blue
    [DWP.ROLE_HEAL]   = { 0.40, 1.00, 0.50, 1 },   -- green
    [DWP.ROLE_DPS]    = { 1.00, 0.50, 0.40, 1 },   -- coral
    [DWP.ROLE_CASTER] = { 0.80, 0.60, 1.00, 1 },   -- purple-ish
    [DWP.ROLE_AUTO]   = DWP.Skin.COLORS.MUTED,
}

local ROLE_LABELS = {
    [DWP.ROLE_TANK]   = "TANK",
    [DWP.ROLE_HEAL]   = "HEAL",
    [DWP.ROLE_DPS]    = "DPS",
    [DWP.ROLE_CASTER] = "DPS",
    [DWP.ROLE_AUTO]   = "—",
}

-- (In chat-fallback mode, bot.class is already the class file name like
-- "WARRIOR" from UnitClass(). No numeric-to-file map needed.)

----------------------------------------------------------------------
-- Pool
----------------------------------------------------------------------

local pool = {}
local activeByName = {}  -- botName -> tile, for fast lookup

----------------------------------------------------------------------
-- Bar helpers
----------------------------------------------------------------------

-- A "bar" is a frame with a background texture and a fill texture.
-- The fill's width is a fraction of the background's width.
--
-- Returns: bar object with methods SetValue(frac), SetColor(rgba),
-- SetText(s), Update(dt).
local function CreateBar(parent, height)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(height)

    -- Background (dark channel).
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(0, 0, 0, 0.75)
    bg:SetAllPoints(bar)
    bar.bg = bg

    -- Border (thin steel-blue).
    local border = bar:CreateTexture(nil, "BORDER")
    border:SetTexture(DWP.Skin.COLORS.STEEL_BLUE[1],
                      DWP.Skin.COLORS.STEEL_BLUE[2],
                      DWP.Skin.COLORS.STEEL_BLUE[3], 0.9)
    border:SetAllPoints(bar)
    -- Border is rendered as a slightly-oversized black tile underneath.
    -- Simplest approach: stack two textures (border and bg+1px inset).
    -- Here we skip the outline for speed; the tile's own border frames it.

    -- Fill (colored, width-anchored left).
    local fill = bar:CreateTexture(nil, "ARTWORK")
    fill:SetTexture(1, 1, 1, 1) -- white, tinted by SetColor
    fill:SetPoint("TOPLEFT",    bar, "TOPLEFT",  1, -1)
    fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 1,  1)
    fill:SetWidth(1)
    bar.fill = fill

    -- Highlight strip along the top of the fill, fakes a gloss.
    local gloss = bar:CreateTexture(nil, "OVERLAY")
    gloss:SetTexture(1, 1, 1, 0.25)
    gloss:SetPoint("TOPLEFT",  fill, "TOPLEFT",  0, 0)
    gloss:SetPoint("TOPRIGHT", fill, "TOPRIGHT", 0, 0)
    gloss:SetHeight(math.max(1, math.floor(height / 3)))
    bar.gloss = gloss

    -- Text overlay (centered).
    local text = bar:CreateFontString(nil, "OVERLAY")
    text:SetFont(DWP.Skin.FONTS.NUMBER, DWP.Skin.FONT_SIZES.BAR_TEXT, "OUTLINE")
    text:SetTextColor(DWP.Skin.COLORS.PURE_ICE[1],
                      DWP.Skin.COLORS.PURE_ICE[2],
                      DWP.Skin.COLORS.PURE_ICE[3], 1)
    text:SetPoint("CENTER", bar, "CENTER", 0, 0)
    bar.text = text

    -- Animation state. `value` is the logical target [0..1]; `displayed`
    -- is the currently-drawn value being tweened toward `value`.
    bar.value     = 0
    bar.displayed = 0

    function bar:SetValue(frac)
        self.value = math.max(0, math.min(1, frac or 0))
    end

    function bar:SetColor(c)
        self.fill:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    end

    function bar:SetText(s)
        self.text:SetText(s or "")
    end

    function bar:Update(dt)
        if self.displayed ~= self.value then
            -- Linear tween over BAR_ANIM_SECONDS.
            local step = dt / BAR_ANIM_SECONDS
            if self.value > self.displayed then
                self.displayed = math.min(self.value, self.displayed + step)
            else
                self.displayed = math.max(self.value, self.displayed - step)
            end
            local w = self:GetWidth()
            if w > 2 then
                self.fill:SetWidth(math.max(1, (w - 2) * self.displayed))
            end
        end
    end

    return bar
end

----------------------------------------------------------------------
-- HP color interpolation: lerp from plague-green (full) through amber
-- (~40%) to danger-red (<15%). Produces a smooth gradient the player
-- can read at a glance.
----------------------------------------------------------------------

local function LerpColor(a, b, t)
    t = math.max(0, math.min(1, t))
    return {
        a[1] + (b[1] - a[1]) * t,
        a[2] + (b[2] - a[2]) * t,
        a[3] + (b[3] - a[3]) * t,
        1,
    }
end

local function HPColorForFraction(frac)
    local good = DWP.Skin.COLORS.HEALTH_GOOD
    local mid  = DWP.Skin.COLORS.HEALTH_MID
    local bad  = DWP.Skin.COLORS.DANGER
    if frac >= 0.6 then
        return good
    elseif frac >= CRIT_HP_THRESHOLD then
        -- Lerp mid<->good across 60% to 15%.
        local t = (frac - CRIT_HP_THRESHOLD) / (0.6 - CRIT_HP_THRESHOLD)
        return LerpColor(mid, good, t)
    else
        -- Lerp bad<->mid across 15% to 0%.
        local t = frac / CRIT_HP_THRESHOLD
        return LerpColor(bad, mid, t)
    end
end

----------------------------------------------------------------------
-- Tile construction
----------------------------------------------------------------------

local function BuildTile(parent)
    local tile = CreateFrame("Frame", nil, parent)
    tile:SetHeight(TILE_H)
    DWP.Skin:ApplyTileLook(tile)
    tile:Hide()

    ------------------------------------------------------------------
    -- Portrait area. In 3.3.5a, PlayerModel doesn't reliably clip its
    -- rendered 3D content to the frame rectangle (model renders based on
    -- internal world coords, not frame bounds). SetCamera, SetPortraitZoom,
    -- and similar workarounds either don't exist or misbehave on this
    -- client version.
    --
    -- Solution: use a static 2D portrait via SetPortraitTexture. This is
    -- what Blizzard's party/target frames use natively — a snapshot of
    -- the unit's head texture, always clipped to the texture region,
    -- guaranteed to fit. Trade-off: not animated. But it always works.
    ------------------------------------------------------------------
    local portrait = tile:CreateTexture(nil, "ARTWORK")
    portrait:SetSize(MODEL_SIZE, MODEL_SIZE)
    portrait:SetPoint("TOPLEFT", tile, "TOPLEFT", MODEL_PAD, -MODEL_PAD)
    tile.portrait = portrait
    -- Kept as 'model' for backward compatibility with other code that
    -- calls :Show() / :Hide() on it.
    tile.model = portrait

    -- A thin frost-blue frame around the portrait.
    local modelBorder = CreateFrame("Frame", nil, tile)
    modelBorder:SetAllPoints(portrait)
    modelBorder:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    modelBorder:SetBackdropBorderColor(
        DWP.Skin.COLORS.ICE_PRIMARY[1],
        DWP.Skin.COLORS.ICE_PRIMARY[2],
        DWP.Skin.COLORS.ICE_PRIMARY[3], 0.8)

    -- Fallback icon shown when the portrait cannot be resolved.
    local fallback = tile:CreateTexture(nil, "ARTWORK")
    fallback:SetAllPoints(portrait)
    fallback:SetTexCoord(0.07, 0.93, 0.07, 0.93)  -- trim default icon border
    fallback:Hide()
    tile.fallback = fallback

    -- Level badge (bottom-right of portrait).
    local lvlBadge = CreateFrame("Frame", nil, tile)
    lvlBadge:SetSize(24, 14)
    lvlBadge:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", 2, -2)
    -- portrait is a texture, not a frame, so we can't call GetFrameLevel
    -- on it. Use the tile's frame level + offset instead.
    lvlBadge:SetFrameLevel(tile:GetFrameLevel() + 2)
    local lvlBg = lvlBadge:CreateTexture(nil, "BACKGROUND")
    lvlBg:SetTexture(0, 0.06, 0.19, 0.95)
    lvlBg:SetAllPoints(lvlBadge)
    local lvlText = lvlBadge:CreateFontString(nil, "OVERLAY")
    lvlText:SetFont(DWP.Skin.FONTS.HEADER, 11, "OUTLINE")
    lvlText:SetTextColor(DWP.Skin.COLORS.GLACIAL_CYAN[1],
                         DWP.Skin.COLORS.GLACIAL_CYAN[2],
                         DWP.Skin.COLORS.GLACIAL_CYAN[3], 1)
    lvlText:SetPoint("CENTER", lvlBadge, "CENTER", 0, 0)
    tile.levelText = lvlText

    ------------------------------------------------------------------
    -- Command bar (bottom of tile): attack, follow, stay, reset.
    -- Anchored first so content above can stop just short of it.
    ------------------------------------------------------------------
    local COMMAND_BAR_H = 20
    local cmdBar = DWP.CommandBar:Build(tile)
    cmdBar:SetPoint("BOTTOMLEFT",  tile, "BOTTOMLEFT",  TILE_PADDING, TILE_PADDING)
    cmdBar:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -TILE_PADDING, TILE_PADDING)
    cmdBar:SetHeight(COMMAND_BAR_H)
    tile.commandBar = cmdBar

    ------------------------------------------------------------------
    -- Strategy panel: sits just above the command bar. Collapsed by
    -- default. When expanded, the tile's height grows to accommodate
    -- the content, and the MainFrame scroll area re-lays out tiles.
    ------------------------------------------------------------------
    local stratPanel
    if DWP.StrategyPanel and DWP.StrategyPanel.Build then
        stratPanel = DWP.StrategyPanel:Build(tile)
        stratPanel:SetPoint("BOTTOMLEFT",
            cmdBar, "TOPLEFT", 0, 4)
        stratPanel:SetPoint("BOTTOMRIGHT",
            cmdBar, "TOPRIGHT", 0, 4)
        tile.strategyPanel = stratPanel

        -- When expanded/collapsed, resize the whole tile and ask the
        -- MainFrame to re-layout tiles in the scroll area.
        stratPanel:SetOnExpandChanged(function(expanded)
            if expanded then
                local extra = stratPanel:GetContentHeight() + 6  -- 6px for gap
                tile:SetHeight(TILE_H + extra)
            else
                tile:SetHeight(TILE_H)
            end
            -- Notify main frame so the scroll area recalculates tile
            -- positions (tiles need to slide down below an expanded one).
            if DWP.MainFrame and DWP.MainFrame.Refresh then
                DWP.MainFrame:Refresh()
            end
        end)
    end

    ------------------------------------------------------------------
    -- Right-side content: name row, HP bar, power bar, target row.
    -- Always sits within the "core tile" area — not affected by
    -- strategy panel expansion.
    ------------------------------------------------------------------
    local content = CreateFrame("Frame", nil, tile)
    content:SetPoint("TOPLEFT",     portrait, "TOPRIGHT", 8,  0)
    content:SetPoint("TOPRIGHT",    tile,     "TOPRIGHT", -TILE_PADDING, -MODEL_PAD)
    -- Content's bottom is at portrait's bottom edge — fixed regardless of
    -- strategy panel expansion.
    content:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", 0, 0)
    content:SetPoint("BOTTOMLEFT",  portrait, "BOTTOMRIGHT", 8, 0)
    tile.content = content

    ------------------------------------------------------------------
    -- Strategy expand/collapse caret button. Placed at top-right of tile.
    ------------------------------------------------------------------
    local caret
    if stratPanel then
        caret = CreateFrame("Button", nil, tile)
        caret:SetSize(14, 14)
        caret:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -6, -6)
        local caretText = caret:CreateFontString(nil, "OVERLAY")
        caretText:SetFont(DWP.Skin.FONTS.HEADER, 10, "OUTLINE")
        caretText:SetPoint("CENTER", caret, "CENTER", 0, 0)
        caretText:SetTextColor(
            DWP.Skin.COLORS.ICE_PRIMARY[1],
            DWP.Skin.COLORS.ICE_PRIMARY[2],
            DWP.Skin.COLORS.ICE_PRIMARY[3], 1)
        caretText:SetText("▸")  -- right-pointing triangle, rotates to ▾ when open
        caret._text = caretText
        caret:SetScript("OnClick", function(self)
            stratPanel:Toggle()
            self._text:SetText(stratPanel:IsExpanded() and "▾" or "▸")
        end)
        caret:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText("Strategies", 1, 1, 1)
            GameTooltip:AddLine(
                stratPanel:IsExpanded() and "Click to collapse." or "Click to expand.",
                0.9, 0.9, 0.9)
            GameTooltip:Show()
        end)
        caret:SetScript("OnLeave", function() GameTooltip:Hide() end)
        tile.caret = caret
    end

    -- Row 1: bot name + role pill.
    local nameText = content:CreateFontString(nil, "OVERLAY")
    nameText:SetFont(DWP.Skin.FONTS.HEADER, DWP.Skin.FONT_SIZES.BOT_NAME, "OUTLINE")
    nameText:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -2)
    nameText:SetJustifyH("LEFT")
    tile.nameText = nameText

    local rolePill = CreateFrame("Frame", nil, content)
    rolePill:SetSize(38, 14)
    rolePill:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -2)
    local rolePillBg = rolePill:CreateTexture(nil, "BACKGROUND")
    rolePillBg:SetAllPoints(rolePill)
    rolePillBg:SetTexture(0, 0, 0, 0.8)
    local rolePillText = rolePill:CreateFontString(nil, "OVERLAY")
    rolePillText:SetFont(DWP.Skin.FONTS.BODY, 9, "OUTLINE")
    rolePillText:SetPoint("CENTER", rolePill, "CENTER", 0, 0)
    tile.rolePill     = rolePill
    tile.rolePillBg   = rolePillBg
    tile.rolePillText = rolePillText

    -- Row 2: HP bar (big).
    local hpBar = CreateBar(content, BAR_HP_H)
    hpBar:SetPoint("TOPLEFT",  nameText, "BOTTOMLEFT",  0, -4)
    hpBar:SetPoint("TOPRIGHT", content,  "TOPRIGHT",    0, -(4 + DWP.Skin.FONT_SIZES.BOT_NAME + 2))
    tile.hpBar = hpBar

    -- Row 3: power bar.
    local powerBar = CreateBar(content, BAR_POW_H)
    powerBar:SetPoint("TOPLEFT",  hpBar, "BOTTOMLEFT",  0, -BAR_GAP)
    powerBar:SetPoint("TOPRIGHT", hpBar, "BOTTOMRIGHT", 0, -BAR_GAP)
    tile.powerBar = powerBar

    -- Row 4: target label + name + thin HP bar.
    local targetRow = CreateFrame("Frame", nil, content)
    targetRow:SetPoint("TOPLEFT",  powerBar, "BOTTOMLEFT",  0, -BAR_GAP - 2)
    targetRow:SetPoint("TOPRIGHT", powerBar, "BOTTOMRIGHT", 0, -BAR_GAP - 2)
    targetRow:SetHeight(12)
    tile.targetRow = targetRow

    local targetLabel = targetRow:CreateFontString(nil, "OVERLAY")
    targetLabel:SetFont(DWP.Skin.FONTS.BODY, DWP.Skin.FONT_SIZES.LABEL, "")
    targetLabel:SetTextColor(DWP.Skin.COLORS.GLACIAL_CYAN[1],
                             DWP.Skin.COLORS.GLACIAL_CYAN[2],
                             DWP.Skin.COLORS.GLACIAL_CYAN[3], 0.65)
    targetLabel:SetText("TARGET")
    targetLabel:SetPoint("LEFT", targetRow, "LEFT", 0, 0)
    tile.targetLabel = targetLabel

    local targetName = targetRow:CreateFontString(nil, "OVERLAY")
    targetName:SetFont(DWP.Skin.FONTS.BODY, DWP.Skin.FONT_SIZES.LABEL + 1, "OUTLINE")
    targetName:SetTextColor(DWP.Skin.COLORS.DANGER[1],
                            DWP.Skin.COLORS.DANGER[2],
                            DWP.Skin.COLORS.DANGER[3], 1)
    targetName:SetJustifyH("LEFT")
    targetName:SetPoint("LEFT", targetLabel, "RIGHT", 6, 0)
    tile.targetName = targetName

    local targetHpBar = CreateBar(targetRow, BAR_TGT_H)
    targetHpBar:SetPoint("BOTTOMLEFT",  targetRow, "BOTTOMLEFT",  0, -2)
    targetHpBar:SetPoint("BOTTOMRIGHT", targetRow, "BOTTOMRIGHT", 0, -2)
    targetHpBar:SetColor(DWP.Skin.COLORS.DANGER)
    tile.targetHpBar = targetHpBar
    -- The target HP bar overlaps the target name row by design; it sits
    -- underneath as a thin accent strip.
    targetHpBar:SetFrameLevel(targetRow:GetFrameLevel() - 1)

    ------------------------------------------------------------------
    -- OnUpdate: drive bar tweens + low-HP pulse.
    ------------------------------------------------------------------
    tile:SetScript("OnUpdate", function(self, dt)
        self.hpBar:Update(dt)
        self.powerBar:Update(dt)
        self.targetHpBar:Update(dt)

        -- Low-HP pulse on the HP bar alpha.
        if self._bot and self.hpBar.value < LOW_HP_THRESHOLD and self._bot.combat then
            local t = (GetTime() * LOW_HP_PULSE_HZ) % 1
            -- Triangle wave: 0..1..0 per period.
            local pulse = t < 0.5 and (t * 2) or ((1 - t) * 2)
            local alpha = 0.55 + (pulse * 0.45)
            self.hpBar.fill:SetAlpha(alpha)
        else
            self.hpBar.fill:SetAlpha(1)
        end

        -- Out-of-combat fade.
        if self._bot then
            local target = self._bot.combat and 1.0 or 0.85
            local cur = self:GetAlpha()
            if math.abs(cur - target) > 0.01 then
                local step = dt * 2.0
                if target > cur then
                    self:SetAlpha(math.min(target, cur + step))
                else
                    self:SetAlpha(math.max(target, cur - step))
                end
            end
        end
    end)

    ------------------------------------------------------------------
    -- Public methods on the tile.
    ------------------------------------------------------------------

    -- Try to bind the 3D model to a live unit. In 3.3.5a, PlayerModel's
    -- SetUnit works on any GUID the client knows about — party members,
    -- raid members, targetable units. For bots that are in our party
    -- (partyN / raidN), this works; otherwise we fall back to a static
    -- class icon.
    --
    -- We try a range of unit IDs to find one whose name matches the bot.
    local function ResolveUnitId(botName)
        for i = 1, 4 do
            local u = "party" .. i
            if UnitExists(u) and UnitName(u) == botName then return u end
        end
        for i = 1, 40 do
            local u = "raid" .. i
            if UnitExists(u) and UnitName(u) == botName then return u end
        end
        return nil
    end

    function tile:SetBot(bot)
        self._bot = bot
        if not bot then
            self:Hide()
            return
        end

        -- Name (class-colored). bot.class is already a class file name string
        -- (like "WARRIOR") in the chat-fallback roster, sourced from UnitClass().
        self.nameText:SetText(bot.name)
        local classFile = bot.class or "WARRIOR"
        DWP.Skin:ApplyClassColor(self.nameText, classFile)

        -- Level.
        self.levelText:SetText(tostring(bot.level or "?"))

        -- Role pill — we don't have role in chat fallback; derive from
        -- combat strategies. Any of ("tank", "heal") in the combat strat
        -- list sets that role; otherwise DPS.
        local role = DWP.ROLE_DPS
        if bot.strategiesCombat then
            for _, s in ipairs(bot.strategiesCombat) do
                if s == "tank" then role = DWP.ROLE_TANK; break
                elseif s == "heal" then role = DWP.ROLE_HEAL; break
                end
            end
        end
        local roleColor = ROLE_COLORS[role] or ROLE_COLORS[DWP.ROLE_AUTO]
        self.rolePillText:SetText(ROLE_LABELS[role] or "?")
        self.rolePillText:SetTextColor(roleColor[1], roleColor[2], roleColor[3], 1)
        self.rolePillBg:SetTexture(roleColor[1] * 0.25,
                                    roleColor[2] * 0.25,
                                    roleColor[3] * 0.25, 0.9)

        -- Portrait snapshot (static). Uses the 2D portrait from the game's
        -- portrait atlas — same source Blizzard's party frames use. Always
        -- clips cleanly to the texture bounds.
        local unitId = bot.unit or ResolveUnitId(bot.name)
        if unitId and UnitExists(unitId) then
            self.fallback:Hide()
            self.portrait:Show()
            SetPortraitTexture(self.portrait, unitId)
        else
            self.portrait:Hide()
            self.fallback:Show()
            self.fallback:SetTexture("Interface\\Icons\\ClassIcon_" .. classFile)
        end

        -- Wire up the command bar so its buttons target this bot.
        if self.commandBar then
            self.commandBar:SetBot(bot.name)
        end

        -- Wire up the strategy panel. If it's already expanded, it'll
        -- refresh its pill layout to reflect current strategies.
        if self.strategyPanel then
            self.strategyPanel:SetBot(bot)
        end

        self:Update()
        self:Show()
    end

    -- Re-read state from the stored bot and push to bars / text. Called
    -- whenever the roster reports this bot changed.
    function tile:Update()
        local bot = self._bot
        if not bot then return end

        -- HP.
        local hpFrac = (bot.hpm and bot.hpm > 0) and (bot.hp / bot.hpm) or 0
        self.hpBar:SetValue(hpFrac)
        self.hpBar:SetColor(HPColorForFraction(hpFrac))
        if bot.hp and bot.hpm then
            self.hpBar:SetText(string.format("%d / %d", bot.hp, bot.hpm))
        else
            self.hpBar:SetText("")
        end

        -- Power. bot.powerType is numeric (from UnitPowerType).
        local pt = bot.powerType or 0
        local powFrac = (bot.mpm and bot.mpm > 0) and (bot.mp / bot.mpm) or 0
        self.powerBar:SetValue(powFrac)
        self.powerBar:SetColor(POWER_COLORS[pt] or POWER_COLOR_DEFAULT)
        local ptName = POWER_NAMES[pt] or "none"
        if ptName == "mana" and bot.mp and bot.mpm then
            self.powerBar:SetText(string.format("%d / %d", bot.mp, bot.mpm))
        elseif ptName ~= "none" and bot.mp then
            self.powerBar:SetText(tostring(bot.mp))
        else
            self.powerBar:SetText("")
        end

        -- Target.
        if bot.target and bot.target ~= "" then
            self.targetName:SetText(bot.target)
            self.targetName:SetTextColor(DWP.Skin.COLORS.DANGER[1],
                                         DWP.Skin.COLORS.DANGER[2],
                                         DWP.Skin.COLORS.DANGER[3], 1)
            local thpFrac = (bot.targetHp or 0) / 100
            self.targetHpBar:SetValue(thpFrac)
            self.targetRow:Show()
        else
            self.targetName:SetText("-")
            self.targetName:SetTextColor(DWP.Skin.COLORS.MUTED[1],
                                         DWP.Skin.COLORS.MUTED[2],
                                         DWP.Skin.COLORS.MUTED[3], 0.7)
            self.targetHpBar:SetValue(0)
        end

        -- If the strategy panel is expanded, keep it in sync with any
        -- newly-polled strategy changes for this bot.
        if self.strategyPanel and self.strategyPanel:IsExpanded() then
            self.strategyPanel:Refresh()
        end
    end

    return tile
end

----------------------------------------------------------------------
-- Public API: pool management
----------------------------------------------------------------------

function BotPortrait:Acquire(parent, bot)
    -- If this bot already has an active tile, return it.
    local existing = activeByName[bot.name]
    if existing then
        existing:SetBot(bot)
        return existing
    end

    -- Pull an unused tile from the pool, or build a new one.
    local tile
    for i, t in ipairs(pool) do
        if not t._bot then
            tile = t
            break
        end
    end
    if not tile then
        tile = BuildTile(parent)
        table.insert(pool, tile)
    else
        -- Re-parent in case the previous parent was different.
        tile:SetParent(parent)
    end

    tile:SetBot(bot)
    activeByName[bot.name] = tile
    return tile
end

function BotPortrait:Release(botName)
    local tile = activeByName[botName]
    if not tile then return end
    tile:Hide()
    tile._bot = nil
    -- Collapse strategy panel so a pool-reused tile starts fresh for
    -- whoever binds to it next.
    if tile.strategyPanel and tile.strategyPanel:IsExpanded() then
        tile.strategyPanel:Collapse()
        if tile.caret then tile.caret._text:SetText("▸") end
    end
    tile:SetHeight(TILE_H)
    activeByName[botName] = nil
end

-- Release all tiles — used on /reload or roster clear.
function BotPortrait:ReleaseAll()
    for name, tile in pairs(activeByName) do
        tile:Hide()
        tile._bot = nil
        if tile.strategyPanel and tile.strategyPanel:IsExpanded() then
            tile.strategyPanel:Collapse()
            if tile.caret then tile.caret._text:SetText("▸") end
        end
        tile:SetHeight(TILE_H)
    end
    activeByName = {}
end

-- Get the tile currently bound to a bot (if any).
function BotPortrait:GetTile(botName)
    return activeByName[botName]
end

-- Expose the tile height so MainFrame can stride correctly.
BotPortrait.TILE_HEIGHT = TILE_H
