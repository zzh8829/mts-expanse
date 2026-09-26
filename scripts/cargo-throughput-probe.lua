-- Loaded only into disposable native Factorio test profiles.
local Event = require 'utils.event'
local Missions = require 'maps.expanse.space_missions'
local Data = require 'maps.expanse.mission_data'
local Public = {}
local FIRST_PRODUCTION = 10800
local INTERVAL = 3600

local function add_contents(totals, inventory)
    for _, item in pairs(inventory.get_contents()) do
        local key = item.name .. '|' .. item.quality
        totals[key] = (totals[key] or 0) + item.count
    end
end

local function contents(state)
    local hub = state.use_space_platform and state.space_platform.hub or state.nonspace_pad
    local inventory = hub.get_inventory(state.use_space_platform and defines.inventory.hub_main or defines.inventory.cargo_landing_pad_main)
    local totals = {}
    add_contents(totals, inventory)
    for _, buffer in pairs(state.reward_overflow or {}) do add_contents(totals, buffer) end
    return totals
end

local function equal_counts(actual, expected)
    for key, count in pairs(expected) do if (actual[key] or 0) ~= count then return false end end
    for key, count in pairs(actual) do if (expected[key] or 0) ~= count then return false end end
    return true
end

local function setup(state, config)
    local surface = game.surfaces[state.active_surface_index]
    surface.request_to_generate_chunks({45, 45}, 1)
    surface.force_generate_chunk_requests()
    local tiles = {}
    for x = 35, 55 do
        for y = 35, 55 do tiles[#tiles + 1] = {name = 'grass-1', position = {x, y}} end
    end
    surface.set_tiles(tiles)
    local pad = assert(surface.create_entity{name = 'cargo-landing-pad', position = {45, 45}, force = 'team-1'})
    pad.destructible = false
    state.landing_pad = pad
    local rates = {}
    for tier = 4, config.endgame and 10 or 4 do
        for _, reward in ipairs(Data.rewards[tier]) do
            for key, count in pairs(reward.production or {}) do rates[key] = (rates[key] or 0) + count end
        end
    end
    state.space_production = rates
    state.space_production_interval_ticks = INTERVAL
    if config.requests then
        local point = pad.get_logistic_point(defines.logistic_member_index.cargo_landing_pad_requester)
        local section = point.get_section(1) or point.add_section()
        local keys = {}
        for key in pairs(rates) do keys[#keys + 1] = key end
        table.sort(keys)
        for i, key in ipairs(keys) do
            local name, quality = Missions.split_key(key)
            section.set_slot(i, {value = {name = name, quality = quality, type = 'item', comparator = '='}, min = rates[key] * 2})
        end
    end
    local hub = state.use_space_platform and state.space_platform.hub or state.nonspace_pad
    local launcher = state.use_space_platform and hub or state.nonspace_silo
    return {
        rates = rates, received = {}, expected = {}, generated = {}, cycles = {},
        matched = true, source_hatches = #launcher.cargo_hatches, pad_hatches = #pad.cargo_hatches,
        ground_before = surface.count_entities_filtered{type = 'item-entity'}
    }
end

function Public.install(Expanse, config)
    Event.on_init(function() Expanse.reset('team-1') end)
    -- Measure what entered the real source inventories, independently of arrivals.
    local produce = Missions.produce_space_goods
    Missions.produce_space_goods = function(state)
        local audit = storage.throughput
        local before = audit and state.force_name == 'team-1' and contents(state)
        produce(state)
        if before then
            for key, count in pairs(contents(state)) do
                audit.generated[key] = (audit.generated[key] or 0) + math.max(0, count - (before[key] or 0))
            end
        end
    end
    Event.add(defines.events.on_tick, function()
        if game.tick < 10001 then return end
        local state = Expanse.test_state('team-1')
        local audit = storage.throughput
        if not audit then audit = setup(state, config); storage.throughput = audit end
        if audit.done then return end
        local inventory = state.landing_pad.get_inventory(defines.inventory.cargo_landing_pad_main)
        local blocked = config.blocked and game.tick < FIRST_PRODUCTION + 2 * INTERVAL
        if config.blocked and not blocked and not audit.resumed then
            assert(not inventory.is_empty(), 'blocked pad never received cargo')
            assert(next(contents(state)), 'blocked pad did not retain source cargo')
            state.space_production = {} -- Drain only previously generated cargo, checking conservation.
            audit.resumed = game.tick
        end
        if not blocked and game.tick % config.drain_every == 0 then
            if not inventory.is_empty() then audit.last_receipt_tick = game.tick end
            add_contents(audit.received, inventory)
            inventory.clear() -- Simulate downstream users clearing the pad, not cargo teleportation.
        end
        if game.tick >= FIRST_PRODUCTION and (game.tick + 1 - FIRST_PRODUCTION) % INTERVAL == 0 then
            local cycles = (game.tick + 1 - FIRST_PRODUCTION) / INTERVAL
            if config.blocked then
                audit.expected = table.deepcopy(audit.generated)
            else
                for key, count in pairs(audit.rates) do audit.expected[key] = cycles * count end
            end
            local matched = equal_counts(audit.received, audit.expected) and equal_counts(audit.generated, audit.expected)
            if not config.blocked then audit.matched = audit.matched and matched end
            audit.cycles[#audit.cycles + 1] = {
                tick = game.tick, received = table.deepcopy(audit.received), source = contents(state),
                matched = matched, last_receipt_tick = audit.last_receipt_tick
            }
            if cycles >= config.cycles then
                audit.done = true
                audit.matched = audit.matched and matched
                audit.spilled = state.landing_pad.surface.count_entities_filtered{type = 'item-entity'} - audit.ground_before
                assert(audit.spilled == 0, 'cargo spilled on the ground')
                state.space_production = {}
                helpers.write_file('throughput.json', helpers.table_to_json(audit))
            end
        end
    end)
end
return Public
