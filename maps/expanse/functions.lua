local Price_raffle = require 'maps.expanse.price_raffle'
local BiterRaffle = require 'utils.functions.biter_raffle'
local Mode = require 'maps.expanse.mode'
local SpaceMissions = require 'maps.expanse.space_missions'
local Task = require 'utils.task'
local Token = require 'utils.token'
local Public = {}

local ores = { 'copper-ore', 'iron-ore', 'stone', 'coal' }
local price_modifiers = {
    ['unit-spawner'] = -256,
    ['unit'] = -16,
    ['turret'] = -128,
    ['tree'] = -8,
    ['simple-entity'] = 2,
    ['cliff'] = -128,
    ['water'] = -5,
    ['water-green'] = -5,
    ['deepwater'] = -5,
    ['deepwater-green'] = -5,
    ['water-mud'] = -6,
    ['water-shallow'] = -6
}

local qualities = {
    ['normal'] = 0,
    ['uncommon'] = 1,
    ['rare'] = 2,
    ['epic'] = 3,
    ['legendary'] = 5
}
local default_tier_distance_thresholds = { 30, 60, 90, 150, 210, 300 }

local function cell_random_int(expanse, left_top, salt, max)
    max = math.floor(max or 1)
    if max <= 1 then
        return 1
    end

    local seed = math.floor((expanse and expanse.shared_seed) or 1) % 2147483647
    local p = math.floor((expanse and expanse.planet_key) or 0) % 1000039
    local x = math.floor((left_top and left_top.x) or 0) % 1000003
    local y = math.floor((left_top and left_top.y) or 0) % 1000033
    local s = math.floor(salt or 0) % 1000037
    local n = (seed + p * 70368767 + x * 73856093 + y * 19349663 + s * 83492791) % 2147483647
    n = (n * 48271 + 1) % 2147483647
    return (n % max) + 1
end

local function make_cell_rng(expanse, left_top, salt)
    local counter = 0
    return function(min, max)
        counter = counter + 1
        return min + cell_random_int(expanse, left_top, salt + counter, max - min + 1) - 1
    end
end

local function random_int(rng, min, max)
    if rng then
        return rng(min, max)
    end
    return math.random(min, max)
end

local function state_force(expanse)
    if not game then
        return nil
    end
    return game.forces[expanse.force_name or 'player'] or game.forces.player
end

--- Some mods like to destroy the infini tree.
--- So we solve it by delaying the creation.
local delay_infini_tree_token =
    Token.register(
        function (event)
            local surface = event.surface
            local position = event.position

            local species = cell_random_int(event.expanse, position, 9100, 9)
            local newtree = surface.create_entity({ name = 'tree-0' .. species, position = position })
            event.expanse.tree = script.register_on_object_destroyed(newtree)
        end
    )

local function reward_tokens(expanse, entity)
    local chance = expanse.token_chance % 1
    local count = math.floor(expanse.token_chance)

    if chance > 0 then
        chance = math.floor(chance * 1000)
        -- Keyed by chest position so the bonus token is identical across teams (each team's
        -- copy of the same cell rolls the same), rather than drawing the interleaved global RNG.
        if cell_random_int(expanse, entity.position, 61000, 1000) <= chance then
            entity.surface.spill_item_stack({ position = entity.position, stack = { name = 'coin', count = 1 }, enable_looted = true, allow_belts = false })
        end
    end
    if count > 0 then
        for _ = 1, count, 1 do
            entity.surface.spill_item_stack({ position = entity.position, stack = { name = 'coin', count = 1 }, enable_looted = true, allow_belts = false })
        end
    end
end

local function get_cell_value(expanse, left_top)
    local square_size = expanse.square_size
    local value = square_size ^ 2
    value = value * (expanse.cell_value_multiplier or 8)

    local source_surface = game.surfaces[expanse.source_surface]
    if not source_surface then
        return expanse.min_cell_value or 16
    end
    source_surface.request_to_generate_chunks(left_top, 1)
    source_surface.force_generate_chunk_requests()
    local area = { { left_top.x, left_top.y }, { left_top.x + square_size, left_top.y + square_size } }
    local entities = source_surface.find_entities(area)
    local tiles = source_surface.find_tiles_filtered({ area = area })

    for _, tile in pairs(tiles) do
        if price_modifiers[tile.name] then
            value = value + price_modifiers[tile.name]
        end
    end
    for _, entity in pairs(entities) do
        if price_modifiers[entity.type] then
            value = value + price_modifiers[entity.type]
        end
    end

    local distance = math.sqrt(left_top.x ^ 2 + left_top.y ^ 2)
    value = value * ((distance ^ 1.15) * expanse.price_distance_modifier)
    local ore_modifier = distance * (expanse.price_distance_modifier / (expanse.ore_modifier_divisor or 20))
    if ore_modifier > expanse.max_ore_price_modifier then
        ore_modifier = expanse.max_ore_price_modifier
    end

    for _, entity in pairs(entities) do
        if entity.type == 'resource' then
            if entity.prototype.resource_category == 'basic-fluid' then
                value = value + (entity.amount * ore_modifier * (expanse.fluid_price_multiplier or 0.01))
            else
                value = value + (entity.amount * ore_modifier)
            end
        end
    end

    value = math.floor(value)
    local min_cell_value = expanse.min_cell_value or 16
    if value < min_cell_value then
        value = min_cell_value
    end

    return value
end

local function get_left_top(expanse, position)
    local vectors = { { -1, 0 }, { 1, 0 }, { 0, 1 }, { 0, -1 } }
    table.shuffle_table(vectors)

    local surface = game.surfaces[expanse.active_surface_index]

    for _, v in pairs(vectors) do
        local tile = surface.get_tile(position.x + v[1], position.y + v[2])
        if tile.name == 'out-of-map' then
            local left_top = tile.position
            left_top.x = left_top.x - left_top.x % expanse.square_size
            left_top.y = left_top.y - left_top.y % expanse.square_size
            if not expanse.grid[tostring(left_top.x .. '_' .. left_top.y)] then
                return left_top
            end
        end
    end

    return false
end

local function grid_key(left_top)
    return tostring(left_top.x .. '_' .. left_top.y)
end

local function ensure_meta_cell(expanse, left_top)
    local meta_map = expanse and expanse.meta_map
    if not (meta_map and left_top) then
        return nil
    end

    meta_map.cells = meta_map.cells or {}
    local key = grid_key(left_top)
    local cell = meta_map.cells[key]
    if not cell then
        cell = {
            key = key,
            left_top = { x = left_top.x, y = left_top.y },
            rolls = {}
        }
        meta_map.cells[key] = cell
    end
    cell.rolls = cell.rolls or {}
    return cell
end

local function is_cell_open(expanse, left_top)
    if not left_top then
        return false
    end
    return expanse.grid and expanse.grid[grid_key(left_top)] == true
end

local function same_left_top(a, b)
    return a and b and a.x == b.x and a.y == b.y
end

local function parse_grid_key(key)
    local x, y = tostring(key):match('^(-?%d+)_(-?%d+)$')
    if not x or not y then
        return nil
    end
    return { x = tonumber(x), y = tonumber(y) }
end

local function has_container_for_left_top(expanse, left_top)
    for unit_number, container in pairs(expanse.containers or {}) do
        if not container.entity or not container.entity.valid then
            expanse.containers[unit_number] = nil
        elseif same_left_top(container.left_top, left_top) then
            return true
        end
    end
    return false
end

local function is_container_position_valid(expanse, position, left_top)
    left_top = left_top or get_left_top(expanse, position)
    if not left_top or is_cell_open(expanse, left_top) or has_container_for_left_top(expanse, left_top) then
        return false
    end

    if
        game.surfaces[expanse.active_surface_index].count_entities_filtered(
            {
                name = 'requester-chest',
                force = 'neutral',
                area = { { position.x - 0.5, position.y - 0.5 }, { position.x + 0.5, position.y + 0.5 } }
            }
        ) > 0
    then
        return false
    end

    return left_top
end

local function create_costs_render(entity, name, offset, quality)
    local id = rendering.draw_sprite {
        sprite = 'virtual-signal/signal-grey',
        surface = entity.surface,
        target = {
            entity = entity,
            offset = { offset, -1.5 }
        },
        x_scale = 1.1,
        y_scale = 1.1,
        render_layer = '190',
        only_in_alt_mode = true
    }
    local id2 = rendering.draw_sprite {
        sprite = 'item/' .. name,
        surface = entity.surface,
        target = {
            entity = entity,
            offset = { offset, -1.5 }
        },
        x_scale = 0.75,
        y_scale = 0.75,
        render_layer = '191',
        only_in_alt_mode = true
    }
    local Q = script.active_mods['quality']
    local id3 = rendering.draw_sprite {
        sprite = 'quality/' .. quality,
        surface = entity.surface,
        target = {
            entity = entity,
            offset = { offset - 0.25, -1.25 }
        },
        x_scale = 0.25,
        y_scale = 0.25,
        render_layer = Q and '192' or '189',
        only_in_alt_mode = true
    }

    return { id, id2, id3}
end

local function remove_one_render(container, key)
    local render = container.price[key] and container.price[key].render or {}
    if render[1] and render[1].valid then
        render[1].destroy()
    end
    if render[2] and render[2].valid then
        render[2].destroy()
    end
    if render[3] and render[3].valid then
        render[3].destroy()
    end
end

local function remove_old_renders(container)
    for key, _ in pairs(container.price) do
        remove_one_render(container, key)
    end
end

local function destroy_container_renders(container)
    for _, price in pairs(container and container.price or {}) do
        for _, render in pairs(price.render or {}) do
            if render and render.valid then
                render.destroy()
            end
        end
    end
end

local function clear_container_requests(entity)
    if not (entity and entity.valid) then
        return
    end

    local logi = entity.get_logistic_point(defines.logistic_member_index.logistic_container)
    if not logi then
        return
    end

    for i = 1, 256, 1 do
        if logi.get_section(i) then
            logi.remove_section(i)
        end
    end
end

local function register_container(expanse, entity, known_left_top)
    if not (entity and entity.valid and entity.name == 'requester-chest' and entity.unit_number) then
        return nil
    end

    expanse.containers = expanse.containers or {}
    local container = expanse.containers[entity.unit_number]

    local left_top = known_left_top
    if (not left_top or is_cell_open(expanse, left_top)) and container and container.left_top and not is_cell_open(expanse, container.left_top) then
        left_top = container.left_top
    end
    if not left_top or is_cell_open(expanse, left_top) then
        left_top = get_left_top(expanse, entity.position)
    end
    if not left_top or is_cell_open(expanse, left_top) then
        return nil
    end

    if not container then
        container = {
            entity = entity,
            left_top = left_top,
            price = {},
            revealed = false,
            force_name = expanse.force_name,
            surface_index = expanse.active_surface_index
        }
        expanse.containers[entity.unit_number] = container
        clear_container_requests(entity)
        return container
    end

    container.entity = entity
    container.left_top = container.left_top or left_top
    if is_cell_open(expanse, container.left_top) then
        container.left_top = left_top
    end
    container.price = container.price or {}
    if container.revealed == nil then
        container.revealed = next(container.price) ~= nil
    end
    container.force_name = expanse.force_name
    container.surface_index = expanse.active_surface_index
    if not container.revealed then
        clear_container_requests(entity)
    end

    return container
end

local function frontier_candidates_from_open_cell(expanse, left_top)
    local square_size = expanse.square_size
    return {
        {
            position = { x = left_top.x + cell_random_int(expanse, left_top, 1, square_size - 2), y = left_top.y },
            left_top = { x = left_top.x, y = left_top.y - square_size }
        },
        {
            position = { x = left_top.x, y = left_top.y + cell_random_int(expanse, left_top, 2, square_size - 2) },
            left_top = { x = left_top.x - square_size, y = left_top.y }
        },
        {
            position = { x = left_top.x + cell_random_int(expanse, left_top, 3, square_size - 2), y = left_top.y + (square_size - 1) },
            left_top = { x = left_top.x, y = left_top.y + square_size }
        },
        {
            position = { x = left_top.x + (square_size - 1), y = left_top.y + cell_random_int(expanse, left_top, 4, square_size - 2) },
            left_top = { x = left_top.x + square_size, y = left_top.y }
        }
    }
end

local function position_has_hungry_chest(surface, position)
    return surface.count_entities_filtered({
        name = 'requester-chest',
        force = 'neutral',
        area = { { position.x - 0.5, position.y - 0.5 }, { position.x + 0.5, position.y + 0.5 } }
    }) > 0
end

local function can_host_hungry_chest(surface, position)
    local tile = surface.get_tile(position.x, position.y)
    return tile
        and tile.valid
        and tile.name ~= 'out-of-map'
        and not position_has_hungry_chest(surface, position)
        and surface.can_place_entity({ name = 'requester-chest', position = position, force = 'neutral' })
end

local function find_hungry_chest_position(surface, position, square_size)
    if can_host_hungry_chest(surface, position) then
        return position
    end

    local max_radius = math.max(2, math.floor((square_size or 15) * 0.5))
    for radius = 1, max_radius, 1 do
        local candidate = surface.find_non_colliding_position('requester-chest', position, radius, 0.25)
        if candidate and can_host_hungry_chest(surface, candidate) then
            return candidate
        end
    end

    return nil
end

local function create_frontier_chest(expanse, surface, candidate)
    local unlock_left_top = is_container_position_valid(expanse, candidate.position, candidate.left_top)
    if not unlock_left_top then
        return false
    end

    local position = find_hungry_chest_position(surface, candidate.position, expanse.square_size)
    if not position then
        return false
    end

    unlock_left_top = is_container_position_valid(expanse, position, candidate.left_top)
    if not unlock_left_top then
        return false
    end

    local entity = surface.create_entity({ name = 'requester-chest', position = position, force = 'neutral' })
    if not entity then
        return false
    end
    entity.destructible = false
    entity.minable = false
    register_container(expanse, entity, unlock_left_top)
    return true
end

local function candidate_less(a, b)
    if a.position.x ~= b.position.x then
        return a.position.x < b.position.x
    end
    if a.position.y ~= b.position.y then
        return a.position.y < b.position.y
    end
    if a.left_top.x ~= b.left_top.x then
        return a.left_top.x < b.left_top.x
    end
    return a.left_top.y < b.left_top.y
end

local natural_enemy_entity_types = {
    unit = true,
    turret = true,
    ['unit-spawner'] = true,
    fish = true
}

local function is_natural_enemy_entity(entity)
    return entity
        and entity.valid
        and natural_enemy_entity_types[entity.type]
        and entity.force
        and (entity.force.name == 'enemy' or entity.force.name == 'neutral')
end

local function destroy_natural_enemy_entities(surface, area)
    if not (surface and surface.valid) then
        return 0
    end

    local filters = { type = { 'unit', 'turret', 'unit-spawner', 'fish' }, force = { 'enemy', 'neutral' } }
    if area then
        filters.area = area
    end

    local removed = 0
    for _, entity in pairs(surface.find_entities_filtered(filters)) do
        if is_natural_enemy_entity(entity) then
            entity.destroy()
            removed = removed + 1
        end
    end
    return removed
end

local function track_cell_biter(expanse, entity)
    if not (expanse and entity and entity.valid and entity.unit_number) then
        return
    end
    expanse.cell_biter_units = expanse.cell_biter_units or {}
    expanse.cell_biter_units[entity.unit_number] = true
end

local function create_tracked_enemy(expanse, surface, name, position)
    if not (surface and surface.valid and name and position) then
        return nil
    end
    local free_pos = surface.find_non_colliding_position(name, position, 8, 0.25)
        or surface.find_non_colliding_position(name, position, 16, 0.5)
    if not free_pos then
        return nil
    end
    local entity = surface.create_entity({ name = name, position = free_pos, force = 'enemy' })
    if entity then
        track_cell_biter(expanse, entity)
    end
    return entity
end

local function spawn_units_at_position(expanse, surface, position, salt)
    if not (surface and surface.valid and position) then
        return 0
    end

    local evolution = game.forces.enemy.get_evolution_factor(surface)
    local base = expanse and expanse.spawner_spawn_base or 4
    local scale = expanse and expanse.spawner_spawn_evolution_scale or 8
    local count = math.floor(base + math.floor(scale * evolution))
    if count <= 0 then
        return 0
    end

    local rng = expanse and expanse.sync_invasions ~= false and make_cell_rng(expanse, position, salt or 30000) or nil
    local created = 0
    for _ = 1, count, 1 do
        local biter_roll = BiterRaffle.roll('mixed', evolution, rng)
        if biter_roll then
            local candidate = { x = position.x + random_int(rng, -8, 8), y = position.y + random_int(rng, -8, 8) }
            local free_pos = surface.find_non_colliding_position(biter_roll, candidate, 12, 0.05)
                or surface.find_non_colliding_position(biter_roll, position, 12, 0.25)
            if free_pos then
                local unit = create_tracked_enemy(expanse, surface, biter_roll, free_pos)
                if unit then
                    created = created + 1
                end
            end
        end
    end
    return created
end

local function deterministic_cell_biter_position(expanse, left_top, salt)
    local square_size = expanse.square_size or 15
    local margin = square_size > 4 and 2 or 1
    local span = math.max(1, square_size - margin * 2)
    salt = salt or 8100
    return {
        x = left_top.x + margin + cell_random_int(expanse, left_top, salt + 2, span) - 1,
        y = left_top.y + margin + cell_random_int(expanse, left_top, salt + 3, span) - 1
    }
end

local function random_cell_biter_position(expanse, left_top)
    local square_size = expanse.square_size or 15
    local margin = square_size > 4 and 2 or 1
    local span = math.max(1, square_size - margin * 2)
    return {
        x = left_top.x + margin + math.random(0, span - 1),
        y = left_top.y + margin + math.random(0, span - 1)
    }
end

local function source_spawner_positions(expanse, source_surface, area, left_top, meta_cell)
    if meta_cell and meta_cell.cell_biter_source_positions then
        return table.deepcopy(meta_cell.cell_biter_source_positions)
    end

    local positions = {}
    if source_surface and source_surface.valid then
        for _, entity in pairs(source_surface.find_entities_filtered({ area = area, type = 'unit-spawner', force = 'enemy' })) do
            positions[#positions + 1] = {
                name = entity.name,
                x = entity.position.x,
                y = entity.position.y
            }
        end
    end
    table.sort(positions, function(a, b)
        if a.x ~= b.x then
            return a.x < b.x
        end
        return a.y < b.y
    end)

    if meta_cell then
        meta_cell.cell_biter_source_positions = table.deepcopy(positions)
        if #positions > 0 and meta_cell.cell_biter_spawn == nil then
            meta_cell.cell_biter_spawn = true
        end
    end

    return positions
end

local function camp_entry_position(entry)
    if not entry then
        return nil
    end
    if entry.position then
        return entry.position
    end
    return { x = entry.x, y = entry.y }
end

local function pick_spawner_name(rng)
    if random_int(rng, 1, 4) == 1 then
        return 'spitter-spawner'
    end
    return 'biter-spawner'
end

local function build_source_camp(source_positions)
    local camp = { entities = {}, unit_sources = {} }
    for _, entry in ipairs(source_positions or {}) do
        local position = camp_entry_position(entry)
        if position then
            camp.entities[#camp.entities + 1] = {
                name = entry.name or 'biter-spawner',
                position = { x = position.x, y = position.y }
            }
            camp.unit_sources[#camp.unit_sources + 1] = { x = position.x, y = position.y }
        end
    end
    return camp
end

local function build_synthetic_camp(expanse, left_top, meta_cell, surface)
    if expanse.sync_invasions == false then
        if math.random(1, 4) ~= 1 then
            return { entities = {}, unit_sources = {} }
        end
    elseif meta_cell then
        if meta_cell.cell_biter_spawn == nil then
            meta_cell.cell_biter_spawn = cell_random_int(expanse, left_top, 8101, 4) == 1
        end
        if not meta_cell.cell_biter_spawn then
            return { entities = {}, unit_sources = {} }
        end
    elseif cell_random_int(expanse, left_top, 8101, 4) ~= 1 then
        return { entities = {}, unit_sources = {} }
    end

    local rng = expanse.sync_invasions ~= false and make_cell_rng(expanse, left_top, 8200) or nil
    local evolution = surface and surface.valid and game.forces.enemy.get_evolution_factor(surface) or game.forces.enemy.evolution_factor
    local distance = math.sqrt(left_top.x ^ 2 + left_top.y ^ 2)
    local distance_bonus = math.min(2, math.floor(distance / 150))
    local evolution_bonus = math.min(2, math.floor(evolution * 3))
    local spawner_count = 1 + distance_bonus + evolution_bonus + random_int(rng, 0, 1)
    local worm_count = math.max(1, spawner_count - 1 + random_int(rng, 0, 2))
    local camp = { entities = {}, unit_sources = {} }

    if meta_cell and meta_cell.cell_biter_position then
        camp.entities[#camp.entities + 1] = {
            name = pick_spawner_name(rng),
            position = table.deepcopy(meta_cell.cell_biter_position)
        }
        camp.unit_sources[#camp.unit_sources + 1] = table.deepcopy(meta_cell.cell_biter_position)
    end

    while #camp.unit_sources < spawner_count do
        local index = #camp.unit_sources + 1
        local position = expanse.sync_invasions ~= false
            and deterministic_cell_biter_position(expanse, left_top, 8200 + index * 10)
            or random_cell_biter_position(expanse, left_top)
        camp.entities[#camp.entities + 1] = {
            name = pick_spawner_name(rng),
            position = position
        }
        camp.unit_sources[#camp.unit_sources + 1] = { x = position.x, y = position.y }
    end

    for index = 1, worm_count, 1 do
        local position = expanse.sync_invasions ~= false
            and deterministic_cell_biter_position(expanse, left_top, 9100 + index * 10)
            or random_cell_biter_position(expanse, left_top)
        camp.entities[#camp.entities + 1] = {
            name = BiterRaffle.roll('worm', evolution, rng) or 'small-worm-turret',
            position = position
        }
    end

    return camp
end

local function cell_biter_camp(expanse, left_top, source_positions, meta_cell, surface)
    if source_positions and #source_positions > 0 then
        local camp = build_source_camp(source_positions)
        if meta_cell and not meta_cell.cell_biter_camp then
            meta_cell.cell_biter_camp = table.deepcopy(camp)
        end
        return camp
    end
    if meta_cell and meta_cell.cell_biter_camp then
        return table.deepcopy(meta_cell.cell_biter_camp)
    end

    local camp = build_synthetic_camp(expanse, left_top, meta_cell, surface)
    if meta_cell and (camp.entities[1] or camp.unit_sources[1]) then
        meta_cell.cell_biter_camp = table.deepcopy(camp)
    end
    return camp
end

function Public.spawn_units(expanse, spawner)
    if spawner == nil and expanse and expanse.valid then
        spawner = expanse
        expanse = nil
    end
    if not (spawner and spawner.valid) then
        return 0
    end
    return spawn_units_at_position(expanse, spawner.surface, spawner.position, 30000)
end

function Public.spawn_cell_biters(expanse, surface, left_top, source_positions, meta_cell)
    if not (expanse and surface and surface.valid and left_top) then
        return 0
    end
    if game.tick == expanse.reset_tick then
        return 0
    end

    meta_cell = meta_cell or (expanse.sync_invasions ~= false and ensure_meta_cell(expanse, left_top) or nil)
    local camp = cell_biter_camp(expanse, left_top, source_positions, meta_cell, surface)
    local spawned = 0
    local structures = 0
    for _, entity in ipairs(camp.entities or {}) do
        local created = create_tracked_enemy(expanse, surface, entity.name, entity.position)
        if created then
            structures = structures + 1
        end
    end
    for index, position in ipairs(camp.unit_sources or {}) do
        spawned = spawned + spawn_units_at_position(expanse, surface, position, 32000 + index * 1000)
    end

    if spawned > 0 or structures > 0 then
        expanse.cell_biter_tracker = expanse.cell_biter_tracker or {}
        expanse.cell_biter_tracker.spawned = (expanse.cell_biter_tracker.spawned or 0) + spawned
        expanse.cell_biter_tracker.structures = (expanse.cell_biter_tracker.structures or 0) + structures
        expanse.cell_biter_tracker.last_spawn_tick = game.tick
        expanse.cell_biter_tracker.last_spawned = spawned
        expanse.cell_biter_tracker.last_structures = structures
        expanse.cell_biter_tracker.last_cell = { x = left_top.x, y = left_top.y }
    end
    return spawned
end

function Public.get_item_tooltip(name, quality, include_value, force)
    local value = include_value and Price_raffle.get_item_worth(name, qualities[quality], force) or ''
    local desc = include_value and 'expanse.stats_item_tooltip' or 'expanse.stats_item_tooltip_nv'
    if quality == 'normal' then
        return { desc, prototypes.item[name].localised_name, '', value }
    end
    return { desc, prototypes.item[name].localised_name, {'expanse.stats_quality', prototypes.quality[quality].localised_name or ''}, value }
end

function Public.invasion_numbers(expanse)
    local evo = game.forces.enemy.get_evolution_factor(game.surfaces[expanse.active_surface_index])
    return {
        candidates = (expanse.invasion_candidate_base or 3) + math.floor(evo * (expanse.invasion_candidate_evolution_scale or 10)),
        groups = (expanse.invasion_group_base or 1) + math.floor(evo * (expanse.invasion_group_evolution_scale or 4))
    }
end

function Public.invasion_warn(event)
    local seconds = ((event.total_delay_ticks or 120 * 60) - (event.delay or 0)) / 60
    local force_name = event.force_name or 'player'
    local message = { 'expanse.biters_invasion_warning', force_name, seconds, event.size }
    local color = { r = 0.88, g = 0.22, b = 0.22 }
    local force = game.forces[force_name]
    if force and force.valid then
        force.print(message, color)
    else
        game.print(message, color)
    end
end

function Public.invasion_detonate(event)
    local surface = event.surface
    local position = event.position
    local entities_close = surface.find_entities_filtered { position = position, radius = event.kill_radius or 8 }
    for _, entity in pairs(entities_close) do
        if entity.valid then
            entity.die('enemy')
        end
    end
    local entities_nearby = surface.find_entities_filtered { position = position, radius = event.damage_radius or 16 }
    for _, entity in pairs(entities_nearby) do
        if entity.valid and entity.is_entity_with_health then
            entity.damage(entity.max_health * (event.damage_fraction or 0.75), 'enemy')
        end
    end
    surface.create_entity({ name = 'nuke-explosion', position = position })
end

function Public.invasion_trigger(event)
    local surface = event.surface
    local position = event.position
    local round = event.round or 1
    local evolution = game.forces.enemy.get_evolution_factor(surface)
    local rng = event.sync_invasions and make_cell_rng({ shared_seed = event.seed }, position, (event.invasion_salt or 50000) + round * 1000) or nil
    local biters = {}
    local biter_count = (event.biter_base or 5) + math.floor((event.biter_evolution_scale or 30) * evolution) + math.floor(round * (event.biter_round_scale or 5))
    for i = 1, biter_count, 1 do
        local biter_roll = BiterRaffle.roll('mixed', evolution, rng)
        local free_pos = surface.find_non_colliding_position(biter_roll, { x = position.x + random_int(rng, -8, 8), y = position.y + random_int(rng, -8, 8) }, 12, 0.05)
        biters[#biters + 1] = surface.create_entity({ name = biter_roll, position = free_pos or position, force = 'enemy' })
    end
    local group = surface.create_unit_group { position = position, force = 'enemy' }
    for _, biter in pairs(biters) do
        group.add_member(biter)
    end
    group.set_command({ type = defines.command.attack_area, destination = position, radius = event.attack_radius or 80, distraction = defines.distraction.by_anything })
    group.start_moving()
    local worm_roll = BiterRaffle.roll('worm', evolution, rng)
    for i = 1, (event.worm_base or 3) + math.floor((event.worm_evolution_scale or 7) * evolution), 1 do
        local worm_pos = surface.find_non_colliding_position(worm_roll, { x = position.x + random_int(rng, -12, 12), y = position.y + random_int(rng, -12, 12) }, 12, 0.1)
        if worm_pos then
            surface.create_entity({ name = worm_roll, position = worm_pos, force = 'enemy' })
        end
    end
    local nest = { 'biter-spawner', 'biter-spawner', 'biter-spawner', 'spitter-spawner' }
    local nest_roll = nest[random_int(rng, 1, 4)]
    local nest_pos = surface.find_non_colliding_position(nest_roll, position, 12, 0.1)
    if nest_pos then
        surface.create_entity({ name = nest_roll, position = nest_pos, force = 'enemy' })
    end
end

local function schedule_detonation(expanse, surface, position)
    table.insert(expanse.schedule, {
        tick = game.tick + (expanse.invasion_detonate_delay_ticks or 120 * 60),
        event = 'invasion_detonate',
        parameters = {
            surface = surface,
            position = position,
            kill_radius = expanse.invasion_nuke_kill_radius,
            damage_radius = expanse.invasion_nuke_damage_radius,
            damage_fraction = expanse.invasion_nuke_damage_fraction
        }
    })
end

local function schedule_warning(expanse, size, delay)
    table.insert(expanse.schedule, {
        tick = game.tick + (expanse.invasion_first_warning_delay_ticks or 2 * 60) + delay,
        event = 'invasion_warn',
        parameters = {
            force_name = expanse.force_name,
            size = size,
            delay = delay,
            total_delay_ticks = expanse.invasion_detonate_delay_ticks
        }
    })
end

local function schedule_biters(expanse, surface, position, delay, round, group_index)
    table.insert(expanse.schedule, {
        tick = game.tick + delay + (expanse.invasion_detonate_delay_ticks or 120 * 60),
        event = 'invasion_trigger',
        parameters = {
            surface = surface,
            position = position,
            round = round,
            sync_invasions = expanse.sync_invasions ~= false,
            seed = expanse.shared_seed,
            invasion_salt = 50000 + (group_index or 0) * 1000,
            biter_base = expanse.invasion_biter_base,
            biter_evolution_scale = expanse.invasion_biter_evolution_scale,
            biter_round_scale = expanse.invasion_biter_round_scale,
            worm_base = expanse.invasion_worm_base,
            worm_evolution_scale = expanse.invasion_worm_evolution_scale,
            attack_radius = expanse.invasion_attack_radius
        }
    })
end

local function copy_invasion_candidates(candidates)
    local copy = {}
    for _, candidate in pairs(candidates or {}) do
        copy[#copy + 1] = candidate
    end
    return copy
end

local function sort_invasion_candidates_by_position(candidates)
    table.sort(candidates, function(a, b)
        local ax = a.position and a.position.x or 0
        local bx = b.position and b.position.x or 0
        if ax ~= bx then
            return ax < bx
        end
        local ay = a.position and a.position.y or 0
        local by = b.position and b.position.y or 0
        return ay < by
    end)
end

local function plan_invasion(expanse, invasion_numbers)
    local candidates = expanse.invasion_candidates
    if expanse.sync_invasions ~= false then
        candidates = copy_invasion_candidates(candidates)
        sort_invasion_candidates_by_position(candidates)
    else
        table.shuffle_table(candidates)
    end
    schedule_warning(expanse, invasion_numbers.groups, 0)
    schedule_warning(expanse, invasion_numbers.groups, expanse.invasion_extra_warning_1_ticks or 60 * 60)
    schedule_warning(expanse, invasion_numbers.groups, expanse.invasion_extra_warning_2_ticks or 90 * 60)
    local rounds = expanse.invasion_rounds_base or 4
    local random_rounds = expanse.invasion_rounds_random_max or 8
    if random_rounds > 0 then
        if expanse.sync_invasions ~= false then
            local anchor = candidates[1] and candidates[1].position or { x = 0, y = 0 }
            rounds = rounds + cell_random_int(expanse, anchor, 41000 + #candidates + invasion_numbers.groups, random_rounds)
        else
            rounds = rounds + math.random(1, random_rounds)
        end
    end
    for i = 1, invasion_numbers.groups, 1 do
        local surface_index = candidates[i].surface_index
        if not surface_index then break end
        local surface = game.get_surface(surface_index)
        local position = candidates[i].position
        schedule_detonation(expanse, surface, position)
        for ii = 1, rounds, 1 do
            schedule_biters(expanse, surface, position, (expanse.invasion_wave_first_delay_ticks or 120) + (ii - 1) * (expanse.invasion_wave_interval_ticks or 300), ii, i)
        end
        candidates[i].render.time_to_live = (expanse.invasion_detonate_delay_ticks or 120 * 60) + (expanse.invasion_render_grace_ticks or 120) + rounds * (expanse.invasion_wave_interval_ticks or 300)
    end
    for j = invasion_numbers.groups + 1, #candidates, 1 do
        candidates[j].render.time_to_live = (expanse.invasion_detonate_delay_ticks or 120 * 60) + (expanse.invasion_render_grace_ticks or 120)
    end
    expanse.invasion_candidates = {}
    expanse.invasion_candidate_cells = {}
    expanse.invasion_tracker = expanse.invasion_tracker or {}
    expanse.invasion_tracker.pending = 0
    expanse.invasion_tracker.required = invasion_numbers.candidates
    expanse.invasion_tracker.groups = invasion_numbers.groups
    expanse.invasion_tracker.last_plan_tick = game.tick
    expanse.invasion_tracker.last_planned_candidates = #candidates
    expanse.invasion_tracker.last_planned_groups = invasion_numbers.groups
    expanse.invasion_tracker.scheduled_invasions = (expanse.invasion_tracker.scheduled_invasions or 0) + 1
end

function Public.check_invasion(expanse)
    expanse.invasion_candidates = expanse.invasion_candidates or {}
    expanse.invasion_tracker = expanse.invasion_tracker or {}
    if expanse.invasion_enabled == false then
        expanse.invasion_candidates = {}
        expanse.invasion_candidate_cells = {}
        expanse.invasion_tracker.pending = 0
        expanse.invasion_tracker.required = 0
        expanse.invasion_tracker.groups = 0
        return
    end
    local invasion_numbers = Public.invasion_numbers(expanse)
    expanse.invasion_tracker.pending = #expanse.invasion_candidates
    expanse.invasion_tracker.required = invasion_numbers.candidates
    expanse.invasion_tracker.groups = invasion_numbers.groups
    if #expanse.invasion_candidates >= invasion_numbers.candidates then
        plan_invasion(expanse, invasion_numbers)
        return true
    end
    return false
end

function Public.ensure_frontier_chests(expanse)
    if not (expanse and expanse.active_surface_index) then
        return 0
    end

    local surface = game.surfaces[expanse.active_surface_index]
    if not (surface and surface.valid) then
        return 0
    end

    expanse.containers = expanse.containers or {}

    for unit_number, container in pairs(expanse.containers) do
        local entity = container.entity
        if not (entity and entity.valid) or entity.surface.index ~= surface.index then
            destroy_container_renders(container)
            expanse.containers[unit_number] = nil
        elseif not container.left_top or is_cell_open(expanse, container.left_top) then
            destroy_container_renders(container)
            entity.destroy()
            expanse.containers[unit_number] = nil
        end
    end

    for _, entity in pairs(surface.find_entities_filtered({ name = 'requester-chest', force = 'neutral' })) do
        if not expanse.containers[entity.unit_number] then
            local left_top = get_left_top(expanse, entity.position)
            if left_top and not is_cell_open(expanse, left_top) and not has_container_for_left_top(expanse, left_top) then
                register_container(expanse, entity, left_top)
            else
                entity.destroy()
            end
        end
    end

    local candidates_by_left_top = {}
    for key, is_open in pairs(expanse.grid or {}) do
        if is_open then
            local open_left_top = parse_grid_key(key)
            if open_left_top then
                for _, candidate in pairs(frontier_candidates_from_open_cell(expanse, open_left_top)) do
                    if not is_cell_open(expanse, candidate.left_top) and not has_container_for_left_top(expanse, candidate.left_top) then
                        local candidate_key = grid_key(candidate.left_top)
                        candidates_by_left_top[candidate_key] = candidates_by_left_top[candidate_key] or {}
                        candidates_by_left_top[candidate_key][#candidates_by_left_top[candidate_key] + 1] = candidate
                    end
                end
            end
        end
    end

    local keys = {}
    for key, _ in pairs(candidates_by_left_top) do
        keys[#keys + 1] = key
    end
    table.sort(keys)

    local created = 0
    for _, key in ipairs(keys) do
        local candidates = candidates_by_left_top[key]
        table.sort(candidates, candidate_less)
        for _, candidate in ipairs(candidates) do
            if not is_cell_open(expanse, candidate.left_top) and not has_container_for_left_top(expanse, candidate.left_top) then
                if create_frontier_chest(expanse, surface, candidate) then
                    created = created + 1
                    break
                end
            end
        end
    end

    return created
end

local function calculate_tier(expanse, left_top)
    local distances = expanse.tier_distance_thresholds or default_tier_distance_thresholds
    local tier = 5
    local distance = math.sqrt(left_top.x ^ 2 + left_top.y ^ 2)
    for i = 1, #distances - 1, 1 do
        if distance < distances[i] then
            tier = i
            break
        end
    end
    if Mode.is_space_age() then
        local biomes = {
            6, --vulcanus
            7, --fulgora
            8, --gleba
            9, --aquilo
        }
        if distance > distances[5] and distance < distances[6] then
            if left_top.x >= 0 and left_top.y >= 0 then
                tier = biomes[(expanse.biome_offset + 1) % 4 + 1]
            elseif left_top.x >= 0 and left_top.y < 0 then
                tier = biomes[(expanse.biome_offset + 2) % 4 + 1]
            elseif left_top.x < 0 and left_top.y >= 0 then
                tier = biomes[(expanse.biome_offset + 3) % 4 + 1]
            elseif left_top.x < 0 and left_top.y < 0 then
                tier = biomes[(expanse.biome_offset + 4) % 4 + 1]
            end
        elseif distance >= distances[6] then
            tier = 10
        end
    end
    return tier, distance
end

function Public.expand(expanse, left_top)
    expanse.grid[tostring(left_top.x .. '_' .. left_top.y)] = true
    local meta_cell = expanse.sync_cell_content ~= false and ensure_meta_cell(expanse, left_top) or nil
    local tier, distance = calculate_tier(expanse, left_top)
    if meta_cell then
        meta_cell.tier = meta_cell.tier or tier
        meta_cell.distance = meta_cell.distance or distance
        tier = meta_cell.tier
    end
    local square_size = expanse.square_size
    -- if tier == 7 then
    --     expanse.lightning_tiles[#expanse.lightning_tiles + 1] = {x = left_top.x + square_size / 2, y = left_top.y + square_size / 2}
    -- end

    local source_surface = game.surfaces[expanse.source_surface]
    if not source_surface then
        return
    end
    source_surface.request_to_generate_chunks(left_top, 2)
    source_surface.force_generate_chunk_requests()

    local area = { { left_top.x, left_top.y }, { left_top.x + square_size, left_top.y + square_size } }
    local surface = game.surfaces[expanse.active_surface_index]
    local source_positions = source_spawner_positions(expanse, source_surface, area, left_top, meta_cell)
    destroy_natural_enemy_entities(source_surface, area)

    source_surface.clone_area(
        {
            source_area = area,
            destination_area = area,
            destination_surface = surface,
            clone_tiles = true,
            clone_entities = game.tick ~= expanse.reset_tick,
            clone_decoratives = game.tick ~= expanse.reset_tick and (tier < 6 or tier > 9),
            clear_destination_entities = false,
            clear_destination_decoratives = true,
            expand_map = true
        }
    )
    destroy_natural_enemy_entities(surface, area)
    Public.spawn_cell_biters(expanse, surface, left_top, source_positions, meta_cell)

    if not expanse.suppress_hungry_chests then
        for _, candidate in pairs(frontier_candidates_from_open_cell(expanse, left_top)) do
            create_frontier_chest(expanse, surface, candidate)
        end
    end
    local custom_tier = tier
    if tier == 10 then
        if meta_cell and meta_cell.custom_tier then
            custom_tier = meta_cell.custom_tier
        elseif expanse.tiered_specials[tier].specials == 0 or cell_random_int(expanse, left_top, 5, expanse.tier10_special_chance or 20) ~= 1 then
            custom_tier = 5 + cell_random_int(expanse, left_top, 6, 4)
            if meta_cell then
                meta_cell.custom_tier = custom_tier
            end
        elseif meta_cell then
            meta_cell.custom_tier = custom_tier
        end
    elseif meta_cell then
        meta_cell.custom_tier = custom_tier
    end

    SpaceMissions.convert_tiles(surface, left_top, custom_tier, square_size)
    SpaceMissions.convert_entities(surface, left_top, custom_tier, square_size)
    SpaceMissions.convert_decoratives(surface, left_top, custom_tier, square_size)
    SpaceMissions.place_special_tiered_object(expanse, tier, surface, left_top, custom_tier)

    if game.tick == expanse.reset_tick then
        local a = math.floor(expanse.square_size * 0.5)
        for x = 1, 3, 1 do
            for y = 1, 3, 1 do
                surface.set_tiles({ { name = 'water', position = { a + x + 2, a + y + 2 } } }, true)
            end
        end
        surface.create_entity({ name = 'crude-oil', position = { a - 4, a - 4 }, amount = 1500000 })
        Task.set_timeout_in_ticks(30, delay_infini_tree_token, { surface = surface, position = { a - 4, a + 4 }, expanse = expanse })
        surface.create_entity({ name = 'big-rock', position = { a + 4, a - 4 } })
        surface.spill_item_stack({ position = { a, a + 2 }, stack = { name = 'coin', count = 1 }, enable_looted = false, allow_belts = false })
        surface.spill_item_stack({ position = { a + 0.5, a + 2.5 }, stack = { name = 'coin', count = 1 }, enable_looted = false, allow_belts = false })
        surface.spill_item_stack({ position = { a - 0.5, a + 2.5 }, stack = { name = 'coin', count = 1 }, enable_looted = false, allow_belts = false })

        for x = 0, square_size, 1 do
            for y = 0, square_size, 1 do
                if surface.can_place_entity({ name = 'wooden-chest', position = { x, y } }) and surface.can_place_entity({ name = 'coal', position = { x, y }, amount = 1 }) then
                    surface.create_entity({ name = ores[(x + y) % 4 + 1], position = { x, y }, amount = 1500 })
                end
            end
        end
    end
end

local function get_tier_locker(tier)
    local SA = Mode.is_space_age()
    local lockers = {
        [5] = 'space-science-pack',
        [6] = SA and 'metallurgic-science-pack' or nil,
        [7] = SA and 'electromagnetic-science-pack' or nil,
        [8] = SA and 'agricultural-science-pack' or nil,
        [9] = SA and 'cryogenic-science-pack' or nil,
        [10] = SA and 'promethium-science-pack' or nil
    }
    return lockers[tier]
end

local function init_container(expanse, entity, budget, known_left_top)
    local left_top = known_left_top
    if not left_top or is_cell_open(expanse, left_top) then
        left_top = get_left_top(expanse, entity.position)
    end
    if not left_top then
        return
    end
    local tier_multi = {
        [1] = 1,
        [2] = 1,
        [3] = 1.5,
        [4] = 1.5,
        [5] = 2,
        [6] = 1,
        [7] = 1,
        [8] = 1,
        [9] = 1,
        [10] = 3
    }
    local tier, distance = calculate_tier(expanse, left_top)
    -- Cell tier/distance are world layout: deterministic per (planet, position) and shared
    -- across teams, so cache them on the meta cell. The PRICE and its rerolls are per-team:
    -- the reroll generation lives on THIS container, never on the shared meta cell, so one
    -- team rerolling (or feeding) a chest can never change another team's chest.
    local meta_cell = expanse.sync_cell_content ~= false and ensure_meta_cell(expanse, left_top) or nil
    if meta_cell then
        tier = meta_cell.tier or tier
        distance = meta_cell.distance or distance
        meta_cell.tier = tier
        meta_cell.distance = distance
    end
    local existing = expanse.containers[entity.unit_number]
    local reroll_generation = (existing and existing.reroll_generation) or 0
    local cell_value = budget or get_cell_value(expanse, left_top) * tier_multi[tier]
    -- Generation 0 is deterministic per planet+position, so every team starts with the same
    -- offer; each reroll advances only this container's generation.
    local item_stacks = {}
    local locker = get_tier_locker(tier)
    if locker then
        item_stacks[locker] = {['normal'] = 10}
    end
    local roll_count = expanse.price_roll_count or 3
    for roll_index = 1, roll_count, 1 do
        local rng = expanse.sync_cell_content ~= false and make_cell_rng(expanse, left_top, 10000 + reroll_generation * 100000 + roll_index * 1000) or nil
        for _, stack in pairs(Price_raffle.roll(math.floor(cell_value / roll_count), 3, tier, nil, state_force(expanse), rng)) do
            if not item_stacks[stack.name] then
                item_stacks[stack.name] = {[stack.quality] = stack.count}
            elseif not item_stacks[stack.name][stack.quality] then
                item_stacks[stack.name][stack.quality] = stack.count
            else
                item_stacks[stack.name][stack.quality] = item_stacks[stack.name][stack.quality] + stack.count
            end
        end
    end

    local price_entries = {}
    local names = {}
    for name, _ in pairs(item_stacks) do
        names[#names + 1] = name
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local quality_names = {}
        for quality, _ in pairs(item_stacks[name]) do
            quality_names[#quality_names + 1] = quality
        end
        table.sort(quality_names)
        for _, quality in ipairs(quality_names) do
            price_entries[#price_entries + 1] = { name = name, quality = quality, count = item_stacks[name][quality] }
        end
    end

    local price = {}
    local offset = -3
    for _, entry in ipairs(price_entries) do
        table.insert(price, { name = entry.name, count = entry.count, quality = entry.quality, render = create_costs_render(entity, entry.name, offset, entry.quality) })
        offset = offset + 1
    end
    if _DEBUG then
        game.print('distance: ' .. distance .. ', tier: ' .. tier .. ', value: ' .. cell_value)
    end
    local containers = expanse.containers
    containers[entity.unit_number] = {
        entity = entity,
        left_top = left_top,
        price = price,
        revealed = true,
        reroll_generation = reroll_generation,
        force_name = expanse.force_name,
        surface_index = expanse.active_surface_index
    }
end

local function get_remaining_budget(expanse, container)
    local budget = 0
    for _, item_stack in pairs(container.price) do
        budget = budget + (item_stack.count * Price_raffle.get_item_worth(item_stack.name, qualities[item_stack.quality], state_force(expanse)))
    end
    return budget
end

function Public.make_key(name, quality)
    return name .. '|' .. quality
end

function Public.split_key(key)
    return string.match(key, '^(.-)|(.+)$')
end

local function price_request_signature(price)
    local parts = {}
    for index, item in ipairs(price or {}) do
        parts[index] = table.concat({ item.name, item.quality, tostring(item.count) }, '|')
    end
    return table.concat(parts, ';')
end

local function sync_container_requests(container, force)
    local logi = container.entity.get_logistic_point(defines.logistic_member_index.logistic_container)
    if not logi then
        return
    end
    local signature = price_request_signature(container.price)
    if not force and container.request_signature == signature then
        return
    end
    for i = 1, 256, 1 do
        if logi.get_section(i) then
            logi.remove_section(i)
        end
    end

    logi.add_section()
    local section = logi.get_section(1)

    for slot = 1, #container.price, 1 do
        if #container.price >= slot then
            local item = container.price[slot]
            section.set_slot(slot, { value = {type = 'item', name = item.name, quality = item.quality, comparator = '='}, min = item.count })
        end
    end
    container.request_signature = signature
end

function Public.set_container(expanse, entity, known_left_top, reveal)
    if entity.name ~= 'requester-chest' then
        return
    end
    local should_reveal = reveal ~= false
    local container = register_container(expanse, entity, known_left_top)
    if not container then
        return
    end
    if not container.revealed then
        if not should_reveal then
            return
        end
        init_container(expanse, entity, nil, container.left_top)
    end
    container = expanse.containers[entity.unit_number]
    if not container or not container.entity or not container.entity.valid then
        expanse.containers[entity.unit_number] = nil
        return
    end
    if not container.left_top or is_cell_open(expanse, container.left_top) then
        local left_top = get_left_top(expanse, entity.position)
        if left_top then
            container.left_top = left_top
        end
    end

    local inventory = container.entity.get_inventory(defines.inventory.chest)
    local trash_inventory = container.entity.get_inventory(defines.inventory.logistic_container_trash)

    if not inventory.is_empty() then
        if inventory.get_item_count('coin') > 0 then
            local count_removed = inventory.remove({ name = 'coin', count = 1 })
            if count_removed > 0 then
                expanse.cost_stats[Public.make_key('coin', 'normal')] = (expanse.cost_stats[Public.make_key('coin', 'normal')] or 0) + count_removed
                script.raise_event(expanse.events.gui_update, { item = 'coin', quality = 'normal', force_name = expanse.force_name })
                local remaining_budget = get_remaining_budget(expanse, container)
                -- Per-team reroll: advance only THIS container's generation; never touch the
                -- shared meta cell, so other teams' chests are completely unaffected.
                container.reroll_generation = (container.reroll_generation or 0) + 1
                remove_old_renders(container)
                init_container(expanse, entity, remaining_budget, container.left_top)
                container = expanse.containers[entity.unit_number]
                game.print({ 'expanse.chest_reset', { 'expanse.gps', math.floor(entity.position.x), math.floor(entity.position.y), game.surfaces[expanse.active_surface_index].name } })
            end
        end
        if _DEBUG and inventory.get_item_count('infinity-chest') > 0 then
            remove_old_renders(container)
            container.price = {}
        end
    end

    for key = #container.price, 1, -1 do
        local item_stack = container.price[key]
        local name = item_stack.name
        local quality = item_stack.quality
        local count_removed = inventory.remove({ name = name, count = item_stack.count, quality = item_stack.quality})
        container.price[key].count = container.price[key].count - count_removed
        if count_removed > 0 then
            expanse.cost_stats[Public.make_key(name, quality)] = (expanse.cost_stats[Public.make_key(name, quality)] or 0) + count_removed
            script.raise_event(expanse.events.gui_update, { item = name, quality = quality, force_name = expanse.force_name})
            if container.price[key].count <= 0 then
                remove_one_render(container, key)
                table.remove(container.price, key)
            end
        end
    end

    if #container.price == 0 then
        local unlock_left_top = container.left_top
        Public.expand(expanse, unlock_left_top)
        local a = math.floor(expanse.square_size * 0.5)
        local expansion_position = { x = unlock_left_top.x + a, y = unlock_left_top.y + a }
        expanse.containers[entity.unit_number] = nil
        for _, inv in pairs({inventory, trash_inventory}) do
            if not inv.is_empty() then
                for index = 1, #inv, 1 do
                    local slot = inv[index]
                    if slot.valid_for_read then
                        entity.surface.spill_item_stack({ position = entity.position, stack = slot, enable_looted = true, allow_belts = false })
                    end
                end
            end
        end
        reward_tokens(expanse, entity)
        entity.destructible = true
        entity.die()
        return expansion_position
    end
    sync_container_requests(container, should_reveal)
end

Public.cell_random_int = cell_random_int
Public.ensure_meta_cell = ensure_meta_cell

function Public.chest_value(expanse, player)
    if not player or not player.valid then return end
    local position = player.position
    local chests = player.surface.find_entities_filtered({ name = 'requester-chest', force = 'neutral', position = position, radius = 10})
    for _, chest in pairs(chests) do
        local container = expanse.containers[chest.unit_number]
        local value = container and get_remaining_budget(expanse, container) or 0
        player.print({'expanse.chest_value', value, {'expanse.gps', chest.position.x, chest.position.y, chest.surface.name}})
    end
end

return Public
