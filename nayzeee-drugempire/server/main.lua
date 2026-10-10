--[[ Player lifecycle + the one heartbeat thread (every 60s, only while players are loaded) ]]

local function boot(src)
    if Profile.get(src) then return end
    local P = Profile.load(src)
    if not P then return end
    if P.rv.owned then RV.spawn(src) end
    Story.restore(src)
    Profile.sync(src)
end

FW.onLoaded(function(src)
    SetTimeout(2000, function() boot(src) end)
end)

-- clients ask once their scripts are ready (covers resource restarts and frameworks without events)
RegisterNetEvent('nzde:ready', function()
    local src = source
    if not Guard.rate(src, 'ready', 5000) then return end
    if Profile.get(src) then
        Profile.sync(src)
        local net = RV.netOf(src)
        if net then TriggerClientEvent('nzde:rv:net', src, net) end
        local m = Story.missionNet(src)
        if m then TriggerClientEvent('nzde:story:mission', src, { net = m, spot = Profile.get(src).story.rvSpot }) end
        return
    end
    if FW.name ~= 'none' and not FW.getPlayer(src) then return end -- character not picked yet
    boot(src)
end)

FW.onUnloaded(function(src)
    if Profile.get(src) then
        TriggerEvent('nzde:server:unload', src)
        Profile.unload(src)
    end
end)

CreateThread(function()
    local lastSave = os.time()
    while true do
        Wait(60000)
        local list = Profile.all()
        if next(list) then
            for src in pairs(list) do
                Story.tick(src)
                RV.tick(src)
                Customers.tick(src)
                Dealers.tick(src)
                Deliveries.tick(src)
            end
            if os.time() - lastSave >= ServerConfig.SaveSeconds then
                lastSave = os.time()
                for src in pairs(list) do Profile.save(src) end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    for src in pairs(Profile.all()) do Profile.save(src, true) end
end)

print(('^2[%s]^7 framework: %s | inventory: %s | dispatch: %s'):format(RES, FW.name, Inv.name, Dispatch.name))
