-----------------------------------------------------------------
-- Sale delivery: drive to the buyer, every hit drops the price
-----------------------------------------------------------------
Sell = {}
local handlers = Client.Handlers
local D = Config.Selling.Damage

local WEAPON_RAMMED = joaat('WEAPON_RAMMED_BY_CAR')
local WEAPON_RUNOVER = joaat('WEAPON_RUN_OVER_BY_CAR')

local active  -- current sale mission (also the gate for the damage event)

local function v3(t) return vec3(t.x, t.y, t.z) end

local function hud(m, extra)
    local data = {
        mode = 'sell', label = m.data.label, rarity = m.data.rarity, buyer = m.data.buyer, illegal = m.data.illegal,
        attack = m.lastCombat and (GetGameTimer() - m.lastCombat < 15000) or false,
        offer = m.offer, agreed = m.data.offer, minOffer = m.data.minOffer, counts = m.counts,
        remaining = math.max(0, math.floor((m.expiresAt - GetGameTimer()) / 1000)),
        objective = m.objective, health = m.health,
    }
    if extra then for k, v in pairs(extra) do data[k] = v end end
    Client.Send('hud', data)
end

local dropBuyer
local function cleanup(m)
    m.done = true
    if active == m then active = nil end
    if dropBuyer then dropBuyer(m) end
    for _, b in pairs(m.blips) do if DoesBlipExist(b) then RemoveBlip(b) end end
    if m.point then m.point:remove() end
    if m.buyerPoint then m.buyerPoint:remove() m.buyerPoint = nil end
    Scenarios.Release(m.peds)
    Bridge.HideText()
    Client.Send('hud', { mode = 'none' })
    if Client.mission == m then Client.mission = nil end
end

local function healthOf(veh)
    return math.max(0.0, GetVehicleBodyHealth(veh)) + math.max(0.0, GetVehicleEngineHealth(veh))
end

-----------------------------------------------------------------
-- Damage recording. One crash = one hit (debounced).
-----------------------------------------------------------------
local function record(m, kind)
    local now = GetGameTimer()
    if now - (m.lastHit or 0) < D.debounce then
        -- upgrade a hit that turned out to be a ram or a shot in the same window
        if m.lastKind == 'hit' and kind ~= 'hit' then m.lastKind = kind end
        return
    end
    local veh = m.vehicle
    if not veh or not DoesEntityExist(veh) then return end
    local h = healthOf(veh)
    local lost = math.max(0.0, (m.lastHealth or h) - h)
    m.lastHealth = h
    if kind == 'hit' and lost < D.minHealthDrop then return end
    m.lastHit, m.lastKind = now, kind

    -- show the drop straight away, the server answer corrects it
    local def = D[kind]
    local pct = def.pct + (lost / 100) * D.severityPer100
    m.counts[kind] = (m.counts[kind] or 0) + 1
    m.offer = math.max(math.floor(m.offer * (1 - pct / 100)), m.data.minOffer)
    m.health = math.floor(h / 20)
    hud(m, { flash = { kind = kind, label = def.label, pct = Cargo.Round(pct * 10) / 10 } })

    lib.callback('nz_cargo:sell:damage', false, function(res)
        if res and active == m then
            m.offer = res.offer
            m.counts = res.counts
            hud(m)
        end
    end, m.id, kind, lost)
end

AddEventHandler('gameEventTriggered', function(name, args)
    if not active or name ~= 'CEventNetworkEntityDamage' then return end
    local m = active
    local victim, attacker, weapon = args[1], args[2], args[7]
    if victim ~= m.vehicle then return end
    local kind = 'hit'
    local dmgType = weapon and weapon ~= 0 and GetWeaponDamageType(weapon) or 0
    if dmgType == 5 then
        kind = 'explosion'
    elseif dmgType == 3 then
        kind = 'shot'
    elseif weapon == WEAPON_RAMMED or (attacker and attacker ~= 0 and attacker ~= m.vehicle and DoesEntityExist(attacker) and IsEntityAVehicle(attacker)) then
        kind = 'rammed'
    elseif weapon == WEAPON_RUNOVER then
        kind = 'hit'
    end
    record(m, kind)
end)

-----------------------------------------------------------------
-- Start
-----------------------------------------------------------------
local function spawnAttack(m, plan)
    SetTimeout((plan.delay or 30) * 1000, function()
        if active ~= m or m.done then return end
        local made = Scenarios.Chasers(Config.Attackers, plan.cars or 1, 'ram')
        for _, e in ipairs(made) do m.peds[#m.peds + 1] = e end
        local ids = Scenarios.NetIds(made)
        if #ids > 0 then lib.callback.await('nz_cargo:sell:peds', false, m.id, ids) end
        Music.Play('attack')
        m.lastCombat = GetGameTimer()
        Bridge.Notify(L('sell_rivals'), 'error', 'Attackers')
    end)
end

-----------------------------------------------------------------
-- The buyer waits at the drop, killing time, before you arrive
-----------------------------------------------------------------
local IDLE = Config.Selling.Cutscene.Idle or { 'WORLD_HUMAN_SMOKING', 'WORLD_HUMAN_STAND_MOBILE', 'WORLD_HUMAN_AA_COFFEE', 'WORLD_HUMAN_HANG_OUT_STREET', 'WORLD_HUMAN_GUARD_STAND' }

local function spawnBuyer(m)
    if m.buyerPed and DoesEntityExist(m.buyerPed) then return m.buyerPed end
    local d = m.data
    local hash = Client.LoadModel(d.buyerModel or 'a_m_y_business_03')
    if not hash then return nil end
    -- beside the drop, on the passenger side of where you pull up
    local drop = d.drop
    local h = math.rad(drop.w or 0.0)
    local x, y = drop.x + math.cos(h) * 3.4, drop.y + math.sin(h) * 3.4
    local ok, gz = GetGroundZFor_3dCoord(x, y, drop.z + 1.5, false)
    local ped = CreatePed(4, hash, x, y, ok and gz or drop.z, GetHeadingFromVector_2d(drop.x - x, drop.y - y), true, true)
    SetModelAsNoLongerNeeded(hash)
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedCanRagdollFromPlayerImpact(ped, false)
    SetEntityInvincible(ped, true)
    TaskStartScenarioInPlace(ped, IDLE[math.random(1, #IDLE)], 0, true)
    m.buyerPed = ped
    return ped
end

dropBuyer = function(m)
    if m.handedOver then return end   -- the cutscene still needs them
    if m.buyerPed and DoesEntityExist(m.buyerPed) then DeleteEntity(m.buyerPed) end
    m.buyerPed = nil
end

-----------------------------------------------------------------
-- Handover cinematic: get out, keys for cash, buyer drives off.
-- One scripted camera steered by hand every frame: its position
-- glides to the shot and it always looks at the current subject,
-- so the drive-off shot follows the car instead of a fixed spot.
-----------------------------------------------------------------
local function waitUntil(fn, ms)
    local t = GetGameTimer() + ms
    while not fn() and GetGameTimer() < t do Wait(50) end
end

local function control(ent, ms)
    if not ent or not DoesEntityExist(ent) then return false end
    local t = GetGameTimer() + (ms or 1000)
    while not NetworkHasControlOfEntity(ent) and GetGameTimer() < t do
        NetworkRequestControlOfEntity(ent)
        Wait(25)
    end
    return NetworkHasControlOfEntity(ent)
end

local function handItem(model, from, to)
    local hash = Client.LoadModel(model)
    local obj = hash and CreateObject(hash, 0.0, 0.0, 0.0, true, true, false)
    if hash then SetModelAsNoLongerNeeded(hash) end
    if obj then AttachEntityToEntity(obj, from, GetPedBoneIndex(from, 57005), 0.12, 0.02, -0.03, 0.0, 0.0, 0.0, true, true, false, true, 1, true) end
    TaskPlayAnim(from, 'mp_common', 'givetake1_a', 8.0, -8.0, 1800, 49, 0, false, false, false)
    TaskPlayAnim(to, 'mp_common', 'givetake1_b', 8.0, -8.0, 1800, 49, 0, false, false, false)
    Wait(900)
    if obj then
        DetachEntity(obj, true, false)
        AttachEntityToEntity(obj, to, GetPedBoneIndex(to, 57005), 0.12, 0.02, -0.03, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
    end
    Wait(900)
    if obj and DoesEntityExist(obj) then DeleteEntity(obj) end
end

local function lookRot(from, to)
    local d = to - from
    local flat = math.sqrt(d.x * d.x + d.y * d.y)
    return math.deg(math.atan(d.z, flat)), -math.deg(math.atan(d.x, d.y))
end

-- shot = { pos = fn() -> vector3, look = fn() -> vector3, fov, speed (0..1 per frame) }
local function director()
    local self = { cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true), on = true }
    function self.cut(shot)
        self.shot = shot
        self.p, self.l = shot.pos(), shot.look()
    end
    function self.go(shot) self.shot = shot end
    CreateThread(function()
        while self.on do
            local sh = self.shot
            if sh then
                local wp, wl = sh.pos(), sh.look()
                if wp and wl then
                    local k = sh.speed or 0.05
                    self.p = self.p and (self.p + (wp - self.p) * k) or wp
                    self.l = self.l and (self.l + (wl - self.l) * math.min(1.0, k * 2.5)) or wl
                    SetCamCoord(self.cam, self.p.x, self.p.y, self.p.z)
                    local pitch, yaw = lookRot(self.p, self.l)
                    SetCamRot(self.cam, pitch, 0.0, yaw, 2)
                    SetCamFov(self.cam, sh.fov or 42.0)
                end
            end
            Wait(0)
        end
    end)
    function self.stop()
        self.on = false
        RenderScriptCams(false, true, 1100, true, false)
        DestroyCam(self.cam, false)
    end
    return self
end

local function at(ent, x, y, z) return function() return DoesEntityExist(ent) and GetOffsetFromEntityInWorldCoords(ent, x, y, z) or nil end end
local function fixed(v) return function() return v end end

local function cutscene(m)
    local d, veh, ped = m.data, m.vehicle, cache.ped
    if not d.cutscene or not veh or not DoesEntityExist(veh) then return end
    local buyer = spawnBuyer(m)
    if not buyer then return end
    m.handedOver = true

    local cine, skip = true, false
    CreateThread(function()
        while cine do
            DisableAllControlActions(0)
            EnableControlAction(0, 249, true) -- push to talk
            if IsDisabledControlJustPressed(0, 191) or IsDisabledControlJustPressed(0, 177) then skip = true end
            Wait(0)
        end
    end)
    Client.Send('cine', { on = true })
    DisplayRadar(false)
    control(veh, 1500)
    SetVehicleDoorsLocked(veh, 1)
    SetVehicleDoorsLockedForAllPlayers(veh, false)
    SetVehicleEngineOn(veh, false, false, true)
    ClearPedTasks(buyer)

    local cam = director()
    -- 1. Wide shot from the front corner: you get out
    local wide = GetOffsetFromEntityInWorldCoords(veh, -5.5, 7.5, 2.2)
    cam.cut({ pos = fixed(wide), look = at(veh, 0.0, 0.0, 0.4), fov = 42.0 })
    RenderScriptCams(true, true, 700, true, false)
    TaskTurnPedToFaceEntity(buyer, veh, 1500)
    TaskLeaveVehicle(ped, veh, 0)
    waitUntil(function() return skip or not IsPedInAnyVehicle(ped, false) end, 3500)

    -- 2. You walk over, the buyer meets you halfway
    if not skip then
        cam.go({ pos = fixed(wide), look = function() return (GetEntityCoords(ped) + GetEntityCoords(buyer)) / 2 + vec3(0.0, 0.0, 0.4) end, fov = 40.0, speed = 0.04 })
        TaskGoToEntity(ped, buyer, -1, 1.1, 1.0, 0, 0)
        TaskGoToEntity(buyer, ped, -1, 1.1, 1.0, 0, 0)
        waitUntil(function() return skip or #(GetEntityCoords(ped) - GetEntityCoords(buyer)) < 1.5 end, 7000)
    end

    -- 3. Close two-shot: keys one way, envelope of cash the other
    if not skip then
        ClearPedTasks(ped)
        ClearPedTasks(buyer)
        local a, b = GetEntityCoords(ped), GetEntityCoords(buyer)
        local mid = (a + b) / 2
        local side = vec3(-(b.y - a.y), b.x - a.x, 0.0)
        local len = math.max(0.01, #side)
        local two = mid + side / len * 2.2 + vec3(0.0, 0.0, 0.55)
        cam.go({ pos = fixed(two), look = fixed(mid + vec3(0.0, 0.0, 0.25)), fov = 38.0, speed = 0.06 })
        TaskTurnPedToFaceEntity(ped, buyer, 700)
        TaskTurnPedToFaceEntity(buyer, ped, 700)
        Wait(750)
        lib.requestAnimDict('mp_common')
        handItem('p_car_keys_01', ped, buyer)
        if not skip then
            Wait(200)
            handItem('prop_cash_envelope_01', buyer, ped)
            PlaySoundFrontend(-1, 'LOCAL_PLYR_CASH_COUNTER_COMPLETE', 'DLC_HEISTS_GENERAL_FRONTEND_SOUNDS', true)
        end
        RemoveAnimDict('mp_common')
    end

    -- 4. The buyer walks to the car and gets in (camera behind the car looking at him)
    if not skip then
        local behind = GetOffsetFromEntityInWorldCoords(veh, 3.2, -7.0, 1.6)
        cam.go({ pos = fixed(behind), look = function() return GetEntityCoords(buyer) + vec3(0.0, 0.0, 0.3) end, fov = 44.0, speed = 0.035 })
        control(veh, 800)
        TaskEnterVehicle(buyer, veh, 10000, -1, 1.0, 1, 0)
        waitUntil(function() return skip or IsPedInVehicle(buyer, veh, false) end, 9000)
        if not skip and not IsPedInVehicle(buyer, veh, false) then SetPedIntoVehicle(buyer, veh, -1) end

        -- 5. Engine on and away: the camera stays put and turns to follow the car
        if not skip then
            local stand = GetOffsetFromEntityInWorldCoords(veh, 4.0, 6.5, 1.3)
            cam.go({ pos = fixed(stand), look = at(veh, 0.0, 0.0, 0.5), fov = 40.0, speed = 0.03 })
            SetVehicleEngineOn(veh, true, true, false)
            Wait(700)
            TaskVehicleDriveWander(buyer, veh, 20.0, 786603)
            local start = GetEntityCoords(veh)
            waitUntil(function() return skip or #(GetEntityCoords(veh) - start) > 40.0 end, 8000)
        end
    end

    -- 6. Back to you
    cine = false
    cam.stop()
    ClearPedTasks(ped)
    DisplayRadar(true)
    Client.Send('cine', { on = false })
    if DoesEntityExist(buyer) then
        SetEntityInvincible(buyer, false)
        if IsPedInVehicle(buyer, veh, false) then
            if skip then TaskVehicleDriveWander(buyer, veh, 20.0, 786603) end
            SetPedAsNoLongerNeeded(buyer)
        else
            DeleteEntity(buyer)
        end
    end
    m.buyerPed = nil
end

local function deliver(m)
    if m.busy then return end
    m.busy = true
    Bridge.HideText()
    local res = lib.callback.await('nz_cargo:sell:deliver', false, m.id)
    if not res then m.busy = false return end
    if res.waiting then return Sell.Waiting(m, res) end
    local veh = m.vehicle
    m.handedOver = m.data.cutscene and true or false
    cleanup(m)
    m.vehicle = veh
    Music.Stop(true)
    cutscene(m)
    local stats = {
        { 'Agreed', '$' .. lib.math.groupdigits(res.agreed) },
        { 'Damage', ('-%.1f%%'):format(res.penalty) },
        { 'Paid', '$' .. lib.math.groupdigits(res.mine) },
        { 'XP', '+' .. res.xp },
    }
    Client.Send('banner', {
        kind = 'success', title = res.clean and 'Clean Delivery' or 'Vehicle Sold', subtitle = res.label, rarity = res.rarity,
        stats = stats, counts = res.counts, streak = res.streak, cuts = res.cuts, clean = res.clean,
    })
end

function Sell.Run(d)
    local m = {
        kind = 'sell', id = d.id, data = d, offer = d.offer, counts = { hit = 0, rammed = 0, shot = 0, explosion = 0 },
        blips = {}, peds = {}, expiresAt = GetGameTimer() + d.timeLimit * 1000, health = 100,
    }
    m.cancel = function() lib.callback.await('nz_cargo:sell:cancel', false, m.id) end
    Client.mission = m

    Client.Fade(true)
    if Client.inside then Warehouse.Cleanup() end
    local sp = d.spawn
    SetEntityCoords(cache.ped, sp.x + 2.5, sp.y, sp.z, false, false, false, false)
    local veh = Client.NetEntity(d.netId, 10000)
    if not veh then
        Client.Fade(false)
        m.cancel()
        cleanup(m)
        return
    end
    m.vehicle = veh
    if Client.Control(veh, 2000) then
        Bridge.SetProps(veh, d.props)
        SetVehicleOnGroundProperly(veh)
        SetVehicleFixed(veh)
        SetVehicleDirtLevel(veh, 0.0)
    end
    TaskWarpPedIntoVehicle(cache.ped, veh, -1)
    Bridge.GiveKeys(veh)
    Bridge.SetFuel(veh, 100.0)
    Music.RadioOff(veh)
    SetVehicleEngineOn(veh, true, true, false)
    m.lastHealth = healthOf(veh)
    active = m
    Wait(400)
    Client.Fade(false)

    Music.Play('start')
    SetTimeout(6000, function() if active == m and not m.lastCombat then Music.Play('delivering') end end)

    local drop = v3(d.drop)
    m.blips.drop = Client.Blip(drop, 523, 2, d.buyer.name .. ' · ' .. (d.buyer.place or d.buyer.label), true)
    m.objective = d.deal and ('Crew sale: drop your car at %s. Hits only cost this car.'):format(d.buyer.place or d.buyer.name)
        or ('Deliver to %s. Every hit costs you.'):format(d.buyer.name)
    Bridge.Notify(L('sell_started', d.label, d.buyer.name), 'info', 'Sale')
    hud(m)
    if d.attack then spawnAttack(m, d.attack) end

    local radius = d.deal and (Config.CrewSale.DropRadius - 2.0) or 7.0
    local dp = lib.points.new({ coords = drop, distance = 35.0 + radius })
    function dp:nearby()
        if GetVehiclePedIsIn(cache.ped, false) ~= m.vehicle then return end
        DrawMarker(1, drop.x, drop.y, drop.z - 1.0, 0, 0, 0, 0, 0, 0, radius, radius, 1.0, 8, 175, 162, 70, false, false, 2, false, nil, nil, false)
        if self.currentDistance < radius then
            Bridge.ShowText(Config.Interact.KeyLabel, d.deal and 'Drop the car' or 'Deliver to buyer')
            if IsControlJustPressed(0, Config.Interact.Key) and GetEntitySpeed(m.vehicle) < 4.0 then
                CreateThread(function() deliver(m) end)
            end
        else
            Bridge.HideText()
        end
    end
    function dp:onExit() Bridge.HideText() end
    m.point = dp

    -- the buyer is already there waiting when you show up
    if d.cutscene then
        local bp = lib.points.new({ coords = drop, distance = 140.0 })
        function bp:onEnter() if not m.done then spawnBuyer(m) end end
        m.buyerPoint = bp
    end

    -- light watcher: destroyed check, health poll for world collisions, music, countdown
    CreateThread(function()
        local lastHud = 0
        while active == m and not m.done do
            local v = m.vehicle
            if not DoesEntityExist(v) or IsEntityDead(v) or GetVehicleEngineHealth(v) < -3900.0 then
                lib.callback.await('nz_cargo:sell:destroyed', false, m.id)
                break
            end
            local h = healthOf(v)
            if m.lastHealth and (m.lastHealth - h) >= D.minHealthDrop and GetGameTimer() - (m.lastHit or 0) > D.debounce then
                record(m, 'hit')
            elseif h > (m.lastHealth or h) then
                m.lastHealth = h
            end
            m.health = math.floor(h / 20)

            if Scenarios.InCombat(m.peds) then m.lastCombat = GetGameTimer() end
            local remaining = (m.expiresAt - GetGameTimer()) / 1000
            if remaining <= 30 then
                if not m.countdown then m.countdown = true Music.Play('countdown') end
            elseif m.lastCombat and GetGameTimer() - m.lastCombat < 15000 then
                Music.Play('attack')
            elseif m.lastCombat then
                Music.Play('delivering')
            end

            if GetGameTimer() - lastHud > 1000 then
                lastHud = GetGameTimer()
                hud(m, { distance = math.floor(#(GetEntityCoords(v) - drop)) })
            end
            Wait(250)
        end
    end)
end

handlers.sellStart = function(d)
    if Client.mission then Bridge.Notify(L('busy'), 'error') return { ok = false } end
    local data = lib.callback.await('nz_cargo:sell:start', false, d.id, d.buyer)
    if not data then return { ok = false } end
    Laptop.Close(true)
    Client.CloseUI()
    CreateThread(function() Sell.Run(data) end)
    return { ok = true }
end

RegisterNetEvent('nz_cargo:sell:end', function(info)
    local m = Client.mission
    if not m or m.kind ~= 'sell' then return end
    cleanup(m)
    Music.Stop(false)
    if info and info.deal then
        Client.Send('banner', { kind = 'fail', title = 'Car Lost', subtitle = 'The deal goes on. Help the crew finish.' })
    else
        Client.Send('banner', { kind = 'fail', title = 'Sale Failed', subtitle = info and info.reason or '' })
    end
end)

-----------------------------------------------------------------
-- Crew sales: everyone drives one car, one shared handover at the end
-----------------------------------------------------------------
local dealState = {}   -- { done, total, lost }

local function dealHud(m)
    if not m or not m.waiting then return end
    local ds = dealState
    Client.Send('hud', {
        mode = 'sell', label = m.data.label, rarity = m.data.rarity, buyer = m.data.buyer, illegal = m.data.illegal,
        offer = m.final, agreed = m.data.offer, minOffer = m.data.minOffer, counts = m.counts, remaining = 0,
        objective = ('Car dropped. Waiting on the crew · %d of %d in%s'):format(ds.done or 1, ds.total or m.data.deal.cars, (ds.lost or 0) > 0 and (' · %d lost'):format(ds.lost) or ''),
        health = m.health,
    })
end

function Sell.Waiting(m, res)
    -- the price is locked; stop tracking damage and wait for everyone
    m.waiting, m.final = true, res.final
    m.busy = false
    if active == m then active = nil end
    for _, b in pairs(m.blips) do if DoesBlipExist(b) then RemoveBlip(b) end end
    m.blips = {}
    if m.point then m.point:remove() m.point = nil end
    Bridge.HideText()
    dealState = { done = res.done, total = res.total, lost = 0 }
    Bridge.Notify(L('deal_dropped', lib.math.groupdigits(res.final)), 'success', 'Crew Sale')
    Music.Play('delivering')
    dealHud(m)
end

RegisterNetEvent('nz_cargo:crewsale:begin', function(data)
    if Client.mission then return end
    if Laptop.open then Laptop.Close(true) end
    Client.CloseUI()
    CreateThread(function() Sell.Run(data) end)
end)

RegisterNetEvent('nz_cargo:crewsale:progress', function(p)
    dealState = p
    local m = Client.mission
    if m and m.kind == 'sell' and m.waiting then dealHud(m)
    elseif m and m.kind == 'sell' then Bridge.Notify(('%d of %d cars dropped.'):format(p.done, p.total), 'info', 'Crew Sale') end
end)

-- One handover for the whole crew at a single drop. The deal leader's client
-- (the director) brings in the buyer's drivers; everyone else just watches.
local function crewCutscene(d)
    local me = cache.serverId
    local cars = {}
    for _, c in ipairs(d.cars) do
        if not c.lost and c.netId and NetworkDoesEntityExistWithNetworkId(c.netId) then
            local e = NetToVeh(c.netId)
            if e and e ~= 0 and DoesEntityExist(e) then cars[#cars + 1] = { ent = e, c = c } end
        end
    end
    if #cars == 0 or not Config.Selling.Cutscene.Enabled then return end

    if d.mode == 'split' then
        -- everyone hands over their own car at their own drop, all at the same moment
        for _, car in ipairs(cars) do
            if car.c.driver == me then
                cutscene({ data = { cutscene = true, buyerModel = d.buyerModel, drop = car.c.drop }, vehicle = car.ent })
            end
        end
        return
    end

    local center = vec3(0.0, 0.0, 0.0)
    for _, car in ipairs(cars) do center = center + GetEntityCoords(car.ent) end
    center = center / #cars
    if #(GetEntityCoords(cache.ped) - center) > 250.0 then return end

    local cine, skip = true, false
    CreateThread(function()
        while cine do
            DisableAllControlActions(0)
            EnableControlAction(0, 249, true)
            if IsDisabledControlJustPressed(0, 191) or IsDisabledControlJustPressed(0, 177) then skip = true end
            Wait(0)
        end
    end)
    Client.Send('cine', { on = true })
    DisplayRadar(false)
    local veh = GetVehiclePedIsIn(cache.ped, false)
    if veh ~= 0 then TaskLeaveVehicle(cache.ped, veh, 0) end

    local drop = d.cars[1].drop
    local h = math.rad(drop.w or 0.0)
    local fwd, right = vec3(-math.sin(h), math.cos(h), 0.0), vec3(math.cos(h), math.sin(h), 0.0)
    local cam = director()
    cam.cut({ pos = fixed(center + fwd * 13.0 + right * 7.0 + vec3(0.0, 0.0, 4.0)), look = fixed(center + vec3(0.0, 0.0, 0.6)), fov = 48.0 })
    RenderScriptCams(true, true, 700, true, false)

    local isDirector = d.director == me
    local peds = {}
    if isDirector then
        CreateThread(function()
            Wait(2500)   -- let the crew climb out
            local models = Config.Selling.Cutscene.BuyerModels
            for i, car in ipairs(cars) do
                local hash = Client.LoadModel(i == 1 and d.buyerModel or models[math.random(1, #models)])
                if hash then
                    local at = GetOffsetFromEntityInWorldCoords(car.ent, 4.5, -2.0, 0.0)
                    local ok, gz = GetGroundZFor_3dCoord(at.x, at.y, at.z + 1.5, false)
                    local ped = CreatePed(4, hash, at.x, at.y, ok and gz or at.z, GetEntityHeading(car.ent), true, true)
                    SetModelAsNoLongerNeeded(hash)
                    SetBlockingOfNonTemporaryEvents(ped, true)
                    SetEntityInvincible(ped, true)
                    peds[i] = ped
                end
            end
            -- the buyer pays you, his drivers take the keys
            local boss = peds[1]
            if boss then
                TaskGoToEntity(boss, cache.ped, -1, 1.2, 1.0, 0, 0)
                waitUntil(function() return skip or #(GetEntityCoords(boss) - GetEntityCoords(cache.ped)) < 1.6 end, 7000)
                TaskTurnPedToFaceEntity(cache.ped, boss, 700)
                TaskTurnPedToFaceEntity(boss, cache.ped, 700)
                Wait(700)
                lib.requestAnimDict('mp_common')
                handItem('p_car_keys_01', cache.ped, boss)
                handItem('prop_cash_envelope_01', boss, cache.ped)
                PlaySoundFrontend(-1, 'LOCAL_PLYR_CASH_COUNTER_COMPLETE', 'DLC_HEISTS_GENERAL_FRONTEND_SOUNDS', true)
                RemoveAnimDict('mp_common')
            end
            for i, car in ipairs(cars) do
                if peds[i] and control(car.ent, 800) then
                    SetVehicleDoorsLocked(car.ent, 1)
                    FreezeEntityPosition(car.ent, false)
                    TaskEnterVehicle(peds[i], car.ent, 10000, -1, 1.0, 1, 0)
                end
            end
            waitUntil(function()
                for i, car in ipairs(cars) do if peds[i] and not IsPedInVehicle(peds[i], car.ent, false) then return false end end
                return true
            end, 10000)
            for i, car in ipairs(cars) do
                if peds[i] then
                    if not IsPedInVehicle(peds[i], car.ent, false) then SetPedIntoVehicle(peds[i], car.ent, -1) end
                    SetVehicleEngineOn(car.ent, true, true, false)
                    TaskVehicleDriveWander(peds[i], car.ent, 20.0, 786603)
                    Wait(1200)
                end
            end
        end)
    end

    -- everyone's camera: the line of cars, then the lead car pulling away
    local lead = cars[1].ent
    waitUntil(function() return skip or GetEntitySpeed(lead) > 2.0 end, 26000)
    if not skip then
        cam.go({ pos = fixed(GetEntityCoords(lead) + right * 6.0 + vec3(0.0, 0.0, 2.0)), look = at(lead, 0.0, 0.0, 0.5), fov = 42.0, speed = 0.03 })
        local start = GetEntityCoords(lead)
        waitUntil(function() return skip or #(GetEntityCoords(lead) - start) > 45.0 end, 9000)
    end
    cine = false
    cam.stop()
    ClearPedTasks(cache.ped)
    DisplayRadar(true)
    Client.Send('cine', { on = false })
    for _, ped in pairs(peds) do
        if DoesEntityExist(ped) then
            SetEntityInvincible(ped, false)
            if IsPedInAnyVehicle(ped, false) then SetPedAsNoLongerNeeded(ped) else DeleteEntity(ped) end
        end
    end
end

RegisterNetEvent('nz_cargo:crewsale:finale', function(d)
    local m = Client.mission
    if m and m.kind == 'sell' then cleanup(m) end
    Music.Stop(not d.failed)
    if d.failed then
        Client.Send('banner', { kind = 'fail', title = 'Deal Fell Through', subtitle = L('deal_failed') })
        return
    end
    crewCutscene(d)
    local stats = {
        { 'Cars', ('%d / %d'):format(d.delivered, d.count) },
        { 'Deal', '$' .. lib.math.groupdigits(d.total) },
        { d.leader == cache.serverId and 'Yours' or 'Your cut', '$' .. lib.math.groupdigits(d.mine) },
        { 'XP', '+' .. d.xp },
    }
    Client.Send('banner', { kind = 'success', title = 'Crew Sale Complete', subtitle = d.buyer and d.buyer.label or '', stats = stats })
end)

handlers.dealOffers = function(d)
    if Client.mission then Bridge.Notify(L('busy'), 'error') return { ok = false } end
    return lib.callback.await('nz_cargo:crewsale:offers', false, d.ids) or { ok = false }
end

handlers.dealStart = function(d)
    if Client.mission then Bridge.Notify(L('busy'), 'error') return { ok = false } end
    return lib.callback.await('nz_cargo:crewsale:start', false, d.option, d.assign) or { ok = false }
end
