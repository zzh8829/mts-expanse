-- Native engine regressions, loaded only into disposable test profiles.
local Event = require 'utils.event'
local Missions = require 'maps.expanse.space_missions'
local Cargo = require 'maps.expanse.cargo_delivery'
local Data = require 'maps.expanse.mission_data'
local Public = {}

function Public.install(Expanse, mts, platform)
    local target = mts and 'team-1' or 'player'
    Event.on_init(function()
        if mts then Expanse.reset(target); Expanse.reset('team-2') end
        local state = Expanse.test_state(target)
        local surface = game.surfaces[state.active_surface_index]
        storage.cargo_test = {checks={}, surface=surface.index, level=state.missions[4].level}
        if mts then
            local other = Expanse.test_state('team-2')
            storage.cargo_test.other_surface = other.active_surface_index
            storage.cargo_test.other_level = other.missions[4].level
        end
    end)
    Event.on_nth_tick(30, function()
        local audit = storage.cargo_test
        if audit.done or game.tick < 10020 then return end
        local state = Expanse.test_state(target)
        if not audit.pad then
            local surface = game.surfaces[state.active_surface_index]
            surface.request_to_generate_chunks({45,45},1)
            surface.force_generate_chunk_requests()
            local tiles = {}
            for x=35,55 do for y=35,55 do tiles[#tiles+1]={name='grass-1',position={x,y}} end end
            surface.set_tiles(tiles)
            audit.pad = assert(surface.create_entity{name='cargo-landing-pad',position={45,45},force=target})
            audit.pad.destructible = false
            state.landing_pad = audit.pad
        end
        local pad = audit.pad
        local dst = pad.get_inventory(defines.inventory.cargo_landing_pad_main)
        local point = pad.get_logistic_point(defines.logistic_member_index.cargo_landing_pad_requester)
        local hub = platform and state.space_platform.hub or state.nonspace_pad
        local src = hub.get_inventory(platform and defines.inventory.hub_main or defines.inventory.cargo_landing_pad_main)
        local launcher = platform and hub or state.nonspace_silo
        if audit.circuit_started then
            if game.tick < audit.circuit_started + 60 then return end
            local requests = point.filters
            assert(#requests == 1 and requests[1].name == 'iron-plate' and requests[1].count == 25, 'circuit requests did not compile')
            Missions.deliver_goods(state)
            local incoming = point.targeted_items_deliver
            assert(#incoming == 1 and incoming[1].name == 'iron-plate' and incoming[1].count == 25, 'circuit request not respected')
            assert(src.get_item_count('iron-plate') == 25, 'wrong circuit payload removed')
            audit.checks.positive_circuit_request = true
            audit.done = true
            helpers.write_file('cargo-result.json', helpers.table_to_json(audit.checks))
            return
        end
        if audit.flight_started then
            if game.tick < audit.flight_started + 3600 then return end
            assert(dst.get_item_count('iron-plate') == 100, 'real cargo did not arrive at the requested quantity')
            assert(pad.surface.count_entities_filtered{type='item-entity'} == audit.ground_before, 'cargo spilled on ground')
            audit.checks.real_delivery_no_spill = true
            dst.clear(); src.clear(); src.insert{name='iron-plate',count=50}
            point.get_section(1).filters = {}
            local combinator = assert(pad.surface.create_entity{name='constant-combinator',position={50,45},force=target})
            combinator.get_or_create_control_behavior().add_section().set_slot(1,{value={type='item',name='iron-plate',quality='normal'},min=25})
            combinator.get_wire_connector(defines.wire_connector_id.circuit_green,true).connect_to(pad.get_wire_connector(defines.wire_connector_id.circuit_green,true))
            pad.get_or_create_control_behavior().circuit_exclusive_mode_of_operation=defines.control_behavior.cargo_landing_pad.exclusive_mode.set_requests
            audit.circuit_started=game.tick
            return
        end
        local pods = {}
        local wrapped = {create_cargo_pod=function()
            local pod = launcher.surface.create_entity{name='cargo-pod',position=launcher.position,force=target}
            if pod then pods[#pods+1] = pod end
            return pod
        end}
        local function clear()
            for _, pod in pairs(pods) do if pod.valid then pod.destroy() end end
            pods = {}
            src.clear(); dst.clear(); dst.set_bar()
            point.enabled = true
            pad.get_or_create_control_behavior().circuit_exclusive_mode_of_operation = defines.control_behavior.cargo_landing_pad.exclusive_mode.none
            for _, section in pairs(point.sections) do if section.is_manual then section.filters = {}; section.active = true; section.multiplier = 1 end end
        end
        local function request(item, count, quality)
            local section = point.get_section(1) or point.add_section()
            section.set_slot(1,{value={type='item',name=item,quality=quality or 'normal',comparator='='},min=count})
            return section
        end
        local function incoming(item, quality)
            local count = 0
            for _, v in pairs(point.targeted_items_deliver) do
                if v.name == item and v.quality == (quality or 'normal') then count = count + v.count end
            end
            return count
        end
        local function send() Cargo.send(src,wrapped,pad) end
        local function check(name, condition) assert(condition,name);audit.checks[name]=true end

        clear(); src.insert{name='iron-plate',count=200};send()
        check('empty_requests_keep_automatic_delivery',incoming('iron-plate')==200 and src.is_empty())
        clear();request('iron-plate',100);dst.insert{name='iron-plate',count=80};src.insert{name='iron-plate',count=300}
        local existing=wrapped.create_cargo_pod();assert(existing)
        existing.get_inventory(defines.inventory.cargo_unit).insert{name='iron-plate',count=15}
        existing.cargo_pod_destination={type=defines.cargo_destination.station,station=pad}
        send();send()
        check('request_counts_existing_and_incoming_without_duplicates',incoming('iron-plate')==20 and src.get_item_count('iron-plate')==295)
        clear();dst.set_bar(2);dst.insert{name='iron-plate',count=95};src.insert{name='iron-plate',count=50};send()
        check('partial_stack_respects_inventory_bar',incoming('iron-plate')==5 and src.get_item_count('iron-plate')==45)
        clear();dst.set_bar(2);dst.insert{name='iron-plate',count=100};src.insert{name='copper-plate',count=50};send()
        check('full_pad_retains_source_items',#pods==0 and src.get_item_count('copper-plate')==50)
        clear();dst.set_bar(2);src.insert{name='iron-plate',count=80};src.insert{name='copper-plate',count=80};send()
        check('different_items_share_one_free_slot',incoming('iron-plate')+incoming('copper-plate')==80 and src.get_item_count()==80)
        clear();dst.set_bar(2);src.insert{name='copper-plate',count=50}
        existing=wrapped.create_cargo_pod();assert(existing)
        existing.get_inventory(defines.inventory.cargo_unit).insert{name='iron-plate',count=1}
        existing.cargo_pod_destination={type=defines.cargo_destination.station,station=pad};send()
        check('incoming_other_item_reserves_shared_slot',incoming('copper-plate')==0 and #pods==1)
        clear();request('iron-plate',100);src.insert{name='iron-plate',count=100};point.enabled=false;send()
        check('disabled_requests_pause',#pods==0)
        clear();local section=request('iron-plate',100);src.insert{name='iron-plate',count=100};section.active=false;send()
        check('inactive_section_does_not_enable_unrestricted_delivery',#pods==0)
        clear();section=request('iron-plate',100);src.insert{name='iron-plate',count=300};section.multiplier=2;send()
        check('native_section_multiplier',incoming('iron-plate')==200)
        clear();section=request('iron-plate',100);src.insert{name='iron-plate',count=300};section.multiplier=0;send()
        check('zero_multiplier_pauses',#pods==0)
        clear();request('iron-plate',0);src.insert{name='iron-plate',count=100};send()
        check('zero_request_does_not_enable_unrestricted_delivery',#pods==0)
        clear();request('iron-plate',10,'legendary');src.insert{name='iron-plate',count=20};src.insert{name='iron-plate',count=20,quality='legendary'};send()
        check('exact_quality_request',incoming('iron-plate')==0 and incoming('iron-plate','legendary')==10)
        clear();request('space-science-pack',7)
        for i=1,20 do src[i].set_stack{name='iron-plate',count=100} end
        src[30].set_stack{name='space-science-pack',count=10};send()
        check('unrequested_front_stacks_do_not_block_later_requests',incoming('space-science-pack')==7 and incoming('iron-plate')==0)
        clear();src.insert{name='iron-plate',count=100}
        pad.get_or_create_control_behavior().circuit_exclusive_mode_of_operation=defines.control_behavior.cargo_landing_pad.exclusive_mode.set_requests
        send();check('empty_circuit_requests_pause',#pods==0)

        clear();src.insert{name='iron-plate',count=100}
        Cargo.send(src,{create_cargo_pod=function() return nil end},pad)
        check('unavailable_hatch_retains_items',src.get_item_count('iron-plate')==100)
        pad.force='neutral';state.landing_pad=pad;Missions.deliver_goods(state)
        check('missing_owned_pad_retains_items',src.get_item_count('iron-plate')==100 and not state.landing_pad)
        pad.force=target;state.landing_pad=pad

        clear();src.insert{name='iron-plate',count=500000}
        state.missions[4].level=2;state.missions[4].delivered={}
        for item,count in pairs(Data.costs[4][2]) do state.missions[4].delivered[item]=count end
        local missionpod=assert(launcher.surface.create_entity{name='cargo-pod',position=launcher.position,force=target});state.cargo_pods[missionpod.unit_number]={pod=missionpod,tier=4}
        Missions.rocket_delivery(state,missionpod);missionpod.destroy()
        check('one_time_reward_survives_full_source',state.missions[4].level==3 and state.pending_space_rewards['space-science-pack|normal']==200)
        src.clear();state.space_production={};Missions.produce_space_goods(state);Missions.produce_space_goods(state)
        check('pending_one_time_reward_paid_exactly_once',src.get_item_count('space-science-pack')==200 and not next(state.pending_space_rewards))
        if mts then
            local other=Expanse.test_state('team-2')
            check('other_team_unchanged',other.active_surface_index==audit.other_surface and other.missions[4].level==audit.other_level and not next(other.space_production))
        end
        clear();state.space_production={};request('iron-plate',100);src.insert{name='iron-plate',count=150}
        audit.ground_before=pad.surface.count_entities_filtered{type='item-entity'}
        Missions.deliver_goods(state)
        check('integrated_delivery_limits_request',incoming('iron-plate')==100 and src.get_item_count('iron-plate')==50)
        audit.flight_started=game.tick
        helpers.write_file('cargo-progress.json',helpers.table_to_json(audit.checks))
    end)
end
return Public
