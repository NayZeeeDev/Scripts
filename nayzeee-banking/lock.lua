--[[
    Folder name lock.

    Every export, event and NUI callback in this resource is namespaced to
    nayzeee-banking. Renaming the folder breaks all of them quietly — the
    script boots, the UI opens, and then exports fail somewhere else on the
    server with no obvious cause.

    So it refuses to run at all instead.
]]

local REQUIRED = 'nayzeee-banking'
local current  = GetCurrentResourceName()

BankLocked = current ~= REQUIRED

if BankLocked then
    local line = ('^1%s^0'):format(string.rep('═', 68))

    print(line)
    print('^1  NAYZEEE BANKING — WRONG FOLDER NAME^0')
    print('')
    print(('^1  Found:    ^3%s^0'):format(current))
    print(('^1  Required: ^2%s^0'):format(REQUIRED))
    print('')
    print('^1  Rename the folder to ^2' .. REQUIRED .. '^1 and restart the server.^0')
    print('^1  The resource has been stopped.^0')
    print(line)

    if IsDuplicityVersion() then
        CreateThread(function()
            Wait(500)
            StopResource(current)
        end)
    end
end
