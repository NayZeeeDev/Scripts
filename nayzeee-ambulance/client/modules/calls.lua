--[[
    NAYZEEE AMBULANCE - NPC calls (client): scene builder, scene effects, extrication,
    release on scene, bystanders

    Builder: the server picks the nearest medic's client when a call's scene must exist
    ('nza:calls:build' with a plan: models, offsets, poses - never medical data). This client
    snaps the place to a road (snap = 'road', pulled to the kerb) or walkable ground
    (snap = 'ped'), spawns networked vehicles (crash deformation, smashed windows, open hood,
    burst tyres, hazard lights, low engine health = GTA engine smoke), victims (seated /
    trapped in the car or posed on the ground, damage packs, wet clothes), debris props and
    the 911 caller / CPR bystander, then reports the net ids ('nza:calls:built'). The server
    checks every entity before the victims become patients.

    Scene effects (every client within Config.Calls.fx.radius): looped smoke / fire particles
    on vehicles, props or spots. Put them out:
        smoke on a car → hold [E] at the engine "Cut the engine" (only once the car is not burning)
        fire           → spray it with the fire extinguisher (or hold [E] "Smother" when
                         Config.Calls.fx.fireNeedsExtinguisher = false)
    Effects also stop by themselves after Config.Calls.fx.duration.

    Patient options (NZA.Interact): nza_calls_extricate 'Cut free' (order 11, trapped victims;
    also an [E] prompt at the car), nza_calls_release 'Release on scene' (order 92).
    Bystanders (owner client): the caller stands on the phone and waves the first medic over;
    the CPR bystander does compressions on the arrest victim until a medic is close.

    Net events handled: nza:calls:build, nza:calls:scenes, nza:calls:scene, nza:calls:sceneRemove,
                        nza:calls:fade, nza:calls:fallback
    Net events sent:    nza:calls:built, nza:calls:buildFailed, nza:calls:fxOut
    Callbacks used:     nza:calls:sync, nza:calls:extricate, nza:calls:release
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Calls = NZA.Calls or {}
local C = NZA.Calls

local scenes = {}         -- [id] = public scene
local fxHandles = {}      -- ['scene:fx'] = handle
local building = false
local fallbackBlips = {}  -- [id] = { blip, until }
local sprayed = {}        -- ['scene:fx'] = seconds sprayed
local busy = false
local warnedFire = {}
local lastSprayQ = -1

local function cfg(section)
    local c = Config.Calls or {}
    if section then return c[section] or {} end
    return c
end

local function L(key, ...) return NZA.L(key, ...) end

local function toast(msg, kind)
    if NZA.UI and NZA.UI.Toast then NZA.UI.Toast({ message = msg, type = kind or 'info' }) end
end

-- ════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════════════

local function loadModel(model, timeout)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) or not IsModelValid(hash) then return nil end
    RequestModel(hash)
    local t = GetGameTimer() + (timeout or 8000)
    while not HasModelLoaded(hash) and GetGameTimer() < t do Wait(25) end
    if not HasModelLoaded(hash) then return nil end
    return hash
end

local function loadDict(dict)
    if not dict or not DoesAnimDictExist(dict) then return false end
    RequestAnimDict(dict)
    local t = GetGameTimer() + 2500
    while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(25) end
    return HasAnimDictLoaded(dict)
end

local function netOf(ent, timeout)
    local deadline = GetGameTimer() + (timeout or 3000)
    while not NetworkGetEntityIsNetworked(ent) and GetGameTimer() < deadline do
        NetworkRegisterEntityAsNetworked(ent)
        Wait(50)
    end
    if not NetworkGetEntityIsNetworked(ent) then return nil end
    local net = NetworkGetNetworkIdFromEntity(ent)
    SetNetworkIdCanMigrate(net, true)
    SetNetworkIdExistsOnAllMachines(net, true)
    return net
end

local function entOf(net)
    net = tonumber(net)
    if not net or not NetworkDoesNetworkIdExist(net) then return 0 end
    local ent = NetworkGetEntityFromNetworkId(net)
    if ent == 0 or not DoesEntityExist(ent) then return 0 end
    return ent
end
C.EntOf = entOf

local function control(ent, ms)
    if ent == 0 then return false end
    if NetworkHasControlOfEntity(ent) then return true end
    local t = GetGameTimer() + (ms or 1500)
    while not NetworkHasControlOfEntity(ent) and GetGameTimer() < t do
        NetworkRequestControlOfEntity(ent)
        Wait(50)
    end
    return NetworkHasControlOfEntity(ent)
end

local function groundAt(x, y, zHint)
    RequestCollisionAtCoord(x, y, zHint)
    for _, dz in ipairs({ 2.0, 6.0, 15.0, 40.0, 80.0 }) do
        local ok, gz = GetGroundZFor_3dCoord(x, y, zHint + dz, false)
        if ok and math.abs(gz - zHint) < 30.0 then return gz end
    end
    return zHint
end

-- local offset (x right, y forward) → world
local function worldOf(o, off)
    local h = math.rad(o.w)
    local ox, oy = (off and off.x) or 0.0, (off and off.y) or 0.0
    local x = o.x + ox * math.cos(h) - oy * math.sin(h)
    local y = o.y + ox * math.sin(h) + oy * math.cos(h)
    return x, y, groundAt(x, y, o.z + ((off and off.z) or 0.0))
end

-- ════════════════════════════════════════════════════════════════════════
-- BUILDER
-- ════════════════════════════════════════════════════════════════════════

local function snapOrigin(plan)
    local l = plan.loc
    local o = { x = l.x, y = l.y, z = l.z, w = l.w or 0.0 }
    RequestCollisionAtCoord(o.x, o.y, o.z)
    local t = GetGameTimer() + 2000
    while GetGameTimer() < t and not HasCollisionLoadedAroundEntity(PlayerPedId()) do Wait(50) end
    if plan.snap == 'road' then
        local found, pos, heading = GetClosestVehicleNodeWithHeading(o.x, o.y, o.z, 1, 3.0, 0)
        if found and #(vector3(pos.x, pos.y, pos.z) - vector3(o.x, o.y, o.z)) < 80.0 then
            local h = math.rad(heading)
            local side = tonumber(plan.roadside) or 3.5
            o.x, o.y, o.z, o.w = pos.x + math.cos(h) * side, pos.y + math.sin(h) * side, pos.z, heading
        end
    elseif plan.snap == 'ped' then
        local found, pos = GetSafeCoordForPed(o.x, o.y, o.z, true, 16)
        if found and #(vector3(pos.x, pos.y, pos.z) - vector3(o.x, o.y, o.z)) < 40.0 then
            o.x, o.y, o.z = pos.x, pos.y, pos.z
        end
    end
    o.z = groundAt(o.x, o.y, o.z)
    return o
end

local DAMAGE_DIR = {
    front = { 0.0, 1.9, 0.15 }, rear = { 0.0, -2.0, 0.15 }, left = { -0.95, 0.2, 0.25 }, right = { 0.95, 0.2, 0.25 },
}

local function crashVehicle(veh, spec, plan)
    SetVehicleOnGroundProperly(veh)
    SetVehicleEngineOn(veh, false, true, true)
    SetVehicleUndriveable(veh, true)
    SetVehicleEngineCanDegrade(veh, false)
    SetVehicleDoorsLocked(veh, 1)
    SetVehicleDirtLevel(veh, 6.0 + math.random() * 6.0)
    for dir, amount in pairs(type(spec.damage) == 'table' and spec.damage or {}) do
        local d = DAMAGE_DIR[dir]
        amount = tonumber(amount) or 0.0
        if d and amount > 0 then
            for i = 1, 3 + math.floor(amount * 3) do
                local jx = (math.random() - 0.5) * 0.7
                SetVehicleDamage(veh, d[1] + jx, d[2], d[3], 450.0 + 650.0 * amount, 180.0, true)
            end
        end
    end
    if spec.damage and next(spec.damage) then
        SetVehicleBodyHealth(veh, 250.0 + math.random() * 200.0)
        SetVehiclePetrolTankHealth(veh, 650.0)
    end
    for _, w in ipairs(type(spec.windows) == 'table' and spec.windows or {}) do SmashVehicleWindow(veh, w) end
    for _, door in ipairs(type(spec.doors) == 'table' and spec.doors or {}) do SetVehicleDoorOpen(veh, door, false, true) end
    if (tonumber(spec.tyres) or 0) > 0 then
        for i = 0, 5 do
            if math.random() < spec.tyres then SetVehicleTyreBurst(veh, i, true, 1000.0) end
        end
    end
    if spec.smoke and plan.engineSmoke then SetVehicleEngineHealth(veh, 280.0) end
    if plan.hazard and spec.damage and next(spec.damage) then
        SetVehicleIndicatorLights(veh, 0, true)
        SetVehicleIndicatorLights(veh, 1, true)
    end
    if spec.flip then
        local r = GetEntityRotation(veh, 2)
        SetEntityRotation(veh, r.x, 180.0, r.z, 2, true)
    end
end

local function makePed(hash, x, y, z, h)
    local ped = CreatePed(4, hash, x, y, z, h, true, true)
    if ped == 0 then return 0 end
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedDiesWhenInjured(ped, false)
    SetPedConfigFlag(ped, 281, true)
    SetPedCanRagdollFromPlayerImpact(ped, false)
    SetPedKeepTask(ped, true)
    if (cfg('npc')).invincible ~= false then SetEntityInvincible(ped, true) end
    SetPedRandomComponentVariation(ped, 0)
    return ped
end

local function build(plan)
    local created = {}
    local result = { vehicles = {}, victims = {}, props = {}, bystanders = {} }
    local function track(ent) created[#created + 1] = ent end
    local timeout = tonumber(plan.modelTimeout) or 8000
    local o = snapOrigin(plan)
    result.origin = { x = o.x, y = o.y, z = o.z, w = o.w }

    -- vehicles
    local vehEnts = {}
    for _, v in ipairs(plan.vehicles or {}) do
        local hash = loadModel(v.model, timeout)
        if hash then
            local x, y, z = worldOf(o, v.offset)
            local veh = CreateVehicle(hash, x, y, z + 0.4, (o.w + (v.heading or 0.0)) % 360.0, true, true)
            if veh ~= 0 then
                track(veh)
                SetEntityAsMissionEntity(veh, true, true)
                crashVehicle(veh, v, plan)
                SetVehicleNumberPlateText(veh, ('%02d%s%03d'):format(math.random(10, 99), string.char(math.random(65, 90), math.random(65, 90), math.random(65, 90)), math.random(0, 999)))
                vehEnts[v.idx] = veh
                local net = netOf(veh)
                if net then result.vehicles[#result.vehicles + 1] = { i = v.idx, n = net } end
            end
            SetModelAsNoLongerNeeded(hash)
        end
    end

    -- victims
    local victimEnts = {}
    for _, v in ipairs(plan.victims or {}) do
        local hash = loadModel(v.model, timeout)
        if hash then
            local veh = v.vehicle and vehEnts[v.vehicle]
            local ped
            if veh then
                local c = GetEntityCoords(veh)
                ped = makePed(hash, c.x, c.y, c.z + 2.0, GetEntityHeading(veh))
                if ped ~= 0 then SetPedIntoVehicle(ped, veh, v.seat or -1) end
            else
                local x, y, z = worldOf(o, v.offset)
                ped = makePed(hash, x, y, z, (o.w + (v.heading or 0.0)) % 360.0)
            end
            if ped ~= 0 then
                track(ped)
                victimEnts[v.idx] = ped
                for _, pack in ipairs(type(v.dp) == 'table' and v.dp or {}) do ApplyPedDamagePack(ped, pack, 0.0, 1.0) end
                if v.wet then SetPedWetnessHeight(ped, 2.0) end
                if NZA.CallsNpc and NZA.CallsNpc.ApplyPose then
                    local pose = v.pose
                    if veh and v.trapped then pose = 'trapped' elseif veh then pose = nil end
                    if pose == 'sit' and v.sex == 'f' then pose = 'sit_f' end
                    if pose then NZA.CallsNpc.ApplyPose(ped, pose) end
                end
                local net = netOf(ped)
                if net then result.victims[#result.victims + 1] = { i = v.idx, n = net } end
            end
            SetModelAsNoLongerNeeded(hash)
        end
    end

    -- props
    for _, pr in ipairs(plan.props or {}) do
        local hash = loadModel(pr.model, math.min(timeout, 4000))
        if hash then
            local x, y, z = worldOf(o, pr.offset)
            local obj = CreateObject(hash, x, y, z, true, true, false)
            if obj ~= 0 then
                track(obj)
                SetEntityAsMissionEntity(obj, true, true)
                local rot = pr.rot or {}
                SetEntityHeading(obj, (o.w + (rot.z or 0.0)) % 360.0)
                PlaceObjectOnGroundProperly(obj)
                if (rot.x or 0.0) ~= 0.0 or (rot.y or 0.0) ~= 0.0 then
                    SetEntityRotation(obj, rot.x or 0.0, rot.y or 0.0, (o.w + (rot.z or 0.0)) % 360.0, 2, true)
                end
                FreezeEntityPosition(obj, true)
                local net = netOf(obj)
                if net then result.props[#result.props + 1] = { i = pr.idx, n = net } end
            end
            SetModelAsNoLongerNeeded(hash)
        end
    end

    -- bystanders
    for _, b in ipairs(plan.bystanders or {}) do
        local hash = loadModel(b.model, timeout)
        if hash then
            local x, y, z, h
            local victim = b.victim and victimEnts[b.victim]
            if b.role == 'cpr' and victim then
                local vc = GetEntityCoords(victim)
                local vh = GetEntityHeading(victim)
                local off = GetOffsetFromEntityInWorldCoords(victim, b.offset and b.offset.x or 0.75, b.offset and b.offset.y or 0.15, 0.0)
                x, y, z = off.x, off.y, groundAt(off.x, off.y, vc.z)
                h = (vh + (b.heading or 90.0)) % 360.0
            else
                x, y, z = worldOf(o, b.offset)
                -- face the scene
                h = (math.deg(math.atan(o.y - y, o.x - x)) - 90.0) % 360.0
            end
            local ped = makePed(hash, x, y, z, h)
            if ped ~= 0 then
                track(ped)
                local net = netOf(ped)
                if net then result.bystanders[#result.bystanders + 1] = { i = b.idx, n = net } end
                if b.role == 'cpr' then
                    local a = Config.AIMedic and Config.AIMedic.cprAnim or { dict = 'mini@cpr@char_a@cpr_str', clip = 'cpr_pumpchest' }
                    if loadDict(a.dict) then TaskPlayAnim(ped, a.dict, a.clip, 8.0, -8.0, -1, 1, 0.0, false, false, false) end
                elseif b.scenario then
                    TaskStartScenarioInPlace(ped, b.scenario, 0, true)
                end
            end
            SetModelAsNoLongerNeeded(hash)
        end
    end

    if #result.victims == 0 then
        for _, ent in ipairs(created) do
            if DoesEntityExist(ent) then SetEntityAsMissionEntity(ent, true, true) DeleteEntity(ent) end
        end
        return nil
    end
    Wait(400)
    return result
end

RegisterNetEvent('nza:calls:build', function(plan)
    if type(plan) ~= 'table' or type(plan.loc) ~= 'table' then return end
    CreateThread(function()
        local t = GetGameTimer() + 15000
        while building and GetGameTimer() < t do Wait(100) end
        building = true
        local ok, result = pcall(build, plan)
        building = false
        if ok and result then
            TriggerServerEvent('nza:calls:built', plan.id, plan.token, result)
        else
            if not ok then NZA.Debug('calls: build failed', result) end
            TriggerServerEvent('nza:calls:buildFailed', plan.id, plan.token, ok and 'no_victims' or 'error')
        end
    end)
end)

-- ════════════════════════════════════════════════════════════════════════
-- SCENE STORE
-- ════════════════════════════════════════════════════════════════════════

local function stopFx(key)
    local h = fxHandles[key]
    if h then
        StopParticleFxLooped(h, false)
        RemoveParticleFx(h, false)
        fxHandles[key] = nil
    end
end

local function dropScene(id)
    for key in pairs(fxHandles) do
        if key:sub(1, #id + 1) == id .. ':' then stopFx(key) end
    end
    scenes[id] = nil
end

RegisterNetEvent('nza:calls:scenes', function(list)
    if type(list) ~= 'table' then return end
    local seen = {}
    for _, s in ipairs(list) do
        if type(s) == 'table' and s.id then scenes[s.id] = s; seen[s.id] = true end
    end
    for id in pairs(scenes) do if not seen[id] then dropScene(id) end end
end)

RegisterNetEvent('nza:calls:scene', function(s)
    if type(s) ~= 'table' or not s.id then return end
    scenes[s.id] = s
    for _, f in ipairs(s.fx or {}) do
        if not f.on then stopFx(s.id .. ':' .. f.id) end
    end
end)

RegisterNetEvent('nza:calls:sceneRemove', function(id)
    if type(id) == 'string' then dropScene(id) end
end)

RegisterNetEvent('nza:calls:fade', function(nets)
    if type(nets) ~= 'table' then return end
    for _, net in ipairs(nets) do
        local ent = entOf(net)
        if ent ~= 0 and NetworkHasControlOfEntity(ent) then NetworkFadeOutEntity(ent, false, true) end
    end
end)

local function sync()
    local ok, list = pcall(lib.callback.await, 'nza:calls:sync', false)
    if ok and type(list) == 'table' then TriggerEvent('nza:calls:scenes', list) end
end

CreateThread(function()
    Wait(4000)
    sync()
end)

if Bridge and Bridge.OnPlayerLoaded then
    Bridge.OnPlayerLoaded(function() SetTimeout(3000, sync) end)
end

function C.Scenes() return scenes end

function C.SceneOfEntity(ent)
    if not ent or ent == 0 then return nil end
    local net = NetworkGetEntityIsNetworked(ent) and NetworkGetNetworkIdFromEntity(ent) or nil
    if not net then return nil end
    for _, s in pairs(scenes) do
        for _, v in ipairs(s.victims or {}) do if v.n == net then return s, v end end
    end
    return nil
end

-- ════════════════════════════════════════════════════════════════════════
-- EFFECTS
-- ════════════════════════════════════════════════════════════════════════

local assets = {}

local function loadAsset(asset)
    if assets[asset] ~= nil then return assets[asset] end
    RequestNamedPtfxAsset(asset)
    local t = GetGameTimer() + 3000
    while not HasNamedPtfxAssetLoaded(asset) and GetGameTimer() < t do Wait(25) end
    assets[asset] = HasNamedPtfxAssetLoaded(asset)
    return assets[asset]
end

local function fxPos(f)
    if f.net then
        local ent = entOf(f.net)
        if ent == 0 then return nil, 0 end
        if IsEntityAVehicle(ent) then
            local bone = GetEntityBoneIndexByName(ent, 'engine')
            if bone ~= -1 then return GetWorldPositionOfEntityBone(ent, bone), ent end
            return GetOffsetFromEntityInWorldCoords(ent, 0.0, 1.8, 0.3), ent
        end
        return GetEntityCoords(ent), ent
    end
    if f.at then return vector3(f.at.x, f.at.y, f.at.z), 0 end
    return nil, 0
end

local function startFx(key, f)
    local spec = (cfg('fx'))[f.kind]
    if type(spec) ~= 'table' or not spec.asset or not loadAsset(spec.asset) then return end
    local scale = tonumber(spec.scale) or 0.5
    local off = spec.offset or vector3(0.0, 0.0, 0.0)
    local handle
    if f.net then
        local ent = entOf(f.net)
        if ent == 0 then return end
        UseParticleFxAssetNextCall(spec.asset)
        local bone = spec.bone and GetEntityBoneIndexByName(ent, spec.bone) or -1
        if bone ~= -1 then
            handle = StartParticleFxLoopedOnEntityBone(spec.name, ent, off.x, off.y, off.z, 0.0, 0.0, 0.0, bone, scale, false, false, false)
        else
            handle = StartParticleFxLoopedOnEntity(spec.name, ent, off.x, off.y + (IsEntityAVehicle(ent) and 1.6 or 0.0), off.z, 0.0, 0.0, 0.0, scale, false, false, false)
        end
    elseif f.at then
        UseParticleFxAssetNextCall(spec.asset)
        handle = StartParticleFxLoopedAtCoord(spec.name, f.at.x, f.at.y, f.at.z, 0.0, 0.0, 0.0, scale, false, false, false, false)
    end
    if handle and handle ~= 0 then fxHandles[key] = handle end
end

local function effectsTick(me)
    local radius = tonumber(cfg('fx').radius) or 180.0
    local keep = {}
    for id, s in pairs(scenes) do
        local c = s.c and vector3(s.c.x, s.c.y, s.c.z)
        if c and #(c - me) <= radius then
            for _, f in ipairs(s.fx or {}) do
                local key = id .. ':' .. f.id
                if f.on then
                    keep[key] = true
                    if not fxHandles[key] then startFx(key, f) end
                    -- GTA's own engine smoke on the burning / smoking car (owner only)
                    if f.kind == 'smoke' and cfg('fx').engineSmoke ~= false then
                        local veh = entOf(f.net)
                        if veh ~= 0 and NetworkHasControlOfEntity(veh) and GetVehicleEngineHealth(veh) > 320.0 then
                            SetVehicleEngineHealth(veh, 280.0)
                        end
                    end
                elseif f.kind == 'smoke' then
                    local veh = entOf(f.net)
                    if veh ~= 0 and NetworkHasControlOfEntity(veh) and GetVehicleEngineHealth(veh) < 400.0 then
                        SetVehicleEngineHealth(veh, 650.0)
                    end
                end
            end
        end
    end
    for key in pairs(fxHandles) do
        if not keep[key] then stopFx(key) end
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- PUT IT OUT (cut engine / extinguisher / smother) + CUT FREE prompt
-- ════════════════════════════════════════════════════════════════════════

local function anyFireOn(s, net)
    for _, f in ipairs(s.fx or {}) do
        if f.on and f.kind == 'fire' and f.net == net then return true end
    end
    return false
end

local function nearestAction(me)
    local fc = cfg('fx')
    local best, bestD = nil, math.huge
    local cut = fc.cutEngine or {}
    local sm = fc.smother or {}
    for id, s in pairs(scenes) do
        for _, f in ipairs(s.fx or {}) do
            if f.on then
                local pos = fxPos(f)
                if pos then
                    local d = #(pos - me)
                    if f.kind == 'smoke' and f.net and not anyFireOn(s, f.net) and d <= (tonumber(cut.distance) or 3.2) and d < bestD then
                        best, bestD = { kind = 'cut', scene = id, fx = f, pos = pos }, d
                    elseif (f.kind == 'groundSmoke' or ((f.kind == 'fire' or f.kind == 'groundFire') and fc.fireNeedsExtinguisher == false))
                        and d <= (tonumber(sm.distance) or 2.6) and d < bestD then
                        best, bestD = { kind = 'smother', scene = id, fx = f, pos = pos }, d
                    elseif (f.kind == 'fire' or f.kind == 'groundFire') and d <= 4.0 and not warnedFire[id .. ':' .. f.id] then
                        warnedFire[id .. ':' .. f.id] = true
                        toast(L('calls.need_extinguisher'), 'warning')
                    end
                end
            end
        end
        -- trapped victims (cut free)
        local ec = cfg('extricate')
        if ec.enabled ~= false and NZA.Perm and NZA.Perm(ec.perm or 'transport') then
            for _, v in ipairs(s.victims or {}) do
                if v.tr then
                    local ped = entOf(v.n)
                    if ped ~= 0 then
                        local d = #(GetEntityCoords(ped) - me)
                        if d <= (tonumber(ec.distance) or 2.6) and d < bestD then
                            best, bestD = { kind = 'extricate', scene = id, ped = ped, net = v.n }, d
                        end
                    end
                end
            end
        end
    end
    return best
end

local function holdWork(label, seconds, anim, prop)
    local opts = {
        duration = math.floor(seconds * 1000), label = label, useWhileDead = false, canCancel = true,
        disable = { move = true, car = true, combat = true },
    }
    if anim and anim.dict then opts.anim = { dict = anim.dict, clip = anim.clip, flag = 1 } end
    if prop then opts.prop = { model = prop, bone = 57005, pos = vec3(0.1, 0.03, -0.02), rot = vec3(-80.0, 0.0, 0.0) } end
    local style = Config.EasyMode and Config.EasyMode.style or 'bar'
    if style == 'circle' and lib.progressCircle then
        opts.position = 'bottom'
        return lib.progressCircle(opts)
    end
    return lib.progressBar(opts)
end

local function doFxAction(a)
    local fc = cfg('fx')
    local spec = a.kind == 'cut' and (fc.cutEngine or {}) or (fc.smother or {})
    local ped = PlayerPedId()
    TaskTurnPedToFaceCoord(ped, a.pos.x, a.pos.y, a.pos.z, 600)
    Wait(600)
    local done = holdWork(L(a.kind == 'cut' and 'calls.cut_engine' or 'calls.smother'), tonumber(spec.time) or 4, spec.anim)
    ClearPedTasks(ped)
    if done then TriggerServerEvent('nza:calls:fxOut', a.scene, a.fx.id, a.kind) end
end

-- the medic pulls the victim out of the car (or from under the load)
local function pullOut(ped, res)
    if ped == 0 then return end
    local veh = res and res.veh and entOf(res.veh) or 0
    if veh == 0 and IsPedInAnyVehicle(ped, false) then veh = GetVehiclePedIsIn(ped, false) end
    if veh ~= 0 and res and res.breakDoor and control(veh, 1500) then
        local seat = tonumber(res.seat) or -1
        local door = ({ [-1] = 0, [0] = 1, [1] = 2, [2] = 3 })[seat] or 0
        SetVehicleDoorBroken(veh, door, false)
    end
    if not control(ped, 2000) then return end
    if IsPedInAnyVehicle(ped, false) then
        local v = GetVehiclePedIsIn(ped, false)
        local seat = tonumber(res and res.seat) or -1
        local side = (seat == -1 or seat == 1) and -1.6 or 1.6
        local out = GetOffsetFromEntityInWorldCoords(v, side, 0.4, 0.0)
        TaskLeaveVehicle(ped, v, 16)
        Wait(200)
        ClearPedTasksImmediately(ped)
        local _, gz = GetGroundZFor_3dCoord(out.x, out.y, out.z + 1.5, false)
        SetEntityCoords(ped, out.x, out.y, (gz and gz > 0.0) and gz or out.z, false, false, false, false)
        SetEntityHeading(ped, GetEntityHeading(v) + (side < 0 and 90.0 or -90.0))
    else
        ClearPedTasks(ped)
    end
    if NZA.CallsNpc and NZA.CallsNpc.ApplyPose then NZA.CallsNpc.ApplyPose(ped, 'writhe') end
end

local function extricate(ped, target)
    if busy then return end
    busy = true
    target = target or NZA.Target.FromEntity(ped)
    local ec = cfg('extricate')
    local ok, res = pcall(lib.callback.await, 'nza:calls:extricate', false, target, 'start')
    if not ok or type(res) ~= 'table' or not res.ok then
        toast(type(res) == 'table' and res.msg or L('calls.extricate_fail'), 'error')
        busy = false
        return
    end
    local me = PlayerPedId()
    local pc = GetEntityCoords(ped)
    TaskTurnPedToFaceCoord(me, pc.x, pc.y, pc.z, 600)
    Wait(600)
    local done = holdWork(L('calls.extricating'), tonumber(res.time) or tonumber(ec.time) or 12, ec.anim, ec.prop or nil)
    ClearPedTasks(me)
    if not done then
        pcall(lib.callback.await, 'nza:calls:extricate', false, target, 'cancel')
        busy = false
        return
    end
    local ok2, fin = pcall(lib.callback.await, 'nza:calls:extricate', false, target, 'finish', res.token)
    if ok2 and type(fin) == 'table' and fin.ok then
        pullOut(ped, fin)
        toast(fin.msg or L('calls.extricated', ''), 'success')
    else
        toast(type(fin) == 'table' and fin.msg or L('calls.extricate_fail'), 'error')
    end
    busy = false
end
C.Extricate = extricate

-- extinguisher spray detection (local player)
local function sprayTick(me, dt)
    local sp = cfg('fx').spray or {}
    local ped = PlayerPedId()
    local weapon = GetHashKey(sp.weapon or 'WEAPON_FIREEXTINGUISHER')
    if GetSelectedPedWeapon(ped) ~= weapon or not IsPedShooting(ped) then return false end
    local camRot = GetGameplayCamRot(2)
    local pitch, yaw = math.rad(camRot.x), math.rad(camRot.z)
    local dir = vector3(-math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch))
    local range = tonumber(sp.distance) or 9.0
    for id, s in pairs(scenes) do
        for _, f in ipairs(s.fx or {}) do
            if f.on and (f.kind == 'fire' or f.kind == 'groundFire' or f.kind == 'groundSmoke') then
                local pos = fxPos(f)
                if pos then
                    local to = pos - me
                    local d = #to
                    if d <= range and d > 0.1 then
                        local dot = (to.x * dir.x + to.y * dir.y + to.z * dir.z) / d
                        if dot > 0.75 then
                            local key = id .. ':' .. f.id
                            sprayed[key] = (sprayed[key] or 0) + dt
                            local need = tonumber(sp.time) or 3.5
                            if NZA.UI and NZA.UI.Prompt then
                                local q = math.floor(math.min(1, sprayed[key] / need) * 20) / 20
                                if q ~= lastSprayQ then
                                    lastSprayQ = q
                                    NZA.UI.Prompt('calls_spray', { key = 'LMB', label = L('calls.spraying'), progress = q })
                                end
                            end
                            if sprayed[key] >= need then
                                sprayed[key] = 0
                                TriggerServerEvent('nza:calls:fxOut', id, f.id, 'spray')
                            end
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

CreateThread(function()
    local shown = nil
    local sprayShown = false
    while true do
        local me = GetEntityCoords(PlayerPedId())
        local ok, err = pcall(effectsTick, me)
        if not ok then NZA.Debug('calls fx', err) end
        -- anything to do within reach?
        local near = false
        for _, s in pairs(scenes) do
            if s.c and #(vector3(s.c.x, s.c.y, s.c.z) - me) < 40.0 then near = true break end
        end
        if not near then
            if shown then NZA.UI.HidePrompt('calls_act') shown = nil end
            Wait(750)
        else
            local frames = 0
            local last = GetGameTimer()
            while frames < 30 do
                Wait(0)
                frames = frames + 1
                local now = GetGameTimer()
                local dt = (now - last) / 1000.0
                last = now
                me = GetEntityCoords(PlayerPedId())
                local spraying = sprayTick(me, dt)
                if not spraying and sprayShown then
                    NZA.UI.HidePrompt('calls_spray')
                    lastSprayQ = -1
                end
                sprayShown = spraying
                local a = nil
                if not busy and not IsPedInAnyVehicle(PlayerPedId(), false) then
                    if frames % 10 == 1 then a = nearestAction(me) else a = shown end
                end
                if a then
                    local label = a.kind == 'cut' and L('calls.cut_engine') or (a.kind == 'smother' and L('calls.smother') or L('calls.opt_extricate'))
                    local sub = a.kind == 'cut' and L('calls.cut_engine_sub') or (a.kind == 'smother' and L('calls.smother_sub') or L('calls.trapped_note'))
                    if not shown or shown.kind ~= a.kind or shown.fx ~= a.fx or shown.ped ~= a.ped then
                        NZA.UI.Prompt('calls_act', { key = 'E', label = label, sub = sub })
                    end
                    shown = a
                    if IsControlJustPressed(0, 38) then
                        NZA.UI.HidePrompt('calls_act')
                        shown = nil
                        busy = true
                        CreateThread(function()
                            if a.kind == 'extricate' then
                                busy = false
                                extricate(a.ped)
                            else
                                local ok2, err2 = pcall(doFxAction, a)
                                if not ok2 then NZA.Debug('calls fx action', err2) end
                                busy = false
                            end
                        end)
                    end
                elseif shown then
                    NZA.UI.HidePrompt('calls_act')
                    shown = nil
                end
            end
        end
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- BYSTANDERS (owner client)
-- ════════════════════════════════════════════════════════════════════════

local byState = {}   -- [ped] = role applied

local function bystanderTick()
    for _, s in pairs(scenes) do
        for _, b in ipairs(s.bystanders or {}) do
            local ped = entOf(b.n)
            if ped ~= 0 and NetworkHasControlOfEntity(ped) then
                local bag = Entity(ped).state.nzaBy
                local role = type(bag) == 'table' and bag.role or 'caller'
                SetBlockingOfNonTemporaryEvents(ped, true)
                if cfg('npc').invincible ~= false then SetEntityInvincible(ped, true) end
                if role == 'cpr' then
                    local a = Config.AIMedic and Config.AIMedic.cprAnim or { dict = 'mini@cpr@char_a@cpr_str', clip = 'cpr_pumpchest' }
                    if not IsEntityPlayingAnim(ped, a.dict, a.clip, 3) and loadDict(a.dict) then
                        TaskPlayAnim(ped, a.dict, a.clip, 8.0, -8.0, -1, 1, 0.0, false, false, false)
                    end
                elseif role == 'watch' then
                    if byState[ped] ~= 'watch' then
                        byState[ped] = 'watch'
                        CreateThread(function()
                            ClearPedTasks(ped)
                            if bag and bag.wave and loadDict('friends@frj@ig_1') then
                                TaskPlayAnim(ped, 'friends@frj@ig_1', 'wave_a', 8.0, -8.0, 2600, 48, 0.0, false, false, false)
                                Wait(2600)
                            elseif bag and bag.v then
                                local victim = entOf(bag.v)
                                if victim ~= 0 then
                                    local away = GetOffsetFromEntityInWorldCoords(victim, 2.6, -1.4, 0.0)
                                    TaskGoStraightToCoord(ped, away.x, away.y, away.z, 1.0, 4000, GetEntityHeading(ped), 0.4)
                                    Wait(3000)
                                    local vc = GetEntityCoords(victim)
                                    TaskTurnPedToFaceCoord(ped, vc.x, vc.y, vc.z, 800)
                                    Wait(800)
                                end
                            end
                            if DoesEntityExist(ped) then
                                TaskStartScenarioInPlace(ped, (bag and bag.scenario) or 'WORLD_HUMAN_STAND_IMPATIENT', 0, true)
                            end
                        end)
                    end
                else
                    local sc = (type(bag) == 'table' and bag.scenario) or 'WORLD_HUMAN_STAND_MOBILE'
                    if not IsPedUsingAnyScenario(ped) and not GetIsTaskActive(ped, 134) then
                        TaskStartScenarioInPlace(ped, sc, 0, true)
                    end
                end
            end
        end
    end
    for ped in pairs(byState) do if not DoesEntityExist(ped) then byState[ped] = nil end end
end

CreateThread(function()
    while true do
        Wait(1000)
        if next(scenes) ~= nil then
            local ok, err = pcall(bystanderTick)
            if not ok then NZA.Debug('calls bystanders', err) end
        end
        -- fallback pages (no dispatch module): drop the blip on arrival or after 10 min
        if next(fallbackBlips) then
            local me = GetEntityCoords(PlayerPedId())
            for id, fb in pairs(fallbackBlips) do
                if GetGameTimer() > fb.untilAt or #(me - fb.coords) < 30.0 then
                    RemoveBlip(fb.blip)
                    fallbackBlips[id] = nil
                end
            end
        end
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- INTERACTIONS
-- ════════════════════════════════════════════════════════════════════════

NZA.Interact.Add({
    name = 'nza_calls_extricate', label = L('calls.opt_extricate'), icon = 'wrench', order = 11,
    perm = (Config.Calls and Config.Calls.extricate and Config.Calls.extricate.perm) or 'transport',
    states = { alive = true, wounded = true, arrest = true, dead = true }, npc = true, player = false, distance = 2.8,
    canInteract = function(entity)
        if not (Config.Calls and Config.Calls.extricate and Config.Calls.extricate.enabled ~= false) then return false end
        local b = Entity(entity).state.nzaNpc
        return type(b) == 'table' and b.tr == true
    end,
    onSelect = function(entity, target) extricate(entity, target) end,
})

NZA.Interact.Add({
    name = 'nza_calls_release', label = L('calls.opt_release'), icon = 'check', order = 92,
    perm = (Config.Calls and Config.Calls.npc and Config.Calls.npc.release and Config.Calls.npc.release.perm) or 'assess',
    states = { alive = true }, npc = true, player = false, distance = 2.5,
    canInteract = function(entity)
        local rc = Config.Calls and Config.Calls.npc and Config.Calls.npc.release or {}
        if rc.enabled == false then return false end
        local b = Entity(entity).state.nzaNpc
        return type(b) == 'table' and b.c ~= nil and not b.rel and not b.ho and not b.tr
    end,
    onSelect = function(entity, target)
        local ok, res = pcall(lib.callback.await, 'nza:calls:release', false, target)
        if ok and type(res) == 'table' then
            toast(res.msg or '', res.ok and 'success' or 'error')
        end
    end,
})

-- ════════════════════════════════════════════════════════════════════════
-- FALLBACK PAGE (no dispatch module installed)
-- ════════════════════════════════════════════════════════════════════════

RegisterNetEvent('nza:calls:fallback', function(d)
    if type(d) ~= 'table' or not tonumber(d.x) then return end
    local blip = AddBlipForCoord(d.x + 0.0, d.y + 0.0, d.z + 0.0)
    SetBlipSprite(blip, 153)
    SetBlipColour(blip, d.priority == 1 and 1 or (d.priority == 2 and 47 or 2))
    SetBlipScale(blip, 0.9)
    SetBlipFlashes(blip, true)
    SetBlipRoute(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(tostring(d.title or 'EMS'))
    EndTextCommandSetBlipName(blip)
    fallbackBlips[d.id or tostring(blip)] = { blip = blip, coords = vector3(d.x, d.y, d.z), untilAt = GetGameTimer() + 600000 }
    if NZA.UI and NZA.UI.Toast then
        NZA.UI.Toast({ title = tostring(d.code or ''), message = L('calls.fallback_call', tostring(d.title or '')), type = 'warning', duration = 8000 })
    end
    PlaySoundFrontend(-1, 'Event_Start_Text', 'GTAO_FM_Events_Soundset', false)
end)

-- ════════════════════════════════════════════════════════════════════════
-- CLEANUP
-- ════════════════════════════════════════════════════════════════════════

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for key in pairs(fxHandles) do stopFx(key) end
    for _, fb in pairs(fallbackBlips) do RemoveBlip(fb.blip) end
    fallbackBlips = {}
    if NZA.UI and NZA.UI.HidePrompt then
        pcall(NZA.UI.HidePrompt, 'calls_act')
        pcall(NZA.UI.HidePrompt, 'calls_spray')
    end
end)
