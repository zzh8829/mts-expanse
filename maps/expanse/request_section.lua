local Public = {}

-- Circuit sections are read-only. Editing a named section also edits every
-- other requester using that group.
function Public.is_private(section)
    return section and section.valid and section.is_manual and section.group == ''
end

function Public.acquire(owner, section)
    if Public.is_private(section) then return section end
    return owner.add_section()
end

return Public
