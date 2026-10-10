--[[ Player lifecycle + the one heartbeat thread (every 60s, only while players are loaded) ]]

local function boot(src)
    if Profile.get(src) then return end
    local P = Profile.load(src)
    if not P then return end
    if P.labs.rv.owned then Labs.spawnRV(src) end
    Story.restore(src)
    Profile.sync(src)
end

FW.onLoaded(function(src)
    SetTimeout(2000, function() boot(src) end)
end)

-- clients ask once their scripts are ready (covers resource restarts and frameworks without events)
RegisterNetEvent('nzwl:ready', function()
    local src = source
    if not Guard.rate(src, 'ready', 5000) then return end
    if Profile.get(src) then
        Profile.sync(src)
        local net = Labs.rvNet(src)
        if net then TriggerClientEvent('nzwl:rv:net', src, net) end
        local m = Story.missionNet(src)
        if m then TriggerClientEvent('nzwl:story:mission', src, { net = m, spot = Profile.get(src).story.rvSpot }) end
        return
    end
    if FW.name ~= 'none' and not FW.getPlayer(src) then return end -- character not picked yet
    boot(src)
end)

FW.onUnloaded(function(src)
    if Profile.get(src) then
        TriggerEvent('nzwl:server:unload', src)
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
                Labs.tick(src)
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
