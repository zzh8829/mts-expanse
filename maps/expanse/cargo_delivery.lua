-- Mission rewards use scripted pods, so vanilla request/capacity checks must be
-- applied before launching them. All reservations below are local to one tick;
-- Factorio owns the persistent incoming-cargo accounting, including across saves.
local Public = {}

local function key(name, quality)
    return name .. '|' .. (quality or 'normal')
end

local function request_limits(pad, point)
    if not point.enabled then return {} end
    local configured = false
    for _, section in pairs(point.sections) do
        -- Inactive sections and zero multipliers are still configured requests.
        -- They must not turn into an unrestricted delivery when switched off.
        for _, filter in pairs(section.filters) do
            if filter.value and (filter.value.type or 'item') == 'item' then
                configured = true
                break
            end
        end
    end
    local control = pad.get_control_behavior()
    if control and control.circuit_exclusive_mode_of_operation == defines.control_behavior.cargo_landing_pad.exclusive_mode.set_requests then
        configured = true -- A zero circuit signal means request nothing.
    end
    local limits = {}
    for _, filter in pairs(point.filters or {}) do
        if filter.name and (filter.type or 'item') == 'item' then
            configured = true
            -- Positive logistic requests are exact-quality filters in Factorio.
            local id = key(filter.name, filter.quality)
            limits[id] = math.max(0, filter.count or 0)
        end
    end
    return configured and limits or nil
end

function Public.send(source, launcher, pad)
    local destination = pad.get_inventory(defines.inventory.cargo_landing_pad_main)
    local point = pad.get_logistic_point(defines.logistic_member_index.cargo_landing_pad_requester)
    if not (destination and point) then return end
    local limits = request_limits(pad, point)
    if limits and not next(limits) then return end
    local slots = #destination
    if destination.supports_bar() then slots = math.min(slots, destination.get_bar() - 1) end
    if slots == 0 then return end

    -- Copy the usable slots into a temporary inventory. Reserving incoming and
    -- newly planned stacks here accounts for different items sharing free slots.
    local capacity = game.create_inventory(slots)
    for i = 1, slots do capacity[i].set_stack(destination[i]) end
    local stock = {}
    for _, item in pairs(destination.get_contents()) do stock[key(item.name, item.quality)] = item.count end
    for _, item in pairs(point.targeted_items_deliver) do
        local id = key(item.name, item.quality)
        stock[id] = (stock[id] or 0) + item.count
        if capacity.insert(item) < item.count then
            capacity.destroy()
            return -- Existing incoming cargo already uses all remaining space.
        end
    end
    local stage = game.create_inventory(1)
    local budget = math.min(12, math.max(1, math.ceil(source.get_item_count() / 200)))
    for _ = 1, budget do
        local pod, payload
        -- Scan past unrequested stacks: they must not block a requested item
        -- later in the source inventory, even beyond the first twenty slots.
        for i = 1, #source do
            local stack = source[i]
            if stack.valid_for_read then
                local id = key(stack.name, stack.quality.name)
                local need = limits and math.max(0, (limits[id] or 0) - (stock[id] or 0)) or stack.count
                local item = {name = stack.name, quality = stack.quality.name}
                local count = math.min(stack.count, need, capacity.get_insertable_count(item), destination.get_insertable_count(item))
                if count > 0 then
                    if not pod then
                        pod = launcher.create_cargo_pod()
                        if not (pod and pod.valid) then break end
                        payload = pod.get_inventory(defines.inventory.cargo_unit)
                    end
                    stage[1].set_stack(stack)
                    stage[1].count = count
                    -- Reserve the actual stack, including metadata. A partial
                    -- pod insertion may leave conservative unused reservations
                    -- until the next attempt, but can never overbook the pad.
                    local reserved = capacity.insert(stage[1])
                    local inserted = 0
                    if reserved > 0 then
                        stage[1].count = reserved
                        inserted = payload.insert(stage[1])
                    end
                    if inserted > 0 then
                        stock[id] = (stock[id] or 0) + inserted
                        stack.count = stack.count - inserted
                    end
                end
            end
        end
        if not (pod and pod.valid) then break end
        if payload.is_empty() then pod.destroy(); break end
        pod.cargo_pod_destination = {type = defines.cargo_destination.station, station = pad}
    end
    stage.destroy()
    capacity.destroy()
end

return Public
