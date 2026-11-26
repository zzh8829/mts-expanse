-- Team chat lines about missions: one line per event, with the ship's name, the
-- reward in words and where to go next. Only the owning team sees them.
local MissionData = require 'maps.expanse.mission_data'
local Model = require 'maps.expanse.missions.model'
local Ships = require 'maps.expanse.missions.ships'
local Text = require 'maps.expanse.missions.text'
local Server = require 'utils.server'

local Public = {}

local function say(state, message)
    local force = game.forces[state.force_name or 'player'] or game.forces.player
    if force and force.valid then force.print(message) end
end

-- The Discord relay has no team context of its own, so every line names the team.
local function team_label(state)
    local force_name = state.force_name or 'player'
    local ok, label = pcall(remote.call, 'mts-v1', 'get_team_label', force_name)
    return ok and type(label) == 'string' and label or force_name
end

local function gps(entity)
    return { 'expanse.gps', math.floor(entity.position.x), math.floor(entity.position.y), entity.surface.name }
end

function Public.unlocked(state, tier)
    local ship = Ships.by_tier[tier]
    local data = Model.silo_data(state, tier)
    if data then
        say(state, { 'expanse-missions.chat_unlocked_found', ship.icon, ship.name, Ships.role(tier), gps(data.entity) })
    else
        say(state, { 'expanse-missions.chat_unlocked', ship.icon, ship.name, Ships.role(tier), Ships.ring(state, tier) })
    end
end

function Public.silo_found(state, tier, silo)
    local ship = Ships.by_tier[tier]
    local tech = prototypes.technology[MissionData.mission_unlocks[tier]]
    local mission = state.missions and state.missions[tier]
    if mission and mission.level == 0 and tech then
        say(state, { 'expanse-missions.chat_silo_found_locked', ship.name, gps(silo), tech.name, tech.localised_name })
    else
        say(state, { 'expanse-missions.chat_silo_found', ship.name, gps(silo) })
    end
end

function Public.pad_found(state, pad)
    say(state, { 'expanse-missions.chat_pad_found', gps(pad) })
end

-- names is the list of held rewards in words.
function Public.rewards_held(state, pad, names)
    say(state, { 'expanse-missions.chat_rewards_held', names, gps(pad) })
end

-- Called after a step's rewards are paid and the mission moved on.
function Public.step_done(state, tier, finished_step, rewards)
    local ship = Ships.by_tier[tier]
    local steps = Model.step_count(tier)
    local reward = Text.join(Text.reward_lines(state, rewards, true), ', ')
    if finished_step >= steps then
        say(state, { 'expanse-missions.chat_mission_done', ship.icon, ship.name, steps, reward, Ships.gives(tier) })
        Server.to_discord_embed({ 'expanse-missions.discord_mission_done', team_label(state), ship.name }, true)
        return
    end
    local next_step = Model.build(state, tier)
    say(state, { 'expanse-missions.chat_step_done', ship.icon, ship.name, finished_step, steps, reward, next_step.rockets })
    Server.to_discord_embed({ 'expanse-missions.discord_step_done', team_label(state), ship.name, finished_step, steps }, true)
end

return Public
