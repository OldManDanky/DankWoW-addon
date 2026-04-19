--[[
    OptionsPanel.lua

    Settings UI. Registers with Blizzard's Interface Options (ESC >
    Interface > AddOns > DankWoW Playerbots) and opens standalone via
    /dwp options or the header gear button.

    Layout: a single scrolling frame with labeled sections. Controls are
    bound to DWP.Config.db paths; changes are applied immediately and
    persisted via the SavedVariable mechanism on logout.

    Widgets used:
      - CheckButtonTemplate        — boolean toggles
      - OptionsSliderTemplate      — numeric ranges
      - UIDropDownMenuTemplate     — enumerated choices

    All widgets are plain Blizzard templates (not custom ice-styled) so
    the panel looks native inside the Blizzard options UI. The standalone
    dialog uses the same frame, so it looks consistent either way.
]]

local DWP = DankWoWPlayerbots
local OptionsPanel = {}
DWP.OptionsPanel = OptionsPanel

local FRAME_NAME = "DankWoWPlayerbotsOptionsFrame"
local _frame   -- memoized

----------------------------------------------------------------------
-- Widget builders — minimal wrappers around Blizzard templates.
----------------------------------------------------------------------

local nextWidgetId = 0
local function uniqueName(prefix)
    nextWidgetId = nextWidgetId + 1
    return prefix .. nextWidgetId
end

-- Section header text.
local function BuildSectionHeader(parent, text, yOfs)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, yOfs)
    fs:SetText(text)
    fs:SetTextColor(1, 0.82, 0)  -- Blizzard gold, standard for section headers
    return fs
end

-- Checkbox. `getter()` returns current bool; `setter(b)` applies new bool.
local function BuildCheckbox(parent, label, tooltip, getter, setter, yOfs)
    local cb = CreateFrame("CheckButton", uniqueName("DWPOptCB"), parent, "InterfaceOptionsCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, yOfs)
    _G[cb:GetName() .. "Text"]:SetText(label)
    cb.tooltipText = tooltip
    cb:SetScript("OnShow", function(self) self:SetChecked(getter()) end)
    cb:SetScript("OnClick", function(self) setter(self:GetChecked() and true or false) end)
    return cb
end

-- Slider. min/max/step are the numeric range; `getter/setter` bind to state.
local function BuildSlider(parent, label, tooltip, min, max, step, getter, setter, formatFn, yOfs)
    local name = uniqueName("DWPOptSlider")
    local sl = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    sl:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, yOfs)
    sl:SetWidth(200)
    sl:SetMinMaxValues(min, max)
    sl:SetValueStep(step)
    -- SetObeyStepOnDrag(true) was added post-3.3.5; omitted for client compat.
    _G[name .. "Text"]:SetText(label)
    _G[name .. "Low"]:SetText(tostring(min))
    _G[name .. "High"]:SetText(tostring(max))
    sl.tooltipText = tooltip

    -- Current-value label shown to the right of the slider.
    local valLabel = sl:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valLabel:SetPoint("LEFT", sl, "RIGHT", 10, 0)

    local function updateLabel(v)
        valLabel:SetText(formatFn and formatFn(v) or tostring(v))
    end

    sl:SetScript("OnShow", function(self)
        local v = getter()
        self:SetValue(v)
        updateLabel(v)
    end)
    sl:SetScript("OnValueChanged", function(self, v)
        setter(v)
        updateLabel(v)
    end)
    return sl
end

-- Dropdown. `choices` is a list of { value=..., label=... } tables.
local function BuildDropdown(parent, label, tooltip, choices, getter, setter, yOfs)
    -- Label above the dropdown.
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, yOfs)
    fs:SetText(label)

    local dd = CreateFrame("Frame", uniqueName("DWPOptDD"), parent, "UIDropDownMenuTemplate")
    dd:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", -16, -6)

    local function SelectedLabel(val)
        for _, c in ipairs(choices) do
            if c.value == val then return c.label end
        end
        return "?"
    end

    local function InitFn(self, level)
        for _, c in ipairs(choices) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = c.label
            info.value = c.value
            info.func = function()
                setter(c.value)
                UIDropDownMenu_SetSelectedValue(dd, c.value)
                UIDropDownMenu_SetText(dd, c.label)
            end
            info.checked = (c.value == getter())
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_Initialize(dd, InitFn)
    UIDropDownMenu_SetWidth(dd, 140)

    -- Sync selection on show.
    dd:SetScript("OnShow", function(self)
        local v = getter()
        UIDropDownMenu_SetSelectedValue(self, v)
        UIDropDownMenu_SetText(self, SelectedLabel(v))
    end)

    return dd
end

----------------------------------------------------------------------
-- Main frame construction
----------------------------------------------------------------------

local function BuildFrame()
    local f = CreateFrame("Frame", FRAME_NAME, UIParent)
    f:SetSize(560, 520)
    f.name = "DankWoW Playerbots"   -- Blizzard uses .name for the category tab label

    -- Title at top.
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -16)
    title:SetText("DankWoW Playerbots")
    title:SetTextColor(0.25, 0.66, 1)

    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetText(string.format("v%s — preferences and tuning.", DWP.VERSION or "?"))

    -- Scroll area so the panel works at any resolution.
    local scroll = CreateFrame("ScrollFrame", "DankWoWPlayerbotsOptionsScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -60)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -32, 10)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(520, 900)
    scroll:SetScrollChild(content)

    ------------------------------------------------------------------
    -- Settings binding helpers (DRY for get/set into Config.db)
    ------------------------------------------------------------------
    local function getPath(section, key) return function() return DWP.Config.db[section][key] end end
    local function setPath(section, key, onChange)
        return function(v)
            DWP.Config.db[section][key] = v
            if onChange then onChange(v) end
        end
    end

    ------------------------------------------------------------------
    -- DISPLAY section
    ------------------------------------------------------------------
    local y = -10
    BuildSectionHeader(content, "Display", y)
    y = y - 24

    BuildSlider(content, "Panel scale", "Overall size of the main panel.",
        0.3, 2.0, 0.05,
        getPath("panel", "scale"),
        setPath("panel", "scale", function(v)
            if DWP.MainFrame and DWP.MainFrame.Get then
                DWP.MainFrame:Get():SetScale(v)
            end
        end),
        function(v) return string.format("%.2f", v) end,
        y)
    y = y - 48

    BuildSlider(content, "Panel opacity", "Transparency of the main panel.",
        0.2, 1.0, 0.05,
        getPath("panel", "alpha"),
        setPath("panel", "alpha", function(v)
            if DWP.MainFrame and DWP.MainFrame.Get then
                DWP.MainFrame:Get():SetAlpha(v)
            end
        end),
        function(v) return string.format("%.0f%%", v * 100) end,
        y)
    y = y - 48

    BuildCheckbox(content, "Lock panel position",
        "Prevents accidentally dragging the main panel.",
        getPath("panel", "locked"),
        setPath("panel", "locked"),
        y)
    y = y - 32

    ------------------------------------------------------------------
    -- MINIMAP section
    ------------------------------------------------------------------
    BuildSectionHeader(content, "Minimap", y)
    y = y - 24

    BuildCheckbox(content, "Show minimap button",
        "Toggle the DankWoW Playerbots button on the minimap.",
        getPath("minimap", "shown"),
        setPath("minimap", "shown", function(v)
            if DWP.MinimapButton then
                if v then DWP.MinimapButton:Show() else DWP.MinimapButton:Hide() end
            end
        end),
        y)
    y = y - 32

    BuildSlider(content, "Minimap button angle", "Position around the minimap, in degrees.",
        0, 360, 5,
        getPath("minimap", "angle"),
        setPath("minimap", "angle", function(v)
            if DWP.MinimapButton and DWP.MinimapButton.ApplyPosition then
                DWP.MinimapButton:ApplyPosition()
            end
        end),
        function(v) return string.format("%d°", v) end,
        y)
    y = y - 48

    ------------------------------------------------------------------
    -- AUDIO section
    ------------------------------------------------------------------
    BuildSectionHeader(content, "Audio", y)
    y = y - 24

    BuildCheckbox(content, "Play sound on command",
        "Play a soft click when you send a bot command.",
        getPath("audio", "commandSound"),
        setPath("audio", "commandSound"),
        y)
    y = y - 28

    BuildCheckbox(content, "Play sound on bot events",
        "Play a sound when a bot dies, levels up, or joins/leaves.",
        getPath("audio", "eventSound"),
        setPath("audio", "eventSound"),
        y)
    y = y - 32

    ------------------------------------------------------------------
    -- POLLING section
    ------------------------------------------------------------------
    BuildSectionHeader(content, "Polling (advanced)", y)
    y = y - 24

    BuildSlider(content, "Strategy poll interval",
        "How often to poll each bot for its active strategies (co/nc).\nLower = faster UI updates, more chat traffic.",
        5, 60, 5,
        getPath("polling", "strategiesInterval"),
        setPath("polling", "strategiesInterval"),
        function(v) return string.format("%ds", v) end,
        y)
    y = y - 48

    BuildSlider(content, "Identity poll interval",
        "How often to poll each bot for who-info (gearscore, zone, etc).\nIdentity rarely changes; long interval is fine.",
        30, 300, 15,
        getPath("polling", "identityInterval"),
        setPath("polling", "identityInterval"),
        function(v) return string.format("%ds", v) end,
        y)
    y = y - 48

    BuildCheckbox(content, "Hide poll traffic from chat",
        "Suppresses the whispers we send to bots (and their replies to those whispers) from your chat frames.",
        getPath("polling", "silentPolls"),
        setPath("polling", "silentPolls"),
        y)
    y = y - 32

    ------------------------------------------------------------------
    -- CONVENIENCE section
    ------------------------------------------------------------------
    BuildSectionHeader(content, "Convenience", y)
    y = y - 24

    BuildCheckbox(content, "Auto-open panel when summoning a bot",
        "When you summon a bot from the Bots dialog, automatically bring up the main panel.",
        getPath("convenience", "autoOpenOnSummon"),
        setPath("convenience", "autoOpenOnSummon"),
        y)
    y = y - 32

    BuildDropdown(content, "Default combat preset on summon",
        "When a bot joins your party, optionally apply this combat preset automatically.",
        {
            { value = "none",   label = "None (leave as-is)" },
            { value = "dps",    label = "DPS" },
            { value = "tank",   label = "Tank" },
            { value = "healer", label = "Healer" },
            { value = "nuker",  label = "Nuker" },
        },
        getPath("convenience", "defaultCombatPreset"),
        setPath("convenience", "defaultCombatPreset"),
        y)
    y = y - 52

    BuildDropdown(content, "Default non-combat preset on summon",
        "When a bot joins your party, optionally apply this non-combat preset automatically.",
        {
            { value = "none",    label = "None (leave as-is)" },
            { value = "follow",  label = "Follow" },
            { value = "stay",    label = "Stay" },
            { value = "quest",   label = "Quest" },
            { value = "dungeon", label = "Dungeon" },
            { value = "gather",  label = "Gather" },
            { value = "auto",    label = "Auto" },
        },
        getPath("convenience", "defaultNonCombatPreset"),
        setPath("convenience", "defaultNonCombatPreset"),
        y)
    y = y - 52

    ------------------------------------------------------------------
    -- DEBUG section
    ------------------------------------------------------------------
    BuildSectionHeader(content, "Debug", y)
    y = y - 24

    BuildCheckbox(content, "Log protocol messages",
        "Prints outgoing polls and incoming responses to your chat frame. Useful for diagnosing comm issues.",
        getPath("debug", "logMessages"),
        setPath("debug", "logMessages"),
        y)
    y = y - 32

    ------------------------------------------------------------------
    -- Resize content to fit everything we laid out.
    ------------------------------------------------------------------
    content:SetHeight(math.abs(y) + 20)

    ------------------------------------------------------------------
    -- Blizzard Interface Options registration.
    -- Register the frame as a category; the default options UI shows
    -- the frame we provide as the panel body.
    ------------------------------------------------------------------
    if InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(f)
    end

    return f
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function OptionsPanel:Get()
    if not _frame then _frame = BuildFrame() end
    return _frame
end

-- Open the panel. On Blizzard's options-panel side, this means calling
-- InterfaceOptionsFrame_OpenToCategory twice (Blizzard has a known bug
-- where the first call expands the tree but doesn't show, so doing it
-- twice works around it).
function OptionsPanel:Show()
    local f = self:Get()
    if InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(f)
        InterfaceOptionsFrame_OpenToCategory(f)
    end
end

function OptionsPanel:Toggle()
    if InterfaceOptionsFrame and InterfaceOptionsFrame:IsShown() then
        InterfaceOptionsFrame:Hide()
    else
        self:Show()
    end
end
