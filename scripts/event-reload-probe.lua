-- Installed only into disposable test copies by test-event-reload.py.
local Event = require 'utils.event'
local Functions = require 'maps.expanse.functions'
local Public = {}

function Public.install(Expanse, mts, bootstrap)
    local names = mts and {'team-1', 'team-2'} or {'player'}
    local events = Expanse.test_events()
    for _, name in ipairs({'gui_update', 'mission_gui_update', 'invasion_warn', 'invasion_detonate', 'invasion_trigger', 'victory', 'map_reset'}) do
        Event.add(events[name], function(event)
            local probe = storage.event_reload_probe
            if not probe then return end
            local key = (event.force_name or 'player') .. ':' .. name
            probe.seen[key] = (probe.seen[key] or 0) + 1
        end)
    end
    Event.on_configuration_changed(function()
        storage.event_reload_probe.configuration_changed = true
    end)
    local function setup_fixture()
        local probe = {seen = {}, teams = {}, saved_events = table.deepcopy(events),
            start_tick = game.tick, shift = events.gui_update - ServerCommands.events.on_player_untrusted}
        storage.event_reload_probe = probe
        for _, name in ipairs(names) do
            local state = Expanse.test_state(name)
            local surface = game.surfaces[state.active_surface_index]
            local position = {x = 60, y = 60}
            surface.request_to_generate_chunks(position, 2)
            surface.force_generate_chunk_requests()
            for x = 30, 75, 15 do for y = 30, 75, 15 do Functions.expand(state, {x=x, y=y}) end end
            for _, entity in pairs(surface.find_entities_filtered{area = {{35,35},{85,85}}}) do entity.destroy() end
            local tiles = {}
            for x = 35, 85 do for y = 35, 85 do tiles[#tiles + 1] = {name = 'grass-1', position = {x,y}} end end
            surface.set_tiles(tiles)
            local victim = assert(surface.create_entity{name = 'steel-chest', position = position, force = name})
            local building = assert(surface.create_entity{name = 'steel-chest', position = {40,40}, force = name})
            building.insert{name = 'iron-plate', count = 37}
            game.forces[name].technologies.automation.researched = true
            local chest
            for _, container in pairs(state.containers) do chest = container; break end
            assert(chest and chest.entity.valid)
            Functions.set_container(state, chest.entity, chest.left_top, true)
            chest = state.containers[chest.entity.unit_number]
            chest.price = {{name = 'iron-plate', count = 2, quality = 'normal'}}
            -- A partial payment exercises the same GUI event that fails in the server log.
            chest.entity.insert{name = 'iron-plate', count = 1}
            state.schedule = {
                {tick = game.tick + 60, event = 'invasion_warn', parameters = {force_name = name, size = 1, total_delay_ticks = 120}},
                {tick = game.tick + 120, event = 'invasion_detonate', parameters = {surface = surface, position = position, kill_radius = 2, damage_radius = 3}},
                {tick = game.tick + 180, event = 'invasion_trigger', parameters = {surface = surface, position = position,
                    round = 1, biter_base = 3, biter_evolution_scale = 0, biter_round_scale = 0,
                    worm_base = 1, worm_evolution_scale = 0, attack_radius = 10}},
                {tick = game.tick + 3600, event = 'invasion_warn', parameters = {force_name = name, size = 1}}
            }
            probe.teams[name] = {surface = surface, victim = victim, building = building,
                chest = chest.entity, left_top = chest.left_top, size = state.size}
        end
        probe.seen = {}
        helpers.write_file('event-fixture.json', helpers.table_to_json({shift = probe.shift, saved_events = probe.saved_events}))
    end
    Event.on_init(function()
        for _, name in ipairs(names) do Expanse.reset(name) end
        game.speed = 100
    end)
    Event.on_nth_tick(30, function()
        if bootstrap then
            -- MTS's initial vanilla mirror is asynchronous. Save an established world,
            -- after its initial clone jobs finish, rather than racing them with the fixture.
            if game.tick == 600 then
                setup_fixture()
                game.server_save('event-before')
            end
            return
        end
        local probe = storage.event_reload_probe
        if game.tick == probe.start_tick + 30 then
            for name, fixture in pairs(probe.teams) do
                local state = Expanse.test_state(name)
                Functions.set_container(state, fixture.chest, fixture.left_top, false)
            end
        end
        if game.tick ~= probe.start_tick + 240 then return end
        local checks = {ids_changed = events.gui_update ~= probe.saved_events.gui_update}
        local teams = {}
        for name, fixture in pairs(probe.teams) do
            local state = Expanse.test_state(name)
            local surface = fixture.surface
            local units = surface.count_entities_filtered{force = 'enemy', type = 'unit', area = {{35,35},{85,85}}}
            local nests = surface.count_entities_filtered{force = 'enemy', type = 'unit-spawner', area = {{35,35},{85,85}}}
            local worms = surface.count_entities_filtered{force = 'enemy', type = 'turret', area = {{35,35},{85,85}}}
            local seen = probe.seen
            checks[name .. ':gui_routed'] = (seen[name .. ':gui_update'] or 0) > 0
            checks[name .. ':warning_routed'] = seen[name .. ':invasion_warn'] == 1
            checks[name .. ':detonation_routed'] = seen[name .. ':invasion_detonate'] == 1
            checks[name .. ':wave_routed'] = seen[name .. ':invasion_trigger'] == 1
            checks[name .. ':detonation_executed'] = not fixture.victim.valid
            -- A new nest can also spawn a native unit before this observation.
            checks[name .. ':enemies_spawned'] = units >= 3 and nests == 1 and worms == 1
            checks[name .. ':payment_processed'] = state.cost_stats[Functions.make_key('iron-plate', 'normal')] == 1
            checks[name .. ':future_timer_preserved'] = table_size(state.schedule) == 1
            checks[name .. ':world_preserved'] = state.active_surface_index == surface.index
                and state.size == fixture.size and fixture.building.valid
                and fixture.building.get_item_count('iron-plate') == 37
                and game.forces[name].technologies.automation.researched
            teams[name] = {units = units, nests = nests, worms = worms, tracker = state.invasion_tracker,
                building_valid = fixture.building.valid, same_size = state.size == fixture.size,
                researched = game.forces[name].technologies.automation.researched,
                same_surface = state.active_surface_index == surface.index}
        end
        helpers.write_file('event-result.json', helpers.table_to_json({checks = checks, teams = teams,
            seen = probe.seen, registered_events = events, saved_events = probe.saved_events,
            configuration_changed = probe.configuration_changed == true}))
    end)
end
return Public
