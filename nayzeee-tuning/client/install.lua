--[[
    Mechanic work orders, fitted for real:
      body parts are carried from their own rack with their own prop,
      brakes / gearbox / suspension put the car on axle stands first,
      wheels are carried and bolted on one corner at a time,
      engines arrive on an engine hoist, paint is sprayed inside the booth.
    Every step plays its sound for everyone nearby.
]]

Install = {}

local IC = Config.Install
local active, cancelled = nil, false
local held = {}            -- props attached to the mechanic
local carry = nil          -- { anim, run } while something is carried
local placed = {}          -- props left in the world (stands, hoist)
local lift                 -- { veh, base } while the car is on stands

function Install.Active() return active ~= nil end

--------------------------------------------------------------------- helpers

local function loadAnim(dict) return HasAnimDictLoaded(dict) or lib.requestAnimDict(dict, 3000) end

local function spawnProp(model, coords)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) or not lib.requestModel(hash, 3000) then return nil end
    local c = coords or GetEntityCoords(cache.ped)
    local obj = CreateObject(hash, c.x, c.y, c.z - 2.0, true, true, false)
    SetModelAsNoLongerNeeded(hash)
    SetEntityCollision(obj, false, false)
    return obj
end

local attachCfg = {}       -- [obj] = { bone, x, y, z, rx, ry, rz, parent } (used by /carryadjust)

local function attach(obj, a)
    attachCfg[obj] = { a[1], a[2], a[3], a[4], a[5], a[6], a[7] }
    AttachEntityToEntity(obj, cache.ped, GetPedBoneIndex(cache.ped, a[1]), a[2], a[3], a[4], a[5], a[6], a[7], true, true, false, true, 1, true)
end

-- the engine hangs off the hoist, not the ped
local function attachToProp(obj, parent, o)
    attachCfg[obj] = { 0, o[1], o[2], o[3], o[4], o[5], o[6], parent = parent }
    AttachEntityToEntity(obj, parent, 0, o[1], o[2], o[3], o[4], o[5], o[6], true, true, false, false, 1, true)
end

local function clearHeld()
    for _, o in ipairs(held) do if DoesEntityExist(o) then DetachEntity(o, true, true) DeleteEntity(o) end end
    held = {}
    if carry and carry.anim then StopAnimTask(cache.ped, carry.anim[1], carry.anim[2], 2.0) end
    carry = nil
end

local function clearPlaced()
    for _, o in ipairs(placed) do if DoesEntityExist(o) then DeleteEntity(o) end end
    placed = {}
end

-- carry loops always use flag 49 (upper body + loop + player keeps control) so you can walk
local function playLoop(anim)
    if not anim or not loadAnim(anim[1]) then return end
    TaskPlayAnim(cache.ped, anim[1], anim[2], 8.0, -8.0, -1, 49, 0, false, false, false)
end

-- light parts can be run with (def.run = true), heavy ones only walked
local function canRun(def)
    if def and def.run ~= nil then return def.run end
    return IC.AllowRunCarrying == true
end

local function stopAnim() ClearPedTasks(cache.ped) end

local function hold(def, carryAnim)
    clearHeld()
    if def.prop then
        local o = spawnProp(def.prop)
        if o then attach(o, def.attach) held[#held + 1] = o end
    end
    carry = { anim = carryAnim, run = canRun(def), def = def }
    if carryAnim then playLoop(carryAnim) end
end
Install.HeldInfo = function() return held, carry end

local function sfx(name)
    local s = IC.Sounds[name]
    if not s then return end
    UI.Send('sound', { file = s.file, volume = s.volume })
    TriggerServerEvent('nayzeee-tuning:sfx', name)
end

Install.Sfx = sfx

RegisterNetEvent('nayzeee-tuning:sfx', function(name, factor)
    local s = IC.Sounds[name]
    if s then UI.Send('sound', { file = s.file, volume = s.volume * (factor or 1.0) }) end
end)

local function isRearEngine(veh)
    local idx = GetEntityBoneIndexByName(veh, 'engine')
    if idx == -1 then return false end
    local w = GetWorldPositionOfEntityBone(veh, idx)
    return GetOffsetFromEntityGivenWorldCoords(veh, w.x, w.y, w.z).y < -0.3
end

-- world position around the car for a direction name, at ground level
local function pointAt(veh, dir, offset)
    local mn, mx = GetModelDimensions(GetEntityModel(veh))
    local m = 0.55
    local x, y = 0.0, 0.0
    if dir == 'front' then y = mx.y + m
    elseif dir == 'rear' then y = mn.y - m
    elseif dir == 'left' then x = mn.x - m
    elseif dir == 'right' then x = mx.x + m
    elseif dir == 'front-left' then x, y = mn.x - m, mx.y * 0.62
    elseif dir == 'front-right' then x, y = mx.x + m, mx.y * 0.62
    elseif dir == 'rear-left' then x, y = mn.x - m, mn.y * 0.62
    elseif dir == 'rear-right' then x, y = mx.x + m, mn.y * 0.62 end
    if offset then x, y = x + offset.x, y + offset.y end
    local z = mn.z + 0.05 - (lift and IC.LiftHeight or 0.0)
    return GetOffsetFromEntityInWorldCoords(veh, x, y, z)
end

local function wheelPoint(veh, bone)
    local idx = GetEntityBoneIndexByName(veh, bone)
    if idx == -1 then return nil end
    local w = GetWorldPositionOfEntityBone(veh, idx)
    local rel = GetOffsetFromEntityGivenWorldCoords(veh, w.x, w.y, w.z)
    local side = rel.x < 0 and -0.75 or 0.75
    local mn = GetModelDimensions(GetEntityModel(veh))
    return GetOffsetFromEntityInWorldCoords(veh, rel.x + side, rel.y, mn.z + 0.05 - (lift and IC.LiftHeight or 0.0))
end

local function faceCar(veh, at)
    local c = GetEntityCoords(veh)
    local h = GetHeadingFromVector_2d(c.x - at.x, c.y - at.y)
    SetEntityHeading(cache.ped, h)
end

--------------------------------------------------------------------- tracker UI

local function tracker()
    if not active then return UI.Send('install:close') end
    local o = active.order
    local done = 0
    for _, it in ipairs(o.items) do if it.done then done = done + 1 end end
    UI.Send('install:state', {
        id = o.id, plate = o.plate, label = o.label or o.model, customer = o.customer,
        items = o.items, done = done, total = #o.items, step = active.step, help = active.help,
        current = active.current, missing = active.missing,
    })
end

local function setStep(text, current, help)
    if not active then return end
    active.step, active.current, active.help = text, current, help
    tracker()
end

--------------------------------------------------------------------- waiting at a spot

local function waitAt(coords, text, dist)
    dist = dist or 1.4
    local showing = false
    while active and not cancelled do
        if not DoesEntityExist(active.veh) then return false end
        DrawMarker(21, coords.x, coords.y, coords.z + 0.85, 0, 0, 0, 180.0, 0, 0, 0.3, 0.3, 0.3, 8, 175, 162, 200, true, true, 2, false, nil, nil, false)
        if carry then
            if not carry.run then DisableControlAction(0, 21, true) DisableControlAction(0, 22, true) end
            DisableControlAction(0, 24, true) DisableControlAction(0, 25, true) DisableControlAction(0, 23, true)
            -- keep the arms up if something (a bump, a door) cancelled the carry loop
            if carry.anim and GetGameTimer() > (carry.check or 0) then
                carry.check = GetGameTimer() + 500
                if not IsEntityPlayingAnim(cache.ped, carry.anim[1], carry.anim[2], 3) then playLoop(carry.anim) end
            end
        end
        local d = #(GetEntityCoords(cache.ped) - coords)
        if d < dist then
            if not showing then Bridge.TextUI(text) showing = true end
            if IsControlJustPressed(0, Config.Keys.Interact) then Bridge.TextUI(false) return true end
        elseif showing then Bridge.TextUI(false) showing = false end
        Wait(0)
    end
    if showing then Bridge.TextUI(false) end
    return false
end

-- the rack a part (or tool / jacks / hoist) is collected from. With PartSource 'inventory' the parts are
-- already in the mechanic's pockets (taken from supply storage), so only equipment is collected.
local function pickupFor(itemId, pile, equipment)
    if not active.physical then return nil end
    if active.source == 'inventory' and not equipment then return nil end
    return (active.parts and active.parts[itemId]) or active.stockpiles[pile or 'body'] or active.stockpiles.body
end

-- timed work with animation + sound, cancellable
local function work(label, time, anim, sound, keepProp)
    if not Bridge.SkillCheck() then
        Notify(L('install_slipped'), 'error')
        if not Bridge.SkillCheck() then return false end
    end
    if not keepProp then clearHeld() end
    if sound then sfx(sound) end
    local ok = Bridge.Progress(label, time, anim and { anim[1], anim[2], 1 } or nil, nil, true)
    stopAnim()
    return ok
end

--------------------------------------------------------------------- axle stands

local function raise(veh, up)
    if not VehUtil.Control(veh, 2500) then return false end
    local start = GetEntityCoords(veh)
    local h = IC.LiftHeight * (up and 1 or -1)
    FreezeEntityPosition(veh, true)
    local t0 = GetGameTimer()
    while true do
        local t = math.min(1.0, (GetGameTimer() - t0) / IC.LiftTime)
        SetEntityCoordsNoOffset(veh, start.x, start.y, start.z + h * t, false, false, false)
        if t >= 1.0 then break end
        Wait(0)
    end
    if not up then FreezeEntityPosition(veh, false) end
    return true
end

local function ensureLifted(veh)
    if lift and lift.veh == veh then return true end
    local J = IC.Jacks
    local pile = pickupFor('jacks', J.pile, true)
    if pile then
        setStep(L('step_jacks_get'), active.current, L('help_jacks_get'))
        SetNewWaypoint(pile.x, pile.y)
        if not waitAt(pile, L('prompt_jacks'), 1.6) then return false end
        clearHeld()
        local a = spawnProp(J.prop)
        local b = spawnProp(J.prop)
        if a then attach(a, J.attach) held[#held + 1] = a end
        if b then attach(b, J.attach2) held[#held + 1] = b end
        carry = { anim = J.carryAnim, run = J.run == true, def = J }
        playLoop(J.carryAnim)
    end
    local at = pointAt(veh, J.placeAt, J.placeOffset)
    setStep(L('step_jacks_place'), active.current, L('help_jacks_place'))
    if not waitAt(at, L('prompt_jacks_place'), 1.5) then return false end
    faceCar(veh, at)
    clearHeld()
    sfx('jacks')
    if not Bridge.Progress(L('placing_jacks'), J.placeTime, { J.placeAnim[1], J.placeAnim[2], 1 }) then stopAnim() return false end
    stopAnim()

    -- stands under every wheel, then up she goes
    for _, bone in ipairs({ 'wheel_lf', 'wheel_rf', 'wheel_lr', 'wheel_rr' }) do
        local idx = GetEntityBoneIndexByName(veh, bone)
        if idx ~= -1 then
            local w = GetWorldPositionOfEntityBone(veh, idx)
            local stand = spawnProp(J.prop, w)
            if stand then
                local _, gz = GetGroundZFor_3dCoord(w.x, w.y, w.z, false)
                SetEntityCoords(stand, w.x, w.y, (gz ~= 0 and gz or w.z - 0.4), false, false, false, false)
                SetEntityHeading(stand, GetEntityHeading(veh))
                FreezeEntityPosition(stand, true)
                placed[#placed + 1] = stand
            end
        end
    end
    if not raise(veh, true) then return false end
    lift = { veh = veh }
    return true
end

local function lowerCar()
    if not lift then return end
    local veh = lift.veh
    lift = nil
    if DoesEntityExist(veh) then
        sfx('jacks')
        raise(veh, false)
        SetVehicleOnGroundProperly(veh)
    end
    clearPlaced()
end

--------------------------------------------------------------------- install types

local Types = {}

local function fetch(item, def, carryAnim)
    local pile = pickupFor(item.id, def.pile)
    if pile then
        setStep(L('step_fetch', item.label), item.id, L('help_fetch', item.label))
        SetNewWaypoint(pile.x, pile.y)
        if not waitAt(pile, L('prompt_grab', item.label), 1.6) then return false end
        if not Bridge.Progress(L('grabbing', item.label), 1400, { 'mini@repair', 'fixing_a_ped', 1 }) then return false end
    end
    hold(def, carryAnim)
    return true
end

local function openDoors(veh, doors, engineBay)
    local list = doors or {}
    if engineBay and isRearEngine(veh) then list = { 5 } end
    for _, d in ipairs(list) do SetVehicleDoorOpen(veh, d, false, false) end
    return list
end

local function closeDoors(veh, list)
    for _, d in ipairs(list or {}) do SetVehicleDoorShut(veh, d, false) end
end

Types.carry = function(item, def, veh)
    if not fetch(item, def, def.carryAnim) then return false end
    local dir = def.point or 'left'
    if def.engineBay and isRearEngine(veh) then dir = 'rear' end
    local at = pointAt(veh, dir, def.offset)
    setStep(L('step_fit', item.label, 1, 1), item.id, L('help_fit', item.label))
    if not waitAt(at, L('prompt_fit', item.label), 1.5) then return false end
    faceCar(veh, at)
    local doors = openDoors(veh, def.doors, def.engineBay)
    local ok = work(L('installing', item.label, 1, 1), def.time or 5000, def.work, def.sound)
    closeDoors(veh, doors)
    return ok
end

Types.tool = function(item, def, veh)
    if not fetch(item, def, nil) then return false end
    local dir = def.point or 'left'
    if def.engineBay and isRearEngine(veh) then dir = 'rear' end
    local at = pointAt(veh, dir, def.offset)
    setStep(L('step_fit', item.label, 1, 1), item.id, L('help_fit', item.label))
    if not waitAt(at, L('prompt_fit', item.label), 1.5) then return false end
    faceCar(veh, at)
    local doors = openDoors(veh, def.doors, def.engineBay)
    local ok = work(L('installing', item.label, 1, 1), def.time or 5000, def.work, def.sound, true)
    clearHeld()
    closeDoors(veh, doors)
    return ok
end

local function inBooth(veh)
    local booths = active.booths or {}
    if #booths == 0 then return true end
    local pos = GetEntityCoords(veh)
    for _, b in ipairs(booths) do if #(pos - b.coords) <= (b.radius or 4.0) then return true end end
    return false
end

local function sprayFx(at, value, time)
    CreateThread(function()
        if not lib.requestNamedPtfxAsset('scr_paintnspray', 2000) then return end
        UseParticleFxAssetNextCall('scr_paintnspray')
        local fx = StartParticleFxLoopedAtCoord('scr_respray_smoke', at.x, at.y, at.z + 0.8, 0.0, 0.0, 0.0, 1.0, false, false, false, false)
        if type(value) == 'table' and value.mode == 'rgb' then SetParticleFxLoopedColour(fx, value.r / 255, value.g / 255, value.b / 255, false) end
        Wait(time)
        StopParticleFxLooped(fx, false)
    end)
end

Types.spray = function(item, def, veh)
    if def.booth ~= false then
        while active and not cancelled and not inBooth(veh) do
            setStep(L('step_booth'), item.id, L('help_booth'))
            Wait(1000)
        end
        if cancelled or not active then return false end
    end
    if not fetch(item, def, nil) then return false end
    local pts = def.points or { 'left' }
    for i, dir in ipairs(pts) do
        local at = pointAt(veh, dir)
        setStep(L('step_fit', item.label, i, #pts), item.id, L('help_spray'))
        if not waitAt(at, L('prompt_spray', item.label), 1.5) then return false end
        faceCar(veh, at)
        sprayFx(at, item.value, def.time or 4000)
        if not work(L('installing', item.label, i, #pts), def.time or 4000, def.work, def.sound, true) then return false end
    end
    clearHeld()
    return true
end

Types.jacks = function(item, def, veh)
    if not ensureLifted(veh) then return false end
    local steps = def.work or { { point = 'front' } }
    for i, w in ipairs(steps) do
        local at = pointAt(veh, w.point or 'front', w.offset)
        setStep(L('step_fit', item.label, i, #steps), item.id, L('help_under'))
        if not waitAt(at, L('prompt_fit', item.label), 1.5) then return false end
        local vh = GetEntityHeading(veh)
        if w.face == 'rear' then SetEntityHeading(cache.ped, vh + 180.0)
        elseif w.face == 'front' then SetEntityHeading(cache.ped, vh)
        else faceCar(veh, at) end
        local anim = w.face and IC.UnderCar.anim or { 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', 'machinic_loop_mechandplayer' }
        if not work(L('installing', item.label, i, #steps), math.floor((def.time or 6000) / #steps) + 1500, anim, def.sound) then return false end
    end
    sfx('tighten')
    return true
end

Types.wheels = function(item, def, veh)
    if not ensureLifted(veh) then return false end
    local bones = def.only or { 'wheel_lf', 'wheel_lr', 'wheel_rf', 'wheel_rr', 'wheel_lm1', 'wheel_rm1' }
    local list = {}
    for _, b in ipairs(bones) do
        local p = wheelPoint(veh, b)
        if p then list[#list + 1] = { bone = b, at = p } end
    end
    for i, w in ipairs(list) do
        if not fetch(item, def, def.carryAnim) then return false end
        setStep(L('step_wheel', item.label, i, #list), item.id, L('help_wheel'))
        if not waitAt(w.at, L('prompt_wheel'), 1.4) then return false end
        local idx = GetEntityBoneIndexByName(veh, w.bone)
        local wc = GetWorldPositionOfEntityBone(veh, idx)
        TaskTurnPedToFaceCoord(cache.ped, wc.x, wc.y, wc.z, 600)
        Wait(600)
        if not work(L('installing', item.label, i, #list), def.time or 5000, { 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', 'machinic_loop_mechandplayer' }, def.sound) then return false end
    end
    return true
end

Types.hoist = function(item, def, veh)
    local H = IC.Hoist
    local pile = pickupFor(item.id, H.pile, true)
    if pile then
        setStep(L('step_hoist_get'), item.id, L('help_hoist'))
        SetNewWaypoint(pile.x, pile.y)
        if not waitAt(pile, L('prompt_hoist'), 1.8) then return false end
    end
    clearHeld()
    local hoist = spawnProp(H.prop)
    local engine = spawnProp(H.part)
    if hoist then
        attach(hoist, H.attach)
        held[#held + 1] = hoist
        if engine then
            attachToProp(engine, hoist, H.partOffset)
            held[#held + 1] = engine
        end
    end
    -- push it: upper-body loop so the legs walk, no running with an engine on a crane
    carry = { anim = H.pushAnim, run = false, def = H }
    playLoop(H.pushAnim)
    local rear = isRearEngine(veh)
    local at = pointAt(veh, rear and 'rear' or 'front', rear and vec3(0.0, -0.4, 0.0) or vec3(0.0, 0.4, 0.0))
    setStep(L('step_hoist_fit', item.label), item.id, L('help_hoist_fit'))
    if not waitAt(at, L('prompt_engine'), 1.6) then return false end
    StopAnimTask(cache.ped, H.pushAnim[1], H.pushAnim[2], 2.0)
    carry = nil
    -- park the hoist against the car
    if hoist and DoesEntityExist(hoist) then
        DetachEntity(hoist, true, true)
        PlaceObjectOnGroundProperly(hoist)
        FreezeEntityPosition(hoist, true)
        for i, o in ipairs(held) do if o == hoist then table.remove(held, i) break end end
        placed[#placed + 1] = hoist
        if engine and DoesEntityExist(engine) then
            for i, o in ipairs(held) do if o == engine then table.remove(held, i) break end end
            placed[#placed + 1] = engine
        end
    end
    faceCar(veh, at)
    local door = rear and 5 or 4
    SetVehicleDoorOpen(veh, door, false, false)
    local ok = work(L('installing', item.label, 1, 1), H.time, H.work, H.sound)
    SetVehicleDoorShut(veh, door, false)
    -- the hoist goes back; axle stands (if any) stay for later items
    for i = #placed, 1, -1 do
        local o = placed[i]
        if o == hoist or o == engine then
            if DoesEntityExist(o) then DeleteEntity(o) end
            table.remove(placed, i)
        end
    end
    return ok
end

--------------------------------------------------------------------- per item

local function defFor(item, veh)
    local def = Config.InstallParts[item.id] or Config.InstallFallback
    local advanced = IC.AdvancedClasses[GetVehicleClass(veh)] and IC.UseJacks
    if not advanced and (def.type == 'jacks' or def.type == 'wheels' or def.type == 'hoist') then
        def = Config.InstallFallback
    end
    return def
end

local function needParts(item)
    if Config.PartItems.Mode == 'off' then return true end
    local pinged = false
    while active and not cancelled do
        local ok, missing, source = lib.callback.await('nayzeee-tuning:orderNeeds', false, active.order.id, item.id)
        if not ok or not missing or #missing == 0 then active.missing = nil tracker() return true end
        active.missing = missing
        local names, inStock = {}, true
        for _, m in ipairs(missing) do
            names[#names + 1] = ('%s x%d'):format(m.label, m.need - m.have)
            if (m.stock or 0) < m.need - m.have then inStock = false end
        end
        local list = table.concat(names, ', ')
        if source == 'inventory' and inStock and active.storage then
            -- go and take them out of supply storage
            if not pinged then SetNewWaypoint(active.storage.x, active.storage.y) pinged = true end
            setStep(L('step_storage', list), item.id, L('help_storage'))
        elseif source == 'supply' or (source == 'both' and not inStock) then
            setStep(L('step_out_of_stock', list), item.id, L('help_out_of_stock'))
        else
            setStep(L('step_missing', list), item.id, L('help_missing'))
        end
        Wait(3000)
    end
    return false
end

local function fitItem(item)
    local veh = active.veh
    if not needParts(item) then return false end
    local def = defFor(item, veh)
    local fn = Types[def.type] or Types.tool
    if not fn(item, def, veh) then return false end

    local part = Config.Parts[item.id]
    if part and not NZ.ExtrasKinds[part.kind] and part.kind ~= 'plateText' then
        if VehUtil.Control(veh, 2000) then Apply.Item(veh, item.id, item.value) end
    end
    local ok, err = lib.callback.await('nayzeee-tuning:orderStep', false, active.order.id, item.id, VehToNet(veh))
    if not ok then Notify(err or L('install_failed'), 'error') return false end
    item.done = true
    tracker()
    return true
end

local function findVehicle(plate)
    local me = GetEntityCoords(cache.ped)
    for _, v in ipairs(GetGamePool('CVehicle')) do
        if VehUtil.Plate(v) == NZ.TrimPlate(plate) and #(GetEntityCoords(v) - me) < Config.Orders.MaxDistanceFromCar then return v end
    end
end

function Install.Stop(reason)
    if not active then return end
    cancelled = true
    clearHeld()
    stopAnim()
    lowerCar()
    clearPlaced()
    Bridge.TextUI(false)
    active = nil
    UI.Send('install:close')
    if reason then Notify(reason, 'inform') end
end

function Install.Begin(orderId)
    if active then return Notify(L('install_busy'), 'error') end
    local ok, order = lib.callback.await('nayzeee-tuning:orderAccept', false, orderId)
    if not ok then return Notify(order or L('install_failed'), 'error') end
    local veh = findVehicle(order.plate)
    if not veh then return Notify(L('install_need_car', order.plate), 'inform') end
    if GetPedInVehicleSeat(veh, -1) ~= 0 then return Notify(L('install_car_occupied'), 'error') end
    local ok2, res = lib.callback.await('nayzeee-tuning:orderStart', false, orderId, VehToNet(veh))
    if not ok2 then return Notify(res or L('install_failed'), 'error') end

    cancelled = false
    active = { order = res.order, veh = veh, stockpiles = res.stockpiles or {}, parts = res.parts or {}, booths = res.booths or {}, physical = res.physical,
        source = res.source or 'supply', storage = res.storage and vec3(res.storage.x, res.storage.y, res.storage.z) or nil }
    tracker()
    Notify(L('install_started', res.order.id), 'inform')

    CreateThread(function()
        -- do the stand work together so the car only goes up once
        local order = {}
        local function rank(it)
            local t = defFor(it, veh).type
            return (t == 'jacks' or t == 'wheels') and 1 or (t == 'hoist' and 0 or 2)
        end
        for _, it in ipairs(active.order.items) do order[#order + 1] = it end
        table.sort(order, function(a, b) return rank(a) < rank(b) end)

        for i, item in ipairs(order) do
            if not active or cancelled then break end
            if not item.done then
                if not fitItem(item) then break end
            end
            -- stands come down once no later item needs them
            local laterNeeds = false
            for j = i + 1, #order do
                local t = defFor(order[j], veh).type
                if not order[j].done and (t == 'jacks' or t == 'wheels') then laterNeeds = true end
            end
            if lift and not laterNeeds then lowerCar() end
        end
        if not active or cancelled then return end
        lowerCar()
        setStep(L('step_finishing'), nil, nil)
        local done, res2 = lib.callback.await('nayzeee-tuning:orderComplete', false, active.order.id, VehToNet(active.veh))
        if done then
            Notify(L('install_complete', res2.commission or 0), 'success')
        else
            Notify(res2 or L('install_failed'), 'error')
        end
        Install.Stop()
    end)
end

lib.addKeybind({
    name = 'nzt_cancel_install',
    description = 'Tuning: pause the current installation',
    defaultKey = Config.Keys.CancelInstall,
    onPressed = function()
        if active then Install.Stop(L('install_paused')) end
    end,
})

--------------------------------------------------------------------- /carryadjust (admins): line up carried props in game

local adjusting = false

local function adjustLoop(spawned)
    adjusting = true
    local idx = 1
    local function cur() return held[idx], attachCfg[held[idx]] end
    local function reattach(obj, a)
        if a.parent then
            AttachEntityToEntity(obj, a.parent, 0, a[2], a[3], a[4], a[5], a[6], a[7], true, true, false, false, 1, true)
        else
            AttachEntityToEntity(obj, cache.ped, GetPedBoneIndex(cache.ped, a[1]), a[2], a[3], a[4], a[5], a[6], a[7], true, true, false, true, 1, true)
        end
    end
    local function line(a)
        if a.parent then return ('partOffset = { %.3f, %.3f, %.3f, %.1f, %.1f, %.1f },'):format(a[2], a[3], a[4], a[5], a[6], a[7]) end
        return ('attach = { %d, %.3f, %.3f, %.3f, %.1f, %.1f, %.1f },'):format(a[1], a[2], a[3], a[4], a[5], a[6], a[7])
    end
    local shown
    while adjusting do
        Wait(0)
        local obj, a = cur()
        if not obj or not DoesEntityExist(obj) or not a then break end
        for _, c in ipairs({ 172, 173, 174, 175, 10, 11, 21, 47, 191, 177, 24, 25, 200 }) do DisableControlAction(0, c, true) end
        local rot = IsDisabledControlPressed(0, 21)
        local step, rstep = 0.005, 1.5
        local changed = false
        local function nudge(i, d) a[i] = a[i] + d changed = true end
        if IsDisabledControlPressed(0, 172) then if rot then nudge(5, rstep) else nudge(3, step) end end
        if IsDisabledControlPressed(0, 173) then if rot then nudge(5, -rstep) else nudge(3, -step) end end
        if IsDisabledControlPressed(0, 175) then if rot then nudge(7, rstep) else nudge(2, step) end end
        if IsDisabledControlPressed(0, 174) then if rot then nudge(7, -rstep) else nudge(2, -step) end end
        if IsDisabledControlPressed(0, 10) then if rot then nudge(6, rstep) else nudge(4, step) end end
        if IsDisabledControlPressed(0, 11) then if rot then nudge(6, -rstep) else nudge(4, -step) end end
        if changed then reattach(obj, a) end
        if IsDisabledControlJustPressed(0, 47) then idx = idx % #held + 1 end
        if IsDisabledControlJustPressed(0, 191) then
            local txt = line(a)
            lib.setClipboard(txt)
            print('[nayzeee-tuning] ' .. txt)
            Notify(L('adjust_copied'), 'success')
        end
        if IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 200) then break end
        local txt = L('adjust_help', idx, #held, line(a))
        if txt ~= shown then shown = txt Bridge.TextUI(txt) end
    end
    Bridge.TextUI(false)
    adjusting = false
    if spawned then clearHeld() stopAnim() end
end

RegisterNetEvent('nayzeee-tuning:carryAdjust', function(partId)
    if adjusting then adjusting = false return end
    if active then
        if #held == 0 then return Notify(L('adjust_nothing'), 'error') end
        return CreateThread(function() adjustLoop(false) end)
    end
    if cache.vehicle then return Notify(L('adjust_on_foot'), 'error') end
    partId = partId or 'mod_1'
    if partId == 'hoist' or partId == 'engine' then
        local H = IC.Hoist
        clearHeld()
        local hoist, engine = spawnProp(H.prop), spawnProp(H.part)
        if hoist then attach(hoist, H.attach) held[#held + 1] = hoist end
        if hoist and engine then attachToProp(engine, hoist, H.partOffset) held[#held + 1] = engine end
        carry = { anim = H.pushAnim, run = false }
        playLoop(H.pushAnim)
    elseif partId == 'jacks' then
        local J = IC.Jacks
        clearHeld()
        local a, b = spawnProp(J.prop), spawnProp(J.prop)
        if a then attach(a, J.attach) held[#held + 1] = a end
        if b then attach(b, J.attach2) held[#held + 1] = b end
        carry = { anim = J.carryAnim, run = false }
        playLoop(J.carryAnim)
    else
        local def = Config.InstallParts[partId]
        if not def or not def.prop then return Notify(L('adjust_unknown', partId), 'error') end
        hold(def, def.carryAnim)
    end
    if #held == 0 then return Notify(L('adjust_unknown', partId), 'error') end
    CreateThread(function() adjustLoop(true) end)
end)

--------------------------------------------------------------------- order notifications

RegisterNetEvent('nayzeee-tuning:orderEvent', function(ev)
    if ev.kind == 'new' then
        Notify(L('order_new', ev.id, ev.text), 'inform', 8000)
        UI.Send('sound', { name = 'ping', volume = 0.35 })
    end
    UI.Send('tablet:refresh', { app = 'orders' })
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearHeld()
    clearPlaced()
    if lift and DoesEntityExist(lift.veh) then FreezeEntityPosition(lift.veh, false) end
end)
