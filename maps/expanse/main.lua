-- a map where you feed hungry boxes, which unlocks new territory, with even more hungry boxes by mewmew

--CONFIGS
local default_cell_size = 15                 -- size of each territory to unlock
local default_chance_to_receive_token = 0.20 -- chance of a hungry chest, dropping a token after unlocking, can be above 1 for multiple
local default_tier_distance_thresholds = { 30, 60, 90, 150, 210, 300 }

local Mode = require 'maps.expanse.mode'
local SA = Mode.is_space_age()
require 'modules.backpack_research'

local Event = require 'utils.event'
local Functions = require 'maps.expanse.functions'
local SpaceMissions = require 'maps.expanse.space_missions'
local MissionData = require 'maps.expanse.mission_data'
local GetNoise = require 'utils.math.get_noise'
local Global = require 'utils.global'
local Map_info = require 'modules.map_info'
local Gui = require 'utils.gui'
local format_number = require 'util'.format_number
local Autostash = require 'modules.autostash'
local FT = require 'utils.functions.flying_texts'
local Raffle = require 'utils.math.raffle'

local expanse = {
    events = {
        gui_update = Event.generate_event_name('expanse_gui_update'),
        mission_gui_update = Event.generate_event_name('expanse_missions_gui_update'),
        invasion_warn = Event.generate_event_name('invasion_warn'),
        invasion_detonate = Event.generate_event_name('invasion_detonate'),
        invasion_trigger = Event.generate_event_name('invasion_trigger'),
        victory = Event.generate_event_name('victory'),
        map_reset = Event.generate_event_name('expanse_map_reset')
    }
}
local Public = {}

Global.register(
    expanse,
    function (tbl)
        expanse = tbl
    end
)

local main_button_name = Gui.uid_name()
local missions_button_name = Gui.uid_name()
local main_frame_name = Gui.uid_name()
local close_main_frame_button_name = Gui.uid_name()
local missions_frame_name = Gui.uid_name()
local close_missions_button_name = Gui.uid_name()

local MTS_INTERFACE = 'mts-v1'
local DEFAULT_FORCE_NAME = 'player'
local DEFAULT_SURFACE_NAME = 'expanse'
local DEFAULT_SOURCE_SURFACE = 'nauvis'
local SHARED_SOURCE_SURFACE = 'mts-expanse-meta-source'
local reset
local destroy_natural_enemy_entities

local function startup_setting(name, default)
    local setting = settings.startup[name]
    if setting == nil or setting.value == nil then
        return default
    end
    return setting.value
end

local function global_setting(name, default)
    local setting = settings.global[name]
    if setting == nil or setting.value == nil then
        return default
    end
    return setting.value
end

local function parse_number_list(value, default)
    if type(value) ~= 'string' then
        return table.deepcopy(default)
    end
    local numbers = {}
    for part in value:gmatch('[^,]+') do
        local number = tonumber(part:match('^%s*(.-)%s*$'))
        if number and number > 0 then
            numbers[#numbers + 1] = number
        end
    end
    if #numbers < #default then
        return table.deepcopy(default)
    end
    return numbers
end

local function expanse_config()
    return {
        cell_size = startup_setting('mts-expanse-cell-size', default_cell_size),
        token_chance = global_setting('mts-expanse-token-chance', default_chance_to_receive_token),
        price_distance_modifier = global_setting('mts-expanse-price-distance-modifier', 0.006),
        max_ore_price_modifier = global_setting('mts-expanse-max-ore-price-modifier', 0.33),
        override_nauvis = global_setting('mts-expanse-override-nauvis', true),
        cleanup_mts_nauvis = global_setting('mts-expanse-cleanup-mts-nauvis', true),
        admin_open_max_radius = global_setting('mts-expanse-admin-open-max-radius', 8),
        admin_frontier_max_rings = global_setting('mts-expanse-admin-frontier-max-rings', 4),
        admin_frontier_max_cells = global_setting('mts-expanse-admin-frontier-max-cells', 256),
        cell_value_multiplier = global_setting('mts-expanse-cell-value-multiplier', 8),
        min_cell_value = global_setting('mts-expanse-min-cell-value', 16),
        fluid_price_multiplier = global_setting('mts-expanse-fluid-price-multiplier', 0.01),
        ore_modifier_divisor = global_setting('mts-expanse-ore-modifier-divisor', 20),
        tier_distance_thresholds = parse_number_list(global_setting('mts-expanse-tier-distance-thresholds', '30,60,90,150,210,300'), default_tier_distance_thresholds),
        price_roll_count = global_setting('mts-expanse-price-roll-count', 3),
        tier10_special_chance = global_setting('mts-expanse-tier10-special-chance', 20),
        sync_cell_content = global_setting('mts-expanse-sync-cell-content', true),
        map_starting_area = global_setting('mts-expanse-map-starting-area', 0.08),
        spoil_time_modifier = global_setting('mts-expanse-spoil-time-modifier', 1),
        enemy_expansion_cooldown_ticks = global_setting('mts-expanse-enemy-expansion-cooldown-ticks', 1800),
        enemy_settler_group_max_size = global_setting('mts-expanse-enemy-settler-group-max-size', 8),
        enemy_settler_group_min_size = global_setting('mts-expanse-enemy-settler-group-min-size', 16),
        enemy_evolution_destroy_factor = global_setting('mts-expanse-enemy-evolution-destroy-factor', 0.003),
        enemy_evolution_pollution_factor = global_setting('mts-expanse-enemy-evolution-pollution-factor', 0.0000006),
        enemy_evolution_time_factor = global_setting('mts-expanse-enemy-evolution-time-factor', 0.000002),
        map_reset_delay_ticks = global_setting('mts-expanse-map-reset-delay-ticks', 7200),
        space_production_interval_ticks = global_setting('mts-expanse-space-production-interval-ticks', 3600),
        invasion_enabled = global_setting('mts-expanse-invasion-enabled', true),
        sync_invasions = global_setting('mts-expanse-sync-invasions', true),
        spawner_spawn_base = global_setting('mts-expanse-spawner-spawn-base', 4),
        spawner_spawn_evolution_scale = global_setting('mts-expanse-spawner-spawn-evolution-scale', 8),
        invasion_candidate_base = global_setting('mts-expanse-invasion-candidate-base', 3),
        invasion_candidate_evolution_scale = global_setting('mts-expanse-invasion-candidate-evolution-scale', 10),
        invasion_group_base = global_setting('mts-expanse-invasion-group-base', 1),
        invasion_group_evolution_scale = global_setting('mts-expanse-invasion-group-evolution-scale', 4),
        invasion_detonate_delay_ticks = global_setting('mts-expanse-invasion-detonate-delay-ticks', 7200),
        invasion_first_warning_delay_ticks = global_setting('mts-expanse-invasion-first-warning-delay-ticks', 120),
        invasion_extra_warning_1_ticks = global_setting('mts-expanse-invasion-extra-warning-1-ticks', 3600),
        invasion_extra_warning_2_ticks = global_setting('mts-expanse-invasion-extra-warning-2-ticks', 5400),
        invasion_nuke_kill_radius = global_setting('mts-expanse-invasion-nuke-kill-radius', 8),
        invasion_nuke_damage_radius = global_setting('mts-expanse-invasion-nuke-damage-radius', 16),
        invasion_nuke_damage_fraction = global_setting('mts-expanse-invasion-nuke-damage-fraction', 0.75),
        invasion_biter_base = global_setting('mts-expanse-invasion-biter-base', 5),
        invasion_biter_evolution_scale = global_setting('mts-expanse-invasion-biter-evolution-scale', 30),
        invasion_biter_round_scale = global_setting('mts-expanse-invasion-biter-round-scale', 5),
        invasion_worm_base = global_setting('mts-expanse-invasion-worm-base', 3),
        invasion_worm_evolution_scale = global_setting('mts-expanse-invasion-worm-evolution-scale', 7),
        invasion_rounds_base = global_setting('mts-expanse-invasion-rounds-base', 4),
        invasion_rounds_random_max = global_setting('mts-expanse-invasion-rounds-random-max', 8),
        invasion_wave_first_delay_ticks = global_setting('mts-expanse-invasion-wave-first-delay-ticks', 120),
        invasion_wave_interval_ticks = global_setting('mts-expanse-invasion-wave-interval-ticks', 300),
        invasion_attack_radius = global_setting('mts-expanse-invasion-attack-radius', 80),
        invasion_render_grace_ticks = global_setting('mts-expanse-invasion-render-grace-ticks', 120),
        use_space_platform = global_setting('mts-expanse-use-space-platform', false),
        nonspace_support_size = global_setting('mts-expanse-nonspace-support-size', 40),
        rocket_launch_weight_threshold = global_setting('mts-expanse-rocket-launch-weight-threshold', 999500)
    }
end

local function apply_world_settings()
    local config = expanse_config()
    game.difficulty_settings.spoil_time_modifier = config.spoil_time_modifier
    game.map_settings.enemy_expansion.enabled = false
    game.map_settings.enemy_expansion.max_expansion_cooldown = config.enemy_expansion_cooldown_ticks
    game.map_settings.enemy_expansion.min_expansion_cooldown = config.enemy_expansion_cooldown_ticks
    game.map_settings.enemy_expansion.settler_group_max_size = config.enemy_settler_group_max_size
    game.map_settings.enemy_expansion.settler_group_min_size = config.enemy_settler_group_min_size
    game.map_settings.enemy_evolution.destroy_factor = config.enemy_evolution_destroy_factor
    game.map_settings.enemy_evolution.pollution_factor = config.enemy_evolution_pollution_factor
    game.map_settings.enemy_evolution.time_factor = config.enemy_evolution_time_factor
end

local function is_mts_active()
    return remote.interfaces[MTS_INTERFACE] ~= nil
end

local function is_team_force_name(force_name)
    return type(force_name) == 'string' and force_name:match('^team%-%d+$') ~= nil
end

local function promote_mts_team_host_info(info)
    if not (is_mts_active() and type(info) == 'table' and info.is_occupied) then
        return false
    end
    if not is_team_force_name(info.force_name) then
        return false
    end
    local player_index = info.leader_player_index
    if type(player_index) ~= 'number' then
        return false
    end
    local player = game.get_player(player_index)
    if not (player and player.valid) then
        return false
    end
    local changed = false
    local team_force = game.forces[info.force_name]
    if team_force and team_force.valid and player.force.name ~= info.force_name then
        local force_ok, force_err = pcall(function()
            player.force = team_force
        end)
        if force_ok then
            changed = true
            log('[mts-expanse] restored MTS team host force: ' .. player.name .. ' (' .. info.force_name .. ')')
        else
            log('[mts-expanse] failed to restore MTS team host force for ' .. player.name .. ': ' .. tostring(force_err))
        end
    end
    if not player.admin then
        local ok, err = pcall(function()
            player.admin = true
        end)
        if not ok then
            log('[mts-expanse] failed to promote MTS team host ' .. player.name .. ' to admin: ' .. tostring(err))
            return changed
        end
        changed = true
        if player.connected then
            player.print('You are now an admin because you host an MTS team.')
        end
        log('[mts-expanse] promoted MTS team host to admin: ' .. player.name .. ' (' .. info.force_name .. ')')
    end
    return changed
end

local function promote_mts_team_host(force_name)
    if not (is_mts_active() and is_team_force_name(force_name)) then
        return false
    end
    local ok, info = pcall(remote.call, MTS_INTERFACE, 'get_team_info', force_name)
    if not ok then
        return false
    end
    return promote_mts_team_host_info(info)
end

local function promote_all_mts_team_hosts()
    if not is_mts_active() then
        return
    end
    local ok, teams = pcall(remote.call, MTS_INTERFACE, 'get_team_list')
    if not ok or type(teams) ~= 'table' then
        return
    end
    for _, info in pairs(teams) do
        promote_mts_team_host_info(info)
    end
end

local function find_character_position(surface, position)
    return surface.find_non_colliding_position('character', position, 32, 0.5)
        or surface.find_non_colliding_position('character', position, 64, 1)
        or position
end

local function place_player_on_expanse_surface(player, surface, position)
    if not (player and player.valid and surface and surface.valid) then
        return false
    end

    local target = find_character_position(surface, position)
    if player.character and player.character.valid then
        return player.teleport(target, surface)
    end

    if player.controller_type ~= defines.controllers.god then
        player.set_controller({ type = defines.controllers.god })
    end
    player.teleport(target, surface)

    if not player.create_character() then
        log('[mts-expanse] failed to create character for ' .. player.name .. ' on ' .. surface.name)
        return false
    end
    if player.character and player.character.valid then
        player.set_controller({ type = defines.controllers.character, character = player.character })
        return true
    end

    log('[mts-expanse] create_character returned without a valid character for ' .. player.name .. ' on ' .. surface.name)
    return false
end

local function ensure_indexes()
    expanse.team_states = expanse.team_states or {}
    expanse.surface_to_force = expanse.surface_to_force or {}
    expanse.object_to_force = expanse.object_to_force or {}
    expanse.pending_player_teleports = expanse.pending_player_teleports or {}
    expanse.shared_seed = expanse.shared_seed or math.random(1, 4000000000)
    expanse.shared_biome_offset = expanse.shared_biome_offset or math.random(1, 4)
    expanse.meta_map = expanse.meta_map or {}
    expanse.meta_map.source_surface = expanse.meta_map.source_surface or SHARED_SOURCE_SURFACE
    expanse.meta_map.cells = expanse.meta_map.cells or {}
    expanse.meta_map.shared_seed = expanse.shared_seed
    expanse.meta_map.biome_offset = expanse.shared_biome_offset
end

local function state_key(state)
    return state and state.force_name or DEFAULT_FORCE_NAME
end

local function state_force(state)
    return game.forces[state_key(state)] or game.forces.player
end

local function state_surface_name(force_name)
    if is_team_force_name(force_name) then
        return force_name .. '-expanse'
    end
    return DEFAULT_SURFACE_NAME
end

local function state_source_surface_name(force_name)
    if is_mts_active() then
        return SHARED_SOURCE_SURFACE
    end
    if is_team_force_name(force_name) then
        return force_name .. '-expanse-source'
    end
    return DEFAULT_SOURCE_SURFACE
end

local function state_support_surface_name(force_name)
    if is_team_force_name(force_name) then
        return force_name .. '-NonOrbit'
    end
    return 'NonOrbit'
end

local function init_state_defaults(state, force_name)
    local config = expanse_config()
    state.force_name = force_name or state.force_name or DEFAULT_FORCE_NAME
    state.events = expanse.events
    state.surface_name = state.surface_name or state_surface_name(state.force_name)
    local desired_source_surface = state_source_surface_name(state.force_name)
    if is_mts_active() then
        state.source_surface = desired_source_surface
    else
        state.source_surface = state.source_surface or desired_source_surface
    end
    state.nonspace_surface = state.nonspace_surface or state_support_surface_name(state.force_name)
    state.meta_map = expanse.meta_map
    state.token_chance = config.token_chance
    state.price_distance_modifier = config.price_distance_modifier
    state.max_ore_price_modifier = config.max_ore_price_modifier
    state.square_size = config.cell_size
    state.shared_seed = expanse.shared_seed
    state.override_nauvis = config.override_nauvis
    state.cleanup_mts_nauvis = config.cleanup_mts_nauvis
    state.cell_value_multiplier = config.cell_value_multiplier
    state.min_cell_value = config.min_cell_value
    state.fluid_price_multiplier = config.fluid_price_multiplier
    state.ore_modifier_divisor = config.ore_modifier_divisor
    state.tier_distance_thresholds = config.tier_distance_thresholds
    state.price_roll_count = config.price_roll_count
    state.tier10_special_chance = config.tier10_special_chance
    state.sync_cell_content = config.sync_cell_content
    state.map_starting_area = config.map_starting_area
    state.map_reset_delay_ticks = config.map_reset_delay_ticks
    state.space_production_interval_ticks = config.space_production_interval_ticks
    state.invasion_enabled = config.invasion_enabled
    state.sync_invasions = config.sync_invasions
    state.spawner_spawn_base = config.spawner_spawn_base
    state.spawner_spawn_evolution_scale = config.spawner_spawn_evolution_scale
    state.invasion_candidate_base = config.invasion_candidate_base
    state.invasion_candidate_evolution_scale = config.invasion_candidate_evolution_scale
    state.invasion_group_base = config.invasion_group_base
    state.invasion_group_evolution_scale = config.invasion_group_evolution_scale
    state.invasion_detonate_delay_ticks = config.invasion_detonate_delay_ticks
    state.invasion_first_warning_delay_ticks = config.invasion_first_warning_delay_ticks
    state.invasion_extra_warning_1_ticks = config.invasion_extra_warning_1_ticks
    state.invasion_extra_warning_2_ticks = config.invasion_extra_warning_2_ticks
    state.invasion_nuke_kill_radius = config.invasion_nuke_kill_radius
    state.invasion_nuke_damage_radius = config.invasion_nuke_damage_radius
    state.invasion_nuke_damage_fraction = config.invasion_nuke_damage_fraction
    state.invasion_biter_base = config.invasion_biter_base
    state.invasion_biter_evolution_scale = config.invasion_biter_evolution_scale
    state.invasion_biter_round_scale = config.invasion_biter_round_scale
    state.invasion_worm_base = config.invasion_worm_base
    state.invasion_worm_evolution_scale = config.invasion_worm_evolution_scale
    state.invasion_rounds_base = config.invasion_rounds_base
    state.invasion_rounds_random_max = config.invasion_rounds_random_max
    state.invasion_wave_first_delay_ticks = config.invasion_wave_first_delay_ticks
    state.invasion_wave_interval_ticks = config.invasion_wave_interval_ticks
    state.invasion_attack_radius = config.invasion_attack_radius
    state.invasion_render_grace_ticks = config.invasion_render_grace_ticks
    state.use_space_platform = config.use_space_platform
    state.nonspace_support_size = config.nonspace_support_size
    state.rocket_launch_weight_threshold = config.rocket_launch_weight_threshold
end

local function ensure_team_state(force_name)
    ensure_indexes()
    if not is_team_force_name(force_name) then
        init_state_defaults(expanse, DEFAULT_FORCE_NAME)
        return expanse
    end
    local state = expanse.team_states[force_name]
    if not state then
        state = {}
        expanse.team_states[force_name] = state
    end
    init_state_defaults(state, force_name)
    return state
end

local function iter_states()
    local states = { expanse }
    for _, state in pairs(expanse.team_states or {}) do
        states[#states + 1] = state
    end
    return pairs(states)
end

local function state_from_force_name(force_name)
    if is_mts_active() and is_team_force_name(force_name) then
        return ensure_team_state(force_name)
    end
    init_state_defaults(expanse, DEFAULT_FORCE_NAME)
    return expanse
end

local function state_matches_surface(state, surface)
    return state and surface and (
        state.active_surface_index == surface.index or
        state.surface_name == surface.name or
        state.source_surface == surface.name or
        state.nonspace_surface == surface.name
    )
end

local state_from_surface

local function state_from_player(player)
    if not player then
        return expanse
    end
    if is_mts_active() then
        local surface_state = state_from_surface(player.surface)
        if surface_state and is_team_force_name(state_key(surface_state)) then
            return surface_state
        end
    end
    if is_mts_active() and not is_team_force_name(player.force.name) then
        return nil
    end
    return state_from_force_name(player.force.name)
end

state_from_surface = function(surface)
    if not surface then
        return nil
    end
    init_state_defaults(expanse, DEFAULT_FORCE_NAME)
    ensure_indexes()
    local mapped_force_name = expanse.surface_to_force[surface.name]
    if mapped_force_name then
        return state_from_force_name(mapped_force_name)
    end
    if state_matches_surface(expanse, surface) then
        return expanse
    end
    local force_name = surface.name:match('^(team%-%d+)%-expanse') or surface.name:match('^(team%-%d+)%-NonOrbit$')
    if force_name then
        return ensure_team_state(force_name)
    end
    for _, state in pairs(expanse.team_states or {}) do
        if state_matches_surface(state, surface) then
            return state
        end
    end
    return nil
end

local function state_from_cargo_pod(pod)
    if not pod or not pod.valid or not pod.unit_number then
        return nil
    end
    for _, state in iter_states() do
        if state.cargo_pods and state.cargo_pods[pod.unit_number] then
            return state
        end
    end
    return state_from_surface(pod.surface)
end

local function state_from_event(event)
    if event and event.force_name then
        return state_from_force_name(event.force_name)
    end
    if event and event.surface then
        return state_from_surface(event.surface)
    end
    return expanse
end

local function state_players(state)
    local force = state_force(state)
    if is_mts_active() and is_team_force_name(force.name) then
        return force.players
    end
    return game.players
end

local function state_print(state, message, color)
    local force = state_force(state)
    if force and force.valid then
        force.print(message, color)
    else
        game.print(message, color)
    end
end

local function register_state_object(state, registration_number)
    if registration_number then
        ensure_indexes()
        expanse.object_to_force[registration_number] = state_key(state)
    end
end

local function ensure_state_ready(state)
    init_state_defaults(state, state and state.force_name or DEFAULT_FORCE_NAME)
    if not state.active_surface_index or not game.surfaces[state.active_surface_index] then
        reset(state)
    end
    return state
end

local function mts_nauvis_surface_names(force_name)
    local names = {}
    if not is_team_force_name(force_name) then
        return names
    end

    names[#names + 1] = force_name .. '-nauvis'
    if SA then
        local slot = force_name:match('^team%-(%d+)$')
        if slot then
            names[#names + 1] = 'mts-nauvis-' .. slot
        end
    end
    return names
end

local function is_protected_expanse_surface(state, surface)
    if not (state and surface and surface.valid) then
        return true
    end
    if state.active_surface_index and surface.index == state.active_surface_index then
        return true
    end
    return surface.name == DEFAULT_SOURCE_SURFACE
        or surface.name == state.surface_name
        or surface.name == state.source_surface
        or surface.name == state.nonspace_surface
end

local function schedule_mts_nauvis_cleanup(state, delay_ticks)
    if not (is_mts_active() and state and is_team_force_name(state_key(state))) then
        return
    end
    init_state_defaults(state, state_key(state))
    if state.cleanup_mts_nauvis == false then
        state.next_mts_nauvis_cleanup_tick = nil
        return
    end

    local target_tick = game.tick + (delay_ticks or 60)
    if not state.next_mts_nauvis_cleanup_tick or target_tick < state.next_mts_nauvis_cleanup_tick then
        state.next_mts_nauvis_cleanup_tick = target_tick
    end
end

local function cleanup_mts_nauvis_surfaces(state)
    if not (is_mts_active() and state and is_team_force_name(state_key(state))) then
        return 0
    end
    init_state_defaults(state, state_key(state))
    state.last_mts_nauvis_cleanup_tick = game.tick
    state.last_mts_nauvis_cleanup_deleted = 0
    state.last_mts_nauvis_cleanup_error = nil
    state.next_mts_nauvis_cleanup_tick = nil

    if state.cleanup_mts_nauvis == false then
        return 0
    end

    local active_surface = state.active_surface_index and game.surfaces[state.active_surface_index] or nil
    if not (active_surface and active_surface.valid) then
        state.last_mts_nauvis_cleanup_error = 'missing active Expanse surface'
        schedule_mts_nauvis_cleanup(state, 60)
        return 0
    end

    local deleted = 0
    for _, surface_name in ipairs(mts_nauvis_surface_names(state_key(state))) do
        local surface = game.surfaces[surface_name]
        if surface and surface.valid and not is_protected_expanse_surface(state, surface) then
            for _, player in pairs(game.players) do
                if player.valid and player.surface and player.surface.valid and player.surface.index == surface.index then
                    if player.force and player.force.valid and player.force.name == state_key(state) then
                        place_player_on_expanse_surface(player, active_surface, player.force.get_spawn_position(active_surface))
                    else
                        player.teleport({ 0, 0 }, active_surface)
                    end
                end
            end

            local occupied = false
            for _, player in pairs(game.players) do
                if player.valid and player.surface and player.surface.valid and player.surface.index == surface.index then
                    occupied = true
                    break
                end
            end

            if occupied then
                state.last_mts_nauvis_cleanup_error = 'players still on ' .. surface_name
                schedule_mts_nauvis_cleanup(state, 60)
            else
                local ok, result = pcall(game.delete_surface, surface)
                if ok and result ~= false then
                    state.cleaned_mts_nauvis_surfaces = state.cleaned_mts_nauvis_surfaces or {}
                    state.cleaned_mts_nauvis_surfaces[surface_name] = game.tick
                    deleted = deleted + 1
                    log('[mts-expanse] deleted unused MTS starter surface ' .. surface_name .. ' for ' .. state_key(state))
                else
                    state.last_mts_nauvis_cleanup_error = ok and ('delete_surface returned ' .. tostring(result)) or tostring(result)
                    schedule_mts_nauvis_cleanup(state, 600)
                end
            end
        end
    end

    state.last_mts_nauvis_cleanup_deleted = deleted
    return deleted
end

local function destroy_container_render(container)
    for _, price in pairs(container and container.price or {}) do
        for _, render in pairs(price.render or {}) do
            if render and render.valid then
                render.destroy()
            end
        end
    end
end

local function destroy_hungry_chest(state, entity)
    if not (entity and entity.valid and entity.unit_number) then
        return
    end
    local container = state.containers and state.containers[entity.unit_number]
    destroy_container_render(container)
    if state.containers then
        state.containers[entity.unit_number] = nil
    end
    entity.destroy()
end

local function same_left_top(left, right)
    return left and right and left.x == right.x and left.y == right.y
end

local function destroy_hungry_chests_for_cell(state, left_top)
    local removed = 0
    for unit_number, container in pairs(state.containers or {}) do
        if same_left_top(container.left_top, left_top) then
            destroy_container_render(container)
            if container.entity and container.entity.valid then
                container.entity.destroy()
            end
            state.containers[unit_number] = nil
            removed = removed + 1
        end
    end
    return removed
end

local function clear_hungry_chests(state, area)
    local surface = state and state.active_surface_index and game.surfaces[state.active_surface_index] or nil
    if not surface then
        return 0
    end
    local filters = { name = 'requester-chest', force = 'neutral' }
    if area then
        filters.area = area
    end
    local removed = 0
    for _, chest in pairs(surface.find_entities_filtered(filters)) do
        destroy_hungry_chest(state, chest)
        removed = removed + 1
    end
    return removed
end

local function destroy_missions_gui(player)
    if player.gui.screen[missions_frame_name] then
        player.gui.screen[missions_frame_name].destroy()
    end
    local button_flow = Gui.get_button_flow(player)
    if button_flow and button_flow[missions_button_name] then
        button_flow[missions_button_name].destroy()
    end
    if player.gui.top[missions_button_name] then
        player.gui.top[missions_button_name].destroy()
    end
end

local function create_button(player)
    local buttons = {}
    if Gui.get_mod_gui_top_frame() then
        buttons[1] =
            Gui.add_mod_button(
                player,
                {
                    type = 'sprite-button',
                    name = main_button_name,
                    sprite = 'item/requester-chest',
                    tooltip = {'expanse.stats_button'},
                    style = Gui.button_style
                }
            )
        if SpaceMissions.enabled() then
            buttons[2] = Gui.add_mod_button(
                player,
                {
                    type = 'sprite-button',
                    name = missions_button_name,
                    sprite = 'item/rocket-part',
                    tooltip = {'expanse.missions_button'},
                    style = Gui.button_style
                }
            )
        else
            destroy_missions_gui(player)
        end
        for _, button in pairs(buttons) do
            if button and button.valid then
                button.style.font_color = { 165, 165, 165 }
                button.style.font = 'default-semibold'
                button.style.minimal_height = 36
                button.style.maximal_height = 36
                button.style.minimal_width = 40
                button.style.padding = -2
            end
        end
    else
        buttons[1] =
            player.gui.top[main_button_name] or
            player.gui.top.add(
                {
                    type = 'sprite-button',
                    sprite = 'item/requester-chest',
                    name = main_button_name,
                    tooltip = {'expanse.stats_button'},
                    style = Gui.button_style
                }
            )
        if SpaceMissions.enabled() then
            buttons[2] =
                player.gui.top[missions_button_name] or
                player.gui.top.add(
                    {
                        type = 'sprite-button',
                        name = missions_button_name,
                        sprite = 'item/rocket-part',
                        tooltip = {'expanse.missions_button'},
                        style = Gui.button_style
                    }
                )
        else
            destroy_missions_gui(player)
        end
        for _, button in pairs(buttons) do
            if button and button.valid then
                button.style.font_color = { r = 0.11, g = 0.8, b = 0.44 }
                button.style.font = 'heading-1'
                button.style.minimal_height = 40
                button.style.maximal_width = 40
                button.style.minimal_width = 38
                button.style.maximal_height = 38
                button.style.padding = 1
                button.style.margin = 0
            end
        end
    end
end

local function set_source_surface(state)
    init_state_defaults(state, state and state.force_name or DEFAULT_FORCE_NAME)
    ensure_indexes()
    local source_name = state.source_surface
    local surface = game.surfaces[source_name]
    local created = false
    if not surface then
        local base = game.surfaces[DEFAULT_SOURCE_SURFACE]
        local map_gen_settings = base and base.map_gen_settings or {}
        surface = game.create_surface(source_name, map_gen_settings)
        created = true
    end
    local map_gen_settings = surface.map_gen_settings
    map_gen_settings.autoplace_controls = {
        ['coal'] = { frequency = 6, size = 0.7, richness = 0.5 },
        ['stone'] = { frequency = 6, size = 0.4, richness = 0.5 },
        ['copper-ore'] = { frequency = 6, size = 0.7, richness = 0.95 },
        ['iron-ore'] = { frequency = 6, size = 0.7, richness = 1 },
        ['uranium-ore'] = { frequency = 10, size = 0.7, richness = 1 },
        ['crude-oil'] = { frequency = 20, size = 1.5, richness = 1.5 },
        ['trees'] = { frequency = 1.75, size = 1.25, richness = 1 },
        ['enemy-base'] = { frequency = 0, size = 0, richness = 0 },
        ['water'] = {frequency = 12, size = 0.25 , richness = 1}
    }
    map_gen_settings.seed = expanse.shared_seed or map_gen_settings.seed or math.random(1, 4000000000)
    map_gen_settings.starting_area = state.map_starting_area
    map_gen_settings.default_enable_all_autoplace_controls = false
    surface.map_gen_settings = map_gen_settings
    expanse.meta_map.source_surface = source_name
    expanse.meta_map.shared_seed = expanse.shared_seed
    expanse.meta_map.biome_offset = expanse.shared_biome_offset
    if created or not expanse.meta_map.source_configured then
        for chunk in surface.get_chunks() do
            surface.delete_chunk({ chunk.x, chunk.y })
        end
        expanse.meta_map.source_configured = true
    elseif destroy_natural_enemy_entities then
        destroy_natural_enemy_entities(surface)
    end
    return surface
end

reset = function(state)
    state = state or expanse
    ensure_indexes()
    init_state_defaults(state, state.force_name or DEFAULT_FORCE_NAME)
    apply_world_settings()
    local enemy = game.forces.enemy
    enemy.set_gun_speed_modifier('rocket', 2)
    enemy.set_gun_speed_modifier('bullet', 2)
    enemy.set_gun_speed_modifier('beam', 2)
    enemy.set_ammo_damage_modifier('rocket', 2)
    enemy.set_ammo_damage_modifier('bullet', 2)
    enemy.set_ammo_damage_modifier('beam', 2)
    clear_hungry_chests(state)
    state.grid = {}
    state.containers = {}
    state.cost_stats = {}
    state.rocket_silos = {}
    state.missions = {
        [4] = {level = 0, delivered = {}},
        [5] = {level = 0, delivered = {}},
        [6] = {level = 0, delivered = {}},
        [7] = {level = 0, delivered = {}},
        [8] = {level = 0, delivered = {}},
        [9] = {level = 0, delivered = {}},
        [10] = {level = 0, delivered = {}},
    }
    state.landing_pad = nil
    state.space_platform = nil
    state.nonspace_pad = nil
    state.nonspace_silo = nil
    state.space_production = {}
    state.cargo_pods = {}
    state.invasion_candidates = {}
    state.invasion_candidate_cells = {}
    state.invasion_tracker = {}
    state.lightning_tiles = {}
    state.schedule = {}
    state.size = 1
    state.reset_tick = game.tick
    state.tree = nil
    state.rock = nil
    state.acid_tank = nil
    state.biome_offset = expanse.shared_biome_offset
    state.tiered_specials = {
        [1] = {unlocks = 0, tiles = 0},
        [2] = {unlocks = 0, tiles = 0},
        [3] = {unlocks = 4, tiles = 0}, --uranium guaranteed
        [4] = {unlocks = SA and 3 or 1, tiles = 0}, --Space Age landing pad/silo, vanilla oil only
        [5] = {unlocks = SA and 5 or 0, tiles = 0}, --Space Age mission silos
        [6] = {unlocks = 80, tiles = 0}, --vulcanus
        [7] = {unlocks = 80, tiles = 0}, --fulgora
        [8] = {unlocks = 80, tiles = 0}, --gleba
        [9] = {unlocks = 80, tiles = 0}, --aquilo
        [10] = {unlocks = 50000, tiles = 0, specials = 1}, --all

    }
    Autostash.insert_into_furnace(true)

    local map_gen_settings = {
        ['water'] = 0,
        ['starting_area'] = 1,
        ['cliff_settings'] = { cliff_elevation_interval = 0, cliff_elevation_0 = 0 },
        ['default_enable_all_autoplace_controls'] = false,
        ['autoplace_settings'] = {
            ['entity'] = { treat_missing_as_default = false },
            ['tile'] = { treat_missing_as_default = false },
            ['decorative'] = { treat_missing_as_default = true, settings = {}}
        },
        autoplace_controls = {
            ['coal'] = { frequency = 0, size = 0, richness = 0 },
            ['stone'] = { frequency = 0, size = 0, richness = 0 },
            ['copper-ore'] = { frequency = 0, size = 0, richness = 0 },
            ['iron-ore'] = { frequency = 0, size = 0, richness = 0 },
            ['uranium-ore'] = { frequency = 0, size = 0, richness = 0 },
            ['crude-oil'] = { frequency = 0, size = 0, richness = 0 },
            ['trees'] = { frequency = 0, size = 0, richness = 0 },
            ['enemy-base'] = { frequency = 0, size = 0, richness = 0 }
        }
    }
    local force = state_force(state)
    local surface = state.active_surface_index and game.surfaces[state.active_surface_index] or game.surfaces[state.surface_name]
    if not surface then
        surface = game.create_surface(state.surface_name, map_gen_settings)
        state.active_surface_index = surface.index
    else
        local old_surface = surface
        local fallback_surface = game.surfaces[DEFAULT_SOURCE_SURFACE]
        for _, player in pairs(game.players) do
            if player.surface.index == old_surface.index then
                player.teleport({ -4, -4 }, fallback_surface)
            end
        end

        state.reset_generation = (state.reset_generation or 0) + 1
        local surface_name = state.surface_name .. tostring(state.reset_generation)
        while game.surfaces[surface_name] do
            state.reset_generation = state.reset_generation + 1
            surface_name = state.surface_name .. tostring(state.reset_generation)
        end

        surface = game.create_surface(surface_name, map_gen_settings)
        state.active_surface_index = surface.index
        state.reset_tick = game.tick
        game.delete_surface(old_surface)
    end
    surface.ignore_surface_conditions = true

    if state.override_nauvis then
        set_source_surface(state)
    end

    local source_surface = game.surfaces[state.source_surface] or set_source_surface(state)
    source_surface.request_to_generate_chunks({ x = 0, y = 0 }, 4)
    source_surface.force_generate_chunk_requests()
    expanse.surface_to_force[state.surface_name] = state_key(state)
    expanse.surface_to_force[surface.name] = state_key(state)
    expanse.surface_to_force[state.source_surface] = state_key(state)
    expanse.surface_to_force[state.nonspace_surface] = state_key(state)
    for _, candidate_force in pairs(game.forces) do
        if candidate_force.valid then
            candidate_force.set_surface_hidden(source_surface, true)
        end
    end

    surface.request_to_generate_chunks({ x = 0, y = 0 }, 4)
    surface.force_generate_chunk_requests()
    local techs = force.technologies
    techs['atomic-bomb'].enabled = false
    for _, tech in pairs(MissionData.locked_techs) do
        techs[tech].enabled = false
        techs[tech].visible_when_disabled = true
    end

    if force and force.valid then
        force.set_spawn_position({ 8, 8 }, surface)
    end

    for _, player in pairs(state_players(state)) do
        player.teleport({ -4, -4 }, source_surface)
    end
    if SpaceMissions.enabled() then
        SpaceMissions.ensure_support(state)
    else
        SpaceMissions.reset_space(state)
    end

    Functions.expand(state, { x = 0, y = 0 })
    Functions.ensure_frontier_chests(state)

    for _, player in pairs(state_players(state)) do
        player.teleport(surface.find_non_colliding_position('character', { state.square_size * 0.5, state.square_size * 0.5 }, 8, 0.5) or {5, 5}, surface)
    end
    schedule_mts_nauvis_cleanup(state, 120)
    game.reset_time_played()
    if SpaceMissions.enabled() then
        script.raise_event(expanse.events.mission_gui_update, { force_name = state_key(state) })
    end
end

local ores = { 'copper-ore', 'iron-ore', 'stone', 'coal', 'iron-ore', 'copper-ore', 'coal', 'iron-ore' }
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

local function count_natural_enemy_entities(surface, area)
    if not (surface and surface.valid) then
        return 0
    end
    local filters = { type = { 'unit', 'turret', 'unit-spawner', 'fish' }, force = { 'enemy', 'neutral' } }
    if area then
        filters.area = area
    end
    local count = 0
    for _, entity in pairs(surface.find_entities_filtered(filters)) do
        if is_natural_enemy_entity(entity) then
            count = count + 1
        end
    end
    return count
end

destroy_natural_enemy_entities = function(surface, area)
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

local function generate_ore(surface, left_top, state)
    local seed = (state and state.shared_seed) or (expanse and expanse.shared_seed) or surface.map_gen_settings.seed
    local left_top_x = left_top.x
    local left_top_y = left_top.y

    --Draw the mixed ore patches.
    for x = 0, 31, 1 do
        for y = 0, 31, 1 do
            local pos = { x = left_top_x + x, y = left_top_y + y }
            if surface.can_place_entity({ name = 'iron-ore', position = pos }) then
                local noise = GetNoise('smol_areas', pos, seed)
                if math.abs(noise) > 0.78 or math.abs(noise) < 0.11 then
                    local amount = 500 + math.sqrt(pos.x ^ 2 + pos.y ^ 2) * 4
                    local i = math.floor(noise * 40 + math.abs(pos.x) * 0.05) % 8 + 1
                    surface.create_entity({ name = ores[i], position = pos, amount = amount })
                end
            end
        end
    end
end

local function on_resource_depleted(event)
    local ore = event.entity
    if ore and ore.valid then
        local distance = math.sqrt(ore.position.x ^ 2 + ore.position.y ^ 2)
        if ore.name == 'stone' and distance > 100 then
            if math.random(1, 4) == 1 then
                ore.surface.create_entity({ name = 'uranium-ore', position = ore.position, amount = 200 + math.floor(distance) * math.random(1, 3) })
            end
        end
    end
end

local function is_tile_in_open_cell(state, x, y)
    if not (state and state.grid and state.square_size) then
        return false
    end
    local square_size = state.square_size
    local cell_x = x - x % square_size
    local cell_y = y - y % square_size
    return state.grid[tostring(cell_x .. '_' .. cell_y)] == true
end

local function on_chunk_generated(event)
    local surface = event.surface
    local state = state_from_surface(surface)

    if not state or surface.index ~= state.active_surface_index then
        if state and state.override_nauvis and surface.name == state.source_surface then
                for _, e in pairs(surface.find_entities_filtered({ area = event.area, name = { 'iron-ore', 'copper-ore', 'coal', 'stone', 'uranium-ore' } })) do
                    surface.create_entity({ name = e.name, position = e.position, amount = 500 + math.sqrt(e.position.x ^ 2 + e.position.y ^ 2) * 3 })
                    e.destroy()
                end
                generate_ore(surface, event.area.left_top, state)
                destroy_natural_enemy_entities(surface, event.area)
        end
        return
    end
    local left_top = event.area.left_top
    local tiles = {}
    local i = 1

    for x = 0, 31, 1 do
        for y = 0, 31, 1 do
            local tile_x = left_top.x + x
            local tile_y = left_top.y + y
            local in_initial_cell = tile_x >= 0 and tile_x < state.square_size and tile_y >= 0 and tile_y < state.square_size
            if not in_initial_cell and not is_tile_in_open_cell(state, tile_x, tile_y) then
                tiles[i] = { name = 'out-of-map', position = { tile_x, tile_y } }
                i = i + 1
            end
        end
    end
    surface.set_tiles(tiles, true)
    destroy_natural_enemy_entities(surface, event.area)
end

local function on_area_cloned(event)
    local dest_surface = event.destination_surface
    for _, cloned_entity in pairs(dest_surface.find_entities(event.destination_area)) do
        if is_natural_enemy_entity(cloned_entity) then
            cloned_entity.destroy()
        elseif cloned_entity.valid then
            cloned_entity.active = true
        end
    end
end

local function position_cell_left_top(state, position)
    local square_size = state.square_size
    return {
        x = position.x - position.x % square_size,
        y = position.y - position.y % square_size
    }
end

local function invasion_cell_key(left_top)
    return tostring(left_top.x .. '_' .. left_top.y)
end

local function invasion_tracker(state)
    state.invasion_tracker = state.invasion_tracker or {}
    return state.invasion_tracker
end

local function is_invasion_schedule_event(stuff)
    return stuff and (stuff.event == 'invasion_warn' or stuff.event == 'invasion_detonate' or stuff.event == 'invasion_trigger')
end

local function count_scheduled_invasion_events(state)
    local count = 0
    local next_tick = nil
    for _, stuff in pairs(state.schedule or {}) do
        if is_invasion_schedule_event(stuff) then
            count = count + 1
            if stuff.tick and (not next_tick or stuff.tick < next_tick) then
                next_tick = stuff.tick
            end
        end
    end
    return count, next_tick
end

local function sync_invasion_tracker(state)
    local tracker = invasion_tracker(state)
    local invasion_numbers = Functions.invasion_numbers(state)
    local scheduled_events, next_scheduled_tick = count_scheduled_invasion_events(state)
    tracker.pending = #(state.invasion_candidates or {})
    tracker.required = invasion_numbers.candidates
    tracker.groups = invasion_numbers.groups
    tracker.scheduled_events = scheduled_events
    tracker.next_scheduled_tick = next_scheduled_tick
    return tracker
end

local function should_create_invasion_candidate(state, expansion_position)
    if state.invasion_enabled == false then
        return false
    end
    if state.sync_invasions == false then
        return math.random(1, 4) == 1
    end
    local left_top = position_cell_left_top(state, expansion_position)
    local cell = Functions.ensure_meta_cell(state, left_top)
    if cell then
        if cell.invasion_candidate == nil then
            cell.invasion_candidate = Functions.cell_random_int(state, left_top, 7001, 4) == 1
        end
        return cell.invasion_candidate
    end
    return Functions.cell_random_int(state, left_top, 7001, 4) == 1
end

local function expected_synced_invasion_candidate(state, expansion_position)
    if state.invasion_enabled == false or state.sync_invasions == false then
        return nil
    end
    local left_top = position_cell_left_top(state, expansion_position)
    local cell = Functions.ensure_meta_cell(state, left_top)
    if cell and cell.invasion_candidate ~= nil then
        return cell.invasion_candidate
    end
    return Functions.cell_random_int(state, left_top, 7001, 4) == 1
end

local function handle_completed_container(state, expansion_position, player)
    local surface = game.surfaces[state.active_surface_index]
    if not surface or not surface.valid then return end
    local unlocker = 'The logistics network'
    if player and player.valid then
        unlocker = { 'expanse.colored_text', player.color.r * 0.6 + 0.35, player.color.g * 0.6 + 0.35, player.color.b * 0.6 + 0.35, player.name }
    end
    state_print(state, { 'expanse.tile_unlock', unlocker, { 'expanse.gps', math.floor(expansion_position.x), math.floor(expansion_position.y), surface.name } })
    state.size = (state.size or 1) + 1
    state.invasion_candidates = state.invasion_candidates or {}
    state.invasion_candidate_cells = state.invasion_candidate_cells or {}
    local tracker = invasion_tracker(state)
    tracker.last_unlock_tick = game.tick
    if should_create_invasion_candidate(state, expansion_position) then
        if surface.count_tiles_filtered({ position = expansion_position, radius = 6, collision_mask = 'water_tile' }) > 40 then
            tracker.last_blocked_water_tick = game.tick
        else
            local left_top = position_cell_left_top(state, expansion_position)
            local key = invasion_cell_key(left_top)
            if not state.invasion_candidate_cells[key] then
                local render = rendering.draw_sprite {
                    sprite = 'utility/danger_icon',
                    surface = surface,
                    target = expansion_position,
                    x_scale = 2,
                    y_scale = 2
                }
                local cell = state.sync_invasions ~= false and Functions.ensure_meta_cell(state, left_top) or nil
                if cell then
                    cell.invasion_candidate = true
                    cell.invasion_position = { x = expansion_position.x, y = expansion_position.y }
                end
                state.invasion_candidate_cells[key] = true
                table.insert(state.invasion_candidates, { surface_index = surface.index, position = expansion_position, render = render, left_top = left_top })
                tracker.last_candidate_tick = game.tick
                tracker.last_candidate = { x = expansion_position.x, y = expansion_position.y }
            end
            Functions.check_invasion(state)
        end
    end
    sync_invasion_tracker(state)
    script.raise_event(expanse.events.gui_update, { force_name = state_key(state) })
end

local function container_opened(event)
    local entity = event.entity
    if not entity then
        return
    end
    if not entity.valid then
        return
    end
    if not entity.unit_number then
        return
    end
    if entity.force.name ~= 'neutral' then
        return
    end
    local state = state_from_surface(entity.surface)
    if not state or entity.surface.index ~= state.active_surface_index then
        return
    end
    local expansion_position = Functions.set_container(state, entity, nil, true)
    if expansion_position then
        local player = game.players[event.player_index]
        handle_completed_container(state, expansion_position, player)
    end
end

local function on_gui_opened(event)
    container_opened(event)
end

local function on_gui_closed(event)
    container_opened(event)
end

local function assign_acid_tank(entity)
    local tanks = entity.surface.find_entities_filtered { name = 'storage-tank', position = entity.position, radius = 8 }
    for _, tank in pairs(tanks) do
        if tank.get_fluid_count('sulfuric-acid') > 0 then
            return tank
        end
    end
    return nil
end

local function uranium_mining(entity, state)
    local force = state_force(state)
    if not force.technologies['uranium-processing'].researched then return end
    if not state.acid_tank or not state.acid_tank.valid then
        state.acid_tank = assign_acid_tank(entity)
    end
    local tank = state.acid_tank
    if tank and tank.valid then
        local acid = tank.get_fluid_count('sulfuric-acid')
        if acid > 5 then
            tank.remove_fluid { name = 'sulfuric-acid', amount = 4 }
            entity.surface.spill_item_stack({position = entity.position, stack ={ name = 'uranium-ore', count = 4 }, enable_looted = true, allow_belts = true})
            FT.flying_text(nil, entity.surface, tank.position, '-4 [fluid=sulfuric-acid]', { r = 0.88, g = 0.02, b = 0.02 })
        end
    end
end

local function infini_rock(entity, state)
    if entity.type ~= 'simple-entity' then
        return
    end
    local techs = state_force(state).technologies
    local inf_ores = {
        ['iron-ore'] = 16,
        ['copper-ore'] = 8,
        ['coal'] = 8,
        ['stone'] = 3,
        ['scrap'] = (SA and techs['recycling'].researched) and 4 or nil,
        ['tungsten-ore'] = (SA and techs['foundry'].researched) and 2 or nil,
        ['calcite'] = (SA and techs['foundry'].researched) and 1 or nil
    }
    local a = math.floor(state.square_size * 0.5)
    if entity.position.x == a + 4 and entity.position.y == a - 4 then
        local newrock = entity.surface.create_entity({ name = 'big-rock', position = { a + 4, a - 4 } })
        local roll = Raffle.raffle(inf_ores)
        entity.surface.spill_item_stack({position = entity.position, stack = { name = roll, count = math.random(80, 160) }, enable_looted = true, allow_belts = true})
        uranium_mining(entity, state)
        if newrock then
            state.rock = script.register_on_object_destroyed(newrock)
            register_state_object(state, state.rock)
        end
    end
end

local function infini_tree(state)
    local techs = state_force(state).technologies
    local trees = {
        ['tree-01'] = 1,
        ['tree-02'] = 1,
        ['tree-02-red'] = 1,
        ['tree-03'] = 1,
        ['tree-04'] = 1,
        ['tree-05'] = 1,
        ['tree-06'] = 1,
        ['tree-06-brown'] = 1,
        ['tree-07'] = 1,
        ['tree-08'] = 1,
        ['tree-08-brown'] = 1,
        ['tree-08-red'] = 1,
        ['tree-09'] = 1,
        ['tree-09-brown'] = 1,
        ['tree-09-red'] = 1,
        ['ashland-lichen-tree'] = (SA and techs['foundry'].researched) and 7 or nil,
        ['funneltrunk'] = (SA and techs['agriculture'].researched) and 5 or nil,
        ['teflilly'] = (SA and techs['agriculture'].researched) and 5 or nil,
        ['stingfrond'] = (SA and techs['agriculture'].researched) and 5 or nil,
        ['sunnycomb'] = (SA and techs['agriculture'].researched) and 5 or nil,
        ['boompuff'] = (SA and techs['agriculture'].researched) and 2 or nil,
    }
    local a = math.floor(state.square_size * 0.5)
    local surface = game.surfaces[state.active_surface_index]
    local position = {a - 4, a + 4}

    local newtree = surface.create_entity({ name = Raffle.raffle(trees), position = position, }) --register_plant = true ?
    if newtree then
        state.tree = script.register_on_object_destroyed(newtree)
        register_state_object(state, state.tree)
    end
end

local function infini_resource(event)
    local entity = event.entity
    if not entity.valid then
        return
    end
    local state = state_from_surface(entity.surface)
    if not state then
        return
    end
    if entity.name == 'big-rock' then
        infini_rock(entity, state)
    end
end

local function infini_resource2(event)
    local force_name = expanse.object_to_force and expanse.object_to_force[event.registration_number]
    local state = force_name and state_from_force_name(force_name) or nil
    if not state then
        for _, candidate in iter_states() do
            if event.registration_number == candidate.tree or event.registration_number == candidate.rock then
                state = candidate
                break
            end
        end
    end
    if not state then
        return
    end
    if event.registration_number == state.tree then
        infini_tree(state)
    elseif event.registration_number == state.rock then
        local a = math.floor(state.square_size * 0.5)
        infini_rock({type = 'simple-entity', position = {x = a + 4, y = a - 4 }, surface = game.surfaces[state.active_surface_index]}, state)
    end
end

local function on_entity_damaged(event)
    local entity = event.entity
    if not entity or not entity.valid then return end
    if entity.type == 'reactor' then
        if entity.temperature > 800 then
            --we deny reactors to stay over 900 degrees, so there cannnot be nuclear meltdown that would damage the tiles uncontrollably
            entity.temperature = 800
        end
    end
end

local function on_player_joined_game(event)
    local player = game.players[event.player_index]
    if player then
        promote_mts_team_host(player.force.name)
    end
    local state = state_from_player(player)
    if not state then
        create_button(player)
        return
    end
    ensure_state_ready(state)
    local surface = game.surfaces[state.active_surface_index]
    local position
    if player.online_time == 0 then
        position = { state.square_size * 0.5, state.square_size * 0.5 }
    end

    if player.surface.index ~= state.active_surface_index or not (player.character and player.character.valid) then
        place_player_on_expanse_surface(player, surface, position or player.force.get_spawn_position(surface))
    end

    create_button(player)
end

local function on_player_changed_force(event)
    if not is_mts_active() then
        return
    end
    local player = game.get_player(event.player_index)
    if not player or not player.valid or not is_team_force_name(player.force.name) then
        return
    end
    local state = ensure_team_state(player.force.name)
    expanse.pending_player_teleports[player.index] = {
        force_name = state_key(state),
        tick = game.tick + 5
    }
    schedule_mts_nauvis_cleanup(state, 180)
    promote_mts_team_host(player.force.name)
end

local function on_pre_player_left_game(event)
    local player = game.players[event.player_index]
    if not player.character then
        return
    end
    if not player.character.valid then
        return
    end
    local inventory = player.get_main_inventory()
    if not inventory then
        return
    end
    local removed_count = inventory.remove({ name = 'coin', count = 999999 })
    if removed_count > 0 then
        for _ = 1, removed_count, 1 do
            player.surface.spill_item_stack({position = player.position, stack = { name = 'coin', count = 1 }, enable_looted = false, allow_belts = false})
        end
        game.print({ 'expanse.tokens_dropped', player.name, { 'expanse.gps', math.floor(player.position.x), math.floor(player.position.y), player.surface.name } })
    end
end

local function on_init()
    ensure_indexes()
    init_state_defaults(expanse, DEFAULT_FORCE_NAME)
    local T = Map_info.get_map_information()
    T.localised_category = 'expanse'
    T.main_caption_color = { r = 170, g = 170, b = 0 }
    T.sub_caption_color = { r = 120, g = 120, b = 0 }

    apply_world_settings()
    if is_mts_active() then
        set_source_surface(expanse)
        promote_all_mts_team_hosts()
    else
        reset(expanse)
    end
end

local function map_reset(event)
    local state = state_from_event(event)
    SpaceMissions.reset_space(state)
    reset(state)
end

local function on_configuration_changed(_event)
    ensure_indexes()
    init_state_defaults(expanse, DEFAULT_FORCE_NAME)
    if not expanse.active_surface_index or not game.surfaces[expanse.active_surface_index] then
        if not is_mts_active() then
            on_init()
            return
        end
    end

    for _, player in pairs(game.players) do
        create_button(player)
    end
    for _, state in iter_states() do
        if SpaceMissions.enabled() then
            SpaceMissions.ensure_support(state)
        else
            SpaceMissions.reset_space(state)
        end
        schedule_mts_nauvis_cleanup(state, 120)
    end
    if SpaceMissions.enabled() then
        script.raise_event(expanse.events.mission_gui_update, {})
    end
    promote_all_mts_team_hosts()
end

local function on_runtime_mod_setting_changed(event)
    if not (event and event.setting and event.setting:match('^mts%-expanse%-')) then
        return
    end
    for _, state in iter_states() do
        init_state_defaults(state, state_key(state))
    end
    apply_world_settings()
    script.raise_event(expanse.events.gui_update, {})
    if SpaceMissions.enabled() then
        script.raise_event(expanse.events.mission_gui_update, {})
    end
end

local function victory(event)
    local state = state_from_event(event)
    state_print(state, {'expanse.script-victory'})
    for _, player in pairs(state_players(state)) do
        player.play_sound { path = 'utility/game_won', volume_modifier = 0.9 }
    end
    table.insert(state.schedule, { tick = game.tick + state.map_reset_delay_ticks, event = 'map_reset', parameters = { force_name = state_key(state) } })
end

local function process_pending_player_teleports()
    if not expanse.pending_player_teleports then
        return
    end
    for player_index, pending in pairs(expanse.pending_player_teleports) do
        if game.tick >= pending.tick then
            local player = game.get_player(player_index)
            local state = player and player.valid and state_from_player(player) or nil
            if state and state_key(state) == pending.force_name then
                ensure_state_ready(state)
                local surface = game.surfaces[state.active_surface_index]
                place_player_on_expanse_surface(player, surface, { state.square_size * 0.5, state.square_size * 0.5 })
                create_button(player)
                schedule_mts_nauvis_cleanup(state, 60)
            end
            expanse.pending_player_teleports[player_index] = nil
        end
    end
end

local function process_hungry_chests(state)
    state.last_hungry_scan_tick = game.tick
    local live_containers = 0
    for unit_number, container in pairs(state.containers or {}) do
        local entity = container.entity
        if entity and entity.valid then
            live_containers = live_containers + 1
            local expansion_position = Functions.set_container(state, entity, nil, false)
            if expansion_position then
                state.last_hungry_completion_tick = game.tick
                handle_completed_container(state, expansion_position)
            end
        else
            state.last_hungry_removed_invalid_tick = game.tick
            state.containers[unit_number] = nil
        end
    end
    if live_containers == 0 then
        state.last_frontier_repair_tick = game.tick
        state.last_frontier_repair_created = Functions.ensure_frontier_chests(state)
    end
end

local function process_state_schedule(state)
    if not next(state.schedule or {}) then return end
    local invasion_schedule_changed = false
    for index, stuff in pairs(state.schedule) do
        if game.tick >= stuff.tick then
            stuff.parameters = stuff.parameters or {}
            stuff.parameters.force_name = stuff.parameters.force_name or state_key(state)
            if stuff.event == 'invasion_detonate' then
                local tracker = invasion_tracker(state)
                tracker.last_detonate_tick = game.tick
                tracker.detonated_events = (tracker.detonated_events or 0) + 1
                invasion_schedule_changed = true
            elseif stuff.event == 'invasion_trigger' then
                local tracker = invasion_tracker(state)
                tracker.last_trigger_tick = game.tick
                tracker.triggered_events = (tracker.triggered_events or 0) + 1
                invasion_schedule_changed = true
            elseif stuff.event == 'invasion_warn' then
                local tracker = invasion_tracker(state)
                tracker.last_warning_tick = game.tick
                tracker.warning_events = (tracker.warning_events or 0) + 1
                invasion_schedule_changed = true
            end
            script.raise_event(state.events and state.events[stuff.event] or expanse.events[stuff.event], stuff.parameters)
            state.schedule[index] = nil
        end
    end
    if invasion_schedule_changed then
        sync_invasion_tracker(state)
        script.raise_event(expanse.events.gui_update, { force_name = state_key(state) })
    end
end

local function process_state_tick(state)
    if not state.active_surface_index or not game.surfaces[state.active_surface_index] then
        return
    end
    if state.next_mts_nauvis_cleanup_tick and game.tick >= state.next_mts_nauvis_cleanup_tick then
        cleanup_mts_nauvis_surfaces(state)
    end
    process_hungry_chests(state)
    if SpaceMissions.enabled() then
        SpaceMissions.ensure_support(state)
        SpaceMissions.launch_rockets(state)
        if game.tick % state.space_production_interval_ticks == 0 then
            SpaceMissions.produce_space_goods(state)
            SpaceMissions.deliver_goods(state)
        end
    end
    process_state_schedule(state)
end

local function on_tick()
    promote_all_mts_team_hosts()
    process_pending_player_teleports()
    for _, state in iter_states() do
        process_state_tick(state)
    end
end

local function resource_stats(parent, name, quality, count, state)
    local color = prototypes.quality[quality].color
    local tooltip = {'expanse.colored_text', color.r, color.g, color.b, Functions.get_item_tooltip(name, quality, true, state and state_force(state) or nil)}
    local button = parent.add({ type = 'sprite-button', name = name .. '|' .. quality .. '_sprite', sprite = 'item/' .. name, quality = quality, enabled = false, tooltip = tooltip })
    local label = parent.add({ type = 'label', name = name .. '|' .. quality .. '_label', caption = format_number(tonumber(count), true), tooltip = count })
    label.style.width = 40
    label.style.font_color = color
    return button, label
end

local function create_main_frame(player)
    local state = state_from_player(player)
    if not state then
        player.print('Join a Multi-Team Support team before opening Expanse.')
        return
    end
    ensure_state_ready(state)
    local frame, inside_frame = Gui.add_main_frame_with_toolbar(player, 'screen', main_frame_name, false, close_main_frame_button_name, { 'expanse.stats_gui' })
    --local frame = player.gui.screen.add({ type = 'frame', name = main_frame_name, caption = { 'expanse.stats_gui' }, direction = 'vertical' })
    if not frame or not inside_frame then return end
    frame.location = { x = 10, y = 50 }
    frame.style.maximal_height = 600
    local invasion_numbers = Functions.invasion_numbers(state)
    inside_frame.add({ type = 'label', name = 'size', caption = { 'expanse.stats_size', state.size or 1 } })
    inside_frame.add({ type = 'label', name = 'biters', caption = { 'expanse.stats_attack', #state.invasion_candidates, invasion_numbers.candidates, invasion_numbers.groups } })
    local scroll = inside_frame.add({ type = 'scroll-pane', name = 'scroll_pane', horizontal_scroll_policy = 'never', vertical_scroll_policy = 'auto-and-reserve-space' })

    local frame_table = scroll.add({ type = 'table', name = 'resource_stats', column_count = 8 })
    frame_table.style.horizontally_stretchable = true
    frame_table.style.vertically_stretchable = true
    for qname, count in table.spairs(state.cost_stats, function (t, a, b) return t[a] > t[b] end) do
        local name, quality = Functions.split_key(qname)
        resource_stats(frame_table, name, quality, count, state)
    end
end

local function update_resource_gui(event)
    for _, player in pairs(game.connected_players) do
        if player.gui.screen[main_frame_name] then
            local state = state_from_player(player)
            if not state or (event.force_name and state_key(state) ~= event.force_name) then
                goto continue
            end
            local frame = player.gui.screen[main_frame_name]['inside_frame']
            local invasion_numbers = Functions.invasion_numbers(state)
            frame['size'].caption = { 'expanse.stats_size', state.size or 1 }
            frame['biters'].caption = { 'expanse.stats_attack', #state.invasion_candidates, invasion_numbers.candidates, invasion_numbers.groups }
            if event.item and event.quality then
                local frame_table = frame['scroll_pane']['resource_stats']
                local count = state.cost_stats[Functions.make_key(event.item, event.quality)] or 0
                if not frame_table[event.item .. '|' .. event.quality .. '_label'] then
                    resource_stats(frame_table, event.item, event.quality, count, state)
                else
                    frame_table[event.item .. '|' .. event.quality .. '_label'].caption = format_number(tonumber(count), true)
                    frame_table[event.item .. '|' .. event.quality .. '_label'].tooltip = count
                end
            end
        end
        ::continue::
    end
end

local function mission_stats(parent, name, quality, count, delivered, state)
    local color = prototypes.quality[quality].color
    local tooltip = {'expanse.colored_text', color.r, color.g, color.b, Functions.get_item_tooltip(name, quality, false, state and state_force(state) or nil)}
    local button = parent.add({ type = 'sprite-button', name = name .. '|' .. quality .. '_sprite', sprite = 'item/' .. name, quality = quality, enabled = false, tooltip = tooltip })
    local label = parent.add({ type = 'label', name = name .. '|' .. quality .. '_label', caption = {'expanse.missions_progress', format_number(tonumber(delivered), true), format_number(tonumber(count), true)} })
    label.style.minimal_width = 40
    label.style.font_color = delivered == count and {r = 0, g = 0.88, b = 0} or {r = 0.88, g = 0, b = 0}
    return button, label
end

local function mission_rewards(parent, type, reward)
    local type_sprites = {
        ['research'] = 'virtual-signal/signal-science-pack',
        ['production'] = 'virtual-signal/signal-clockwise-circle-arrow',
        ['once'] = 'virtual-signal/signal-1',
        ['script'] = 'virtual-signal/signal-check'
    }
    local things = {''}
    if type == 'research' then
        for tech, progress in pairs(reward) do
            things = {'', things, {'expanse.missions_reward_tech', tech, {'technology-name.' .. tech}, progress * 100}}
        end
    elseif type == 'script' then
        for thing, value in pairs(reward) do
            things = {'', things, {'expanse.script-' .. thing, value}}
            things = {'', things, '\n'}
            if thing == 'new-ship' then
                things = {'', things, {'expanse.ship-desc-' .. value}}
                things = {'', things, '\n'}
            end
        end
    elseif type == 'production' or type == 'once' then
        for qname, count in pairs(reward) do
            local name, quality = Functions.split_key(qname)
            things = {'', things, count}
            things = {'', things, ' [item=' .. name .. ',quality=' .. quality .. ']\n'}
        end
    end
    local tooltip = {'expanse.missions_reward_tooltip', {'expanse.missions_reward_' .. type}, things}
    local type_button = parent.add({ type = 'sprite-button', sprite = type_sprites[type], name = 'reward|' .. type, tooltip = tooltip, enabled = false})
    return type_button
end

local function create_missions_frame(player, location, selected_tab_index)
    if not SpaceMissions.enabled() then
        destroy_missions_gui(player)
        player.print('Space missions are only available when Space Age is enabled.')
        return
    end
    local state = state_from_player(player)
    if not state then
        player.print('Join a Multi-Team Support team before opening Expanse.')
        return
    end
    ensure_state_ready(state)
    local frame, inside_frame = Gui.add_main_frame_with_toolbar(player, 'screen', missions_frame_name, false, close_missions_button_name, { 'expanse.missions_gui' })
    --local frame = player.gui.screen.add({ type = 'frame', name = missions_frame_name, caption = { 'expanse.missions_gui' }, direction = 'vertical' })
    if not frame or not inside_frame then return end
    local pane = inside_frame.add({ type = 'tabbed-pane', name = 'missions_tab_pane' })
    frame.location = location or { x = 210, y = 50 }
    frame.style.maximal_height = 600
    local prod_tab = pane.add({ type = 'tab', caption = 'Production', name = 'mission_tab_prod', style = 'slightly_smaller_tab' })
    local prod_frame = pane.add({ type = 'frame', name = 'prod_frame', direction = 'vertical', style = 'mod_gui_inside_deep_frame' })
    prod_frame.style.padding = 8
    prod_frame.style.horizontally_stretchable = true
    prod_frame.style.vertically_stretchable = true
    pane.add_tab(prod_tab, prod_frame)
    prod_frame.add({ type = 'label', caption = {'expanse.production_label'}, name = 'prod_label'})
    local prod_table = prod_frame.add({ type = 'table', name = 'prod_table', column_count = 10 })
    for qname, count in pairs(state.space_production) do
        local name, quality = Functions.split_key(qname)
        resource_stats(prod_table, name, quality, count, state)
    end
    for i = 4, SA and 10 or 5, 1 do
        local req = MissionData.mission_unlocks[i]
        local level = state.missions[i].level
        local tab = pane.add({ type = 'tab', caption = 'M' .. i, name = 'mission_tab_' .. i, style = 'slightly_smaller_tab' })
        local mission_frame = pane.add({ type = 'frame', name = 'mission_frame' .. i, direction = 'vertical', style = 'mod_gui_inside_deep_frame' })
        mission_frame.style.padding = 8
        mission_frame.style.horizontally_stretchable = true
        mission_frame.style.vertically_stretchable = true
        pane.add_tab(tab, mission_frame)
        local mission_table = mission_frame.add({ type = 'table', name = 'mission_table' .. i, column_count = 2})
        mission_table.add({ type = 'sprite-button', name = 'tier' .. i, sprite = 'virtual-signal/signal-' .. (i < 10 and i or 0), tooltip = {'expanse.missions_tier', i, level}, enabled = false })
        mission_table.add({ type = 'label', name = 'mission_label' .. i, caption = {'expanse.missions_tier', i, level} })
        mission_table.add({ type = 'sprite-button', name = 'mission_unlock' .. i, sprite = 'virtual-signal/signal-info', enabled = false})

        local lore_table = mission_table.add({ type = 'table', name = 'lore_table' .. i, column_count = 2})
        lore_table.add({ type = 'sprite-button', name = 'lore-unlock' .. i, sprite = 'virtual-signal/signal-unlock', enabled = false})
        lore_table.add({ type = 'label', name = 'lore-' .. i .. '-u', caption = {'expanse.missions_reqs', req, {'technology-name.' .. req}} })
        -- for s = 0, level, 1 do
        --     local sprite = (s == level) and 'virtual-signal/signal-hourglass' or 'virtual-signal/signal-check'
        --     lore_table.add({ type = 'sprite-button', name = 'lore-' .. i .. '-' .. s, sprite = sprite, enabled = false})
        --     lore_table.add({ type = 'label', name = 'lore-label-' .. i .. '-' .. s, caption = {'expanse-lore.m' .. i .. '-' .. s}})
        -- end

        mission_table.add({ type = 'sprite-button', name = 'dummy' .. i, sprite = 'item/rocket-part', enabled = false, tooltip = {'expanse.missions_mission'} })
        local tier_table = mission_table.add({ type = 'table', name = 'mission_reqs' .. i, column_count = 10 })
        mission_table.add({ type = 'sprite-button', name = 'reward' .. i, sprite = 'virtual-signal/signal-output', enabled = false, tooltip = {'expanse.missions_reward'}})
        local reward_table = mission_table.add({ type = 'table', name = 'reward_table' .. i, column_count = 10})
        if level > 0 then
            local costs = SA and MissionData.costs[i] or MissionData.nonspace_costs[i]
            for qname, count in pairs(costs[state.missions[i].level]) do
                local name, quality = Functions.split_key(qname)
                local delivered = state.missions[i].delivered[qname] or 0
                mission_stats(tier_table, name, quality, count, delivered, state)
            end
            local rewards = SA and MissionData.rewards[i] or MissionData.nonspace_rewards[i]
            for type, reward in pairs(rewards[level]) do
                mission_rewards(reward_table, type, reward)
            end
        end
    end
    pane.selected_tab_index = selected_tab_index or 1
end

local function update_mission_gui(event)
    if not SpaceMissions.enabled() then
        for _, player in pairs(game.connected_players) do
            destroy_missions_gui(player)
        end
        return
    end
    for _, player in pairs(game.connected_players) do
        if player.gui.screen[missions_frame_name] then
            local state = state_from_player(player)
            if not state or (event.force_name and state_key(state) ~= event.force_name) then
                goto continue
            end
            local frame = player.gui.screen[missions_frame_name]
            local location = frame.location
            local selected_tab_index = frame['inside_frame']['missions_tab_pane'].selected_tab_index
            frame.destroy()
            create_missions_frame(player, location, selected_tab_index)
        end
        ::continue::
    end
end

local function on_gui_click(event)
    local element = event.element
    if not element.valid then
        return
    end
    local name = element.name
    local player = game.players[event.player_index]

    if name == main_button_name or name == close_main_frame_button_name then
        if player.gui.screen[main_frame_name] then
            player.gui.screen[main_frame_name].destroy()
        else
            create_main_frame(player)
        end
        return
    end
    if name == missions_button_name or name == close_missions_button_name then
        if not SpaceMissions.enabled() then
            destroy_missions_gui(player)
            player.print('Space missions are only available when Space Age is enabled.')
            return
        end
        if player.gui.screen[missions_frame_name] then
            player.gui.screen[missions_frame_name].destroy()
        else
            create_missions_frame(player)
        end
        return
    end
end

local function on_research_finished(event)
    local research = event.research
    local force = research.force
    local state = state_from_force_name(force.name)
    if not state then return end
    if not SpaceMissions.enabled() then return end
    local banned_items = {
        ['cargo-landing-pad'] = (not state.landing_pad or not state.landing_pad.valid) and true or false,
        ['rocket-silo'] = true,
        ['atomic-bomb'] = true
    }
    for recipe, state in pairs(banned_items) do
        if state == true then
            force.recipes[recipe].enabled = false
        end
    end
    for tier, name in pairs(MissionData.mission_unlocks) do
        if research.name == name then
            SpaceMissions.unlock_mission_tier(state, tier)
        end
    end
end

local function on_rocket_launch_ordered(event)
    if not SpaceMissions.enabled() then return end
    local silo = event.rocket_silo
    local pod = event.rocket.attached_cargo_pod
    if not (silo and silo.valid and pod and pod.valid) then return end
    local state = state_from_surface(silo.surface)
    if not state then return end
    local data = state.rocket_silos[silo.unit_number]
    if not data then return end

    state.cargo_pods[pod.unit_number] = {pod = pod, tier = data.tier, source = silo}
end

local function on_cargo_pod_finished_ascending(event)
    if not SpaceMissions.enabled() then return end
    local pod = event.cargo_pod
    if not pod or not pod.valid then return end
    local state = state_from_cargo_pod(pod)
    if state then
        SpaceMissions.rocket_delivery(state, pod)
    end
end

local function cmd_handler(event, admin_required)
	local player = event and event.player_index and game.get_player(event.player_index) or nil
	local p
	if not (player and player.valid) then
		p = log
	else
		p = player.print
	end
	if player and admin_required and not player.admin then
		p('You are not an admin!')
		return false, nil, p
	end
	return true, player or {name = 'Server'}, p
end

local function state_from_command(player, parameter)
    local force_name = parameter and parameter:match('^%s*(team%-%d+)%s*$')
    if force_name then
        return state_from_force_name(force_name)
    end
    return player and player.valid and state_from_player(player) or expanse
end

local function parse_admin_number(value)
    if not value then
        return nil
    end
    local number = tonumber(value)
    if not number then
        return nil
    end
    return math.floor(number)
end

local function parse_admin_args(parameter)
    local args = {}
    for arg in string.gmatch(parameter or '', '%S+') do
        args[#args + 1] = arg
    end
    return args
end

local function clamp_admin_radius(value, default, max)
    value = parse_admin_number(value) or default
    if value < 0 then
        value = 0
    end
    if value > max then
        value = max
    end
    return value
end

local function state_grid_key(left_top)
    return tostring(left_top.x .. '_' .. left_top.y)
end

local function parse_state_grid_key(key)
    local x, y = tostring(key):match('^(-?%d+)_(-?%d+)$')
    if not x or not y then
        return nil
    end
    return { x = tonumber(x), y = tonumber(y) }
end

local function snap_to_cell(state, position)
    local square_size = state.square_size
    return {
        x = position.x - position.x % square_size,
        y = position.y - position.y % square_size
    }
end

local function open_admin_cell(state, left_top, player)
    state.grid = state.grid or {}
    local key = state_grid_key(left_top)
    if state.grid[key] then
        return false
    end
    local removed_chests = destroy_hungry_chests_for_cell(state, left_top)
    Functions.expand(state, left_top)
    local a = math.floor(state.square_size * 0.5)
    handle_completed_container(state, { x = left_top.x + a, y = left_top.y + a }, player)
    return true, removed_chests
end

local function open_admin_square(state, center_left_top, radius, player)
    local opened = 0
    local square_size = state.square_size
    for dx = -radius, radius, 1 do
        for dy = -radius, radius, 1 do
            local left_top = {
                x = center_left_top.x + dx * square_size,
                y = center_left_top.y + dy * square_size
            }
            if open_admin_cell(state, left_top, player) then
                opened = opened + 1
            end
        end
    end
    return opened
end

local function open_admin_frontier(state, rings, player)
    local opened = 0
    local square_size = state.square_size
    local max_opened = expanse_config().admin_frontier_max_cells
    local directions = {
        { x = square_size, y = 0 },
        { x = -square_size, y = 0 },
        { x = 0, y = square_size },
        { x = 0, y = -square_size }
    }

    for _ = 1, rings, 1 do
        local candidates = {}
        for key, _ in pairs(state.grid or {}) do
            local left_top = parse_state_grid_key(key)
            if left_top then
                for _, direction in pairs(directions) do
                    local candidate = {
                        x = left_top.x + direction.x,
                        y = left_top.y + direction.y
                    }
                    local candidate_key = state_grid_key(candidate)
                    if not state.grid[candidate_key] then
                        candidates[candidate_key] = candidate
                    end
                end
            end
        end
        if not next(candidates) then
            break
        end
        for _, left_top in pairs(candidates) do
            if opened >= max_opened then
                return opened, true
            end
            if open_admin_cell(state, left_top, player) then
                opened = opened + 1
            end
        end
    end

    return opened, false
end

local function print_admin_open_result(state, player, opened, limited)
    local suffix = limited and ' Limit reached; run the command again to continue.' or ''
    state_print(state, (player.name or 'Server') .. ' admin-opened ' .. opened .. ' Expanse cell(s).' .. suffix)
    script.raise_event(expanse.events.gui_update, { force_name = state_key(state) })
end

local function run_admin_open_batch(state, open_fn)
    local previous_suppression = state.suppress_hungry_chests
    state.suppress_hungry_chests = true
    local results = { pcall(open_fn) }
    state.suppress_hungry_chests = previous_suppression
    if not results[1] then
        error(results[2])
    end
    local created_chests = Functions.ensure_frontier_chests(state)
    return results[2], results[3], created_chests
end

commands.add_command(
    'expanse-reset',
    'Fully resets the current Expanse map. Usage: /expanse-reset [team-N]',
	    function(event)
			local s, player = cmd_handler(event, true)
			if s then
                local state = state_from_command(player, event.parameter)
                if state then
				    map_reset({ force_name = state_key(state) })
				    state_print(state, (player and player.name or 'Server') .. ' has reset the map.')
                elseif player and player.valid then
                    player.print('Join a Multi-Team Support team before resetting Expanse.')
                end
			end
		end
	)

commands.add_command(
    'expanse-open',
    'Admin: opens Expanse cells around your current position. Usage: /expanse-open [radius]',
        function(event)
            local s, player, p = cmd_handler(event, true)
            if not (s and player and player.valid) then
                p('Run this as an admin player.')
                return
            end
            local state = state_from_player(player)
            if not state then
                player.print('Join a Multi-Team Support team before opening Expanse tiles.')
                return
            end
            ensure_state_ready(state)
            if player.surface.index ~= state.active_surface_index then
                player.print('Stand on your Expanse surface, or use /expanse-open-at <x> <y> [radius].')
                return
            end

            local args = parse_admin_args(event.parameter)
            local radius = clamp_admin_radius(args[1], 1, expanse_config().admin_open_max_radius)
            local opened = run_admin_open_batch(state, function()
                return open_admin_square(state, snap_to_cell(state, player.position), radius, player)
            end)
            print_admin_open_result(state, player, opened, false)
        end
    )

commands.add_command(
    'expanse-open-at',
    'Admin: opens Expanse cells around a world coordinate. Usage: /expanse-open-at <x> <y> [radius]',
        function(event)
            local s, player, p = cmd_handler(event, true)
            if not (s and player and player.valid) then
                p('Run this as an admin player.')
                return
            end
            local state = state_from_player(player)
            if not state then
                player.print('Join a Multi-Team Support team before opening Expanse tiles.')
                return
            end
            ensure_state_ready(state)

            local args = parse_admin_args(event.parameter)
            local x = parse_admin_number(args[1])
            local y = parse_admin_number(args[2])
            if not x or not y then
                player.print('Usage: /expanse-open-at <x> <y> [radius]')
                return
            end

            local radius = clamp_admin_radius(args[3], 0, expanse_config().admin_open_max_radius)
            local opened = run_admin_open_batch(state, function()
                return open_admin_square(state, snap_to_cell(state, { x = x, y = y }), radius, player)
            end)
            print_admin_open_result(state, player, opened, false)
        end
    )

commands.add_command(
    'expanse-open-frontier',
    'Admin: opens rings around every currently unlocked Expanse cell. Usage: /expanse-open-frontier [rings]',
        function(event)
            local s, player, p = cmd_handler(event, true)
            if not (s and player and player.valid) then
                p('Run this as an admin player.')
                return
            end
            local state = state_from_player(player)
            if not state then
                player.print('Join a Multi-Team Support team before opening Expanse tiles.')
                return
            end
            ensure_state_ready(state)

            local args = parse_admin_args(event.parameter)
            local rings = clamp_admin_radius(args[1], 1, expanse_config().admin_frontier_max_rings)
            local opened, limited = run_admin_open_batch(state, function()
                return open_admin_frontier(state, rings, player)
            end)
            print_admin_open_result(state, player, opened, limited)
        end
    )

commands.add_command(
    'chest-value',
    'Shows value of the chest nearby',
	    function(event)
	        local s, player = cmd_handler(event, false)
	        if s and player and player.valid then
                local state = state_from_player(player)
                if state then
	                Functions.chest_value(state, player)
                end
	        end
	    end
	)

commands.add_command(
    'expanse-state',
    'Prints a short Expanse state summary.',
	    function(event)
	        local s, player = cmd_handler(event, false)
	        if s and player and player.valid then
	            local state = Public.get_state(player.force.name)
	            player.print('Expanse surface: ' .. tostring(state.active_surface_name) .. ', size: ' .. tostring(state.size))
	        end
	    end
	)
	
	function Public.reset(force_name)
        local state = force_name and state_from_force_name(force_name) or expanse
	    map_reset({ force_name = state_key(state) })
	    return true
	end

    local function first_admin_open_target(state)
        for unit_number, container in pairs(state.containers or {}) do
            if container.left_top and container.entity and container.entity.valid then
                return {
                    left_top = { x = container.left_top.x, y = container.left_top.y },
                    unit_number = unit_number,
                    entity = container.entity
                }
            end
        end
        return nil
    end

    function Public.probe_reveal_first_hungry_chest(force_name)
        local state = force_name and state_from_force_name(force_name) or expanse
        ensure_state_ready(state)
        local target = first_admin_open_target(state)
        if not target then
            return { ok = false, error = 'missing hungry chest target', force_name = state_key(state) }
        end

        local before_container = state.containers and state.containers[target.unit_number]
        local before_revealed = before_container and before_container.revealed == true or false
        local before_price_count = before_container and #(before_container.price or {}) or 0
        local before_point = target.entity.get_logistic_point(defines.logistic_member_index.logistic_container)
        local before_section = before_point and before_point.get_section(1) ~= nil or false

        local expansion_position = Functions.set_container(state, target.entity, target.left_top, true)
        if expansion_position then
            handle_completed_container(state, expansion_position)
        end

        local container = state.containers and state.containers[target.unit_number]
        local point = target.entity.valid and target.entity.get_logistic_point(defines.logistic_member_index.logistic_container) or nil
        local section = point and point.get_section(1) or nil
        local ok, slot = pcall(function()
            return section and section.get_slot(1) or nil
        end)
        local has_request = ok
            and slot
            and slot.value
            and slot.value.type == 'item'
            and slot.value.name
            and slot.min
            and slot.min > 0

        return {
            ok = container ~= nil and container.revealed == true and has_request == true,
            error = (container ~= nil and container.revealed == true and has_request == true) and nil or 'hungry chest did not reveal requests',
            force_name = state_key(state),
            unit_number = target.unit_number,
            left_top = target.left_top,
            before_revealed = before_revealed,
            before_price_count = before_price_count,
            before_section = before_section,
            revealed = container and container.revealed == true,
            price_count = container and #(container.price or {}) or 0,
            request_name = has_request and slot.value.name or nil,
            request_quality = has_request and slot.value.quality or nil,
            request_count = has_request and slot.min or nil
        }
    end

    function Public.probe_complete_first_hungry_chest(force_name)
        local state = force_name and state_from_force_name(force_name) or expanse
        ensure_state_ready(state)
        local surface = game.surfaces[state.active_surface_index]
        if not (surface and surface.valid) then
            return { ok = false, error = 'missing active surface', force_name = state_key(state) }
        end
        local target = first_admin_open_target(state)
        if not target then
            return { ok = false, error = 'missing hungry chest target', force_name = state_key(state) }
        end

        local before_size = state.size or 0
        local reveal_position = Functions.set_container(state, target.entity, target.left_top, true)
        if reveal_position then
            handle_completed_container(state, reveal_position)
        end

        local container = state.containers and state.containers[target.unit_number]
        local entity = container and container.entity or target.entity
        if container and entity and entity.valid then
            local inventory = entity.get_inventory(defines.inventory.chest)
            for _, item_stack in pairs(container.price or {}) do
                local inserted = inventory.insert({
                    name = item_stack.name,
                    count = item_stack.count,
                    quality = item_stack.quality or 'normal'
                })
                if inserted < item_stack.count then
                    return {
                        ok = false,
                        error = 'could not insert requested item',
                        force_name = state_key(state),
                        item = item_stack.name,
                        requested = item_stack.count,
                        inserted = inserted
                    }
                end
            end
            local expansion_position = Functions.set_container(state, entity, target.left_top, true)
            if expansion_position then
                handle_completed_container(state, expansion_position)
            end
        end

        local center = {
            x = target.left_top.x + math.floor(state.square_size * 0.5),
            y = target.left_top.y + math.floor(state.square_size * 0.5)
        }
        local tile = surface.get_tile(center)
        local ok = (state.size or 0) > before_size and tile.valid and tile.name ~= 'out-of-map'
        return {
            ok = ok,
            error = ok and nil or 'hungry chest completion did not unlock target',
            force_name = state_key(state),
            surface_name = surface.name,
            unit_number = target.unit_number,
            left_top = target.left_top,
            center = center,
            tile = tile.valid and tile.name or nil,
            before_size = before_size,
            after_size = state.size or 0,
            cell_size = state.square_size
        }
    end

    function Public.probe_admin_open(force_name)
        local state = force_name and state_from_force_name(force_name) or expanse
        ensure_state_ready(state)
        local surface = game.surfaces[state.active_surface_index]
        if not (surface and surface.valid) then
            return { ok = false, error = 'missing active surface' }
        end
        local target = first_admin_open_target(state)
        if not target then
            return { ok = false, error = 'missing hungry chest target' }
        end
        local before_chests = surface.count_entities_filtered({ name = 'requester-chest', force = 'neutral' })
        local before_size = state.size or 0
        local before_candidates = #(state.invasion_candidates or {})
        local before_schedule = 0
        for _, _ in pairs(state.schedule or {}) do
            before_schedule = before_schedule + 1
        end
        local removed_chests = 0
        local opened_count, _, created_chests = run_admin_open_batch(state, function()
            local opened_cell, removed = open_admin_cell(state, target.left_top)
            removed_chests = removed or 0
            return opened_cell and 1 or 0
        end)
        local opened = opened_count == 1
        local after_chests = surface.count_entities_filtered({ name = 'requester-chest', force = 'neutral' })
        local after_candidates = #(state.invasion_candidates or {})
        local after_schedule = 0
        for _, _ in pairs(state.schedule or {}) do
            after_schedule = after_schedule + 1
        end
        local target_removed = not (target.entity and target.entity.valid)
        local area = { { target.left_top.x, target.left_top.y }, { target.left_top.x + state.square_size, target.left_top.y + state.square_size } }
        local natural_enemy_count = count_natural_enemy_entities(surface, area)
        local a = math.floor(state.square_size * 0.5)
        local expansion_position = { x = target.left_top.x + a, y = target.left_top.y + a }
        local expected_invasion_candidate = expected_synced_invasion_candidate(state, expansion_position)
        local invasion_candidate_blocked_by_water = surface.count_tiles_filtered({ position = expansion_position, radius = 6, collision_mask = 'water_tile' }) > 40
        return {
            ok = opened == true
                and removed_chests > 0
                and created_chests > 0
                and target_removed
                and state.grid[state_grid_key(target.left_top)] == true
                and after_chests > 0
                and natural_enemy_count == 0
                and (not expected_invasion_candidate or invasion_candidate_blocked_by_water or after_candidates > before_candidates or after_schedule > before_schedule),
            opened = opened,
            force_name = state_key(state),
            surface_name = surface.name,
            target = target.left_top,
            target_unit_number = target.unit_number,
            target_removed = target_removed,
            removed_chests = removed_chests,
            created_chests = created_chests,
            before_chests = before_chests,
            after_chests = after_chests,
            before_size = before_size,
            after_size = state.size or 0,
            before_invasion_candidates = before_candidates,
            after_invasion_candidates = after_candidates,
            before_schedule = before_schedule,
            after_schedule = after_schedule,
            expected_invasion_candidate = expected_invasion_candidate,
            invasion_candidate_blocked_by_water = invasion_candidate_blocked_by_water,
            natural_enemy_count = natural_enemy_count
        }
    end

    function Public.probe_synced_invasion(force_name)
        local state = force_name and state_from_force_name(force_name) or expanse
        ensure_state_ready(state)
        if state.sync_invasions == false then
            return { ok = false, error = 'sync invasions disabled', force_name = state_key(state) }
        end
        local surface = game.surfaces[state.active_surface_index]
        if not (surface and surface.valid) then
            return { ok = false, error = 'missing active surface', force_name = state_key(state) }
        end

        local position = { x = math.floor(state.square_size * 0.5), y = math.floor(state.square_size * 0.5) }
        local radius = 32
        local area = { { position.x - radius, position.y - radius }, { position.x + radius, position.y + radius } }
        for _, entity in pairs(surface.find_entities_filtered({ area = area, type = { 'unit', 'turret', 'unit-spawner' }, force = 'enemy' })) do
            if entity.valid then
                entity.destroy()
            end
        end

        Functions.invasion_trigger({
            surface = surface,
            position = position,
            round = 2,
            sync_invasions = true,
            seed = state.shared_seed,
            invasion_salt = 62000,
            biter_base = 2,
            biter_evolution_scale = 0,
            biter_round_scale = 1,
            worm_base = 1,
            worm_evolution_scale = 0,
            attack_radius = 20
        })

        local rows = {}
        local created = surface.find_entities_filtered({ area = area, type = { 'unit', 'turret', 'unit-spawner' }, force = 'enemy' })
        for _, entity in pairs(created) do
            if entity.valid then
                rows[#rows + 1] = table.concat({
                    entity.name,
                    entity.type,
                    math.floor((entity.position.x - position.x) * 100),
                    math.floor((entity.position.y - position.y) * 100)
                }, '|')
            end
        end
        table.sort(rows)
        for _, entity in pairs(created) do
            if entity.valid then
                entity.destroy()
            end
        end

        return {
            ok = #rows > 0,
            error = #rows > 0 and nil or 'no invasion entities created',
            force_name = state_key(state),
            surface_name = surface.name,
            signature = table.concat(rows, ';'),
            entity_count = #rows
        }
    end
			
	    local function shallow_copy(tbl)
        local copy = {}
        for key, value in pairs(tbl or {}) do
            copy[key] = value
        end
        return copy
    end

	    local function table_count(tbl)
        local count = 0
        for _, _ in pairs(tbl or {}) do
            count = count + 1
        end
        return count
    end

    local invasion_probe_config_keys = {
        'invasion_enabled',
        'sync_invasions',
        'invasion_candidate_base',
        'invasion_candidate_evolution_scale',
        'invasion_group_base',
        'invasion_group_evolution_scale',
        'invasion_detonate_delay_ticks',
        'invasion_first_warning_delay_ticks',
        'invasion_extra_warning_1_ticks',
        'invasion_extra_warning_2_ticks',
        'invasion_wave_first_delay_ticks',
        'invasion_wave_interval_ticks',
        'invasion_rounds_base',
        'invasion_rounds_random_max',
        'invasion_biter_base',
        'invasion_biter_evolution_scale',
        'invasion_biter_round_scale',
        'invasion_worm_base',
        'invasion_worm_evolution_scale',
        'invasion_attack_radius'
    }

    local function snapshot_invasion_probe_config(state)
        local snapshot = { nil_keys = {} }
        for _, key in ipairs(invasion_probe_config_keys) do
            if state[key] == nil then
                snapshot.nil_keys[key] = true
            else
                snapshot[key] = state[key]
            end
        end
        return snapshot
    end

    local function restore_invasion_probe_config(state, snapshot)
        for _, key in ipairs(invasion_probe_config_keys) do
            if snapshot.nil_keys[key] then
                state[key] = nil
            else
                state[key] = snapshot[key]
            end
        end
    end

    local function configure_fast_invasion_probe(state)
        state.invasion_enabled = true
        state.sync_invasions = true
        state.invasion_candidate_base = 2
        state.invasion_candidate_evolution_scale = 0
        state.invasion_group_base = 1
        state.invasion_group_evolution_scale = 0
        state.invasion_detonate_delay_ticks = 1
        state.invasion_first_warning_delay_ticks = 1
        state.invasion_extra_warning_1_ticks = 2
        state.invasion_extra_warning_2_ticks = 3
        state.invasion_wave_first_delay_ticks = 1
        state.invasion_wave_interval_ticks = 1
        state.invasion_rounds_base = 1
        state.invasion_rounds_random_max = 0
        state.invasion_biter_base = 1
        state.invasion_biter_evolution_scale = 0
        state.invasion_biter_round_scale = 0
        state.invasion_worm_base = 0
        state.invasion_worm_evolution_scale = 0
        state.invasion_attack_radius = 20
    end

    local function sorted_container_targets(state)
        local targets = {}
        for unit_number, container in pairs(state.containers or {}) do
            if container.entity and container.entity.valid and container.left_top and not state.grid[state_grid_key(container.left_top)] then
                targets[#targets + 1] = {
                    unit_number = unit_number,
                    entity = container.entity,
                    left_top = { x = container.left_top.x, y = container.left_top.y }
                }
            end
        end
        table.sort(targets, function(a, b)
            if a.left_top.x ~= b.left_top.x then
                return a.left_top.x < b.left_top.x
            end
            if a.left_top.y ~= b.left_top.y then
                return a.left_top.y < b.left_top.y
            end
            return a.unit_number < b.unit_number
        end)
        return targets
    end

    local function mark_probe_invasion_candidate(state, left_top)
        local cell = Functions.ensure_meta_cell(state, left_top)
        if not cell then
            return false
        end
        cell.invasion_candidate = true
        cell.invasion_position = nil
        return true
    end

    local function run_regular_invasion_probe_open(state)
        local targets = sorted_container_targets(state)
        for _, target in ipairs(targets) do
            if target.entity and target.entity.valid and mark_probe_invasion_candidate(state, target.left_top) then
                local before_pending = #(state.invasion_candidates or {})
                local reveal_position = Functions.set_container(state, target.entity, target.left_top, true)
                if reveal_position then
                    handle_completed_container(state, reveal_position)
                end

                local container = state.containers and state.containers[target.unit_number]
                local entity = container and container.entity or target.entity
                if container and entity and entity.valid then
                    local inventory = entity.get_inventory(defines.inventory.chest)
                    for _, item_stack in pairs(container.price or {}) do
                        local inserted = inventory.insert({
                            name = item_stack.name,
                            count = item_stack.count,
                            quality = item_stack.quality or 'normal'
                        })
                        if inserted < item_stack.count then
                            return {
                                ok = false,
                                error = 'could not insert requested item',
                                item = item_stack.name,
                                requested = item_stack.count,
                                inserted = inserted
                            }
                        end
                    end

                    local expansion_position = Functions.set_container(state, entity, target.left_top, true)
                    if expansion_position then
                        handle_completed_container(state, expansion_position)
                    end
                end

                local tracker = sync_invasion_tracker(state)
                if #(state.invasion_candidates or {}) > before_pending then
                    return {
                        ok = true,
                        unit_number = target.unit_number,
                        left_top = target.left_top,
                        pending = tracker.pending,
                        required = tracker.required
                    }
                end
            end
        end

        return {
            ok = false,
            error = 'regular open did not queue an invasion candidate',
            targets = #targets,
            tracker = shallow_copy(sync_invasion_tracker(state))
        }
    end

    local function sorted_admin_invasion_targets(state)
        local seen = {}
        local targets = {}
        local square_size = state.square_size
        local directions = {
            { x = square_size, y = 0 },
            { x = -square_size, y = 0 },
            { x = 0, y = square_size },
            { x = 0, y = -square_size }
        }

        local function add_target(left_top)
            local key = state_grid_key(left_top)
            if not seen[key] and not (state.grid and state.grid[key]) then
                seen[key] = true
                targets[#targets + 1] = { x = left_top.x, y = left_top.y }
            end
        end

        for key, is_open in pairs(state.grid or {}) do
            if is_open then
                local left_top = parse_state_grid_key(key)
                if left_top then
                    for _, direction in pairs(directions) do
                        add_target({ x = left_top.x + direction.x, y = left_top.y + direction.y })
                    end
                end
            end
        end

        if #targets == 0 then
            for ring = 1, 12, 1 do
                for dx = -ring, ring, 1 do
                    add_target({ x = dx * square_size, y = -ring * square_size })
                    add_target({ x = dx * square_size, y = ring * square_size })
                end
                for dy = -ring + 1, ring - 1, 1 do
                    add_target({ x = -ring * square_size, y = dy * square_size })
                    add_target({ x = ring * square_size, y = dy * square_size })
                end
                if #targets > 0 then
                    break
                end
            end
        end

        table.sort(targets, function(a, b)
            local da = math.abs(a.x) + math.abs(a.y)
            local db = math.abs(b.x) + math.abs(b.y)
            if da ~= db then
                return da < db
            end
            if a.x ~= b.x then
                return a.x < b.x
            end
            return a.y < b.y
        end)
        return targets
    end

    local function run_admin_invasion_probe_open(state, before_schedule)
        local targets = sorted_admin_invasion_targets(state)
        for _, left_top in ipairs(targets) do
            if not (state.grid and state.grid[state_grid_key(left_top)]) and mark_probe_invasion_candidate(state, left_top) then
                local opened_count, _, created_chests = run_admin_open_batch(state, function()
                    local opened = open_admin_cell(state, left_top)
                    return opened and 1 or 0
                end)
                local tracker = sync_invasion_tracker(state)
                if opened_count == 1 and tracker.last_plan_tick == game.tick and tracker.scheduled_events > before_schedule then
                    return {
                        ok = true,
                        left_top = left_top,
                        created_chests = created_chests,
                        scheduled_events = tracker.scheduled_events,
                        scheduled_invasions = tracker.scheduled_invasions,
                        last_plan_tick = tracker.last_plan_tick
                    }
                end
            end
        end

        return {
            ok = false,
            error = 'admin open did not schedule an invasion',
            targets = #targets,
            before_schedule = before_schedule,
            tracker = shallow_copy(sync_invasion_tracker(state))
        }
    end

    function Public.probe_invasion_tracking(force_name)
        local state = force_name and state_from_force_name(force_name) or expanse
        ensure_state_ready(state)
        local surface = game.surfaces[state.active_surface_index]
        if not (surface and surface.valid) then
            return { ok = false, error = 'missing active surface', force_name = state_key(state) }
        end

        local config_snapshot = snapshot_invasion_probe_config(state)
        configure_fast_invasion_probe(state)
        state.invasion_candidates = {}
        state.invasion_candidate_cells = {}
        state.invasion_tracker = state.invasion_tracker or {}
        sync_invasion_tracker(state)

        local existing_schedule_entries = {}
        for _, stuff in pairs(state.schedule or {}) do
            existing_schedule_entries[stuff] = true
        end
        local before_schedule = count_scheduled_invasion_events(state)
        local before_warning_events = state.invasion_tracker.warning_events or 0
        local before_detonated_events = state.invasion_tracker.detonated_events or 0
        local before_triggered_events = state.invasion_tracker.triggered_events or 0
        local regular = run_regular_invasion_probe_open(state)
        local after_regular_tracker = shallow_copy(sync_invasion_tracker(state))
        local admin = regular.ok and run_admin_invasion_probe_open(state, before_schedule) or {
            ok = false,
            error = 'regular open did not queue candidate first'
        }
        local scheduled_tracker = shallow_copy(sync_invasion_tracker(state))
        local probe_scheduled_events = 0
        if admin.ok then
            for _, stuff in pairs(state.schedule or {}) do
                if not existing_schedule_entries[stuff] and is_invasion_schedule_event(stuff) then
                    stuff.tick = game.tick
                    probe_scheduled_events = probe_scheduled_events + 1
                end
            end
            process_state_schedule(state)
        end
        local trigger_tracker = shallow_copy(sync_invasion_tracker(state))
        local ok = regular.ok == true
            and admin.ok == true
            and scheduled_tracker.pending == 0
            and (scheduled_tracker.scheduled_events or 0) > before_schedule
            and scheduled_tracker.last_plan_tick == game.tick
            and probe_scheduled_events > 0
            and (trigger_tracker.warning_events or 0) > before_warning_events
            and (trigger_tracker.detonated_events or 0) > before_detonated_events
            and (trigger_tracker.triggered_events or 0) > before_triggered_events

        restore_invasion_probe_config(state, config_snapshot)

        return {
            ok = ok,
            error = ok and nil or 'invasion tracking probe failed',
            force_name = state_key(state),
            surface_name = surface.name,
            before_schedule = before_schedule,
            before_warning_events = before_warning_events,
            before_detonated_events = before_detonated_events,
            before_triggered_events = before_triggered_events,
            regular = regular,
            after_regular_tracker = after_regular_tracker,
            admin = admin,
            probe_scheduled_events = probe_scheduled_events,
            tracker = scheduled_tracker,
            trigger_tracker = trigger_tracker,
            verify_tick = game.tick + 30
        }
    end

    local function valid_container_targets(state)
        for _, container in pairs(state.containers or {}) do
            if not (container.entity and container.entity.valid and container.left_top) then
                return false
            end
            if state.grid and state.grid[state_grid_key(container.left_top)] then
                return false
            end
        end
        return true
    end

    function Public.probe_admin_open_variants(force_name)
        local state = force_name and state_from_force_name(force_name) or expanse
        ensure_state_ready(state)
        local surface = game.surfaces[state.active_surface_index]
        if not (surface and surface.valid) then
            return { ok = false, error = 'missing active surface' }
        end

        local at_target = first_admin_open_target(state)
        if not at_target then
            return { ok = false, error = 'missing /expanse-open-at hungry chest target' }
        end

        local before_at_chests = surface.count_entities_filtered({ name = 'requester-chest', force = 'neutral' })
        local opened_at, _, created_at = run_admin_open_batch(state, function()
            return open_admin_square(state, at_target.left_top, 0)
        end)
        local after_at_chests = surface.count_entities_filtered({ name = 'requester-chest', force = 'neutral' })
        local at_ok = opened_at == 1
            and state.grid[state_grid_key(at_target.left_top)] == true
            and after_at_chests > 0
            and created_at > 0
            and valid_container_targets(state)

        local before_frontier_chests = after_at_chests
        local opened_frontier, limited, created_frontier = run_admin_open_batch(state, function()
            return open_admin_frontier(state, 1)
        end)
        local after_frontier_chests = surface.count_entities_filtered({ name = 'requester-chest', force = 'neutral' })
        local frontier_ok = opened_frontier > 0
            and limited ~= true
            and created_frontier > 0
            and after_frontier_chests > 0
            and valid_container_targets(state)

        return {
            ok = at_ok and frontier_ok,
            error = (at_ok and frontier_ok) and nil or 'admin open variant frontier rebuild failed',
            force_name = state_key(state),
            surface_name = surface.name,
            open_at = {
                target = at_target.left_top,
                opened = opened_at,
                created_chests = created_at,
                before_chests = before_at_chests,
                after_chests = after_at_chests,
                ok = at_ok
            },
            open_frontier = {
                opened = opened_frontier,
                limited = limited,
                created_chests = created_frontier,
                before_chests = before_frontier_chests,
                after_chests = after_frontier_chests,
                ok = frontier_ok
            },
            container_count = table_count(state.containers)
        }
    end

    function Public.probe_vanilla_rocket_gating(force_name)
        local state = force_name and state_from_force_name(force_name) or expanse
        ensure_state_ready(state)
        if SpaceMissions.enabled() then
            return { ok = true, skipped = true, mode = Mode.current() }
        end

        local surface = game.surfaces[state.active_surface_index]
        if not (surface and surface.valid) then
            return { ok = false, error = 'missing active surface', mode = Mode.current() }
        end

        local left_top = { x = state.square_size * 20, y = 0 }
        while state.grid and state.grid[state_grid_key(left_top)] do
            left_top.x = left_top.x + state.square_size
        end

        local before_silos = surface.count_entities_filtered({ name = 'rocket-silo' })
        local opened, _, created_chests = run_admin_open_batch(state, function()
            return open_admin_square(state, left_top, 0)
        end)
        local after_silos = surface.count_entities_filtered({ name = 'rocket-silo' })
        local registered_silos = table_count(state.rocket_silos)

        local force = state_force(state)
        local rocket_tech = force and force.technologies and force.technologies['rocket-silo']
        local rocket_recipe = force and force.recipes and force.recipes['rocket-silo']
        if rocket_tech then
            rocket_tech.researched = true
            if force.reset_technology_effects then
                pcall(function()
                    force.reset_technology_effects()
                end)
            end
        end
        local rocket_recipe_enabled = rocket_recipe and rocket_recipe.enabled or false

        local ok = opened == 1
                and created_chests > 0
                and after_silos == before_silos
                and registered_silos == 0
                and rocket_recipe_enabled == true

        return {
            ok = ok,
            error = ok and nil or 'vanilla rocket gating failed',
            mode = Mode.current(),
            target = left_top,
            opened = opened,
            created_chests = created_chests,
            before_silos = before_silos,
            after_silos = after_silos,
            registered_silos = registered_silos,
            rocket_recipe_enabled = rocket_recipe_enabled
        }
    end

    function Public.probe_frontier_repair(force_name)
        local state = force_name and state_from_force_name(force_name) or expanse
        ensure_state_ready(state)
        local surface = game.surfaces[state.active_surface_index]
        if not (surface and surface.valid) then
            return { ok = false, error = 'missing active surface' }
        end

        local before_chests = surface.count_entities_filtered({ name = 'requester-chest', force = 'neutral' })
        local cleared_chests = clear_hungry_chests(state)
        state.containers = {}
        local created_chests = Functions.ensure_frontier_chests(state)
        local after_chests = surface.count_entities_filtered({ name = 'requester-chest', force = 'neutral' })
        local registry_count = table_count(state.containers)

        return {
            ok = after_chests > 0 and registry_count == after_chests,
            force_name = state_key(state),
            surface_name = surface.name,
            before_chests = before_chests,
            cleared_chests = cleared_chests,
            created_chests = created_chests,
            after_chests = after_chests,
            registry_count = registry_count
        }
    end

    local function create_probe_mts_nauvis_surface(state)
        local force_name = state_key(state)
        local surface_name = force_name .. '-nauvis'
        if SA then
            local slot = force_name:match('^team%-(%d+)$')
            if slot then
                surface_name = 'mts-nauvis-' .. slot
            end
        end

        local surface = game.surfaces[surface_name]
        if not surface and SA and game.planets and game.planets[surface_name] then
            local planet = game.planets[surface_name]
            local ok, result = pcall(function()
                return (planet.surface and planet.surface.valid) and planet.surface or planet.create_surface()
            end)
            if ok then
                surface = result
            end
        end
        if not surface then
            local base = game.surfaces[DEFAULT_SOURCE_SURFACE]
            surface = game.create_surface(surface_name, base and base.map_gen_settings or {})
        end
        if surface and surface.valid then
            surface.request_to_generate_chunks({ 0, 0 }, 1)
            surface.force_generate_chunk_requests()
        end
        return surface_name, surface
    end

    function Public.probe_mts_nauvis_cleanup(force_name)
        local state = force_name and state_from_force_name(force_name) or expanse
        ensure_state_ready(state)
        if not (is_mts_active() and is_team_force_name(state_key(state))) then
            return { ok = false, error = 'MTS team force required', force_name = state_key(state) }
        end

        local surface_name, surface = create_probe_mts_nauvis_surface(state)
        local before_exists = surface and surface.valid and true or false
        local deleted = cleanup_mts_nauvis_surfaces(state)
        local after_surface = game.surfaces[surface_name]
        local after_exists = after_surface and after_surface.valid and true or false
        local ok = before_exists and deleted > 0
        return {
            ok = ok,
            error = ok and nil or (state.last_mts_nauvis_cleanup_error or 'starter Nauvis surface was not deleted'),
            force_name = state_key(state),
            surface_name = surface_name,
            before_exists = before_exists,
            after_exists = after_exists,
            deleted = deleted,
            cleanup_tick = state.last_mts_nauvis_cleanup_tick
        }
    end

    local function container_summaries(state)
        local containers = {}
        for unit_number, container in pairs(state.containers or {}) do
            if container.entity and container.entity.valid and container.left_top then
                local remaining = 0
                for _, item_stack in pairs(container.price or {}) do
                    remaining = remaining + (item_stack.count or 0)
                end
                containers[#containers + 1] = {
                    unit_number = unit_number,
                    position = { x = container.entity.position.x, y = container.entity.position.y },
                    left_top = { x = container.left_top.x, y = container.left_top.y },
                    revealed = container.revealed == true,
                    price_count = #(container.price or {}),
                    remaining = remaining
                }
            end
        end
        return containers
    end

	    local function state_summary(state)
		    local mission_levels = {}
		    for tier, mission in pairs(state.missions or {}) do
		        mission_levels[tier] = mission.level
		    end
            local meta_map = state.meta_map or expanse.meta_map or {}
		
		    local surface = state.active_surface_index and game.surfaces[state.active_surface_index] or nil
		    return {
	            force_name = state_key(state),
	        active_surface_index = state.active_surface_index,
	        active_surface_name = surface and surface.name or nil,
	        source_surface = state.source_surface,
            nonspace_surface = state.nonspace_surface,
	        size = state.size or 0,
	            shared_seed = state.shared_seed,
	            biome_offset = state.biome_offset,
                meta_map = {
                    source_surface = meta_map.source_surface,
                    shared_seed = meta_map.shared_seed,
                    biome_offset = meta_map.biome_offset,
                    cell_count = table_count(meta_map.cells),
                    source_configured = meta_map.source_configured
                },
	            cost_stats = shallow_copy(state.cost_stats),
            container_count = table_count(state.containers),
            containers = container_summaries(state),
            mode = Mode.current(),
	        space_age = SA and true or false,
            space_missions_enabled = SpaceMissions.enabled(),
            mission_support_mode = SpaceMissions.support_mode(state),
            space_platform_enabled = SpaceMissions.enabled() and SpaceMissions.uses_space_platform(state) or false,
            settings = expanse_config(),
            last_hungry_scan_tick = state.last_hungry_scan_tick,
            last_hungry_completion_tick = state.last_hungry_completion_tick,
            last_hungry_removed_invalid_tick = state.last_hungry_removed_invalid_tick,
            last_frontier_repair_tick = state.last_frontier_repair_tick,
            last_frontier_repair_created = state.last_frontier_repair_created,
            invasion_candidates = #(state.invasion_candidates or {}),
            invasion_candidate_cells = table_count(state.invasion_candidate_cells),
            invasion_tracker = shallow_copy(sync_invasion_tracker(state)),
            next_mts_nauvis_cleanup_tick = state.next_mts_nauvis_cleanup_tick,
            last_mts_nauvis_cleanup_tick = state.last_mts_nauvis_cleanup_tick,
            last_mts_nauvis_cleanup_deleted = state.last_mts_nauvis_cleanup_deleted,
            last_mts_nauvis_cleanup_error = state.last_mts_nauvis_cleanup_error,
            cleaned_mts_nauvis_surfaces = shallow_copy(state.cleaned_mts_nauvis_surfaces),
	        mission_levels = SpaceMissions.enabled() and mission_levels or nil
	    }
    end

    function Public.probe_rocket_delivery(force_name)
        return SpaceMissions.probe_rocket_delivery(state_from_force_name(force_name or DEFAULT_FORCE_NAME))
    end

	function Public.get_state(force_name)
        if force_name then
            return state_summary(state_from_force_name(force_name))
        end
        local summary = state_summary(expanse)
        if is_mts_active() then
            summary.teams = {}
            for name, state in pairs(expanse.team_states or {}) do
                summary.teams[name] = state_summary(state)
            end
        end
        return summary
	end

Event.on_init(on_init)
Event.on_configuration_changed(on_configuration_changed)
Event.on_nth_tick(60, on_tick)
Event.add(defines.events.on_chunk_generated, on_chunk_generated)
Event.add(defines.events.on_area_cloned, on_area_cloned)
Event.add(defines.events.on_resource_depleted, on_resource_depleted)
Event.add(defines.events.on_entity_died, infini_resource)
Event.add(defines.events.on_gui_closed, on_gui_closed)
Event.add(defines.events.on_gui_opened, on_gui_opened)
Event.add(defines.events.on_gui_click, on_gui_click)
Event.add(defines.events.on_player_joined_game, on_player_joined_game)
Event.add(defines.events.on_player_changed_force, on_player_changed_force)
Event.add(defines.events.on_pre_player_left_game, on_pre_player_left_game)
Event.add(defines.events.on_pre_player_mined_item, infini_resource)
Event.add(defines.events.on_robot_pre_mined, infini_resource)
Event.add(defines.events.on_research_finished, on_research_finished)
Event.add(defines.events.on_rocket_launch_ordered, on_rocket_launch_ordered)
Event.add(defines.events.on_cargo_pod_finished_ascending, on_cargo_pod_finished_ascending)
Event.add(defines.events.on_runtime_mod_setting_changed, on_runtime_mod_setting_changed)
Event.add(defines.events.on_object_destroyed, infini_resource2)
Event.add(defines.events.on_entity_damaged, on_entity_damaged)
Event.add(expanse.events.gui_update, update_resource_gui)
Event.add(expanse.events.mission_gui_update, update_mission_gui)
Event.add(expanse.events.invasion_warn, Functions.invasion_warn)
Event.add(expanse.events.invasion_detonate, Functions.invasion_detonate)
Event.add(expanse.events.invasion_trigger, Functions.invasion_trigger)
Event.add(expanse.events.victory, victory)
Event.add(expanse.events.map_reset, map_reset)

return Public
