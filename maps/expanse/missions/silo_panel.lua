-- Side panel on a mission silo's own window: which mission this is, what the
-- step still needs and how much of it the cargo chest already holds, how full
-- the rocket is, the launch rule in one sentence, a button that sends the
-- rocket with what is aboard, and the cargo chest itself.
local Model = require 'maps.expanse.missions.model'
local Ships = require 'maps.expanse.missions.ships'
local W = require 'maps.expanse.widgets'

local Public = { FRAME = 'expanse_missions_silo_panel' }

local WIDTH = 330
-- Six slots fit the panel's width, with or without a scroll bar beside them.
local SLOTS_PER_ROW = 6
-- Four rows of the chest show at once; the rest scrolls.
local CHEST_HEIGHT = 168
-- Fading an icon came with 2.1.25; older 2.1 builds show both numbers unfaded.
local CAN_FADE = helpers.compare_versions(script.active_mods.base, '2.1.25') >= 0

local function silo_data(state, silo)
    local data = state.rocket_silos and state.rocket_silos[silo.unit_number]
    return data and data.entity == silo and data or nil
end

local function rocket_standing(silo)
    return silo.rocket_silo_status == defines.rocket_silo_status.rocket_ready
end

local function ready_to_launch(silo, weight)
    return weight > 0 and rocket_standing(silo)
end

local function sorted_keys(counts)
    local keys = {}
    for key in pairs(counts) do keys[#keys + 1] = key end
    table.sort(keys)
    return keys
end

local function chest_inventory(data)
    local chest = data.cargo_chest
    return chest and chest.valid and chest.get_inventory(defines.inventory.chest) or nil
end

-- What decides which elements the panel has. Everything else is a number or a
-- caption and is written into the open panel, so it never flickers and a
-- player moving items through the chest slots is not interrupted.
local function layout_key(state, data, stage)
    local chest = data.cargo_chest
    return table.concat({
        data.entity.unit_number, chest and chest.valid and chest.unit_number or 0,
        stage.status, stage.step, tostring(rocket_standing(data.entity)), Ships.launch_weight(state),
        table.concat(sorted_keys(Model.outstanding(state, data.tier)), ';'),
    }, '/')
end

-- Bottom number: still to launch. Top number: already in the cargo chest. An
-- item the chest has none of is drawn faded, the game's look for "not here yet".
local function fill_slot(slot, left, in_chest)
    slot.number = left
    slot.secondary_number = in_chest
    if CAN_FADE then slot.opacity = in_chest > 0 and 1 or 0.5 end
end

local function fill_needed(grid, outstanding, chest)
    for key, left in pairs(outstanding) do
        local name, quality = Model.split_key(key)
        fill_slot(grid[key], left, chest and chest.get_item_count({ name = name, quality = quality }) or 0)
    end
end

local function needed_grid(parent, outstanding, chest)
    local keys = sorted_keys(outstanding)
    if #keys == 0 then
        W.label(parent, { 'expanse-missions.panel_all_aboard' }, nil, W.GREEN)
        return
    end
    W.label(parent, { 'expanse-missions.panel_needed' }, 'default-semibold', W.GREY).style.top_margin = 4
    local grid = parent.add { type = 'table', name = 'needed', column_count = SLOTS_PER_ROW }
    for _, key in ipairs(keys) do
        local name, quality = Model.split_key(key)
        W.item_slot(grid, name, quality, nil, key)
    end
    fill_needed(grid, outstanding, chest)
    W.label(parent, { 'expanse-missions.panel_legend' }, nil, W.GREY)
end

local function fill_cargo(inner, weight, ready)
    if inner.cargo then
        inner.cargo.caption = { 'expanse-missions.panel_cargo', Ships.format_weight(weight), Ships.format_weight(Ships.ROCKET_WEIGHT) }
        inner.bar.value = math.min(weight / Ships.ROCKET_WEIGHT, 1)
        inner.bar.style.color = weight >= Ships.ROCKET_WEIGHT and W.GREEN or W.GOLD
    end
    inner.launch.enabled = ready
end

local function cargo_block(parent, silo, weight, ready, threshold)
    parent.add { type = 'line' }.style.top_margin = 6
    if rocket_standing(silo) then
        parent.add { type = 'label', name = 'cargo' }.style.font = 'default-bold'
        parent.add { type = 'progressbar', name = 'bar' }.style.horizontally_stretchable = true
    else
        -- While a rocket is being built or is leaving, the silo has no cargo
        -- hold to read; the cargo chest keeps collecting meanwhile.
        W.label(parent, { 'expanse-missions.panel_no_rocket' }, 'default-bold')
    end
    W.label(parent, { 'expanse-missions.panel_rule', Ships.format_weight(threshold) }, nil, W.GREY)
    local button = parent.add { type = 'button', name = 'launch', caption = { 'expanse-missions.panel_launch' }, style = 'confirm_button',
        tags = { [W.TAG] = 'launch', unit = silo.unit_number } }
    button.style.top_margin = 6
    fill_cargo(parent, weight, ready)
end

-- The cargo chest's own slots, live. A player at the silo can see what the
-- chest holds and move items in and out without walking over to it.
local function chest_block(parent, chest)
    if not chest then return end
    parent.add { type = 'line' }.style.top_margin = 6
    W.label(parent, { 'expanse-missions.panel_chest' }, 'default-bold')
    local pane = parent.add { type = 'scroll-pane', horizontal_scroll_policy = 'never' }
    pane.style.maximal_height = CHEST_HEIGHT
    local slots = pane.add { type = 'inventory', inventory = chest, slots_per_row = SLOTS_PER_ROW,
        handle_cursor_transfer = true, handle_cursor_split = true, tags = { [W.TAG] = 'chest_slots' } }
    slots.inventory = chest
end

-- Shift-click and control-click on a chest slot: the game reports them and the
-- mod carries them out, into the player's inventory, the way a real chest
-- window does. Plain clicks with an item in hand are handled by the element.
local QUICK_TRANSFERS = {
    [defines.inventory_actions.stack_transfer] = true,
    [defines.inventory_actions.stack_split] = true,
    [defines.inventory_actions.inventory_transfer] = true,
    [defines.inventory_actions.inventory_split] = true,
}

function Public.on_inventory_action(event)
    local element = event.element
    if not (element and element.valid and element.tags[W.TAG] == 'chest_slots' and QUICK_TRANSFERS[event.action]) then return end
    local player = game.get_player(event.player_index)
    local inventory = element.inventory
    if not (inventory and inventory.valid) then return end
    player.stack_transfers { index = event.slot, source_inventory = inventory, target = player, transfer_type = event.action }
end

local function build(player, state, silo, data, key)
    Public.close(player)
    local tier = data.tier
    local stage = Model.stage(state, tier)
    local frame = player.gui.relative.add { type = 'frame', name = Public.FRAME, direction = 'vertical',
        caption = { 'expanse-missions.panel_title', Ships.by_tier[tier].name },
        anchor = { gui = defines.relative_gui_type.rocket_silo_gui, position = defines.relative_gui_position.left },
        tags = { key = key } }
    frame.style.width = WIDTH
    local inner = frame.add { type = 'frame', name = 'inner', direction = 'vertical', style = 'inside_shallow_frame_with_padding' }
    if stage.status == 'locked' or stage.status == 'done' then
        W.label(inner, { 'expanse-missions.panel_' .. stage.status }, nil, W.GREY)
        return
    end
    local chest = chest_inventory(data)
    W.label(inner, { 'expanse-missions.step_of', stage.step, stage.steps }, 'default-bold')
    needed_grid(inner, Model.outstanding(state, tier), chest)
    local weight = Model.inventory_weight(Model.rocket_inventory(silo))
    cargo_block(inner, silo, weight, ready_to_launch(silo, weight), Ships.launch_weight(state))
    chest_block(inner, chest)
end

-- Writes the current numbers into a panel whose layout still fits.
local function update(frame, state, silo, data)
    local inner = frame.inner
    if not (inner and inner.launch) then return end
    if inner.needed then fill_needed(inner.needed, Model.outstanding(state, data.tier), chest_inventory(data)) end
    local weight = Model.inventory_weight(Model.rocket_inventory(silo))
    fill_cargo(inner, weight, ready_to_launch(silo, weight))
end

function Public.close(player)
    local frame = player.gui.relative[Public.FRAME]
    if frame then frame.destroy() end
end

-- Shows the panel for a mission silo and removes it for any other entity.
function Public.show(player, state, silo)
    local data = silo and silo.valid and silo.type == 'rocket-silo' and state and silo_data(state, silo)
    if not data then
        Public.close(player)
        return
    end
    local stage = Model.stage(state, data.tier)
    local key = layout_key(state, data, stage)
    local frame = player.gui.relative[Public.FRAME]
    if frame and frame.tags.key == key then
        update(frame, state, silo, data)
    else
        build(player, state, silo, data, key)
    end
end

-- Rocket and chest contents change without an event, so open panels are checked
-- once a second from the mission tick. Players with no silo open cost one
-- comparison.
function Public.refresh_open(state, players)
    for _, player in pairs(players) do
        local opened = player.opened_gui_type == defines.gui_type.entity and player.opened
        if opened and opened.valid and opened.type == 'rocket-silo' then
            Public.show(player, state, opened)
        end
    end
end

return Public
