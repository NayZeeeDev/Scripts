--[[
    NAYZEEE Inventory Manager: file writer
    FiveM only lets a resource write inside its own folder. Add this file to a resource the panel
    edits (qb-core, qb-shops, qb-inventory, your own inventory...) so saves from the panel can land:

        1. Copy this file into that resource, e.g. qb-core/nz_writer.lua
        2. Add it to that resource's fxmanifest.lua:   server_script 'nz_writer.lua'
        3. Restart the server

    Only the resource named by the `inventory:nzmanager` convar (default nayzeee-inventorylogs)
    can call it, and only for .lua files and .png images inside this resource.
    The one-line alternative is `add_filesystem_permission nayzeee-inventorylogs write <resource>`
    in server.cfg; you only need one of the two.
]]
local RESOURCE = GetCurrentResourceName()
local MANAGER = GetConvar('inventory:nzmanager', 'nayzeee-inventorylogs')

exports('nzWrite', function(path, content)
    if GetInvokingResource() ~= MANAGER then return { ok = false, err = 'not allowed' } end
    if type(path) ~= 'string' or type(content) ~= 'string' then return { ok = false, err = 'bad arguments' } end
    if path:find('%.%.') or path:find('^[/\\]') or not (path:match('%.lua$') or path:match('%.png$')) then
        return { ok = false, err = 'path not allowed' }
    end
    local ok = SaveResourceFile(RESOURCE, path, content, #content)
    return { ok = ok == true or ok == 1, err = (ok ~= true and ok ~= 1) and ('could not write ' .. path) or nil }
end)
