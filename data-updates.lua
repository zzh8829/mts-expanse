if not mods['space-age'] then return end
-- Native hatches accept explicit pod prototypes. Preserve vanilla pods and
-- allow the larger mission-only batches, including attached cargo bays.
local function allow_reward_pods(hatches)
    for _, hatch in pairs(hatches or {}) do
        for _, name in ipairs(hatch.receiving_cargo_units or {}) do
            if name == 'cargo-pod' then
                table.insert(hatch.receiving_cargo_units, 'mts-expanse-reward-pod')
                break
            end
        end
    end
end
for _, prototype in pairs(data.raw['cargo-landing-pad']) do
    local station = prototype.cargo_station_parameters
    allow_reward_pods(station and station.hatch_definitions)
end
for _, prototype in pairs(data.raw['cargo-bay']) do
    allow_reward_pods(prototype.hatch_definitions)
end
