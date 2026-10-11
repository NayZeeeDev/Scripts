--[[
    Supply runs, step by step (objective tracker on screen):
      1 get in the work van   2 drive to the warehouse   3 carry the packages into the van
      4 drive back to the shop   5 carry every package into supply storage
]]

Supply = { active = nil }

local SR = Config.SupplyRuns
local CARRY = { 'anim@heists@box_carry@', 'idle' }
local CRATE_AT = { 60309, 0.025, 0.08, 0.255, -145.0, 290.0, 0.0 }

local function isTruck(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return false end
    local m = GetEntityModel(veh)
    for _, name in ipairs(SR.TruckModels) do if m == joaat(name) then return true end end
    return false
end

local function rearOf(veh)
    local min = GetModelDimensions(GetEntityModel(veh))
    return GetOffsetFromEntityInWorldCoords(veh, 0.0, min.y - 0.7, 0.0)
end

local function blipAt(c, sprite, color, label)
    local b = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(b, sprite)
    SetBlipColour(b, color)
    SetBlipRoute(b, true)
    SetBlipRouteColour(b, color)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandSetBlipName(b)
    return b
end

local function setBlip(r, c, sprite, color, label)
    if r.blip and DoesBlipExist(r.blip) then RemoveBlip(r.blip) end
    r.blip = c and blipAt(c, sprite, color, label) or nil
end

--------------------------------------------------------------------- objective tracker

local STEPS = { 'van', 'drive', 'load', 'return', 'unload' }

local function objectives(r)
    local at = 0
    for i, s in ipairs(STEPS) do if s == r.stage then at = i end end
    local list = {
        { label = r.ownTruck and L('obj_van') or L('obj_van_own') },
        { label = L('obj_drive', r.data.warehouse.label) },
        { label = L('obj_load'), n = r.loaded, of = r.crates },
        { label = L('obj_return', r.data.shopLabel or '') },
        { label = L('obj_store'), n = r.stored, of = r.crates },
    }
    for i, o in ipairs(list) do o.state = i < at and 'done' or i == at and 'now' or 'next' end
    local sig = r.stage .. r.loaded .. r.stored
    if sig == r.sig then return end
    r.sig = sig
    UI.Send('obj:set', { title = L('obj_supply_title'), icon = 'fa-truck-ramp-box', left = r.ends - GetCloudTimeAsInt(), steps = list })
end

--------------------------------------------------------------------- carrying a package

local function dropCrate(r)
    if r.crate and DoesEntityExist(r.crate) then DetachEntity(r.crate, true, true) DeleteEntity(r.crate) end
    r.crate = nil
    StopAnimTask(cache.ped, CARRY[1], CARRY[2], 2.0)
end

local function pickUp(r)
    if not lib.requestAnimDict(CARRY[1], 2000) then return end
    local model = joaat(SR.CrateProp)
    if not lib.requestModel(model, 3000) then return end
    TaskPlayAnim(cache.ped, CARRY[1], CARRY[2], 6.0, -6.0, -1, 49, 0, false, false, false)
    local c = GetEntityCoords(cache.ped)
    r.crate = CreateObject(model, c.x, c.y, c.z, true, true, false)
    SetEntityCollision(r.crate, false, false)
    local a = CRATE_AT
    AttachEntityToEntity(r.crate, cache.ped, GetPedBoneIndex(cache.ped, a[1]), a[2], a[3], a[4], a[5], a[6], a[7], true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(model)
end

-- walking with a package: no sprinting, jumping or fighting; keep the arms up
local function carrying(r)
    if not r.crate then return end
    DisableControlAction(0, 21, true) DisableControlAction(0, 22, true)
    DisableControlAction(0, 24, true) DisableControlAction(0, 25, true) DisableControlAction(0, 23, true)
    if not IsEntityPlayingAnim(cache.ped, CARRY[1], CARRY[2], 3) then
        TaskPlayAnim(cache.ped, CARRY[1], CARRY[2], 6.0, -6.0, -1, 49, 0, false, false, false)
    end
end

local function setDown(label)
    local ok = Bridge.Progress(label, SR.LoadTime, { CARRY[1], CARRY[2], 49 }, nil, false)
    return ok
end

--------------------------------------------------------------------- run

local function cleanup()
    local r = Supply.active
    if not r then return end
    setBlip(r, nil)
    dropCrate(r)
    Bridge.TextUI(false)
    UI.Send('obj:clear')
    local truck = r.ownTruck
    if truck and DoesEntityExist(truck) then
        CreateThread(function()
            while DoesEntityExist(truck) and GetVehiclePedIsIn(cache.ped, false) == truck do Wait(1000) end
            Wait(8000)
            if DoesEntityExist(truck) and GetPedInVehicleSeat(truck, -1) == 0 then DeleteEntity(truck) end
        end)
    end
    Supply.active = nil
end

local function arrow(c, z)
    DrawMarker(2, c.x, c.y, c.z + (z or 1.0), 0, 0, 0, 180.0, 0, 0, 0.3, 0.3, 0.3, 8, 175, 162, 200, true, true, 2, false, nil, nil, false)
end

function Supply.Start(d)
    if Supply.active then return Notify(L('supply_busy'), 'error') end
    local wh = d.warehouse
    local r = { data = d, stage = 'van', loaded = 0, stored = 0, crates = d.crates,
        pile = vec3(wh.crates.x, wh.crates.y, wh.crates.z),
        drop = vec3(d.drop.x, d.drop.y, d.drop.z), storage = vec3(d.storage.x, d.storage.y, d.storage.z),
        ends = GetCloudTimeAsInt() + d.limit }
    Supply.active = r

    if SR.SpawnTruck and not isTruck(cache.vehicle) and d.truckSpawn then
        local model = joaat(SR.TruckModel)
        if lib.requestModel(model, 5000) then
            local s = d.truckSpawn
            r.ownTruck = CreateVehicle(model, s.x, s.y, s.z, s.w or 0.0, true, false)
            SetModelAsNoLongerNeeded(model)
            SetVehicleOnGroundProperly(r.ownTruck)
            SetVehicleNumberPlateText(r.ownTruck, ('SUP%03d'):format(math.random(0, 999)))
            SetVehicleDoorsLocked(r.ownTruck, 1)
            lib.callback.await('nayzeee-tuning:workTruck', false, VehToNet(r.ownTruck))
            r.truck = r.ownTruck
            setBlip(r, GetEntityCoords(r.ownTruck), 67, 5, L('supply_van_blip'))
        end
    end
    if isTruck(cache.vehicle) then r.truck = cache.vehicle end
    if not r.ownTruck then r.stage = isTruck(cache.vehicle) and 'drive' or 'van' end
    if r.stage == 'drive' then setBlip(r, r.pile, 478, 5, L('supply_blip', wh.label)) end
    objectives(r)

    CreateThread(function()
        local shown
        local function show(t) if shown ~= t then shown = t Bridge.TextUI(t) end end
        local function hide() if shown then shown = nil Bridge.TextUI(false) end end
        local function go(stage, c, sprite, color, label)
            r.stage = stage
            if c then setBlip(r, c, sprite, color, label) end
            objectives(r)
        end

        while Supply.active == r do
            local sleep = 500
            local me = GetEntityCoords(cache.ped)
            if cache.vehicle and isTruck(cache.vehicle) then r.truck = cache.vehicle end
            local truck = r.truck and DoesEntityExist(r.truck) and r.truck or nil
            if r.crate then sleep = 0 carrying(r) end

            if r.stage == 'van' then
                if cache.vehicle and isTruck(cache.vehicle) then
                    go('drive', r.pile, 478, 5, L('supply_blip', wh.label))
                elseif truck then
                    local tc = GetEntityCoords(truck)
                    if #(me - tc) < 30.0 then sleep = 0 arrow(tc, 2.6) end
                end

            elseif r.stage == 'drive' then
                if #(me - r.pile) < 45.0 then go('load') end

            elseif r.stage == 'load' then
                sleep = 0
                if not r.crate then arrow(r.pile, 0.4) end
                if r.crate then
                    if truck then
                        local rear = rearOf(truck)
                        arrow(rear)
                        if #(me - rear) < 2.4 then
                            show(L('prompt_supply_load', r.loaded + 1, r.crates))
                            if IsControlJustPressed(0, Config.Keys.Interact) then
                                hide()
                                SetVehicleDoorOpen(truck, 2, false, false) SetVehicleDoorOpen(truck, 3, false, false)
                                if setDown(L('supply_loading')) then
                                    local ok, n = lib.callback.await('nayzeee-tuning:supply:crate', false, VehToNet(truck))
                                    if ok then
                                        dropCrate(r)
                                        r.loaded = n
                                        objectives(r)
                                        if r.loaded >= r.crates then
                                            SetVehicleDoorsShut(truck, false)
                                            go('return', r.drop, 478, 2, L('supply_drop_blip'))
                                            Notify(L('supply_loaded'), 'success')
                                        end
                                    else Notify(n or L('supply_need_truck'), 'error') end
                                end
                            end
                        else hide() end
                    else show(L('supply_bring_truck')) end
                elseif not cache.vehicle and #(me - r.pile) < 1.8 then
                    show(L('prompt_supply_grab', r.loaded + 1, r.crates))
                    if IsControlJustPressed(0, Config.Keys.Interact) then hide() pickUp(r) end
                else hide() end

            elseif r.stage == 'return' then
                if #(me - r.drop) < SR.DropRadius + 30.0 then
                    sleep = 0
                    arrow(r.drop, 0.2)
                    if truck and not cache.vehicle and #(GetEntityCoords(truck) - r.drop) < SR.DropRadius then
                        go('unload', r.storage, 478, 2, L('supply_storage_blip'))
                    end
                end

            elseif r.stage == 'unload' then
                sleep = 0
                if r.crate then
                    arrow(r.storage, 0.4)
                    if #(me - r.storage) < Config.Storage.UseRadius then
                        show(L('prompt_supply_store', r.stored + 1, r.crates))
                        if IsControlJustPressed(0, Config.Keys.Interact) then
                            hide()
                            if setDown(L('supply_storing')) then
                                local ok, res = lib.callback.await('nayzeee-tuning:supply:store', false)
                                if ok then
                                    dropCrate(r)
                                    r.stored = res.stored
                                    objectives(r)
                                    if res.done then
                                        Notify(L('supply_done'), 'success')
                                        cleanup()
                                        break
                                    end
                                else Notify(res or L('failed'), 'error') end
                            end
                        end
                    else hide() end
                elseif truck then
                    local rear = rearOf(truck)
                    arrow(rear)
                    if not cache.vehicle and #(me - rear) < 2.4 then
                        show(L('prompt_supply_unload', r.stored + 1, r.crates))
                        if IsControlJustPressed(0, Config.Keys.Interact) then
                            hide()
                            SetVehicleDoorOpen(truck, 2, false, false) SetVehicleDoorOpen(truck, 3, false, false)
                            local ok, n = lib.callback.await('nayzeee-tuning:supply:unload', false, VehToNet(truck))
                            if ok then pickUp(r) else Notify(n or L('failed'), 'error') end
                        end
                    else hide() end
                end
            end
            Wait(sleep)
        end
        Bridge.TextUI(false)
    end)
end

RegisterNetEvent('nayzeee-tuning:supplyEnd', function() cleanup() end)

RegisterCommand('cancelsupply', function()
    if not Supply.active then return end
    local ok, fee = lib.callback.await('nayzeee-tuning:supply:cancel', false)
    cleanup()
    if ok then Notify(L('supply_cancelled', fee), 'inform') end
end, false)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() or not Supply.active then return end
    local truck = Supply.active.ownTruck
    cleanup()
    -- cleanup() parks the van from a thread, which never runs while the resource stops
    if truck and DoesEntityExist(truck) and GetVehiclePedIsIn(cache.ped, false) ~= truck then DeleteEntity(truck) end
end)
