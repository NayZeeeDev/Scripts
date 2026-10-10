-- Framework bridge (client). Reports downed state and performs the actual revive.
Bridge = {}

local downed = false

function Bridge.IsDowned() return downed end

local function setDowned(state)
    state = state == true
    if downed == state then return end
    downed = state
    TriggerServerEvent('nz_squads:setDowned', state)
end

Bridge.SetDowned = setDowned

if GetResourceState('es_extended') ~= 'missing' then
    AddEventHandler('esx:onPlayerDeath', function() setDowned(true) end)
    AddEventHandler('esx:onPlayerSpawn', function() setDowned(false) end)
    RegisterNetEvent('esx_ambulancejob:revive', function() setDowned(false) end)
elseif GetResourceState('qbx_core') ~= 'missing' or GetResourceState('qb-core') ~= 'missing' then
    RegisterNetEvent('QBCore:Player:SetPlayerData', function(data)
        local md = data and data.metadata
        if md then setDowned(md.isdead or md.inlaststand) end
    end)
end

-- fallback for servers with no ambulance job wired in
CreateThread(function()
    while true do
        Wait(1000)
        local ped = cache.ped
        if IsPedDeadOrDying(ped, true) then
            if not downed then setDowned(true) end
        elseif downed and GetEntityHealth(ped) > 101 then
            setDowned(false)
        end
    end
end)

--- Called by the server once a revive is approved.
RegisterNetEvent('nz_squads:client:revive', function(health)
    local ped = cache.ped
    local coords = GetEntityCoords(ped)

    if GetResourceState('es_extended') ~= 'missing' then
        TriggerEvent('esx_ambulancejob:revive')
    end

    if IsPedDeadOrDying(ped, true) then
        NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, GetEntityHeading(ped), true, false)
    end

    local max = GetEntityMaxHealth(ped)
    SetEntityHealth(ped, math.floor(100 + (max - 100) * (math.min(100, health or 50) / 100)))
    ClearPedBloodDamage(ped)
    ClearPedTasksImmediately(ped)
    SetPlayerInvincible(PlayerId(), false)
    setDowned(false)
end)
