--[[ Server bootstrap: menu access, usable items, featured heist, reconnect restore, heist vehicle ]]

--[[ featured heist of the day ]]
local function refreshFeatured()
    GlobalState:set('nzh:featured', Utils.featured(), true)
end
CreateThread(function()
    refreshFeatured()
    while true do
        Wait(3600000)
        refreshFeatured()
    end
end)

--[[ tablet bootstrap ]]
Guard.callback('nzh:menu:open', function(src)
    if not Engine.canAccessMenu(src) then return false, locale('no_permission') end
    if Config.Menu.requireNearEmployer > 0 then
        local near = false
        for i = 1, #Config.Employers do
            if Guard.near(src, Config.Employers[i].coords, Config.Menu.requireNearEmployer) then near = true break end
        end
        if not near then return false, locale('menu_need_employer') end
    end
    local profile = Profile.public(src)
    if not profile then return false, locale('profile_error') end
    local crew = Crew.ensure(src)
    return true, {
        profile = profile,
        crew = Crew.state(crew),
        featured = GlobalState['nzh:featured'],
        featuredBonus = Config.Featured,
        levels = Config.Levels,
    }
end)

--[[ usable items ]]
if Config.Menu.item then
    FW.registerUsable(Config.Menu.item, function(src)
        TriggerClientEvent('nzh:menu:open', src)
    end)
end

FW.registerUsable('heist_drone', function(src)
    TriggerClientEvent('nzh:drone:use', src)
end)

FW.registerUsable('gasmask', function(src)
    TriggerClientEvent('nzh:gasmask', src)
end)

--[[ reconnect restore ]]
FW.onLoaded(function(src)
    SetTimeout(2500, function() Engine.restore(src) end)
end)

--[[ crew getaway vehicle (once per heist, leader only, near an employer) ]]
Guard.callback('nzh:heist:vehicle', function(src)
    if not Config.HeistVehicle.enabled then return false end
    local crew = Crew.get(src)
    local inst = crew and crew.heist and Engine.instances[crew.heist]
    if not inst or inst.finished then return false, locale('no_heist') end
    if crew.leader ~= src then return false, locale('only_leader') end
    if inst.crewVehicle then return false, locale('vehicle_already') end
    local employer
    for i = 1, #Config.Employers do
        if Guard.near(src, Config.Employers[i].coords, 15.0) then employer = Config.Employers[i] break end
    end
    if not employer or not employer.vehicleSpawn then return false, locale('menu_need_employer') end
    local s = employer.vehicleSpawn
    local veh = CreateVehicleServerSetter(joaat(Config.HeistVehicle.model), 'automobile', s.x, s.y, s.z, s.w)
    local timeout = 0
    while not DoesEntityExist(veh) and timeout < 50 do Wait(50) timeout = timeout + 1 end
    if not DoesEntityExist(veh) then return false end
    Entity(veh).state:set('nzhCrewVehicle', inst.uid, true)
    local netId = NetworkGetNetworkIdFromEntity(veh)
    inst.crewVehicle = netId
    inst.entities.crewVehicle = netId
    for i = 1, #inst.members do
        TriggerClientEvent('nzh:heist:entities', inst.members[i], inst.entities, inst.guards)
    end
    return true, netId
end)

--[[ resource stop: give every running crew a clean slate ]]
AddEventHandler('onResourceStop', function(res)
    if res ~= RES then return end
    GlobalState:set('nzh:doors', {}, true)
    for _, inst in pairs(Engine.instances) do
        for i = 1, #inst.members do
            if GetPlayerRoutingBucket(inst.members[i]) == inst.bucket then SetPlayerRoutingBucket(inst.members[i], 0) end
        end
    end
end)

print(('^2[%s]^7 loaded %d heists | framework: %s | inventory: %s | dispatch: %s'):format(RES, #Heists.order, FW.name, Inv.name, Dispatch.name))
