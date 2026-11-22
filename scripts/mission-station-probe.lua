-- Native engine regressions for the mission cargo station, loaded only into
-- disposable test profiles by scripts/test-mission-station.py.
local Event = require 'utils.event'
local SpaceMissions = require 'maps.expanse.space_missions'
local Model = require 'maps.expanse.missions.model'
local Cargo = require 'maps.expanse.missions.cargo'
local Data = require 'maps.expanse.mission_data'
local Functions = require 'maps.expanse.functions'
local Public = {}

local TIER, LEVEL = 4, 2
local ITEM = 'fast-inserter'
local KEY = ITEM .. '|normal'
local SURPLUS = 5

local function section_counts(section)
    local counts = {}
    for _, filter in pairs(section and section.filters or {}) do
        if filter.value then counts[filter.value.name] = filter.min end
    end
    return counts
end

local function check_station_sections(check, state, data)
    local chest = data.cargo_chest
    local point = chest.get_requester_point()
    local position = chest.surface.find_non_colliding_position('requester-chest', chest.position, 7, 1, true)
    local peer = chest.surface.create_entity{name = 'requester-chest', position = position, force = chest.force}
    local group = peer.get_requester_point().get_section(1)
    group.group = 'Station test group'
    group.set_slot(1, {value = {name = 'copper-plate', quality = 'normal', comparator = '='}, min = 27})
    point.get_section(1).group = group.group
    Cargo.tick(state, data)
    check('other_chests_keep_their_shared_requests', section_counts(group)['copper-plate'] == 27)
    check('station_writes_a_separate_request', section_counts(point.get_section(2))['space-platform-starter-pack'] == 1)

    local red = defines.wire_connector_id.circuit_red
    chest.get_wire_connector(red, true).connect_to(peer.get_wire_connector(red, true), false)
    chest.get_or_create_control_behavior().set_requests = true
    for i = point.sections_count, 1, -1 do
        if point.get_section(i).is_manual then point.remove_section(i) end
    end
    local circuit = point.get_section(1)
    assert(circuit and circuit.type == defines.logistic_section_type.circuit_controlled)
    Cargo.tick(state, data)
    check('circuit_section_survives_station_update', circuit.valid and not circuit.is_manual)
    check('station_restores_deleted_request_section', section_counts(point.get_section(2))['space-platform-starter-pack'] == 1)
end

local function check_hungry_chest_sections(check, state)
    local unit, hidden = next(state.containers)
    local entity = hidden.entity
    local point = entity.get_requester_point()
    check('hidden_chest_starts_without_requests', not hidden.revealed and point.sections_count == 0)
    local position = entity.surface.find_non_colliding_position('constant-combinator', entity.position, 8, 1, true)
    local peer = entity.surface.create_entity{name = 'constant-combinator', position = position, force = entity.force}
    local red = defines.wire_connector_id.circuit_red
    entity.get_wire_connector(red, true).connect_to(peer.get_wire_connector(red, true), false)
    entity.get_or_create_control_behavior().set_requests = true
    local circuit = point.get_section(1)
    assert(circuit and not circuit.is_manual)
    local user = point.add_section('Frontier supply')
    user.set_slot(1, {value = {name = 'copper-plate', quality = 'normal', comparator = '='}, min = 27})
    Functions.set_container(state, entity, hidden.left_top, false)
    Functions.set_container(state, entity, hidden.left_top, true)
    local revealed = state.containers[unit]
    local price = revealed.price[1]
    local offer = revealed.request_section.get_slot(1)
    check('reveal_uses_a_private_section', offer.value.name == price.name and offer.value.quality == price.quality and offer.min == price.count)
    check('reveal_preserves_circuit_and_user_requests', circuit.valid and user.valid and section_counts(user)['copper-plate'] == 27)
    local section = revealed.request_section
    point.remove_section(section.index)
    Functions.set_container(state, entity, hidden.left_top, false)
    check('unchanged_offer_restores_deleted_section', revealed.request_section.get_slot(1).min == price.count)
    local restored = revealed.request_section
    entity.insert{name = 'coin', count = 1}
    Functions.set_container(state, entity, hidden.left_top, true)
    check('reroll_reuses_the_private_section', state.containers[unit].request_section == restored and user.valid and circuit.valid)

    -- Saves from 0.1.25 tracked the offer by signature, without a section handle.
    local other_unit, other = next(state.containers, unit)
    Functions.set_container(state, other.entity, other.left_top, true)
    other = state.containers[other_unit]
    local old = other.request_section
    other.request_section = nil
    Functions.set_container(state, other.entity, other.left_top, false)
    check('legacy_offer_reuses_its_original_section', other.request_section == old)
    old.set_slot(1, {value = {name = 'space-platform-starter-pack', quality = 'normal', comparator = '='}, min = 987})
    other.request_section = nil
    Functions.set_container(state, other.entity, other.left_top, false)
    check('legacy_player_filters_survive_upgrade', other.request_section ~= old and old.get_slot(1).min == 987)
end

local function build_silo(state, surface, force)
    surface.request_to_generate_chunks({50, 50}, 2)
    surface.force_generate_chunk_requests()
    local tiles = {}
    for x = 30, 70 do for y = 30, 70 do tiles[#tiles + 1] = {name = 'grass-1', position = {x, y}} end end
    surface.set_tiles(tiles)
    for _, entity in pairs(surface.find_entities_filtered{area = {{30, 30}, {70, 70}}}) do
        if entity.type ~= 'character' then entity.destroy() end
    end
    local silo = assert(surface.create_entity{name = 'rocket-silo', position = {50, 50}, force = force})
    silo.minable_flag = false
    silo.destructible = false
    assert(surface.create_entity{name = 'substation', position = {60, 45}, force = force})
    local source = assert(surface.create_entity{name = 'electric-energy-interface', position = {63, 45}, force = force})
    source.power_production, source.electric_buffer_size, source.energy = 10e9, 10e9, 10e9
    state.rocket_silos[silo.unit_number] = {entity = silo, tier = TIER}
    -- Everything of the step is credited except ten fast inserters: one part load.
    local delivered = {}
    for key, count in pairs(Data.costs[TIER][LEVEL]) do delivered[key] = count end
    delivered[KEY] = delivered[KEY] - 10
    state.missions[TIER] = {level = LEVEL, delivered = delivered}
    return silo
end

function Public.install(Expanse, mts)
    local target = mts and 'team-1' or 'player'
    Event.on_init(function()
        if mts then Expanse.reset(target) end
        storage.station_test = {checks = {}, phase = 'build'}
    end)
    Event.add(defines.events.on_rocket_launch_ordered, function(event)
        local audit = storage.station_test
        if not audit or event.rocket_silo ~= audit.silo then return end
        local cargo = event.rocket.attached_cargo_pod.get_inventory(defines.inventory.cargo_unit)
        local stack = cargo.find_item_stack(ITEM)
        audit.payload_health = stack and stack.health
    end)
    Event.on_nth_tick(30, function()
        local audit = storage.station_test
        if audit.done or game.tick < 600 then return end
        local state = Expanse.test_state(target)
        local surface = game.surfaces[state.active_surface_index]
        local force = game.forces[target]
        local function check(name, condition) assert(condition, name); audit.checks[name] = true end

        if audit.phase == 'build' then
            -- Exercise every cargo definition through the same model that builds
            -- the mission board. A missing item or quality also breaks loading.
            local quality_enabled = script.active_mods['quality'] ~= nil
            for tier, steps in pairs(Data.costs) do
                for level = 1, #steps - 1 do
                    local view = Model.build({missions = {[tier] = {level = level, delivered = {}}}}, tier)
                    for _, item in ipairs(view.items) do assert(prototypes.quality[item.quality], item.quality) end
                end
            end
            local module = quality_enabled and 'quality-module-2|normal' or 'efficiency-module-2|normal'
            check('hephaestus_requests_available_modules', Data.costs[6][7][module] == 50)
            audit.silo = build_silo(state, surface, force)
            audit.phase = 'station'
            return
        end
        local data = state.rocket_silos[audit.silo.unit_number]
        local silo = data.entity
        if silo.rocket_silo_status == defines.rocket_silo_status.building_rocket and silo.rocket_parts < 50 then
            silo.rocket_parts = 50
        end
        local chest, combinator = data.cargo_chest, data.cargo_combinator
        if not (chest and chest.valid and combinator and combinator.valid) then return end

        if audit.phase == 'station' then
            check('station_is_protected', not chest.destructible and not chest.minable_flag and not combinator.destructible)
            check('station_survives_base_reset', Expanse.forfeit_impl.is_preserved_force_entity(state, chest)
                and Expanse.forfeit_impl.is_preserved_force_entity(state, combinator))
            chest.insert{name = ITEM, count = 4, health = 0.5}
            audit.phase = 'signals'
            -- The station is refreshed once a second; give it two refreshes.
            audit.resume_tick = game.tick + 120
        elseif audit.phase == 'signals' then
            if game.tick < audit.resume_tick then return end
            local requests = section_counts(chest.get_requester_point().get_section(1))
            local signals = section_counts(combinator.get_control_behavior().get_section(1))
            -- Requests are the chest's target content; the signal is what is still missing from it.
            check('chest_requests_only_the_outstanding_item', requests[ITEM] == 10 and table_size(requests) == 1)
            check('combinator_shows_what_is_missing_from_the_chest', signals[ITEM] == 6 and table_size(signals) == 1)
            chest.insert{name = ITEM, count = 6 + SURPLUS, health = 0.5}
            audit.phase = 'launch'
        elseif audit.phase == 'launch' then
            if state.missions[TIER].level == LEVEL then
                local outstanding = Model.outstanding(state, TIER)[KEY] or 0
                assert(outstanding + (Model.in_transit(state, TIER)[KEY] or 0) + (state.missions[TIER].delivered[KEY] or 0)
                    == Data.costs[TIER][LEVEL][KEY], 'cargo counted twice or lost while in flight')
                return
            end
            check('part_load_launches_and_completes_the_step', state.missions[TIER].level == LEVEL + 1)
            check('surplus_stays_in_the_chest', chest.get_item_count(ITEM) == SURPLUS)
            check('cargo_keeps_item_health', audit.payload_health and math.abs(audit.payload_health - 0.5) < 0.01)
            audit.phase = 'next_step'
        elseif audit.phase == 'next_step' then
            local requests = section_counts(chest.get_requester_point().get_section(1))
            local next_costs = Data.costs[TIER][LEVEL + 1]
            local valid = table_size(requests) > 0
            for name, count in pairs(requests) do valid = valid and count <= (next_costs[name .. '|normal'] or 0) end
            check('requests_follow_the_next_step', valid and requests[ITEM] == nil)

            -- A reset keeps research, so a mission with its technology done must reopen.
            force.technologies[Data.mission_unlocks[TIER]].researched = true
            state.missions[TIER] = {level = 0, delivered = {}}
            SpaceMissions.sync_unlocks(state)
            check('researched_mission_reopens', state.missions[TIER].level == 1)

            local admin = {valid = true, force = force, surface = surface}
            check('reset_typo_never_targets_own_world', Expanse.test_reset_target(admin, 'team 1') == nil
                and Expanse.test_reset_target(admin, 'team-1 extra') == nil)
            check('command_refuses_unknown_team', Expanse.test_reset_target(admin, 'team-99') == nil)
            check('reset_accepts_current_and_explicit_target', Expanse.test_reset_target(admin, nil) == state
                and Expanse.test_reset_target(nil, '  ' .. target .. '  ') == state)
            if mts then
                local observer = {valid = true, force = game.forces.player, surface = surface}
                check('viewing_team_surface_does_not_target_it_for_reset', Expanse.test_reset_target(observer, nil) == nil)
            end
            check('command_refuses_default_state_under_mts', (Expanse.forfeit_impl.command_state(nil) == nil) == mts)
            check('remote_reset_refuses_default_state_under_mts', (not mts) or Expanse.reset() == false)

            surface.create_decoratives{check_collision = false, decoratives = {{name = 'enemy-decal', position = {35, 35}, amount = 1}}}
            SpaceMissions.convert_decoratives(surface, {x = 30, y = 30}, 9, 15)
            local area = {{28, 28}, {47, 47}}
            check('aquilo_decals_replace_enemy_decals', #surface.find_decoratives_filtered{area = area, name = 'aqulio-ice-decal-blue'} == 1
                and #surface.find_decoratives_filtered{area = area, name = 'enemy-decal'} == 0)

            local old = {missions = {[8] = {level = 7}}, space_production = {}}
            SpaceMissions.migrate_gaia_rewards(old)
            SpaceMissions.migrate_gaia_rewards(old)
            check('gaia_fruit_migrates_once', old.space_production['yumako|normal'] == 4 and old.space_production['jellynut|normal'] == 4)
            check('gaia_no_longer_changes_spoil_time', Data.rewards[8][4].script == nil and Data.rewards[8][4].production['yumako|normal'] == 4)

            check_station_sections(check, state, data)
            check_hungry_chest_sections(check, state)
            helpers.write_file('station-result.json', helpers.table_to_json(audit.checks))
            audit.done = true
        end
    end)
end

return Public
