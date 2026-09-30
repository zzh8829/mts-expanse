-- Native save/load regression; never packaged in the playable mod.
local Event = require 'utils.event'
local Missions = require 'maps.expanse.space_missions'
local Public = {}

function Public.install(Expanse, mts, platform)
    local target = mts and 'team-1' or 'player'
    local loaded = false
    local function source(state)
        local hub = platform and state.space_platform.hub or state.nonspace_pad
        return hub.get_inventory(platform and defines.inventory.hub_main or defines.inventory.cargo_landing_pad_main)
    end
    local function create_pad(state)
        local surface = game.surfaces[state.active_surface_index]
        surface.request_to_generate_chunks({44,44},1);surface.force_generate_chunk_requests()
        local tiles = {}
        for x=34,56 do for y=34,56 do tiles[#tiles+1]={name='grass-1',position={x,y}} end end
        surface.set_tiles(tiles)
        local pad = assert(surface.create_entity{name='cargo-landing-pad',position={44,44},force=target})
        pad.destructible = false
        state.landing_pad = pad
        local point = pad.get_logistic_point(defines.logistic_member_index.cargo_landing_pad_requester)
        local section = point.get_section(1) or point.add_section()
        for i, item in ipairs({{'yumako',300},{'jellynut',300},{'spoilage',0},{'yumako',7,'rare'}}) do
            section.set_slot(i,{value={type='item',name=item[1],quality=item[3] or 'normal',comparator='='},min=item[2]})
        end
        point.enabled = false
        return pad
    end
    Event.on_load(function() loaded = true end)
    Event.on_init(function()
        if mts then Expanse.reset(target) end
        local state = Expanse.test_state(target)
        local src = source(state)
        src.clear();src.insert{name='metallic-asteroid-chunk',count=100000}
        src[1].set_stack{name='spoilage',count=50} -- Legitimate shared-hub rewards must survive.
        state.space_production = {}
        Missions.clear_reward_overflow(state)
        state.reward_overflow = {}
        -- Persist the exact clogged layout produced by 0.1.21, including quality.
        for _, item in ipairs({{'yumako','normal'},{'jellynut','normal'},{'yumako','rare'}}) do
            local inv = game.create_inventory(1)
            inv.insert{name='spoilage',quality=item[2],count=4}
            state.reward_overflow[item[1]..'|'..item[2]] = inv
        end
        local intended = game.create_inventory(1)
        intended.insert{name='spoilage',count=200}
        state.reward_overflow['spoilage|normal'] = intended
        storage.reward_spoilage_test = {checks={},phase='legacy'}
    end)
    Event.on_nth_tick(30,function()
        if game.tick<10020 then return end
        local a = storage.reward_spoilage_test
        if a.done then return end
        local state = Expanse.test_state(target)
        -- MTS finishes copying its surface after on_init. Place the receiver afterwards.
        if not a.pad then
            a.pad = create_pad(state)
            a.ground = a.pad.surface.count_entities_filtered{type='item-entity'}
        end
        local src, pad = source(state), a.pad
        local dst = pad.get_inventory(defines.inventory.cargo_landing_pad_main)
        local point = pad.get_logistic_point(defines.logistic_member_index.cargo_landing_pad_requester)
        local function check(name, ok) assert(ok,name);a.checks[name]=true end
        local function incoming(name,quality)
            local n = 0
            for _,item in pairs(point.targeted_items_deliver) do
                if item.name==name and item.quality==(quality or 'normal') then n=n+item.count end
            end
            return n
        end
        local function buffer(item) return assert(state.reward_overflow[item]) end
        if a.phase=='legacy' then
            check('loaded_persisted_legacy_buffers',loaded)
            Missions.deliver_goods(state)
            check('legacy_fruit_waste_cleared',buffer('yumako|normal').is_empty() and buffer('jellynut|normal').is_empty())
            check('legacy_quality_waste_cleared',buffer('yumako|rare').is_empty())
            check('intentional_spoilage_preserved',buffer('spoilage|normal').get_item_count('spoilage')==200 and src.get_item_count('spoilage')==50)
            state.space_production = {['yumako|normal']=4,['jellynut|normal']=4,['yumako|rare']=7,['pentapod-egg|normal']=1}
            for attempt=1,25 do
                Missions.produce_space_goods(state)
                assert(buffer('yumako|normal').get_item_count('yumako')==4)
                assert(buffer('jellynut|normal').get_item_count('jellynut')==4)
                assert(buffer('yumako|rare').get_item_count{name='yumako',quality='rare'}==7)
                for _,key in ipairs({'yumako|normal','jellynut|normal','yumako|rare'}) do
                    buffer(key)[1].spoil_tick=game.tick-1
                end
            end
            check('repeated_spoilage_never_jams_production',true)
            for _=1,200 do Missions.produce_space_goods(state) end
            check('buffers_remain_bounded',#buffer('yumako|normal')==1 and buffer('yumako|normal').get_item_count('yumako')==50 and #buffer('jellynut|normal')==1)
            check('no_waste_pending_backlog',not next(state.pending_space_rewards or {}))
            Missions.deliver_goods(state)
            check('disabled_requests_still_pause',#point.targeted_items_deliver==0)
            state.space_production = {}
            -- Let engine time cross the old expiry. Only hidden rewards may be refreshed.
            src[2].set_stack{name='yumako',count=1};src[2].spoil_tick=game.tick+120
            buffer('yumako|normal')[1].spoil_tick=game.tick+120
            buffer('jellynut|normal')[1].spoil_tick=game.tick+120
            a.eggs=buffer('pentapod-egg|normal').get_item_count('pentapod-egg')
            buffer('pentapod-egg|normal')[1].spoil_tick=game.tick+120
            dst.insert{name='yumako',count=10};dst.find_item_stack('yumako').spoil_tick=game.tick+120
            a.external=game.create_inventory(1);a.external.insert{name='yumako',count=2};a.external[1].spoil_tick=game.tick+120
            a.phase='freshness';a.at=game.tick+180
        elseif a.phase=='freshness' and game.tick>=a.at then
            check('shared_hub_rewards_stay_fresh',src.get_item_count('yumako')==1 and src[2].spoil_percent<0.001)
            check('overflow_rewards_stay_fresh',buffer('yumako|normal').get_item_count('yumako')==50 and buffer('jellynut|normal').get_item_count('jellynut')==50)
            check('staged_eggs_do_not_hatch',buffer('pentapod-egg|normal').get_item_count('pentapod-egg')==a.eggs)
            check('landing_pad_spoils_normally',dst.get_item_count('spoilage')==10 and dst.get_item_count('yumako')==0)
            check('other_inventory_spoils_normally',a.external.get_item_count('spoilage')==2)
            a.external.destroy();a.external=nil
            check('delivered_waste_not_auto_deleted',dst.get_item_count('spoilage')==10)
            src[2].set_stack{name='metallic-asteroid-chunk',count=1}
            dst.clear();dst.insert{name='metallic-asteroid-chunk',count=100000}
            point.enabled=true;Missions.deliver_goods(state)
            check('full_pad_still_retains_rewards',#point.targeted_items_deliver==0 and buffer('yumako|normal').get_item_count('yumako')==50)
            for i=1,4 do dst[i].clear() end
            Missions.deliver_goods(state)
            check('clearing_pad_resumes_fruit_dispatch',incoming('yumako')==50 and incoming('jellynut')==50)
            check('quality_request_is_exact',incoming('yumako','rare')==7 and buffer('yumako|rare').get_item_count{name='yumako',quality='rare'}==43)
            check('zero_spoilage_request_respected',incoming('spoilage')==0)
            a.phase='arrival';a.at=game.tick+3600
        elseif a.phase=='arrival' and game.tick>=a.at then
            check('recovered_yumako_really_arrives',dst.get_item_count{name='yumako',quality='normal'}==50)
            check('recovered_jellynut_really_arrives',dst.get_item_count('jellynut')==50)
            check('quality_arrives_without_duplicates',dst.get_item_count{name='yumako',quality='rare'}==7 and incoming('yumako','rare')==0)
            check('received_fruit_ages_normally',dst.find_item_stack('jellynut').spoil_percent>0.001)
            check('spoilage_rewards_still_retained',buffer('spoilage|normal').get_item_count('spoilage')==200 and src.get_item_count('spoilage')==50)
            -- Intentional spoilage remains requestable after obsolete fruit waste is removed.
            dst.clear()
            point.get_section(1).set_slot(3,{value={type='item',name='spoilage',quality='normal',comparator='='},min=250})
            Missions.deliver_goods(state)
            check('intentional_spoilage_dispatches_on_request',incoming('spoilage')==250)
            a.phase='finish';a.at=game.tick+3600
        elseif a.phase=='finish' and game.tick>=a.at then
            check('intentional_spoilage_really_arrives',dst.get_item_count('spoilage')==250)
            check('no_ground_spills',pad.surface.count_entities_filtered{type='item-entity'}==a.ground)
            local old = state.reward_overflow
            Missions.clear_reward_overflow(state)
            for _,inv in pairs(old) do assert(not inv.valid) end
            check('reset_cleans_all_overflow_inventories',not state.reward_overflow)
            a.done=true
            helpers.write_file('cargo-result.json',helpers.table_to_json(a.checks))
        end
    end)
end
return Public
