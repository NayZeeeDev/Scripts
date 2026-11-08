if not NAYZEEE_LOCK_OK then return end

--[[
    Client: open / close, the NUI bridge, purchased vehicle spawning and test drives.
    Nothing runs while the shop is closed and nobody is test driving.
]]

local open, ready = false, false
local drive = nil          -- { vehicle, coords, heading, ends }

local function UI(action, data) SendNUIMessage({ action = action, data = data }) end

local function openShop()
    if open or not ready or drive or IsPauseMenuActive() then return end
    open = true
    SetNuiFocus(true, true)
    if Config.General.Blur then TriggerScreenblurFadeIn(200) end
    UI('open')
end

local function closeShop(fromNui)
    if not open then return end
    open = false
    if ShowroomStop then ShowroomStop() end
    SetNuiFocus(false, false)
    if Config.General.Blur then TriggerScreenblurFadeOut(200) end
    if not fromNui then UI('close') end
    TriggerServerEvent('nzc:closed')
end

exports('openShop', openShop)
exports('closeShop', function() closeShop() end)
exports('isOpen', function() return open end)

if Config.General.Command then
    RegisterCommand(Config.General.Command, function() if open then closeShop() else openShop() end end, false)
    RegisterKeyMapping(Config.General.Command, Config.General.KeyDescription, 'keyboard', Config.General.Key)
end

RegisterNetEvent('nzc:open', openShop)

-- ── NUI ─────────────────────────────────────────────────────────────────
RegisterNUICallback('ready', function(_, cb)
    ready = true
    cb({ locale = NZC.Locale(), scale = Config.UI.Scale })
end)

RegisterNUICallback('close', function(_, cb)
    closeShop(true)
    cb(true)
end)

RegisterNUICallback('req', function(d, cb)
    cb(lib.callback.await('nzc:req', false, d.name, d.data) or { error = 'ERR_GENERIC' })
end)

RegisterNUICallback('notify', function(d, cb)
    ClientBridge.Notify(d.text, d.kind)
    cb(true)
end)

RegisterNetEvent('nzc:push', function(channel, data)
    if open then UI('push', { channel = channel, data = data }) end
end)

-- ── vehicles ────────────────────────────────────────────────────────────
local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then return nil end
    RequestModel(hash)
    local deadline = GetGameTimer() + 8000
    while not HasModelLoaded(hash) do
        if GetGameTimer() > deadline then return nil end
        Wait(25)
    end
    return hash
end

local function spawnAt(hash, coords, heading, plate)
    local veh = CreateVehicle(hash, coords.x, coords.y, coords.z, heading, true, false)
    local deadline = GetGameTimer() + 3000
    while not DoesEntityExist(veh) and GetGameTimer() < deadline do Wait(0) end
    SetModelAsNoLongerNeeded(hash)
    if not DoesEntityExist(veh) then return nil end
    SetVehicleNumberPlateText(veh, plate)
    SetVehicleOnGroundProperly(veh)
    SetVehicleDirtLevel(veh, 0.0)
    SetVehRadioStation(veh, 'OFF')
    return veh
end

RegisterNetEvent('nzc:vehicle', function(model, plate, spawn)
    if not spawn then
        ClientBridge.Notify(T('N_VEHICLE_GARAGE', plate), 'success')
        return
    end
    local hash = loadModel(model)
    if not hash then return ClientBridge.Notify(T('N_VEHICLE_SPAWN_FAILED', plate), 'error') end
    local ped = cache.ped
    local pos = GetOffsetFromEntityInWorldCoords(ped, 0.0, Config.Vehicles.SpawnDistance, 0.0)
    local veh = spawnAt(hash, pos, GetEntityHeading(ped), plate)
    if not veh then return ClientBridge.Notify(T('N_VEHICLE_SPAWN_FAILED', plate), 'error') end
    SetEntityAsMissionEntity(veh, true, true)
    TaskWarpPedIntoVehicle(ped, veh, -1)
    ClientBridge.GiveKeys(veh, plate)
    ClientBridge.SetFuel(veh, 100.0)
    ClientBridge.Notify(T('N_VEHICLE_READY', plate), 'success')
    TriggerEvent('nayzeee-coinshop:vehicleSpawned', veh, plate, model)
end)

-- ── test drive ──────────────────────────────────────────────────────────
local function fade(out)
    if out then DoScreenFadeOut(400) else DoScreenFadeIn(400) end
    local deadline = GetGameTimer() + 1500
    while (out and not IsScreenFadedOut() or not out and not IsScreenFadedIn()) and GetGameTimer() < deadline do Wait(0) end
end

local function endDrive(reason)
    if not drive then return end
    local d = drive
    drive = nil
    UI('testdrive', { active = false })
    fade(true)
    local ped = cache.ped
    if d.vehicle and DoesEntityExist(d.vehicle) then
        if GetVehiclePedIsIn(ped, false) == d.vehicle then TaskLeaveVehicle(ped, d.vehicle, 16) Wait(150) end
        SetEntityAsMissionEntity(d.vehicle, true, true)
        DeleteVehicle(d.vehicle)
    end
    TriggerServerEvent('nzc:testdrive:end')
    SetEntityCoords(ped, d.coords.x, d.coords.y, d.coords.z - 0.95, false, false, false, false)
    SetEntityHeading(ped, d.heading)
    Wait(250)
    fade(false)
    ClientBridge.Notify(T(reason or 'N_TD_ENDED'), 'inform')
    TriggerEvent('nayzeee-coinshop:testDriveEnded')
    if d.reopen then SetTimeout(300, openShop) end
end

RegisterNUICallback('testdrive', function(d, cb)
    if drive then return cb({ error = 'ERR_TD_ACTIVE' }) end
    local res = lib.callback.await('nzc:req', false, 'testdrive:start', { id = d.id })
    if not res or res.error then return cb(res or { error = 'ERR_GENERIC' }) end
    local hash = loadModel(res.data.model)
    if not hash then
        TriggerServerEvent('nzc:testdrive:end')
        return cb({ error = 'ERR_TD_MODEL' })
    end
    cb({ data = true })
    closeShop()
    local ped = cache.ped
    drive = { coords = GetEntityCoords(ped), heading = GetEntityHeading(ped), ends = GetGameTimer() + res.data.duration * 1000, reopen = d.reopen ~= false }
    fade(true)
    local loc = Config.TestDrive.Location
    SetEntityCoords(ped, loc.x, loc.y, loc.z, false, false, false, false)
    local fwd = vector3(-math.sin(math.rad(loc.w)), math.cos(math.rad(loc.w)), 0.0)
    local veh = spawnAt(hash, vector3(loc.x, loc.y, loc.z) + fwd * Config.TestDrive.SpawnDistance, loc.w, Config.TestDrive.Plate)
    if not veh then
        drive.ends = 0
    else
        drive.vehicle = veh
        SetVehicleDoorsLocked(veh, 4)
        TaskWarpPedIntoVehicle(ped, veh, -1)
        ClientBridge.GiveKeys(veh, Config.TestDrive.Plate)
        ClientBridge.SetFuel(veh, 100.0)
    end
    fade(false)
    UI('testdrive', { active = true, seconds = res.data.duration })
    TriggerEvent('nayzeee-coinshop:testDriveStarted', res.data.model)
    CreateThread(function()
        while drive do
            local veh2 = drive.vehicle
            if GetGameTimer() >= drive.ends then endDrive('N_TD_ENDED') break end
            if not veh2 or not DoesEntityExist(veh2) or GetVehiclePedIsIn(cache.ped, false) ~= veh2 or IsEntityDead(cache.ped) then
                endDrive('N_TD_LEFT') break
            end
            Wait(250)
        end
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= NZC.Resource then return end
    if open then SetNuiFocus(false, false) TriggerScreenblurFadeOut(0) end
    if drive then
        if drive.vehicle and DoesEntityExist(drive.vehicle) then DeleteVehicle(drive.vehicle) end
        SetEntityCoords(cache.ped, drive.coords.x, drive.coords.y, drive.coords.z - 0.95, false, false, false, false)
        DoScreenFadeIn(0)
    end
end)
