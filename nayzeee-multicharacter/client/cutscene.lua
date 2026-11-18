if not NAYZEEE_LOCK_OK then return end

--[[
    Departure cutscene (contract §8 + §10). Cutscene.Run(theme) blocks until the screen is black.
      steps     fired at `at` ms on a timeline, each in its own thread (pcall'd: a broken step never stalls the run)
      camera    multi-point track; rel space of the main mark, or entity-local with attach = 'vehicle1' | 'main'
                (chase cam). follow = 'vehicle1' | 'main' keeps the camera pointed at that entity.
      fade      DoScreenFadeOut at fadeAt (forced early enough to be black at `duration`)
    Every step degrades gracefully: missing vehicle / crew / pet / partner = step skipped.
]]

Cutscene = { running = false, token = 0, fx = {}, assets = {}, entered = {}, jumped = {}, tasks = {} }

local Steps = {}

local function alive(my) return Cutscene.running and Cutscene.token == my end
local function rel(off) return NZ.Rel(Scene.main, off or vec3(0.0, 0.0, 0.0)) end
local function target(s) return Actors.Target(s.target) end

local function actorOf(ped)
    for _, a in pairs(Actors.list) do if a.ped == ped then return a end end
end

-- Marks a ped as tasked by this step (a later "clear after time" must not cancel a newer task)
local function claim(ped)
    Cutscene.tasks[ped] = (Cutscene.tasks[ped] or 0) + 1
    return Cutscene.tasks[ped]
end

-- Actors that move must be unfrozen, collidable and free of pose retries
local function free(ped)
    if not ped or not DoesEntityExist(ped) then return false end
    U.StopPose(ped)
    if IsEntityAttached(ped) then DetachEntity(ped, true, true) end
    FreezeEntityPosition(ped, false)
    SetEntityCollision(ped, true, true)
    claim(ped)
    return true
end

local function strip(ped)
    U.ClearProps(ped)
    RemoveAllPedWeapons(ped, true)
    local a = actorOf(ped)
    if a then a.weapon = nil end
end

local function freeSeat(veh, want)
    if want and IsVehicleSeatFree(veh, want) then return want end
    for s = 0, GetVehicleMaxNumberOfPassengers(veh) - 1 do
        if IsVehicleSeatFree(veh, s) then return s end
    end
end

-- A ped told to enter `veh` gets ms to finish, then is warped into its seat
local function waitIn(ped, veh, ms, my)
    local e = ped and Cutscene.entered[ped]
    if not e or e.veh ~= veh then return end
    local deadline = GetGameTimer() + (ms or 2500)
    while alive(my) and not IsPedInVehicle(ped, veh, false) and GetGameTimer() < deadline do Wait(50) end
    if alive(my) and not IsPedInVehicle(ped, veh, false) and IsVehicleSeatFree(veh, e.seat) then
        SetPedIntoVehicle(ped, veh, e.seat)
    end
end

local function driver(veh)
    local d = GetPedInVehicleSeat(veh, -1)
    if d ~= 0 and DoesEntityExist(d) then return d end
end

local function startVehicle(veh)
    FreezeEntityPosition(veh, false)
    SetVehicleEngineOn(veh, true, true, false)
end

-- ── steps ────────────────────────────────────────────────────────────────
-- Partners / squad wave, couple pose released
Steps.goodbye = function()
    if Couple.active then
        local b = Couple.active.b
        Couple.Stop()
        local a = actorOf(b)
        if a and not a.seat then Actors.Place(a) end
    end
    for slot = 2, 4 do
        local a = Actors.list[slot]
        if a and DoesEntityExist(a.ped) then
            -- flag 48 = upper body + secondary: layered on the idle / seat anim
            U.Pose(a.ped, Config.GoodbyeAnim, { keepTasks = true, keepProps = true })
        end
    end
end

-- Clear weapon + handheld props on the main actor
Steps.holster = function(s)
    local ped = target(s)
    if not ped or not DoesEntityExist(ped) then return end
    strip(ped)
    local a = actorOf(ped)
    if a and a.seat and a.seat.anim then
        U.Pose(ped, a.seat.anim)          -- seated: drop the layered pose, keep sitting
    else
        U.StopPose(ped)
        ClearPedTasks(ped)
    end
end

Steps.enterVehicle = function(s)
    local veh = Scene.Vehicle(s.vehicle)
    local ped = target(s)
    if not veh or not free(ped) then return end
    strip(ped)
    FreezeEntityPosition(veh, false)
    SetVehicleDoorsLocked(veh, 1)
    local seat = freeSeat(veh, s.seat or -1)
    if not seat then return end
    SetPedConfigFlag(ped, 184, true)      -- PreventAutoShuffleToDriversSeat: stay in the exact seat
    ClearPedTasks(ped)
    -- TaskEnterVehicle(ped, vehicle, timeout, seat, speed, flag 1 = resume if interrupted, p6)
    TaskEnterVehicle(ped, veh, 10000, seat, (s.speed or 1.0) + 0.0, 1, 0)
    Cutscene.entered[ped] = { veh = veh, seat = seat }
end

-- Animals can't use the enter-vehicle task: trot to the car, then warp in
Steps.petEnter = function(s, my)
    local veh = Scene.Vehicle(s.vehicle)
    local pet = Actors.pet and Actors.pet.ped
    if not veh or not free(pet) then return end
    ClearPedTasks(pet)
    TaskGoToEntity(pet, veh, -1, 2.5, 2.0, 0, 0)
    Wait(s.delay or 1600)
    if not alive(my) or not DoesEntityExist(pet) then return end
    local seat = freeSeat(veh, s.seat or 0)
    if seat then TaskWarpPedIntoVehicle(pet, veh, seat) end
end

Steps.petFollow = function()
    local pet = Actors.pet and Actors.pet.ped
    local main = Actors.Target('main')
    if not main or not free(pet) then return end
    ClearPedTasks(pet)
    -- TaskFollowToOffsetOfEntity(ped, entity, offset xyz, speed, timeout, stoppingRange, persist)
    TaskFollowToOffsetOfEntity(pet, main, 0.6, -0.8, 0.0, 1.6, -1, 0.8, true)
end

Steps.lights = function(s)
    local veh = Scene.Vehicle(s.vehicle)
    if veh then SetVehicleLights(veh, 2) end
end

Steps.engine = function(s)
    local veh = Scene.Vehicle(s.vehicle)
    if veh then startVehicle(veh) end
end

Steps.rotors = function(s)
    local veh = Scene.Vehicle(s.vehicle)
    if not veh then return end
    SetVehicleEngineOn(veh, true, true, false)
    if IsThisModelAHeli(GetEntityModel(veh)) then SetHeliBladesFullSpeed(veh) end
end

local function driveTo(s, my, taxi)
    local veh = Scene.Vehicle(s.vehicle)
    if not veh then return end
    waitIn(Actors.Target('main'), veh, 2500, my)
    if not alive(my) then return end
    local d = driver(veh)
    if not d then return end
    startVehicle(veh)
    local to = rel(s.to)
    local speed = (s.speed or 9.0) + 0.0
    -- TaskVehicleDriveToCoord(ped, veh, x, y, z, speed, p6, model, drivingStyle, stopRange, straightLineDist)
    TaskVehicleDriveToCoord(d, veh, to.x, to.y, to.z, speed, 0, GetEntityModel(veh), s.style or 786603, 2.0, -1.0)
    SetPedKeepTask(d, true)
    if taxi then
        -- Some jets ignore drive tasks on the apron: give them an initial roll
        Wait(1500)
        if alive(my) and DoesEntityExist(veh) and GetEntitySpeed(veh) < 1.0 then
            SetVehicleForwardSpeed(veh, math.min(speed, 6.0))
        end
    end
end

Steps.drive = function(s, my) driveTo(s, my, false) end
Steps.taxi = function(s, my) driveTo(s, my, true) end

Steps.fly = function(s, my)
    local veh = Scene.Vehicle(s.vehicle)
    if not veh then return end
    waitIn(Actors.Target('main'), veh, 2500, my)
    if not alive(my) then return end
    local pilot = driver(veh)
    if not pilot then return end
    startVehicle(veh)
    local to = rel(s.to)
    local speed = (s.speed or 12.0) + 0.0
    local model = GetEntityModel(veh)
    if IsThisModelAHeli(model) then
        SetHeliBladesFullSpeed(veh)
        -- TaskHeliMission(ped, heli, targetVeh, targetPed, x, y, z, 4 = goto, maxSpeed, radius, heading, flightHeight, minHeight, slowDist, flags)
        TaskHeliMission(pilot, veh, 0, 0, to.x, to.y, to.z, 4, speed, 5.0, -1.0, math.floor(to.z), 10, -1.0, 0)
    elseif IsThisModelAPlane(model) then
        -- TaskPlaneMission(ped, plane, targetVeh, targetPed, x, y, z, 4 = goto, angularDrag/speed, targetReached, heading, maxZ, minZ, p13)
        TaskPlaneMission(pilot, veh, 0, 0, to.x, to.y, to.z, 4, speed, 0.0, -1.0, math.floor(to.z + 60.0), math.floor(to.z - 10.0), false)
    else
        TaskVehicleDriveToCoord(pilot, veh, to.x, to.y, to.z, speed, 0, model, 786603, 2.0, -1.0)
    end
    SetPedKeepTask(pilot, true)
end

Steps.walkTo = function(s)
    local ped = target(s)
    if not free(ped) then return end
    local to = rel(s.to)
    local from = GetEntityCoords(ped)
    ClearPedTasks(ped)
    -- TaskGoStraightToCoord(ped, x, y, z, speed (1.0 walk, 2.0 run), timeout, targetHeading, distanceToSlide)
    TaskGoStraightToCoord(ped, to.x, to.y, to.z, (s.speed or 1.0) + 0.0, 20000, NZ.HeadingTo(from, to), 0.5)
end

-- Config.Poses id (props included) or { dict, clip, flag }; cleared after `time` ms
Steps.anim = function(s, my)
    local ped = target(s)
    if not ped or not DoesEntityExist(ped) then return end
    local def = (s.pose and NZ.PoseById(s.pose)) or (s.dict and { dict = s.dict, clip = s.clip, flag = s.flag or 49 }) or s.anim
    if not def then return end
    local mine = claim(ped)
    U.Pose(ped, def)
    if not s.time then return end
    Wait(s.time)
    if alive(my) and DoesEntityExist(ped) and Cutscene.tasks[ped] == mine then
        U.StopPose(ped)
        U.ClearProps(ped)
        ClearPedTasks(ped)
    end
end

Steps.ptfx = function(s)
    local asset = s.asset or 'core'
    RequestNamedPtfxAsset(asset)
    local deadline = GetGameTimer() + 2000
    while not HasNamedPtfxAssetLoaded(asset) and GetGameTimer() < deadline do Wait(0) end
    if not HasNamedPtfxAssetLoaded(asset) then return end
    Cutscene.assets[asset] = true
    local o, scale = s.offset or vec3(0.0, 0.0, 0.0), (s.scale or 1.0) + 0.0
    local ent = s.entity and Cam.AttachTarget(s.entity)
    UseParticleFxAsset(asset)   -- applies to the next Start* call only
    local h
    if ent then
        h = StartParticleFxLoopedOnEntity(s.name, ent, o.x, o.y, o.z, 0.0, 0.0, 0.0, scale, false, false, false)
    else
        local p = rel(o)
        h = StartParticleFxLoopedAtCoord(s.name, p.x, p.y, p.z, 0.0, 0.0, 0.0, scale, false, false, false, false)
    end
    if h and h ~= 0 then Cutscene.fx[#Cutscene.fx + 1] = h end
end

Steps.sound = function(s)
    if Settings.Get('muted') or not s.name then return end
    local ent = s.entity and Cam.AttachTarget(s.entity)
    if ent then
        PlaySoundFromEntity(-1, s.name, ent, s.set or 0, false, 0)
    else
        PlaySoundFrontend(-1, s.name, s.set or 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
    end
end

Steps.doors = function(s)
    local veh = Scene.Vehicle(s.vehicle)
    if not veh then return end
    for _, d in ipairs(s.open or {}) do SetVehicleDoorOpen(veh, d, false, false) end
    if s.close == true then
        SetVehicleDoorsShut(veh, false)
    elseif type(s.close) == 'table' then
        for _, d in ipairs(s.close) do SetVehicleDoorShut(veh, d, false) end
    end
end

-- ── in-flight steps (§10) ────────────────────────────────────────────────
local function jump(ped)
    if not ped or not DoesEntityExist(ped) then return end
    local heli = IsEntityAttached(ped) and GetEntityAttachedTo(ped) or 0
    local p = GetEntityCoords(ped)
    local away, hv = NZ.Fwd(GetEntityHeading(ped)), vec3(0.0, 0.0, 0.0)
    if heli ~= 0 and DoesEntityExist(heli) then
        local c = GetEntityCoords(heli)
        local dx, dy = p.x - c.x, p.y - c.y
        local len = math.sqrt(dx * dx + dy * dy)
        if len > 0.05 then away = vec3(dx / len, dy / len, 0.0) end
        hv = GetEntityVelocity(heli)
    end
    free(ped)
    strip(ped)
    ClearPedTasksImmediately(ped)
    -- Clear of the door so the ped doesn't snag the skid
    SetEntityCoordsNoOffset(ped, p.x + away.x * 0.7, p.y + away.y * 0.7, p.z - 0.2, false, false, false)
    GiveWeaponToPed(ped, `GADGET_PARACHUTE`, 1, false, false)
    SetEntityVelocity(ped, hv.x + away.x * 4.0, hv.y + away.y * 4.0, hv.z + 1.2)
    TaskSkyDive(ped, true)
    Cutscene.jumped[#Cutscene.jumped + 1] = ped
end

Steps.jump = function(s)
    jump(target(s))
end

Steps.squadJump = function(s, my)
    for slot = 2, 4 do
        if not alive(my) then return end
        local a = Actors.list[slot]
        if a then
            jump(a.ped)
            Wait(s.spacing or 450)
        end
    end
end

Steps.parachute = function(s, my)
    local list = Cutscene.jumped
    if s.target then list = { target(s) } end
    for _, ped in ipairs(list) do
        if DoesEntityExist(ped) then ForcePedToOpenParachute(ped) end
    end
    Wait(350)
    if not alive(my) then return end
    for _, ped in ipairs(list) do
        -- parachute state: -1 none, 0 freefall, 1 deploying, 2 open
        if DoesEntityExist(ped) and GetPedParachuteState(ped) < 1 then TaskParachute(ped, true, false) end
    end
end

-- ── runner ───────────────────────────────────────────────────────────────
local function camDef(p)
    local def = Cam.Point(p, nil, false)
    if not def then return nil end
    def.shake = p.shake ~= false
    if p.follow and not def.attach then
        local ent = Cam.AttachTarget(p.follow)
        if ent then def.entity, def.lookAt = ent, nil end
    end
    return def
end

local function camTrack(points, my)
    for i = 2, #points do
        if not alive(my) then return end
        local def = camDef(points[i])
        if def and not Cam.Go(def, points[i].time or 2000) then return end
    end
end

function Cutscene.Run(theme)
    local dep = theme and theme.departure
    Cutscene.token = Cutscene.token + 1
    local my = Cutscene.token
    Cutscene.running = true
    Cutscene.entered, Cutscene.jumped, Cutscene.tasks = {}, {}, {}
    if not dep or not Scene.main then
        U.FadeOut(600)
        Cutscene.Stop()
        return
    end

    local duration = dep.duration or 9000
    local fadeTime = dep.fadeTime or 900
    local fadeAt = math.min(dep.fadeAt or (duration - fadeTime), duration - fadeTime)

    local points = dep.camera or {}
    if points[1] then
        local def = camDef(points[1])
        if def then Cam.Go(def, 0) end
    end
    if IsScreenFadedOut() or IsScreenFadingOut() then DoScreenFadeIn(500) end

    local t0 = GetGameTimer()
    CreateThread(function() camTrack(points, my) end)

    local steps = {}
    for i, s in ipairs(dep.steps or {}) do steps[i] = s end
    table.sort(steps, function(a, b) return (a.at or 0) < (b.at or 0) end)
    CreateThread(function()
        for _, s in ipairs(steps) do
            while alive(my) and GetGameTimer() < t0 + (s.at or 0) do Wait(10) end
            if not alive(my) then return end
            local fn = Steps[s['do']]
            if fn then
                CreateThread(function()
                    local ok, err = pcall(fn, s, my)
                    if not ok then NZ.Debug('cutscene step failed', s['do'], err) end
                end)
            else
                NZ.Debug('unknown cutscene step', tostring(s['do']))
            end
        end
    end)

    while alive(my) and GetGameTimer() < t0 + fadeAt do Wait(50) end
    U.FadeOut(fadeTime)
    Cutscene.Stop()
end

function Cutscene.Stop()
    Cutscene.token = Cutscene.token + 1
    Cutscene.running = false
    for _, h in ipairs(Cutscene.fx) do StopParticleFxLooped(h, false) end
    for asset in pairs(Cutscene.assets) do RemoveNamedPtfxAsset(asset) end
    Cutscene.fx, Cutscene.assets, Cutscene.entered, Cutscene.jumped, Cutscene.tasks = {}, {}, {}, {}, {}
end
