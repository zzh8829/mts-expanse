-- Cargo station of a mission silo: a requester chest and a constant combinator
-- owned by the mod. Robots, inserters and players fill the chest; this module
-- moves what the step needs into the rocket and sends it.
--
-- One number drives everything: Model.outstanding, what the step still needs
-- that is not in the rocket or in flight. The chest never asks for more than
-- that, and it is lowered in the same tick cargo moves into the rocket, so
-- robots cannot be sent for items the step can no longer use. (A requester
-- chest on "need minus credited" keeps refilling while cargo is in the rocket:
-- measured 413 items carried for a step that needs 186.)
local Model = require 'maps.expanse.missions.model'
local RequestSection = require 'maps.expanse.request_section'
local Ships = require 'maps.expanse.missions.ships'
local SpaceMissions = require 'maps.expanse.space_missions'

local Public = {}

local SEARCH_RADIUS = 8
-- Weight the chest aims to hold plus have on order. Keeps a large step arriving
-- as a steady stream of about two rocket loads instead of one swarm of robots.
local REQUEST_BUDGET = 2 * Ships.ROCKET_WEIGHT
local GOLD = { 1, 0.82, 0.4 }

local function place(silo, name, near)
    local surface = silo.surface
    local position = surface.find_non_colliding_position(name, near, SEARCH_RADIUS, 1, true)
    if not position then return nil end
    local entity = surface.create_entity { name = name, position = position, force = silo.force, create_build_effect_smoke = false }
    if not entity then return nil end
    entity.minable_flag = false
    entity.destructible = false
    return entity
end

-- Places the chest and the combinator under the silo's lower left corner, or as
-- near as free land allows. Retried every tick until both exist, so silos from
-- older saves get theirs too.
local function ensure_station(data)
    local silo = data.entity
    if not (data.cargo_chest and data.cargo_chest.valid) then
        data.cargo_chest = place(silo, 'requester-chest', { silo.position.x - 1, silo.position.y + 5.5 })
        if not data.cargo_chest then return false end
        rendering.draw_text { text = { 'expanse-missions.chest_label', Ships.by_tier[data.tier].name }, surface = silo.surface,
            target = { entity = data.cargo_chest, offset = { 0, -1.3 } }, color = GOLD, scale = 1, alignment = 'center' }
        data.request_section, data.request_key = nil, nil
    end
    if not (data.cargo_combinator and data.cargo_combinator.valid) then
        local chest = data.cargo_chest.position
        data.cargo_combinator = place(silo, 'constant-combinator', { chest.x + 1, chest.y })
        if data.cargo_combinator then data.cargo_combinator.operable = false end
        data.signal_section, data.signal_key = nil, nil
    end
    return true
end

local function sorted_keys(counts)
    local keys = {}
    for key in pairs(counts) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

local function weight_of(key)
    return prototypes.item[Model.split_key(key)].weight
end

-- Moves needed items from the chest into the standing rocket, as many as fit
-- by weight. Returns what is still outstanding afterwards.
local function load_rocket(state, data)
    local outstanding = Model.outstanding(state, data.tier)
    local rocket = Model.rocket_inventory(data.entity)
    local chest = data.cargo_chest.get_inventory(defines.inventory.chest)
    if not next(outstanding) or chest.is_empty() then return outstanding end
    local staging
    for slot = 1, #chest do
        local stack = chest[slot]
        if stack.valid_for_read then
            local key = stack.name .. '|' .. stack.quality.name
            local needed = outstanding[key]
            if needed then
                local moved
                if stack.count <= needed then
                    moved = rocket.transfer_from_stack(stack)
                else
                    -- Split with the engine to keep spoilage, health and partial ammo.
                    staging = staging or game.create_inventory(1)
                    staging[1].transfer_stack(stack, needed)
                    moved = rocket.transfer_from_stack(staging[1])
                    if staging[1].valid_for_read then stack.transfer_stack(staging[1]) end
                end
                outstanding[key] = needed > moved and needed - moved or nil
            end
        end
    end
    if staging then staging.destroy() end
    return outstanding
end

-- True when the rocket can take at least one more item the step still needs.
local function more_can_board(rocket, outstanding)
    local free = Ships.ROCKET_WEIGHT - Model.inventory_weight(rocket)
    for key in pairs(outstanding) do
        local name, quality = Model.split_key(key)
        if weight_of(key) <= free and rocket.can_insert({ name = name, quality = quality, count = 1 }) then
            return true
        end
    end
    return false
end

-- A full rocket leaves through SpaceMissions.launch_rockets. This sends the
-- ones that would otherwise wait forever: the last load of a step, and a load
-- that no needed item fits into any more.
local function launch_part_load(state, data, outstanding)
    local rocket = Model.rocket_inventory(data.entity)
    if more_can_board(rocket, outstanding) then return end
    -- Only cargo the step can use is worth a launch; filler alone stays put.
    for key in pairs(Model.current_costs(state, data.tier)) do
        local name, quality = Model.split_key(key)
        if rocket.get_item_count({ name = name, quality = quality }) > 0 then
            SpaceMissions.launch_silo(state, data.entity)
            return
        end
    end
end

local function write_section(owner, counts, section, cached_key)
    -- Reuse the default section on fresh stations and pre-upgrade saves.
    local previous = section
    section = RequestSection.acquire(owner, section or owner.get_section(1))
    if not section then return nil, nil end
    if section ~= previous then cached_key = nil end
    local keys = sorted_keys(counts)
    local parts = {}
    for index, key in ipairs(keys) do parts[index] = key .. '=' .. counts[key] end
    local signature = table.concat(parts, ';')
    if signature == cached_key then return section, cached_key end
    for slot = section.filters_count, 1, -1 do section.clear_slot(slot) end
    for slot, key in ipairs(keys) do
        local name, quality = Model.split_key(key)
        section.set_slot(slot, { value = { type = 'item', name = name, quality = quality, comparator = '=' }, min = counts[key] })
    end
    return section, signature
end

-- Chest requests. Every outstanding item first gets an equal share of the
-- budget (at least one piece), so an item the team cannot supply yet never
-- holds up the ones it can. What is left of the budget then goes to the items
-- in a fixed order.
local function requests(outstanding)
    local keys = sorted_keys(outstanding)
    local wanted, budget = {}, REQUEST_BUDGET
    local share = #keys > 0 and REQUEST_BUDGET / #keys or 0
    for _, key in ipairs(keys) do
        wanted[key] = math.min(outstanding[key], math.max(1, math.floor(share / weight_of(key))))
        budget = budget - wanted[key] * weight_of(key)
    end
    for _, key in ipairs(keys) do
        local extra = math.min(outstanding[key] - wanted[key], math.floor(math.max(budget, 0) / weight_of(key)))
        wanted[key] = wanted[key] + extra
        budget = budget - extra * weight_of(key)
    end
    return wanted
end

-- Combinator signals: what still has to be brought to the chest. For players
-- who feed it by belt or train and want to gate that with circuits.
local function signals(data, outstanding)
    local chest = data.cargo_chest.get_inventory(defines.inventory.chest)
    local missing = {}
    for key, count in pairs(outstanding) do
        local name, quality = Model.split_key(key)
        local left = count - chest.get_item_count({ name = name, quality = quality })
        if left > 0 then missing[key] = left end
    end
    return missing
end

-- Once a second per silo. A chest filling up raises no event, so this cannot
-- be event-driven; an idle station costs a few inventory reads.
function Public.tick(state, data)
    local silo = data.entity
    if not (silo and silo.valid) or not ensure_station(data) then return end
    local outstanding
    if silo.rocket_silo_status == defines.rocket_silo_status.rocket_ready and Model.current_costs(state, data.tier) then
        outstanding = load_rocket(state, data)
        launch_part_load(state, data, outstanding)
    else
        outstanding = Model.outstanding(state, data.tier)
    end
    data.request_section, data.request_key = write_section(
        data.cargo_chest.get_requester_point(), requests(outstanding), data.request_section, data.request_key)
    local combinator = data.cargo_combinator
    if combinator and combinator.valid then
        data.signal_section, data.signal_key = write_section(
            combinator.get_or_create_control_behavior(), signals(data, outstanding), data.signal_section, data.signal_key)
    end
end

-- Station entities belong to the mission, so a base reset keeps them.
function Public.owns(state, entity)
    for _, data in pairs(state.rocket_silos or {}) do
        if entity == data.cargo_chest or entity == data.cargo_combinator then return true end
    end
    return false
end

return Public
