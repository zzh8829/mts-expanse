local Public = {}

Public.VANILLA = 'vanilla'
Public.SPACE_AGE = 'space-age'

function Public.current()
    return script.active_mods['space-age'] and Public.SPACE_AGE or Public.VANILLA
end

function Public.is_space_age()
    return Public.current() == Public.SPACE_AGE
end

function Public.is_vanilla()
    return Public.current() == Public.VANILLA
end

return Public
