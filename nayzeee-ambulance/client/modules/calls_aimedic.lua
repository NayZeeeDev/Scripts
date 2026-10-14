--[[
    NAYZEEE AMBULANCE - AI medic (client): drives the AI ambulance and its crew

    Runs on the client the server picked as controller (the downed player themself, or the
    nearest player for an NPC patient):
      spawn  networked ambulance + crew on a road node Config.AIMedic.spawnDistance away,
             siren & lights, map blip for the patient
      drive  TaskVehicleDriveToCoordLongrange to the patient; ETA to the server every etaUpdate s;
             stuck → reverse & retry → fade-teleport closer; driveTimeout → teleport next to the patient
      treat  crew walks over (or is placed after walkTimeout), kneels / does CPR, talks (subtitles)
      load   fade, patient into the back of the ambulance (drive mode), crew back in
      drive  to the hospital with the patient on board (exit blocked); stuck / timeout → fade there
      hand-over (patient's client) fade, out of the vehicle, onto the bed / hospital spot
      leave  the unit drives off and is deleted (server deletes it too as a fallback)
    Net events handled: nza:aimedic:run, nza:aimedic:treated, nza:aimedic:handover,
                        nza:aimedic:done, nza:aimedic:cancel
    Net events sent: nza:aimedic:spawned, eta, arrived, treating, loaded, atHospital, ready, failed
]]

if not NAYZEEE_LOCK_OK then return end

NZA.AIMedic = NZA.AIMedic or {}
local A = NZA.AIMedic

local runs = {}   -- [id] = run state

local function L(job, key, ...)
    local loc = job and job.locale
    local short = key:gsub('^calls%.', '')
    local s = (loc and loc[short]) or NZA.L(key)
    if select('#', ...) > 0 then
        local ok, out = pcall(string.format, s, ...)
        if ok then return out end
    end
    return s
end

local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local t = GetGameTimer() + 8000
    while not HasModelLoaded(hash) and GetGameTimer() < t do Wait(25) end
    return HasModelLoaded(hash) and hash or nil
end

local function loadDict(dict)
    if not dict or not DoesAnimDictExist(dict) then return false end
    RequestAnimDict(dict)
    local t = GetGameTimer() + 2500
    while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(25) end
    return HasAnimDictLoaded(dict)
end

local function netOf(ent)
    local t = GetGameTimer() + 3000
    while not NetworkGetEntityIsNetworked(ent) and GetGameTimer() < t do
        NetworkRegisterEntityAsNetworked(ent)
        Wait(50)
    end
    if not NetworkGetEntityIsNetworked(ent) then return nil end
    local net = NetworkGetNetworkIdFromEntity(ent)
    SetNetworkIdCanMigrate(net, true)
    return net
end

local function patientPed(job)
    local t = job.target
    if type(t) ~= 'table' then return 0 end
    if t.kind == 'player' then
        if t.sid == GetPlayerServerId(PlayerId()) then return PlayerPedId() end
        local idx = GetPlayerFromServerId(t.sid)
        return idx ~= -1 and GetPlayerPed(idx) or 0
    end
    local net = tonumber(t.net)
    if net and NetworkDoesNetworkIdExist(net) then return NetworkGetEntityFromNetworkId(net) end
    return 0
end

local function isSelf(job)
    return job.self == true
end

local function fade(out, ms)
    if out then
        DoScreenFadeOut(ms or 500)
        local t = GetGameTimer() + (ms or 500) + 1500
        while not IsScreenFadedOut() and GetGameTimer() < t do Wait(10) end
    else
        DoScreenFadeIn(ms or 600)
    end
end

local function send(job, name, ...)
    TriggerServerEvent('nza:aimedic:' .. name, job.id, job.token, ...)
end

local function say(job, key)
    if not isSelf(job) or not (NZA.UI and NZA.UI.Speech) then return end
    NZA.UI.Speech(L(job, 'calls.ai_name'), L(job, key), 3600)
end

-- road node at roughly minD..maxD metres from c
local function roadNodeAround(c, minD, maxD)
    for _ = 1, 30 do
        local a = math.random() * math.pi * 2
        local r = minD + math.random() * (maxD - minD)
        local found, pos, heading = GetClosestVehicleNodeWithHeading(c.x + math.cos(a) * r, c.y + math.sin(a) * r, c.z, 1, 3.0, 0)
        if found then
            local d = #(vector3(pos.x, pos.y, pos.z) - c)
            if d >= minD * 0.7 and d <= maxD * 1.4 then return vector3(pos.x, pos.y, pos.z), heading end
        end
    end
    local found, pos, heading = GetNthClosestVehicleNodeWithHeading(c.x, c.y, c.z, 25, 1, 3.0, 2.5)
    if found then return vector3(pos.x, pos.y, pos.z), heading end
    return nil
end

local function roadNear(c, maxD)
    local found, pos, heading = GetClosestVehicleNodeWithHeading(c.x, c.y, c.z, 1, 3.0, 0)
    if found and #(vector3(pos.x, pos.y, pos.z) - c) <= (maxD or 120.0) then return vector3(pos.x, pos.y, pos.z), heading end
    return nil
end

local function setupCrew(ped)
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedFleeAttributes(ped, 0, false)
    SetPedKeepTask(ped, true)
    SetEntityInvincible(ped, true)
    SetPedCanBeDraggedOut(ped, false)
    SetPedCanRagdoll(ped, false)
    SetPedConfigFlag(ped, 32, false)   -- not thrown through the windscreen
end

local function deleteAll(r)
    for _, e in ipairs({ r.veh, r.driver, r.partner }) do
        if e and e ~= 0 and DoesEntityExist(e) then
            if NetworkHasControlOfEntity(e) or not NetworkGetEntityIsNetworked(e) then
                SetEntityAsMissionEntity(e, true, true)
                DeleteEntity(e)
            end
        end
    end
    if r.blip and DoesBlipExist(r.blip) then RemoveBlip(r.blip) end
end

local function driveTo(r, dest)
    local j = r.job
    TaskVehicleDriveToCoordLongrange(r.driver, r.veh, dest.x, dest.y, dest.z, (j.speed or 28.0) + 0.0, j.drivingStyle or 787004, (j.stopRange or 14.0) + 0.0)
end

local function teleportVehicle(r, at, heading, withFade)
    if withFade then fade(true, 400) end
    SetEntityCoords(r.veh, at.x, at.y, at.z + 0.5, false, false, false, false)
    SetEntityHeading(r.veh, heading or GetEntityHeading(r.veh))
    SetVehicleOnGroundProperly(r.veh)
    if withFade then
        Wait(300)
        fade(false, 500)
    end
end

-- drive loop shared by "to the patient" and "to the hospital"
-- returns 'arrived' | 'teleported' | 'cancelled'
local function driveLoop(r, getDest, arriveDist, timeout, onTick, fadeOnTeleport)
    local j = r.job
    local started = GetGameTimer()
    local lastPos, lastMove = GetEntityCoords(r.veh), GetGameTimer()
    local reversed = false
    local dest = getDest()
    driveTo(r, dest)
    while true do
        Wait(500)
        if r.stop then return 'stopped' end
        if not DoesEntityExist(r.veh) or not DoesEntityExist(r.driver) then return 'cancelled' end
        local pos = GetEntityCoords(r.veh)
        local nd = getDest()
        if #(nd - dest) > 12.0 then
            dest = nd
            driveTo(r, dest)
        end
        local dist = #(pos - dest)
        if onTick then onTick(dist) end
        if dist <= arriveDist then return 'arrived' end
        if #(pos - lastPos) > 2.0 then
            lastPos, lastMove = pos, GetGameTimer()
            reversed = false
        end
        local stuckFor = (GetGameTimer() - lastMove) / 1000.0
        if stuckFor >= (j.stuckTime or 10) and not reversed then
            reversed = true
            TaskVehicleTempAction(r.driver, r.veh, 28, 2500)
            Wait(2600)
            driveTo(r, dest)
        end
        local elapsed = (GetGameTimer() - started) / 1000.0
        if stuckFor >= (j.stuckTeleport or 22) or elapsed >= timeout then
            local node, heading = roadNear(dest, 150.0)
            if not node then node, heading = dest, GetEntityHeading(r.veh) end
            teleportVehicle(r, node, heading, fadeOnTeleport)
            return 'teleported'
        end
    end
end

local function walkTo(ped, target, timeout, offset)
    local t = GetGameTimer() + (timeout or 25) * 1000
    local function goal()
        if offset then return GetOffsetFromEntityInWorldCoords(target, offset.x, offset.y, 0.0) end
        return GetEntityCoords(target)
    end
    local g = goal()
    TaskGoToCoordAnyMeans(ped, g.x, g.y, g.z, 2.0, 0, false, 786603, -1.0)
    while GetGameTimer() < t do
        Wait(300)
        if not DoesEntityExist(ped) or not DoesEntityExist(target) then return false end
        local ng = goal()
        if #(GetEntityCoords(ped) - ng) <= 1.4 then return true end
        if #(ng - g) > 1.5 then
            g = ng
            TaskGoToCoordAnyMeans(ped, g.x, g.y, g.z, 2.0, 0, false, 786603, -1.0)
        end
    end
    -- could not get there: place the medic next to the patient
    local g2 = goal()
    SetEntityCoords(ped, g2.x, g2.y, g2.z - 0.95, false, false, false, false)
    return true
end

local function playAnim(ped, a, flag)
    if type(a) ~= 'table' or not loadDict(a.dict) then return false end
    TaskPlayAnim(ped, a.dict, a.clip, 4.0, -4.0, -1, flag or 1, 0.0, false, false, false)
    return true
end

-- ════════════════════════════════════════════════════════════════════════
-- RUN
-- ════════════════════════════════════════════════════════════════════════

local function run(job)
    local r = { job = job, phase = 'spawn' }
    runs[job.id] = r
    local tped = patientPed(job)
    local t0 = GetGameTimer()
    while tped == 0 and GetGameTimer() - t0 < 5000 do Wait(250) tped = patientPed(job) end
    if tped == 0 then send(job, 'failed', 'no_patient') runs[job.id] = nil return end
    local pc = GetEntityCoords(tped)

    -- spawn
    local sd = job.spawnDistance or { 150.0, 300.0 }
    local node, heading = roadNodeAround(pc, tonumber(sd[1]) or 150.0, tonumber(sd[2]) or 300.0)
    local vehHash = loadModel(job.vehicle or 'ambulance')
    local crewHash = {}
    for i, m in ipairs(job.crew or { 's_m_m_paramedic_01' }) do
        if i <= 2 then crewHash[#crewHash + 1] = loadModel(m) end
    end
    if not node or not vehHash or not crewHash[1] then
        send(job, 'failed', 'spawn')
        runs[job.id] = nil
        return
    end
    RequestCollisionAtCoord(node.x, node.y, node.z)
    r.veh = CreateVehicle(vehHash, node.x, node.y, node.z + 0.5, heading or 0.0, true, true)
    if r.veh == 0 then send(job, 'failed', 'spawn') runs[job.id] = nil return end
    SetEntityAsMissionEntity(r.veh, true, true)
    SetVehicleOnGroundProperly(r.veh)
    SetVehicleEngineOn(r.veh, true, true, false)
    SetVehicleSiren(r.veh, job.siren ~= false)
    SetVehicleHasMutedSirens(r.veh, false)
    SetVehicleDoorsLocked(r.veh, 2)
    SetVehicleCanBeVisiblyDamaged(r.veh, false)
    SetEntityInvincible(r.veh, true)
    if job.plate then SetVehicleNumberPlateText(r.veh, tostring(job.plate):sub(1, 8)) end
    if job.livery then SetVehicleLivery(r.veh, tonumber(job.livery) or 0) end
    r.driver = CreatePedInsideVehicle(r.veh, 26, crewHash[1], -1, true, true)
    setupCrew(r.driver)
    SetDriverAbility(r.driver, 1.0)
    SetDriverAggressiveness(r.driver, 0.5)
    if crewHash[2] then
        r.partner = CreatePedInsideVehicle(r.veh, 26, crewHash[2], 0, true, true)
        setupCrew(r.partner)
    end
    SetModelAsNoLongerNeeded(vehHash)
    local vehNet = netOf(r.veh)
    local crew = { netOf(r.driver) }
    if r.partner then crew[#crew + 1] = netOf(r.partner) end
    if not vehNet then deleteAll(r) send(job, 'failed', 'network') runs[job.id] = nil return end
    send(job, 'spawned', vehNet, crew)
    if isSelf(job) then
        r.blip = AddBlipForEntity(r.veh)
        SetBlipSprite(r.blip, 56)
        SetBlipColour(r.blip, 1)
        SetBlipFlashes(r.blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(L(job, 'calls.ai_unit'))
        EndTextCommandSetBlipName(r.blip)
    end

    -- drive to the patient
    r.phase = 'enroute'
    local lastEta = 0
    local res = driveLoop(r, function()
        local p = DoesEntityExist(tped) and GetEntityCoords(tped) or pc
        return p
    end, (job.stopRange or 14.0) + 6.0, job.driveTimeout or 120, function(dist)
        if GetGameTimer() - lastEta >= (job.etaUpdate or 4) * 1000 then
            lastEta = GetGameTimer()
            local speed = math.max(6.0, GetEntitySpeed(r.veh))
            send(job, 'eta', math.floor(dist / math.max(speed, (job.speed or 28.0) * 0.45)))
        end
    end, false)
    if res == 'stopped' then return end
    if res == 'cancelled' then deleteAll(r) send(job, 'failed', 'vehicle') runs[job.id] = nil return end
    TaskVehicleTempAction(r.driver, r.veh, 27, 3000)
    Wait(800)
    send(job, 'arrived', res == 'teleported')

    -- crew to the patient
    r.phase = 'onscene'
    TaskLeaveVehicle(r.driver, r.veh, 0)
    if r.partner then TaskLeaveVehicle(r.partner, r.veh, 0) end
    local t1 = GetGameTimer() + 5000
    while IsPedInAnyVehicle(r.driver, false) and GetGameTimer() < t1 do Wait(100) end
    if r.stop then return end
    local medic = r.driver
    walkTo(medic, tped, job.walkTimeout or 25, vector3(0.7, 0.1, 0.0))
    if r.partner then CreateThread(function() walkTo(r.partner, tped, job.walkTimeout or 25, vector3(-0.9, 0.6, 0.0)) end) end
    if r.stop then return end
    local tc = GetEntityCoords(tped)
    TaskTurnPedToFaceCoord(medic, tc.x, tc.y, tc.z, 700)
    Wait(700)
    local bag = NZA.Target and NZA.Target.State and NZA.Target.State(tped) or nil
    local arrest = type(bag) == 'table' and bag.st == 'arrest'
    if arrest then
        playAnim(medic, job.cprAnim, 1)
        say(job, 'calls.ai_say_cpr')
    else
        playAnim(medic, job.treatAnim or job.kneelAnim, 1)
        say(job, 'calls.ai_say_1')
    end
    if r.partner then
        CreateThread(function()
            Wait(1500)
            if DoesEntityExist(r.partner) then
                local pcc = GetEntityCoords(tped)
                TaskTurnPedToFaceCoord(r.partner, pcc.x, pcc.y, pcc.z, 700)
                Wait(700)
                if not playAnim(r.partner, job.kneelAnim, 1) then
                    TaskStartScenarioInPlace(r.partner, 'CODE_HUMAN_MEDIC_KNEEL', 0, true)
                end
            end
        end)
    end
    send(job, 'treating')
    r.phase = 'treating'
    local tt = GetGameTimer() + ((job.treatTime or 14) + 20) * 1000
    local half = GetGameTimer() + (job.treatTime or 14) * 500
    local said = false
    while not r.treated and not r.stop and not r.handover and GetGameTimer() < tt do
        Wait(250)
        if not said and GetGameTimer() > half then
            said = true
            say(job, 'calls.ai_say_2')
        end
    end
    if r.stop then return end
    if not r.treated then
        -- teleport mode: the server hands over directly; the crew packs up
        r.phase = 'leaving'
        return
    end

    -- load the patient
    r.phase = 'loading'
    say(job, 'calls.ai_say_3')
    Wait(1200)
    local self = isSelf(job)
    if self then fade(true, 600) end
    ClearPedTasks(medic)
    if r.partner then ClearPedTasks(r.partner) end
    if self then
        SetPedIntoVehicle(PlayerPedId(), r.veh, 2)
    elseif tped ~= 0 and DoesEntityExist(tped) then
        local t2 = GetGameTimer() + 1500
        while not NetworkHasControlOfEntity(tped) and GetGameTimer() < t2 do NetworkRequestControlOfEntity(tped) Wait(50) end
        if NetworkHasControlOfEntity(tped) then
            ClearPedTasksImmediately(tped)
            SetPedIntoVehicle(tped, r.veh, 2)
        end
    end
    SetPedIntoVehicle(r.driver, r.veh, -1)
    if r.partner then SetPedIntoVehicle(r.partner, r.veh, 1) end
    Wait(400)
    if self then fade(false, 700) end
    send(job, 'loaded')

    -- drive to the hospital
    r.phase = 'transport'
    local h = r.hospital or job.hospital
    if not h then send(job, 'failed', 'no_hospital') r.phase = 'leaving' return end
    local hv = vector3(h.x, h.y, h.z)
    local hnode = roadNear(hv, 200.0) or hv
    if self then
        CreateThread(function()
            while r.phase == 'transport' do
                DisableControlAction(0, 75, true)    -- exit vehicle
                DisableControlAction(27, 75, true)
                Wait(0)
            end
        end)
    end
    local res2 = driveLoop(r, function() return hnode end, (job.hospitalRadius or 60.0) * 0.6, job.transportTimeout or 150, nil, self)
    if res2 == 'stopped' then return end
    if res2 == 'cancelled' then
        send(job, 'failed', 'vehicle')
        return
    end
    TaskVehicleTempAction(r.driver, r.veh, 27, 3000)
    r.phase = 'arrived'
    send(job, 'atHospital', res2 == 'teleported')
end

-- ════════════════════════════════════════════════════════════════════════
-- EVENTS
-- ════════════════════════════════════════════════════════════════════════

RegisterNetEvent('nza:aimedic:run', function(job)
    if type(job) ~= 'table' or not job.id then return end
    if runs[job.id] then return end
    CreateThread(function()
        local ok, err = pcall(run, job)
        if not ok then
            NZA.Debug('aimedic run failed', err)
            local r = runs[job.id]
            if r then deleteAll(r) runs[job.id] = nil end
            TriggerServerEvent('nza:aimedic:failed', job.id, job.token, 'error')
        end
    end)
end)

RegisterNetEvent('nza:aimedic:treated', function(id, data)
    local r = runs[id]
    if not r then return end
    if type(data) == 'table' and type(data.hospital) == 'table' then r.hospital = data.hospital end
    r.treated = true
end)

local function leave(r)
    r.phase = 'leaving'
    if not r.veh or not DoesEntityExist(r.veh) then deleteAll(r) return end
    CreateThread(function()
        if r.driver and DoesEntityExist(r.driver) then
            ClearPedTasks(r.driver)
            if not IsPedInVehicle(r.driver, r.veh, false) then
                TaskEnterVehicle(r.driver, r.veh, 8000, -1, 2.0, 1, 0)
            end
        end
        if r.partner and DoesEntityExist(r.partner) and not IsPedInVehicle(r.partner, r.veh, false) then
            ClearPedTasks(r.partner)
            TaskEnterVehicle(r.partner, r.veh, 8000, 0, 2.0, 1, 0)
        end
        local t = GetGameTimer() + 9000
        while GetGameTimer() < t and r.driver and DoesEntityExist(r.driver) and not IsPedInVehicle(r.driver, r.veh, false) do Wait(250) end
        if r.driver and DoesEntityExist(r.driver) and not IsPedInVehicle(r.driver, r.veh, false) then SetPedIntoVehicle(r.driver, r.veh, -1) end
        if r.partner and DoesEntityExist(r.partner) and not IsPedInVehicle(r.partner, r.veh, false) then SetPedIntoVehicle(r.partner, r.veh, 0) end
        SetVehicleSiren(r.veh, false)
        if r.blip and DoesBlipExist(r.blip) then RemoveBlip(r.blip) r.blip = nil end
        TaskVehicleDriveWander(r.driver, r.veh, 18.0, 786603)
        local t2 = GetGameTimer() + 30000
        local me = PlayerPedId()
        while GetGameTimer() < t2 and DoesEntityExist(r.veh) and #(GetEntityCoords(me) - GetEntityCoords(r.veh)) < 120.0 do Wait(1000) end
        deleteAll(r)
    end)
end

RegisterNetEvent('nza:aimedic:done', function(id)
    local r = runs[id]
    if not r then return end
    runs[id] = nil
    r.stop = true
    leave(r)
end)

RegisterNetEvent('nza:aimedic:cancel', function(id)
    local r = runs[id]
    if not r then return end
    runs[id] = nil
    r.stop = true
    leave(r)
end)

-- the patient's own client: out of the ambulance and into the hospital bed / spot
RegisterNetEvent('nza:aimedic:handover', function(id, data)
    if type(data) ~= 'table' then return end
    local r = runs[id]
    if r then r.handover = true end
    CreateThread(function()
        -- the downed pose must not fight the move into the bed
        local W = NZA.Wounded
        if W and W.SuspendPose then W.SuspendPose('aimedic', true) end
        SetTimeout(9000, function()
            if W and W.SuspendPose then W.SuspendPose('aimedic', false) end
        end)
        fade(true, 600)
        local ped = PlayerPedId()
        if IsPedInAnyVehicle(ped, false) then
            ClearPedTasksImmediately(ped)
        end
        local c = data.coords
        if type(c) == 'table' and tonumber(c.x) then
            RequestCollisionAtCoord(c.x, c.y, c.z)
            SetEntityCoords(ped, c.x + 0.0, c.y + 0.0, c.z + 0.0, false, false, false, false)
            if c.w then SetEntityHeading(ped, c.w + 0.0) end
            local t = GetGameTimer() + 3000
            while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < t do Wait(50) end
        end
        TriggerServerEvent('nza:aimedic:ready', id, data.token)
        Wait(2200)
        fade(false, 900)
    end)
end)

function A.Runs() return runs end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, r in pairs(runs) do deleteAll(r) end
    runs = {}
    if NZA.Wounded and NZA.Wounded.SuspendPose then pcall(NZA.Wounded.SuspendPose, 'aimedic', false) end
    if IsScreenFadedOut() or IsScreenFadingOut() then DoScreenFadeIn(300) end
end)
