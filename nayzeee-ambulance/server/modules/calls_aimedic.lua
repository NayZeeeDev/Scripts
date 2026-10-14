--[[
    NAYZEEE AMBULANCE - AI medic (server)

    When a downed patient calls for help and no medic is on duty (the wounded module calls
    NZA.AIMedic.Request), an AI ambulance answers:
      1. the patient's own client (players) / the nearest player (NPC patients) spawns a
         networked ambulance + crew on a road 150-300 m away; it drives in with lights & siren
         (ETA pushed to the patient's HUD through NZA.Wounded.Help { eta, ai = true })
      2. the crew walks over, kneels and treats (bleeding controlled, ROSC for arrest,
         naloxone / oxygen when needed) for Config.AIMedic.treatTime seconds - server timed
      3. the patient is loaded (fade) and driven to the nearest hospital (or faded straight
         there, transport = 'teleport'), placed in a free bed (NZA.Hospitals.FreeBed) or at a
         fallback hospital spot, revived / healed per Config.AIMedic.revive and billed
         (NZA.Billing.Charge, insurance applies)
    Every step has a server-side fallback (stuck, timeout, controller gone, failed spawn), so
    a patient is never left waiting: after Config.AIMedic.maxTime the job completes anyway.

    API (server)
      NZA.AIMedic.Request(pidOrSrc, opts?) → jobId | false, err   opts = { callId, force, source }
      NZA.AIMedic.Cancel(pidOrJobId, reason?) → bool
      NZA.AIMedic.Active(pid) → job | nil      NZA.AIMedic.Jobs() → { [id] = job }
    Exports: RequestAIMedic(pidOrSrc, opts), CancelAIMedic(pidOrSrc)
    Net events
      S→C nza:aimedic:run (job)  nza:aimedic:treated (id, data)  nza:aimedic:handover (id, data)
          nza:aimedic:done (id, reason)  nza:aimedic:cancel (id, reason)
      C→S nza:aimedic:spawned (id, token, vehNet, crewNets)  nza:aimedic:eta (id, token, seconds)
          nza:aimedic:arrived (id, token, teleported)  nza:aimedic:treating (id, token)
          nza:aimedic:loaded (id, token)  nza:aimedic:atHospital (id, token, teleported)
          nza:aimedic:ready (id, token)  nza:aimedic:failed (id, token, reason)
    Bus listened: dispatch:respond (a real medic takes the call), state:changed, patient:removed,
                  player:unloaded
]]

if not NAYZEEE_LOCK_OK then return end

NZA.AIMedic = NZA.AIMedic or {}
local A = NZA.AIMedic
local U = NZA.Util

local jobs = {}       -- [id] = job
local byPid = {}      -- [pid] = id
local cooldown = {}   -- [pid] = os.time()
local seq = 0

local function cfg() return Config.AIMedic or {} end
local function L(key, ...) return NZA.L(key, ...) end
local function now() return os.time() end

local function ent(net)
    if NZA.Calls and NZA.Calls.Internal and NZA.Calls.Internal.Ent then return NZA.Calls.Internal.Ent(net) end
    net = tonumber(net)
    if not net then return 0 end
    local e = NetworkGetEntityFromNetworkId(net)
    if not e or e == 0 or not DoesEntityExist(e) then return 0 end
    return e
end

local function deleteNet(net)
    local e = ent(net)
    if e ~= 0 then pcall(DeleteEntity, e) end
end

local function v4(c)
    if not c then return nil end
    local x, y, z = tonumber(c.x or c[1]), tonumber(c.y or c[2]), tonumber(c.z or c[3])
    if not x or not y or not z then return nil end
    return { x = x, y = y, z = z, w = tonumber(c.w or c.h or c.heading or c[4]) or 0.0 }
end

local function help(job, status, eta)
    local W = NZA.Wounded
    if not (W and W.Help) then return end
    local p = NZA.Patients.Get(job.pid)
    if not p or p.kind ~= 'player' or not p.src then return end
    pcall(W.Help, p.src, { eta = eta, unit = L('calls.ai_unit'), ai = true, status = status })
end

local function toastPatient(job, key, kind, ...)
    local p = NZA.Patients.Get(job.pid)
    if p and p.kind == 'player' and p.src then NZA.Core.Notify(p.src, L(key, ...), kind or 'info') end
end

local function medicsOnDuty()
    local ok, list = pcall(NZA.Staff.OnDuty)
    return ok and type(list) == 'table' and #list or 0
end

local function patientCoords(p)
    return NZA.Core.PatientCoords(p)
end

-- ════════════════════════════════════════════════════════════════════════
-- HOSPITAL
-- ════════════════════════════════════════════════════════════════════════

local function pickHospital(coords)
    local H = NZA.Hospitals
    if H and H.FreeBed and coords then
        local dept
        if H.Nearest then
            local ok, d = pcall(H.Nearest, coords)
            if ok then dept = d end
        end
        local ok, bed = pcall(H.FreeBed, dept and dept.id or nil)
        if not (ok and bed) and dept then ok, bed = pcall(H.FreeBed, nil) end
        if ok and type(bed) == 'table' and bed.coords then
            local c = v4(bed.coords)
            if c then return { point = bed.id, type = bed.type or 'bed', hospital = bed.hospital, coords = c } end
        end
    end
    local best, bestD = nil, math.huge
    for _, h in ipairs(cfg().hospitals or {}) do
        local c = v4(h)
        if c and coords then
            local d = #(vector3(c.x, c.y, c.z) - coords)
            if d < bestD then best, bestD = c, d end
        elseif c and not best then
            best = c
        end
    end
    return best and { coords = best } or nil
end

-- ════════════════════════════════════════════════════════════════════════
-- MEDICAL CARE (on scene + at the hospital)
-- ════════════════════════════════════════════════════════════════════════

local function stabilize(p)
    if not p then return end
    local P = NZA.Patients
    if p.state == 'arrest' then pcall(P.Revive, p.pid, { rosc = true, reason = 'ai_medic' }) end
    for id, inj in pairs(p.injuries or {}) do
        if (tonumber(inj.bleed) or 0) > 0 and inj.status ~= 'treated' then
            pcall(P.UpdateInjury, p.pid, id, { treat = { bandaged = true, packed = (tonumber(inj.bleed) or 0) > 15 or nil } })
        end
    end
    if p.conditions and p.conditions.overdose then pcall(P.GiveMed, p.pid, 'naloxone', { by = 'ai' }) end
    if p.conditions and (p.conditions.hypoxia or p.conditions.airway) then pcall(P.SetDevice, p.pid, 'oxygen', true) end
    if NZA.Patients.Touch then pcall(NZA.Patients.Touch, p, true) end
end

local function bill(job, p)
    local price = math.floor(tonumber(cfg().price) or 0)
    if price <= 0 or p.kind ~= 'player' then return end
    local reason = L(cfg().billReason or 'calls.ai_bill')
    if NZA.Billing and NZA.Billing.Charge then
        local ok, res = pcall(NZA.Billing.Charge, p.src or p.identifier, price, reason, { kind = 'aimedic', pid = p.pid })
        if ok and res then return end
    end
    local B = NZA.Core.B
    if p.src and B('RemoveMoney', p.src, (Config.Billing and Config.Billing.account) or 'bank', price, reason) then
        B('Society.Add', (Config.Billing and Config.Billing.society) or 'ambulance', price)
        NZA.Core.Notify(p.src, L('calls.ai_charged', price), 'info')
    end
end

-- put the patient in the hospital bed the same way the transport module does
local function placeInBed(p, hosp)
    local T, H = NZA.Transport, NZA.Hospitals
    if not (hosp and hosp.point and T and T.PatientBag and T.ReleaseAll and T.Pack) then return false end
    if H and H.BedOccupant then
        local ok, occ = pcall(H.BedOccupant, hosp.point)
        if ok and occ and occ ~= p.pid then return false end
    end
    pcall(T.ReleaseAll, p, true)
    if T.beds then T.beds[hosp.point] = p.pid end
    NZA.Patients.SetMeta(p, 'bed', { point = hosp.point, type = hosp.type or 'bed', hospital = hosp.hospital })
    if H and H.OccupyBed then pcall(H.OccupyBed, hosp.point, p.pid) end
    NZA.Patients.SetMeta(p, 'inBed', true)
    local c = hosp.coords
    T.PatientBag(p, { m = 'bed', b = hosp.point, bt = hosp.type or 'bed', at = T.Pack(vector4(c.x, c.y, c.z, c.w or 0.0)) })
    return true
end

-- ════════════════════════════════════════════════════════════════════════
-- JOBS
-- ════════════════════════════════════════════════════════════════════════

local function publicJob(job)
    local p = NZA.Patients.Get(job.pid)
    local target = p and (p.kind == 'player' and { kind = 'player', sid = p.src } or { kind = 'npc', net = p.net }) or nil
    local c = cfg()
    return {
        id = job.id, token = job.token, target = target, self = p and p.kind == 'player' and p.src == job.src or false,
        hospital = job.hospital and job.hospital.coords or nil, transport = c.transport or 'drive',
        vehicle = c.vehicle or 'ambulance', livery = c.livery, crew = c.crew or { 's_m_m_paramedic_01' }, plate = c.plate,
        spawnDistance = c.spawnDistance or { 150.0, 300.0 }, speed = c.speed or 28.0, drivingStyle = c.drivingStyle or 787004,
        stopRange = c.stopRange or 14.0, siren = c.siren ~= false, etaUpdate = c.etaUpdate or 4,
        stuckTime = c.stuckTime or 10, stuckTeleport = c.stuckTeleport or 22, driveTimeout = c.driveTimeout or 120,
        walkTimeout = c.walkTimeout or 25, treatTime = c.treatTime or 14, transportTimeout = c.transportTimeout or 150,
        hospitalRadius = c.hospitalRadius or 60.0,
        cprAnim = c.cprAnim, treatAnim = c.treatAnim, kneelAnim = c.kneelAnim,
        locale = NZA.LocaleTable and NZA.LocaleTable('calls') or nil,
    }
end

local function controllerFor(p)
    if p.kind == 'player' and p.src and NZA.Core.Online(p.src) then return p.src end
    local c = patientCoords(p)
    if not c then return nil end
    local best, bestD = nil, 300.0
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        local sc = NZA.Core.SrcCoords(src)
        if sc then
            local d = #(sc - c)
            if d < bestD then best, bestD = src, d end
        end
    end
    return best
end

local function cleanup(job, delay)
    local nets = {}
    if job.veh then nets[#nets + 1] = job.veh end
    for _, n in ipairs(job.crew or {}) do nets[#nets + 1] = n end
    SetTimeout((delay or 45) * 1000, function()
        for _, n in ipairs(nets) do deleteNet(n) end
    end)
end

local function endJob(job, reason, delay)
    if jobs[job.id] ~= job then return end
    jobs[job.id] = nil
    if byPid[job.pid] == job.id then byPid[job.pid] = nil end
    cooldown[job.pid] = now()
    if job.src and NZA.Core.Online(job.src) then
        TriggerClientEvent(reason == 'done' and 'nza:aimedic:done' or 'nza:aimedic:cancel', job.src, job.id, reason)
    end
    cleanup(job, delay or (reason == 'done' and 50 or 30))
    NZA.Debug('aimedic: job', job.id, 'ended', reason)
end

function A.Jobs() return jobs end

function A.Active(pid)
    if type(pid) == 'table' then pid = pid.pid end
    local id = pid and byPid[pid]
    return id and jobs[id] or nil
end

function A.Cancel(x, reason)
    local job = jobs[x]
    if not job then
        local p = NZA.Patients.Resolve(x)
        job = p and A.Active(p.pid)
    end
    if not job then return false end
    help(job, 'cancelled')
    if reason == 'medic' then toastPatient(job, 'calls.ai_medic_took', 'info') end
    endJob(job, reason or 'cancelled')
    return true
end

function A.Request(x, opts)
    opts = opts or {}
    local c = cfg()
    if c.enabled == false then return false, 'disabled' end
    local p = NZA.Patients.Resolve(x)
    if not p then return false, 'no_patient' end
    local states = c.states or { wounded = true, arrest = true }
    if not states[p.state] then return false, 'state' end
    local existing = A.Active(p.pid)
    if existing then return existing.id end
    if cooldown[p.pid] and now() - cooldown[p.pid] < (tonumber(c.cooldown) or 120) and not opts.force then return false, 'cooldown' end
    if c.onlyNoMedics ~= false and not opts.force and medicsOnDuty() > 0 then return false, 'medics' end
    if U.tableCount(jobs) >= (tonumber(c.maxActive) or 4) then return false, 'busy' end
    local src = controllerFor(p)
    if not src then return false, 'no_client' end
    local coords = patientCoords(p)
    seq = seq + 1
    local job = {
        id = ('AI%03d'):format(seq), pid = p.pid, src = src, state = 'dispatch', started = now(),
        token = ('%d-%d'):format(math.random(100000, 999999), GetGameTimer()),
        callId = opts.callId or (p.meta and p.meta.callId), hospital = pickHospital(coords), crew = {},
    }
    jobs[job.id] = job
    byPid[p.pid] = job.id
    local sd = c.spawnDistance or { 150.0, 300.0 }
    local mid = ((tonumber(sd[1]) or 150.0) + (tonumber(sd[2]) or 300.0)) / 2
    local eta = math.floor(mid / math.max(8.0, (tonumber(c.speed) or 28.0) * 0.55))
    job.eta = eta
    TriggerClientEvent('nza:aimedic:run', src, publicJob(job))
    help(job, 'enroute', eta)
    NZA.Debug('aimedic: job', job.id, 'for', p.pid, 'controller', src)
    return job.id
end

-- ── step: treatment done → load / hand over ─────────────────────────────

local function finish(job, teleported)
    if job.finishing then return end
    job.finishing = true
    local p = NZA.Patients.Get(job.pid)
    if not p then endJob(job, 'gone') return end
    if not job.treated then stabilize(p); job.treated = true end
    job.state = 'handover'
    local hosp = job.hospital or pickHospital(patientCoords(p))
    if hosp and hosp.point and NZA.Hospitals and NZA.Hospitals.BedOccupant then
        local ok, occ = pcall(NZA.Hospitals.BedOccupant, hosp.point)
        if ok and occ and occ ~= p.pid then hosp = pickHospital(patientCoords(p)) end
    end
    job.hospital = hosp

    if p.kind == 'npc' then
        -- NPC patients are admitted straight away
        local scene = NZA.Calls and NZA.Calls.SceneOf and NZA.Calls.SceneOf(p.pid)
        if scene and NZA.Calls.Internal.RemoveVictim then
            NZA.Calls.Internal.RemoveVictim(scene, p.pid, 'ai_medic')
        else
            local net = p.net
            NZA.Patients.Remove(p.pid, 'ai_medic')
            deleteNet(net)
        end
        endJob(job, 'done')
        return
    end

    local coords = hosp and hosp.coords or nil
    job.readyWait = true
    if p.src then TriggerClientEvent('nza:aimedic:handover', p.src, job.id, { coords = coords, token = job.token }) end
    local pid = job.pid
    local function proceed()
        if not job.readyWait then return end
        job.readyWait = false
        local cur = NZA.Patients.Get(pid)
        if not cur then endJob(job, 'gone') return end
        local c = cfg()
        if c.revive == 'stabilize' then
            stabilize(cur)
            pcall(NZA.Patients.Revive, pid, { reason = 'ai_medic' })
        else
            pcall(NZA.Patients.Revive, pid, { full = true, reason = 'ai_medic' })
        end
        SetTimeout(1500, function()
            local cur2 = NZA.Patients.Get(pid)
            if cur2 and hosp and hosp.point then placeInBed(cur2, hosp) end
        end)
        bill(job, cur)
        help(job, 'cleared')
        toastPatient(job, c.revive == 'stabilize' and 'calls.ai_done_stable' or 'calls.ai_done', 'success')
        if c.closeCall ~= false and job.callId and NZA.Dispatch and NZA.Dispatch.Close then
            pcall(NZA.Dispatch.Close, job.callId, 'ai_medic')
        end
        endJob(job, 'done')
    end
    job.proceed = proceed
    SetTimeout(5000, proceed)   -- the client did not answer: carry on anyway
end

local function treatDone(job)
    if jobs[job.id] ~= job or job.treated then return end
    local p = NZA.Patients.Get(job.pid)
    if not p then endJob(job, 'gone') return end
    stabilize(p)
    job.treated = true
    job.state = 'treated'
    local mode = cfg().transport or 'drive'
    if mode == 'teleport' then
        finish(job)
        return
    end
    toastPatient(job, 'calls.ai_loading', 'info')
    TriggerClientEvent('nza:aimedic:treated', job.src, job.id, { transport = mode, hospital = job.hospital and job.hospital.coords })
end

-- ════════════════════════════════════════════════════════════════════════
-- CLIENT REPORTS
-- ════════════════════════════════════════════════════════════════════════

local function valid(src, id, token)
    local job = jobs[id]
    if not job or job.src ~= src or job.token ~= token then return nil end
    if not NZA.Core.Rate('aimedic', src, 20, 10000) then return nil end
    return job
end

local function sameModel(e, model)
    local m, h = GetEntityModel(e), joaat(model)
    if m < 0 then m = m + 4294967296 end
    if h < 0 then h = h + 4294967296 end
    return m == h
end

RegisterNetEvent('nza:aimedic:spawned', function(id, token, vehNet, crewNets)
    local src = source
    local job = valid(src, id, token)
    if not job or job.veh then return end
    local veh = ent(vehNet)
    if veh == 0 or not sameModel(veh, cfg().vehicle or 'ambulance') then
        deleteNet(vehNet)
        return
    end
    job.veh = tonumber(vehNet)
    pcall(SetEntityOrphanMode, veh, 2)
    for _, n in ipairs(type(crewNets) == 'table' and crewNets or {}) do
        local e = ent(n)
        if e ~= 0 and GetEntityType(e) == 1 then
            job.crew[#job.crew + 1] = tonumber(n)
            pcall(SetEntityOrphanMode, e, 2)
        end
    end
    job.state = 'enroute'
    job.driveAt = now()
end)

RegisterNetEvent('nza:aimedic:eta', function(id, token, eta)
    local src = source
    local job = valid(src, id, token)
    if not job or job.state ~= 'enroute' then return end
    eta = U.clamp(math.floor(tonumber(eta) or 0), 0, 900)
    job.eta = eta
    help(job, 'enroute', eta)
end)

RegisterNetEvent('nza:aimedic:arrived', function(id, token, teleported)
    local src = source
    local job = valid(src, id, token)
    if not job or (job.state ~= 'enroute' and job.state ~= 'dispatch') then return end
    local p = NZA.Patients.Get(job.pid)
    if not p then endJob(job, 'gone') return end
    local veh = ent(job.veh)
    local pc = patientCoords(p)
    if veh ~= 0 and pc and #(GetEntityCoords(veh) - pc) > 90.0 then return end
    job.state = 'onscene'
    job.arrivedAt = now()
    help(job, 'onscene')
    toastPatient(job, 'calls.ai_arrived', 'info')
end)

RegisterNetEvent('nza:aimedic:treating', function(id, token)
    local src = source
    local job = valid(src, id, token)
    if not job or job.state ~= 'onscene' then return end
    job.state = 'treating'
    job.treatAt = now()
    local t = math.max(3, tonumber(cfg().treatTime) or 14)
    SetTimeout(t * 1000, function() treatDone(job) end)
end)

RegisterNetEvent('nza:aimedic:loaded', function(id, token)
    local src = source
    local job = valid(src, id, token)
    if not job or job.state ~= 'treated' then return end
    job.state = 'transport'
    job.transportAt = now()
    toastPatient(job, 'calls.ai_transport', 'info')
end)

RegisterNetEvent('nza:aimedic:atHospital', function(id, token, teleported)
    local src = source
    local job = valid(src, id, token)
    if not job or job.state ~= 'transport' then return end
    local hosp = job.hospital and job.hospital.coords
    local veh = ent(job.veh)
    local close = true
    if hosp and veh ~= 0 then
        close = #(GetEntityCoords(veh) - vector3(hosp.x, hosp.y, hosp.z)) <= (tonumber(cfg().hospitalRadius) or 60.0) + 60.0
    end
    local timedOut = now() - (job.transportAt or now()) >= (tonumber(cfg().transportTimeout) or 150) - 5
    if not close and not timedOut and not teleported then return end
    if teleported and not close and not timedOut and now() - (job.transportAt or now()) < 20 then return end
    finish(job, teleported)
end)

RegisterNetEvent('nza:aimedic:ready', function(id, token)
    local src = source
    local job = jobs[id]
    if not job or job.token ~= token then return end
    local p = NZA.Patients.Get(job.pid)
    if not p or p.src ~= src then return end
    if job.proceed then job.proceed() end
end)

RegisterNetEvent('nza:aimedic:failed', function(id, token, reason)
    local src = source
    local job = valid(src, id, token)
    if not job then return end
    NZA.Debug('aimedic: client failed', id, reason)
    job.clientFailed = true
    if job.state == 'dispatch' or job.state == 'enroute' or job.state == 'onscene' then
        -- no AI vehicle: the unit "arrives" virtually after a short wait, then fades to the hospital
        job.state = 'treating'
        help(job, 'onscene')
        SetTimeout(math.max(3, tonumber(cfg().treatTime) or 14) * 1000, function()
            if jobs[job.id] ~= job then return end
            local p = NZA.Patients.Get(job.pid)
            if p then stabilize(p) end
            job.treated = true
            finish(job, true)
        end)
    elseif job.state == 'treated' or job.state == 'transport' then
        finish(job, true)
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- WATCHDOG
-- ════════════════════════════════════════════════════════════════════════

CreateThread(function()
    while true do
        Wait(2000)
        local t = now()
        for _, job in pairs(jobs) do
            local p = NZA.Patients.Get(job.pid)
            if not p then
                endJob(job, 'gone')
            elseif p.state == 'dead' then
                help(job, 'cancelled')
                endJob(job, 'dead')
            elseif p.state == 'alive' and job.state ~= 'handover' and not job.treated then
                -- got up by themselves / a bystander helped
                help(job, 'cancelled')
                endJob(job, 'recovered')
            elseif not NZA.Core.Online(job.src) then
                -- the controller left: finish without the AI vehicle
                if p.kind == 'player' and p.src and NZA.Core.Online(p.src) and p.src ~= job.src then
                    job.src = p.src
                elseif p.kind == 'player' then
                    endJob(job, 'controller_left')
                else
                    finish(job, true)
                end
            elseif t - job.started >= (tonumber(cfg().maxTime) or 480) and not job.finishing then
                finish(job, true)
            elseif job.state == 'dispatch' and t - job.started > 25 then
                -- the client never reported a vehicle
                job.state = 'enroute'
                job.clientFailed = true
                SetTimeout(math.max(3, tonumber(cfg().treatTime) or 14) * 1000, function()
                    if jobs[job.id] == job and not job.finishing then finish(job, true) end
                end)
            end
        end
    end
end)

-- a real medic responded to the patient's call while the AI was still driving
NZA.Bus.On('dispatch:respond', function(call, src)
    if cfg().cancelOnMedic == false or type(call) ~= 'table' then return end
    for _, job in pairs(jobs) do
        if job.callId == call.id and (job.state == 'dispatch' or job.state == 'enroute') then
            A.Cancel(job.id, 'medic')
        end
    end
end)

NZA.Bus.On('patient:removed', function(pid)
    if type(pid) == 'table' then pid = pid.pid end
    local id = pid and byPid[pid]
    if id and jobs[id] and not jobs[id].finishing then endJob(jobs[id], 'gone') end
end)

NZA.Bus.On('player:unloaded', function(src)
    for _, job in pairs(jobs) do
        local p = NZA.Patients.Get(job.pid)
        if p and p.kind == 'player' and p.src == src then endJob(job, 'patient_left') end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, job in pairs(jobs) do
        if job.veh then deleteNet(job.veh) end
        for _, n in ipairs(job.crew or {}) do deleteNet(n) end
    end
end)

exports('RequestAIMedic', function(x, opts) return A.Request(x, opts) end)
exports('CancelAIMedic', function(x) return A.Cancel(x, 'export') end)
