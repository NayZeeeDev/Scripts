--[[
    NAYZEEE AMBULANCE - Radiology (client): X-ray room, films, lightbox reading

    Hospital points (NZA.Points.RegisterType, ARCHITECTURE §8)
        'xray'      Config.Props.xray_table - target "Take X-ray" opens the console (choose the view)
                    for the patient lying on the table (the transport module places patients on it)
        'lightbox'  Config.Props.lightbox   - target "Read X-ray film" (pick one of your films)
    Patient options (NZA.Interact, ARCHITECTURE §11) - patient lying on an X-ray table:
        nza_xray_<view>  'X-ray: Head' ... 'X-ray: Right leg'   order 60-67, perm Config.Xray.Take.perm
        nza_xray_any     'X-ray…' (easy mode, patient anywhere)  order 60
        nza_xray_off     'Help patient off the table'           order 10 (the transport module's own API is
                         used when it has one: NZA.Transport.HelpOff(entity, target))
    Taking a film: NZA.Proc 'xray' - the radiographer steps back, holds Space to expose (breath hold for
        chest / abdomen), beep + flash, the film comes out of the processor → Config.Items.xray_film.
    Reading: use the film item (server event nza:xray:read) or the lightbox target → NUI app 'xray' mode
        'read' (pin the breaks on the AP and lateral film) or 'view' (no permission: look only).
    Radial (NZA.RadialItems): 'Take X-ray' (parent 'patient', patient on a table nearby),
        'Read X-ray film' (root, near a lightbox).

    NUI app 'xray' (shared with client/modules/xray_ortho.lua):
        Lua → open { mode = 'choose'|'expose'|'read'|'view'|'reduce'|'cast', ... }, filmReady, result, error
        JS  → xray:choose {view}  xray:expose {breath}  xray:finish {result}  xray:abort  xray:close
    Callbacks used: nza:xray:films, nza:xray:open, nza:xray:read:finish, nza:xray:offTable (+ core proc)
    Net events: nza:xray:read (payload) S→C, nza:xray:standUp S→C, nza:xray:read:cancel C→S
    Lua API (runtime, also used by xray_ortho.lua): NZA.Xray.Take(entity, target, view),
        NZA.Xray.Console(entity, target), NZA.Xray.Read(payload), NZA.Xray.ReadAt(point),
        NZA.Xray.OffTable(entity, target), NZA.Xray.TablePoint(entity) → point|nil,
        NZA.Xray.NearLightbox(range) → point, entity, NZA.Xray.RunApp(o), NZA.Xray.Busy(),
        NZA.Xray.Toast(key, kind, ...), NZA.Xray.Err(reason), NZA.Xray.EntityOf(snapOrTarget)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Xray = NZA.Xray or {}
local X = NZA.Xray
local U = NZA.Util

local APP = 'xray'
local VIEWS = { 'head', 'neck', 'chest', 'abdomen', 'l_arm', 'r_arm', 'l_leg', 'r_leg' }

local busy = nil          -- 'take' | 'read' | 'reduce' | 'cast' | 'choose'
local session = nil       -- the live NUI session (fields set by the NUI callbacks)

-- ════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════════════

local function cfg(section)
    local c = Config.Xray or {}
    if section then return c[section] or {} end
    return c
end

local function L(key, ...)
    return NZA.L('xray.' .. key, ...)
end

function X.Toast(key, kind, ...)
    NZA.UI.Toast({ title = L('title'), message = L(key, ...), type = kind or 'info', icon = 'xray' })
end

-- server / core error code → text
function X.Err(reason)
    if type(reason) == 'table' then
        if type(reason.msg) == 'string' and reason.msg ~= '' then return reason.msg end
        reason = reason.err or reason.error
    end
    reason = tostring(reason or 'generic')
    local key = 'xray.err_' .. reason
    local s = NZA.L(key)
    if s ~= key then return s end
    key = 'core_client.err.' .. reason
    s = NZA.L(key)
    if s ~= key then return s end
    return L('err_generic')
end

function X.Busy() return busy end
function X.SetBusy(v) busy = v end
function X.Session() return session end

function X.Locale()
    return NZA.LocaleTable('xray')
end

local function keys()
    return cfg().keys or {}
end

function X.EntityOf(t)
    if type(t) ~= 'table' then return 0 end
    if t.kind == 'npc' and t.net then
        if NetworkDoesNetworkIdExist(t.net) then return NetworkGetEntityFromNetworkId(t.net) end
        return 0
    end
    local sid = t.sid or t.src
    if t.kind == 'player' and sid then
        local pl = GetPlayerFromServerId(sid)
        if pl and pl ~= -1 then return GetPlayerPed(pl) end
    end
    return 0
end

local function pointCoords(pt)
    local c = pt and pt.coords
    if not c then return nil end
    return U.vec(c)
end

-- the X-ray table point a patient entity lies on (or nil)
function X.TablePoint(ent)
    if not ent or ent == 0 or not DoesEntityExist(ent) then return nil end
    -- the transport module tells where the patient lies ('nzaTr' bag: m = 'bed', b = point id, bt = type)
    local T = NZA.Transport
    if T and type(T.Bag) == 'function' then
        local ok, bag = pcall(T.Bag, ent)
        if ok and type(bag) == 'table' and bag.m and bag.m ~= 'free' then
            if bag.m == 'bed' and bag.bt == 'xray' and bag.b then return NZA.Points.Get(bag.b) end
            return nil
        end
    end
    local c = GetEntityCoords(ent)
    local r = tonumber(cfg('Take').tableRadius) or 1.6
    local best, bestD = nil, nil
    for _, pt in pairs(NZA.Points.All('xray') or {}) do
        local pc = pointCoords(pt)
        if pc then
            local dx, dy = c.x - pc.x, c.y - pc.y
            local d = math.sqrt(dx * dx + dy * dy)
            if d <= r and math.abs(c.z - pc.z) <= 2.5 and (not bestD or d < bestD) then best, bestD = pt, d end
        end
    end
    return best
end

-- nearest lightbox point to the medic → point, prop entity, distance
function X.NearLightbox(range)
    local me = GetEntityCoords(PlayerPedId())
    local pt, d = NZA.Points.Nearest('lightbox', me, range or ((tonumber(cfg('Read').lightboxDistance) or 3.0) + 0.5))
    if not pt then return nil, 0, nil end
    return pt, NZA.Points.Entity(pt.id) or 0, d
end

-- the patient ped lying on an X-ray table point
local function patientOnPoint(point)
    local pc = pointCoords(point)
    if not pc then return nil end
    local r = tonumber(cfg('Take').tableRadius) or 1.6
    local me = PlayerPedId()
    local best, bestD, bestT = nil, nil, nil
    local function consider(ped)
        if ped == me or not DoesEntityExist(ped) then return end
        local c = GetEntityCoords(ped)
        local dx, dy = c.x - pc.x, c.y - pc.y
        local d = math.sqrt(dx * dx + dy * dy)
        if d <= r and math.abs(c.z - pc.z) <= 2.5 and (not bestD or d < bestD) then
            local t = NZA.Target.FromEntity(ped)
            if t then best, bestD, bestT = ped, d, t end
        end
    end
    for _, pl in ipairs(GetActivePlayers()) do consider(GetPlayerPed(pl)) end
    for _, ped in ipairs(GetGamePool('CPed')) do
        if not IsPedAPlayer(ped) then consider(ped) end
    end
    return best, bestT
end
X.PatientOnPoint = patientOnPoint

local function takePerm() return cfg('Take').perm or 'xray' end

local function easyAnywhere()
    return cfg('Take').easyAnywhere ~= false and NZA.Easy(takePerm())
end

-- ════════════════════════════════════════════════════════════════════════
-- NUI SESSION (one at a time, shared by every mode of the 'xray' app)
--   o = { name (proc), mode, entity, target, payload, label, silent, cam = fn(s), anim = fn(s),
--         data = fn(ctx) → extra NUI data, onOutcome = fn(s, outcome), keepOpen = seconds }
-- ════════════════════════════════════════════════════════════════════════

local function stopAnim()
    local me = PlayerPedId()
    if NZA.Anim and NZA.Anim.Stop then pcall(NZA.Anim.Stop, me) else ClearPedTasks(me) end
end

local function endSession(s)
    if not s or s.cleaned then return end
    s.cleaned = true
    if session == s then session = nil end
    if NZA.UI.IsOpen(APP) then NZA.UI.Close(APP) end
    if s.camOn and NZA.Cam and NZA.Cam.Stop then NZA.Cam.Stop(500) end
    if s.animOn then stopAnim() end
    if s.teardown then pcall(s.teardown, s) end
end
X.EndSession = endSession

local function waitFor(s, check, timeout)
    local deadline = timeout and (GetGameTimer() + timeout) or nil
    while not check() do
        Wait(50)
        if s.ended or s.closed or s.abortReq then return false end
        if NZA.Self and NZA.Self.IsDown and NZA.Self.IsDown() then return false end
        if deadline and GetGameTimer() > deadline then return false end
    end
    return true
end
X.WaitFor = waitFor

function X.RunApp(o)
    if busy then
        X.Toast('err_busy', 'error')
        return false
    end
    busy = o.mode
    local outcomeOut, okOut = nil, false
    local ok, err = pcall(function()
        okOut, outcomeOut = NZA.Proc.Run(o.name, o.target, o.payload or {}, function(ctx)
            local s = { mode = o.mode, ctx = ctx, entity = o.entity, target = o.target, o = o }
            session = s
            ctx.onEnd(function(outcome)
                s.ended = true
                if not outcome then endSession(s) end
            end)
            local me = PlayerPedId()
            if o.entity and o.entity ~= 0 then
                TaskTurnPedToFaceEntity(me, o.entity, 600)
                Wait(400)
            end
            if s.ended then return end
            if o.anim then s.animOn = true pcall(o.anim, s) end
            if o.cam then s.camOn = true pcall(o.cam, s) end
            local data = {}
            for k, v in pairs(ctx.data or {}) do data[k] = v end
            if o.data then for k, v in pairs(o.data(ctx) or {}) do data[k] = v end end
            data.mode = o.mode
            data.keys = keys()
            data.locale = X.Locale()
            NZA.UI.Open(APP, data, { focus = true, cursor = true })

            local got = waitFor(s, function() return s.result ~= nil end)
            if s.ended then return end
            if not got or not s.result then
                ctx.abort(s.closed and 'cancel' or 'silent')
                endSession(s)
                return
            end
            local fine, outcome = ctx.finish(s.result)
            if not fine then
                endSession(s)
                return
            end
            if o.onOutcome then pcall(o.onOutcome, s, outcome) end
            NZA.UI.Send(APP, 'result', outcome or {})
            local hold = (o.keepOpen or 45) * 1000
            local deadline = GetGameTimer() + hold
            while not s.closed and GetGameTimer() < deadline do
                Wait(100)
                if NZA.Self and NZA.Self.IsDown and NZA.Self.IsDown() then break end
            end
            endSession(s)
        end, { label = o.label, silent = o.silent })
    end)
    if not ok then NZA.Warn(('xray %s failed: %s'):format(tostring(o.name), tostring(err))) end
    if session and session.o == o then endSession(session) end
    busy = nil
    return okOut, outcomeOut
end

-- NUI callbacks (every mode)
NZA.UI.On(APP, 'choose', function(data, cb)
    cb({ ok = true })
    local s = session
    if s and s.mode == 'choose' and type(data) == 'table' and type(data.view) == 'string' then s.choice = data.view end
end)

NZA.UI.On(APP, 'expose', function(data, cb)
    cb({ ok = true })
    local s = session
    if s and s.mode == 'expose' and not s.result then
        s.breath = type(data) == 'table' and data.breath == true
        s.result = { score = 100, breath = s.breath }
        X.Flash(s.entity)
    end
end)

NZA.UI.On(APP, 'finish', function(data, cb)
    cb({ ok = true })
    local s = session
    if s and not s.result and type(data) == 'table' then s.result = data end
end)

NZA.UI.On(APP, 'abort', function(_, cb)
    cb({ ok = true })
    local s = session
    if s then s.abortReq = true end
end)

NZA.UI.On(APP, 'close', function(_, cb)
    cb({ ok = true })
    local s = session
    if s then s.closed = true end
end)

-- ════════════════════════════════════════════════════════════════════════
-- TAKING AN X-RAY
-- ════════════════════════════════════════════════════════════════════════

function X.Flash(entity)
    local fc = cfg('Take').flash or {}
    local ms = tonumber(fc.ms) or 140
    local range = tonumber(fc.range) or 4.0
    local intensity = tonumber(fc.intensity) or 12.0
    CreateThread(function()
        local untilT = GetGameTimer() + ms
        while GetGameTimer() < untilT do
            local c = (entity and entity ~= 0 and DoesEntityExist(entity)) and GetEntityCoords(entity) or GetEntityCoords(PlayerPedId())
            DrawLightWithRange(c.x, c.y, c.z + 1.6, 235, 245, 255, range, intensity)
            Wait(0)
        end
    end)
end

local function stepBack(entity, metres)
    metres = tonumber(metres) or 0
    if metres <= 0 or not entity or entity == 0 then return end
    local me = PlayerPedId()
    local a, b = GetEntityCoords(entity), GetEntityCoords(me)
    local dir = vector3(b.x - a.x, b.y - a.y, 0.0)
    local len = #dir
    if len < 0.05 then dir = -GetEntityForwardVector(me) len = 1.0 end
    dir = dir / len
    local dest = vector3(a.x, a.y, b.z) + dir * (len + metres * 0.6)
    local heading = GetHeadingFromVector_2d(a.x - dest.x, a.y - dest.y)
    TaskGoStraightToCoord(me, dest.x, dest.y, dest.z, 1.0, 4000, heading, 0.2)
    local deadline = GetGameTimer() + 3500
    while GetGameTimer() < deadline and #(GetEntityCoords(me) - dest) > 0.35 do Wait(100) end
    TaskTurnPedToFaceEntity(me, entity, 700)
end

function X.Take(entity, target, view)
    if type(target) ~= 'table' then target = NZA.Target.FromEntity(entity) end
    if not target then return false end
    local viewLabel = L('view_' .. view)
    local ok, outcome = X.RunApp({
        name = 'xray', mode = 'expose', entity = entity, target = target, payload = { view = view },
        label = L('take_title'), silent = true, keepOpen = 6,
        anim = function(s)
            local d = s.ctx.data or {}
            stepBack(entity, d.stepBack)
            s.animOn = false
        end,
        cam = function(s)
            if cfg('Take').camera == false then s.camOn = false return end
            NZA.Cam.Orbit(entity, { dist = 3.0, pitch = 34, height = 0.1, fov = 48, hideHud = true, minDist = 1.6, maxDist = 5.0 })
        end,
        data = function()
            return { view = view, viewLabel = viewLabel }
        end,
        onOutcome = function(_, out)
            if type(out) == 'table' and out.film then NZA.UI.Send(APP, 'filmReady', out.film) end
        end,
    })
    if ok and type(outcome) == 'table' then
        NZA.UI.Toast({ title = L('take_title'), message = outcome.msg or L('take_done', '?', viewLabel),
            type = outcome.failed and 'error' or 'success', icon = 'xray', duration = 6500 })
        if outcome.easy then X.Flash(entity) end
    elseif not ok and outcome and outcome ~= 'silent' and outcome ~= 'cancel' then
        NZA.UI.Toast({ title = L('take_title'), message = X.Err(outcome), type = 'error', icon = 'xray' })
    end
    return ok
end

-- console: choose which view to take (table target, radial, easy-mode option)
function X.Console(entity, target)
    if busy then
        X.Toast('err_busy', 'error')
        return
    end
    if not entity or entity == 0 then
        X.Toast('err_no_patient_table', 'error')
        return
    end
    target = target or NZA.Target.FromEntity(entity)
    if not target then return end
    busy = 'choose'
    local s = { mode = 'choose', entity = entity, target = target }
    session = s
    -- suggest the views with injuries (what the patient complains about)
    local suggest = {}
    local okSnap, snap = pcall(NZA.Patient.Get, target)
    if okSnap and type(snap) == 'table' then
        for _, inj in ipairs(snap.injuries or {}) do
            local R = NZA.Const.Region[inj.region or '']
            if R and R.xray then suggest[R.xray] = math.max(suggest[R.xray] or 0, tonumber(inj.severity) or 1) end
        end
    end
    local views = {}
    for _, v in ipairs(VIEWS) do views[#views + 1] = { id = v, label = L('view_' .. v), sev = suggest[v] } end
    local name = okSnap and type(snap) == 'table' and snap.name or ''
    NZA.UI.Open(APP, { mode = 'choose', views = views, name = name, keys = keys(), locale = X.Locale() }, { focus = true, cursor = true })
    waitFor(s, function() return s.choice ~= nil end, 120000)
    local choice = s.choice
    s.cleaned = true
    session = nil
    busy = nil
    -- the exposure re-opens the console (or runs the easy-mode progress bar)
    if NZA.UI.IsOpen(APP) then NZA.UI.Close(APP) end
    if not choice then return end
    X.Take(entity, target, choice)
    if not busy and NZA.UI.IsOpen(APP) then NZA.UI.Close(APP) end
end

-- ════════════════════════════════════════════════════════════════════════
-- READING A FILM
-- ════════════════════════════════════════════════════════════════════════

local function cancelRead(token)
    if token then TriggerServerEvent('nza:xray:read:cancel', token) end
end

local function easyRead(payload)
    local me = PlayerPedId()
    local done = lib.progressBar({
        duration = math.floor((tonumber(payload.easyTime) or 8) * 1000), label = L('read_progress'),
        useWhileDead = false, canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { scenario = 'WORLD_HUMAN_CLIPBOARD' },
    })
    ClearPedTasks(me)
    if not done then
        cancelRead(payload.token)
        return
    end
    local ok, res = pcall(lib.callback.await, 'nza:xray:read:finish', false, payload.token, { easy = true })
    if not ok or type(res) ~= 'table' or not res.ok then
        NZA.UI.Toast({ title = L('read_title'), message = X.Err(ok and res or nil), type = 'error', icon = 'xray' })
        return
    end
    local out = res.outcome or {}
    NZA.UI.Toast({ title = L('read_title'), message = out.msg or '', type = 'success', icon = 'xray', duration = 6500 })
end

function X.Read(payload)
    if type(payload) ~= 'table' or not payload.token then return end
    if busy then
        cancelRead(payload.token)
        X.Toast('err_busy', 'error')
        return
    end
    if payload.easy then
        busy = 'read'
        local ok, err = pcall(easyRead, payload)
        if not ok then NZA.Warn('xray easy read failed: ' .. tostring(err)) end
        busy = nil
        return
    end
    busy = 'read'
    local s = { mode = payload.mode, token = payload.token }
    session = s
    local ok, err = pcall(function()
        local me = PlayerPedId()
        local rc = cfg('Read')
        local point, lbEnt = X.NearLightbox((tonumber(rc.lightboxDistance) or 3.0) + 1.0)
        if lbEnt and lbEnt ~= 0 then
            TaskTurnPedToFaceEntity(me, lbEnt, 700)
            Wait(500)
            if rc.camera ~= false then
                s.camOn = true
                local off = rc.cameraOffset or vector3(0.0, 0.15, 1.47)
                NZA.Cam.Orbit({ entity = lbEnt, offset = off }, {
                    dist = tonumber(rc.cameraDist) or 0.95, pitch = 2, front = true, fov = 46, hideHud = true,
                    minDist = 0.8, maxDist = 2.6, minPitch = -10, maxPitch = 30, pan = false,
                })
            end
        end
        if NZA.Anim and NZA.Anim.Play then
            s.animOn = NZA.Anim.Play(me, nil, nil, { scenario = 'WORLD_HUMAN_CLIPBOARD' }) and true or false
        end
        NZA.UI.Open(APP, {
            mode = payload.mode, token = payload.token, film = payload.film, tolerance = payload.tolerance,
            measureTolerance = payload.measureTolerance, minTime = payload.minTime,
            lightbox = lbEnt ~= nil and lbEnt ~= 0, keys = keys(), locale = X.Locale(),
        }, { focus = true, cursor = true })
        local origin = GetEntityCoords(me)
        local got = waitFor(s, function()
            if #(GetEntityCoords(PlayerPedId()) - origin) > 6.0 then s.abortReq = true end
            return s.result ~= nil
        end, ((tonumber(rc.maxTime) or 600) + 5) * 1000)
        if not got or not s.result then
            cancelRead(payload.token)
            return
        end
        if payload.mode == 'view' then
            cancelRead(payload.token)
            return
        end
        local okCall, res = pcall(lib.callback.await, 'nza:xray:read:finish', false, payload.token, s.result)
        if not okCall or type(res) ~= 'table' or not res.ok then
            NZA.UI.Send(APP, 'error', { msg = X.Err(okCall and res or nil) })
            Wait(2500)
            return
        end
        local out = res.outcome or {}
        NZA.UI.Send(APP, 'result', out)
        NZA.UI.Toast({ title = L('read_title'), message = out.msg or '', type = (out.score or 0) >= 50 and 'success' or 'warning',
            icon = 'xray', grade = out.grade, duration = 6500 })
        local deadline = GetGameTimer() + 90000
        while not s.closed and GetGameTimer() < deadline do
            Wait(100)
            if NZA.Self and NZA.Self.IsDown and NZA.Self.IsDown() then break end
        end
    end)
    if not ok then
        NZA.Warn('xray read failed: ' .. tostring(err))
        cancelRead(payload.token)
    end
    endSession(s)
    busy = nil
end

RegisterNetEvent('nza:xray:read', function(payload)
    CreateThread(function() X.Read(payload) end)
end)

-- lightbox target / radial: choose one of the films you carry
function X.ReadAt()
    if busy then
        X.Toast('err_busy', 'error')
        return
    end
    local ok, films = pcall(lib.callback.await, 'nza:xray:films', false)
    if not ok or type(films) ~= 'table' or #films == 0 then
        X.Toast('err_nofilm', 'error')
        return
    end
    local function open(slot)
        CreateThread(function()
            local okO, res = pcall(lib.callback.await, 'nza:xray:open', false, slot)
            if not okO or type(res) ~= 'table' or not res.ok then
                NZA.UI.Toast({ title = L('read_title'), message = X.Err(okO and res or nil), type = 'error', icon = 'xray' })
                return
            end
            X.Read(res)
        end)
    end
    if #films == 1 then
        open(films[1].slot)
        return
    end
    local options = {}
    for _, f in ipairs(films) do
        options[#options + 1] = {
            title = ('%s · %s'):format(f.id or '?', f.viewLabel or ''),
            description = ('%s · %s%s'):format(f.name or '', f.taken or '', f.read and (' · ' .. L('film_read', f.read)) or ''),
            icon = 'x-ray',
            onSelect = function() open(f.slot) end,
        }
    end
    lib.registerContext({ id = 'nza_xray_films', title = L('films_title'), options = options })
    lib.showContext('nza_xray_films')
end

-- ════════════════════════════════════════════════════════════════════════
-- HELP OFF THE TABLE
-- ════════════════════════════════════════════════════════════════════════

local function requestControl(ent, ms)
    if NetworkHasControlOfEntity(ent) then return true end
    local deadline = GetGameTimer() + (ms or 1500)
    NetworkRequestControlOfEntity(ent)
    while not NetworkHasControlOfEntity(ent) and GetGameTimer() < deadline do
        Wait(50)
        NetworkRequestControlOfEntity(ent)
    end
    return NetworkHasControlOfEntity(ent)
end

-- stand a ped up beside the table it lies on
local function standBeside(ped, point)
    if IsEntityAttached(ped) then DetachEntity(ped, true, true) end
    FreezeEntityPosition(ped, false)
    ClearPedTasksImmediately(ped)
    local pc = pointCoords(point)
    if pc then
        local h = (type(point.coords) == 'vector4' and point.coords.w) or tonumber(point.heading) or GetEntityHeading(ped)
        local rad = math.rad(h)
        local side = vector3(math.cos(rad), math.sin(rad), 0.0)
        local me = GetEntityCoords(PlayerPedId())
        local a, b = pc + side * 0.95, pc - side * 0.95
        local dest = (#(a - me) <= #(b - me)) and a or b
        local found, gz = GetGroundZFor_3dCoord(dest.x, dest.y, pc.z + 1.0, false)
        SetEntityCoords(ped, dest.x, dest.y, found and gz or (pc.z - 0.9), false, false, false, false)
        SetEntityHeading(ped, h)
    end
    local a = cfg('OffTable').getUpAnim
    if a and a.dict and a.clip and lib and lib.requestAnimDict then
        pcall(lib.requestAnimDict, a.dict, 2000)
        if HasAnimDictLoaded(a.dict) then TaskPlayAnim(ped, a.dict, a.clip, 4.0, 4.0, 1600, 0, 0.0, false, false, false) end
    end
end

function X.OffTable(entity, target)
    local T = NZA.Transport
    if T and type(T.HelpOff) == 'function' then return T.HelpOff(entity, target) end
    target = target or NZA.Target.FromEntity(entity)
    if not target then return end
    local point = X.TablePoint(entity)
    local ok, res = pcall(lib.callback.await, 'nza:xray:offTable', false, target)
    if not ok or type(res) ~= 'table' or not res.ok then
        NZA.UI.Toast({ title = L('title'), message = X.Err(ok and res or nil), type = 'error', icon = 'xray' })
        return
    end
    if not res.player and not res.transport and entity and entity ~= 0 then
        if requestControl(entity, 2000) then
            SetBlockingOfNonTemporaryEvents(entity, true)
            standBeside(entity, point)
        end
    end
    X.Toast('off_ok', 'success')
end

RegisterNetEvent('nza:xray:standUp', function()
    local ped = PlayerPedId()
    local point = X.TablePoint(ped)
    standBeside(ped, point)
    X.Toast('off_patient', 'info')
end)

-- ════════════════════════════════════════════════════════════════════════
-- HOSPITAL POINTS
-- ════════════════════════════════════════════════════════════════════════

NZA.Points.RegisterType('xray', {
    label = L('point_xray'), icon = 'xray', prop = Config.Props.xray_table, needsHeading = true,
    target = {
        {
            name = 'nza_xray_console', label = L('opt_take_table'), icon = 'xray', perm = takePerm(), distance = 3.0,
            canInteract = function(point)
                return busy == nil and patientOnPoint(point) ~= nil
            end,
            onSelect = function(point)
                CreateThread(function()
                    local ped, target = patientOnPoint(point)
                    if not ped then
                        X.Toast('err_no_patient_table', 'error')
                        return
                    end
                    X.Console(ped, target)
                end)
            end,
        },
    },
})

NZA.Points.RegisterType('lightbox', {
    label = L('point_lightbox'), icon = 'lightbox', prop = Config.Props.lightbox, needsHeading = true,
    target = {
        {
            name = 'nza_xray_lightbox', label = L('opt_read'), icon = 'xray', distance = 2.2,
            canInteract = function() return busy == nil end,
            onSelect = function() CreateThread(X.ReadAt) end,
        },
    },
})

-- ════════════════════════════════════════════════════════════════════════
-- PATIENT OPTIONS
-- ════════════════════════════════════════════════════════════════════════

local function notPlaced(st)
    return not (type(st) == 'table' and (st.carried or st.bag or st.stretcher))
end

do
    local states = cfg('Take').states or { alive = true, wounded = true }
    -- one option on a patient lying on the table: the console picks the body part (no list of
    -- per-view entries in the target menu)
    NZA.Interact.Add({
        name = 'nza_xray_table', label = L('opt_take_patient'), icon = 'xray', order = 60,
        perm = takePerm(), states = states, distance = 3.0,
        canInteract = function(entity, _, st)
            return busy == nil and notPlaced(st) and X.TablePoint(entity) ~= nil
        end,
        onSelect = function(entity, target) X.Console(entity, target) end,
    })
    NZA.Interact.Add({
        name = 'nza_xray_any', label = L('opt_any'), icon = 'xray', order = 60,
        perm = takePerm(), states = states, distance = 3.0,
        canInteract = function(entity, _, st)
            return busy == nil and notPlaced(st) and X.TablePoint(entity) == nil and easyAnywhere()
        end,
        onSelect = function(entity, target) X.Console(entity, target) end,
    })
    if cfg('OffTable').enabled ~= false then
        NZA.Interact.Add({
            name = 'nza_xray_off', label = L('opt_off'), icon = 'walk', order = 10,
            perm = cfg('OffTable').perm, states = { alive = true, wounded = true }, distance = 3.0,
            canInteract = function(entity, _, st)
                if NZA.Transport and type(NZA.Transport.HelpOff) == 'function' and NZA.Transport.OwnsHelpOff then return false end
                if not cfg('OffTable').perm and not (NZA.Perm('xray') or NZA.Perm('transport')) then return false end
                return busy == nil and notPlaced(st) and X.TablePoint(entity) ~= nil
            end,
            onSelect = function(entity, target) X.OffTable(entity, target) end,
        })
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- RADIAL (EMS job menu)
-- ════════════════════════════════════════════════════════════════════════

local function patientOnNearbyTable()
    local me = GetEntityCoords(PlayerPedId())
    local range = (tonumber(cfg('Radial').range) or 3.0) + 1.5
    local best, bestD, bestT = nil, nil, nil
    for _, pt in pairs(NZA.Points.All('xray') or {}) do
        local pc = pointCoords(pt)
        if pc and #(pc - me) <= range then
            local ped, t = patientOnPoint(pt)
            if ped then
                local d = #(GetEntityCoords(ped) - me)
                if not bestD or d < bestD then best, bestD, bestT = ped, d, t end
            end
        end
    end
    return best, bestT
end

NZA.RadialItems = NZA.RadialItems or {}
table.insert(NZA.RadialItems, {
    id = 'xray_take', parent = 'patient', label = L('opt_take_table'), icon = 'xray', order = 60, perm = takePerm(),
    canShow = function()
        if cfg('Radial').enabled == false or busy then return false end
        return patientOnNearbyTable() ~= nil
    end,
    onSelect = function()
        CreateThread(function()
            local ped, t = patientOnNearbyTable()
            if not ped then
                X.Toast('err_no_patient_table', 'error')
                return
            end
            X.Console(ped, t)
        end)
    end,
})
table.insert(NZA.RadialItems, {
    id = 'xray_read', parent = nil, label = L('opt_read'), icon = 'lightbox', order = 80,
    canShow = function()
        if cfg('Radial').enabled == false or busy then return false end
        local pt = X.NearLightbox(tonumber(cfg('Radial').range) or 3.0)
        return pt ~= nil
    end,
    onSelect = function() CreateThread(X.ReadAt) end,
})

-- ════════════════════════════════════════════════════════════════════════
-- CLEANUP
-- ════════════════════════════════════════════════════════════════════════

NZA.Bus.On('self:state', function(new)
    if new ~= 'alive' and session then
        session.abortReq = true
        if session.mode == 'choose' then endSession(session) busy = nil end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= NZA.Resource then return end
    local s = session
    if s then
        if s.token then TriggerServerEvent('nza:xray:read:cancel', s.token) end
        if s.camOn and NZA.Cam and NZA.Cam.Stop then pcall(NZA.Cam.Stop, 0) end
        if s.animOn then ClearPedTasks(PlayerPedId()) end
    end
end)
