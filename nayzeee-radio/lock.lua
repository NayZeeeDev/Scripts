--[[
    NAYZEEE RADIO - Resource Name Lock

    This resource must live in a folder named exactly 'nayzeee-radio'.

    The name is baked into exports, events, NUI callbacks (https://nayzeee-radio/...),
    DUI urls (nui://nayzeee-radio/...) and streamed asset paths. Renaming the folder
    silently breaks all of them, so the resource refuses to run instead of loading
    half-working.

    Loaded first in shared_scripts. Do not move it further down the list.
]]

local REQUIRED_NAME = 'nayzeee-radio'
local currentName = GetCurrentResourceName()

NAYZEEE_LOCK_OK = (currentName == REQUIRED_NAME)

if not NAYZEEE_LOCK_OK then
    local line = '^1' .. string.rep('=', 68) .. '^7'

    print(line)
    print('^1  NAYZEEE RADIO - WRONG FOLDER NAME^7')
    print(line)
    print(('^1  Folder found:    ^3%s^7'):format(currentName))
    print(('^1  Folder required: ^2%s^7'):format(REQUIRED_NAME))
    print('^7')
    print('^1  This resource will NOT start until the folder is renamed.^7')
    print('^7  The resource name is used by:^7')
    print('^7    - exports[\'nayzeee-radio\']^7')
    print('^7    - nzr:* events and NUI callbacks^7')
    print('^7    - the radio screens (DUI) and streamed props^7')
    print('^7')
    print(('^7  Rename the folder to ^2%s^7 and restart the server.^7'):format(REQUIRED_NAME))
    print(line)

    if IsDuplicityVersion() then
        CreateThread(function()
            Wait(0)
            StopResource(currentName)
        end)
    end
end
