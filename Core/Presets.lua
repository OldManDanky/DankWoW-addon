--[[
    Presets.lua

    Preset strategy bundles for one-click role/mode switching. Each preset
    defines:
      - apply:  strategies to enable (whisper "co +name" / "nc +name")
      - remove: strategies to disable (whisper "co -name" / "nc -name")

    The roster's current strategy state for a bot is inspected to determine
    which preset best matches (for UI highlight).

    Presets are intentionally high-level. Power users can still fine-tune
    individual pills underneath.
]]

local DWP = DankWoWPlayerbots
local Presets = {}
DWP.Presets = Presets

-- Combat role presets.
-- Order here is the left-to-right button order in the UI.
Presets.COMBAT = {
    {
        id = "dps",
        label = "DPS",
        tooltip = "Standard single-target DPS.",
        apply  = { "dps assist", "aoe", "avoid aoe", "behind", "cast time",
                   "potions", "racials", "save mana", "default" },
        remove = { "tank", "tank assist", "tank face", "heal", "passive" },
    },
    {
        id = "tank",
        label = "Tank",
        tooltip = "Main tank: hold threat, face-tank, survive.",
        apply  = { "tank", "tank assist", "tank face", "threat", "avoid aoe",
                   "potions", "racials", "guard", "default" },
        remove = { "dps assist", "dps aoe", "heal", "passive", "flee" },
    },
    {
        id = "healer",
        label = "Healer",
        tooltip = "Healer: keep the group alive, conserve mana.",
        apply  = { "heal", "save mana", "avoid aoe", "potions", "racials",
                   "default" },
        remove = { "tank", "tank face", "aoe", "behind", "dps assist" },
    },
    {
        id = "nuker",
        label = "Nuker",
        tooltip = "Heavy AOE DPS. Glass cannon.",
        apply  = { "dps aoe", "aoe", "cast time", "potions", "racials",
                   "default" },
        remove = { "avoid aoe", "tank", "tank assist", "heal", "passive",
                   "flee" },
    },
}

-- Non-combat mode presets.
Presets.NONCOMBAT = {
    {
        id = "follow",
        label = "Follow",
        tooltip = "Stick with you, loot, eat/drink, mount up when you do.",
        apply  = { "follow", "default", "chat", "emote", "food", "loot", "mount" },
        remove = { "stay", "passive", "move random", "rpg", "grind" },
    },
    {
        id = "stay",
        label = "Stay",
        tooltip = "Hold position; don't follow or wander.",
        apply  = { "stay", "default", "chat" },
        remove = { "follow", "move random", "rpg", "grind", "quest" },
    },
    {
        id = "quest",
        label = "Quest",
        tooltip = "Quest companion: follow, loot, gather along the way.",
        apply  = { "default", "quest", "follow", "loot", "gather" },
        remove = { "passive", "stay", "move random", "rpg" },
    },
    {
        id = "dungeon",
        label = "Dungeon",
        tooltip = "Dungeon-ready: follow and loot, no questing distractions.",
        apply  = { "default", "follow", "loot" },
        remove = { "stay", "passive", "move random", "rpg", "quest", "grind" },
    },
    {
        id = "gather",
        label = "Gather",
        tooltip = "Gather mode: harvest nodes, mount up.",
        apply  = { "gather", "mount", "default", "follow" },
        remove = { "passive", "stay", "quest", "grind" },
    },
    {
        id = "auto",
        label = "Auto",
        tooltip = "Full autonomy: quest, grind, rpg, do your own thing.",
        apply  = { "default", "rpg", "grind", "quest", "gather", "loot",
                   "mount", "food" },
        remove = { "passive", "follow", "stay" },
    },
}

----------------------------------------------------------------------
-- Fuzzy matching: given a bot's current strategies, find the best match.
----------------------------------------------------------------------

-- Score how well an active strategy set matches a preset.
-- Points: +1 for each applied strategy that IS active,
--         +1 for each removed strategy that is NOT active.
-- Normalized by total possible (so presets with more strategies aren't
-- unfairly biased).
local function Score(active, preset)
    local activeSet = {}
    for _, s in ipairs(active or {}) do activeSet[s] = true end

    local hits = 0
    local total = 0
    for _, s in ipairs(preset.apply) do
        total = total + 1
        if activeSet[s] then hits = hits + 1 end
    end
    for _, s in ipairs(preset.remove) do
        total = total + 1
        if not activeSet[s] then hits = hits + 1 end
    end

    if total == 0 then return 0 end
    return hits / total
end

-- Return the ID of the best-matching preset from a list, or nil if the
-- best score is below the confidence threshold. Ties go to the first one.
-- threshold of 0.75 means "matches at least 75% of the preset's criteria"
-- to count as "this is probably what the bot is set to."
local CONFIDENCE_THRESHOLD = 0.75

function Presets:MatchCombat(activeList)
    return self:_match(activeList, self.COMBAT)
end

function Presets:MatchNonCombat(activeList)
    return self:_match(activeList, self.NONCOMBAT)
end

function Presets:_match(activeList, presetList)
    local best, bestScore = nil, 0
    for _, p in ipairs(presetList) do
        local s = Score(activeList, p)
        if s > bestScore then
            best, bestScore = p, s
        end
    end
    if best and bestScore >= CONFIDENCE_THRESHOLD then
        return best.id, bestScore
    end
    return nil, bestScore
end

----------------------------------------------------------------------
-- Applying a preset: returns a list of whispers to send, in order.
----------------------------------------------------------------------

-- Given a preset and the bot's currently-active strategies, return the
-- minimal set of whispers needed to match the preset state. No need to
-- re-send `co +x` if x is already active, or `co -y` if y is already gone.
function Presets:PlanApply(preset, activeList, prefix_add, prefix_remove)
    local activeSet = {}
    for _, s in ipairs(activeList or {}) do activeSet[s] = true end

    local whispers = {}
    for _, s in ipairs(preset.apply) do
        if not activeSet[s] then
            table.insert(whispers, prefix_add .. s)
        end
    end
    for _, s in ipairs(preset.remove) do
        if activeSet[s] then
            table.insert(whispers, prefix_remove .. s)
        end
    end
    return whispers
end
