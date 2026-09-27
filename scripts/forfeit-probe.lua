-- Loaded only into disposable copies by test-forfeit.py. Characters provide real
-- engine crafting queues without connecting graphical players to the test server.
local Event = require 'utils.event'
local Functions = require 'maps.expanse.functions'
local Public = {}
local mts = script.active_mods['multi-team-support'] ~= nil
local target = mts and 'team-1' or 'player'

local function offer(container)
    local items = {}
    for _, item in ipairs(container.price or {}) do
        items[#items + 1] = {name = item.name, quality = item.quality, count = item.count}
    end
    return helpers.table_to_json(items)
end

local function inventory_empty(character)
    return character.get_inventory(defines.inventory.character_main).is_empty()
end

local function seed_enemies(surface)
    -- Keep the fixture away from the factory. No test action is installed in a release.
    surface.request_to_generate_chunks({320, 320}, 4)
    surface.force_generate_chunk_requests()
    local tiles = {}
    for x = 256, 383 do
        for y = 256, 383 do tiles[#tiles + 1] = {name = 'grass-1', position = {x, y}} end
    end
    surface.set_tiles(tiles)
    local names = {'biter-spawner', 'spitter-spawner'}
    for _, size in ipairs({'small', 'medium', 'big', 'behemoth'}) do
        for _, kind in ipairs({'biter', 'spitter', 'worm-turret'}) do
            names[#names + 1] = size .. '-' .. kind
        end
    end
    if script.active_mods['space-age'] then
        for _, size in ipairs({'small', 'medium', 'big'}) do
            for _, kind in ipairs({'stomper-pentapod', 'strafer-pentapod', 'wriggler-pentapod', 'wriggler-pentapod-premature', 'demolisher'}) do
                names[#names + 1] = size .. '-' .. kind
            end
        end
        names[#names + 1] = 'gleba-spawner'
        names[#names + 1] = 'gleba-spawner-small'
    end
    local enemies, types = {}, {}
    for i, name in ipairs(names) do
        local entity = assert(surface.create_entity{name=name, position={272 + (i % 8) * 12, 272 + math.floor(i / 8) * 20}, force='enemy'}, name)
        enemies[name] = entity
        types[entity.type] = (types[entity.type] or 0) + 1
    end
    enemies.grenade = assert(surface.create_entity{name='grenade',position={300,300},target={370,370},speed=0.01,force='enemy'})
    if script.active_mods['space-age'] then
        assert(types['spider-unit'] == 6, 'fixture must include all stompers and strafers')
        assert(types['segmented-unit'] == 3, 'fixture must include all demolishers')
        assert(surface.count_entities_filtered{type='spider-leg'} > 0, 'missing real pentapod legs')
        assert(surface.count_entities_filtered{type='segment'} > 0, 'missing real demolisher segments')
    end
    return enemies, types
end

function Public.install(Expanse)
    -- Route these disconnected test characters through the production team-wide
    -- inventory cleanup. No production methods are replaced inside the release.
    local clear_force_players = Expanse.forfeit_impl.clear_force_player_inventories
    Expanse.forfeit_impl.clear_force_player_inventories = function(force)
        local count = clear_force_players(force)
        for _, character in ipairs(storage.forfeit_test.characters or {}) do
            if character.valid and character.force == force then
                count = count + Expanse.forfeit_impl.clear_player_inventory(character)
            end
        end
        return count
    end
    Event.on_init(function()
        if mts then Expanse.reset('team-1'); Expanse.reset('team-2') end
        storage.forfeit_test = {characters = {}}
    end)
    Event.on_nth_tick(30, function()
        local audit = storage.forfeit_test
        -- MTS builds its vanilla team mirror asynchronously during early ticks.
        -- Wait until that setup finishes before placing the test factory/characters.
        if audit.done or game.tick < 600 then return end
        local state = Expanse.test_state(target)
        local surface = game.surfaces[state.active_surface_index]
        if not audit.started then
            audit.started = true
            audit.started_tick = game.tick
            -- Build a settled frontier after MTS's initial mirror, which can replace
            -- the spawn chests created during on_init before any players connect.
            Functions.expand(state, {x=30, y=30})
            Functions.ensure_frontier_chests(state)
            audit.surface = surface.index
            audit.size = state.size
            game.forces[target].technologies['automation'].researched = true
            local _, container = next(state.containers)
            assert(container and container.entity.valid, 'missing hungry chest')
            Functions.set_container(state, container.entity, container.left_top, true)
            container = state.containers[container.entity.unit_number]
            assert(container.revealed and #container.price > 0, 'missing revealed offer')
            audit.chest = container.entity
            audit.offer = offer(container)
            for _, id in ipairs({defines.inventory.chest, defines.inventory.logistic_container_trash}) do
                local inv = assert(audit.chest.get_inventory(id))
                assert(inv.insert{name='iron-plate',count=37} == 37)
                if script.active_mods.quality then
                    assert(inv.insert{name='copper-plate',quality='legendary',count=11} == 11)
                end
            end
            local other_surface = mts and game.surfaces[Expanse.test_state('team-2').active_surface_index] or game.create_surface('unrelated-forfeit-test', {width=32,height=32})
            other_surface.request_to_generate_chunks({0,0},1);other_surface.force_generate_chunk_requests()
            local pos = assert(other_surface.find_non_colliding_position('requester-chest',{7,7},100,1))
            audit.other = assert(other_surface.create_entity{name='requester-chest',position=pos,force='neutral'})
            audit.other.insert{name='iron-plate',count=23}
            -- A neutral ordinary chest is not an Expanse hungry chest.
            local neutral_pos = assert(surface.find_non_colliding_position('steel-chest',{5,5},100,1))
            audit.neutral = assert(surface.create_entity{name='steel-chest',position=neutral_pos,force='neutral'})
            audit.neutral.insert{name='copper-plate',count=17}
            for _, name in ipairs({'iron-gear-wheel', 'copper-cable', 'stone-furnace', 'electronic-circuit', 'inserter'}) do
                game.forces[target].recipes[name].enabled = true
            end
            for i = 1, 3 do
                local char_pos = assert(surface.find_non_colliding_position('character',{7,7},100,1))
                local character = assert(surface.create_entity{name='character',position=char_pos,force=target})
                character.insert{name='iron-plate',count=500}
                character.insert{name='copper-plate',count=400}
                character.insert{name='stone',count=200}
                if i == 1 then
                    assert(character.begin_crafting{recipe='iron-gear-wheel',count=50} == 50)
                elseif i == 2 then
                    assert(character.begin_crafting{recipe='iron-gear-wheel',count=50} == 50)
                    assert(character.begin_crafting{recipe='copper-cable',count=60} == 60)
                    assert(character.begin_crafting{recipe='stone-furnace',count=30} == 30)
                else
                    assert(character.begin_crafting{recipe='inserter',count=20} == 20)
                    assert(character.crafting_queue_size > 1, 'missing prerequisite crafts')
                end
                -- Force cancellation refunds to overflow, exercising ground cleanup.
                character.insert{name='stone',count=100000}
                audit.characters[#audit.characters+1] = character
            end
            audit.enemies, audit.enemy_types = seed_enemies(surface)
            local bystander_force = mts and game.forces['team-2'] or game.create_force('forfeit-bystander')
            local bystander_name = script.active_mods['space-age'] and 'small-stomper-pentapod' or 'small-biter'
            audit.bystander = assert(surface.create_entity{name=bystander_name,position={320,320},force=bystander_force})
            audit.other_enemy = assert(other_surface.create_entity{name=bystander_name,position=pos,force='enemy'})
            local counts = assert(Expanse.forfeit_impl.run(state))
            audit.results = {
                no_enemy_entities = surface.count_entities_filtered{force='enemy'} == 0,
                no_enemy_body_parts = surface.count_entities_filtered{force='enemy', type={'spider-leg', 'segment'}} == 0,
                other_surface_enemy_preserved = audit.other_enemy.valid,
                other_force_preserved = audit.bystander.valid,
                chest_preserved = audit.chest.valid,
                chest_empty = audit.chest.get_inventory(defines.inventory.chest).is_empty(),
                trash_empty = audit.chest.get_inventory(defines.inventory.logistic_container_trash).is_empty(),
                offer_preserved = offer(state.containers[audit.chest.unit_number]) == audit.offer,
                other_surface_untouched = audit.other.get_inventory(defines.inventory.chest).get_item_count('iron-plate') == 23,
                neutral_storage_untouched = audit.neutral.get_inventory(defines.inventory.chest).get_item_count('copper-plate') == 17,
                queues_empty = true,
                refunds_removed = true,
                no_spilled_refunds = surface.count_entities_filtered{type='item-entity'} == 0,
                surface_and_progress_preserved = surface.index == audit.surface and state.size == audit.size and game.forces[target].technologies.automation.researched
            }
            for name, entity in pairs(audit.enemies) do
                audit.results['removed_' .. name] = not entity.valid
            end
            helpers.write_file('forfeit-enemies.json',helpers.table_to_json({types=audit.enemy_types, results=audit.results}))
            for _, character in ipairs(audit.characters) do
                audit.results.queues_empty = audit.results.queues_empty and character.crafting_queue_size == 0
                audit.results.refunds_removed = audit.results.refunds_removed and inventory_empty(character)
            end
            -- Repeating forfeit must remain safe and leave offers usable.
            assert(Expanse.forfeit_impl.run(state))
            audit.results.repeat_reset_clear = surface.count_entities_filtered{force='enemy'} == 0
        elseif game.tick >= audit.started_tick + 600 then
            audit.results.no_delayed_enemies = surface.count_entities_filtered{force='enemy'} == 0
            audit.results.no_delayed_crafts = true
            for _, character in ipairs(audit.characters) do
                audit.results.no_delayed_crafts = audit.results.no_delayed_crafts and character.crafting_queue_size == 0 and inventory_empty(character)
            end
            helpers.write_file('forfeit-result.json',helpers.table_to_json(audit.results))
            audit.done = true
        end
    end)
end
return Public
