-- The Space missions window: the seven ships and their state on the left, the
-- selected one in full on the right. No tabs; every state is spelled out.
local Model = require 'maps.expanse.missions.model'
local Ships = require 'maps.expanse.missions.ships'
local Detail = require 'maps.expanse.missions.board_detail'
local Pins = require 'maps.expanse.missions.pins'
local W = require 'maps.expanse.widgets'

local Public = { FRAME = 'expanse_missions_board' }

local WIDTH = 1010
local LIST_WIDTH = 250
local DETAIL_HEIGHT = 560
-- Entry 0 of the list is "What you receive"; the others are mission tiers.
local RECEIVE = 0

local function list_entry(list, caption, entry, selected)
    local button = list.add { type = 'button', caption = caption, style = entry == selected and 'button' or 'list_box_item',
        tags = { [W.TAG] = 'select', entry = entry } }
    button.style.horizontally_stretchable = true
    button.style.height = 40
    button.style.horizontal_align = 'left'
end

local function chip(stage)
    if stage.status == 'active' then
        return { 'expanse-missions.chip_active', stage.step, stage.steps }
    end
    return { 'expanse-missions.chip_' .. stage.status }
end

local function build_list(body, state, selected)
    local list = body.add { type = 'frame', direction = 'vertical', style = 'inside_deep_frame' }
    list.style.width = LIST_WIDTH
    list.style.vertically_stretchable = true
    list.style.padding = 4
    list_entry(list, { 'expanse-missions.receive_entry' }, RECEIVE, selected)
    for tier = Ships.FIRST_TIER, Ships.LAST_TIER do
        local ship = Ships.by_tier[tier]
        list_entry(list, { 'expanse-missions.list_entry', ship.icon, ship.name, chip(Model.stage(state, tier)) }, tier, selected)
    end
end

local function build_body(frame, state)
    local body = frame.body
    body.clear()
    local selected = frame.tags.selected
    build_list(body, state, selected)
    local frame_right = body.add { type = 'frame', direction = 'vertical', style = 'inside_shallow_frame_with_padding' }
    frame_right.style.horizontally_stretchable = true
    -- A late step lists more than twenty items. The page scrolls inside the
    -- window so the window, and the button at its end, stay on the screen.
    local detail = frame_right.add { type = 'scroll-pane', horizontal_scroll_policy = 'never', style = 'naked_scroll_pane' }
    detail.style.horizontally_stretchable = true
    detail.style.minimal_height = DETAIL_HEIGHT
    detail.style.maximal_height = DETAIL_HEIGHT
    if selected == RECEIVE then
        Detail.receive(detail, state)
    else
        Detail.mission(detail, state, selected)
    end
end

-- First mission a team can act on, so the window opens on something useful.
local function default_entry(state)
    local first_unfound
    for tier = Ships.FIRST_TIER, Ships.LAST_TIER do
        local status = Model.stage(state, tier).status
        if status == 'active' then return tier end
        if status == 'nosilo' and not first_unfound then first_unfound = tier end
    end
    return first_unfound or Ships.FIRST_TIER
end

function Public.is_open(player)
    return player.gui.screen[Public.FRAME] ~= nil
end

function Public.close(player)
    W.close(player, Public.FRAME)
end

function Public.open(player, state)
    local frame = W.window(player, Public.FRAME, { 'expanse-missions.title' }, WIDTH)
    local body = frame.add { type = 'flow', name = 'body', direction = 'horizontal' }
    body.style.horizontal_spacing = 12
    local tags = frame.tags
    tags.selected = default_entry(state)
    frame.tags = tags
    build_body(frame, state)
end

function Public.toggle(player, state)
    if Public.is_open(player) then
        Public.close(player)
    else
        Public.open(player, state)
    end
end

-- Redraws the window in place after a selection or a mission change.
function Public.refresh(player, state, entry)
    local frame = player.gui.screen[Public.FRAME]
    if not frame then return end
    if entry then
        local tags = frame.tags
        tags.selected = entry
        frame.tags = tags
    end
    build_body(frame, state)
end

-- Pins the mission's silo for this player, or takes the pin away again.
function Public.pin_silo(player, state, tier)
    local data = Model.silo_data(state, tier)
    if not data then return end
    Pins.toggle(data, player)
    Public.refresh(player, state)
end

return Public
