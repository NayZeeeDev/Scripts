--[[
    NAYZEEE AMBULANCE - CPR & defibrillator (client)                          NZA.Cpr

    Starts / joins a code on a patient in cardiac arrest (or wounded, unresponsive and not
    breathing), opens the NUI app 'cpr' (rugged NAYZEEE defibrillator, rhythm game, pads,
    analyse / charge / shock, breaths, adrenaline, swap, debrief) and relays it to the
    authoritative server (server/modules/cpr.lua). The world side lives in cpr_scene.lua.

    Registrations (file top level):
      NZA.Interact.Add  nza_cpr       'Start CPR'  (perm Config.Cpr.perm, order 30, arrest / wounded U)
                        nza_cpr_join  'Join CPR'   (a code is running: take the airway / defib / drugs)
      NZA.ExamRoutes    'cpr'         'Start CPR' button in the Examination screen (arrest, or U + not breathing)
      NZA.RadialItems   'cpr_start'   Patient ▸ Start CPR on the nearest patient in arrest
    API:
      NZA.Cpr.Start(entity?, target?) → bool      (blocks for the server reply; call from a thread)
      NZA.Cpr.Active() → code table | nil         NZA.Cpr.Nearest(maxDist?) → ped, target
      NZA.Cpr.WaitEnd()                            blocks until your part in the code is over
    Server callbacks used: nza:cpr:start, nza:cpr:<pads|analyse|charge|disarm|shock|energy|mode|adrenaline|swap|pulse>
    Net events:  → nza:cpr:cycle, nza:cpr:breath, nza:cpr:hands, nza:cpr:leave
                 ← nza:cpr:state, nza:cpr:event, nza:cpr:ended, nza:cpr:pose (patient side), nza:cpr:use (defib item)
    NUI callbacks: cpr:press, cpr:report, cpr:hands, cpr:breathStart, cpr:breath, cpr:action, cpr:leave
    Client bus: cpr:started (code), cpr:ended (summary)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Cpr = NZA.Cpr or {}
local C = NZA.Cpr
local U = NZA.Util

local APP = 'cpr'
local active = nil          -- your part in a code (see begin)

local ACTIONS = { pads = true, analyse = true, charge = true, disarm = true, shock = true, energy = true, mode = true,
    adrenaline = true, swap = true, pulse = true }

local function cfg() return Config.Cpr or {} end
local function sub(name) return cfg()[name] or {} end
local function L(key, ...) return NZA.L('cpr.' .. key, ...) end
local function Scene() return NZA.Cpr.Scene end

local function toast(kind, msg, title)
    NZA.UI.Toast({ title = title or L('title'), message = msg, type = kind or 'info' })
end

-- ════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════════════

-- server id of the compressor while a code runs on this ped (state bag 'nzaCpr', set by the server)
local function cprBag(ent)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return nil end
    if IsPedAPlayer(ent) then
        if ent == PlayerPedId() then return LocalPlayer.state.nzaCpr end
        local idx = NetworkGetPlayerIndexFromPed(ent)
        if not idx or idx == -1 then return nil end
        return Player(GetPlayerServerId(idx)).state.nzaCpr
    end
    if not NetworkGetEntityIsNetworked(ent) then return nil end
    return Entity(ent).state.nzaCpr
end
C.Bag = cprBag

-- statebag summary → could this patient need CPR? (the server makes the real decision)
local function eligibleBag(bag)
    if type(bag) ~= 'table' then return false end
    if bag.st == 'arrest' then return true end
    if bag.st == 'wounded' and cfg().wounded ~= false and bag.avpu == 'U' then return true end
    return false
end

local function uiCfg()
    local cc, b, d, cy = sub('Compressions'), sub('Breaths'), sub('Defib'), sub('Cycle')
    return {
        target = cc.target, rateMin = cc.rateMin, rateMax = cc.rateMax, perSet = cc.perSet, perfect = cc.perfect, good = cc.good,
        pressMin = cc.pressMin, pressMax = cc.pressMax, metronome = cc.metronome ~= false, idleWarn = cc.idleWarn,
        breathHold = b.hold, tooShort = b.tooShort, tooLong = b.tooLong, mouthSlower = b.mouthSlower, mouthToMouth = b.mouthToMouth ~= false,
        analyseTime = d.analyseTime, chargedFor = d.chargedFor, energies = d.energies, aedEnergies = d.aedEnergies,
        cycleLength = cy.length, checkGrace = cy.checkGrace, snap = sub('Pads').snap,
        sounds = not (Config.UI and Config.UI.sounds == false),
    }
end

function C.Active() return active end

function C.Nearest(maxDist)
    maxDist = tonumber(maxDist) or tonumber(cfg().radialRange) or 3.0
    local me = PlayerPedId()
    local mc = GetEntityCoords(me)
    local best, bestD, bestT = nil, nil, nil
    for _, ped in ipairs(GetGamePool('CPed')) do
        if ped ~= me then
            local d = #(GetEntityCoords(ped) - mc)
            if d <= maxDist and (not best or d < bestD) then
                if eligibleBag(NZA.Target.State(ped)) or cprBag(ped) then
                    local t = NZA.Target.FromEntity(ped)
                    if t then best, bestD, bestT = ped, d, t end
                end
            end
        end
    end
    return best, bestT
end

function C.WaitEnd()
    while active do Wait(250) end
end

-- ════════════════════════════════════════════════════════════════════════
-- START / JOIN
-- ════════════════════════════════════════════════════════════════════════

local function loop(a)
    CreateThread(function()
        while active == a and a.active do
            local ok, err = pcall(Scene().Tick, a)
            if not ok then NZA.Debug('cpr scene tick', err) end
            -- the server went quiet (restart / crash): do not leave the medic stuck
            if GetGameTimer() - (a.lastState or 0) > 12000 then
                C.Finish({ reason = 'error' })
                break
            end
            Wait(0)
        end
    end)
end

local function begin(target, entity, res)
    local view = res.view or {}
    local a = {
        active = true, target = target, entity = entity, pid = view.pid, origin = res.origin, role = view.role or 'comp',
        view = view, npc = view.npc == true, easy = view.easy == true, startedAt = GetGameTimer(), lastState = GetGameTimer(),
        joined = res.joined == true, rate = tonumber(sub('Compressions').target) or 110,
    }
    active = a
    NZA.UI.Open(APP, {
        view = view, keys = sub('Keys'), cfg = uiCfg(), locale = NZA.LocaleTable('cpr'), easy = a.easy,
    }, { focus = true, cursor = true })
    local ok, err = pcall(Scene().Enter, a)
    if not ok then NZA.Debug('cpr scene enter', err) end
    loop(a)
    NZA.Bus.Emit('cpr:started', a)
end

function C.Start(entity, target)
    if active then
        if active.ended then NZA.UI.Close(APP); active = nil
        else toast('error', L('err_in_code')); return false end
    end
    if NZA.Proc and NZA.Proc.Active and NZA.Proc.Active() then toast('error', L('err_busy_proc')); return false end
    if NZA.Self.State() ~= 'alive' then return false end
    if not target and entity then target = NZA.Target.FromEntity(entity) end
    if not entity and target then entity = NZA.Target.Entity(target) end
    if not target or not entity or entity == 0 then toast('error', L('err_no_patient')); return false end
    local origin = Scene().Origin(entity)
    local ok, res = pcall(lib.callback.await, 'nza:cpr:start', false, target, { origin = origin })
    if not ok or type(res) ~= 'table' then toast('error', L('err_failed')); return false end
    if not res.ok then toast('error', res.msg or L('err_failed')); return false end
    res.origin = res.origin or origin
    begin(target, entity, res)
    return true
end

-- your part is over: debrief in the app, world back to normal now
function C.Finish(summary)
    local a = active
    if not a or a.ended then return end
    a.ended, a.active = true, false
    local ok, err = pcall(Scene().Leave, a)
    if not ok then NZA.Debug('cpr scene leave', err) end
    NZA.UI.Send(APP, 'ended', summary or {})
    NZA.Bus.Emit('cpr:ended', summary or {})
    SetTimeout(45000, function()
        if active == a then NZA.UI.Close(APP); active = nil end
    end)
end

local function abandon()
    local a = active
    if not a then return end
    if not a.ended then
        TriggerServerEvent('nza:cpr:leave')
        a.ended, a.active = true, false
        pcall(Scene().Leave, a)
    end
    active = nil
end

-- ════════════════════════════════════════════════════════════════════════
-- SERVER → CLIENT
-- ════════════════════════════════════════════════════════════════════════

RegisterNetEvent('nza:cpr:state', function(view)
    local a = active
    if not a or a.ended or type(view) ~= 'table' or view.pid ~= a.pid then return end
    local oldRole, oldPhase, oldPads = a.role, a.view and a.view.phase, a.view and a.view.pads
    a.view, a.role, a.lastState = view, view.role or a.role, GetGameTimer()
    if view.bed ~= nil then a.bed = view.bed == true end
    NZA.UI.Send(APP, 'state', view)
    if oldRole ~= a.role then CreateThread(function() pcall(Scene().Role, a) end) end
    if oldPhase ~= view.phase then pcall(Scene().Phase, a, view.phase) end
    if view.pads and not oldPads and a.padsMine then pcall(Scene().PadsPlaced, a) end
end)

RegisterNetEvent('nza:cpr:event', function(ev)
    local a = active
    if not a or a.ended or type(ev) ~= 'table' then return end
    NZA.UI.Send(APP, 'event', ev)
    CreateThread(function() pcall(Scene().Event, a, ev) end)
end)

RegisterNetEvent('nza:cpr:ended', function(summary)
    C.Finish(type(summary) == 'table' and summary or {})
end)

-- patient side: lie flat in the synced pose while someone does CPR on you
RegisterNetEvent('nza:cpr:pose', function(d)
    pcall(Scene().Pose, d)
end)

-- the defibrillator item was used: start (or join) CPR on the nearest patient who needs it
RegisterNetEvent('nza:cpr:use', function()
    if active then toast('error', L('err_in_code')); return end
    CreateThread(function()
        local ped, target = C.Nearest((tonumber(cfg().distance) or 2.0) + 1.0)
        if not ped then toast('error', L('err_nobody')); return end
        C.Start(ped, target)
    end)
end)

-- ════════════════════════════════════════════════════════════════════════
-- NUI → CLIENT → SERVER
-- ════════════════════════════════════════════════════════════════════════

local function live() return active and not active.ended and active or nil end

NZA.UI.On(APP, 'press', function(_, cb)
    cb({ ok = true })
    local a = live()
    if a then pcall(Scene().Press, a, a.rate) end
end)

NZA.UI.On(APP, 'report', function(d, cb)
    cb({ ok = true })
    local a = live()
    if not a or type(d) ~= 'table' then return end
    local n = math.floor(U.clamp(tonumber(d.n) or 0, 0, 12))
    local r = tonumber(d.rate) or 0
    if r > 0 then a.rate = U.clamp(r, 40, 200) end
    if n <= 0 and not d.done then return end
    TriggerServerEvent('nza:cpr:cycle', {
        n = n, timing = U.clamp(tonumber(d.timing) or 0, 0, 100), depth = U.clamp(tonumber(d.depth) or 0, 0, 100),
        recoil = U.clamp(tonumber(d.recoil) or 0, 0, 100), rate = U.clamp(tonumber(d.rate) or 0, 0, 220), done = d.done == true,
    })
end)

NZA.UI.On(APP, 'hands', function(_, cb)
    cb({ ok = true })
    if live() then TriggerServerEvent('nza:cpr:hands') end
end)

NZA.UI.On(APP, 'breathStart', function(_, cb)
    cb({ ok = true })
    local a = live()
    if a then pcall(Scene().Breath, a, true) end
end)

NZA.UI.On(APP, 'breath', function(d, cb)
    cb({ ok = true })
    local a = live()
    if not a or type(d) ~= 'table' then return end
    pcall(Scene().Breath, a, false)
    TriggerServerEvent('nza:cpr:breath', { hold = U.clamp(tonumber(d.hold) or 0, 0, 5) })
end)

NZA.UI.On(APP, 'action', function(d, cb)
    local a = live()
    if not a or type(d) ~= 'table' or not ACTIONS[d.name] then cb({ ok = false, err = 'no_code' }); return end
    local ok, res = pcall(lib.callback.await, 'nza:cpr:' .. d.name, false, type(d.data) == 'table' and d.data or {})
    if not ok or type(res) ~= 'table' then res = { ok = false, err = 'error', msg = L('err_failed') } end
    if d.name == 'pads' and res.ok then a.padsMine = true; if a.view and a.view.pads then pcall(Scene().PadsPlaced, a) end end
    cb(res)
end)

NZA.UI.On(APP, 'leave', function(_, cb)
    cb({ ok = true })
    if live() then TriggerServerEvent('nza:cpr:leave') end
end)

-- the app was closed from JS (debrief Done, or anything else): make sure nothing is left behind
NZA.Bus.On('ui:closed', function(app)
    if app == APP then abandon() end
end)

-- ════════════════════════════════════════════════════════════════════════
-- REGISTRATIONS
-- ════════════════════════════════════════════════════════════════════════

NZA.Interact.Add({
    name = 'nza_cpr', label = L('opt_start'), icon = cfg().icon or 'heart', order = tonumber(cfg().order) or 30,
    description = L('opt_start_desc'), perm = cfg().perm or 'cpr',
    states = { arrest = true, wounded = true }, self = false, npc = true, player = true,
    distance = tonumber(cfg().distance) or 2.0,
    canInteract = function(entity, _, bag)
        return active == nil and cprBag(entity) == nil and eligibleBag(bag)
    end,
    onSelect = function(entity, target) C.Start(entity, target) end,
})

NZA.Interact.Add({
    name = 'nza_cpr_join', label = L('opt_join'), icon = 'users', order = (tonumber(cfg().order) or 30) + 1,
    description = L('opt_join_desc'), perm = cfg().perm or 'cpr',
    states = { arrest = true, wounded = true }, self = false, npc = true, player = true,
    distance = tonumber(cfg().distance) or 2.0,
    canInteract = function(entity)
        return active == nil and (tonumber(cfg().maxTeam) or 2) > 1 and cprBag(entity) ~= nil
    end,
    onSelect = function(entity, target) C.Start(entity, target) end,
})

NZA.ExamRoutes = NZA.ExamRoutes or {}
if cfg().examRoute ~= false then
    table.insert(NZA.ExamRoutes, {
        id = 'cpr', label = L('route_label'), icon = cfg().icon or 'heart', perm = cfg().perm or 'cpr', order = 1,
        types = nil, regions = nil,
        available = function(_, snap)
            if type(snap) ~= 'table' then return false end
            if snap.state == 'arrest' then return true end
            local v = snap.vitals or {}
            if snap.state == 'wounded' and cfg().wounded ~= false and v.avpu == 'U'
                and (v.breathing == 'absent' or v.breathing == 'agonal') then
                return true
            end
            return false
        end,
        run = function(target)
            if C.Start(nil, target) then C.WaitEnd() end
        end,
    })
end

NZA.RadialItems = NZA.RadialItems or {}
if cfg().radial ~= false then
    table.insert(NZA.RadialItems, {
        id = 'cpr_start', parent = 'patient', label = L('radial_label'), desc = L('radial_desc'),
        icon = cfg().icon or 'heart', order = tonumber(cfg().order) or 30, perm = cfg().perm or 'cpr',
        canShow = function() return active == nil and C.Nearest() ~= nil end,
        onSelect = function()
            CreateThread(function()
                local ped, target = C.Nearest()
                if not ped then toast('error', L('err_nobody')); return end
                C.Start(ped, target)
            end)
        end,
    })
end

-- ════════════════════════════════════════════════════════════════════════
-- CLEANUP
-- ════════════════════════════════════════════════════════════════════════

-- you went down yourself: the server ends your part; this is the local safety net
NZA.Bus.On('self:state', function(new)
    if new ~= 'alive' and active and not active.ended then
        TriggerServerEvent('nza:cpr:leave')
        C.Finish({ reason = 'down', left = true })
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    local a = active
    if a then
        a.active = false
        pcall(Scene().Leave, a)
        NZA.UI.Close(APP)
        active = nil
    end
end)
