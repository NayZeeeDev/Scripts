-- Resource name lock: the folder must be named exactly 'nayzeee-coinshop'.
NAYZEEE_LOCK_OK = GetCurrentResourceName() == 'nayzeee-coinshop'
if not NAYZEEE_LOCK_OK then
    print(('^1[nayzeee-coinshop] This resource must be named "nayzeee-coinshop" (current: "%s"). Stopping.^0'):format(GetCurrentResourceName()))
    if IsDuplicityVersion() then
        CreateThread(function() StopResource(GetCurrentResourceName()) end)
    end
end
