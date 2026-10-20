--[[
    NAYZEEE AMBULANCE - Burn care & skin graft (client)

    Runs the two burn procedures (server: server/modules/burn.lua) in ONE full-screen 3D NUI app
    'burn' (html/apps/burn, engine html/core/nza3d.js):
      burn care  ('burn')  1 cool · 2 test depth · 3 debride · 8 dress
      skin graft ('graft') 4 excise · 5 harvest · 6 mesh · 7 apply & staple · 8 dress
    A full-thickness burn can go straight from burn care into the graft: the app asks the server
    (nza:burn:graftCheck), burn care finishes with { continue = true }, then the graft session
    starts and the app carries on at step 4 without closing.

    Entry points
      * Patient exam, wound list: NZA.ExamRoutes 'burn' and 'graft'
      * Patient interaction menu: "Burn care" (perm Config.Burn.perm), "Skin graft" (perm Config.Burn.Graft.perm)
      * EMS radial menu, Patient: the same two entries (NZA.RadialItems 'burn_care', 'burn_graft')
      * Using the graft kit item: net event 'nza:burn:use' → nearest patient
      When the patient has several burns the medic picks one (ox_lib context menu).

    API     NZA.Burn.Start(entityOrTarget, injuryId, mode) → ok, outcome | reason   (blocks; call from a thread)
            NZA.Burn.Pick(entity, target, mode)       choose a burn, then Start ('care' | 'graft' | nil = best)
            NZA.Burn.CareEligible(inj) / GraftEligible(inj, snap?) → ok, reasonText
    NUI     burn:finish (result) → { ok, pending } then action 'careDone' (continue) / 'result' (outcome)
            burn:graftCheck {} → { ok, msg, err }   burn:abort        burn:pain { pain }      burn:close (core)
            Lua → JS: open (case) · careDone (outcome) · graft (case) · graftFail { msg } · result (outcome)
    Step away  the app's P / "Step away" parks the session (core '_proc:pause'); onEnd(nil, 'paused')
            closes the app like any end. The next start of the same procedure on this patient opens it
            with ctx.data.resume (the game's snapshot), copied to the app with the rest of the case.
            A graft parked after it went on from burn care is carried on by the next "Burn care" or
            "Skin graft" on that burn (started again with its own payload { injury, continue = true }).
    Events  nza:burn:use (S→C, graft kit used)
    Bus     burn:pain (patientEntity, pain) when the patient reacts in the minigame
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Burn = NZA.Burn or {}
local Bn = NZA.Burn

local APP = 'burn'
local run = nil      -- active session { entity, target, injury, mode, ctx, closed, finished, chain, paused, anim }
-- a graft that went on straight from burn care and was parked with Step away: its server session was
-- started with { continue = true } and resumes only with that payload, so the next "Burn care" /
-- "Skin graft" on that burn carries on with it.  ['<patient key>|<injury id>'] = GetGameTimer()
local chainParked = {}

local function cfg()
    return Config.Burn or {}
end

local function gcfg()
    return (Config.Burn or {}).Graft or {}
end

local function L(key, ...)
    return NZA.L('burn.' .. key, ...)
end

local function toast(kind, message, title)
    if NZA.UI and NZA.UI.Toast then
        NZA.UI.Toast({ title = title or L('label'), message = message, type = kind or 'info' })
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- ELIGIBILITY (mirror of the server rules for menus; the server decides)
-- ════════════════════════════════════════════════════════════════════════

local function burnOf(inj)
    local b = inj.burn or {}
    return tonumber(b.degree) or 1, tonumber(b.full) or 0
end

function Bn.CareEligible(inj)
    if type(inj) ~= 'table' or inj.type ~= 'burn' then return false end
    local t = inj.treat or {}
    if t.grafted then return false, L('err_graft_done') end
    local deg, full = burnOf(inj)
    if deg <= 1 and t.dressed then return false, L('err_done') end
    if t.cooled and t.debrided and t.dressed then
        if deg >= 3 and full > 0 then return false, L('err_graft') end
        return false, L('err_done')
    end
    return true
end

-- Surgery table / configured hospital point or the ambulance treatment bay (from the medic snapshot;
-- the server checks the same thing again when the graft starts)
local function atGraftLocation(snap)
    local meta = type(snap) == 'table' and snap.meta or nil
    if type(meta) ~= 'table' then return true end          -- unknown here: let the server decide
    local locs = gcfg().locations or {}
    if type(meta.bed) == 'table' and meta.bed.type and locs[meta.bed.type] then return true end
    if meta.bay and locs.bay then return true end
    return false
end

-- snap (optional) = medic snapshot of the patient, for the room check
function Bn.GraftEligible(inj, snap)
    if type(inj) ~= 'table' or inj.type ~= 'burn' then return false end
    local t = inj.treat or {}
    if t.grafted then return false, L('err_graft_done') end
    local deg, full = burnOf(inj)
    if deg < 3 or full <= 0 then return false end
    local easy = NZA.Easy and NZA.Easy(gcfg().perm or 'graft')
    if not easy and gcfg().needCare ~= false and not (t.cooled and t.debrided) then
        return false, L('why_care_first')
    end
    if not easy and gcfg().requireLocation ~= false and snap and not atGraftLocation(snap) then
        return false, L('why_graft_location')
    end
    return true
end

local function eligible(inj, mode, snap)
    if mode == 'graft' then return Bn.GraftEligible(inj, snap) end
    return Bn.CareEligible(inj)
end

-- ════════════════════════════════════════════════════════════════════════
-- RUN
-- ════════════════════════════════════════════════════════════════════════

local function lying(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    local st = NZA.Target.State(entity)
    if type(st) == 'table' and st.stretcher then return false end
    local s = type(st) == 'table' and st.st or 'alive'
    if s ~= 'alive' then return true end
    return IsPedRagdoll(entity) or IsPedFatallyInjured(entity)
end

local function startAnim(s)
    if s.anim then return end
    local me = PlayerPedId()
    if s.entity and s.entity ~= 0 and s.entity ~= me then
        TaskTurnPedToFaceEntity(me, s.entity, 500)
        Wait(400)
    end
    if s.entity == me then
        local ok, token = NZA.Anim.Play(me, 'missmic4', 'michael_tux_fidget', { flag = 49 })
        if ok then s.anim = token end
    elseif lying(s.entity) then
        s.anim = NZA.Anim.Kneel(me)
    else
        local ok, token = NZA.Anim.Play(me, 'mini@repair', 'fixing_a_ped', { flag = 49 })
        if ok then s.anim = token end
    end
end

local function stopAnim(s)
    if s and s.anim then
        NZA.Anim.Stop(PlayerPedId(), { token = s.anim })
        s.anim = nil
    end
end

local function cleanup(s)
    if not s or s.cleaned then return end
    s.cleaned = true
    if NZA.UI.IsOpen(APP) then NZA.UI.Close(APP) end
    stopAnim(s)
    if run == s then run = nil end
end

local function gameCfg()
    local g = {}
    for k, v in pairs(cfg().Game or {}) do g[k] = v end
    g.cooledBelow = cfg().cooledBelow
    g.sootLeftMax = cfg().sootLeftMax
    g.debridedMin = cfg().debridedMin
    g.secureAbove = cfg().secureAbove
    -- the optional sterile dressing is part of the kit (else the app never asks for one)
    g.secureItem = (tonumber((cfg().optional or {}).dressing) or 0) > 0
    g.minCoverage = gcfg().minCoverage
    g.minStaples = gcfg().minStaples
    g.minExcised = gcfg().minExcised
    return g
end

-- one procedure session with the app; keeps the app open when burn care chains into the graft
local function session(s, name, payload, first)
    return NZA.Proc.Run(name, s.target, payload, function(ctx)
        s.ctx = ctx
        s.finished = false
        ctx.onEnd(function(outcome, reason)
            -- stepped away (P): the server keeps the game state; the app closes like on any other end
            s.paused = reason == 'paused' and name or nil
            -- a finished session keeps the app (result card or the graft that follows); an abort closes it
            if not outcome then cleanup(s) end
        end)
        startAnim(s)
        if ctx.done() then return end
        local data = ctx.data or {}
        data.cfg = gameCfg()
        if first then
            data.locale = NZA.LocaleTable('burn')
            NZA.UI.Open(APP, data, { focus = true, cursor = true })
        elseif NZA.UI.IsOpen(APP) then
            NZA.UI.Send(APP, 'graft', data)
        else
            data.locale = NZA.LocaleTable('burn')
            NZA.UI.Open(APP, data, { focus = true, cursor = true })
        end
        -- the NUI drives the session (finish / abort callbacks); wait here until it ends
        while not ctx.done() and not s.closed do Wait(100) end
        if not ctx.done() then ctx.abort('cancel') end
    end, { label = name == 'graft' and L('graft_label') or L('label') })
end

-- Blocks until the procedure(s) end and the medic has closed the result card.
-- mode 'care' (default) or 'graft'. target = entity or target table.
function Bn.Start(target, injuryId, mode)
    if run then
        toast('error', L('err_busy'))
        return false, 'busy'
    end
    mode = mode == 'graft' and 'graft' or 'care'
    local entity = type(target) == 'number' and target or NZA.Target.Entity(target)
    local tgt = type(target) == 'table' and target or NZA.Target.FromEntity(entity, true)
    if not tgt then toast('error', L('err_no_patient')) return false, 'invalid' end
    local s = { entity = entity, target = tgt, injury = injuryId, mode = mode }
    run = s

    local ck = NZA.Target.Key(tgt)
    ck = ck and (ck .. '|' .. tostring(injuryId)) or nil
    local parkedAt = ck and chainParked[ck]
    if parkedAt and GetGameTimer() - parkedAt > (tonumber((Config.ProcPause or {}).keep) or 600) * 1000 then
        chainParked[ck], parkedAt = nil, nil
    end

    local ok, res
    if parkedAt then
        -- carry on with the graft that followed burn care (same payload as when it was parked)
        s.mode = 'graft'
        s.chain = true
        ok, res = session(s, 'graft', { injury = injuryId, continue = true }, true)
        -- it could not start again (room, kit, burn changed): the option works as usual next time
        if not s.ctx then chainParked[ck] = nil end
    elseif mode == 'care' then
        ok, res = session(s, 'burn', { injury = injuryId }, true)
        if ok and type(res) == 'table' and res.continue and not s.closed then
            -- straight on to the graft: same app, same patient
            s.mode = 'graft'
            s.chain = true
            -- an easy-mode graft runs as the core progress bar: the 3D app has nothing left to show
            if NZA.Easy and NZA.Easy(gcfg().perm or 'graft') and NZA.UI.IsOpen(APP) then
                NZA.UI.Close(APP)
            end
            local appOpen = NZA.UI.IsOpen(APP)
            local ok2, res2 = session(s, 'graft', { injury = injuryId, continue = true }, not appOpen)
            if not ok2 and NZA.UI.IsOpen(APP) and not s.closed then
                local key = 'err_graft_' .. tostring(res2)
                local msg = L(key)
                if msg == 'burn.' .. key then msg = L('err_graft_start') end
                NZA.UI.Send(APP, 'graftFail', { msg = msg, err = res2 })
            end
            ok, res = ok2 or ok, ok2 and res2 or res
        end
    else
        ok, res = session(s, 'graft', { injury = injuryId }, true)
    end
    if ck and s.chain then
        if s.paused == 'graft' then chainParked[ck] = GetGameTimer()
        elseif s.ctx and s.ctx.done() then chainParked[ck] = nil end
    end

    if NZA.UI.IsOpen(APP) and not s.closed then
        -- result card: wait for the medic to close it (Enter), at most a minute
        local deadline = GetGameTimer() + 60000
        while not s.closed and NZA.UI.IsOpen(APP) and GetGameTimer() < deadline do
            Wait(100)
            if NZA.Self and NZA.Self.IsDown and NZA.Self.IsDown() then break end
        end
    end
    cleanup(s)
    return ok, res
end

-- Choose a burn on this patient, then start. mode nil = graft when one is ready, else burn care.
function Bn.Pick(entity, target, mode)
    target = target or NZA.Target.FromEntity(entity)
    if not target then return end
    local snap = NZA.Patient.Get(target)
    if not snap then toast('error', L('err_no_patient')) return end
    local list, firstWhy = {}, nil
    for _, inj in ipairs(snap.injuries or {}) do
        if inj.type == 'burn' then
            local m = mode
            if not m then
                m = (Bn.GraftEligible(inj, snap) and NZA.Perm(gcfg().perm or 'graft')) and 'graft' or 'care'
            end
            local ok, why = eligible(inj, m, snap)
            if ok or why then list[#list + 1] = { inj = inj, ok = ok, why = why, mode = m } end
            if not ok and why and not firstWhy then firstWhy = why end
        end
    end
    local ready = {}
    for _, c in ipairs(list) do if c.ok then ready[#ready + 1] = c end end
    if #ready == 0 then
        toast('error', firstWhy or (mode == 'graft' and L('err_nothing_graft') or L('err_nothing')))
        return
    end
    local function go(c)
        Bn.Start(entity ~= 0 and entity or target, c.inj.id, c.mode)
    end
    if #ready == 1 then go(ready[1]) return end
    local options = {}
    for _, c in ipairs(list) do
        local inj = c.inj
        local deg, full = burnOf(inj)
        options[#options + 1] = {
            title = ('%s · %s'):format(L('deg_' .. math.max(1, math.min(3, deg))), NZA.Util.RegionLabel(inj.region)),
            description = c.ok and L('pick_desc', tonumber(inj.burn and inj.burn.area) or 0, full, c.mode == 'graft' and L('graft_label') or L('label')) or c.why,
            icon = c.mode == 'graft' and 'layer-group' or 'fire', disabled = not c.ok,
            onSelect = function() CreateThread(function() go(c) end) end,
        }
    end
    lib.registerContext({ id = 'nza_burn_pick', title = L('pick_title'), options = options })
    lib.showContext('nza_burn_pick')
end

-- ════════════════════════════════════════════════════════════════════════
-- NUI
-- ════════════════════════════════════════════════════════════════════════

NZA.UI.On(APP, 'finish', function(data, cb)
    local s = run
    if not s or not s.ctx or s.finished or s.ctx.done() then cb({ ok = false }) return end
    s.finished = true
    cb({ ok = true, pending = true })
    CreateThread(function()
        local fine, outcome = s.ctx.finish(type(data) == 'table' and data or {})
        if not NZA.UI.IsOpen(APP) then return end
        if fine and type(outcome) == 'table' then
            if outcome.continue then
                NZA.UI.Send(APP, 'careDone', outcome)
            else
                NZA.UI.Send(APP, 'result', outcome)
            end
        else
            NZA.UI.Send(APP, 'result', { error = L('err_save') })
        end
    end)
end)

NZA.UI.On(APP, 'graftCheck', function(_, cb)
    local s = run
    if not s or not s.target then cb({ ok = false, msg = L('err_no_patient') }) return end
    local ok, res = pcall(lib.callback.await, 'nza:burn:graftCheck', false, s.target, s.injury, true)
    if ok and type(res) == 'table' then
        cb({ ok = res.ok == true, msg = res.msg, err = res.err, easy = res.easy })
    else
        cb({ ok = false, msg = L('err_graft_start') })
    end
end)

NZA.UI.On(APP, 'abort', function(_, cb)
    cb({ ok = true })
    local s = run
    if s and s.ctx and not s.ctx.done() then s.ctx.abort('cancel') end
end)

NZA.UI.On(APP, 'pain', function(data, cb)
    cb({ ok = true })
    NZA.Bus.Emit('burn:pain', run and run.entity or 0, type(data) == 'table' and tonumber(data.pain) or 0)
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

local function itemsOf(list, skip)
    local out = {}
    for key, n in pairs(list or {}) do
        local name = Config.Items and Config.Items[key]
        if name and (tonumber(n) or 0) > 0 and key ~= skip then out[name] = math.floor(tonumber(n)) end
    end
    return out
end

NZA.ExamRoutes = NZA.ExamRoutes or {}
table.insert(NZA.ExamRoutes, {
    id = 'burn', label = L('route_care'), icon = 'flame', perm = cfg().perm or 'burn', order = 34,
    types = { 'burn' }, regions = nil,
    items = itemsOf(cfg().items),
    available = function(inj)
        if inj and inj.condition then return false end
        return Bn.CareEligible(inj)
    end,
    run = function(target, inj) Bn.Start(target, inj.id, 'care') end,
})
table.insert(NZA.ExamRoutes, {
    id = 'graft', label = L('route_graft'), icon = 'scissors', perm = gcfg().perm or 'graft', order = 36,
    types = { 'burn' }, regions = nil,
    items = itemsOf(gcfg().items),
    available = function(inj, snap)
        if inj and inj.condition then return false end
        return Bn.GraftEligible(inj, snap)
    end,
    run = function(target, inj) Bn.Start(target, inj.id, 'graft') end,
})

local function hasBurnTag(bag)
    if type(bag) ~= 'table' or not bag.tags then return true end
    for _, tag in ipairs(bag.tags) do
        if tag == 'burn' then return true end
    end
    return false
end

if cfg().interact ~= false then
    NZA.Interact.Add({
        name = 'nza_burn', label = L('opt_care'), icon = 'flame', faIcon = 'fa-solid fa-fire',
        order = tonumber(cfg().order) or 63, perm = cfg().perm or 'burn',
        states = { alive = true, wounded = true }, self = cfg().allowSelf == true, npc = true, player = true, distance = 2.0,
        canInteract = function(_, _, bag) return not run and hasBurnTag(bag) end,
        onSelect = function(entity, target) Bn.Pick(entity, target, 'care') end,
    })
    NZA.Interact.Add({
        name = 'nza_graft', label = L('opt_graft'), icon = 'scissors', faIcon = 'fa-solid fa-layer-group',
        order = (tonumber(cfg().order) or 63) + 1, perm = gcfg().perm or 'graft',
        states = { alive = true, wounded = true }, self = false, npc = true, player = true, distance = 2.0,
        canInteract = function(_, _, bag) return not run and hasBurnTag(bag) end,
        onSelect = function(entity, target) Bn.Pick(entity, target, 'graft') end,
    })
end

-- ════════════════════════════════════════════════════════════════════════
-- NEAREST PATIENT (radial menu, usable item)
-- ════════════════════════════════════════════════════════════════════════

local function nearestPatient(range)
    local me = PlayerPedId()
    local coords = GetEntityCoords(me)
    local best, bestD = nil, range
    for _, pl in ipairs(GetActivePlayers()) do
        local ped = GetPlayerPed(pl)
        if ped ~= me and ped ~= 0 then
            local d = #(coords - GetEntityCoords(ped))
            if d < bestD then best, bestD = ped, d end
        end
    end
    for _, ped in ipairs(GetGamePool('CPed')) do
        if ped ~= me and not IsPedAPlayer(ped) and NetworkGetEntityIsNetworked(ped) and Entity(ped).state.nza ~= nil then
            local d = #(coords - GetEntityCoords(ped))
            if d < bestD then best, bestD = ped, d end
        end
    end
    return best
end

local function startNearest(mode)
    if run then return end
    local ped = nearestPatient(tonumber(cfg().useRange) or 3.0)
    if not ped and cfg().allowSelf and mode ~= 'graft' then ped = PlayerPedId() end
    if not ped then toast('error', L('err_no_patient')) return end
    local target = NZA.Target.FromEntity(ped, true)
    if not target then toast('error', L('err_no_patient')) return end
    Bn.Pick(ped, target, mode)
end

NZA.RadialItems = NZA.RadialItems or {}
if cfg().radial ~= false then
    table.insert(NZA.RadialItems, {
        id = 'burn_care', parent = 'patient', label = L('opt_care'), icon = 'flame', order = 63, perm = cfg().perm or 'burn',
        canShow = function()
            if run or (NZA.Proc.Active and NZA.Proc.Active()) then return false end
            local ped = nearestPatient(tonumber(cfg().useRange) or 3.0)
            return ped ~= nil and hasBurnTag(NZA.Target.State(ped))
        end,
        onSelect = function() CreateThread(function() startNearest('care') end) end,
    })
    table.insert(NZA.RadialItems, {
        id = 'burn_graft', parent = 'patient', label = L('opt_graft'), icon = 'scissors', order = 64, perm = gcfg().perm or 'graft',
        canShow = function()
            if run or (NZA.Proc.Active and NZA.Proc.Active()) then return false end
            local ped = nearestPatient(tonumber(cfg().useRange) or 3.0)
            return ped ~= nil and hasBurnTag(NZA.Target.State(ped))
        end,
        onSelect = function() CreateThread(function() startNearest('graft') end) end,
    })
end

RegisterNetEvent('nza:burn:use', function()
    if run then return end
    CreateThread(function() startNearest(nil) end)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if run then cleanup(run) end
end)
