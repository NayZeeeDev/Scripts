--[[
    NAYZEEE AMBULANCE - Bullet / fragment extraction (client)

    Runs the extraction surgery (server: server/modules/bullet.lua) with the full-screen 3D
    close-up NUI app 'bullet' (html/apps/bullet, engine html/core/nza3d.js) and owns the
    hospital point type 'surgery' (the operating table).

    Entry points
      * Examination screen: NZA.ExamRoutes entry 'bullet' (gunshot / shrapnel wounds that still
        hold metal) - greyed with the reason when the patient is not on an operating table or
        in an ambulance treatment bay (easy mode skips the room rule).
      * Patient interaction menu: "Remove projectile" (perm Config.Bullet.perm).
      * Operating table point: "Operate" on the patient lying there.
      * EMS radial → Patient → "Remove projectile" while a patient lies on a nearby table.
      * Using the surgical kit item: event 'nza:bullet:use' → nearest patient.
      When several wounds hold metal the surgeon picks one (ox_lib context menu).

    Point type 'surgery'  (NZA.Points.RegisterType)
      prop Config.Bullet.Table.model (false = the map's own table), the instrument tray
      Config.Props[Config.Bullet.Table.tray] beside it and a warm local operating light.
      The transport module lays patients on it (point.data.lie) and sets meta.bed.type = 'surgery'.

    API     NZA.Bullet.Start(entityOrTarget, injuryId) → ok, outcome | reason  (blocks; call from a thread)
            NZA.Bullet.Pick(entity, target)           choose a wound, then Start
            NZA.Bullet.Eligible(injury, snap) → ok, reasonText
            NZA.Bullet.OnTable(point) → entity, target  the patient lying on that operating table
    NUI     bullet:finish (result) → { ok, pending }, then action 'result' (outcome)
            bullet:abort { loss }  bullet:flinch { pain }  bullet:exitBay { loss }  bullet:close (core)
            Lua → JS: open (case), vitals (live monitor), result, abort
    Events  nza:bullet:use (S→C, item used)   nza:bullet:partial (C→S, blood the open wound cost before a stop)
    Bus     bullet:flinch (patientEntity, pain) when the patient flinches in the minigame
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Bullet = NZA.Bullet or {}
local Bx = NZA.Bullet
local U = NZA.Util

local APP = 'bullet'
local run = nil         -- active session { ctx, entity, target, injury, closed, finished, anim, stopWatch }
local suites = {}       -- [pointId] = { point, group, lamp = vector3 | nil, onTable = cache }

local function cfg()
    return Config.Bullet or {}
end

local function tcfg()
    return cfg().Table or {}
end

local function perm()
    return cfg().perm or 'surgery'
end

local function L(key, ...)
    return NZA.L('bullet.' .. key, ...)
end

local function toast(kind, message)
    if NZA.UI and NZA.UI.Toast then
        NZA.UI.Toast({ title = L('label'), message = message, type = kind or 'info' })
    end
end

local function easy()
    return NZA.Easy ~= nil and NZA.Easy(perm()) == true
end

-- ════════════════════════════════════════════════════════════════════════
-- ELIGIBILITY (mirror of the server rule, for menus; the server decides)
-- ════════════════════════════════════════════════════════════════════════

local function holdsMetal(inj)
    if type(inj) ~= 'table' then return false end
    if not (cfg().types or {})[inj.type] then return false end
    if (tonumber(inj.retained) or 0) <= 0 then return false end
    return not (inj.treat and inj.treat.extracted)
end

-- where the patient is, from a medic snapshot → ok, kind
local function located(snap)
    local meta = type(snap) == 'table' and snap.meta or {}
    local locs = cfg().locations or {}
    if type(meta) ~= 'table' then return false, 'field' end
    if type(meta.bed) == 'table' and meta.bed.type then return locs[meta.bed.type] == true, 'bed' end
    if meta.bay then return locs.bay == true, 'bay' end
    return false, 'field'
end

function Bx.Eligible(inj, snap)
    if not holdsMetal(inj) then return false end
    if cfg().requireLocation == false or easy() then return true end
    if snap ~= nil then
        local ok = located(snap)
        if not ok then return false, L('why_location') end
    end
    return true
end

local function candidates(snap)
    local out = {}
    for _, inj in ipairs((snap and snap.injuries) or {}) do
        if holdsMetal(inj) then
            local ok, why = Bx.Eligible(inj, snap)
            out[#out + 1] = { inj = inj, ok = ok, why = why }
        end
    end
    return out
end

-- ════════════════════════════════════════════════════════════════════════
-- OPERATING TABLE (point type 'surgery')
-- ════════════════════════════════════════════════════════════════════════

local function pointCoords(point)
    local c = point and point.coords
    if not c then return nil, 0.0 end
    return vector3(c.x + 0.0, c.y + 0.0, c.z + 0.0), (tonumber(c.w) or tonumber(point.heading) or 0.0) + 0.0
end

local function toWorld(point, off)
    local pos, h = pointCoords(point)
    if not pos then return nil end
    off = U.vec(off) or vector3(0.0, 0.0, 0.0)
    return GetOffsetFromCoordAndHeadingInWorldCoords(pos.x, pos.y, pos.z, h, off.x, off.y, off.z)
end

local function lieOffset(point)
    local d = point and type(point.data) == 'table' and point.data.lie or nil
    if type(d) == 'table' and (d.x or d.y or d.z) then
        return vector3(tonumber(d.x) or 0.0, tonumber(d.y) or 0.0, tonumber(d.z) or 0.0)
    end
    if tcfg().model == false then return vector3(0.0, 0.0, 0.0) end
    return U.vec(tcfg().lie) or vector3(0.0, 0.0, 0.62)
end

-- every patient ped near a spot, nearest first
local function patientsNear(coords, range)
    local out = {}
    local me = PlayerPedId()
    for _, ped in ipairs(GetGamePool('CPed')) do
        if ped ~= me and DoesEntityExist(ped) then
            local d = #(GetEntityCoords(ped) - coords)
            if d <= range then
                local target = NZA.Target.FromEntity(ped)
                if target then out[#out + 1] = { ent = ped, target = target, d = d } end
            end
        end
    end
    table.sort(out, function(a, b) return a.d < b.d end)
    return out
end

-- the patient lying on this table (laid there by the transport module, or simply lying on it)
function Bx.OnTable(point)
    if not point then return nil, nil end
    local s = suites[point.id] or { point = point }
    local now = GetGameTimer()
    local c = s.onTable
    if c and now - c.at < 500 and (not c.ent or DoesEntityExist(c.ent)) then return c.ent, c.target end
    local spot = toWorld(point, lieOffset(point))
    local first = nil
    if spot then
        local list = patientsNear(spot, (tonumber(tcfg().range) or 1.8) + 0.4)
        for _, p in ipairs(list) do
            local bag = Entity(p.ent).state.nzaTr
            if type(bag) == 'table' and bag.m == 'bed' and tostring(bag.b) == tostring(point.id) then
                first = p
                break
            end
        end
        if not first then
            for _, p in ipairs(list) do
                local head = GetPedBoneCoords(p.ent, 31086, 0.0, 0.0, 0.0)
                if head.z - GetEntityCoords(p.ent).z < 0.4 then
                    first = p
                    break
                end
            end
        end
    end
    s.onTable = { at = now, ent = first and first.ent or nil, target = first and first.target or nil }
    suites[point.id] = s
    if first then return first.ent, first.target end
    return nil, nil
end

-- the nearest operating table to a spot
local function tableNear(coords, range)
    local best, bestD = nil, range or 4.0
    for _, s in pairs(suites) do
        local pos = pointCoords(s.point)
        if pos then
            local d = #(pos - coords)
            if d < bestD then best, bestD = s, d end
        end
    end
    return best
end

local lampThread = false
local function lampLoop()
    if lampThread then return end
    lampThread = true
    CreateThread(function()
        local col = tcfg().lampColor or { 255, 244, 226 }
        local r, g, b = tonumber(col[1]) or 255, tonumber(col[2]) or 244, tonumber(col[3]) or 226
        local range = (tonumber(tcfg().lampRange) or 3.2) + 0.0
        local power = (tonumber(tcfg().lampIntensity) or 3.0) + 0.0
        while next(suites) ~= nil do
            local me = GetEntityCoords(PlayerPedId())
            local any = false
            for _, s in pairs(suites) do
                if s.lamp and #(s.lamp - me) < 30.0 then
                    any = true
                    DrawLightWithRange(s.lamp.x, s.lamp.y, s.lamp.z, r, g, b, range, power)
                end
            end
            Wait(any and 0 or 600)
        end
        lampThread = false
    end)
end

local function buildSuite(point, entity)
    local group = ('bullet_suite_%s'):format(tostring(point.id))
    local s = suites[point.id] or {}
    s.point, s.group, s.entity = point, group, entity
    suites[point.id] = s
    local T = tcfg()
    if T.tray and Config.Props and Config.Props[T.tray] then
        local pos = toWorld(point, T.trayPos or vector3(1.05, 0.15, 0.0))
        local _, h = pointCoords(point)
        if pos then
            NZA.Props.Spawn(T.tray, pos, {
                group = group, heading = (h + (tonumber(T.trayHeading) or 90.0)) % 360.0,
                freeze = true, collision = true, network = false, ground = true, fallbackKey = T.tray,
            })
        end
    end
    if suites[point.id] ~= s then
        NZA.Props.Clear(group)     -- removed while the tray was loading
        return
    end
    if T.lamp ~= false then
        s.lamp = toWorld(point, T.lampPos or vector3(0.0, 0.1, 2.1))
        lampLoop()
    end
end

local function removeSuite(point)
    local s = suites[point.id]
    suites[point.id] = nil
    NZA.Props.Clear(('bullet_suite_%s'):format(tostring(point.id)))
    if s then s.lamp = nil end
end

local function tableModel()
    local m = tcfg().model
    if m == false or m == nil or m == '' then return nil end
    return m
end

-- ════════════════════════════════════════════════════════════════════════
-- RUN
-- ════════════════════════════════════════════════════════════════════════

local function onBedPoint(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    local bag = Entity(entity).state.nzaTr
    return type(bag) == 'table' and (bag.m == 'bed' or bag.m == 'bay')
end

local function startAnim(s)
    local me = PlayerPedId()
    if s.entity and s.entity ~= 0 and s.entity ~= me and DoesEntityExist(s.entity) then
        TaskTurnPedToFaceEntity(me, s.entity, 500)
        Wait(450)
    end
    if s.entity == me then return end
    local st = s.entity and s.entity ~= 0 and NZA.Target.State(s.entity) or nil
    local down = type(st) == 'table' and st.st ~= 'alive' and not st.stretcher
    if down and not onBedPoint(s.entity) then
        s.anim = NZA.Anim.Kneel(me)
    else
        local ok, token = NZA.Anim.Play(me, 'mini@repair', 'fixing_a_ped', { flag = 49 })
        if ok then s.anim = token end
    end
end

-- live monitor for the NUI from the medic watch
local function vitalsOf(snap)
    local v = type(snap) == 'table' and snap.vitals or {}
    local drip, infusing = 0, false
    for _, inf in ipairs(type(snap) == 'table' and snap.infusions or {}) do
        if type(inf) == 'table' and not inf.paused and (tonumber(inf.left) or 0) > 0 then
            drip = drip + (tonumber(inf.rate) or 0)
            if inf.kind == 'blood' or inf.kind == 'plasma' then infusing = true end
        end
    end
    return {
        hr = tonumber(v.hr) or 0, ecgRate = tonumber(v.ecgRate) or tonumber(v.hr) or 0, rhythm = v.rhythm or 'sinus',
        spo2 = tonumber(v.spo2) or 0, sys = tonumber(v.sys) or 0, dia = tonumber(v.dia) or 0, map = tonumber(v.map) or 0,
        rr = tonumber(v.rr) or 0, bloodPct = tonumber(snap and snap.bloodPct) or 100,
        drip = math.floor(drip + 0.5), infusing = infusing,
    }
end

local function cleanup(s)
    if not s or s.cleaned then return end
    s.cleaned = true
    if s.stopWatch then pcall(s.stopWatch) s.stopWatch = nil end
    if NZA.UI.IsOpen(APP) then NZA.UI.Close(APP) end
    if s.anim then NZA.Anim.Stop(PlayerPedId(), { token = s.anim }) s.anim = nil end
    if run == s then run = nil end
end

local function gameCfg()
    local g = {}
    for k, v in pairs(cfg().Game or {}) do g[k] = v end
    g.gauzeMax = tonumber(cfg().gauzeMax) or 6
    return g
end

local function inBay()
    local T = NZA.Transport
    return T ~= nil and T.Bay ~= nil and T.Bay.Active ~= nil and T.Bay.Active() ~= nil
end

-- Blocks until the procedure ends and the surgeon has closed the result card.
-- target = entity or target table.
function Bx.Start(target, injuryId)
    if run then
        toast('error', L('err_busy'))
        return false, 'busy'
    end
    local entity = type(target) == 'number' and target or NZA.Target.Entity(target)
    local tgt = type(target) == 'table' and target or NZA.Target.FromEntity(entity)
    local s = { entity = entity, target = tgt, injury = injuryId }
    run = s
    local ok, res = NZA.Proc.Run('bullet', target, { injury = injuryId }, function(ctx)
        s.ctx = ctx
        ctx.onEnd(function(outcome)
            s.ended = true
            if s.stopWatch then pcall(s.stopWatch) s.stopWatch = nil end
            if s.anim then NZA.Anim.Stop(PlayerPedId(), { token = s.anim }) s.anim = nil end
            -- a finished operation keeps the NUI open for the result card; anything else closes it
            if not outcome then cleanup(s) end
        end)
        startAnim(s)
        if ctx.done() then return end
        local data = ctx.data or {}
        data.locale = NZA.LocaleTable('bullet')
        data.cfg = gameCfg()
        data.bay = data.bay == true and inBay()
        NZA.UI.Open(APP, data, { focus = true, cursor = true })
        if s.target then
            s.stopWatch = NZA.Patient.Watch(s.target, function(snap)
                if snap and NZA.UI.IsOpen(APP) then NZA.UI.Send(APP, 'vitals', vitalsOf(snap)) end
            end, { keep = true, initial = true })
        end
        -- the NUI drives the session (finish / abort callbacks); wait here until it ends
        while not ctx.done() and not s.closed do Wait(100) end
        if not ctx.done() then ctx.abort('cancel') end
    end, { label = L('label') })
    if ok and NZA.UI.IsOpen(APP) then
        -- result card: wait for the surgeon to close it (Enter), at most a minute
        local deadline = GetGameTimer() + 60000
        while not s.closed and NZA.UI.IsOpen(APP) and GetGameTimer() < deadline do
            Wait(100)
            if NZA.Self and NZA.Self.IsDown and NZA.Self.IsDown() then break end
        end
    end
    cleanup(s)
    if s.leaveBay then
        local T = NZA.Transport
        if T and T.Bay and T.Bay.Exit and inBay() then T.Bay.Exit() end
    end
    return ok, res
end

-- Choose a wound on this patient, then start
function Bx.Pick(entity, target)
    target = target or NZA.Target.FromEntity(entity)
    if not target then return end
    if not NZA.Perm(perm()) then toast('error', L('err_perm')) return end
    local snap = NZA.Patient.Get(target)
    if not snap then toast('error', L('err_no_patient')) return end
    local list = candidates(snap)
    local ready = {}
    for _, c in ipairs(list) do if c.ok then ready[#ready + 1] = c end end
    if #ready == 0 then
        toast('error', (list[1] and list[1].why) or L('err_nothing'))
        return
    end
    local where = (entity and entity ~= 0) and entity or target
    if #ready == 1 then
        Bx.Start(where, ready[1].inj.id)
        return
    end
    local options = {}
    for _, c in ipairs(list) do
        local inj = c.inj
        options[#options + 1] = {
            title = ('%s · %s'):format(U.InjuryLabel(inj.type), U.RegionLabel(inj.region)),
            description = c.ok and L('pick_desc', math.floor(tonumber(inj.retained) or 1), tonumber(inj.bleed) or 0) or c.why,
            icon = 'crosshairs', disabled = not c.ok,
            onSelect = function()
                CreateThread(function() Bx.Start(where, inj.id) end)
            end,
        }
    end
    lib.registerContext({ id = 'nza_bullet_pick', title = L('pick_title'), options = options })
    lib.showContext('nza_bullet_pick')
end

-- ════════════════════════════════════════════════════════════════════════
-- NUI
-- ════════════════════════════════════════════════════════════════════════

NZA.UI.On(APP, 'finish', function(data, cb)
    local s = run
    if not s or not s.ctx or s.finished then cb({ ok = false }) return end
    s.finished = true
    cb({ ok = true, pending = true })
    CreateThread(function()
        local fine, outcome = s.ctx.finish(type(data) == 'table' and data or {})
        if NZA.UI.IsOpen(APP) then
            if fine and type(outcome) == 'table' then
                NZA.UI.Send(APP, 'result', outcome)
            else
                NZA.UI.Send(APP, 'result', { error = L('err_save') })
            end
        end
    end)
end)

-- report the blood the open wound cost so far, then stop (the server caps and applies it)
local function reportLoss(s, data)
    local loss = type(data) == 'table' and tonumber(data.loss) or 0
    if s and s.ctx and s.ctx.token and loss and loss >= 1 then
        TriggerServerEvent('nza:bullet:partial', s.ctx.token, math.floor(loss + 0.5))
    end
end

NZA.UI.On(APP, 'abort', function(data, cb)
    cb({ ok = true })
    local s = run
    if s and s.ctx and not s.ctx.done() then
        reportLoss(s, data)
        s.ctx.abort('cancel')
    end
end)

NZA.UI.On(APP, 'flinch', function(data, cb)
    cb({ ok = true })
    local s = run
    if not s then return end
    local now = GetGameTimer()
    if s.lastFlinch and now - s.lastFlinch < 700 then return end
    s.lastFlinch = now
    NZA.Bus.Emit('bullet:flinch', s.entity or 0, type(data) == 'table' and tonumber(data.pain) or 0)
end)

-- hold BACKSPACE in the app: stop and step out of the ambulance bay
NZA.UI.On(APP, 'exitBay', function(data, cb)
    cb({ ok = true })
    local s = run
    if not s then return end
    s.leaveBay = true
    s.closed = true
    if s.ctx and not s.ctx.done() and not s.finished then
        reportLoss(s, data)
        s.ctx.abort('cancel')
    end
    if NZA.UI.IsOpen(APP) then NZA.UI.Close(APP) end
end)

NZA.Bus.On('ui:closed', function(app)
    if app ~= APP then return end
    local s = run
    if not s then return end
    s.closed = true
    if s.ctx and not s.ctx.done() and not s.finished then s.ctx.abort('cancel') end
end)

-- ════════════════════════════════════════════════════════════════════════
-- REGISTRIES
-- ════════════════════════════════════════════════════════════════════════

local function routeTypes()
    local out = {}
    for k in pairs(cfg().types or {}) do out[#out + 1] = k end
    table.sort(out)
    return out
end

local function routeItems()
    local out = {}
    for _, map in ipairs({ cfg().items or {}, cfg().supplies or {} }) do
        for key, n in pairs(map) do
            local name = Config.Items and Config.Items[key]
            if name and (tonumber(n) or 0) > 0 then out[name] = math.max(out[name] or 0, math.floor(tonumber(n))) end
        end
    end
    return out
end

-- Examination → treatment list
NZA.ExamRoutes = NZA.ExamRoutes or {}
table.insert(NZA.ExamRoutes, {
    id = 'bullet', label = L('route_label'), icon = 'forceps', perm = perm(), order = 25,
    types = routeTypes(), regions = nil,
    items = routeItems(),
    available = function(inj, snap)
        if inj and inj.condition then return false end
        return Bx.Eligible(inj, snap)
    end,
    run = function(target, inj)
        Bx.Start(target, inj.id)
    end,
})

-- Patient interaction menu
if cfg().interact ~= false then
    NZA.Interact.Add({
        name = 'nza_bullet', label = L('opt_extract'), icon = 'forceps', faIcon = 'fa-solid fa-crosshairs',
        order = tonumber(cfg().order) or 63, perm = perm(),
        states = { alive = true, wounded = true }, self = cfg().allowSelf == true, npc = true, player = true, distance = 2.2,
        canInteract = function(_, _, bag)
            if run then return false end
            if type(bag) ~= 'table' or not bag.tags then return true end
            for _, tag in ipairs(bag.tags) do
                if (cfg().types or {})[tag] then return true end
            end
            return false
        end,
        onSelect = function(entity, target) Bx.Pick(entity, target) end,
    })
end

-- Hospital point: the operating table
NZA.Points.RegisterType('surgery', {
    label = L('point'),
    desc = L('point_desc'),
    icon = 'scalpel',
    prop = tableModel(),
    needsHeading = true,
    ground = true,
    radius = 1.3,
    distance = 2.4,
    data = { bed = true, lie = { x = lieOffset(nil).x, y = lieOffset(nil).y, z = lieOffset(nil).z } },
    onSpawn = function(point, entity)
        CreateThread(function() buildSuite(point, entity) end)
    end,
    onRemove = function(point)
        removeSuite(point)
    end,
    target = {
        {
            name = 'operate', label = L('opt_operate'), icon = 'scalpel', perm = perm(), order = 1,
            canInteract = function(point)
                if run or NZA.Proc.Active() then return false end
                return Bx.OnTable(point) ~= nil
            end,
            onSelect = function(point)
                local ent, target = Bx.OnTable(point)
                if not ent then
                    toast('error', L('err_nobody_table'))
                    return
                end
                Bx.Pick(ent, target)
            end,
        },
    },
})

-- EMS radial → Patient → Remove projectile (a patient on a nearby operating table)
NZA.RadialItems = NZA.RadialItems or {}
if cfg().radial ~= false then
    table.insert(NZA.RadialItems, {
        id = 'bullet_start', parent = 'patient', label = L('opt_extract'), icon = 'forceps', order = 62, perm = perm(),
        canShow = function()
            if run or NZA.Proc.Active() then return false end
            local s = tableNear(GetEntityCoords(PlayerPedId()), 4.0)
            return s ~= nil and Bx.OnTable(s.point) ~= nil
        end,
        onSelect = function()
            CreateThread(function()
                local s = tableNear(GetEntityCoords(PlayerPedId()), 4.0)
                local ent, target = nil, nil
                if s then ent, target = Bx.OnTable(s.point) end
                if not ent then
                    toast('error', L('err_nobody_table'))
                    return
                end
                Bx.Pick(ent, target)
            end)
        end,
    })
end

-- ════════════════════════════════════════════════════════════════════════
-- USABLE ITEM
-- ════════════════════════════════════════════════════════════════════════

local function nearestPatient(range)
    local me = PlayerPedId()
    local coords = GetEntityCoords(me)
    local s = tableNear(coords, 4.0)
    if s then
        local ent = Bx.OnTable(s.point)
        if ent then return ent end
    end
    local list = patientsNear(coords, range)
    for _, p in ipairs(list) do
        local bag = NZA.Target.State(p.ent)
        if type(bag) == 'table' and type(bag.tags) == 'table' then
            for _, tag in ipairs(bag.tags) do
                if (cfg().types or {})[tag] then return p.ent end
            end
        end
    end
    return list[1] and list[1].ent or nil
end

RegisterNetEvent('nza:bullet:use', function()
    if run then return end
    local ped = nearestPatient(tonumber(cfg().useRange) or 3.0)
    if not ped and cfg().allowSelf then ped = PlayerPedId() end
    if not ped then toast('error', L('err_no_patient')) return end
    local target = NZA.Target.FromEntity(ped, true)
    if not target then toast('error', L('err_no_patient')) return end
    CreateThread(function() Bx.Pick(ped, target) end)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if run then cleanup(run) end
    for id, s in pairs(suites) do
        NZA.Props.Clear(s.group or ('bullet_suite_%s'):format(tostring(id)))
    end
    suites = {}
end)
