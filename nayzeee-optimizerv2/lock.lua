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

-- House-style FAIL line. This runs before server/console.lua exists and the
-- resource stops straight after, so it cannot join the startup block.
local function banner(current)
    print(('^5[NayZeee Optimizer]^7^1 FAIL ^7Folder is named "%s", it must be "%s": rename the folder and restart the server^0')
        :format(tostring(current), REQUIRED_RESOURCE_NAME))
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
