--[[
    A deal in progress: the meet blip, the buyer (on foot, or pulling up in a
    car), and the handover cinematic.

    The server settles the deal the moment the handover starts, then this plays
    it out: you walk up, hand the pair over, they look it over, and either pay
    and leave, or catch a fake, hand it back and storm off.
]]

Selling = {}

local CIN, LINES = Config.Cinematic, Config.Cinematic.Lines
local deal, blip, buyer, car, arrived, spawned
local BAG = `prop_paper_bag_small`
local ENVELOPE = `prop_cash_envelope_01`
local INSPECT = { 'amb@world_human_clipboard@male@idle_a', 'idle_c' }
local NO_WAY = { 'gestures@m@standing@casual', 'gesture_no_way' }
local L_HAND = 18905

local function meetOf(d) return vector3(d.meet.x, d.meet.y, d.meet.z) end
local function groundZ(x, y, z)
    local ok, gz = GetGroundZFor_3dCoord(x, y, z + 2.0, false)
    return ok and gz or z
end

local function setupPed(ped)
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCanRagdollFromPlayerImpact(ped, false)
    SetPedKeepTask(ped, true)
    SetEntityInvincible(ped, true)
end

local function hud(on)
    if not on or not deal then return SendNUIMessage({ action = 'deal', data = false }) end
    local o = deal.offer
    local dist = #(GetEntityCoords(PlayerPedId()) - meetOf(deal))
    SendNUIMessage({ action = 'deal', data = {
        buyer = o.buyer.name, type = o.buyer.label, pair = o.pair, image = o.image, size = o.size, price = o.price,
        meet = deal.meet.label, distance = math.floor(dist),
        left = math.max(0, math.floor((deal.endsAt - GetGameTimer()) / 1000)),
        status = arrived and Config.Text.buyerArrived:format(o.buyer.name) or (o.buyer.drive and Config.Text.driveUp or Config.Text.walkUp),
    } })
end

--- Let the buyer go: drive or walk off, then the game cleans them up
local function releaseBuyer(leave)
    local b, c = buyer, car
    buyer, car, arrived, spawned = nil, nil, false, false
    if not b or not DoesEntityExist(b) then return end
    Cine.Control(b, 800)
    if c then Cine.Control(c, 800) end
    Target.RemoveEntity(b)
    if leave then
        if c and DoesEntityExist(c) then
            if not IsPedInVehicle(b, c, false) then SetPedIntoVehicle(b, c, -1) end
            SetVehicleEngineOn(c, true, true, false)
            TaskVehicleDriveWander(b, c, 20.0, 786603)
        else
            TaskWanderStandard(b, 10.0, 10)
        end
    end
    SetEntityInvincible(b, false)
    SetPedKeepTask(b, false)
    SetPedAsNoLongerNeeded(b)
    if c and DoesEntityExist(c) then SetVehicleAsNoLongerNeeded(c) end
end

local function cleanup(leave)
    if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
    blip = nil
    deal = nil
    hud(false)
    releaseBuyer(leave)
end

--------------------------------------------------------------------------------
-- The buyer shows up
--------------------------------------------------------------------------------

local function ready(d)
    if deal ~= d or not buyer then return end
    arrived = true
    TaskTurnPedToFaceEntity(buyer, PlayerPedId(), 1500)
    SetTimeout(1600, function()
        if buyer and deal == d then TaskStartScenarioInPlace(buyer, d.idle, 0, true) end
    end)
    Target.AddEntity(buyer, {
        { name = 'nzs_deal', label = Config.Text.makeDeal, icon = 'fa-solid fa-handshake',
          canInteract = function() return deal == d and arrived and not Busy end,
          onSelect = function() Selling.Handover() end },
    }, 2.5)
    UI.Notify(Config.Text.buyerArrived:format(d.offer.buyer.name), 'inform')
end

local function spawnWalker(d, m)
    local hash = GetHashKey(d.ped)
    if not LoadModel(hash) then spawned = false return end   -- try again next second
    buyer = CreatePed(4, hash, m.x, m.y, groundZ(m.x, m.y, m.z), d.meet.w or 0.0, true, false)
    SetModelAsNoLongerNeeded(hash)
    setupPed(buyer)
    TaskStartScenarioInPlace(buyer, d.idle, 0, true)
    -- they're "here" once you walk up (the deal loop calls ready)
end

local function spawnDriver(d, m)
    local found, node, heading = GetNthClosestVehicleNodeWithHeading(m.x, m.y, m.z, 30, 1, 3.0, 0)
    local carHash, pedHash = GetHashKey(d.car), GetHashKey(d.ped)
    if not found or not LoadModel(carHash) or not LoadModel(pedHash) then
        d.car = nil
        return spawnWalker(d, m)
    end
    car = CreateVehicle(carHash, node.x, node.y, node.z, heading, true, false)
    SetModelAsNoLongerNeeded(carHash)
    SetEntityAsMissionEntity(car, true, true)
    SetVehicleOnGroundProperly(car)
    SetVehicleEngineOn(car, true, true, false)
    buyer = CreatePedInsideVehicle(car, 4, pedHash, -1, true, false)
    SetModelAsNoLongerNeeded(pedHash)
    setupPed(buyer)
    TaskVehicleDriveToCoordLongrange(buyer, car, m.x, m.y, m.z, 14.0, 786603, 8.0)
    UI.Notify(Config.Text.buyerOnWay:format(d.offer.buyer.name), 'inform')

    CreateThread(function()
        local timeout = GetGameTimer() + 60000
        while deal == d and buyer and DoesEntityExist(car) do
            if #(GetEntityCoords(car) - m) < 12.0 then break end
            if GetGameTimer() > timeout then
                SetEntityCoords(car, m.x, m.y, groundZ(m.x, m.y, m.z), false, false, false, false)   -- stuck in traffic
                break
            end
            Wait(500)
        end
        if deal ~= d or not buyer then return end
        TaskVehicleTempAction(buyer, car, 27, 2500)
        Wait(1500)
        SetVehicleEngineOn(car, false, false, true)
        TaskLeaveVehicle(buyer, car, 0)
        local t = GetGameTimer() + 5000
        while buyer and IsPedInAnyVehicle(buyer, false) and GetGameTimer() < t do Wait(100) end
        ready(d)
    end)
end

local function spawnBuyer(d)
    spawned = true
    local m = meetOf(d)
    if d.car then spawnDriver(d, m) else spawnWalker(d, m) end
end

--------------------------------------------------------------------------------
-- Deal start / end
--------------------------------------------------------------------------------

RegisterNetEvent('nayzeee-sneakers:client:deal', function(d)
    cleanup(false)
    deal = d
    d.endsAt = GetGameTimer() + (d.left or Config.Selling.DealTime) * 1000
    local m = meetOf(d)
    blip = AddBlipForCoord(m.x, m.y, m.z)
    SetBlipSprite(blip, Config.Selling.Blip.sprite)
    SetBlipColour(blip, Config.Selling.Blip.colour)
    SetBlipRoute(blip, true)
    SetBlipRouteColour(blip, Config.Selling.Blip.colour)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(('%s · %s'):format(d.offer.buyer.name, d.meet.label))
    EndTextCommandSetBlipName(blip)
    UI.Notify(Config.Text.dealSet:format(d.offer.buyer.name, d.meet.label), 'success')

    CreateThread(function()
        while deal == d do
            local dist = #(GetEntityCoords(PlayerPedId()) - m)
            if not spawned and dist < 150.0 then spawnBuyer(d) end
            if spawned and buyer and not d.car and not arrived and dist < 30.0 then ready(d) end
            if not Cine.on then hud(true) end
            Wait(1000)
        end
    end)
end)

RegisterNetEvent('nayzeee-sneakers:client:dealEnd', function(reason)
    if reason == 'cancelled' then UI.Notify(Config.Text.dealCancelled, 'inform') end
    cleanup(true)
end)

function Selling.GPS()
    if not deal then return end
    SetNewWaypoint(deal.meet.x, deal.meet.y)
end

--------------------------------------------------------------------------------
-- The handover
--------------------------------------------------------------------------------

local function flatDir(from, to)
    local d = to - from
    local len = math.max(0.01, math.sqrt(d.x * d.x + d.y * d.y))
    return vector3(d.x / len, d.y / len, 0.0)
end

local function playOn(ped, a, flag, ms)
    if LoadAnimDict(a[1]) then TaskPlayAnim(ped, a[1], a[2], 4.0, -4.0, ms or -1, flag or 49, 0.0, false, false, false) end
end

local function cinematic(d, res)
    local ped, b = PlayerPedId(), buyer
    local name = d.offer.buyer.name
    local itemModel = res.boxed and Config.BoxTypes[res.box] and Config.BoxTypes[res.box].base or BAG
    local held

    -- networked: another nearby player may own them by now
    Cine.Control(b, 1500)
    if car then Cine.Control(car, 1500) end
    ClearPedTasks(b)
    Cine.Start()
    local cam = Cine.Director()

    -- 1. Wide: you walk up, they meet you halfway
    local a, bb = GetEntityCoords(ped), GetEntityCoords(b)
    local fwd = flatDir(a, bb)
    local side = vector3(-fwd.y, fwd.x, 0.0)
    local mid = (a + bb) / 2
    cam.cut({ pos = Cine.Fixed(mid + side * 5.5 - fwd * 1.5 + vector3(0.0, 0.0, 1.6)), look = Cine.Between(ped, b, 0.4), fov = 44.0 })
    RenderScriptCams(true, true, 700, true, false)
    Cine.Say(name, LINES.greet)
    TaskGoToEntity(ped, b, -1, 1.1, 1.0, 0, 0)
    TaskGoToEntity(b, ped, -1, 1.1, 1.0, 0, 0)
    Cine.WaitFor(function() return #(GetEntityCoords(ped) - GetEntityCoords(b)) < 1.5 end, 7000)

    -- 2. Two-shot: the pair changes hands
    if not Cine.skip then
        ClearPedTasks(ped)
        ClearPedTasks(b)
        a, bb = GetEntityCoords(ped), GetEntityCoords(b)
        mid = (a + bb) / 2
        fwd = flatDir(a, bb)
        side = vector3(-fwd.y, fwd.x, 0.0)
        cam.go({ pos = Cine.Fixed(mid + side * 2.2 + vector3(0.0, 0.0, 0.55)), look = Cine.Fixed(mid + vector3(0.0, 0.0, 0.25)), fov = 38.0, speed = 0.06 })
        TaskTurnPedToFaceEntity(ped, b, 700)
        TaskTurnPedToFaceEntity(b, ped, 700)
        Wait(750)
        held = Cine.HandItem(itemModel, ped, b, true)
    end

    -- 3. Close-up over your shoulder while they look it over
    if not Cine.skip and res.checked then
        if held then
            DetachEntity(held, true, false)
            AttachEntityToEntity(held, b, GetPedBoneIndex(b, L_HAND), 0.16, 0.06, 0.04, -70.0, 10.0, 0.0, true, true, false, true, 1, true)
        end
        playOn(b, INSPECT, 49)
        local over = GetEntityCoords(ped) + fwd * 0.25 + side * 0.55 + vector3(0.0, 0.0, 0.62)
        cam.go({ pos = Cine.Fixed(over), look = function() return GetPedBoneCoords(b, L_HAND, 0.0, 0.0, 0.0) + vector3(0.0, 0.0, 0.1) end, fov = 30.0, speed = 0.025 })
        Cine.Say(name, LINES.check)
        Cine.Sleep(2800)
        if res.serial then
            Cine.Say(name, LINES.serial)
            Cine.Sleep(1900)
        end
        ClearPedTasks(b)
    end

    -- 4. The verdict
    if not Cine.skip then
        cam.go({ pos = Cine.Fixed(mid + side * 2.4 + vector3(0.0, 0.0, 0.6)), look = Cine.Fixed(mid + vector3(0.0, 0.0, 0.3)), fov = 40.0, speed = 0.05 })
        if res.verdict == 'sold' then
            Cine.Say(name, LINES.pass)
            if held then DeleteEntity(held) held = nil end
            Wait(500)
            Cine.HandItem(ENVELOPE, b, ped)
            PlaySoundFrontend(-1, 'LOCAL_PLYR_CASH_COUNTER_COMPLETE', 'DLC_HEISTS_GENERAL_FRONTEND_SOUNDS', true)
        else
            Cine.Say(name, LINES.fake)
            playOn(b, NO_WAY, 48, 1800)
            Cine.Sleep(1600)
            if held then DeleteEntity(held) held = nil end
            Cine.HandItem(itemModel, b, ped)
            PlaySoundFrontend(-1, 'CHECKPOINT_MISSED', 'HUD_MINI_GAME_SOUNDSET', true)
            if res.police then
                SendNUIMessage({ action = 'subtitle', who = name, text = Config.Text.copsCalled })
                TaskStartScenarioInPlace(b, 'WORLD_HUMAN_STAND_MOBILE', 0, true)
                Cine.Sleep(1800)
            end
        end
    end

    -- 5. They leave: the camera stays put and follows them
    if not Cine.skip then
        ClearPedTasks(b)
        if car and DoesEntityExist(car) then
            cam.go({ pos = Cine.Fixed(GetOffsetFromEntityInWorldCoords(car, 3.2, -7.0, 1.6)), look = function() return GetEntityCoords(b) + vector3(0.0, 0.0, 0.3) end, fov = 44.0, speed = 0.035 })
            TaskEnterVehicle(b, car, 10000, -1, 1.5, 1, 0)
            Cine.WaitFor(function() return IsPedInVehicle(b, car, false) end, 9000)
            if not Cine.skip then
                if not IsPedInVehicle(b, car, false) then SetPedIntoVehicle(b, car, -1) end
                cam.go({ pos = Cine.Fixed(GetOffsetFromEntityInWorldCoords(car, 4.0, 6.5, 1.3)), look = Cine.At(car, 0.0, 0.0, 0.5), fov = 40.0, speed = 0.03 })
                SetVehicleEngineOn(car, true, true, false)
                Wait(600)
                TaskVehicleDriveWander(b, car, res.verdict == 'sold' and 18.0 or 30.0, 786603)
                local start = GetEntityCoords(car)
                Cine.WaitFor(function() return #(GetEntityCoords(car) - start) > 35.0 end, 7000)
            end
        else
            local away = GetEntityCoords(b) + flatDir(GetEntityCoords(ped), GetEntityCoords(b)) * 25.0
            TaskGoStraightToCoord(b, away.x, away.y, away.z, res.verdict == 'sold' and 1.0 or 2.0, 10000, 0.0, 0.5)
            cam.go({ pos = Cine.Fixed(GetEntityCoords(ped) - fwd * 1.2 + side * 1.0 + vector3(0.0, 0.0, 0.9)), look = function() return GetEntityCoords(b) + vector3(0.0, 0.0, 0.4) end, fov = 42.0, speed = 0.03 })
            Cine.Sleep(4500)
        end
    end

    if held and DoesEntityExist(held) then
        local h = held
        SetTimeout(20000, function() if DoesEntityExist(h) then DeleteEntity(h) end end)
    end
    cam.stop()
    Cine.Stop()
    ClearPedTasks(ped)
end

--- Quick version when Config.Cinematic.Enabled is off
local function plain(d, res)
    local ped, b = PlayerPedId(), buyer
    Cine.Control(b, 1500)
    TaskTurnPedToFaceEntity(ped, b, 700)
    TaskTurnPedToFaceEntity(b, ped, 700)
    Wait(750)
    Cine.HandItem(res.boxed and Config.BoxTypes[res.box] and Config.BoxTypes[res.box].base or BAG, ped, b)
    if res.verdict == 'sold' then Cine.HandItem(ENVELOPE, b, ped) end
end

function Selling.Handover()
    if Busy or not deal or not buyer then return end
    Busy = true
    local d = deal
    local res = lib.callback.await('nayzeee-sneakers:handover', false, d.id)
    if not res then Busy = false return end

    hud(false)
    if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
    blip = nil
    Target.RemoveEntity(buyer)
    deal = nil

    if CIN.Enabled then cinematic(d, res) else plain(d, res) end

    local sold = res.verdict == 'sold'
    SendNUIMessage({ action = 'banner', data = {
        kind = sold and 'success' or 'fail',
        title = sold and Config.Text.bnSold or Config.Text.bnCaught,
        subtitle = sold and res.pair or Config.Text.caught:format(res.buyer),
        stats = {
            { Config.Text.bnOffer, '$' .. lib.math.groupdigits(res.price) },
            { Config.Text.bnPaid, sold and ('$' .. lib.math.groupdigits(res.price)) or '—' },
            { Config.Text.bnRep, (res.rep >= 0 and '+' or '') .. res.rep },
            { Config.Text.bnXP, '+' .. (res.xp or 0) },
        },
    } })
    if sold then UI.Notify(Config.Text.sold:format(lib.math.groupdigits(res.price)), 'success') end

    -- a buyer who caught a fake might come at you
    local b = buyer
    if res.aggressive and b and DoesEntityExist(b) then
        releaseBuyer(false)
        SetPedFleeAttributes(b, 0, false)
        SetPedCombatAttributes(b, 46, true)
        TaskCombatPed(b, PlayerPedId(), 0, 16)
    else
        releaseBuyer(true)
    end
    Busy = false
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if buyer and DoesEntityExist(buyer) then DeleteEntity(buyer) end
    if car and DoesEntityExist(car) then DeleteEntity(car) end
    if blip and DoesBlipExist(blip) then RemoveBlip(blip) end
    if Cine.on then Cine.Stop() RenderScriptCams(false, false, 0, true, false) end
end)
