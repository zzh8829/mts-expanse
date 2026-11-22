-- Installed in disposable mod copies by test-richness.py.
local Event = require 'utils.event'
local Functions = require 'maps.expanse.functions'
local Missions = require 'maps.expanse.space_missions'

local function multiplier(name)
    local control = game.default_map_gen_settings.autoplace_controls[name]
    return control and control.richness or 1
end

local function expect(actual, expected, label)
    assert(actual == expected, label .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
end

local function at(surface, name, pos)
    return surface.find_entities_filtered{name = name, position = pos, limit = 1}[1]
end

local function seed_source(surface, name, pos, amount)
    surface.request_to_generate_chunks(pos, 1)
    surface.force_generate_chunk_requests()
    for _, old in pairs(surface.find_entities_filtered{type = 'resource', position = pos}) do
        old.destroy()
    end
    surface.set_tiles{{name = 'grass-1', position = pos}}
    return assert(surface.create_entity{name = name, position = pos, amount = amount or 1200})
end

local function check_new_cell(state, cell, deposits)
    local source = game.surfaces[state.source_surface]
    local surface = game.surfaces[state.active_surface_index]
    for i, spec in ipairs(deposits) do
        spec.position = {x = cell.x + 2.5 + i * 2, y = cell.y + 5.5}
        spec.template = seed_source(source, spec.source, spec.position, spec.amount)
        if spec.initial_amount then
            spec.template.initial_amount = spec.initial_amount
        end
    end

    Functions.expand(state, cell)
    for _, spec in ipairs(deposits) do
        local target = spec.target or spec.source
        local control = spec.control or target
        local cloned = at(surface, target, spec.position)
        local factor = multiplier(control)
        if not state.override_nauvis then
            factor = spec.source == control and 1 or factor / multiplier(spec.source)
        end
        local original = spec.amount or 1200
        if factor == 0 then
            assert(not cloned, 'spawned disabled deposit ' .. target)
        else
            local expected = math.min(4294967295, math.floor(original * factor))
            assert(cloned, 'missing cloned ' .. target)
            expect(cloned.amount, expected, 'revealed ' .. target)
            if spec.initial_amount then
                expect(cloned.initial_amount, spec.initial_amount * factor, 'initial fluid yield')
            end
        end
        expect(spec.template.amount, original, 'template ' .. spec.source)
    end
end

local function check_depletion(state, surface)
    -- Find a stone tile that the ordinary depletion handler replaces with uranium.
    for x = 120, 160 do
        local pos = {x = x + 0.5, y = 0.5}
        if Functions.cell_random_int(state, pos, 9500, 4) == 1 then
            local stone = seed_source(surface, 'stone', pos)
            local event = defines.events.on_resource_depleted
            script.get_event_handler(event){name = event, entity = stone, tick = game.tick}
            local bonus = Functions.cell_random_int(state, pos, 9501, 3)
            local amount = 200 + math.floor(math.sqrt(pos.x^2 + pos.y^2)) * bonus
            expect(assert(at(surface, 'uranium-ore', pos)).amount, amount * multiplier('uranium-ore'), 'depletion uranium')
            return
        end
    end
    error('no uranium-producing tile in fixture')
end

-- A native source can contain both native and scripted chunks after changing
-- the terrain setting during play. Oil is native in both kinds of chunk.
local function check_source_setting_change(expanse)
    local source, active, native_iron
    local native_cell = {x=0, y=60}
    local scripted_cell = {x=960, y=0}
    Event.on_nth_tick(1, function()
        if game.tick == 6 and not settings.global['mts-expanse-override-nauvis'].value then
            local state = expanse.test_richness_state('player')
            source = game.surfaces[state.source_surface]
            active = game.surfaces[state.active_surface_index]
            native_iron = seed_source(source, 'iron-ore', {x=4.5, y=64.5}, 1200)
            settings.global['mts-expanse-override-nauvis'] = {value=true}
        elseif game.tick == 8 and native_iron then
            local state = expanse.test_richness_state('player')
            assert(state.override_nauvis, 'the runtime terrain setting did not change')
            local new_iron = seed_source(source, 'iron-ore', {x=964.5, y=4.5}, 1200)
            local new_oil = seed_source(source, 'crude-oil', {x=970.5, y=7.5}, 120000)
            -- Keep the distant cell on Nauvis so the same resource is compared.
            state.tier_distance_thresholds = {2000, 2100, 2200, 2300, 2400, 2500}
            Functions.expand(state, scripted_cell)
            Functions.expand(state, native_cell)
            expect(at(active, 'iron-ore', native_iron.position).amount, 1200, 'old native chunk after setting change')
            expect(at(active, 'iron-ore', new_iron.position).amount, 1200 * multiplier('iron-ore'), 'new scripted iron')
            expect(at(active, 'crude-oil', new_oil.position).amount, 120000, 'native oil in mixed source')
            helpers.write_file('richness-toggle-ok', 'passed')
        end
    end)
end

return function(expanse, mts, old)
    local teams = mts and {'team-17', 'team-18'} or {'player'}
    if not mts and not old then check_source_setting_change(expanse) end
    Event.on_init(function()
        if old then
            local state = expanse.test_richness_state(teams[1])
            local surface = game.surfaces[state.active_surface_index]
            local ore = assert(surface.find_entities_filtered{name = 'iron-ore', area = {{0, 0}, {15, 15}}, limit = 1}[1])
            expect(ore.amount, 1500, '0.1.25 starter ore')
            ore.amount = 113
            storage.richness_old_ore = ore
        end
    end)

    if mts then
        -- MTS provisions team surfaces after the map has started, when a team joins.
        Event.on_nth_tick(1, function()
            if game.tick ~= 1 then return end
            for _, name in ipairs(teams) do expanse.reset(name) end
        end)
    end

    Event.on_nth_tick(5, function()
        if old or game.tick == 0 or storage.richness_done then return end
        storage.richness_done = true
        for _, team in ipairs(teams) do
            local state = expanse.test_richness_state(team)
            local surface = game.surfaces[state.active_surface_index]
            if storage.richness_old_ore then
                expect(storage.richness_old_ore.amount, 113, 'previously mined deposit after upgrade')
            else
                for _, name in ipairs({'iron-ore', 'copper-ore', 'stone', 'coal', 'crude-oil'}) do
                    local resource = assert(surface.find_entities_filtered{name = name, area = {{0, 0}, {15, 15}}, limit = 1}[1],
                        'missing starter ' .. name .. ' on ' .. surface.name)
                    local baseline = name == 'crude-oil' and 1500000 or 1500
                    expect(resource.amount, baseline * multiplier(name), 'starter ' .. name)
                end
            end
            check_new_cell(state, {x = 30, y = 0}, {
                {source = 'iron-ore'},
                {source = 'coal'},
                {source = 'crude-oil', amount = 120000, initial_amount = 240000},
            })
            if script.active_mods['space-age'] then
                -- Put each planet in a known quadrant before unlocking its tier of cells.
                state.biome_offset = 3
                check_new_cell(state, {x = 240, y = 0}, {
                    {source = 'iron-ore', target = 'tungsten-ore', control = 'tungsten_ore'},
                    {source = 'copper-ore', target = 'coal', control = 'vulcanus_coal'},
                    {source = 'stone', target = 'calcite'},
                })
                local boundary = seed_source(surface, 'coal', {x = 254.5, y = 6.5}, 87)
                check_new_cell(state, {x = 255, y = 0}, {
                    {source = 'iron-ore', target = 'tungsten-ore', control = 'tungsten_ore', amount = 4000000000},
                })
                assert(boundary.valid, 'adjacent cell replaced an already revealed resource')
                expect(boundary.amount, 87, 'partially mined cell boundary')
                check_new_cell(state, {x = 240, y = -15}, {{source = 'coal', target = 'scrap'}})
                check_new_cell(state, {x = -240, y = 0}, {{source = 'coal', target = 'stone', control = 'gleba_stone'}})
                check_new_cell(state, {x = -240, y = -15}, {
                    {source = 'crude-oil', control = 'aquilo_crude_oil', amount = 120000, initial_amount = 240000},
                })
            end

            local cell = {x = 30, y = 0}
            state.tiered_specials[3].tiles = 20 -- guarantee the uranium roll
            Missions.place_special_tiered_object(state, 3, surface, cell, 3)
            local patch = surface.find_entities_filtered{name = 'uranium-ore', area = {{30, 0}, {45, 15}}}
            local found = false
            for _, entity in pairs(patch) do
                if entity.amount == 2500 * multiplier('uranium-ore') then found = true end
            end
            assert(found, 'missing uranium special at configured richness')
            check_depletion(state, surface)
        end
        helpers.write_file('richness-result.json', helpers.table_to_json({teams = #teams, iron = multiplier('iron-ore')}))
    end)
end
