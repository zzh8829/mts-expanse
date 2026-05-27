--[[
Use roll(entity_type, evolution_factor), to get a fitting enemy for the current or custom evolution factor.

entity_type 		- can be "spitter", "biter", "mixed", "worm"
evolution_factor 	- custom evolution factor (optional)
]]
local Public = {}
local math_random = math.random
local math_floor = math.floor

local function random_int(rng, min, max)
    if rng then
        return rng(min, max)
    end
    return math_random(min, max)
end

local function get_raffle_table(level, name)
    local raffle = {
        ['small-' .. name] = 1000 - level * 1.75,
        ['medium-' .. name] = -250 + level * 1.5,
        ['big-' .. name] = 0,
        ['behemoth-' .. name] = 0
    }

    if level > 500 then
        raffle['medium-' .. name] = 500 - (level - 500)
        raffle['big-' .. name] = (level - 500) * 2
    end
    if level > 900 then
        raffle['behemoth-' .. name] = (level - 900) * 3
    end
    for k, _ in pairs(raffle) do
        if raffle[k] < 0 then
            raffle[k] = 0
        end
    end
    return raffle
end

local function roll(evolution_factor, name, rng)
    local raffle = get_raffle_table(math_floor(evolution_factor * 1000), name)
    local max_chance = 0
    local order = {
        'small-' .. name,
        'medium-' .. name,
        'big-' .. name,
        'behemoth-' .. name
    }
    for _, key in ipairs(order) do
        max_chance = max_chance + raffle[key]
    end
    local r = random_int(rng, 0, math_floor(max_chance))
    local current_chance = 0
    for _, k in ipairs(order) do
        local v = raffle[k]
        current_chance = current_chance + v
        if r <= current_chance then
            return k
        end
    end
end

local function get_biter_name(evolution_factor, rng)
    return roll(evolution_factor, 'biter', rng)
end

local function get_spitter_name(evolution_factor, rng)
    return roll(evolution_factor, 'spitter', rng)
end

local function get_worm_raffle_table(level)
    local raffle = {
        ['small-worm-turret'] = 1000 - level * 1.75,
        ['medium-worm-turret'] = level,
        ['big-worm-turret'] = 0,
        ['behemoth-worm-turret'] = 0
    }

    if level > 500 then
        raffle['medium-worm-turret'] = 500 - (level - 500)
        raffle['big-worm-turret'] = (level - 500) * 2
    end
    if level > 900 then
        raffle['behemoth-worm-turret'] = (level - 900) * 3
    end
    for k, _ in pairs(raffle) do
        if raffle[k] < 0 then
            raffle[k] = 0
        end
    end
    return raffle
end

local function get_worm_name(evolution_factor, rng)
    local raffle = get_worm_raffle_table(math_floor(evolution_factor * 1000))
    local max_chance = 0
    local order = {
        'small-worm-turret',
        'medium-worm-turret',
        'big-worm-turret',
        'behemoth-worm-turret'
    }
    for _, key in ipairs(order) do
        max_chance = max_chance + raffle[key]
    end
    local r = random_int(rng, 0, math_floor(max_chance))
    local current_chance = 0
    for _, k in ipairs(order) do
        local v = raffle[k]
        current_chance = current_chance + v
        if r <= current_chance then
            return k
        end
    end
end

local function get_unit_name(evolution_factor, rng)
    if random_int(rng, 1, 3) == 1 then
        return get_spitter_name(evolution_factor, rng)
    else
        return get_biter_name(evolution_factor, rng)
    end
end

local type_functions = {
    ['spitter'] = get_spitter_name,
    ['biter'] = get_biter_name,
    ['mixed'] = get_unit_name,
    ['worm'] = get_worm_name
}

function Public.roll(entity_type, evolution_factor, rng)
    if not entity_type then
        return
    end
    if not type_functions[entity_type] then
        return
    end
    local evo = evolution_factor
    if not evo then
        evo = game.forces.enemy.evolution_factor
    end
    return type_functions[entity_type](evo, rng)
end

return Public
