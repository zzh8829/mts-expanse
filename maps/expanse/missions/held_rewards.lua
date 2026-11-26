-- Tells a team that earned rewards are not sent because its landing pad has
-- requests set and leaves them out. A pad with requests only receives what it
-- asks for, and nothing else showed that a reward was waiting for that reason.
--
-- Shown in four places, all from the once-a-second alert tick: an alert that
-- stays while the condition holds, red text over the pad, a line in the
-- pad's hover tooltip, and one chat line each time a reward newly joins.
local Chat = require 'maps.expanse.missions.chat'
local Model = require 'maps.expanse.missions.model'
local SpaceMissions = require 'maps.expanse.space_missions'

local Public = {}

-- Tooltip field id on the pad; Tooltips.pad owns field 1.
local FIELD = 2
local RED = { 1, 0.35, 0.2 }
local WHITE = { 1, 1, 1 }
-- The pad is 8 tiles tall; the three lines sit just above its top edge.
local TITLE_OFFSET = { 0, -7.2 }
local NAMES_OFFSET = { 0, -5.8 }
local HINT_OFFSET = { 0, -4.8 }
-- A localised string takes 20 parameters, and a line has to stay readable.
local MAX_NAMES = 4

local function sorted_keys(counts)
    local keys = {}
    for key in pairs(counts) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

-- "Lithium, Holmium ore and 2 more" for a list of "name|quality" keys.
local function names(keys)
    local list = { '' }
    for index = 1, math.min(#keys, MAX_NAMES) do
        local name = Model.split_key(keys[index])
        if index > 1 then list[#list + 1] = ', ' end
        list[#list + 1] = { '', '[img=item/' .. name .. '] ', prototypes.item[name].localised_name }
    end
    return #keys > MAX_NAMES and { 'expanse-missions.held_and_more', list, #keys - MAX_NAMES } or list
end

local function clear(state, pad)
    for _, field in ipairs({ 'held_label', 'held_names', 'held_hint' }) do
        if state[field] and state[field].valid then state[field].destroy() end
        state[field] = nil
    end
    if state.held_key and pad and pad.valid then pad.clear_tooltip_field(FIELD) end
    state.held_key, state.held_announced = nil, nil
end

local function draw(pad, force, text, offset, color, scale)
    return rendering.draw_text { text = text, surface = pad.surface, target = { entity = pad, offset = offset },
        color = color, scale = scale, alignment = 'center', forces = { force }, use_rich_text = true }
end

-- One chat line for the rewards that were not held a second ago.
local function announce(state, pad, keys)
    local announced, fresh = state.held_announced or {}, {}
    state.held_announced = {}
    for _, key in ipairs(keys) do
        if not announced[key] then fresh[#fresh + 1] = key end
        state.held_announced[key] = true
    end
    if #fresh > 0 then Chat.rewards_held(state, pad, names(fresh)) end
end

-- Once a second per team that has players online.
function Public.tick(state, force)
    local pad = state.landing_pad
    local keys = pad and pad.valid and sorted_keys(SpaceMissions.rewards_unrequested(state)) or {}
    if #keys == 0 then
        if state.held_key then clear(state, pad) end
        return
    end
    local list = names(keys)
    local first = Model.split_key(keys[1])
    force.add_custom_alert(pad, { type = 'item', name = first }, { 'expanse-missions.alert_rewards_held', list }, true)
    announce(state, pad, keys)
    local key = table.concat(keys, ';')
    -- Render objects die with the pad they hang on.
    if state.held_key == key and state.held_label and state.held_label.valid then return end
    clear(state, pad)
    state.held_key = key
    state.held_announced = {}
    for _, held in ipairs(keys) do state.held_announced[held] = true end
    state.held_label = draw(pad, force, { 'expanse-missions.label_rewards_held' }, TITLE_OFFSET, RED, 2.2)
    state.held_names = draw(pad, force, list, NAMES_OFFSET, WHITE, 1.5)
    state.held_hint = draw(pad, force, { 'expanse-missions.label_rewards_held_hint' }, HINT_OFFSET, WHITE, 1.3)
    pad.set_tooltip_field { id = FIELD, order = FIELD, name = { 'expanse-missions.tip_held' }, value = { 'expanse-missions.tip_held_value', list } }
end

return Public
