require 'utils.data_stages'

_LIFECYCLE = _STAGE.control
_DEBUG = false

local Event = require 'utils.event'
local Mode = require 'maps.expanse.mode'

ServerCommands = {
    events = {
        on_entity_mined = Event.generate_event_name('on_entity_mined'),
        custom_on_entity_died = Event.generate_event_name('custom_on_entity_died'),
        remove_surface = Event.generate_event_name('remove_surface'),
        reset_game = Event.generate_event_name('reset_game'),
        init_surfaces = Event.generate_event_name('init_surfaces'),
        on_spell_cast_success = Event.generate_event_name('on_spell_cast_success'),
        on_spell_cast_failure = Event.generate_event_name('on_spell_cast_failure'),
        on_wave_created = Event.generate_event_name('on_wave_created'),
        on_unit_group_created = Event.generate_event_name('on_unit_group_created'),
        on_evolution_factor_changed = Event.generate_event_name('on_evolution_factor_changed'),
        on_game_reset = Event.generate_event_name('on_game_reset'),
        on_target_aquired = Event.generate_event_name('on_target_aquired'),
        on_primary_target_missing = Event.generate_event_name('on_primary_target_missing'),
        on_entity_created = Event.generate_event_name('on_entity_created'),
        on_biters_evolved = Event.generate_event_name('on_biters_evolved'),
        on_spawn_unit_group = Event.generate_event_name('on_spawn_unit_group'),
        on_spawn_unit_group_simple = Event.generate_event_name('on_spawn_unit_group_simple'),
        on_gui_removal = Event.generate_event_name('on_gui_removal'),
        on_gui_closed_main_frame = Event.generate_event_name('on_gui_closed_main_frame'),
        on_player_removed = Event.generate_event_name('on_player_removed'),
        on_rpg_callback_added = Event.generate_event_name('on_rpg_callback_added'),
        on_config_changed = Event.generate_event_name('on_config_changed'),
        on_server_started = Event.generate_event_name('on_server_started'),
        on_changes_detected = Event.generate_event_name('on_changes_detected'),
        on_player_banned = Event.generate_event_name('on_player_banned'),
        on_player_jailed = Event.generate_event_name('on_player_jailed'),
        on_player_unjailed = Event.generate_event_name('on_player_unjailed'),
        bottom_quickbar_respawn_raise = Event.generate_event_name('bottom_quickbar_respawn_raise'),
        bottom_quickbar_location_changed = Event.generate_event_name('bottom_quickbar_location_changed'),
        on_poll_complete = Event.generate_event_name('on_poll_complete'),
        on_poll_created = Event.generate_event_name('on_poll_created'),
        on_player_trusted = Event.generate_event_name('on_player_trusted'),
        on_player_untrusted = Event.generate_event_name('on_player_untrusted'),
        on_role_change = Event.generate_event_name('on_role_change')
    }
}

function ServerCommands.is_dev_server()
    return false
end

function ServerCommands.is_game_modded()
    local count = 0
    for _, _ in pairs(script.active_mods) do
        count = count + 1
        if count > 1 then
            return true
        end
    end
    return false
end

function ServerCommands.has_space_age()
    return Mode.is_space_age()
end

function ServerCommands.is_loaded(module)
    return package.loaded[module] or false
end

function ServerCommands.is_loaded_bool(module)
    return package.loaded[module] ~= nil
end

function ServerCommands.raise_callback(func_token, data)
    local Token = require 'utils.token'
    local func = Token.get(func_token)
    if func then
        return func(data)
    end
end

local Expanse = require 'maps.expanse.main'

remote.add_interface(
    'mts_expanse',
    {
        reset = function (force_name)
            return Expanse.reset(force_name)
        end,
        get_state = function (force_name)
            return Expanse.get_state(force_name)
        end,
        probe_rocket_delivery = function (force_name)
            return Expanse.probe_rocket_delivery(force_name)
        end,
        probe_vanilla_rocket_gating = function (force_name)
            return Expanse.probe_vanilla_rocket_gating(force_name)
        end,
        probe_admin_open = function (force_name)
            return Expanse.probe_admin_open(force_name)
        end,
        probe_admin_open_variants = function (force_name)
            return Expanse.probe_admin_open_variants(force_name)
        end,
        probe_mts_nauvis_cleanup = function (force_name)
            return Expanse.probe_mts_nauvis_cleanup(force_name)
        end,
        probe_frontier_repair = function (force_name)
            return Expanse.probe_frontier_repair(force_name)
        end,
        probe_reveal_first_hungry_chest = function (force_name)
            return Expanse.probe_reveal_first_hungry_chest(force_name)
        end,
        probe_complete_first_hungry_chest = function (force_name)
            return Expanse.probe_complete_first_hungry_chest(force_name)
        end,
        probe_synced_invasion = function (force_name)
            return Expanse.probe_synced_invasion(force_name)
        end,
        probe_invasion_tracking = function (force_name)
            return Expanse.probe_invasion_tracking(force_name)
        end
    }
)
