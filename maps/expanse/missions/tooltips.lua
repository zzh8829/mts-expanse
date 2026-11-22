-- Lines the mod adds to the game's own hover tooltip: which mission a silo
-- serves and what it still needs, what a cargo chest is for, and what arrives
-- at the landing pad. They are stored on the entity, so they also show in map
-- view and survive a save; this module only rewrites them when they change.
local MissionData = require 'maps.expanse.mission_data'
local Model = require 'maps.expanse.missions.model'
local Ships = require 'maps.expanse.missions.ships'
local Text = require 'maps.expanse.missions.text'

local Public = {}

-- Field ids are fixed, so a rewrite replaces the line in place.
local MISSION, NEEDS, REWARD = 1, 2, 3
-- A tooltip is narrow: past this many items the rest is summed up.
local MAX_ITEMS = 8

local function sorted_keys(counts)
    local keys = {}
    for key in pairs(counts) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

-- "[item=x,quality=q] 200" for each entry, as one plain rich-text string.
local function item_list(counts, prefix)
    local keys, parts = sorted_keys(counts), {}
    for index = 1, math.min(#keys, MAX_ITEMS) do
        local name, quality = Model.split_key(keys[index])
        parts[index] = '[item=' .. name .. ',quality=' .. quality .. '] ' .. prefix .. counts[keys[index]]
    end
    return table.concat(parts, '   '), #keys - #parts
end

local function mission_line(state, data, stage)
    local ship = Ships.by_tier[data.tier].name
    if stage.status == 'locked' then
        local tech = MissionData.mission_unlocks[data.tier]
        return { 'expanse-missions.tip_locked', ship, prototypes.technology[tech].localised_name }
    elseif stage.status == 'done' then
        return { 'expanse-missions.tip_done', ship }
    end
    return { 'expanse-missions.tip_step', ship, stage.step, stage.steps }
end

local function set(entity, id, name, value)
    entity.set_tooltip_field { id = id, order = id, name = { name }, value = value }
end

local function chest_line(data)
    local chest = data.cargo_chest
    if not (chest and chest.valid) or data.chest_tip == chest.unit_number then return end
    set(chest, MISSION, 'expanse-missions.tip_chest_name', { 'expanse-missions.tip_chest', Ships.by_tier[data.tier].name })
    data.chest_tip = chest.unit_number
end

-- Once a second per silo from the mission tick. The lines only depend on the
-- step and on what is outstanding, so the cached key keeps writes rare.
function Public.silo(state, data)
    local silo = data.entity
    chest_line(data)
    local stage = Model.stage(state, data.tier)
    local outstanding = stage.status == 'active' and Model.outstanding(state, data.tier) or {}
    local needs, more = item_list(outstanding, '')
    local key = table.concat({ silo.unit_number, stage.status, stage.step, needs, more, state.space_production_interval_ticks or 3600 }, '/')
    if data.tooltip_key == key then return end
    data.tooltip_key = key
    set(silo, MISSION, 'expanse-missions.tip_mission', mission_line(state, data, stage))
    if stage.status ~= 'active' then
        silo.clear_tooltip_field(NEEDS)
        silo.clear_tooltip_field(REWARD)
        return
    end
    if needs == '' then
        set(silo, NEEDS, 'expanse-missions.tip_needs', { 'expanse-missions.tip_needs_none' })
    else
        set(silo, NEEDS, 'expanse-missions.tip_needs', more > 0 and { 'expanse-missions.tip_and_more', needs, more } or needs)
    end
    local rewards = MissionData.rewards[data.tier][state.missions[data.tier].level]
    set(silo, REWARD, 'expanse-missions.tip_reward', Text.join(Text.reward_lines(state, rewards, true), ', '))
end

-- What the team's ships send down, on the landing pad itself.
function Public.pad(state)
    local pad = state.landing_pad
    if not (pad and pad.valid) then return end
    local goods, more = item_list(state.space_production or {}, '+')
    local key = table.concat({ pad.unit_number, goods, more, state.space_production_interval_ticks or 3600 }, '/')
    if state.pad_tooltip_key == key then return end
    state.pad_tooltip_key = key
    if goods == '' then
        set(pad, MISSION, 'expanse-missions.tip_pad', { 'expanse-missions.tip_pad_none' })
        return
    end
    goods = more > 0 and { 'expanse-missions.tip_and_more', goods, more } or goods
    set(pad, MISSION, 'expanse-missions.tip_pad', { 'expanse-missions.tip_pad_goods', goods, Text.interval(state) })
end

return Public
