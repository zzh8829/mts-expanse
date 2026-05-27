local Event = require 'utils.event_core'
local Global = {
    names = {},
    index = 0,
    filepath = {},
    filepath_counts = {}
}

storage.tokens = storage.tokens or {}

local concat = table.concat

--- Returns a stable mod-relative path for the caller.
---@param stack_level integer
---@param filepath string
---@return string
local function get_source_path(stack_level)
    local source = debug.getinfo(stack_level, 'S').source
    local filepath = source:match('^@__level__/(.+)$') or source:match('^@__[^/]+__/(.+)$') or source:match('^@(.+)$')

    if not filepath then
        error('Could not determine source path for global registration: ' .. tostring(source), 3)
    end

    return filepath:gsub('%.lua$', ''):gsub('/', '_')
end

--- Returns a deterministic suffix for multiple Global.register calls in one file.
---@param filepath string
---@return string
local function validate_entry(filepath)
    local count = Global.filepath_counts[filepath] or 0
    Global.filepath_counts[filepath] = count + 1
    if count > 0 then
        return filepath .. '_' .. count
    end
    return filepath
end

--- Sets a new global
---@param tbl any
---@return integer
---@return string
function Global.set_global(tbl)
    local filepath = get_source_path(3)
    filepath = validate_entry(filepath)

    Global.index = Global.index + 1
    Global.filepath[filepath] = Global.index
    Global.names[filepath] = concat { Global.filepath[filepath], ' - ', filepath }

    if not storage.tokens[filepath] then
        storage.tokens[filepath] = tbl
    end

    return Global.index, filepath
end

--- Gets a global from global
---@param token number|string
---@return any|nil
function Global.get_global(token)
    if storage.tokens[token] then
        return storage.tokens[token]
    end
end

function Global.register(tbl, callback)
    local token, filepath = Global.set_global(tbl)

    Event.on_load(
        function ()
            if storage.tokens[token] then
                callback(Global.get_global(token))
            else
                callback(Global.get_global(filepath))
            end
        end
    )

    return filepath
end

function Global.register_init(tbl, init_handler, callback)
    local token, filepath = Global.set_global(tbl)

    Event.on_init(
        function ()
            init_handler(tbl)
            callback(tbl)
        end
    )

    Event.on_load(
        function ()
            if storage.tokens[token] then
                callback(Global.get_global(token))
            else
                callback(Global.get_global(filepath))
            end
        end
    )
    return filepath
end

return Global
