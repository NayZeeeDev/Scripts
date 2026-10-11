-- Resource name lock. Every entry file checks NAYZEEE_LOCK_OK before running.
local REQUIRED = 'nayzeee-multicharacter'
local current = GetCurrentResourceName()

NAYZEEE_LOCK_OK = current == REQUIRED

if not NAYZEEE_LOCK_OK then
    print(('^1[%s] This resource must be named "%s" (folder is "%s"). Rename the folder and restart.^0'):format(REQUIRED, REQUIRED, current))
    if IsDuplicityVersion() then
        CreateThread(function() StopResource(current) end)
    end
end
