-- Resource name lock: the folder must be named exactly 'nayzeee-racing'.
NAYZEEE_LOCK_OK = GetCurrentResourceName() == 'nayzeee-racing'
if not NAYZEEE_LOCK_OK then
    print(('^1[nayzeee-racing] This resource must be named "nayzeee-racing" (current: "%s"). Stopping.^0'):format(GetCurrentResourceName()))
    if IsDuplicityVersion() then
        CreateThread(function() StopResource(GetCurrentResourceName()) end)
    end
end
