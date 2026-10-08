-- The Hair Plug phone app: NUI callbacks (shared by every phone and the on-screen fallback)
-- and the meet-up buyer who runs to you.

local CP = Config.Phone
local MU = CP.Meetup

Phone = { ped = nil }

-- app callbacks ------------------------------------------------------------------------------------

RegisterNUICallback('phoneData', function(_, cb)
    local d = lib.callback.await('nz-wig:phone', false)
    if d then d.palette = HairPalette() end
    cb(d or false)
end)

local function reply(cb, ok, msg)
    if msg then PhoneBridge.Notify(msg, ok and 'success' or 'error') end
    cb({ ok = ok == true, msg = msg })
end

RegisterNUICallback('phoneQuickSell', function(d, cb)
    reply(cb, lib.callback.await('nz-wig:phoneQuickSell', false, d and d.keys))
end)

RegisterNUICallback('phoneMeetup', function(d, cb)
    if IsPedInAnyVehicle(PlayerPedId(), false) then return reply(cb, false, L('meetup_vehicle')) end
    reply(cb, lib.callback.await('nz-wig:phoneMeetup', false, d and d.keys))
end)

RegisterNUICallback('phoneList', function(d, cb)
    reply(cb, lib.callback.await('nz-wig:phoneList', false, d and d.key, d and d.price))
end)

RegisterNUICallback('phoneBuy', function(d, cb)
    reply(cb, lib.callback.await('nz-wig:phoneBuy', false, d and d.id))
end)

RegisterNUICallback('phoneCancel', function(d, cb)
    reply(cb, lib.callback.await('nz-wig:phoneCancel', false, d and d.id))
end)

RegisterNUICallback('phoneOrder', function(d, cb)
    reply(cb, lib.callback.await('nz-wig:phoneOrder', false, d and d.order, d and d.key))
end)

RegisterNUICallback('phoneOrderFits', function(d, cb)
    cb(lib.callback.await('nz-wig:phoneOrderFits', false, d and d.order) or {})
end)

-- on-screen fallback (and for servers without a phone) -------------------------------------------------

local function openApp()
    if Snatch.busy then return CB.Notify(L('busy'), 'error') end
    NUI.Open('phone', { name = CP.AppName })
end

if CP.Enabled and CP.Command then
    RegisterCommand(CP.Command, openApp, false)
    if CP.Keybind then RegisterKeyMapping(CP.Command, 'Open ' .. CP.AppName, 'keyboard', CP.Keybind) end
end
exports('OpenHairPlug', openApp)

-- meet-up buyer -----------------------------------------------------------------------------------------------

local HAND_OPT = { { name = 'nzwig_handover', label = 'Hand Over', icon = 'fa-solid fa-sack-dollar', distance = 2.5 } }

local function despawn(walkAway)
    local ped = Phone.ped
    Phone.ped = nil
    TriggerServerEvent('nz-wig:s:meetupGone')
    PhoneBridge.Send({ type = 'refresh' })
    if not ped or not DoesEntityExist(ped) then return end
    if CB.Target ~= 'none' then CB.RemoveLocalEntity(ped, HAND_OPT) end
    if walkAway then
        FreezeEntityPosition(ped, false)
        TaskWanderStandard(ped, 10.0, 10)
        SetTimeout(8000, function() if DoesEntityExist(ped) then DeleteEntity(ped) end end)
    else
        DeleteEntity(ped)
    end
end

local function handOver()
    local ok, msg = lib.callback.await('nz-wig:meetupHandover', false)
    CB.Notify(msg or L('invalid'), ok and 'success' or 'error')
    if ok then
        local me = PlayerPedId()
        PlayAnim({ dict = 'mp_common', clip = 'givetake1_a', flag = 48 }, 1500)
        if Phone.ped then PlayAnim({ dict = 'mp_common', clip = 'givetake1_b', flag = 48 }, 1500, Phone.ped) end
        NUI.Send('cash')
        SetTimeout(1600, function() despawn(true) end)
        FaceEntity(me, Phone.ped or me)
    end
end

local function spawnPoint(me)
    local mc = GetEntityCoords(me)
    for _ = 1, 8 do
        local ang = math.random() * math.pi * 2
        local x, y = mc.x + math.cos(ang) * MU.SpawnDistance, mc.y + math.sin(ang) * MU.SpawnDistance
        local ok, z = GetGroundZFor_3dCoord(x, y, mc.z + 30.0, false)
        if ok and math.abs(z - mc.z) < 8.0 then return vec3(x, y, z) end
    end
    local f = GetOffsetFromEntityInWorldCoords(me, 0.0, -12.0, 0.0)
    return vec3(f.x, f.y, mc.z - 1.0)
end

local function keyLoop(ped)
    CreateThread(function()
        local shown = false
        while Phone.ped == ped and DoesEntityExist(ped) do
            local d = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(ped))
            if d < 2.2 and not NUI.app then
                if not shown then lib.showTextUI('[E] ' .. HAND_OPT[1].label) shown = true end
                if IsControlJustReleased(0, 38) then handOver() end
                Wait(0)
            else
                if shown then lib.hideTextUI() shown = false end
                Wait(400)
            end
        end
        if shown then lib.hideTextUI() end
    end)
end

RegisterNetEvent('nz-wig:c:meetupStart', function()
    if Phone.ped then return end
    CreateThread(function()
        local me = PlayerPedId()
        if not pcall(lib.requestModel, MU.Model, 3000) then return despawn(false) end
        local p = spawnPoint(me)
        local ped = CreatePed(4, MU.Model, p.x, p.y, p.z, 0.0, false, true)
        SetModelAsNoLongerNeeded(MU.Model)
        Phone.ped = ped
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetEntityInvincible(ped, true)
        SetPedCanRagdollFromPlayerImpact(ped, false)
        SetPedFleeAttributes(ped, 0, false)

        TaskGoToEntity(ped, PlayerPedId(), -1, 1.6, MU.RunSpeed, 1073741824.0, 0)
        local started = GetGameTimer()
        while Phone.ped == ped and DoesEntityExist(ped) do
            if #(GetEntityCoords(ped) - GetEntityCoords(PlayerPedId())) < 2.6 then break end
            if GetGameTimer() - started > 60000 then
                CB.Notify(L('buyer_lost'), 'error')
                return despawn(false)
            end
            Wait(300)
        end
        if Phone.ped ~= ped then return end

        ClearPedTasks(ped)
        TaskTurnPedToFaceEntity(ped, PlayerPedId(), 1500)
        Wait(1500)
        FreezeEntityPosition(ped, true)
        TriggerServerEvent('nz-wig:s:meetupArrived')
        if MU.Greeting then NUI.Send('speech', { text = MU.Greeting }) end
        PhoneBridge.Notify(L('buyer_arrived'), 'success')
        PhoneBridge.Send({ type = 'refresh' })

        if CB.Target ~= 'none' then
            CB.AddLocalEntity(ped, { { name = HAND_OPT[1].name, label = HAND_OPT[1].label, icon = HAND_OPT[1].icon, distance = 2.5, onSelect = handOver } })
        else
            keyLoop(ped)
        end

        SetTimeout(MU.WaitTime * 1000, function()
            if Phone.ped == ped then
                CB.Notify(L('buyer_left'), 'info')
                despawn(true)
            end
        end)
    end)
end)

function Phone.Cleanup()
    if Phone.ped and DoesEntityExist(Phone.ped) then DeleteEntity(Phone.ped) end
end
