-- Right-hand side of the mission board: one mission in full, or the list of
-- goods the team's ships send down.
local Model = require 'maps.expanse.missions.model'
local Pins = require 'maps.expanse.missions.pins'
local Ships = require 'maps.expanse.missions.ships'
local SpaceMissions = require 'maps.expanse.space_missions'
local Text = require 'maps.expanse.missions.text'
local W = require 'maps.expanse.widgets'

local Public = {}

local function status_line(model, state)
    local name = model.ship.name
    if model.status == 'done' then
        return { 'expanse-missions.status_done', name, Ships.gives(model.tier) }, W.GREEN
    elseif model.status == 'locked' then
        return { 'expanse-missions.status_locked', model.tech, prototypes.technology[model.tech].localised_name }, W.GREY
    elseif model.status == 'nosilo' then
        return { 'expanse-missions.status_nosilo', Ships.ring(state, model.tier) }, W.GOLD
    end
    local position = model.silo.position
    return { 'expanse-missions.status_active', math.floor(position.x), math.floor(position.y) }, nil
end

local function header(parent, model)
    local head = parent.add { type = 'flow', direction = 'horizontal' }
    head.style.vertical_align = 'center'
    head.style.horizontal_spacing = 10
    local icon = head.add { type = 'sprite', sprite = model.ship.icon }
    icon.style.size = 40
    icon.style.stretch_image_to_widget_size = true
    local titles = head.add { type = 'flow', direction = 'vertical' }
    titles.style.vertical_spacing = 0
    W.label(titles, model.ship.name, 'heading-1')
    W.label(titles, { 'expanse-missions.ship_line', Ships.role(model.tier), Ships.gives(model.tier) }, nil, W.GREY)
    W.pusher(head)
    local steps = head.add { type = 'flow', direction = 'vertical' }
    steps.style.horizontal_align = 'right'
    local caption = model.status == 'done' and { 'expanse-missions.steps_done', model.steps }
        or { 'expanse-missions.step_of', model.step, model.steps }
    W.label(steps, caption, 'default-bold')
    local bar = steps.add { type = 'progressbar', value = model.progress }
    bar.style.width = 160
    bar.style.color = W.GREEN
end

-- One row per item: icon, name, bar, delivered, what is left with its weight.
local function deliver_table(parent, model)
    local rows = parent.add { type = 'table', column_count = 5 }
    rows.style.horizontal_spacing = 12
    rows.style.vertical_spacing = 2
    W.column_headers(rows, { '', { 'expanse-missions.col_item' }, { 'expanse-missions.col_progress' },
        { 'expanse-missions.col_delivered' }, { 'expanse-missions.col_left' } })
    for _, item in ipairs(model.items) do
        local left = item.count - item.delivered
        local done = left <= 0
        W.item_slot(rows, item.name, item.quality)
        local name = W.label(rows, Text.item_name(item.name, item.quality), nil, done and W.GREY or nil)
        name.style.width = 220
        local bar = rows.add { type = 'progressbar', value = item.delivered / item.count }
        bar.style.width = 150
        bar.style.color = done and W.GREEN or W.GOLD
        local count = W.label(rows, done and { 'expanse-missions.count_done', item.count }
            or { 'expanse-missions.count_of', item.delivered, item.count }, nil, done and W.GREEN or nil)
        count.style.width = 90
        W.label(rows, done and '' or { 'expanse-missions.left_value', left, Ships.format_weight(left * item.weight) }, nil, W.GREY)
    end
end

function Public.mission(parent, state, tier)
    local model = Model.build(state, tier)
    header(parent, model)
    parent.add { type = 'line' }
    local text, color = status_line(model, state)
    W.label(parent, text, nil, color)
    if #model.items == 0 then return end

    W.heading(parent, { 'expanse-missions.deliver_heading', math.floor(model.fraction * 100), model.rockets })
    deliver_table(parent, model)
    W.heading(parent, { 'expanse-missions.reward_heading' })
    for _, line in ipairs(Text.reward_lines(state, model.rewards)) do W.label(parent, line) end
    W.heading(parent, { 'expanse-missions.how_heading' })
    W.label(parent, { 'expanse-missions.how_text' }, nil, W.GREY)
    if model.status == 'active' then
        local buttons = parent.add { type = 'flow', direction = 'horizontal' }
        buttons.style.top_margin = 6
        local pinned = Pins.is_pinned(Model.silo_data(state, tier), game.get_player(parent.player_index))
        buttons.add { type = 'button', caption = { pinned and 'expanse-missions.unpin_silo' or 'expanse-missions.pin_silo' },
            tags = { [W.TAG] = 'pin_silo', tier = tier } }
    end
end

local function waiting_in_orbit(state)
    local stored = {}
    for _, inventory in ipairs(SpaceMissions.reward_storage(state)) do
        for _, item in pairs(inventory.get_contents()) do
            local key = item.name .. '|' .. (item.quality or 'normal')
            stored[key] = (stored[key] or 0) + item.count
        end
    end
    return stored
end

function Public.receive(parent, state)
    W.label(parent, { 'expanse-missions.receive_heading' }, 'heading-1')
    parent.add { type = 'line' }
    local pad = state.landing_pad
    if pad and pad.valid then
        W.label(parent, { 'expanse-missions.receive_pad', math.floor(pad.position.x), math.floor(pad.position.y), Text.interval(state) })
    else
        W.label(parent, { 'expanse-missions.receive_nopad', Ships.ring(state, Ships.FIRST_TIER) }, nil, W.GOLD)
    end
    local production = state.space_production or {}
    local stored = waiting_in_orbit(state)
    local keys = {}
    for key in pairs(production) do keys[#keys + 1] = key end
    for key in pairs(stored) do
        if not production[key] then keys[#keys + 1] = key end
    end
    if #keys == 0 then
        W.label(parent, { 'expanse-missions.receive_none' }, nil, W.GREY)
        return
    end
    table.sort(keys)
    local rows = parent.add { type = 'table', column_count = 4 }
    rows.style.horizontal_spacing = 16
    rows.style.top_margin = 6
    W.column_headers(rows, { '', { 'expanse-missions.col_item' }, { 'expanse-missions.col_rate' }, { 'expanse-missions.col_waiting' } })
    for _, key in ipairs(keys) do
        local name, quality = Model.split_key(key)
        W.item_slot(rows, name, quality)
        W.label(rows, Text.item_name(name, quality)).style.width = 220
        W.label(rows, production[key] and '+' .. production[key] or '—')
        W.label(rows, tostring(stored[key] or 0))
    end
end

return Public
