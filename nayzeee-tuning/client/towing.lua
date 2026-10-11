--[[
    Tow jobs: drive out, winch the wreck onto a flatbed (or hook it to a tow truck),
    bring it back to the shop's drop point and unload it.
]]

Tow = { active = nil }

local TW = Config.Towing

local function sfx(name) if Install.Sfx then Install.Sfx(name) end end

local function blipAt(c, sprite, color, label, route)
    local b = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(b, sprite)
    SetBlipColour(b, color)
    SetBlipRoute(b, route ~= false)
    SetBlipRouteColour(b, color)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandSetBlipName(b)
    return b
end

local function truckCfg(veh)
    if not veh or veh == 0 then return nil end
    for model, cfg in pairs(TW.Trucks) do
        if GetEntityModel(veh) == joaat(model) then return cfg end
    end
end

local function rearOf(veh)
    local min = GetModelDimensions(GetEntityModel(veh))
    return GetOffsetFromEntityInWorldCoords(veh, 0.0, min.y - 0.6, 0.0)
end

local TOW_STEPS = { 'drive', 'load', 'haul', 'unload' }
local function objectives(t)
    local at = 1
    for i, st in ipairs(TOW_STEPS) do if st == t.stage then at = i end end
    local list = { { label = L('obj_tow_drive', t.data.vehicle or '') }, { label = L('obj_tow_load') }, { label = L('obj_tow_haul') }, { label = L('obj_tow_unload') } }
    for i, o in ipairs(list) do o.state = i < at and 'done' or i == at and 'now' or 'next' end
    UI.Send('obj:set', { title = L('obj_tow_title'), icon = 'fa-truck-pickup', steps = list })
end

local function cleanup(deleteWreck)
    local t = Tow.active
    if not t then return end
    UI.Send('obj:clear')
    if t.blip and DoesBlipExist(t.blip) then RemoveBlip(t.blip) end
    Bridge.TextUI(false)
    if deleteWreck and t.wreck and DoesEntityExist(t.wreck) then
        if IsEntityAttached(t.wreck) then DetachEntity(t.wreck, true, true) end
        DeleteEntity(t.wreck)
    end
    if t.ped and DoesEntityExist(t.ped) then DeleteEntity(t.ped) end
    -- the shop truck goes back in the garage once you step out of it
    local truck = t.ownTruck
    if truck and DoesEntityExist(truck) then
        CreateThread(function()
            while DoesEntityExist(truck) and GetVehiclePedIsIn(cache.ped, false) == truck do Wait(1000) end
            Wait(8000)
            if DoesEntityExist(truck) and GetPedInVehicleSeat(truck, -1) == 0 then DeleteEntity(truck) end
        end)
    end
    Tow.active = nil
end
Tow.Cleanup = cleanup

local function spawnTruck(at)
    if not at then return nil end
    local model = joaat(TW.TruckModel)
    if not lib.requestModel(model, 5000) then return nil end
    local veh = CreateVehicle(model, at.x, at.y, at.z, at.w or 0.0, true, false)
    SetModelAsNoLongerNeeded(model)
    SetVehicleOnGroundProperly(veh)
    SetVehicleNumberPlateText(veh, ('TOW%03d'):format(math.random(0, 999)))
    SetVehicleDoorsLocked(veh, 1)
    SetVehicleEngineOn(veh, false, true, true)
    lib.callback.await('nayzeee-tuning:workTruck', false, VehToNet(veh))
    return veh
end

local function spawnWreck(c)
    local vm, pm = joaat(c.vehicle), joaat(c.ped)
    if not lib.requestModel(vm, 5000) then return nil end
    local veh = CreateVehicle(vm, c.coords.x, c.coords.y, c.coords.z, c.coords.w, true, false)
    SetModelAsNoLongerNeeded(vm)
    SetVehicleOnGroundProperly(veh)
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleEngineHealth(veh, 90.0)
    SetVehicleBodyHealth(veh, 220.0)
    SetVehicleUndriveable(veh, true)
    SetVehicleDoorsLocked(veh, 2)
    for i = 0, 3 do SmashVehicleWindow(veh, math.random(0, 3)) end
    SetVehicleTyreBurst(veh, math.random(0, 1) == 0 and 0 or 4, true, 1000.0)
    for _ = 1, 5 do
        SetVehicleDamage(veh, math.random(-10, 10) / 10.0, math.random(-20, 20) / 10.0, 0.2, 900.0, 300.0, true)
    end
    SetVehicleIndicatorLights(veh, 0, true)
    SetVehicleIndicatorLights(veh, 1, true)
    local ped
    if lib.requestModel(pm, 4000) then
        local off = GetOffsetFromEntityInWorldCoords(veh, -3.0, 2.0, 0.0)
        ped = CreatePed(4, pm, off.x, off.y, off.z, c.coords.w + 120.0, false, false)
        SetModelAsNoLongerNeeded(pm)
        SetEntityAsMissionEntity(ped, true, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_MOBILE', 0, true)
    end
    return veh, ped
end

local function load(t, truck, cfg)
    local wreck = t.wreck
    if #(GetEntityCoords(wreck) - rearOf(truck)) > TW.LoadDistance then return Notify(L('tow_too_far'), 'error') end
    if GetEntitySpeed(truck) > 0.5 then return Notify(L('tow_stop_truck'), 'error') end
    TaskTurnPedToFaceEntity(cache.ped, wreck, 800)
    Wait(800)
    sfx('crane')
    if not Bridge.Progress(cfg.type == 'bed' and L('tow_winching') or L('tow_hooking'), TW.WinchTime, { 'mini@repair', 'fixing_a_ped', 1 }) then return end
    if not VehUtil.Control(wreck, 2000) then return Notify(L('failed'), 'error') end
    if cfg.type == 'bed' then
        local o = cfg.offset
        AttachEntityToEntity(wreck, truck, GetEntityBoneIndexByName(truck, 'bodyshell'), o.x, o.y, o.z, 0.0, 0.0, 0.0, false, false, true, false, 2, true)
    else
        AttachVehicleToTowTruck(truck, wreck, true, 0.0, 0.0, 0.0)
    end
    sfx('tighten')
    t.truck, t.stage = truck, 'haul'
    objectives(t)
    if t.blip then RemoveBlip(t.blip) end
    t.blip = blipAt(t.drop, 68, 5, L('tow_drop_blip'))
    Notify(L('tow_loaded'), 'success')
end

local function unload(t)
    local truck, wreck = t.truck, t.wreck
    if GetEntitySpeed(truck) > 0.5 then return Notify(L('tow_stop_truck'), 'error') end
    sfx('crane')
    if not Bridge.Progress(L('tow_unloading'), TW.UnloadTime, { 'mini@repair', 'fixing_a_ped', 1 }) then return end
    if not VehUtil.Control(wreck, 2000) then return Notify(L('failed'), 'error') end
    if IsEntityAttachedToEntity(wreck, truck) then DetachEntity(wreck, true, true) end
    if IsVehicleAttachedToTowTruck(truck, wreck) then DetachVehicleFromTowTruck(truck, wreck) end
    local back = GetOffsetFromEntityInWorldCoords(truck, 0.0, -9.5, 0.0)
    SetEntityCoords(wreck, back.x, back.y, back.z + 0.5, false, false, false, false)
    SetEntityHeading(wreck, GetEntityHeading(truck))
    SetVehicleOnGroundProperly(wreck)
    local ok, res = lib.callback.await('nayzeee-tuning:finishTow', false, t.data.id, VehToNet(wreck))
    if not ok then return Notify(res or L('failed'), 'error') end
    Notify(L('tow_paid', res.paid), 'success')
    t.wreck = nil       -- the server removes it after a while
    cleanup(false)
end

function Tow.Start(c)
    if Tow.active or Missions.active then return Notify(L('callout_busy'), 'error') end
    local drop = c.drop and vec3(c.drop.x, c.drop.y, c.drop.z)
    if not drop then return Notify(L('tow_no_drop'), 'error') end
    local t = { data = c, stage = 'drive', drop = drop }
    Tow.active = t
    local target = vec3(c.coords.x, c.coords.y, c.coords.z)
    t.blip = blipAt(target, 68, 47, L('tow_blip', c.vehicle))
    if TW.SpawnTruck and not truckCfg(cache.vehicle) and c.truckSpawn then
        t.ownTruck = spawnTruck(c.truckSpawn)
        if t.ownTruck then t.truckSeen = t.ownTruck Notify(L('tow_truck_ready'), 'inform') end
    end
    Notify(L('tow_started'), 'inform')
    objectives(t)

    CreateThread(function()
        while Tow.active == t and #(GetEntityCoords(cache.ped) - target) > 150.0 do Wait(1000) end
        if Tow.active ~= t then return end
        t.wreck, t.ped = spawnWreck(c)
        if not t.wreck then Notify(L('failed'), 'error') return cleanup(true) end
        t.stage = 'load'
        objectives(t)

        local shown
        local function show(txt) if shown ~= txt then shown = txt Bridge.TextUI(txt) end end
        local function hide() if shown then shown = nil Bridge.TextUI(false) end end

        while Tow.active == t do
            local sleep = 500
            local me = GetEntityCoords(cache.ped)
            if not DoesEntityExist(t.wreck) then Notify(L('tow_lost'), 'error') cleanup(false) break end
            if t.stage == 'load' then
                -- the truck is the last tow-capable vehicle you were in nearby
                local truck = cache.vehicle and truckCfg(cache.vehicle) and cache.vehicle or t.truckSeen
                if cache.vehicle and truckCfg(cache.vehicle) then t.truckSeen = cache.vehicle end
                if not cache.vehicle and truck and DoesEntityExist(truck) then
                    local rear = rearOf(truck)
                    if #(me - rear) < 4.0 then
                        sleep = 0
                        DrawMarker(2, rear.x, rear.y, rear.z + 1.0, 0, 0, 0, 180.0, 0, 0, 0.3, 0.3, 0.3, 8, 175, 162, 200, true, true, 2, false, nil, nil, false)
                        show(L('prompt_tow_load'))
                        if IsControlJustPressed(0, Config.Keys.Interact) then hide() load(t, truck, truckCfg(truck)) end
                    else hide() end
                elseif #(me - GetEntityCoords(t.wreck)) < 40.0 and not t.hinted then
                    t.hinted = true
                    Notify(L('tow_how'), 'inform', 8000)
                end
            elseif t.stage == 'haul' then
                if #(me - t.drop) < TW.DropRadius + 30.0 then
                    sleep = 0
                    DrawMarker(1, t.drop.x, t.drop.y, t.drop.z - 0.95, 0, 0, 0, 0, 0, 0, TW.DropRadius * 2.0, TW.DropRadius * 2.0, 0.6, 8, 175, 162, 60, false, false, 2, false, nil, nil, false)
                    local truck = t.truck
                    if DoesEntityExist(truck) and #(GetEntityCoords(truck) - t.drop) < TW.DropRadius and not t.atDrop then
                        t.atDrop = true
                        t.stage = 'unload' objectives(t) t.stage = 'haul'
                    end
                    if not cache.vehicle and DoesEntityExist(truck) and #(GetEntityCoords(truck) - t.drop) < TW.DropRadius and #(me - rearOf(truck)) < 4.0 then
                        show(L('prompt_tow_unload'))
                        if IsControlJustPressed(0, Config.Keys.Interact) then hide() unload(t) end
                    else hide() end
                end
            end
            Wait(sleep)
        end
        Bridge.TextUI(false)
    end)
end

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and Tow.active then cleanup(true) end
end)
