--[[
    NAYZEEE AMBULANCE - Airway (client)                                       NZA.Intubation

    Runs a bag-valve-mask round (NZA.Proc 'bvm') or a video laryngoscope intubation
    (NZA.Proc 'intubate') on a patient: world scene (intubation_scene.lua), NUI app
    'intubation' (8-step procedure HUD with its own airway monitor, video laryngoscope screen,
    cuff manometer, capnograph and chest auscultation), live server vitals while it runs.
    Easy mode: ox_lib progress bar with the props and camera stepping through the phases.

    Registrations (file top level):
      NZA.Interact.Add  nza_airway_bvm       'Ventilate (BVM)'      order 31 (resuscitation)
                        nza_airway_intubate  'Intubate'             order 61 (procedures)
                        nza_airway_check     'Check tube position'  (intubated patients)
                        nza_airway_adjust    'Correct tube depth'
                        nza_airway_extubate  'Remove the tube'
      NZA.ExamRoutes    airway_intubate (airway / hypoxia conditions, severe face / neck wounds)
                        airway_bvm      (airway / hypoxia conditions)
                        airway_retube   (an oesophageal tube found by the capnography check)
      NZA.RadialItems   airway_bvm, airway_intubate   (Patient ▸ …, nearest patient)
    API:
      NZA.Intubation.Start(mode 'intubate'|'bvm', entity?, target?) → ok, outcome|reason  (blocks)
      NZA.Intubation.Active() → session | nil      NZA.Intubation.Nearest(mode, maxDist?) → ped, target
    NUI callbacks: intubation:step { step, phase, placed } · intubation:finish { result } · intubation:abort
    NUI messages:  open (data from the server + locale + monitor flag) · vitals · abort
    Net events:    nza:intubation:use (mode) - a usable item was used (server)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Intubation = NZA.Intubation or {}
local I = NZA.Intubation
local APP = 'intubation'
local session = nil

local function cfg() return Config.Intubation or {} end
local function sub(k)
    local c = cfg()[k]
    return type(c) == 'table' and c or {}
end
local function L(key, ...) return NZA.L('intubation.' .. key, ...) end
local function Scene() return NZA.Intubation.Scene end
local function perm() return cfg().perm or 'airway' end
local function bvmPerm() return sub('bvm').perm or perm() end
local function toast(kind, msg, title)
    NZA.UI.Toast({ type = kind, title = title or L('title'), message = msg })
end

-- ════════════════════════════════════════════════════════════════════════
-- ELIGIBILITY (from the replicated state bag; the server re-checks everything)
-- ════════════════════════════════════════════════════════════════════════

local function downOk(st, avpu)
    if st == 'arrest' then return true end
    if st ~= 'wounded' then return false end
    if cfg().requireDown == false then return true end
    local allowed = cfg().downAvpu or { P = true, U = true }
    return allowed[avpu or 'A'] == true
end

local function canIntubate(bag)
    return type(bag) == 'table' and not bag.bag and not bag.intub and downOk(bag.st, bag.avpu)
end

local function canBvm(bag)
    local b = sub('bvm')
    if b.enabled == false or type(bag) ~= 'table' or bag.bag then return false end
    local states = b.states or { wounded = true, arrest = true }
    return states[bag.st] == true
end

local function eligible(mode, bag)
    if mode == 'bvm' then return canBvm(bag) end
    return canIntubate(bag)
end

function I.Nearest(mode, maxDist)
    maxDist = tonumber(maxDist) or tonumber(cfg().radialRange) or 3.0
    local me = PlayerPedId()
    local mc = GetEntityCoords(me)
    local best, bestD, bestT = nil, nil, nil
    for _, ped in ipairs(GetGamePool('CPed')) do
        if ped ~= me then
            local d = #(GetEntityCoords(ped) - mc)
            if d <= maxDist and (not best or d < bestD) and eligible(mode, NZA.Target.State(ped)) then
                local t = NZA.Target.FromEntity(ped)
                if t then best, bestD, bestT = ped, d, t end
            end
        end
    end
    return best, bestT
end

function I.Active() return session end

-- ════════════════════════════════════════════════════════════════════════
-- SESSION
-- ════════════════════════════════════════════════════════════════════════

local function endSession(s)
    if not s or s.ended then return end
    s.ended = true
    if s.stopWatch then pcall(s.stopWatch) end
    s.stopWatch = nil
    if s.open then NZA.UI.Close(APP) end
    s.open = false
    if s.extMon and NZA.Monitor and NZA.Monitor.Close then pcall(NZA.Monitor.Close) end
    if s.scene then Scene().End(s.scene) end
    s.scene = nil
end

local function externalMonitor()
    return cfg().externalMonitor == true and type(NZA.Monitor) == 'table' and type(NZA.Monitor.Open) == 'function'
end

local function sendVitals(snap)
    if type(snap) ~= 'table' then return end
    local v = snap.vitals or {}
    NZA.UI.Send(APP, 'vitals', {
        hr = tonumber(v.ecgRate) or tonumber(v.hr), sys = tonumber(v.sys), dia = tonumber(v.dia), map = tonumber(v.map),
        temp = tonumber(v.temp), rhythm = v.rhythm,
    })
end

-- the minigame (normal mode): scene, app, live vitals, wait for the app's verdict
local function run(s, ctx)
    s.ctx = ctx
    local d = type(ctx.data) == 'table' and ctx.data or {}
    local anat = type(d.anat) == 'table' and d.anat or {}
    local ext = externalMonitor()
    s.scene = Scene().Begin(s.entity, s.mode, { intubated = anat.intubated == true, noMonitor = ext })
    if ctx.done() or s.ended then return end
    if ext then
        s.extMon = pcall(NZA.Monitor.Open, s.target, { compact = true, position = 'tr' })
    end

    local data = {}
    for k, v in pairs(d) do data[k] = v end
    data.locale = NZA.LocaleTable('intubation')
    data.monitor = not ext
    s.open = NZA.UI.Open(APP, data, { focus = true, cursor = true }) ~= false
    if not s.open then
        ctx.abort('error')
        return
    end

    s.stopWatch = NZA.Patient.Watch(s.target, function(snap)
        if snap and s.open and not s.ended then sendVitals(snap) end
    end, { keep = true, initial = true })

    while not ctx.done() and not s.ended do
        if s.phase then
            local ph = s.phase
            s.phase = nil
            Scene().Phase(s.scene, ph.phase, ph)
        end
        if s.result then
            local r = s.result
            s.result = nil
            ctx.finish(r)
            break
        elseif s.aborted then
            ctx.abort('cancel')
            break
        end
        Wait(60)
    end
end

-- easy mode: the core runs a progress bar; walk the props through the phases with it
local EASY_SEQ = { { 0.0, 'preox' }, { 0.28, 'insert' }, { 0.5, 'tube' }, { 0.68, 'cuff' }, { 0.84, 'confirm' } }

local function runEasy(s, ctx)
    s.ctx = ctx
    local d = type(ctx.data) == 'table' and ctx.data or {}
    local anat = type(d.anat) == 'table' and d.anat or {}
    s.scene = Scene().Begin(s.entity, s.mode, { easy = true, intubated = anat.intubated == true })
    if s.mode ~= 'intubate' then return end
    local total = tonumber(cfg().easyTime) or 14
    for _, step in ipairs(EASY_SEQ) do
        while not s.ended and not ctx.done() and ctx.elapsed() < step[1] * total do Wait(100) end
        if s.ended or ctx.done() then return end
        Scene().Phase(s.scene, step[2], {})
    end
end

function I.Start(mode, entity, target)
    mode = mode == 'bvm' and 'bvm' or 'intubate'
    if session then
        toast('error', L('err_busy'))
        return false, 'busy'
    end
    if not target and entity then target = NZA.Target.FromEntity(entity) end
    if type(target) ~= 'table' then return false, 'invalid' end
    entity = entity or NZA.Target.Entity(target)
    if not entity or entity == 0 then return false, 'gone' end

    local s = { mode = mode, entity = entity, target = target }
    session = s
    local anim = sub('anim').kneel
    local ok, res = NZA.Proc.Run(mode, target, {}, function(ctx) run(s, ctx) end, {
        label = L(mode == 'bvm' and 'proc_bvm' or 'proc_intubate'),
        anim = type(anim) == 'table' and anim.dict and { dict = anim.dict, clip = anim.clip, flag = 1 } or nil,
        maxDist = tonumber(cfg().maxDistance) or 3.0,
    })
    if ok and s.scene and type(res) == 'table' then
        Scene().Phase(s.scene, 'done', { placed = res.placed })
        Wait(250)
    end
    endSession(s)
    if session == s then session = nil end
    return ok, res
end

local function startAsync(mode, entity, target)
    CreateThread(function() I.Start(mode, entity, target) end)
end

NZA.Bus.On('proc:started', function(ctx)
    local s = session
    if not s or type(ctx) ~= 'table' or ctx.name ~= s.mode or not ctx.easy then return end
    CreateThread(function()
        local ok, err = pcall(runEasy, s, ctx)
        if not ok then NZA.Warn('intubation easy scene failed: ' .. tostring(err)) end
    end)
end)

-- ════════════════════════════════════════════════════════════════════════
-- NUI
-- ════════════════════════════════════════════════════════════════════════

NZA.UI.On(APP, 'step', function(data, cb)
    local s = session
    if s and not s.ended and type(data) == 'table' and type(data.phase) == 'string' then
        s.phase = { phase = data.phase, placed = data.placed, step = data.step }
    end
    cb({ ok = true })
end)

NZA.UI.On(APP, 'finish', function(data, cb)
    local s = session
    if s and not s.ended and type(data) == 'table' and type(data.result) == 'table' then
        s.result = data.result
        cb({ ok = true })
        return
    end
    cb({ ok = false })
end)

NZA.UI.On(APP, 'abort', function(_, cb)
    local s = session
    if s and not s.ended then s.aborted = true end
    cb({ ok = true })
end)

NZA.Bus.On('ui:closed', function(app)
    local s = session
    if app == APP and s and not s.ended then
        s.open = false
        s.aborted = true
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- TUBE CARE (instant treatments)
-- ════════════════════════════════════════════════════════════════════════

local function treat(action, entity)
    local ok, res = NZA.Treat.Do(action, entity, {})
    return ok, res
end

local function extubate(entity)
    local answer = lib.alertDialog({
        header = L('ext_confirm_title'), content = L('ext_confirm_text'), centered = true, cancel = true,
        labels = { confirm = L('ext_confirm_yes'), cancel = L('ext_confirm_no') },
    })
    if answer ~= 'confirm' then return end
    treat('extubate', entity)
end

-- ════════════════════════════════════════════════════════════════════════
-- REGISTRATIONS
-- ════════════════════════════════════════════════════════════════════════

local ic = sub('interact')
if ic.enabled ~= false then
    local dist = tonumber(ic.distance) or 2.0

    if sub('bvm').enabled ~= false then
        NZA.Interact.Add({
            name = 'nza_airway_bvm', label = L('opt_bvm'), description = L('opt_bvm_desc'), icon = 'lungs', faIcon = 'lungs',
            order = tonumber(ic.orderBvm) or 31, perm = bvmPerm(),
            states = { wounded = true, arrest = true }, self = false, npc = true, player = true, distance = dist,
            canInteract = function(_, _, bag) return session == nil and canBvm(bag) end,
            onSelect = function(entity, target) I.Start('bvm', entity, target) end,
        })
    end

    NZA.Interact.Add({
        name = 'nza_airway_intubate', label = L('opt_intubate'), description = L('opt_intubate_desc'), icon = 'tube', faIcon = 'head-side-mask',
        order = tonumber(ic.orderTube) or 61, perm = perm(),
        states = { wounded = true, arrest = true }, self = false, npc = true, player = true, distance = dist,
        canInteract = function(_, _, bag) return session == nil and canIntubate(bag) end,
        onSelect = function(entity, target) I.Start('intubate', entity, target) end,
    })

    if sub('check').enabled ~= false then
        NZA.Interact.Add({
            name = 'nza_airway_check', label = L('opt_check'), description = L('opt_check_desc'), icon = 'ecg', faIcon = 'wave-square',
            order = (tonumber(ic.orderTube) or 61) + 1, perm = perm(),
            states = { wounded = true, arrest = true, dead = true }, self = false, npc = true, player = true, distance = dist,
            canInteract = function(_, _, bag) return session == nil and type(bag) == 'table' and bag.intub == true end,
            onSelect = function(entity) treat('tube_check', entity) end,
        })
    end

    NZA.Interact.Add({
        name = 'nza_airway_adjust', label = L('opt_adjust'), description = L('opt_adjust_desc'), icon = 'ruler', faIcon = 'ruler-vertical',
        order = (tonumber(ic.orderTube) or 61) + 2, perm = perm(),
        states = { wounded = true, arrest = true }, self = false, npc = true, player = true, distance = dist,
        canInteract = function(_, _, bag) return session == nil and type(bag) == 'table' and bag.intub == true end,
        onSelect = function(entity) treat('tube_adjust', entity) end,
    })

    NZA.Interact.Add({
        name = 'nza_airway_extubate', label = L('opt_extubate'), description = L('opt_extubate_desc'), icon = 'x', faIcon = 'xmark',
        order = (tonumber(ic.orderTube) or 61) + 3, perm = perm(),
        states = { alive = true, wounded = true, arrest = true, dead = true }, self = false, npc = true, player = true, distance = dist,
        canInteract = function(_, _, bag) return session == nil and type(bag) == 'table' and bag.intub == true end,
        onSelect = function(entity) extubate(entity) end,
    })
end

local function snapDown(snap)
    return type(snap) == 'table' and downOk(snap.state, (snap.vitals or {}).avpu)
end
local function airwayCond(inj)
    return type(inj) == 'table' and inj.condition == true and (inj.type == 'airway' or inj.type == 'hypoxia')
end
local function intubatedSnap(snap) return type(snap) == 'table' and snap.devices and snap.devices.intubated == true end

NZA.ExamRoutes = NZA.ExamRoutes or {}
if cfg().examRoute ~= false then
    local kit, bvm = Config.Items and Config.Items.intubation_kit, Config.Items and Config.Items.bvm
    local tubeItems = {}
    if kit then tubeItems[kit] = 1 end
    if bvm and cfg().requireBvm ~= false then tubeItems[bvm] = 1 end

    table.insert(NZA.ExamRoutes, {
        id = 'airway_intubate', label = L('route_intubate'), icon = 'tube', perm = perm(), order = 12,
        types = nil, regions = nil, items = tubeItems,
        available = function(inj, snap)
            local relevant = airwayCond(inj)
                or ((inj.region == 'face' or inj.region == 'neck') and (tonumber(inj.severity) or 0) >= 3 and not inj.condition)
            if not relevant or intubatedSnap(snap) then return false end
            if not snapDown(snap) then return false, L('route_not_down') end
            return true
        end,
        run = function(target) I.Start('intubate', nil, target) end,
    })

    if sub('bvm').enabled ~= false then
        table.insert(NZA.ExamRoutes, {
            id = 'airway_bvm', label = L('route_bvm'), icon = 'lungs', perm = bvmPerm(), order = 11,
            types = { 'airway', 'hypoxia' }, regions = nil, items = bvm and { [bvm] = 1 } or nil,
            available = function(inj, snap)
                if not airwayCond(inj) or type(snap) ~= 'table' then return false end
                local states = sub('bvm').states or { wounded = true, arrest = true }
                if not states[snap.state] then return false, L('route_not_down') end
                if inj.finding and inj.finding.key == 'tube_oesophageal' then return false end
                return true
            end,
            run = function(target) I.Start('bvm', nil, target) end,
        })
    end

    table.insert(NZA.ExamRoutes, {
        id = 'airway_retube', label = L('route_retube'), icon = 'x', perm = perm(), order = 10,
        types = { 'hypoxia' }, regions = nil,
        available = function(inj, snap)
            return type(inj.finding) == 'table' and inj.finding.key == 'tube_oesophageal' and intubatedSnap(snap)
        end,
        run = function(target)
            local ok = NZA.Treat.Do('extubate', target, {})
            if ok then
                Wait(400)
                I.Start('intubate', nil, target)
            end
        end,
    })
end

NZA.RadialItems = NZA.RadialItems or {}
if cfg().radial ~= false then
    if sub('bvm').enabled ~= false then
        table.insert(NZA.RadialItems, {
            id = 'airway_bvm', parent = 'patient', label = L('radial_bvm'), desc = L('radial_bvm_desc'),
            icon = 'lungs', order = tonumber(ic.orderBvm) or 31, perm = bvmPerm(),
            canShow = function() return session == nil and I.Nearest('bvm') ~= nil end,
            onSelect = function()
                CreateThread(function()
                    local ped, t = I.Nearest('bvm')
                    if not ped then toast('error', L('err_nobody')) return end
                    I.Start('bvm', ped, t)
                end)
            end,
        })
    end
    table.insert(NZA.RadialItems, {
        id = 'airway_intubate', parent = 'patient', label = L('radial_intubate'), desc = L('radial_intubate_desc'),
        icon = 'tube', order = tonumber(ic.orderTube) or 61, perm = perm(),
        canShow = function() return session == nil and I.Nearest('intubate') ~= nil end,
        onSelect = function()
            CreateThread(function()
                local ped, t = I.Nearest('intubate')
                if not ped then toast('error', L('err_nobody')) return end
                I.Start('intubate', ped, t)
            end)
        end,
    })
end

-- a usable item was used from the inventory: start on the nearest downed patient
RegisterNetEvent('nza:intubation:use', function(mode)
    mode = mode == 'bvm' and 'bvm' or 'intubate'
    if session then toast('error', L('err_busy')) return end
    local ped, t = I.Nearest(mode, tonumber(cfg().useRange) or 2.5)
    if not ped then toast('error', L('err_nobody')) return end
    startAsync(mode, ped, t)
end)

-- ════════════════════════════════════════════════════════════════════════
-- CLEANUP
-- ════════════════════════════════════════════════════════════════════════

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    local s = session
    session = nil
    if s then
        s.aborted = true
        endSession(s)
    end
end)
