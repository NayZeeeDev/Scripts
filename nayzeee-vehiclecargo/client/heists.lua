-----------------------------------------------------------------
-- How the car is taken (the harder scenarios)
--   party       aim at the guests so they give up, search each one
--   pickpocket  sneak up behind the owner and lift the keys
--   hostile     the armed owner fights, search his body
--   guarded     shootout, the key holder drops the keys on the ground
--   tow         steal a flatbed from a guarded depot, tow the dead car
--   cargobob    steal a Cargobob from a guarded pad, hook the car
-- The server decides who holds the keys and validates every step.
-----------------------------------------------------------------
Heist = {}
local C = Config.Sourcing

local function v3(t) return vec3(t.x, t.y, t.z) end

local function blipOn(ent, sprite, colour, label)
    local b = AddBlipForEntity(ent)
    SetBlipSprite(b, sprite)
    SetBlipColour(b, colour)
    SetBlipScale(b, 0.8)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandSetBlipName(b)
    return b
end

-- Third-eye options that are removed with the mission
local function target(m, ent, id, options, radius)
    Bridge.AddEntity(ent, id, options, radius)
    m.targets = m.targets or {}
    m.targets[#m.targets + 1] = { ent = ent, id = id }
end

function Heist.Cleanup(m)
    for _, t in ipairs(m.targets or {}) do Bridge.RemoveEntity(t.ent, t.id) end
    m.targets = {}
    for _, o in ipairs(m.props or {}) do if DoesEntityExist(o) then DeleteEntity(o) end end
    m.props = {}
    if m.carrier and DoesEntityExist(m.carrier) and m.vehicle and DoesEntityExist(m.vehicle) and IsEntityAttachedToEntity(m.vehicle, m.carrier) then
        DetachEntity(m.vehicle, true, true)
    end
end

local function busy(m) return m.busy or m.done end

-----------------------------------------------------------------
-- Keys
-----------------------------------------------------------------
local function gotKeys(m, veh)
    m.locked = false
    m.hasKeys = true
    if DoesEntityExist(veh) then SetVehicleDoorsLocked(veh, 1) end
    PlaySoundFrontend(-1, 'PICK_UP', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
    Bridge.Notify(L('src_keys_found'), 'success')
    Source.Objective(m, 'You have the keys. Take the ' .. m.data.label)
end

local function askKeys(m, veh, index, how)
    local res = lib.callback.await('nz_cargo:source:keys', false, m.id, index, how)
    if res == 'found' then gotKeys(m, veh) end
    return res
end

local SEARCH = { dict = 'anim@gangops@facility@servers@bodysearch@', clip = 'player_search' }
local BODY   = { dict = 'amb@medic@standing@tendtodead@idle_a', clip = 'idle_a' }

local function search(ped, ms, label)
    TaskTurnPedToFaceEntity(cache.ped, ped, 600)
    Wait(600)
    local a = IsEntityDead(ped) and BODY or SEARCH
    return lib.progressCircle({
        duration = ms, label = label, position = 'bottom', canCancel = true,
        disable = { move = true, car = true, combat = true }, anim = { dict = a.dict, clip = a.clip, flag = 1 },
    })
end

-- Search a body / a guest with their hands up
local function searchPed(m, veh, ped, index, how)
    if busy(m) or m.hasKeys then return false end
    m.busy = true
    local dead = IsEntityDead(ped)
    local done = search(ped, how == 'search' and C.Party.SearchTime or 3200, dead and 'Searching the body' or 'Patting them down')
    if done then
        local res = askKeys(m, veh, index, how)
        if res == 'armed' then
            Bridge.Notify(L('src_keys_angry'), 'error')
            Scenarios.Anger(ped, true)
        elseif res ~= 'found' then
            Bridge.Notify(L('src_keys_none'), 'info')
        end
    end
    m.busy = false
    return done
end

-----------------------------------------------------------------
-- Party: hold them up, then search them one by one
-----------------------------------------------------------------
function Heist.Party(m, veh, spot)
    local guests = Scenarios.Party(spot, m.data.crew or m.data.guests or 4)
    lib.callback.await('nz_cargo:source:crew', false, m.id, #guests)
    for _, g in ipairs(guests) do
        m.peds[#m.peds + 1] = g.ped
        target(m, g.ped, ('nzc_guest_%d_%d'):format(m.id, g.index), {
            {
                label = 'Search for keys', icon = 'fa-solid fa-hand',
                canInteract = function()
                    return not m.hasKeys and not g.searched and not busy(m) and (g.surrendered or IsEntityDead(g.ped))
                end,
                onSelect = function()
                    CreateThread(function()
                        if searchPed(m, veh, g.ped, g.index, 'search') then g.searched = true end
                    end)
                end,
            },
        }, 2.2)
    end
    Source.ReportPeds(m, m.peds)
    Source.Objective(m, 'Hold the guests up and search them for the keys')

    local P = C.Party
    local me = PlayerId()
    CreateThread(function()
        while not m.done and not m.hasKeys do
            local sleep = 600
            local myPos = GetEntityCoords(cache.ped)
            if #(myPos - spot) < 40.0 then
                sleep = 150
                if IsPlayerFreeAiming(me) then
                    local ok, ent = GetEntityPlayerIsFreeAimingAt(me)
                    if ok and ent ~= 0 then
                        for _, g in ipairs(guests) do
                            if g.ped == ent and not g.reacted and not IsEntityDead(g.ped) then
                                g.reacted = true
                                local r = math.random()
                                if r < P.FightChance then
                                    Scenarios.Anger(g.ped, true)
                                elseif r < P.FightChance + P.FleeChance then
                                    Scenarios.Flee(g.ped)
                                    m.blips['runner' .. g.index] = blipOn(g.ped, 280, 1, 'Runner')
                                else
                                    Scenarios.Surrender(g.ped)
                                    g.surrendered = true
                                end
                            end
                        end
                    end
                end
                -- a shot near the party: everyone left puts their hands up
                if IsPedShooting(cache.ped) then
                    for _, g in ipairs(guests) do
                        if not g.reacted and not IsEntityDead(g.ped) and #(GetEntityCoords(g.ped) - myPos) < 30.0 then
                            g.reacted, g.surrendered = true, true
                            Scenarios.Surrender(g.ped)
                        end
                    end
                end
            end
            Wait(sleep)
        end
    end)
end

-----------------------------------------------------------------
-- Pickpocket: get behind him without being noticed
-----------------------------------------------------------------
local function behind(owner)
    local op, pp = GetEntityCoords(owner), GetEntityCoords(cache.ped)
    local dir = pp - op
    local len = #dir
    if len < 0.05 or len > 2.4 then return false end
    local f = GetEntityForwardVector(owner)
    return (f.x * dir.x + f.y * dir.y) / len < -0.35
end

local function spook(m, owner)
    if m.spooked then return end
    m.spooked = true
    lib.callback.await('nz_cargo:source:spooked', false, m.id)
    if not DoesEntityExist(owner) or IsEntityDead(owner) then return end
    if math.random() < C.Pickpocket.FightChance then
        Bridge.Notify(L('src_owner_fights'), 'error')
        Scenarios.Anger(owner, true)
    else
        Bridge.Notify(L('src_owner_runs'), 'warning')
        Scenarios.Flee(owner)
    end
    m.blips.owner = m.blips.owner or blipOn(owner, 280, 1, 'Owner')
    Source.Objective(m, 'He made you. Take the keys off him')
end

local function lift(m, veh, owner)
    if busy(m) or m.hasKeys then return end
    m.busy = true
    local P = C.Pickpocket
    -- he stops to check his phone; you have a moment
    ClearPedTasks(owner)
    TaskStartScenarioInPlace(owner, 'WORLD_HUMAN_STAND_MOBILE', 0, true)
    lib.requestAnimDict('mp_common')
    TaskPlayAnim(cache.ped, 'mp_common', 'givetake1_a', 3.0, 3.0, -1, 49, 0, false, false, false)
    local ok = lib.skillCheck(P.SkillCheck, { 'e' })
    if ok then
        ok = lib.progressCircle({ duration = P.Time, label = 'Lifting the keys', position = 'bottom', canCancel = true, disable = { move = true, combat = true } })
    end
    ClearPedTasks(cache.ped)
    RemoveAnimDict('mp_common')
    if ok and behind(owner) and not IsEntityDead(owner) then
        askKeys(m, veh, 1, 'pickpocket')
        ClearPedTasks(owner)
        TaskWanderInArea(owner, m.data.spot.x, m.data.spot.y, m.data.spot.z, 14.0, 2.0, 6.0)
    else
        spook(m, owner)
    end
    m.busy = false
end

function Heist.Pickpocket(m, veh, spot)
    local owner = Scenarios.Owner(spot, C.Pickpocket.OwnerModels, 'wander')
    if not owner then return Heist.Guarded(m, veh, spot) end
    lib.callback.await('nz_cargo:source:crew', false, m.id, 1)
    m.peds[#m.peds + 1] = owner
    Source.ReportPeds(m, { owner })
    target(m, owner, 'nzc_owner_' .. m.id, {
        {
            label = 'Lift the keys', icon = 'fa-solid fa-hand-sparkles',
            canInteract = function() return not m.hasKeys and not m.spooked and not busy(m) and not IsEntityDead(owner) and behind(owner) end,
            onSelect = function() CreateThread(function() lift(m, veh, owner) end) end,
        },
        {
            label = 'Search the body', icon = 'fa-solid fa-hand',
            canInteract = function() return not m.hasKeys and not busy(m) and IsEntityDead(owner) end,
            onSelect = function() CreateThread(function() searchPed(m, veh, owner, 1, 'body') end) end,
        },
    }, 1.8)
    Source.Objective(m, 'Sneak up behind the owner and lift his keys')

    -- he notices you running at him, a gun pointed his way, or shots
    local P = C.Pickpocket
    local me = PlayerId()
    CreateThread(function()
        while not m.done and not m.hasKeys and not m.spooked do
            local sleep = 1000
            if not DoesEntityExist(owner) then break end
            if IsEntityDead(owner) then spook(m, owner) break end
            local d = #(GetEntityCoords(owner) - GetEntityCoords(cache.ped))
            if d < 30.0 then
                sleep = 200
                local aiming = IsPlayerFreeAimingAtEntity(me, owner) or (d < P.Notice and IsPlayerFreeAiming(me))
                local loud = d < P.Notice and (IsPedSprinting(cache.ped) or (IsPedRunning(cache.ped) and not GetPedStealthMovement(cache.ped)))
                local shot = IsPedShooting(cache.ped) and d < 45.0
                local seen = d < 1.6 and not behind(owner) and not m.busy
                if aiming or loud or shot or seen then spook(m, owner) end
            end
            Wait(sleep)
        end
    end)
end

-----------------------------------------------------------------
-- Hostile owner: he and his friends shoot first
-----------------------------------------------------------------
function Heist.Hostile(m, veh, spot)
    local H = C.Hostile
    local owner = Scenarios.Owner(spot, H.OwnerModels, 'guard', H.Weapons[math.random(1, #H.Weapons)], H.Armour)
    local crew = { owner }
    for _, g in ipairs(Scenarios.Guards(spot, m.data.crew or 0, 'hostile', m.data.illegal)) do crew[#crew + 1] = g end
    lib.callback.await('nz_cargo:source:crew', false, m.id, #crew)
    for i, ped in ipairs(crew) do
        if ped then
            m.peds[#m.peds + 1] = ped
            target(m, ped, ('nzc_body_%d_%d'):format(m.id, i), {
                {
                    label = 'Search the body', icon = 'fa-solid fa-hand',
                    canInteract = function() return not m.hasKeys and not busy(m) and IsEntityDead(ped) end,
                    onSelect = function() CreateThread(function() searchPed(m, veh, ped, i, 'body') end) end,
                },
            }, 2.0)
        end
    end
    if owner then m.blips.owner = blipOn(owner, 280, 1, 'Owner') end
    Source.ReportPeds(m, m.peds)
    Source.Objective(m, 'The owner is armed. Take the keys off him')
end

-----------------------------------------------------------------
-- Guarded: the key holder drops them when he goes down
-----------------------------------------------------------------
local function dropKeys(m, veh, ped, index)
    local at = GetOffsetFromEntityInWorldCoords(ped, 0.35, 0.45, 0.0)
    local hash = Client.LoadModel('p_car_keys_01')
    if not hash then return end
    local _, gz = GetGroundZFor_3dCoord(at.x, at.y, at.z + 1.0, false)
    local obj = CreateObject(hash, at.x, at.y, (gz and gz > 0 and gz or at.z) + 0.02, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    PlaceObjectOnGroundProperly(obj)
    SetEntityRotation(obj, 90.0, 0.0, math.random() * 360.0, 2, true)
    FreezeEntityPosition(obj, true)
    m.props = m.props or {}
    m.props[#m.props + 1] = obj
    Bridge.Notify(L('src_keys_dropped'), 'warning')
    Source.Objective(m, 'Grab the keys off the ground')
    target(m, obj, 'nzc_keys_' .. m.id, {
        {
            label = 'Pick up the keys', icon = 'fa-solid fa-key',
            canInteract = function() return not m.hasKeys and not busy(m) end,
            onSelect = function()
                CreateThread(function()
                    m.busy = true
                    lib.requestAnimDict('pickup_object')
                    TaskPlayAnim(cache.ped, 'pickup_object', 'pickup_low', 8.0, -8.0, 1000, 0, 0, false, false, false)
                    Wait(900)
                    RemoveAnimDict('pickup_object')
                    if askKeys(m, veh, index, 'pickup') == 'found' and DoesEntityExist(obj) then DeleteEntity(obj) end
                    m.busy = false
                end)
            end,
        },
    }, 1.6)
    -- a small glint so they can be found
    CreateThread(function()
        while DoesEntityExist(obj) and not m.hasKeys and not m.done do
            local p = GetEntityCoords(obj)
            local sleep = 800
            if #(GetEntityCoords(cache.ped) - p) < 25.0 then
                sleep = 0
                DrawMarker(2, p.x, p.y, p.z + 0.45, 0, 0, 0, 180.0, 0, 0, 0.18, 0.18, 0.18, 229, 165, 10, 200, true, true, 2, false, nil, nil, false)
            end
            Wait(sleep)
        end
    end)
end

function Heist.Guarded(m, veh, spot)
    local guards = Scenarios.Guards(spot, m.data.crew, 'guarded', m.data.illegal)
    lib.callback.await('nz_cargo:source:crew', false, m.id, math.max(1, #guards))
    local index = math.min(m.data.keyHolder or #guards, #guards)
    for i, g in ipairs(guards) do
        m.peds[#m.peds + 1] = g
        target(m, g, ('nzc_body_%d_%d'):format(m.id, i), {
            {
                label = 'Search the body', icon = 'fa-solid fa-hand',
                canInteract = function() return not m.hasKeys and not busy(m) and IsEntityDead(g) and i ~= index end,
                onSelect = function() CreateThread(function() searchPed(m, veh, g, i, 'body') end) end,
            },
        }, 2.0)
    end
    Source.ReportPeds(m, guards)
    Source.Objective(m, 'Take out the guards. One of them has the keys')
    local holder = guards[index]
    if not holder then return end
    CreateThread(function()
        while not m.done and not m.hasKeys do
            if not DoesEntityExist(holder) then break end
            if IsEntityDead(holder) then dropKeys(m, veh, holder, index) break end
            Wait(500)
        end
    end)
end

-----------------------------------------------------------------
-- Recovery: tow truck / Cargobob
-----------------------------------------------------------------
local function carrierOf(m)
    if m.carrier and DoesEntityExist(m.carrier) then return m.carrier end
    local n = m.data.carrierNet
    if n and NetworkDoesEntityExistWithNetworkId(n) then
        m.carrier = NetToVeh(n)
        return m.carrier
    end
end

-- The car won't start
function Heist.DeadCar(m, veh)
    if Client.Control(veh, 1000) then
        SetVehicleUndriveable(veh, true)
        SetVehicleEngineOn(veh, false, true, true)
        SetVehicleDoorsLocked(veh, 2)
        if m.data.scenario == 'tow' then SetVehicleDoorOpen(veh, 4, false, false) end
    end
end

local function hotwire(m, carrier)
    if busy(m) or m.hotwired then return end
    m.busy = true
    TaskTurnPedToFaceEntity(cache.ped, carrier, 600)
    Wait(600)
    lib.requestAnimDict('veh@break_in@0h@p_m_one@')
    TaskPlayAnim(cache.ped, 'veh@break_in@0h@p_m_one@', 'low_force_entry_ds', 3.0, 3.0, -1, 49, 0, false, false, false)
    local ok = lib.skillCheck(C.Recovery.Hotwire, { 'e' })
    ClearPedTasks(cache.ped)
    RemoveAnimDict('veh@break_in@0h@p_m_one@')
    if lib.callback.await('nz_cargo:source:hotwire', false, m.id, ok) then
        m.hotwired = true
        if Client.Control(carrier, 800) then
            SetVehicleDoorsLocked(carrier, 1)
            SetVehicleNeedsToBeHotwired(carrier, false)
            SetVehicleEngineOn(carrier, true, true, false)
        end
        Bridge.GiveKeys(carrier, GetVehicleNumberPlateText(carrier))
        Source.RemoveBlips(m, 'lift')
        if m.blips.spot then SetBlipRoute(m.blips.spot, true) SetBlipRouteColour(m.blips.spot, 5) end
        Source.Objective(m, m.data.scenario == 'tow' and ('Drive the flatbed to the ' .. m.data.label) or ('Fly to the ' .. m.data.label .. ' and hook it'))
    else
        Bridge.Notify(L('src_hotwire_fail'), 'error')
    end
    m.busy = false
end

local function loadTow(m, carrier, veh)
    if busy(m) then return end
    m.busy = true
    Bridge.HideText()
    local done = lib.progressBar({ duration = 4500, label = 'Winching it onto the bed', canCancel = true, disable = { car = true, move = true, combat = true } })
    if done and Client.Control(veh, 1500) then
        local o = C.Recovery.Tow.Offset
        SetVehicleUndriveable(veh, true)
        AttachEntityToEntity(veh, carrier, GetEntityBoneIndexByName(carrier, 'bodyshell'), o.x, o.y, o.z, 0.0, 0.0, 0.0, true, true, false, true, 0, true)
        local res = lib.callback.await('nz_cargo:source:loaded', false, m.id, true)
        if res then
            m.loaded = true
            Source.RemoveBlips(m, 'spot')
            Source.StartEscape(m, veh, res)
        else
            DetachEntity(veh, true, true)
        end
    end
    m.busy = false
end

local function hook(m, heli, veh)
    if busy(m) then return end
    m.busy = true
    Bridge.HideText()
    if Client.Control(veh, 1500) then
        AttachVehicleToCargobob(heli, veh, -1, 0.0, 0.0, 0.0)
        Wait(300)
    end
    if IsVehicleAttachedToCargobob(heli, veh) then
        local res = lib.callback.await('nz_cargo:source:loaded', false, m.id, true)
        if res then
            m.loaded = true
            Source.RemoveBlips(m, 'spot')
            if m.stage ~= 'escape' then Source.StartEscape(m, veh, res) end
        else
            DetachVehicleFromCargobob(heli, veh)
        end
    end
    m.busy = false
end

-- Drop it in the garage zone, let it settle, then it's yours
local function release(m, heli, veh)
    if busy(m) then return end
    m.busy = true
    Bridge.HideText()
    DetachVehicleFromCargobob(heli, veh)
    m.loaded = false
    lib.callback.await('nz_cargo:source:loaded', false, m.id, false)
    local t = GetGameTimer()
    while GetGameTimer() - t < 8000 and DoesEntityExist(veh) and GetEntitySpeed(veh) > 0.4 do Wait(200) end
    m.busy = false
    Source.Deliver(m, veh)
end

local function liftLoop(m)
    local R = C.Recovery
    local tow = m.data.scenario == 'tow'
    local garage = m.data.garage and v3(m.data.garage)
    CreateThread(function()
        while not m.done do
            local sleep = 500
            local carrier, veh = carrierOf(m), m.vehicle
            if m.hotwired and carrier and veh and DoesEntityExist(veh) and GetVehiclePedIsIn(cache.ped, false) == carrier
                and GetPedInVehicleSeat(carrier, -1) == cache.ped and not busy(m) then
                local cp, vp = GetEntityCoords(carrier), GetEntityCoords(veh)
                if tow and not m.loaded then
                    local rear = GetOffsetFromEntityInWorldCoords(carrier, 0.0, -6.0, 0.0)
                    if #(rear - vp) < R.Tow.LoadRange then
                        sleep = 0
                        Bridge.ShowText(Config.Interact.KeyLabel, 'Load the car')
                        if IsControlJustPressed(0, Config.Interact.Key) and GetEntitySpeed(carrier) < 1.5 then CreateThread(function() loadTow(m, carrier, veh) end) end
                    else
                        Bridge.HideText()
                    end
                elseif not tow then
                    if not DoesCargobobHavePickUpRope(carrier) then CreatePickUpRopeForCargobob(carrier, 0) end
                    if not IsVehicleAttachedToCargobob(carrier, veh) then
                        if m.loaded then m.loaded = false lib.callback.await('nz_cargo:source:loaded', false, m.id, false) end
                        local flat = #(vec2(cp.x, cp.y) - vec2(vp.x, vp.y))
                        local above = cp.z - vp.z
                        if flat < R.Cargobob.HookRange and above > 1.0 and above < 30.0 then
                            sleep = 0
                            Bridge.ShowText(Config.Interact.KeyLabel, 'Hook the car')
                            if IsControlJustPressed(0, Config.Interact.Key) then CreateThread(function() hook(m, carrier, veh) end) end
                        else
                            Bridge.HideText()
                        end
                    else
                        if not m.loaded then hook(m, carrier, veh) end   -- hooked it by flying onto it
                        if garage and #(vec2(vp.x, vp.y) - vec2(garage.x, garage.y)) < C.DeliverRadius + 10.0 then
                            sleep = 0
                            DrawMarker(1, garage.x, garage.y, garage.z - 1.0, 0, 0, 0, 0, 0, 0, 14.0, 14.0, 1.0, 8, 175, 162, 70, false, false, 2, false, nil, nil, false)
                            Bridge.ShowText(Config.Interact.KeyLabel, 'Release the car')
                            if IsControlJustPressed(0, Config.Interact.Key) then CreateThread(function() release(m, carrier, veh) end) end
                        elseif garage and #(vp - garage) < 150.0 then
                            sleep = 0
                            DrawMarker(1, garage.x, garage.y, garage.z - 1.0, 0, 0, 0, 0, 0, 0, 14.0, 14.0, 1.0, 8, 175, 162, 70, false, false, 2, false, nil, nil, false)
                            Bridge.HideText()
                        end
                    end
                end
            end
            Wait(sleep)
        end
        Bridge.HideText()
    end)
end

-- Guards at the depot / helipad and the hotwire prompt on the carrier
function Heist.Depot(m)
    local carrier = carrierOf(m)
    if not carrier then return end
    m.depotReady = true
    local lift = v3(m.data.lift)
    local guards = Scenarios.Guards(lift, m.data.crew, m.data.scenario, m.data.illegal)
    for _, g in ipairs(guards) do m.peds[#m.peds + 1] = g end
    Source.ReportPeds(m, guards)
    if m.data.scenario == 'cargobob' then
        CreateThread(function()
            if Client.Control(carrier, 1000) then CreatePickUpRopeForCargobob(carrier, 0) end
        end)
    end
    target(m, carrier, 'nzc_carrier_' .. m.id, {
        {
            label = m.data.scenario == 'tow' and 'Hotwire the flatbed' or 'Hotwire the Cargobob', icon = 'fa-solid fa-bolt',
            canInteract = function() return not m.hotwired and not busy(m) and not IsPedInAnyVehicle(cache.ped, false) end,
            onSelect = function() CreateThread(function() hotwire(m, carrier) end) end,
        },
    }, 3.5)
    liftLoop(m)
end
