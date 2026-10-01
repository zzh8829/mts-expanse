-- Native regression for soft-reset rocket deletion and legacy save recovery.
-- Installed only into disposable test profiles.
local Event = require 'utils.event'
local Missions = require 'maps.expanse.space_missions'
local Public = {}

function Public.install(Expanse, mts)
    local target = mts and 'team-1' or 'player'
    local function check(a, name, ok)
        assert(ok, name)
        a.checks[name] = true
    end
    local function contents(silo)
        local result = {}
        for name, id in pairs(defines.inventory) do
            if name:match('^rocket_silo') then
                local inv = silo.get_inventory(id)
                if inv then result[name] = inv.get_contents() end
            end
        end
        return helpers.table_to_json(result)
    end
    Event.on_init(function()
        if mts then Expanse.reset(target) end
        storage.silo_recovery_test = {checks = {}, launches = 0}
    end)
    Event.add(defines.events.on_rocket_launch_ordered, function(event)
        local a = storage.silo_recovery_test
        if a and (event.rocket_silo == a.healthy or event.rocket_silo == a.repaired) then
            a.launches = a.launches + 1
            a.flying_rocket = event.rocket
            a.flying_pod = event.rocket.attached_cargo_pod
        end
    end)
    Event.add(defines.events.on_tick, function()
        local a = storage.silo_recovery_test
        if a.done or game.tick < 600 then return end
        local state = Expanse.test_state(target)
        local surface = game.surfaces[state.active_surface_index]
        if not a.phase then
            surface.request_to_generate_chunks({80,32}, 2);surface.force_generate_chunk_requests()
            local tiles = {}
            for x=52,109 do for y=22,42 do tiles[#tiles+1]={name='grass-1',position={x,y}} end end
            surface.set_tiles(tiles)
            state.missions[4] = {level=2, delivered={}}
            state.rocket_launch_weight_threshold = 2000000 -- Hold until assertions finish.
            state.space_production = {}
            a.healthy = assert(surface.create_entity{name='rocket-silo',position={64,32},force=target})
            a.broken = assert(surface.create_entity{name='rocket-silo',position={96,32},force=target,quality='rare'})
            a.wire_peer = assert(surface.create_entity{name='constant-combinator',position={90,38},force='neutral'})
            for _, silo in ipairs({a.healthy, a.broken}) do
                silo.minable_flag=false;silo.destructible=false
                silo.rocket_parts=2*silo.prototype.rocket_parts_required
                state.rocket_silos[silo.unit_number]={entity=silo,tier=4}
            end
            a.phase='ready'
        end
        for _, silo in ipairs({a.healthy, a.repaired or a.broken}) do
            if silo.valid then silo.energy=1000000 end
        end
        if a.phase=='ready' and a.healthy.rocket_silo_status==defines.rocket_silo_status.rocket_ready
            and a.broken.rocket_silo_status==defines.rocket_silo_status.rocket_ready then
            for _, silo in ipairs({a.healthy,a.broken}) do
                assert(silo.get_inventory(defines.inventory.rocket_silo_rocket).insert{name='space-platform-foundation',count=50}==50)
            end
            local old = a.broken
            old.get_inventory(defines.inventory.rocket_silo_modules).insert{name='productivity-module-2',quality='rare',count=4}
            old.get_inventory(defines.inventory.rocket_silo_input).insert{name='processing-unit',count=7}
            old.get_inventory(defines.inventory.rocket_silo_trash).insert{name='yumako',quality='uncommon',count=3}
            old.health=1000;old.disabled_by_script=true;old.use_transitional_requests=false
            old.crafting_progress=0.25;old.bonus_progress=0.375
            old.get_or_create_control_behavior().read_mode=defines.control_behavior.rocket_silo.read_mode.logistic_inventory
            local peer=a.wire_peer.get_wire_connector(defines.wire_connector_id.circuit_red,true)
            old.get_wire_connector(defines.wire_connector_id.circuit_red,true).connect_to(peer,false)
            local before=contents(old)
            local trash=old.get_inventory(defines.inventory.rocket_silo_trash)[1]
            trash.spoil_percent=0.4
            local spoil=trash.spoil_percent
            old.rocket.destroy()
            check(a,'legacy_ready_without_rocket_reproduced',old.rocket_silo_status==defines.rocket_silo_status.rocket_ready and not old.rocket)
            local hub=state.use_space_platform and state.space_platform.hub or state.nonspace_pad
            check(a,'legacy_native_launch_fails',not old.launch_rocket{type=defines.cargo_destination.station,station=hub})
            local rocket,pod=a.healthy.rocket,a.healthy.rocket.attached_cargo_pod
            check(a,'rocket_is_preserved',Expanse.forfeit_impl.is_preserved_force_entity(state,rocket))
            check(a,'pod_is_preserved',Expanse.forfeit_impl.is_preserved_force_entity(state,pod))
            assert(Expanse.forfeit_impl.run(state))
            check(a,'actual_soft_reset_keeps_rocket_and_pod',rocket.valid and pod.valid)
            local old_unit=old.unit_number
            local record=state.rocket_silos[old_unit]
            check(a,'one_broken_silo_repaired',Missions.repair_silos(state)==1)
            local new=record.entity;a.repaired=new
            check(a,'registration_replaced',not old.valid and state.rocket_silos[old_unit]==nil and state.rocket_silos[new.unit_number]==record)
            check(a,'healthy_silo_untouched',a.healthy.valid and a.healthy.rocket==rocket)
            check(a,'cargo_modules_inputs_and_trash_preserved',contents(new)==before)
            check(a,'spoil_metadata_preserved',new.get_inventory(defines.inventory.rocket_silo_trash)[1].spoil_percent==spoil)
            check(a,'quality_health_flags_preserved',new.quality.name=='rare' and new.health==1000 and not new.destructible and not new.minable_flag and new.disabled_by_script)
            check(a,'buffered_parts_and_craft_progress_preserved',new.rocket_parts==50 and new.crafting_progress==0.25 and new.bonus_progress==0.375)
            check(a,'wires_preserved',new.get_wire_connector(defines.wire_connector_id.circuit_red,false).is_connected_to(peer))
            check(a,'settings_preserved',not new.use_transitional_requests and new.get_control_behavior().read_mode==defines.control_behavior.rocket_silo.read_mode.logistic_inventory)
            check(a,'repair_does_not_repeat',Missions.repair_silos(state)==0)
            new.disabled_by_script=false
            a.phase='recovered'
        elseif a.phase=='recovered' and a.repaired.rocket_silo_status==defines.rocket_silo_status.rocket_ready then
            check(a,'replacement_creates_a_real_rocket',a.repaired.rocket and a.repaired.rocket.valid)
            state.rocket_launch_weight_threshold=999500
            a.phase='launch'
        elseif a.phase=='launch' and a.launches==2 then
            check(a,'both_rockets_launch',true)
            local rocket,pod=a.flying_rocket,a.flying_pod
            assert(Expanse.forfeit_impl.run(state))
            check(a,'reset_during_launch_keeps_rocket_and_pod',rocket.valid and pod.valid)
            a.phase='arrival'
        elseif a.phase=='arrival' and (state.missions[4].delivered['space-platform-foundation|normal'] or 0)==100 then
            check(a,'both_payloads_credited_exactly_once',a.launches==2)
            check(a,'mission_level_unchanged',state.missions[4].level==2)
            helpers.write_file('cargo-result.json',helpers.table_to_json(a.checks))
            a.done=true
        end
    end)
end
return Public
