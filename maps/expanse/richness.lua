-- The save keeps the map creation sliders even when Expanse replaces Nauvis's
-- surface settings with its terrain generator.
local Event = require 'utils.event'
local Public = {}

local control_names = {
    ['tungsten-ore'] = 'tungsten_ore',
    ['sulfuric-acid-geyser'] = 'sulfuric_acid_geyser',
    ['lithium-brine'] = 'lithium_brine',
    ['fluorine-vent'] = 'fluorine_vent',
}
local biome_controls = {
    [6] = {coal = 'vulcanus_coal'},
    [8] = {stone = 'gleba_stone'},
    [9] = {['crude-oil'] = 'aquilo_crude_oil'},
}

local saved_controls
local function map_controls()
    if not saved_controls then saved_controls = game.default_map_gen_settings.autoplace_controls or {} end
    return saved_controls
end

local function control_name(name, tier)
    local biome = biome_controls[tier]
    return (biome and biome[name]) or control_names[name] or name
end

local function multiplier(controls, key)
    return controls[key] and controls[key].richness or 1
end

-- The source chunk generator replaces these deposits with Expanse's own
-- amounts. Oil and resources added by other mods keep their native amounts.
Public.source_ores = {'iron-ore', 'copper-ore', 'coal', 'stone', 'uranium-ore'}
local rewritten = {}
for _, name in ipairs(Public.source_ores) do rewritten[name] = true end

local function chunk_key(position)
    return math.floor(position.x / 32) .. ',' .. math.floor(position.y / 32)
end

function Public.record_source_chunk(state, surface, left_top)
    local meta = state.meta_map
    if meta.source_configured then return end
    -- Switching the runtime setting on can give a native source both kinds of
    -- chunks. Remember only the exceptions, also clearing a regenerated chunk.
    local by_surface = meta.scripted_ore_chunks
    local chunks = by_surface and by_surface[surface.name]
    if state.override_nauvis then
        if not by_surface then
            by_surface = {}
            meta.scripted_ore_chunks = by_surface
        end
        if not chunks then
            chunks = {}
            by_surface[surface.name] = chunks
        end
        chunks[chunk_key(left_top)] = true
    elseif chunks then
        chunks[chunk_key(left_top)] = nil
    end
end

function Public.native_source(state, surface)
    local meta = state.meta_map
    if meta and meta.source_configured then return nil end
    local chunks = meta and meta.scripted_ore_chunks
    return {controls = surface.map_gen_settings.autoplace_controls or {}, scripted_chunks = chunks and chunks[surface.name]}
end

local function scaled(amount, factor)
    return math.max(1, math.min(4294967295, math.floor(amount * factor)))
end

function Public.create(surface, name, position, amount, tier)
    local factor = multiplier(map_controls(), control_name(name, tier))
    if factor > 0 then
        return surface.create_entity{name = name, position = position, amount = scaled(amount, factor)}
    end
end

-- clone_area raises this event synchronously. Only collect resources actually
-- created by this unlock: a neighbouring deposit may straddle the cell edge.
local current_clone
Event.add(defines.events.on_entity_cloned, function(event)
    if current_clone and event.source.valid and event.destination.valid
        and event.source.surface == current_clone.source
        and event.destination.surface == current_clone.destination then
        local resources = current_clone.resources
        resources[#resources + 1] = event.destination
    end
end)
Event.add_event_filter(defines.events.on_entity_cloned, {filter = 'type', type = 'resource'})

function Public.clone_area(source, parameters)
    local previous = current_clone
    local batch = {source = source, destination = parameters.destination_surface, resources = {}}
    current_clone = batch
    local ok, err = pcall(source.clone_area, parameters)
    current_clone = previous
    if not ok then error(err, 0) end
    return batch.resources
end

function Public.finish_clone(entity, replacement, tier, native_source)
    local name = replacement or entity.name
    if replacement and prototypes.entity[name].type ~= 'resource' then
        entity.surface.create_entity{name = name, position = entity.position}
        entity.destroy()
        return
    end
    local target_key = control_name(name, tier)
    local factor = multiplier(map_controls(), target_key)
    if native_source then
        -- The engine already applied the source planet's slider. For a biome
        -- conversion, replace that slider with the destination resource's.
        local chunks = native_source.scripted_chunks
        local scripted = chunks and rewritten[entity.name] and chunks[chunk_key(entity.position)]
        local original = multiplier(native_source.controls, control_name(entity.name))
        if not scripted and original > 0 then
            factor = factor / original
        end
    end
    if factor <= 0 then
        entity.destroy()
    elseif replacement then
        entity.surface.create_entity{name = name, position = entity.position, amount = scaled(entity.amount, factor)}
        entity.destroy()
    elseif factor ~= 1 then
        local initial = entity.initial_amount
        entity.amount = scaled(entity.amount, factor)
        if initial then entity.initial_amount = scaled(initial, factor) end
    end
end

return Public
