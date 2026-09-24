-- The infinite rock's ore spill, and the penalty for burying the rock.
--
-- Ore lands anywhere on the team's island. The engine is told to search as far as the
-- farthest unlocked cell plus one tile of void (a square: that is how max_radius works),
-- which is every tile of the surface that can hold an item. Without that bound the engine
-- keeps searching the void for each item, and on an island already covered in ore one
-- mine of ~120 items hung a 2.0.77 headless server for minutes.
--
-- The penalty: a mine whose ore lands more than the spill radius from the rock (map
-- setting, 32 tiles by default, admins only) is a strike against the miner. The engine
-- fills outward, so ore that far out means the ground nearer the rock is buried. A strike
-- costs a tenth of max health, health cannot climb back above the strike level while the
-- episode lasts, and the tenth strike kills. Stopping stops it. The team is warned on the
-- first strike of an episode and told when the miner dies. Nothing runs on a tick.
--
-- Only ore on the ground counts, read from the positions the engine returns. Ore that
-- belts carry away is never in that list, so a belt-fed rock is safe.
local Event = require 'utils.event'

local Public = {}

local STRIKE_FRACTION = 0.1
local STRIKES_TO_DIE = 10
-- A strike this long after the previous one starts a fresh episode: warn again, count from 0.
local EPISODE_GAP_TICKS = 60 * 60
local WARNING_COLOR = { r = 1, g = 0.35, b = 0.25 }

-- storage.expanse_rock_spill.buried[player_index] = { last_tick, strikes, fatal }
-- A named storage key rather than Global.register: this mod's utils/global.lua keys
-- registrations by call order, so a new one would shift every later module's table on
-- existing saves.
local function buried_table()
    storage.expanse_rock_spill = storage.expanse_rock_spill or { buried = {} }
    return storage.expanse_rock_spill.buried
end

local function chebyshev(a, b)
    return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

-- Distance from position to the farthest corner of any unlocked cell, plus one tile of
-- void, so a spill bounded by it can reach every tile of the island and nothing beyond.
-- Recomputed only when the cell count changes; a team unlocks cells far less often than it
-- mines the rock.
local function island_radius(state, surface, position)
    local size = state.size or 1
    if state.island_radius and state.island_radius_size == size then
        return state.island_radius
    end
    local square = state.square_size
    local radius = square
    for key in pairs(state.grid or {}) do
        local x, y = key:match('^(-?%d+)_(-?%d+)$')
        x, y = tonumber(x), tonumber(y)
        if x and y then
            for _, corner in ipairs({
                { x = x, y = y }, { x = x + square, y = y },
                { x = x, y = y + square }, { x = x + square, y = y + square }
            }) do
                radius = math.max(radius, chebyshev(corner, position))
            end
        end
    end
    radius = math.ceil(radius) + 1
    -- The engine spills into chunks that do not exist yet, and those items vanish when the
    -- chunk is generated and voided. Make every chunk the search can reach exist first.
    surface.request_to_generate_chunks(position, math.ceil(radius / 32) + 1)
    surface.force_generate_chunk_requests()
    state.island_radius = radius
    state.island_radius_size = size
    return radius
end

-- True when any of the mine's ore landed more than radius tiles from position. placed is
-- the array of item-on-ground entities the mine created.
local function spilled_beyond(position, radius, placed)
    for _, item in pairs(placed) do
        if item.valid and chebyshev(item.position, position) > radius then
            return true
        end
    end
    return false
end

local function warn(force, player, radius)
    if force and force.valid then
        force.print({ 'expanse.rock-spill-warning-team', player.name, radius }, WARNING_COLOR)
    end
    player.print({ 'expanse.rock-spill-warning-player', radius, STRIKES_TO_DIE }, WARNING_COLOR)
end

-- One strike: warn if this is a new episode, then clamp health to the strike level, or
-- kill on the last one.
local function strike(force, player, radius)
    if not (player and player.valid) then
        return
    end
    local buried = buried_table()
    local entry = buried[player.index]
    if not entry or game.tick - entry.last_tick > EPISODE_GAP_TICKS then
        entry = { strikes = 0 }
        buried[player.index] = entry
        warn(force, player, radius)
    end
    entry.last_tick = game.tick
    entry.strikes = entry.strikes + 1
    local character = player.character
    if not (character and character.valid) then
        return
    end
    if entry.strikes >= STRIKES_TO_DIE then
        entry.fatal = true
        character.die()
    else
        -- Clamp rather than subtract: regeneration and fish cannot undo a strike.
        local ceiling = character.max_health * (1 - STRIKE_FRACTION * entry.strikes)
        character.health = math.min(character.health, ceiling)
    end
end

-- Spill ore next to the rock, anywhere on the team's island. When args.miner is a player
-- and some of the ore lands more than args.radius tiles away, that player takes a strike.
-- args: state, surface, position, name, count, radius, force?, miner?
function Public.spill(args)
    local placed = args.surface.spill_item_stack({
        position = args.position,
        stack = { name = args.name, count = args.count },
        enable_looted = true,
        allow_belts = true,
        max_radius = island_radius(args.state, args.surface, args.position),
        use_start_position_on_failure = false
    })
    if args.miner and spilled_beyond(args.position, args.radius, placed) then
        strike(args.force, args.miner, args.radius)
    end
end

local function on_player_died(event)
    local buried = storage.expanse_rock_spill and storage.expanse_rock_spill.buried
    local entry = buried and buried[event.player_index]
    if not entry then
        return
    end
    buried[event.player_index] = nil
    local player = game.get_player(event.player_index)
    if entry.fatal and player and player.valid and player.force.valid then
        player.force.print({ 'expanse.rock-spill-death', player.name }, WARNING_COLOR)
    end
end

Event.add(defines.events.on_player_died, on_player_died)

return Public
