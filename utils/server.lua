local Public = {}

local data_set_handlers = {}

local function noop()
end

function Public.output_script_data(message)
    if message ~= nil then
        log(tostring(message))
    end
end

function Public.to_discord_embed(message)
    if message ~= nil then
        log('[mts-expanse discord disabled] ' .. serpent.line(message))
    end
end

Public.to_discord_bold = Public.to_discord_embed
Public.to_discord = Public.to_discord_embed
Public.to_discord_notification = Public.to_discord_embed

function Public.get_current_time()
    return nil
end

function Public.get_admins_data()
    return {}
end

function Public.set_data(dataset, key, value)
    local handlers = data_set_handlers[dataset]
    if not handlers then
        return
    end
    for _, handler in pairs(handlers) do
        handler({ dataset = dataset, key = key, value = value })
    end
end

function Public.try_get_data(_dataset, key, token)
    if token and ServerCommands and ServerCommands.raise_callback then
        ServerCommands.raise_callback(token, { key = key, value = nil })
    end
end

function Public.try_get_data_and_print(_dataset, key, to_print, token)
    if token and ServerCommands and ServerCommands.raise_callback then
        ServerCommands.raise_callback(token, { key = key, value = nil, to_print = to_print })
    end
end

function Public.try_get_all_data(_dataset, token)
    if token and ServerCommands and ServerCommands.raise_callback then
        ServerCommands.raise_callback(token, { entries = {} })
    end
end

function Public.on_data_set_changed(dataset, handler)
    if not data_set_handlers[dataset] then
        data_set_handlers[dataset] = {}
    end
    data_set_handlers[dataset][#data_set_handlers[dataset] + 1] = handler
end

function Public.start_scenario(name)
    game.print('Scenario restart is disabled in the standalone MTS Expanse mod: ' .. tostring(name))
end

Public.stop_scenario = noop
Public.save_hot_patch = noop
Public.raise_data_set = noop
Public.raise_admins = noop
Public.get_tracked_data_sets = function () return {} end
Public.raise_scenario_changed = noop
Public.get_tracked_scenario = function () return {} end

return Public
