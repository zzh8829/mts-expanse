-- Opens and operates the mod's windows with a real player: the mission board,
-- the silo side panel and the reset dialog. Loaded only into disposable test
-- profiles by scripts/test-windows.py, which runs the game in test mode
-- (Factorio 2.1.24 or newer), the one headless mode that has a player.
--
-- Clicks are sent through the mod's own event dispatcher, so every handler runs
-- exactly as it does for a mouse click.
local Event = require 'utils.event'
local Data = require 'maps.expanse.mission_data'
local Functions = require 'maps.expanse.functions'
local Model = require 'maps.expanse.missions.model'
local Board = require 'maps.expanse.missions.board'
local SiloPanel = require 'maps.expanse.missions.silo_panel'
local Detail = require 'maps.expanse.missions.board_detail'
local Tooltips = require 'maps.expanse.missions.tooltips'
local ForfeitDialog = require 'maps.expanse.forfeit_dialog'
local W = require 'maps.expanse.widgets'
local Public = {}

local TIER, LEVEL = 4, 2
local START = 120
local FORFEIT_TAG = 'expanse_forfeit'

local function dispatch(event_id, fields)
    fields.name, fields.tick = event_id, game.tick
    script.get_event_handler(event_id)(fields)
end

local function click(element, button, control)
    dispatch(defines.events.on_gui_click, { player_index = element.player_index, element = element,
        button = button or defines.mouse_button_type.left, alt = false, control = control or false, shift = false, cursor_display_location = { x = 0, y = 0 } })
end

local function type_text(field, text)
    field.text = text
    dispatch(defines.events.on_gui_text_changed, { player_index = field.player_index, element = field, text = text })
end

-- First element under root for which test(element) is true, depth first.
local function find(root, test)
    if test(root) then return root end
    for _, child in pairs(root.children) do
        local found = find(child, test)
        if found then return found end
    end
    return nil
end

local function tagged(key, value, extra)
    return function(element)
        local tags = element.tags
        return tags[key] == value and (not extra or tags[extra[1]] == extra[2])
    end
end

local function build_silo(state, surface, force)
    surface.request_to_generate_chunks({ 50, 50 }, 2)
    surface.force_generate_chunk_requests()
    local tiles = {}
    for x = 30, 70 do for y = 30, 70 do tiles[#tiles + 1] = { name = 'grass-1', position = { x, y } } end end
    surface.set_tiles(tiles)
    for _, entity in pairs(surface.find_entities_filtered { area = { { 30, 30 }, { 70, 70 } } }) do
        if entity.type ~= 'character' then entity.destroy() end
    end
    local silo = assert(surface.create_entity { name = 'rocket-silo', position = { 50, 50 }, force = force })
    silo.minable_flag = false
    silo.destructible = false
    state.rocket_silos[silo.unit_number] = { entity = silo, tier = TIER }
    return silo
end

function Public.install(Expanse)
    local function check(name, ok)
        local test = storage.windows_test
        test.checks[name] = ok and true or false
        if not ok then log('WINDOWS_TEST FAIL ' .. name) end
    end

    local function state_and_player()
        return Expanse.test_state('player'), game.players[1]
    end

    -- One mission in each state the board can show.
    local function setup()
        local state, player = state_and_player()
        storage.windows_test = { checks = {} }
        check('test_mode_has_a_connected_player', player and player.connected)
        local surface = game.surfaces[state.active_surface_index]
        storage.windows_test.silo = build_silo(state, surface, player.force)
        -- A character opens a machine only within reach.
        player.teleport({ 43, 50 }, surface)
        state.missions[TIER] = { level = LEVEL, delivered = {} }
        state.missions[5] = { level = 1, delivered = {} }
        state.missions[6] = { level = 0, delivered = {} }
        state.missions[7] = { level = Model.step_count(7) + 1, delivered = {} }
    end

    local function board()
        local state, player = state_and_player()
        local silos = state.rocket_silos
        state.rocket_silos = {}
        Board.open(player, state)
        check('board_defaults_to_first_unfound_mission', player.gui.screen[Board.FRAME].tags.selected == TIER)
        Board.close(player)
        state.rocket_silos = silos
        Board.open(player, state)
        local frame = player.gui.screen[Board.FRAME]
        check('board_opens_as_the_players_window', frame and player.opened == frame)
        local expected = { [TIER] = 'active', [5] = 'nosilo', [6] = 'locked', [7] = 'done' }
        for tier, status in pairs(expected) do
            check('board_state_' .. status, Model.stage(state, tier).status == status)
        end
        -- Entry 0 is "What you receive"; the others are the seven missions.
        for _, entry in ipairs({ 0, 4, 5, 6, 7, 8, 9, 10 }) do
            click(find(frame, tagged(W.TAG, 'select', { 'entry', entry })))
            check('board_shows_entry_' .. entry, frame.valid and frame.tags.selected == entry and #frame.body.children == 2)
        end
        -- The longest step of all missions still leaves the window on the screen.
        do
            local long_tier, long_level, most = TIER, LEVEL, 0
            for tier, levels in pairs(Data.costs) do
                for level = 1, Model.step_count(tier) do
                    local kinds = 0
                    for _ in pairs(levels[level]) do kinds = kinds + 1 end
                    if kinds > most then long_tier, long_level, most = tier, level, kinds end
                end
            end
            local saved = state.missions[long_tier]
            state.missions[long_tier] = { level = long_level, delivered = {} }
            click(find(frame, tagged(W.TAG, 'select', { 'entry', long_tier })))
            check('longest_step_scrolls_inside_the_window', find(frame, function(e) return e.type == 'scroll-pane' end) ~= nil and most > 15)
            state.missions[long_tier] = saved
        end
        click(find(frame, tagged(W.TAG, 'select', { 'entry', TIER })))
        click(find(frame, tagged(W.TAG, 'pin_silo')))
        local pins = player.get_pins()
        check('pin_button_pins_the_silo', #pins == 1 and pins[1].label == 'Atlas mission silo')
        local button = find(frame, tagged(W.TAG, 'pin_silo'))
        check('pin_button_offers_removal', button.caption[1] == 'expanse-missions.unpin_silo')
        click(button)
        check('pin_button_removes_the_pin', #player.get_pins() == 0)
        click(find(frame, tagged(W.TAG, 'close')))
        check('board_close_button_closes', player.gui.screen[Board.FRAME] == nil)
        Board.open(player, state)
        player.opened = nil
    end

    local function reward_row(frame, name, quality)
        local rows = find(frame, function(e) return e.type == 'table' end)
        if not rows then return end
        local cells = rows.children
        for i = 5, #cells, 4 do
            if cells[i].sprite == 'item/' .. name and cells[i].quality.name == quality then
                return cells[i + 2].caption, cells[i + 3].caption
            end
        end
    end

    -- Both support modes can hold more of an item in overflow than in the hub.
    local function reward_storage()
        local state, player = state_and_player()
        local overflow = game.create_inventory(1)
        overflow.insert { name = 'iron-plate', count = 6 }
        local platform = player.force.create_space_platform { name = 'Board probe', planet = 'nauvis', starter_pack = 'space-platform-starter-pack' }
        platform.apply_starter_pack(true)
        local frame = player.gui.screen.add { type = 'frame' }
        for _, platform_mode in ipairs({ false, true }) do
            local inventory = platform_mode and platform.hub.get_inventory(defines.inventory.hub_main)
                or state.nonspace_pad.get_inventory(defines.inventory.cargo_landing_pad_main)
            local normal_count = platform_mode and 3 or 4
            inventory.insert { name = 'iron-plate', count = normal_count }
            inventory.insert { name = 'iron-plate', quality = 'rare', count = 2 }
            local view = { use_space_platform = platform_mode, space_platform = platform, nonspace_pad = state.nonspace_pad,
                reward_overflow = { ['iron-plate|normal'] = overflow } }
            local mode = platform_mode and 'platform' or 'surface'
            Detail.receive(frame, view)
            local rate, count = reward_row(frame, 'iron-plate', 'rare')
            check('board_lists_stored_only_goods_before_production_' .. mode, rate == '—' and count == '2')
            frame.clear()
            view.space_production = { ['iron-plate|normal'] = 1, ['coal|normal'] = 2 }
            Detail.receive(frame, view)
            rate, count = reward_row(frame, 'iron-plate', 'normal')
            check('board_counts_waiting_goods_' .. mode, rate == '+1' and count == tostring(normal_count + 6))
            rate, count = reward_row(frame, 'iron-plate', 'rare')
            check('board_lists_stored_only_quality_' .. mode, rate == '—' and count == '2')
            rate, count = reward_row(frame, 'coal', 'normal')
            check('board_lists_recurring_goods_with_no_stock_' .. mode, rate == '+2' and count == '0')
            frame.clear()
        end
        frame.destroy()
        platform.destroy()
        overflow.destroy()
    end

    local function pad_tooltip()
        local state, player = state_and_player()
        local surface = game.surfaces[state.active_surface_index]
        -- The tooltip is an entity field. Use separate disposable entities to
        -- exercise replacing the target while the team's production is unchanged.
        local function target(x)
            return surface.create_entity { name = 'steel-chest', position = { x, 54 }, force = player.force }
        end
        local pad = target(54)
        local view = { landing_pad = pad, space_production = {} }
        for _, name in ipairs({ 'iron-plate', 'copper-plate', 'steel-plate', 'coal', 'stone', 'copper-ore', 'iron-ore', 'battery', 'uranium-ore' }) do
            view.space_production[name .. '|normal'] = 2
        end
        Tooltips.pad(view)
        view.space_production['wood|normal'] = 4
        Tooltips.pad(view)
        local field = pad.get_tooltip_field(1)
        check('pad_tooltip_updates_hidden_item_count', field.value[2][3] == '2')
        pad.destroy()
        view.landing_pad = target(55)
        Tooltips.pad(view)
        check('new_pad_receives_unchanged_tooltip', view.landing_pad.get_tooltip_field(1) ~= nil)
        view.landing_pad.destroy()
    end

    local function open_silo()
        local _, player = state_and_player()
        check('escape_closes_the_board', player.gui.screen[Board.FRAME] == nil)
        settings.global['mts-expanse-rocket-launch-weight-threshold'] = { value = 500000 }
        player.opened = storage.windows_test.silo
    end

    local function silo_panel()
        local state, player = state_and_player()
        local test = storage.windows_test
        local data = state.rocket_silos[test.silo.unit_number]
        local frame = player.gui.relative[SiloPanel.FRAME]
        check('silo_panel_opens_with_the_silo', frame ~= nil)
        if not frame then return end
        local rule = find(frame, function(e)
            return e.type == 'label' and type(e.caption) == 'table' and e.caption[1] == 'expanse-missions.panel_rule'
        end)
        check('panel_reports_configured_launch_weight', rule and rule.caption[2] == '500 kg')
        local needed = frame.inner.needed
        local kinds = 0
        for _ in pairs(Data.costs[TIER][LEVEL]) do kinds = kinds + 1 end
        check('silo_panel_lists_every_needed_item', needed and #needed.children == kinds)
        local slot = needed.children[1]
        check('slot_shows_still_to_launch_and_in_chest', slot.number > 0 and slot.secondary_number == 0)
        check('launch_is_off_without_a_rocket', frame.inner.launch.enabled == false)
        check('silo_panel_shows_the_cargo_chest', find(frame, function(e) return e.type == 'inventory' end) ~= nil)
        local name, quality = Model.split_key(slot.name)
        check('cargo_chest_takes_the_item', data.cargo_chest.insert { name = name, quality = quality, count = 3 } == 3)
        test.slot = slot
    end

    local function silo_panel_updates()
        local state, player = state_and_player()
        local test = storage.windows_test
        local slot = test.slot
        -- Same element as before: the number was written into the open panel.
        check('slot_number_follows_the_chest_in_place', slot and slot.valid and slot.secondary_number == 3)
        -- Shift-click on the chest slot inside the panel: the stack goes to the player.
        local name = Model.split_key(slot.name)
        local slots = find(player.gui.relative[SiloPanel.FRAME], function(e) return e.type == 'inventory' end)
        local before = player.get_main_inventory().get_item_count(name)
        dispatch(defines.events.on_gui_inventory_action, { player_index = player.index, element = slots, slot = 1,
            action = defines.inventory_actions.stack_transfer, button = defines.mouse_button_type.left, alt = false, control = false, shift = true })
        local chest = state.rocket_silos[test.silo.unit_number].cargo_chest
        check('shift_click_moves_the_stack_to_the_player', chest.get_item_count(name) == 0 and player.get_main_inventory().get_item_count(name) == before + 3)
        chest.destroy()
    end

    local function replaced_chest()
        local state, player = state_and_player()
        local data = state.rocket_silos[storage.windows_test.silo.unit_number]
        local slots = find(player.gui.relative[SiloPanel.FRAME], function(e) return e.type == 'inventory' end)
        check('panel_rebinds_to_recreated_chest', slots.inventory == data.cargo_chest.get_inventory(defines.inventory.chest))
        check('recreated_chest_gets_its_tooltip', data.cargo_chest.get_tooltip_field(1) ~= nil)
        player.opened = nil
    end

    local function reset_dialog()
        local _, player = state_and_player()
        check('closing_the_silo_removes_its_panel', player.gui.relative[SiloPanel.FRAME] == nil)
        ForfeitDialog.open(player)
        local frame = player.gui.screen[ForfeitDialog.FRAME]
        check('reset_dialog_opens', frame ~= nil)
        local confirm, field = frame.buttons.confirm, frame.content.confirm_text
        check('reset_button_starts_disabled', confirm.enabled == false)
        type_text(field, 'yes')
        check('reset_button_stays_off_for_another_word', confirm.enabled == false)
        type_text(field, 'reset')
        check('reset_button_works_after_the_word', confirm.enabled == true)
        click(find(frame, tagged(FORFEIT_TAG, 'cancel')))
        check('keep_playing_closes_the_dialog', player.gui.screen[ForfeitDialog.FRAME] == nil)
    end

    local function stash_button(player)
        return find(player.gui.top, function(e) return e.type == 'sprite-button' and e.sprite == 'item/wooden-chest' end)
    end

    local function stash()
        local state, player = state_and_player()
        local surface = game.surfaces[state.active_surface_index]
        player.teleport({ 65, 50 }, surface)
        local target = surface.create_entity { name = 'steel-chest', position = { 66, 50 }, force = player.force }
        local inventory = player.get_main_inventory()
        inventory.clear()
        inventory.insert { name = 'iron-plate', count = 35 }
        inventory.insert { name = 'stone', count = 4 }
        inventory.insert { name = 'power-armor' }
        local armor = inventory.find_item_stack('power-armor')
        armor.grid.put { name = 'battery-equipment' }
        player.set_quick_bar_slot(1, 1, 'stone')
        player.set_quick_bar_slot(10, player.quick_bar_width, armor)
        local slot = player.get_quick_bar_slot(10, player.quick_bar_width)
        assert(slot.type == 'item')
        inventory.insert { name = 'power-armor' }
        click(assert(stash_button(player)))
        check('stash_keeps_quickbar_item', inventory.get_item_count('power-armor') == 1 and inventory.find_item_stack('power-armor').item == slot.item)
        check('stash_moves_other_armor', target.get_item_count('power-armor') == 1)
        check('stash_keeps_quickbar_filter', inventory.get_item_count('stone') == 4)
        check('stash_moves_full_stack', target.get_item_count('iron-plate') == 35 and inventory.get_item_count('iron-plate') == 0)
        target.destroy()
    end

    local function stash_furnaces()
        local state, player = state_and_player()
        local surface = game.surfaces[state.active_surface_index]
        local inventory = player.get_main_inventory()
        inventory.clear()
        inventory.insert { name = 'coal', quality = 'rare', count = 3 }
        inventory.insert { name = 'coal', count = 6 }
        local furnace = surface.create_entity { name = 'stone-furnace', position = { 66, 50 }, force = player.force }
        click(assert(stash_button(player)), defines.mouse_button_type.right, true)
        for _, spec in ipairs({ { 'normal', 6 }, { 'rare', 3 } }) do
            local item = { name = 'coal', quality = spec[1] }
            check('stash_conserves_furnace_fuel_' .. spec[1], inventory.get_item_count(item) + furnace.get_item_count(item) == spec[2])
        end
        check('stash_supplies_furnace_fuel', not furnace.get_fuel_inventory().is_empty())
        furnace.destroy()
    end

    local function legacy_counts()
        local state = state_and_player()
        local unit, container = next(state.containers)
        Functions.set_container(state, container.entity, container.left_top, true)
        container = state.containers[unit]
        local price = container.price[1]
        local renders = price.render
        renders[4].destroy()
        renders[4] = nil
        for i = 1, 3 do renders[i].only_in_alt_mode = true end
        Functions.set_container(state, container.entity, container.left_top, false)
        check('legacy_count_aligns_with_its_icon', renders[4] and renders[4].target.offset.x == renders[2].target.offset.x and not renders[2].only_in_alt_mode)
    end

    local function finish()
        local test = storage.windows_test
        local passed = true
        for _, ok in pairs(test.checks) do passed = passed and ok end
        helpers.write_file('windows-result.json', helpers.table_to_json(test.checks), false)
        log('WINDOWS_TEST DONE ' .. (passed and 'pass' or 'fail'))
        script.finish_test(passed)
    end

    -- The cargo station appears with the first mission tick after the silo
    -- exists, and the open panel refreshes once a second, so those steps wait.
    local steps = {
        [START] = setup,
        [START + 90] = board,
        [START + 91] = reward_storage,
        [START + 92] = open_silo,
        [START + 94] = silo_panel,
        [START + 100] = pad_tooltip,
        [START + 220] = silo_panel_updates,
        [START + 300] = replaced_chest,
        [START + 302] = reset_dialog,
        [START + 325] = stash,
        [START + 355] = stash_furnaces,
        [START + 356] = legacy_counts,
        [START + 357] = finish,
    }
    Event.add(defines.events.on_tick, function()
        local step = steps[game.tick]
        if step then step() end
    end)
end

return Public
