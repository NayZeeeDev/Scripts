--[[
    NAYZEEE AMBULANCE - IV stand (client)                                   NUI app 'ivstand'

    NZA.Blood.OpenStand(target, info?)  - any module (bay F3 hands `info` = bay fittings; beds, surgery,
        field) opens the IV stand panel for a patient: hang saline / blood bags you carry (label, group,
        expiry, compatibility once the patient was typed - mismatch warning), roller clamp, pressure
        infuser (Space squeeze + gauge), live infusion rate, volume in, TXA slow push, take down,
        Type & screen, 'Place an IV first' (field module's IV cannulation when installed, otherwise a
        quick placement), 'Fill blood bag' from the ambulance onboard stock inside the treatment bay.
    The stand is drawn for EVERY client from the patient's 'nzaStand' state bag (server): a tripod
        stand beside the patient with the bags on its hooks (blood bags swap their fill model
        Config.Props.bloodbag_0..100 as they empty); inside the ambulance bay the bags hang on the
        bay's IV hooks (NZA.Transport.Bay.Info().hooks).
    Patient option: nza_blood_stand 'IV stand' (order Config.Blood.Stand.interact.order).
    NZA.ExamRoutes 'transfuse' (bleeding injury + blood volume below Stand.examRoute.belowPct).
    NZA.RadialItems 'blood_stand' (parent 'patient').

    NUI callbacks: ivstand:hang { kind, serial?, slot?, force?, rate } → { ok, result | err, msg }
                   ivstand:rate { id, rate }   ivstand:takedown { id }   ivstand:txa { seconds }
                   ivstand:type   ivstand:iv   ivstand:fill { type }   ivstand:refresh   ivstand:close
    Lua → JS: open { locale, keys, cfg, data, bay }, data (panel data), snap (live patient), result
    Callbacks used: nza:blood:stand:info, nza:blood:stand:fill (+ NZA.Treat 'ivstand:*')
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Blood = NZA.Blood or {}
local B = NZA.Blood
local U = NZA.Util

local APP = 'ivstand'
local HOOKS = { vec3(0.073, 0.0, 1.766), vec3(-0.073, 0.0, 1.766) }

local function sc() return (Config.Blood or {}).Stand or {} end
local function L(key, ...) return NZA.L('blood.' .. key, ...) end
local function toast(msg, kind, title)
    if not msg or msg == '' then return end
    NZA.UI.Toast({ title = title or L('stand_title'), message = msg, type = kind or 'info' })
end
local function errOf(res, fallback)
    if type(res) == 'table' then return res.msg or res.message or fallback end
    if type(res) == 'string' then return res end
    return fallback
end

local stand = nil   -- the open panel

local function bagKeyFor(pct)
    pct = tonumber(pct) or 0
    if pct >= 88 then return 'bloodbag_100' end
    if pct >= 63 then return 'bloodbag_75' end
    if pct >= 38 then return 'bloodbag_50' end
    if pct >= 13 then return 'bloodbag_25' end
    return 'bloodbag_0'
end

-- ════════════════════════════════════════════════════════════════════════
-- PANEL DATA
-- ════════════════════════════════════════════════════════════════════════

local function jsCfg()
    local c = sc()
    return {
        gravity = c.gravity or 32, maxRate = c.maxRate or 160, pressureGain = c.pressureGain or 1.15,
        maxPressure = c.maxPressure or 300, pump = c.pump or 24, leak = c.leak or 5, maxBags = c.maxBags or 2,
        txaPush = (c.txa or {}).push or 10, allowIncompatible = c.allowIncompatible ~= false,
        requireAccess = c.requireAccess ~= false, salineMl = c.salineMl or 500,
        typeScreen = ((Config.Blood or {}).TypeScreen or {}).enabled ~= false,
        bagSize = ((Config.Blood or {}).Bags or {}).bagSize or 500,
    }
end

local function keyCaps()
    local k = sc().keys or {}
    return {
        squeeze = k.squeeze or 'Space', clampDown = k.clampDown or 'KeyQ', clampUp = k.clampUp or 'KeyE',
        txa = k.txa or 'KeyT', hookA = k.hookA or 'Digit1', hookB = k.hookB or 'Digit2',
    }
end

-- what the live medic snapshot may show (the group stays hidden until typed)
local function snapView(snap)
    local meta = snap.meta or {}
    local typed = meta.bloodTyped == true or meta.typed == true
    local d = snap.devices or {}
    local acc = nil
    if type(d.iv) == 'table' then acc = { kind = d.iv.kind or 'iv', site = d.iv.site }
    elseif d.iv == true then acc = { kind = 'iv' }
    elseif d.port then acc = { kind = 'port' } end
    local react = snap.conditions and snap.conditions.reaction or nil
    local infs = {}
    for _, inf in ipairs(snap.infusions or {}) do
        if inf.kind == 'saline' or inf.kind == 'blood' or inf.kind == 'plasma' then
            local bag = type(inf.bag) == 'table' and inf.bag or nil
            infs[#infs + 1] = {
                id = inf.id, kind = inf.kind, ml = inf.ml, left = inf.left, rate = inf.rate, paused = inf.paused and true or nil,
                bag = bag and { type = bag.type or bag.bloodType, serial = bag.serial, donor = bag.donor, expires = bag.expires, created = bag.created } or nil,
                incompatible = (typed or react ~= nil) and inf.incompatible or nil,
            }
        end
    end
    local v = snap.vitals or {}
    return {
        typed = typed, bloodType = typed and snap.bloodType or nil, state = snap.state, name = snap.name,
        access = acc, bloodPct = snap.bloodPct, bleed = snap.bleedTotal, fluid = snap.fluid,
        given = snap.given, infusions = infs,
        vitals = { hr = v.hr, sys = v.sys, dia = v.dia, map = v.map, spo2 = v.spo2, temp = v.temp or snap.temp, rhythm = v.rhythm },
        reaction = react and { stage = react.stage, ml = react.ml } or nil,
    }
end

-- ════════════════════════════════════════════════════════════════════════
-- OPEN / CLOSE
-- ════════════════════════════════════════════════════════════════════════

local function placement(ent)
    local c = GetEntityCoords(ent)
    local pl = sc().placement or {}
    local side, along = tonumber(pl.side) or 0.62, tonumber(pl.along) or 0.55
    -- put the stand on the side of the patient away from the medic, near the head
    local me = GetEntityCoords(PlayerPedId())
    local h = GetEntityHeading(ent)
    local r = math.rad(h)
    local fx, fy = -math.sin(r), math.cos(r)       -- ped forward
    local rx, ry = math.cos(r), math.sin(r)        -- ped right
    local toMe = (me.x - c.x) * rx + (me.y - c.y) * ry
    if toMe > 0 then side = -side end
    local x, y = c.x + rx * side + fx * along, c.y + ry * side + fy * along
    local found, gz = GetGroundZFor_3dCoord(x, y, c.z + 1.0, false)
    local z = found and gz or (c.z - 0.95)
    local heading = math.deg(math.atan(c.y - y, c.x - x)) - 90.0
    return vector3(x, y, z), heading
end

local function cleanup(s, why)
    if not s or s.closed then return end
    s.closed = true
    if s.stop then pcall(s.stop) end
    if s.cam then NZA.Cam.Stop(400) end
    if NZA.UI.IsOpen(APP) then NZA.UI.Close(APP) end
    if stand == s then stand = nil end
    if why == 'far' then toast(L('stand_closed_far'), 'info') end
end

local function refresh(s)
    if not s or s.closed then return end
    local res = lib.callback.await('nza:blood:stand:info', false, s.target)
    if s.closed then return end
    if type(res) == 'table' and res.ok then
        s.data = res.data
        NZA.UI.Send(APP, 'data', res.data)
    end
end

function B.CloseStand()
    if stand then cleanup(stand) end
end

function B.StandOpen()
    return stand ~= nil
end

function B.OpenStand(target, info)
    if type(target) == 'number' then target = NZA.Target.FromEntity(target) end
    if type(target) ~= 'table' then return false end
    if stand then
        if NZA.Target.Same(stand.target, target) then return true end
        cleanup(stand)
    end
    if not NZA.Perm(sc().perm or 'iv') then
        toast(L('err_no_perm'), 'error')
        return false
    end
    local ent = NZA.Target.Entity(target)
    if ent == 0 then return false end
    local res = lib.callback.await('nza:blood:stand:info', false, target)
    if type(res) ~= 'table' or not res.ok then
        toast(errOf(res, L('err_failed')), 'error')
        return false
    end
    local bayInfo = info
    if not bayInfo and NZA.Transport and NZA.Transport.Bay and NZA.Transport.Bay.Info then bayInfo = NZA.Transport.Bay.Info() end
    local s = { target = target, ent = ent, bay = bayInfo and bayInfo.bay ~= false and bayInfo.veh ~= nil, info = bayInfo, data = res.data }
    stand = s
    if not s.bay then
        s.at, s.h = placement(ent)
        local cam = sc().camera or {}
        if cam.enabled ~= false then
            local focus = vector3((s.at.x + GetEntityCoords(ent).x) / 2, (s.at.y + GetEntityCoords(ent).y) / 2, s.at.z + 1.05)
            NZA.Cam.Orbit(focus, {
                dist = cam.dist or 2.3, height = cam.height or 0.35, pitch = cam.pitch or 14.0, fov = cam.fov or 46.0,
                minDist = 1.0, maxDist = 4.0,
            })
            s.cam = true
        end
    end
    NZA.UI.Open(APP, {
        locale = B.Locale(), keys = keyCaps(), cfg = jsCfg(), data = res.data, bay = s.bay == true,
    }, { focus = true, cursor = true })
    s.stop = NZA.Patient.Watch(target, function(snap, reason)
        if stand ~= s then return end
        if not snap then
            cleanup(s, reason)
            return
        end
        NZA.UI.Send(APP, 'snap', snapView(snap))
    end, { maxDist = (tonumber(sc().range) or 6.0) + 1.0, keep = s.bay == true })
    CreateThread(function()
        local range = tonumber(sc().range) or 6.0
        while stand == s and not s.closed do
            Wait(500)
            local e = NZA.Target.Entity(target)
            local ped = PlayerPedId()
            if e == 0 then cleanup(s, 'gone') break end
            if not s.bay and #(GetEntityCoords(ped) - GetEntityCoords(e)) > range then cleanup(s, 'far') break end
            if NZA.Self and NZA.Self.IsDown and NZA.Self.IsDown() then cleanup(s, 'down') break end
        end
    end)
    return true
end

local function quickAnim()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return end
    CreateThread(function()
        local ok = pcall(lib.requestAnimDict, 'mp_common', 1500)
        if not ok then return end
        TaskPlayAnim(ped, 'mp_common', 'givetake1_a', 8.0, -8.0, 1400, 48, 0.0, false, false, false)
        RemoveAnimDict('mp_common')
    end)
end

-- ════════════════════════════════════════════════════════════════════════
-- NUI CALLBACKS
-- ════════════════════════════════════════════════════════════════════════

local function treat(action, payload, msgOk)
    local s = stand
    if not s then return { ok = false, msg = L('err_failed') } end
    local ok, res = NZA.Treat.Do(action, s.target, payload or {}, { silent = true })
    if not ok then
        return { ok = false, err = type(res) == 'table' and res.err or nil, msg = errOf(res, L('err_failed')) }
    end
    if msgOk ~= false and type(res) == 'table' and res.msg then toast(res.msg, 'success') end
    return { ok = true, result = res }
end

NZA.UI.On(APP, 'hang', function(data, cb)
    local s = stand
    if not s or type(data) ~= 'table' then return cb({ ok = false }) end
    local payload = {
        kind = data.kind, serial = data.serial, slot = data.slot, type = data.type, force = data.force == true,
        rate = tonumber(data.rate),
    }
    if s.at then payload.at = { x = s.at.x, y = s.at.y, z = s.at.z } payload.h = s.h end
    local r = treat('ivstand:hang', payload)
    cb(r)
    if r.ok then
        quickAnim()
        refresh(s)
    end
end)

NZA.UI.On(APP, 'rate', function(data, cb)
    if type(data) ~= 'table' then return cb({ ok = false }) end
    cb(treat('ivstand:rate', { id = data.id, rate = tonumber(data.rate) }, false))
end)

NZA.UI.On(APP, 'takedown', function(data, cb)
    local s = stand
    if type(data) ~= 'table' then return cb({ ok = false }) end
    local r = treat('ivstand:takedown', { id = data.id })
    cb(r)
    if r.ok then
        quickAnim()
        refresh(s)
    end
end)

NZA.UI.On(APP, 'txa', function(data, cb)
    local s = stand
    local r = treat('ivstand:txa', { seconds = type(data) == 'table' and tonumber(data.seconds) or 0 })
    cb(r)
    if r.ok then refresh(s) end
end)

NZA.UI.On(APP, 'type', function(_, cb)
    local s = stand
    if not s then return cb({ ok = false }) end
    local bt = B.TypeScreen(s.ent, s.target)
    cb({ ok = bt ~= nil, bloodType = bt })
    if bt then refresh(s) end
end)

NZA.UI.On(APP, 'fill', function(data, cb)
    local s = stand
    local res = lib.callback.await('nza:blood:stand:fill', false, type(data) == 'table' and data.type or nil)
    if type(res) ~= 'table' then res = { ok = false, msg = L('err_failed') } end
    toast(res.msg, res.ok and 'success' or 'error')
    cb(res)
    if res.ok then refresh(s) end
end)

NZA.UI.On(APP, 'refresh', function(_, cb)
    cb({ ok = true })
    refresh(stand)
end)

NZA.UI.On(APP, 'close', function(_, cb)
    cb({ ok = true })
    if stand then cleanup(stand) end
end)

-- ── 'Place an IV first' ────────────────────────────────────────────────

local function hasAccess(target)
    local st = NZA.Target.State(target)
    return type(st) == 'table' and st.iv == true
end

local function fallbackIV(s)
    local pi = sc().placeIv or {}
    local ped = PlayerPedId()
    local lying = false
    local st = NZA.Target.State(s.target)
    if type(st) == 'table' and st.st and st.st ~= 'alive' then lying = true end
    local done = lib.progressBar({
        duration = math.floor((tonumber(pi.seconds) or 8) * 1000), label = L('iv_progress'),
        useWhileDead = false, canCancel = true, disable = { move = true, car = true, combat = true },
        anim = lying and { dict = 'amb@medic@standing@tendtodead@idle_a', clip = 'idle_a', flag = 1 }
            or { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 49 },
    })
    ClearPedSecondaryTask(ped)
    if not done then return false end
    local ok, res = NZA.Treat.Do('ivstand:access', s.target, {}, { silent = true })
    if not ok then
        toast(errOf(res, L('err_failed')), 'error')
        return false
    end
    toast(type(res) == 'table' and res.msg or L('ok_access'), 'success')
    return true
end

NZA.UI.On(APP, 'iv', function(_, cb)
    local s = stand
    if not s then return cb({ ok = false }) end
    cb({ ok = true })
    local pi = sc().placeIv or {}
    local opt = pi.interact and NZA.Interact.Get and NZA.Interact.Get(pi.interact) or nil
    if opt and type(opt.onSelect) == 'function' then
        -- hand over to the field module's IV cannulation, then come back to the stand
        local target, info = s.target, s.info
        cleanup(s)
        CreateThread(function()
            local ent = NZA.Target.Entity(target)
            local okSel, err = pcall(opt.onSelect, ent, target)
            if not okSel then NZA.Warn('blood: IV hand-over failed: ' .. tostring(err)) end
            local function busy() return NZA.Proc.Active and NZA.Proc.Active() ~= nil end
            -- wait for the cannulation to start (onSelect may also have run it to the end already)
            local t0 = GetGameTimer()
            while GetGameTimer() - t0 < 4000 and not busy() and not hasAccess(target) do Wait(200) end
            local deadline = GetGameTimer() + 180000
            while busy() and GetGameTimer() < deadline do Wait(300) end
            Wait(700)   -- state bag replication
            if hasAccess(target) then B.OpenStand(target, info) end
        end)
        return
    end
    if pi.fallback == false then
        toast(L('err_no_access'), 'error')
        return
    end
    CreateThread(function()
        if fallbackIV(s) then refresh(s) end
    end)
end)

-- ════════════════════════════════════════════════════════════════════════
-- WORLD: draw every stand from the 'nzaStand' state bags
-- ════════════════════════════════════════════════════════════════════════

local rendered = {}   -- [key] = { group, sig, stand, bags = { [id] = { ent, model, hook } } }

local function clearOne(key)
    local r = rendered[key]
    if not r then return end
    NZA.Props.Clear(r.group)
    rendered[key] = nil
end

local function spawnBag(r, mode, model, hook)
    hook = tonumber(hook) or 1
    if mode == 'bay' then
        local h = r.hooks and r.hooks[hook] or (r.hooks and r.hooks[1])
        if not h then return 0 end
        return NZA.Props.Spawn(Config.Props[model] or model, vector4(h.x, h.y, h.z, r.heading or 0.0),
            { group = r.group, collision = false, fallbackKey = model })
    end
    if not r.stand or r.stand == 0 or not DoesEntityExist(r.stand) then return 0 end
    return NZA.Props.Spawn(Config.Props[model] or model, {
        attach = { entity = r.stand, pos = HOOKS[hook] or HOOKS[1], rot = vec3(0.0, 0.0, 0.0) },
    }, { group = r.group, fallbackKey = model })
end

local function renderOne(key, v)
    local r = rendered[key]
    if not r then
        r = { group = 'blood_stand_' .. key, bags = {} }
        rendered[key] = r
    end
    local mode, sig
    if v.bay then
        local bi = NZA.Transport and NZA.Transport.Bay and NZA.Transport.Bay.Info and NZA.Transport.Bay.Info() or nil
        if not bi or tonumber(bi.veh) ~= tonumber(v.bay) or not bi.hooks or not bi.hooks[1] then
            clearOne(key)
            return
        end
        mode, sig = 'bay', 'bay:' .. tostring(v.bay)
        r.hooks = bi.hooks
        r.heading = bi.cot and bi.cot.w or 0.0
    elseif type(v.at) == 'table' and v.at.x then
        mode = 'stand'
        sig = ('stand:%.2f:%.2f:%.2f:%.0f'):format(v.at.x, v.at.y, v.at.z, tonumber(v.h) or 0)
    else
        clearOne(key)
        return
    end
    if r.sig ~= sig then
        NZA.Props.Clear(r.group)
        r.bags, r.stand, r.sig = {}, nil, sig
        if mode == 'stand' then
            local ent = NZA.Props.Spawn(Config.Props.ivstand, vector4(v.at.x, v.at.y, v.at.z, tonumber(v.h) or 0.0),
                { group = r.group, ground = true, collision = false, fallbackKey = 'ivstand' })
            r.stand = ent ~= 0 and ent or nil
        end
    end
    local want = {}
    for _, b in ipairs(v.b or {}) do
        if b.id then
            local model = b.k == 'blood' and bagKeyFor(b.done and 0 or b.f) or 'ivbag_saline'
            want[b.id] = true
            local cur = r.bags[b.id]
            if not cur or cur.model ~= model or cur.hook ~= b.hook or not DoesEntityExist(cur.ent or 0) then
                if cur and cur.ent then NZA.Props.Delete(cur.ent) end
                local ent = spawnBag(r, mode, model, b.hook)
                r.bags[b.id] = { ent = ent, model = model, hook = b.hook }
            end
        end
    end
    for id, cur in pairs(r.bags) do
        if not want[id] then
            if cur.ent then NZA.Props.Delete(cur.ent) end
            r.bags[id] = nil
        end
    end
end

CreateThread(function()
    while true do
        local found = {}
        local me = GetEntityCoords(PlayerPedId())
        for _, pl in ipairs(GetActivePlayers()) do
            local ped = GetPlayerPed(pl)
            if ped ~= 0 and #(GetEntityCoords(ped) - me) < 45.0 then
                local sid = GetPlayerServerId(pl)
                local v = Player(sid).state.nzaStand
                if type(v) == 'table' then found['p' .. sid] = v end
            end
        end
        for _, ped in ipairs(GetGamePool('CPed')) do
            if not IsPedAPlayer(ped) and NetworkGetEntityIsNetworked(ped) and #(GetEntityCoords(ped) - me) < 45.0 then
                local v = Entity(ped).state.nzaStand
                if type(v) == 'table' then found['n' .. NetworkGetNetworkIdFromEntity(ped)] = v end
            end
        end
        for key, v in pairs(found) do
            local ok, err = pcall(renderOne, key, v)
            if not ok then NZA.Warn('blood: stand render failed: ' .. tostring(err)) end
        end
        for key in pairs(rendered) do
            if not found[key] then clearOne(key) end
        end
        Wait(next(found) and 900 or 2000)
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- REGISTRIES
-- ════════════════════════════════════════════════════════════════════════

local ic = sc().interact or {}
if ic.enabled ~= false then
    NZA.Interact.Add({
        name = 'nza_blood_stand', label = L('opt_stand'), icon = ic.icon or 'iv', order = tonumber(ic.order) or 45,
        perm = sc().perm or 'iv',
        states = { alive = true, wounded = true, arrest = true },
        npc = true, player = true, self = false, distance = tonumber(ic.distance) or 2.4,
        canInteract = function() return stand == nil end,
        onSelect = function(_, target) B.OpenStand(target) end,
    })
end

local function nearestPatient(range)
    local me = PlayerPedId()
    local mc = GetEntityCoords(me)
    local best, bestT, bd = nil, nil, range
    local function consider(ped)
        if ped == me or ped == 0 then return end
        local d = #(GetEntityCoords(ped) - mc)
        if d >= bd then return end
        local st = NZA.Target.State(ped)
        if type(st) ~= 'table' or st.st == 'dead' then return end
        if st.st == 'alive' and not st.iv and (tonumber(st.bleed) or 0) < 1 then return end
        local t = NZA.Target.FromEntity(ped)
        if t then best, bestT, bd = ped, t, d end
    end
    for _, pl in ipairs(GetActivePlayers()) do consider(GetPlayerPed(pl)) end
    for _, ped in ipairs(GetGamePool('CPed')) do
        if not IsPedAPlayer(ped) then consider(ped) end
    end
    return best, bestT
end

if sc().radial ~= false then
    NZA.RadialItems = NZA.RadialItems or {}
    table.insert(NZA.RadialItems, {
        id = 'blood_stand', parent = 'patient', label = L('opt_stand'), icon = 'iv', order = 46, perm = sc().perm or 'iv',
        canShow = function()
            if stand then return false end
            local ped = nearestPatient(3.0)
            return ped ~= nil
        end,
        onSelect = function()
            CreateThread(function()
                local _, t = nearestPatient(3.0)
                if not t then return toast(L('err_no_patient'), 'error') end
                B.OpenStand(t)
            end)
        end,
    })
end

local er = sc().examRoute or {}
if er.enabled ~= false then
    local BLEED_TYPES = { gunshot = true, shrapnel = true, stab = true, laceration = true, internal = true, fracture = true, burn = true }
    NZA.ExamRoutes = NZA.ExamRoutes or {}
    table.insert(NZA.ExamRoutes, {
        id = 'transfuse', label = L('route_transfuse'), icon = 'bloodbag', perm = sc().perm or 'iv', order = 30,
        types = { 'gunshot', 'shrapnel', 'stab', 'laceration', 'internal', 'fracture', 'burn' },
        available = function(inj, snap)
            if type(snap) ~= 'table' or type(inj) ~= 'table' or inj.condition then return false end
            local pct = tonumber(snap.bloodPct) or 100
            if pct >= (tonumber(er.belowPct) or 88) then return false end
            -- one button only: on the worst bleeding injury (snapshot injuries are sorted by severity)
            local first = nil
            for _, i in ipairs(snap.injuries or {}) do
                if BLEED_TYPES[i.type] then first = i break end
            end
            if not first or first.id ~= inj.id then return false end
            local blood = Config.Items.blood_bag and Bridge.Inv.Count(Config.Items.blood_bag) or 0
            local saline = Config.Items.saline_bag and Bridge.Inv.Count(Config.Items.saline_bag) or 0
            if (blood or 0) + (saline or 0) <= 0 then return false, L('route_need_fluids') end
            return true
        end,
        run = function(target) B.OpenStand(target) end,
    })
end

-- ════════════════════════════════════════════════════════════════════════
-- CLEANUP
-- ════════════════════════════════════════════════════════════════════════

NZA.Bus.On('self:state', function(new)
    if new ~= 'alive' and stand then cleanup(stand, 'down') end
end)

NZA.Bus.On('bay:left', function()
    if stand and stand.bay then cleanup(stand) end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if stand and stand.cam then NZA.Cam.Stop(0) end
end)
