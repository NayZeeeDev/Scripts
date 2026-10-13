--[[
    ═══════════════════════════════════════════════════════════════════════════
     NAYZEEE OPTIMIZER — RESOURCE NAME LOCK

     Keep this file escrow-protected. It must NOT be listed in .escrow_ignore,
     otherwise the lock is editable by anyone who buys the resource.

     Loaded as the first shared_script so client.lua and server.lua can call
     NayZeeeResourceLock() before doing anything else.
    ═══════════════════════════════════════════════════════════════════════════
]]

local REQUIRED_RESOURCE_NAME = 'nayzeee-optimizerv2'

local function banner(current)
    print('^1')
    print('^1╔══════════════════════════════════════════════════════════════╗^7')
    print('^1║  NAYZEEE OPTIMIZER — WRONG FOLDER NAME, RESOURCE NOT LOADED  ║^7')
    print('^1╚══════════════════════════════════════════════════════════════╝^7')
    print(('^1  Folder is named : ^3%s^7'):format(tostring(current)))
    print(('^1  It must be named: ^2%s^7'):format(REQUIRED_RESOURCE_NAME))
    print('^1  Rename the folder to the name above, then restart the server.^7')
    print('^1')
end

-- Global on purpose: client.lua and server.lua call this before anything else.
-- Returns true only when the folder name matches exactly.
function NayZeeeResourceLock()
    local current = GetCurrentResourceName()

    if current == REQUIRED_RESOURCE_NAME then
        return true
    end

    banner(current)

    if IsDuplicityVersion and IsDuplicityVersion() then
        StopResource(current)
    end

    return false
end

-- Fail closed on the server even if something later swallows the return value.
if IsDuplicityVersion and IsDuplicityVersion() then
    CreateThread(function()
        Wait(0)
        if GetCurrentResourceName() ~= REQUIRED_RESOURCE_NAME then
            StopResource(GetCurrentResourceName())
        end
    end)
end
