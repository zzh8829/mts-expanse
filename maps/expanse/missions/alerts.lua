-- Team alerts for mission logistics that are stuck. An alert sits in the alert
-- bar beside the quick bar and opens the map at its entity when clicked.
--
-- A custom alert fades within about twenty seconds unless it is raised again
-- (measured on 2.1.25), so each one is re-raised from the once-a-second mission
-- tick for as long as its condition holds and disappears by itself after. That
-- suits a standing problem; one-time news stays in chat.
local Model = require 'maps.expanse.missions.model'
local Ships = require 'maps.expanse.missions.ships'
local SpaceMissions = require 'maps.expanse.space_missions'
local HeldRewards = require 'maps.expanse.missions.held_rewards'

local Public = {}

local NO_POWER = {
    [defines.entity_status.no_power] = true,
    [defines.entity_status.not_plugged_in_electric_network] = true,
}

local function icon(item)
    return { type = 'item', name = item }
end

-- True when the step's cargo is waiting at the silo: in the chest or aboard.
local function cargo_waiting(state, data)
    local chest = data.cargo_chest.get_inventory(defines.inventory.chest)
    local rocket = Model.rocket_inventory(data.entity)
    for key in pairs(Model.current_costs(state, data.tier)) do
        local name, quality = Model.split_key(key)
        local item = { name = name, quality = quality }
        if chest.get_item_count(item) > 0 or (rocket and rocket.get_item_count(item) > 0) then return true end
    end
    return false
end

-- The team's robot networks on a surface that have logistic robots.
local function robot_networks(force, surface)
    local networks = {}
    for _, network in pairs(force.logistic_networks[surface.name] or {}) do
        if network.all_logistic_robots > 0 then networks[#networks + 1] = network end
    end
    return networks
end

-- True when robots hold something the chest still wants and cannot bring it,
-- because the chest stands outside every network. A team that feeds a chest by
-- hand, belt or train, or has nothing for it yet, is not bothered.
local function robots_cannot_reach(state, data, networks)
    local chest = data.cargo_chest
    if chest.logistic_network or #networks == 0 then return false end
    local inventory = chest.get_inventory(defines.inventory.chest)
    for key, count in pairs(Model.outstanding(state, data.tier)) do
        local name, quality = Model.split_key(key)
        local item = { name = name, quality = quality }
        if inventory.get_item_count(item) < count then
            for _, network in ipairs(networks) do
                if network.get_item_count(item) > 0 then return true end
            end
        end
    end
    return false
end

local function silo_alerts(state, force, data, networks)
    local silo, chest = data.entity, data.cargo_chest
    if not (silo and silo.valid and chest and chest.valid and Model.current_costs(state, data.tier)) then return end
    local ship = Ships.by_tier[data.tier].name
    if NO_POWER[silo.status] and cargo_waiting(state, data) then
        force.add_custom_alert(silo, icon('rocket-silo'), { 'expanse-missions.alert_no_power', ship }, true)
    end
    if robots_cannot_reach(state, data, networks) then
        force.add_custom_alert(chest, icon('requester-chest'), { 'expanse-missions.alert_no_network', ship }, true)
    end
end

-- Once a second per team, from the mission tick.
function Public.tick(state)
    local force = game.forces[state.force_name or 'player']
    -- Alerts reach connected players only, so an empty team costs nothing.
    if not (force and force.valid) or #force.connected_players == 0 then return end
    local pad = state.landing_pad
    if pad and pad.valid and SpaceMissions.rewards_blocked(state) then
        force.add_custom_alert(pad, icon('cargo-landing-pad'), { 'expanse-missions.alert_pad_full' }, true)
    end
    HeldRewards.tick(state, force)
    local networks
    for _, data in pairs(state.rocket_silos or {}) do
        if data.entity and data.entity.valid then
            networks = networks or robot_networks(force, data.entity.surface)
            silo_alerts(state, force, data, networks)
        end
    end
end

return Public
