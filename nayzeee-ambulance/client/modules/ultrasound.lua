--[[
    NAYZEEE AMBULANCE - Ultrasound (client)                                   NZA.Ultrasound

    eFAST scan on a live B-mode image, the treatment plan it builds, ultrasound-guided
    pericardiocentesis, chest drain and needle decompression. The world side (camera, anchors,
    probe / syringe props, medic pose, cart screen) lives in ultrasound_world.lua.

    Where it works (the server re-checks everything, ARCHITECTURE §13):
      scan        patient within Config.Ultrasound.Scan.cartRange of an 'ultrasound' cart point,
                  on a cart point, in the ambulance treatment bay (Scan.bay), anywhere with
                  Scan.field, or anywhere in easy mode (NZA.Easy(perm))
      chest drain / pericardiocentesis   on a bed / table of the allowed room types, near a cart,
                  in the bay, with `field`, or anywhere in easy mode
      decompression   anywhere

    Registrations (file top level):
      NZA.Points.RegisterType 'ultrasound'   Config.Props.us_cart; target "Scan the patient (eFAST)"
                                             for the patient lying next to the cart
      NZA.Interact.Add  nza_us_scan    'Ultrasound (eFAST)'          order 60, perm Scan.perm
                        nza_us_drain   'Chest drain'                 order 62, perm ChestDrain.perm
                        nza_us_decomp  'Needle decompression'        order 34, perm Decompress.perm
                        nza_us_peri    'Pericardiocentesis'          order 63, perm Pericardio.perm
      NZA.ExamRoutes    us_drain (haemothorax / pneumothorax), us_decomp (pneumothorax),
                        us_peri (tamponade), us_scan (penetrating / blunt torso wounds, internal bleeds)
      NZA.RadialItems   us_scan, us_decomp (parent 'patient')
    API (runtime): NZA.Ultrasound.Scan(entity, target) · .Pericardio(entity, target)
      · .ChestDrain(entity, target, side?) · .Decompress(entity, target, side?)   (all block)
      · .Busy() · .CanHere(section, ped, perm) → ok, where · .Nearest(range?) → ped, target
    NUI callbacks: ultrasound:probe {x,y,rot,tilt,contact,…} · ultrasound:needle {phase,depth,ang,draw,touch}
      · ultrasound:finish {result} · ultrasound:launch {action, side, result} · ultrasound:flinch {pain}
      · ultrasound:abort · ultrasound:close (core)
    NUI messages: open (mode + server data + locale + inv + perms + stepItems) · vitals · result
      · launchFailed {msg} · abort
    Net events: nza:us:use (kind) S→C - a chest drain kit / decompression needle was used
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Ultrasound = NZA.Ultrasound or {}
local US = NZA.Ultrasound
local APP = 'ultrasound'
local session = nil

local function cfg(section)
    local c = Config.Ultrasound or {}
    if section then return type(c[section]) == 'table' and c[section] or {} end
    return c
end
local function L(key, ...) return NZA.L('ultrasound.' .. key, ...) end
local function num(v, d)
    v = tonumber(v)
    if not v or v ~= v then return d end
    return v
end
local function World() return NZA.Ultrasound.World end
local function toast(kind, msg, title)
    NZA.UI.Toast({ type = kind, title = title or L('title'), message = msg })
end

local PERM = {
    scan = function() return cfg('Scan').perm or 'ultrasound' end,
    chestdrain = function() return cfg('ChestDrain').perm or 'chestdrain' end,
    decompress = function() return cfg('Decompress').perm or 'chestdrain' end,
    pericardio = function() return cfg('Pericardio').perm or 'pericardio' end,
}
local SECTION = { scan = 'Scan', chestdrain = 'ChestDrain', decompress = 'Decompress', pericardio = 'Pericardio' }

function US.Busy() return session ~= nil end

-- ════════════════════════════════════════════════════════════════════════
-- ITEMS (client view; the server checks for real)
-- ════════════════════════════════════════════════════════════════════════

local function itemName(key) return Config.Items and Config.Items[key] or nil end

local function countOf(key)
    local name = itemName(key)
    if not name or not (Bridge and Bridge.Inv) then return 0 end
    if type(Bridge.Inv.Count) == 'function' then
        local ok, n = pcall(Bridge.Inv.Count, name)
        if ok and tonumber(n) then return tonumber(n) end
    end
    if type(Bridge.Inv.Has) == 'function' then
        local ok, has = pcall(Bridge.Inv.Has, name, 1)
        if ok and has then return 1 end
    end
    return 0
end

local function labelOf(key)
    local def = Config.ItemDefs and Config.ItemDefs[key]
    if type(def) == 'table' and def.label then return def.label end
    return (tostring(key):gsub('_', ' '))
end

local function hasItems(map)
    for key, n in pairs(map or {}) do
        if countOf(key) < (tonumber(n) or 1) then return false, key end
    end
    return true
end

local function angioItems()
    local a = Config.Angio
    if type(a) == 'table' and type(a.items) == 'table' then return a.items end
    return {}
end

local function stepItems()
    return {
        chestdrain = cfg('ChestDrain').items or {},
        decompress = cfg('Decompress').items or {},
        pericardio = cfg('Pericardio').items or {},
        angio = angioItems(),
        bleeding = { tourniquet = 1, bandage = 1, gauze = 1 },
        fragments = { surgical_kit = 1 },
    }
end

-- { [key] = { label, count } } for every key a plan step can show
local function invTable(steps)
    local out, seen = {}, {}
    local function add(key)
        if seen[key] then return end
        seen[key] = true
        out[key] = { label = labelOf(key), count = countOf(key) }
    end
    for _, map in pairs(stepItems()) do for key in pairs(map) do add(key) end end
    for _, s in ipairs(steps or {}) do
        if type(s) == 'table' and type(s.items) == 'table' then for key in pairs(s.items) do add(key) end end
    end
    if Config.Items and Config.Items.lidocaine then add('lidocaine') end
    return out
end

-- ════════════════════════════════════════════════════════════════════════
-- WHERE (mirror of server US.Location, for showing options only)
-- ════════════════════════════════════════════════════════════════════════

local function trBag(ped)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    if IsPedAPlayer(ped) then
        if ped == PlayerPedId() then return LocalPlayer.state.nzaTr end
        local idx = NetworkGetPlayerIndexFromPed(ped)
        if not idx or idx == -1 then return nil end
        return Player(GetPlayerServerId(idx)).state.nzaTr
    end
    if not NetworkGetEntityIsNetworked(ped) then return nil end
    return Entity(ped).state.nzaTr
end

local function inBay(ped)
    local tr = trBag(ped)
    if type(tr) == 'table' and tr.m == 'bay' then return true end
    local T = NZA.Transport
    if T and T.Bay and type(T.Bay.Active) == 'function' then
        local ok, active = pcall(T.Bay.Active)
        if ok and active then return true end
    end
    return false
end

-- section 'Scan' | 'ChestDrain' | 'Pericardio' | 'Decompress' → ok, where
function US.CanHere(section, ped, perm)
    if section == 'Decompress' then return true, 'field' end
    if NZA.Easy and NZA.Easy(perm) then return true, 'easy' end
    local c = cfg(section)
    if c.bay ~= false and inBay(ped) then return true, 'bay' end
    local tr = trBag(ped)
    local bedType = type(tr) == 'table' and tr.m == 'bed' and tr.bt or nil
    local coords = ped and ped ~= 0 and GetEntityCoords(ped) or nil
    if section == 'Scan' then
        if bedType == 'ultrasound' then return true, 'cart' end
        if coords and World().NearestCart(coords) then return true, 'cart' end
    else
        local rooms = c.rooms or {}
        if bedType and rooms[bedType] then return true, 'room' end
        if rooms.ultrasound and coords and World().NearestCart(coords) then return true, 'room' end
    end
    if c.field == true then return true, 'field' end
    return false, section == 'Scan' and 'need_cart' or 'need_room'
end

local function stateOk(bag, states)
    return type(bag) == 'table' and not bag.bag and (states or { alive = true, wounded = true, arrest = true })[bag.st] == true
end

-- lying patients only near a cart (a standing colleague next to it is not a patient)
local function lying(ped, bag)
    if type(bag) ~= 'table' then return false end
    if bag.st ~= 'alive' then return true end
    local tr = trBag(ped)
    if type(tr) == 'table' and (tr.m == 'bed' or tr.m == 'str' or tr.m == 'bay') then return true end
    if IsPedRagdoll(ped) then return true end
    local neck = GetPedBoneCoords(ped, 39317, 0.0, 0.0, 0.0)
    local pelvis = GetPedBoneCoords(ped, 11816, 0.0, 0.0, 0.0)
    return math.abs(neck.z - pelvis.z) < 0.32
end

function US.Nearest(range, filter)
    range = range or num(cfg().useRange, 3.0)
    local me = PlayerPedId()
    local mc = GetEntityCoords(me)
    local best, bd, bt = nil, nil, nil
    for _, ped in ipairs(GetGamePool('CPed')) do
        if ped ~= me then
            local d = #(GetEntityCoords(ped) - mc)
            if d <= range and (not bd or d < bd) then
                local bag = NZA.Target.State(ped)
                if stateOk(bag) and (not filter or filter(ped, bag)) then
                    local t = NZA.Target.FromEntity(ped)
                    if t then best, bd, bt = ped, d, t end
                end
            end
        end
    end
    return best, bt
end

local function patientAtCart(point)
    local c = point and point.coords
    if not c then return nil end
    local range = num(cfg('Scan').cartRange, 2.6)
    local me = PlayerPedId()
    local best, bd, bt = nil, nil, nil
    for _, ped in ipairs(GetGamePool('CPed')) do
        if ped ~= me then
            local pc = GetEntityCoords(ped)
            local d = #(vector2(pc.x, pc.y) - vector2(c.x, c.y))
            if d <= range and math.abs(pc.z - c.z) < 2.5 and (not bd or d < bd) then
                local bag = NZA.Target.State(ped)
                if stateOk(bag) and lying(ped, bag) then
                    local t = NZA.Target.FromEntity(ped)
                    if t then best, bd, bt = ped, d, t end
                end
            end
        end
    end
    return best, bt
end

-- ════════════════════════════════════════════════════════════════════════
-- SESSION HELPERS
-- ════════════════════════════════════════════════════════════════════════

local function vitalsOf(snap)
    local v = type(snap) == 'table' and snap.vitals or {}
    return {
        hr = tonumber(v.ecgRate) or tonumber(v.hr), ecgRate = tonumber(v.ecgRate), rhythm = v.rhythm,
        sys = tonumber(v.sys), dia = tonumber(v.dia), map = tonumber(v.map), spo2 = tonumber(v.spo2),
        rr = tonumber(v.rr), etco2 = tonumber(v.etco2),
    }
end

local function endSession(s)
    if not s or s.ended then return end
    s.ended = true
    if s.stopWatch then pcall(s.stopWatch) end
    s.stopWatch = nil
    if s.open then NZA.UI.Close(APP) end
    s.open = false
    if s.world then World().End(s.world) end
    s.world = nil
end

local function openApp(s, mode, d)
    local data = {}
    for k, v in pairs(d or {}) do data[k] = v end
    data.mode = mode
    data.locale = NZA.LocaleTable('ultrasound')
    data.inv = invTable(data.plan)
    data.stepItems = stepItems()
    data.perms = {
        chestdrain = NZA.Perm(PERM.chestdrain()), decompress = NZA.Perm(PERM.decompress()), pericardio = NZA.Perm(PERM.pericardio()),
    }
    data.keys = cfg().keys
    data.quality = data.quality or cfg('ChestDrain').quality
    s.open = NZA.UI.Open(APP, data, { focus = true, cursor = true }) ~= false
    if s.open then
        s.stopWatch = NZA.Patient.Watch(s.target, function(snap)
            if snap and s.open and not s.ended then
                local v = vitalsOf(snap)
                NZA.UI.Send(APP, 'vitals', v)
                if s.world then World().Vitals(s.world, v) end
            end
        end, { keep = true, initial = true })
    end
    return s.open
end

-- wait until the app is closed / aborted / a follow-up procedure is asked for
local function waitApp(s, ctx)
    while not s.ended do
        if ctx and ctx.done() then return 'done' end
        if s.result and ctx then
            local r = s.result
            s.result = nil
            local ok, outcome = ctx.finish(r)
            if ok then
                if s.open then NZA.UI.Send(APP, 'result', outcome or {}) end
                s.outcome = outcome
            else
                return 'failed'
            end
            return 'finished'
        end
        if s.launch then return 'launch' end
        if s.aborted or s.closed then return 'closed' end
        Wait(50)
    end
    return 'ended'
end

-- after the server graded it: keep the result on screen until the medic closes it or launches
local function readResult(s)
    if s.world then World().Hold(s.world) end
    local maxDist = num(cfg().maxDist, 6.0)
    while not s.ended and s.open and not s.closed and not s.aborted and not s.launch do
        local ent = s.entity
        if not ent or ent == 0 or not DoesEntityExist(ent) or #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(ent)) > maxDist then break end
        Wait(100)
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- SIDE PICKER (chest drain / decompression from the menu)
-- ════════════════════════════════════════════════════════════════════════

local function suspectedSide(target, kind)
    local okSnap, snap = pcall(NZA.Patient.Get, target)
    if not okSnap or type(snap) ~= 'table' then return nil end
    local f = type(snap.meta) == 'table' and type(snap.meta.findings) == 'table' and snap.meta.findings or {}
    local function has(k) return f[k] ~= nil end
    if kind == 'decompress' then
        if has('pneumothorax_suspected_right') and not has('pneumothorax_suspected_left') then return 'right' end
        if has('pneumothorax_suspected_left') and not has('pneumothorax_suspected_right') then return 'left' end
    else
        local r = has('haemothorax_suspected_right') or has('pneumothorax_suspected_right')
        local l = has('haemothorax_suspected_left') or has('pneumothorax_suspected_left')
        local drains = type(snap.devices) == 'table' and type(snap.devices.chestDrain) == 'table' and snap.devices.chestDrain or {}
        if r and not drains.right and not (l and not drains.left) then return 'right' end
        if l and not drains.left and not (r and not drains.right) then return 'left' end
    end
    return nil
end

local function pickSide(target, kind)
    local guess = suspectedSide(target, kind)
    if guess and cfg().askSide ~= true then return guess end
    local rows = lib.inputDialog(L(kind == 'decompress' and 'side_title_decomp' or 'side_title_drain'), {
        {
            type = 'select', label = L('side_label'), required = true, default = guess or 'right',
            options = {
                { value = 'right', label = L('side_pick_right') .. (guess == 'right' and (' · ' .. L('side_suspected')) or '') },
                { value = 'left', label = L('side_pick_left') .. (guess == 'left' and (' · ' .. L('side_suspected')) or '') },
            },
        },
    })
    if not rows or (rows[1] ~= 'right' and rows[1] ~= 'left') then return nil end
    return rows[1]
end

-- ════════════════════════════════════════════════════════════════════════
-- RUNNERS
-- ════════════════════════════════════════════════════════════════════════

local launchNext

local function procOpts(kind, entity)
    return { label = L('proc_' .. kind), maxDist = num(cfg(SECTION[kind]).maxDist, 3.0) + 0.5 }
end

local function resolve(entity, target)
    if not target and entity then target = NZA.Target.FromEntity(entity) end
    if type(target) ~= 'table' then return nil, nil end
    entity = (entity and entity ~= 0) and entity or NZA.Target.Entity(target)
    if not entity or entity == 0 then return nil, nil end
    return entity, target
end

local function begin(kind, entity, target, payload)
    if session then
        toast('error', L('err_busy'))
        return false, 'busy'
    end
    entity, target = resolve(entity, target)
    if not entity then return false, 'invalid' end
    local s = { kind = kind, entity = entity, target = target, payload = payload or {} }
    session = s
    return s
end

local function finishSession(s)
    endSession(s)
    if session == s then session = nil end
    local nxt = s.next
    if nxt then launchNext(s, nxt) end
end

-- ── eFAST scan ──
local function scanRunner(s, ctx)
    s.ctx = ctx
    local d = type(ctx.data) == 'table' and ctx.data or {}
    s.data = d
    s.world = World().Begin('scan', s.entity, { data = d })
    if ctx.done() or s.ended then return end
    if not openApp(s, 'scan', d) then ctx.abort('error') return end
    local how = waitApp(s, ctx)
    if how == 'launch' and not ctx.done() then
        -- the medic jumped straight to a step of the plan: grade what was called so far
        local r = s.launch.result
        local ok, outcome = ctx.finish(type(r) == 'table' and r or {})
        if ok then s.outcome = outcome end
    elseif how == 'closed' and not ctx.done() then
        ctx.abort('cancel')
    end
end

function US.Scan(entity, target)
    local s, err = begin('scan', entity, target)
    if not s then return false, err end
    local ok, res = NZA.Proc.Run('ultrasound', s.target, {}, function(ctx) scanRunner(s, ctx) end, procOpts('scan', s.entity))
    if ok and s.open and not s.ended and not s.launch then
        readResult(s)
    elseif ok and not s.world and s.ctx and s.ctx.easy and not s.ended then
        -- easy mode: show the read and the plan from the server's own read
        local d = type(s.ctx.data) == 'table' and s.ctx.data or {}
        s.data = d
        d.review = true
        if openApp(s, 'scan', d) then
            NZA.UI.Send(APP, 'result', type(res) == 'table' and res or {})
            readResult(s)
        end
    end
    if s.launch then s.next = { action = s.launch.action, side = s.launch.side } end
    finishSession(s)
    return ok, res
end

-- ── pericardiocentesis ──
local function periRunner(s, ctx)
    s.ctx = ctx
    local d = type(ctx.data) == 'table' and ctx.data or {}
    s.world = World().Begin('pericardio', s.entity, { data = d })
    if ctx.done() or s.ended then return end
    if not openApp(s, 'pericardio', d) then ctx.abort('error') return end
    waitApp(s, ctx)
    if s.aborted and not ctx.done() then ctx.abort('cancel') end
end

function US.Pericardio(entity, target)
    local s, err = begin('pericardio', entity, target)
    if not s then return false, err end
    local ok, res = NZA.Proc.Run('pericardio', s.target, {}, function(ctx) periRunner(s, ctx) end, procOpts('pericardio', s.entity))
    if ok and s.open and not s.ended then
        if s.world then World().Needle(s.world, { phase = 'out' }) end
        readResult(s)
    end
    finishSession(s)
    return ok, res
end

-- ── chest drain / decompression (full-screen 3D close-up) ──
local function closeUpRunner(kind)
    return function(s, ctx)
        s.ctx = ctx
        local d = type(ctx.data) == 'table' and ctx.data or {}
        s.world = World().Begin(kind, s.entity, { data = d, side = d.side or s.payload.side })
        if ctx.done() or s.ended then return end
        if not openApp(s, kind, d) then ctx.abort('error') return end
        waitApp(s, ctx)
        if s.aborted and not ctx.done() then ctx.abort('cancel') end
    end
end
local drainRunner, decompRunner = closeUpRunner('chestdrain'), closeUpRunner('decompress')

local function closeUp(kind, proc, runner, entity, target, side)
    entity, target = resolve(entity, target)
    if not entity then return false, 'invalid' end
    if session then toast('error', L('err_busy')) return false, 'busy' end
    if side ~= 'left' and side ~= 'right' then side = pickSide(target, kind) end
    if not side then return false, 'cancel' end
    local s, err = begin(kind, entity, target, { side = side })
    if not s then return false, err end
    local ok, res = NZA.Proc.Run(proc, s.target, { side = side }, function(ctx) runner(s, ctx) end, procOpts(kind, s.entity))
    if ok and s.open and not s.ended then readResult(s) end
    finishSession(s)
    return ok, res
end

function US.ChestDrain(entity, target, side) return closeUp('chestdrain', 'chestdrain', drainRunner, entity, target, side) end
function US.Decompress(entity, target, side) return closeUp('decompress', 'decompress', decompRunner, entity, target, side) end

launchNext = function(prev, nxt)
    local entity, target = prev.entity, prev.target
    CreateThread(function()
        Wait(350)
        if nxt.action == 'chestdrain' then US.ChestDrain(entity, target, nxt.side)
        elseif nxt.action == 'decompress' then US.Decompress(entity, target, nxt.side)
        elseif nxt.action == 'pericardio' then US.Pericardio(entity, target) end
    end)
end

-- ════════════════════════════════════════════════════════════════════════
-- NUI
-- ════════════════════════════════════════════════════════════════════════

NZA.UI.On(APP, 'probe', function(data, cb)
    local s = session
    if s and not s.ended and s.world and type(data) == 'table' then World().Probe(s.world, data) end
    cb({ ok = true })
end)

NZA.UI.On(APP, 'needle', function(data, cb)
    local s = session
    if s and not s.ended and s.world and type(data) == 'table' then
        World().Needle(s.world, data)
        if data.touch == true then
            World().Flinch(s.world)
            local name = s.ctx and type(s.ctx.data) == 'table' and s.ctx.data.patient and s.ctx.data.patient.name
            if name and cfg().speech ~= false then NZA.UI.Speech(name, L('say_heart_' .. math.random(1, 3)), 2600) end
        end
    end
    cb({ ok = true })
end)

NZA.UI.On(APP, 'flinch', function(data, cb)
    local s = session
    if s and not s.ended then
        if s.world then World().Flinch(s.world) end
        local now = GetGameTimer()
        if cfg().speech ~= false and (not s.saidAt or now - s.saidAt > 4500) then
            s.saidAt = now
            local name = s.ctx and type(s.ctx.data) == 'table' and s.ctx.data.patient and s.ctx.data.patient.name
            local st = NZA.Target.State(s.target)
            if name and type(st) == 'table' and (st.avpu == 'A' or st.avpu == 'V') then
                NZA.UI.Speech(name, L('say_pain_' .. math.random(1, 4)), 2600)
            end
        end
    end
    cb({ ok = true })
end)

NZA.UI.On(APP, 'finish', function(data, cb)
    local s = session
    if s and not s.ended and s.ctx and not s.ctx.done() and type(data) == 'table' and type(data.result) == 'table' then
        s.result = data.result
        cb({ ok = true })
        return
    end
    cb({ ok = false, msg = L('err_generic') })
end)

NZA.UI.On(APP, 'launch', function(data, cb)
    local s = session
    if not s or s.ended or s.kind ~= 'scan' or type(data) ~= 'table' then cb({ ok = false, msg = L('err_generic') }) return end
    local action = data.action
    if action ~= 'chestdrain' and action ~= 'decompress' and action ~= 'pericardio' then cb({ ok = false, msg = L('err_generic') }) return end
    if not NZA.Perm(PERM[action]()) then cb({ ok = false, msg = L('err_no_perm') }) return end
    local okItems, missing = hasItems(cfg(SECTION[action]).items)
    if not okItems then cb({ ok = false, msg = L('err_missing_item', labelOf(missing)) }) return end
    if action ~= 'decompress' then
        local ok, why = US.CanHere(SECTION[action], s.entity, PERM[action]())
        if not ok then cb({ ok = false, msg = L('err_' .. why) }) return end
    end
    local side = (data.side == 'left' or data.side == 'right') and data.side or nil
    s.launch = { action = action, side = side, result = type(data.result) == 'table' and data.result or {} }
    cb({ ok = true })
end)

NZA.UI.On(APP, 'abort', function(_, cb)
    local s = session
    if s and not s.ended then
        s.aborted = true
        if s.open then NZA.UI.Close(APP) s.open = false end
    end
    cb({ ok = true })
end)

NZA.Bus.On('ui:closed', function(app)
    local s = session
    if app == APP and s and not s.ended then
        s.open = false
        s.closed = true
        if s.ctx and not s.ctx.done() then s.aborted = true end
    end
end)

-- easy mode never calls the runner: keep the context (the scan shows its read afterwards)
NZA.Bus.On('proc:started', function(ctx)
    local s = session
    if not s or type(ctx) ~= 'table' or s.ctx then return end
    local procName = s.kind == 'scan' and 'ultrasound' or s.kind
    if ctx.name == procName then s.ctx = ctx end
end)

-- the core ended the session itself (patient moved, died, timed out): close the app
NZA.Bus.On('proc:ended', function(name, ok)
    local s = session
    if not s or s.ended or ok then return end
    local procName = s.kind == 'scan' and 'ultrasound' or s.kind
    if name ~= procName then return end
    if s.open then
        NZA.UI.Send(APP, 'abort', {})
        NZA.UI.Close(APP)
        s.open = false
    end
    s.aborted = true
end)

-- ════════════════════════════════════════════════════════════════════════
-- REGISTRATIONS
-- ════════════════════════════════════════════════════════════════════════

local function startAsync(fn, ...)
    local a = { ... }
    CreateThread(function() fn(table.unpack(a)) end)
end

-- hospital point: the ultrasound cart
NZA.Points.RegisterType('ultrasound', {
    label = L('point_cart'), icon = 'probe', prop = Config.Props.us_cart, needsHeading = true,
    data = { lie = cfg('Cart').lie },
    target = {
        {
            name = 'nza_us_cart', label = L('opt_cart_scan'), icon = 'probe', perm = PERM.scan(), distance = 2.6,
            canInteract = function(point) return session == nil and patientAtCart(point) ~= nil end,
            onSelect = function(point)
                CreateThread(function()
                    local ped, target = patientAtCart(point)
                    if not ped then toast('error', L('err_no_patient_cart')) return end
                    US.Scan(ped, target)
                end)
            end,
        },
    },
})

local ic = cfg('Interact')
if ic.enabled ~= false then
    local dist = num(ic.distance, 2.2)

    NZA.Interact.Add({
        name = 'nza_us_scan', label = L('opt_scan'), description = L('opt_scan_desc'), icon = 'probe', faIcon = 'wave-square',
        order = num(ic.orderScan, 60), perm = PERM.scan(),
        states = { alive = true, wounded = true, arrest = true }, self = false, npc = true, player = true, distance = dist,
        canInteract = function(entity, _, bag)
            if session or not stateOk(bag) then return false end
            return (US.CanHere('Scan', entity, PERM.scan()))
        end,
        onSelect = function(entity, target) US.Scan(entity, target) end,
    })

    NZA.Interact.Add({
        name = 'nza_us_drain', label = L('opt_drain'), description = L('opt_drain_desc'), icon = 'tube', faIcon = 'lungs',
        order = num(ic.orderDrain, 62), perm = PERM.chestdrain(),
        states = { alive = true, wounded = true, arrest = true }, self = false, npc = true, player = true, distance = dist,
        canInteract = function(entity, _, bag)
            if session or not stateOk(bag) then return false end
            if ic.needItems ~= false and not hasItems(cfg('ChestDrain').items) then return false end
            return (US.CanHere('ChestDrain', entity, PERM.chestdrain()))
        end,
        onSelect = function(entity, target) US.ChestDrain(entity, target) end,
    })

    NZA.Interact.Add({
        name = 'nza_us_decomp', label = L('opt_decomp'), description = L('opt_decomp_desc'), icon = 'needle', faIcon = 'syringe',
        order = num(ic.orderDecomp, 34), perm = PERM.decompress(),
        states = { alive = true, wounded = true, arrest = true }, self = false, npc = true, player = true, distance = dist,
        canInteract = function(_, _, bag)
            if session or not stateOk(bag) then return false end
            return ic.needItems == false or hasItems(cfg('Decompress').items)
        end,
        onSelect = function(entity, target) US.Decompress(entity, target) end,
    })

    NZA.Interact.Add({
        name = 'nza_us_peri', label = L('opt_peri'), description = L('opt_peri_desc'), icon = 'heart', faIcon = 'heart-pulse',
        order = num(ic.orderPeri, 63), perm = PERM.pericardio(),
        states = { alive = true, wounded = true, arrest = true }, self = false, npc = true, player = true, distance = dist,
        canInteract = function(entity, _, bag)
            if session or not stateOk(bag) then return false end
            if ic.needItems ~= false and not hasItems(cfg('Pericardio').items) then return false end
            return (US.CanHere('Pericardio', entity, PERM.pericardio()))
        end,
        onSelect = function(entity, target) US.Pericardio(entity, target) end,
    })
end

-- examination: treatment buttons on suspected chest conditions and torso wounds
local function itemsByName(map)
    local out = {}
    for key, n in pairs(map or {}) do
        local name = itemName(key)
        if name then out[name] = n end
    end
    return out
end
local function entityOfSnap(target)
    local ent = NZA.Target.Entity(target)
    return ent ~= 0 and ent or nil
end
local function targetOfSnap(snap)
    if type(snap) ~= 'table' then return nil end
    if snap.kind == 'npc' and snap.net then return { kind = 'npc', net = snap.net } end
    if snap.src then return { kind = 'player', sid = snap.src } end
    return nil
end
local function placeReason(section, perm, snap)
    local target = targetOfSnap(snap)
    if not target then return true end
    local ent = entityOfSnap(target)
    if not ent then return false, L('err_generic') end
    local ok, why = US.CanHere(section, ent, perm)
    if ok then return true end
    return false, L('route_' .. why)
end

NZA.ExamRoutes = NZA.ExamRoutes or {}
if cfg().examRoutes ~= false then
    table.insert(NZA.ExamRoutes, {
        id = 'us_drain', label = L('route_drain'), icon = 'tube', perm = PERM.chestdrain(), order = 30,
        types = { 'haemothorax', 'pneumothorax' }, regions = nil, items = itemsByName(cfg('ChestDrain').items),
        available = function(inj, snap)
            if type(inj) ~= 'table' or inj.condition ~= true then return false end
            local drains = type(snap) == 'table' and type(snap.devices) == 'table' and type(snap.devices.chestDrain) == 'table' and snap.devices.chestDrain or {}
            if inj.side and drains[inj.side] then return false end
            return placeReason('ChestDrain', PERM.chestdrain(), snap)
        end,
        run = function(target, inj) US.ChestDrain(nil, target, inj and inj.side) end,
    })
    table.insert(NZA.ExamRoutes, {
        id = 'us_decomp', label = L('route_decomp'), icon = 'needle', perm = PERM.decompress(), order = 20,
        types = { 'pneumothorax' }, regions = nil, items = itemsByName(cfg('Decompress').items),
        available = function(inj) return type(inj) == 'table' and inj.condition == true end,
        run = function(target, inj) US.Decompress(nil, target, inj and inj.side) end,
    })
    table.insert(NZA.ExamRoutes, {
        id = 'us_peri', label = L('route_peri'), icon = 'heart', perm = PERM.pericardio(), order = 40,
        types = { 'tamponade' }, regions = nil, items = itemsByName(cfg('Pericardio').items),
        available = function(inj, snap)
            if type(inj) ~= 'table' or inj.condition ~= true then return false end
            return placeReason('Pericardio', PERM.pericardio(), snap)
        end,
        run = function(target) US.Pericardio(nil, target) end,
    })
    table.insert(NZA.ExamRoutes, {
        id = 'us_scan', label = L('route_scan'), icon = 'probe', perm = PERM.scan(), order = 75,
        types = { 'gunshot', 'stab', 'shrapnel', 'contusion', 'internal' }, regions = { 'chest', 'abdomen', 'pelvis', 'back' },
        available = function(inj, snap)
            if type(inj) ~= 'table' or (inj.type == 'contusion' and (tonumber(inj.severity) or 0) < 3) then return false end
            return placeReason('Scan', PERM.scan(), snap)
        end,
        run = function(target) US.Scan(nil, target) end,
    })
end

-- EMS radial (Patient ▸ …)
NZA.RadialItems = NZA.RadialItems or {}
if cfg().radial ~= false then
    local function scanFilter(ped) return (US.CanHere('Scan', ped, PERM.scan())) end
    table.insert(NZA.RadialItems, {
        id = 'us_scan', parent = 'patient', label = L('radial_scan'), desc = L('radial_scan_desc'), icon = 'probe',
        order = num(ic.orderScan, 60), perm = PERM.scan(),
        canShow = function() return session == nil and US.Nearest(nil, scanFilter) ~= nil end,
        onSelect = function()
            CreateThread(function()
                local ped, t = US.Nearest(nil, scanFilter)
                if not ped then toast('error', L('err_nobody')) return end
                US.Scan(ped, t)
            end)
        end,
    })
    table.insert(NZA.RadialItems, {
        id = 'us_decomp', parent = 'patient', label = L('radial_decomp'), desc = L('radial_decomp_desc'), icon = 'needle',
        order = num(ic.orderDecomp, 34), perm = PERM.decompress(),
        canShow = function() return session == nil and hasItems(cfg('Decompress').items) and US.Nearest() ~= nil end,
        onSelect = function()
            CreateThread(function()
                local ped, t = US.Nearest()
                if not ped then toast('error', L('err_nobody')) return end
                US.Decompress(ped, t)
            end)
        end,
    })
end

-- a usable item was used from the inventory (server checked the permission)
RegisterNetEvent('nza:us:use', function(kind)
    if kind ~= 'chestdrain' and kind ~= 'decompress' then return end
    if session then toast('error', L('err_busy')) return end
    local ped, t = US.Nearest(num(cfg().useRange, 3.0))
    if not ped then toast('error', L('err_nobody')) return end
    if kind == 'chestdrain' then
        local ok, why = US.CanHere('ChestDrain', ped, PERM.chestdrain())
        if not ok then toast('error', L('err_' .. why)) return end
        startAsync(US.ChestDrain, ped, t)
    else
        startAsync(US.Decompress, ped, t)
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- CLEANUP
-- ════════════════════════════════════════════════════════════════════════

NZA.Bus.On('self:state', function(state)
    local s = session
    if s and state ~= 'alive' then
        s.aborted = true
        if s.ctx and not s.ctx.done() then s.ctx.abort('down') end
        endSession(s)
        session = nil
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    local s = session
    session = nil
    if s then
        s.aborted = true
        endSession(s)
    end
end)
