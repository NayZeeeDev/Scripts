--[[
    NAYZEEE AMBULANCE - Check-in (client): lying in a called bed, AI doctor, bed rest HUD

    LYING DOWN (queue beds)
      NZA.CheckinC.LieDown(ticket, teleport) lies you on the bed your ticket was called to
      (server 'nza:checkin:lie' occupies it). Teleport = fade into the bed (AI doctor calls with
      Config.Checkin.ai.travel = 'teleport', or downed patients). Get up with
      Config.Checkin.rest.getUpKey (held for ai.getUpHold seconds while the AI treats you).
      Beds you lie in through the hospital module (its own [X] get up) and beds a medic puts
      you on (transport) show the same rest HUD.

    AI DOCTOR ('bed' app, mode 'ai')
      Cinematic treatment HUD: step timeline with timers, live bedside monitor, the bill with
      insurance cover, doctor lines as subtitles. A local doctor ped stands by the bed and
      slow camera shots move around it ([C] back to your own camera). Ends with a summary
      card; you stand up healed.

    BED REST ('bed' app, mode 'rest')
      Rest timer, healing ×4, recovery per injury, blood / pain, time to fully healed,
      get-up key. Polls 'nza:checkin:rest' every Config.Checkin.rest.poll seconds.

    Internals (NZA.CheckinC): Lying() → bool, LieDown(ticket, teleport) → bool, GetUp(reason),
                              AIActive() → bool
    Net events handled: nza:checkin:bed ({ point, on }), nza:checkin:ai (action, data)
    Callbacks used:     nza:checkin:lie, nza:checkin:rest
    NUI (bed app) actions sent: open, step, vitals, done, hold, cam, rest, close
    NUI callbacks: none (this file closes the app itself on done / abort / get up)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Checkin = NZA.Checkin or {}
NZA.CheckinC = NZA.CheckinC or {}
local K = NZA.CheckinC

local APP = 'bed'

local lying = nil        -- { point, coords = { x, y, z, w }, label, gen }
local lyingGen = 0
local busy = false
local ai = nil           -- { data, coords, startedAt, index }
local rest = nil         -- { point, since, gen }
local restGen = 0
local appOpen = false
local doctor = nil       -- local doctor ped
local doctorTask = nil
local cine = { on = false, gen = 0, cams = {}, radar = nil, user = true }
local startRest, restKeys -- forward declarations (defined in BED REST HUD)

local function cfg(section, key, default)
    local s = Config.Checkin and Config.Checkin[section]
    if type(s) ~= 'table' or s[key] == nil then return default end
    return s[key]
end

local function L(key, ...) return NZA.L('checkin.' .. key, ...) end

local function toast(msg, kind, title, ms)
    NZA.UI.Toast({ title = title or L('title'), message = msg, type = kind or 'info', duration = ms, icon = 'bed' })
end

local function call(name, ...)
    local ok, res = pcall(lib.callback.await, name, false, ...)
    if not ok or type(res) ~= 'table' then return { ok = false, err = 'failed', msg = L('err_failed') } end
    return res
end

local function v3(c) return vector3((c.x or 0.0) + 0.0, (c.y or 0.0) + 0.0, (c.z or 0.0) + 0.0) end

-- lying pose: the hospital module's bed settings win so every bed looks the same
local function pose()
    local hb = Config.Hospital and Config.Hospital.bed or {}
    return {
        dict = hb.dict or cfg('rest', 'dict', 'anim@gangops@morgue@table@'),
        clip = hb.clip or cfg('rest', 'clip', 'body_search'),
        z = tonumber(hb.zOffset) or tonumber(cfg('rest', 'zOffset', 0.0)) or 0.0,
        side = tonumber(hb.exitSide) or tonumber(cfg('rest', 'exitSide', 1.1)) or 1.1,
    }
end

local function hospitalBed()
    if NZA.Hospitals and type(NZA.Hospitals.InBed) == 'function' then
        local ok, id = pcall(NZA.Hospitals.InBed)
        if ok then return id end
    end
    return nil
end

function K.Lying() return lying ~= nil or hospitalBed() ~= nil end
function K.AIActive() return ai ~= nil end

-- ════════════════════════════════════════════════════════════════════════
-- NUI
-- ════════════════════════════════════════════════════════════════════════

local function keys()
    local hb = Config.Hospital and Config.Hospital.bed or {}
    return {
        getUp = cfg('rest', 'getUpKey', 'X'), hospitalGetUp = hb.getUpKey or 'X',
        cam = cfg('ai', 'cameraKey', 'C'), hold = tonumber(cfg('ai', 'getUpHold', 1.5)) or 1.5,
        summary = tonumber(cfg('ai', 'summaryTime', 9)) or 9,
    }
end

local function openBed(data)
    data.locale = NZA.LocaleTable('checkin')
    data.keys = keys()
    data.clock = K.Clock and K.Clock() or nil
    NZA.UI.Open(APP, data, { focus = false, cursor = false })
    appOpen = true
end

local function closeBed()
    if not appOpen then return end
    appOpen = false
    NZA.UI.Close(APP)
end

NZA.Bus.On('ui:closed', function(app)
    if app == APP then appOpen = false end
end)

-- ════════════════════════════════════════════════════════════════════════
-- CINEMATIC CAMERA
-- ════════════════════════════════════════════════════════════════════════

local function destroyCams(keep)
    for i = #cine.cams, 1, -1 do
        local c = cine.cams[i]
        if c ~= keep then
            if DoesCamExist(c) then DestroyCam(c, false) end
            table.remove(cine.cams, i)
        end
    end
end

-- keep a camera out of walls: pull it towards the bed when something is in the way
local function clearPos(from, to)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(from.x, from.y, from.z, to.x, to.y, to.z, 1 + 16, PlayerPedId(), 7)
    local _, hit, pos = GetShapeTestResult(ray)
    if hit == 1 or hit == true then
        local dir = to - from
        local len = #dir
        local hitLen = #(pos - from)
        local keepLen = math.max(0.75, hitLen - 0.3)
        if len > 0.01 and keepLen < len then return from + dir * (keepLen / len) end
    end
    return to
end

local function shots(c)
    local h = math.rad(c.w or 0.0)
    local fwd = vector3(-math.sin(h), math.cos(h), 0.0)
    local right = vector3(math.cos(h), math.sin(h), 0.0)
    local up = vector3(0.0, 0.0, 1.0)
    local base = v3(c)
    local side = -right    -- the open side (where you stand up and the doctor stands)
    return base, {
        { a = base + side * 2.3 + fwd * -0.9 + up * 0.85, b = base + side * 2.0 + fwd * 0.9 + up * 0.95, look = base + up * 0.15, fov = 44.0 },
        { a = base + fwd * 2.7 + up * 1.35, b = base + fwd * 2.1 + up * 1.15, look = base + up * 0.1, fov = 36.0 },
        { a = base + up * 2.5 + side * 0.25 + fwd * -0.2, b = base + up * 1.95 + side * 0.2 + fwd * 0.25, look = base, fov = 52.0 },
        { a = base + right * 2.0 + fwd * 1.1 + up * 1.1, b = base + right * 1.8 + fwd * -0.7 + up * 1.05, look = base + side * 0.6 + up * 0.35, fov = 40.0 },
        { a = base + fwd * -2.6 + up * 0.7, b = base + fwd * -2.2 + side * 0.5 + up * 0.9, look = base + up * 0.25, fov = 38.0 },
    }
end

local function stopCinematic(ease)
    if not cine.on then return end
    cine.on = false
    cine.gen = cine.gen + 1
    RenderScriptCams(false, ease ~= false, ease == false and 0 or 900, true, true)
    destroyCams()
    if cine.radar ~= nil then DisplayRadar(cine.radar) cine.radar = nil end
    if appOpen then NZA.UI.Send(APP, 'cam', { on = false }) end
end

local function startCinematic(coords)
    if cine.on or not coords then return end
    if NZA.Cam and NZA.Cam.Active and NZA.Cam.Active() then return end
    cine.on = true
    cine.gen = cine.gen + 1
    local gen = cine.gen
    cine.radar = not IsRadarHidden()
    DisplayRadar(false)
    if appOpen then NZA.UI.Send(APP, 'cam', { on = true }) end
    local base, list = shots(coords)
    local shotMs = math.floor((tonumber(cfg('ai', 'shotTime', 8)) or 8) * 1000)
    CreateThread(function()
        local i, first = 0, true
        while cine.on and cine.gen == gen do
            i = (i % #list) + 1
            local s = list[i]
            local pa = clearPos(base + vector3(0.0, 0.0, 0.6), s.a)
            local pb = clearPos(base + vector3(0.0, 0.0, 0.6), s.b)
            local ca = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', pa.x, pa.y, pa.z, 0.0, 0.0, 0.0, s.fov, false, 0)
            local cb = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', pb.x, pb.y, pb.z, 0.0, 0.0, 0.0, s.fov - 3.0, false, 0)
            PointCamAtCoord(ca, s.look.x, s.look.y, s.look.z)
            PointCamAtCoord(cb, s.look.x, s.look.y, s.look.z)
            cine.cams[#cine.cams + 1] = ca
            cine.cams[#cine.cams + 1] = cb
            SetCamActive(ca, true)
            if first then RenderScriptCams(true, true, 900, true, true) first = false end
            SetCamActiveWithInterp(cb, ca, shotMs, 1, 1)
            local t = GetGameTimer()
            while cine.on and cine.gen == gen and GetGameTimer() - t < shotMs do Wait(100) end
            if cine.on and cine.gen == gen then destroyCams(cb) end
        end
    end)
    CreateThread(function()
        while cine.on and cine.gen == gen do
            HideHudAndRadarThisFrame()
            Wait(0)
        end
    end)
end

local function toggleCinematic()
    if not ai then return end
    if cine.on then
        cine.user = false
        stopCinematic()
    else
        cine.user = true
        startCinematic(ai.coords)
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- DOCTOR PED
-- ════════════════════════════════════════════════════════════════════════

local function deleteDoctor()
    doctorTask = nil
    if doctor and DoesEntityExist(doctor) then
        SetEntityAsMissionEntity(doctor, true, true)
        DeleteEntity(doctor)
    end
    doctor = nil
end

local NOTE_STEPS = { assess = true, discharge = true }

local function doctorDo(stepKey)
    if not doctor or not DoesEntityExist(doctor) then return end
    local want = NOTE_STEPS[stepKey] and 'notes' or 'work'
    if doctorTask == want then return end
    doctorTask = want
    ClearPedTasks(doctor)
    if want == 'notes' then
        TaskStartScenarioInPlace(doctor, cfg('ai', 'doctorScenario', 'CODE_HUMAN_MEDIC_TIME_OF_DEATH'), 0, true)
    else
        local w = cfg('ai', 'doctorWork', {}) or {}
        local dict = w.dict or 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@'
        local clip = w.clip or 'machinic_loop_mechandplayer'
        local ok = pcall(lib.requestAnimDict, dict, 4000)
        if ok and doctor and DoesEntityExist(doctor) then
            TaskPlayAnim(doctor, dict, clip, 4.0, -4.0, -1, 1, 0.0, false, false, false)
        end
    end
end

local function spawnDoctor(coords, stepKey)
    if not cfg('ai', 'doctorPed', true) or not coords then return end
    deleteDoctor()
    CreateThread(function()
        local models = cfg('ai', 'doctorModels', { 's_m_m_doctor_01' }) or {}
        local hash
        for _, m in ipairs(models) do
            local h = joaat(m)
            if IsModelInCdimage(h) and IsModelAPed(h) then hash = h break end
        end
        if not hash then return end
        local ok = pcall(lib.requestModel, hash, 8000)
        if not ok or not HasModelLoaded(hash) or not ai then return end
        local h = math.rad(coords.w or 0.0)
        local right = vector3(math.cos(h), math.sin(h), 0.0)
        local side = tonumber(pose().side) or 1.1
        local pos = v3(coords) - right * (side * 0.85)
        local found, gz = GetGroundZFor_3dCoord(pos.x, pos.y, pos.z + 0.5, false)
        local z = (found and gz > pos.z - 2.5) and gz or (pos.z - 0.55)
        local ped = CreatePed(4, hash, pos.x, pos.y, z, ((coords.w or 0.0) - 90.0) % 360.0, false, true)
        SetModelAsNoLongerNeeded(hash)
        if not ped or ped == 0 then return end
        if not ai then DeleteEntity(ped) return end
        doctor = ped
        SetEntityAsMissionEntity(ped, true, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetEntityInvincible(ped, true)
        SetPedCanRagdoll(ped, false)
        SetPedFleeAttributes(ped, 0, false)
        SetPedDiesWhenInjured(ped, false)
        SetPedCanBeTargetted(ped, false)
        SetEntityCanBeDamaged(ped, false)
        SetPedKeepTask(ped, true)
        SetEntityHeading(ped, ((coords.w or 0.0) - 90.0) % 360.0)
        FreezeEntityPosition(ped, true)
        doctorTask = nil
        doctorDo(stepKey)
    end)
end

-- ════════════════════════════════════════════════════════════════════════
-- LYING DOWN / GETTING UP
-- ════════════════════════════════════════════════════════════════════════

local function playPose(ped)
    local p = pose()
    return NZA.Anim.Play(ped, p.dict, p.clip, { flag = 1 })
end

local function standBeside(ped, c)
    local h = math.rad((c.w or 0.0) + 90.0)
    local side = pose().side
    local x, y = c.x - math.sin(h) * side, c.y + math.cos(h) * side
    local found, gz = GetGroundZFor_3dCoord(x, y, c.z + 0.6, false)
    local z = (found and gz > c.z - 2.5) and gz or c.z
    SetEntityCoords(ped, x, y, z, false, false, false, false)
    SetEntityHeading(ped, ((c.w or 0.0) + 90.0) % 360.0)
end

-- reason: 'key' | 'done' | 'abort' | 'dead' | 'stop' ; silent = no toast, no server call when false
function K.GetUp(reason, opts)
    if not lying then return end
    opts = opts or {}
    local st = lying
    lying = nil
    lyingGen = lyingGen + 1
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, false)
    NZA.Anim.Stop(ped, { immediate = true })
    if NZA.Self.State() == 'alive' then
        ClearPedTasks(ped)
        standBeside(ped, st.coords)
    end
    if NZA.Wounded and NZA.Wounded.SuspendPose then NZA.Wounded.SuspendPose('checkin_bed', false) end
    if appOpen then NZA.UI.Send(APP, 'hold', { p = 0 }) end
    if opts.server ~= false then
        CreateThread(function() call('nza:checkin:lie', { point = st.point, on = false }) end)
    end
    if not opts.silent and reason == 'key' and not ai then toast(L('bed_up'), 'info') end
end

local function lyingLoop()
    local gen = lyingGen
    CreateThread(function()
        local p = pose()
        local holdStart, lastSent = nil, -1
        local control = tonumber(cfg('rest', 'getUpControl', 73)) or 73
        local tick = 0
        while lying and lyingGen == gen do
            local ped = PlayerPedId()
            DisableControlAction(0, 21, true)   -- sprint
            DisableControlAction(0, 22, true)   -- jump
            DisableControlAction(0, 23, true)   -- enter vehicle
            DisableControlAction(0, 24, true)   -- attack
            DisableControlAction(0, 25, true)   -- aim
            DisableControlAction(0, 44, true)   -- cover
            DisableControlAction(0, 140, true)  -- melee
            DisableControlAction(0, control, true)
            tick = tick + 1
            if tick % 20 == 0 and not IsEntityPlayingAnim(ped, p.dict, p.clip, 3) then playPose(ped) end
            local need = ai and (tonumber(cfg('ai', 'getUpHold', 1.5)) or 1.5) or 0
            if IsDisabledControlPressed(0, control) then
                if need <= 0 then
                    if IsDisabledControlJustPressed(0, control) then K.GetUp('key') break end
                else
                    holdStart = holdStart or GetGameTimer()
                    local prog = math.min(1.0, (GetGameTimer() - holdStart) / (need * 1000))
                    local step = math.floor(prog * 20)
                    if step ~= lastSent and appOpen then lastSent = step NZA.UI.Send(APP, 'hold', { p = prog }) end
                    if prog >= 1.0 then K.GetUp('key') break end
                end
            elseif holdStart then
                holdStart, lastSent = nil, -1
                if appOpen then NZA.UI.Send(APP, 'hold', { p = 0 }) end
            end
            if NZA.Self.State() == 'dead' then K.GetUp('dead', { silent = true }) break end
            Wait(0)
        end
    end)
end

function K.LieDown(ticket, teleport)
    if lying or busy or type(ticket) ~= 'table' or not ticket.bedId then return false end
    if hospitalBed() then return false end
    busy = true
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then busy = false return false end
    if teleport then
        DoScreenFadeOut(450)
        local t = GetGameTimer()
        while not IsScreenFadedOut() and GetGameTimer() - t < 1500 do Wait(0) end
    end
    local res = call('nza:checkin:lie', { point = ticket.bedId, on = true, teleport = teleport == true })
    if not res.ok or type(res.coords) ~= 'table' then
        busy = false
        if teleport then DoScreenFadeIn(450) end
        toast(res.msg or L('err_failed'), 'error')
        return false
    end
    local c = res.coords
    if NZA.Wounded and NZA.Wounded.SuspendPose then NZA.Wounded.SuspendPose('checkin_bed', true) end
    ped = PlayerPedId()
    ClearPedTasksImmediately(ped)
    local p = pose()
    local at = vector4(c.x + 0.0, c.y + 0.0, c.z + 0.0, (c.w or 0.0) + 0.0)
    -- on the mattress, not in it (the transport module finds the top and lifts the body onto it)
    local Tr = NZA.Transport
    local spot, lift = at, 0.0
    if Tr and Tr.BedSpot then spot, lift = Tr.BedSpot(at, 'bed', ped) end
    SetEntityCoordsNoOffset(ped, spot.x, spot.y, spot.z + p.z, false, false, false)
    SetEntityHeading(ped, (c.w or 0.0) + 0.0)
    FreezeEntityPosition(ped, true)
    playPose(ped)
    -- the body rests on the mattress once its height is measured
    if Tr and Tr.SettleLying and lift > 0.0 then
        Tr.SettleLying(ped, { dict = p.dict, clip = p.clip }, lift, function(d)
            if lying and lying.point == ticket.bedId then SetEntityCoordsNoOffset(ped, spot.x, spot.y, spot.z + p.z + d, false, false, false) end
        end)
    end
    lyingGen = lyingGen + 1
    lying = { point = ticket.bedId, coords = c, label = res.label, gen = lyingGen }
    lyingLoop()
    if rest and rest.point == lying.point and appOpen and not ai then NZA.UI.Send(APP, 'rest', { how = restKeys(lying.point) }) end
    if teleport then
        Wait(350)
        DoScreenFadeIn(700)
    end
    busy = false
    if K.StopGuide then K.StopGuide() end
    return true
end

-- ════════════════════════════════════════════════════════════════════════
-- AI DOCTOR SESSION
-- ════════════════════════════════════════════════════════════════════════

local function endAI(keepRest)
    stopCinematic()
    deleteDoctor()
    ai = nil
    if not keepRest then
        if rest then rest = nil restGen = restGen + 1 end
    end
end

local function bedCoordsFor(data)
    if type(data.coords) == 'table' then return data.coords end
    if lying then return lying.coords end
    local pt = data.point and NZA.Points.Get(data.point)
    if pt and pt.coords then return { x = pt.coords.x, y = pt.coords.y, z = pt.coords.z, w = pt.coords.w or 0.0 } end
    return nil
end

local AI_ACTIONS = {}

-- [C] switches between the cinematic shots and your own camera while the AI works
local function aiLoop(session)
    CreateThread(function()
        local control = tonumber(cfg('ai', 'cameraControl', 26)) or 26
        while ai == session do
            DisableControlAction(0, control, true)
            if IsDisabledControlJustPressed(0, control) then toggleCinematic() end
            Wait(0)
        end
    end)
end

AI_ACTIONS.start = function(data)
    local coords = bedCoordsFor(data)
    ai = { data = data, coords = coords, index = tonumber(data.index) or 0 }
    aiLoop(ai)
    cine.user = true
    restGen = restGen + 1   -- the AI HUD replaces the rest HUD
    openBed({ mode = 'ai', session = data, cinematic = cfg('ai', 'cinematic', true) ~= false })
    local steps = data.steps or {}
    local first = steps[math.max(1, ai.index)] or steps[1] or {}
    spawnDoctor(coords, first.key)
    if cfg('ai', 'cinematic', true) ~= false and cine.user ~= false then startCinematic(coords) end
    NZA.UI.Send('_core', 'sound', { name = 'success' })
end

AI_ACTIONS.step = function(data)
    if not ai then return end
    ai.index = tonumber(data.index) or ai.index
    local st = (ai.data.steps or {})[ai.index] or {}
    doctorDo(st.key)
    NZA.UI.Send(APP, 'step', data)
end

AI_ACTIONS.vitals = function(data)
    if ai then NZA.UI.Send(APP, 'vitals', data) end
end

AI_ACTIONS.done = function(data)
    if not ai then return end
    NZA.UI.Send(APP, 'done', data)
    NZA.UI.Send('_core', 'sound', { name = 'success' })
    local holdMs = math.floor((tonumber(cfg('ai', 'summaryTime', 9)) or 9) * 1000)
    local session = ai
    if doctor and DoesEntityExist(doctor) then doctorTask = nil doctorDo('discharge') end
    SetTimeout(holdMs, function()
        if ai ~= session then return end
        endAI(false)
        closeBed()
        if lying then K.GetUp('done', { silent = true }) end
        toast(data.msg or L('closed_done', session.data.ticket or ''), data.unpaid and 'warning' or 'success', L('ai_title'), 8000)
    end)
end

AI_ACTIONS.abort = function(data)
    if not ai then return end
    local reason = tostring(data.reason or 'stopped')
    local staffTook = reason == 'staff'
    endAI(staffTook)
    if staffTook and rest then
        -- a medic took over: stay in the bed, the rest HUD comes back
        local point = rest.point
        rest = nil
        startRest(point)
    else
        closeBed()
        if lying and not staffTook then K.GetUp('abort', { silent = true }) end
    end
    local msg = L('ai_abort_' .. reason)
    if data.bill and (tonumber(data.amount) or 0) > 0 then msg = msg .. ' ' .. L('ai_abort_bill', data.amount) end
    toast(msg, staffTook and 'info' or 'warning', L('ai_title'), 8000)
end

RegisterNetEvent('nza:checkin:ai', function(action, data)
    local fn = AI_ACTIONS[action]
    if fn and type(data) == 'table' then fn(data) end
end)

-- ════════════════════════════════════════════════════════════════════════
-- BED REST HUD
-- ════════════════════════════════════════════════════════════════════════

function restKeys(point)
    if lying and lying.point == point then return { getUp = cfg('rest', 'getUpKey', 'X'), own = true } end
    if hospitalBed() == point then
        local hb = Config.Hospital and Config.Hospital.bed or {}
        return { getUp = hb.getUpKey or 'X', hospital = true }
    end
    return { medic = true }
end

function startRest(point)
    if cfg('rest', 'enabled', true) == false then return end
    restGen = restGen + 1
    local gen = restGen
    rest = { point = point, since = GetGameTimer(), gen = gen }
    if ai then return end
    local pt = NZA.Points.Get(point)
    openBed({ mode = 'rest', point = point, bed = pt and pt.label or nil, how = restKeys(point) })
    if cfg('rest', 'hideBedPrompt', true) ~= false then
        SetTimeout(250, function() if rest and rest.gen == gen then NZA.UI.HidePrompt('nza_hospital_bed') end end)
        SetTimeout(1200, function() if rest and rest.gen == gen then NZA.UI.HidePrompt('nza_hospital_bed') end end)
    end
    CreateThread(function()
        local poll = math.max(2, tonumber(cfg('rest', 'poll', 4)) or 4) * 1000
        Wait(600)   -- let whoever put us in the bed finish lying down first (key hints)
        while rest and rest.gen == gen and not ai do
            local res = call('nza:checkin:rest')
            if not (rest and rest.gen == gen) or ai then break end
            if res.ok then
                if res.inBed == false then
                    rest = nil
                    closeBed()
                    break
                end
                res.how = restKeys(point)
                res.since = math.floor((GetGameTimer() - rest.since) / 1000)
                NZA.UI.Send(APP, 'rest', res)
            end
            local t = GetGameTimer()
            while rest and rest.gen == gen and not ai and GetGameTimer() - t < poll do Wait(250) end
        end
    end)
end

local function stopRest()
    if not rest then return end
    rest = nil
    restGen = restGen + 1
    if not ai then closeBed() end
end

RegisterNetEvent('nza:checkin:bed', function(data)
    if type(data) ~= 'table' then return end
    local point = tonumber(data.point) or data.point
    if data.on then
        if rest and rest.point == point then return end
        startRest(point)
    elseif rest and (rest.point == point or point == nil) then
        stopRest()
        -- the bed was released by someone else (medic, transport): stand up too
        if lying and lying.point == point and not ai then K.GetUp('stop', { silent = true, server = false }) end
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- LIFECYCLE
-- ════════════════════════════════════════════════════════════════════════

NZA.Bus.On('self:state', function(new)
    if new == 'dead' then
        if ai then endAI(false) closeBed() end
        if lying then K.GetUp('dead', { silent = true }) end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    stopCinematic(false)
    deleteDoctor()
    if lying then
        local ped = PlayerPedId()
        FreezeEntityPosition(ped, false)
        ClearPedTasksImmediately(ped)
    end
    if IsScreenFadedOut() or IsScreenFadingOut() then DoScreenFadeIn(0) end
    if appOpen then NZA.UI.Close(APP) end
end)
