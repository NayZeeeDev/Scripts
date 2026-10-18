--[[
    NAYZEEE AMBULANCE - Suture / wound closure (client)

    Runs the suture procedure (server: server/modules/suture.lua) with the full-screen 3D
    close-up NUI app 'suture' (html/apps/suture, engine html/core/nza3d.js).

    Entry points
      * Examination screen: NZA.ExamRoutes entry 'suture' (laceration / stab, and gunshot /
        shrapnel once the object is out) — available when the bleeding is controlled or the
        wound is small, otherwise greyed with the reason.
      * Patient interaction menu: "Stitch wound" (perm Config.Suture.perm).
      * Using the suture kit item: event 'nza:suture:use' → nearest patient.
      When several wounds can be closed the medic picks one (ox_lib context menu).

    API     NZA.Suture.Start(entityOrTarget, injuryId) → ok, outcome | reason  (blocks; call from a thread)
            NZA.Suture.Pick(entity, target)            choose a wound, then Start
            NZA.Suture.Eligible(injury) → ok, reasonText
    NUI     suture:finish (result) → { ok, pending }   then action 'result' (outcome) is sent
            suture:abort  suture:flinch  suture:close (core)
    Events  nza:suture:use (S→C, item used)
    Bus     suture:flinch (patientEntity, pain) when the patient flinches in the minigame
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Suture = NZA.Suture or {}
local Su = NZA.Suture

local APP = 'suture'
local run = nil      -- active session { ctx, entity, target, injury, closed, finished, anim }

local function cfg()
    return Config.Suture or {}
end

local function L(key, ...)
    return NZA.L('suture.' .. key, ...)
end

local function toast(kind, message)
    if NZA.UI and NZA.UI.Toast then
        NZA.UI.Toast({ title = L('label'), message = message, type = kind or 'info' })
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- ELIGIBILITY (mirror of the server rule, for menus; the server decides)
-- ════════════════════════════════════════════════════════════════════════

function Su.Eligible(inj)
    if type(inj) ~= 'table' then return false end
    local mode = (cfg().types or {})[inj.type]
    if not mode then return false end
    local t = inj.treat or {}
    if t.sutured then return false end          -- already closed: the route is hidden
    if mode == 'controlled' and (tonumber(inj.retained) or 0) > 0 and not t.extracted then
        return false, L('why_retained')
    end
    if NZA.Easy and NZA.Easy(cfg().perm or 'suture') then return true end
    local small = mode ~= 'controlled' and (tonumber(inj.severity) or 4) <= (tonumber(cfg().smallSeverity) or 2)
    local controlled = (tonumber(inj.bleed) or 0) <= (tonumber(cfg().maxBleed) or 12)
        or t.packed or t.bandaged or t.tourniquet
    if not small and not controlled then return false, L('why_bleeding', tonumber(inj.bleed) or 0) end
    return true
end

-- every wound of a medic snapshot this procedure applies to: { inj, ok, why }
local function candidates(snap)
    local out = {}
    for _, inj in ipairs((snap and snap.injuries) or {}) do
        if (cfg().types or {})[inj.type] and not (inj.treat and inj.treat.sutured) then
            local ok, why = Su.Eligible(inj)
            out[#out + 1] = { inj = inj, ok = ok, why = why }
        end
    end
    return out
end

-- ════════════════════════════════════════════════════════════════════════
-- RUN
-- ════════════════════════════════════════════════════════════════════════

local function lying(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end
    local st = NZA.Target.State(entity)
    local s = type(st) == 'table' and st.st or 'alive'
    if type(st) == 'table' and st.stretcher then return false end
    if s ~= 'alive' then return true end
    return IsPedRagdoll(entity) or IsPedFatallyInjured(entity)
end

local function startAnim(s)
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

local function cleanup(s)
    if not s or s.cleaned then return end
    s.cleaned = true
    if NZA.UI.IsOpen(APP) then NZA.UI.Close(APP) end
    if s.anim then NZA.Anim.Stop(PlayerPedId(), { token = s.anim }) end
    if run == s then run = nil end
end

local function gameCfg()
    local g = {}
    for k, v in pairs(cfg().Game or {}) do g[k] = v end
    g.gauzeMax = tonumber((cfg().optional or {}).gauze) or 0
    return g
end

-- Blocks until the procedure ends and the medic has closed the result card.
-- target = entity or target table.
function Su.Start(target, injuryId)
    if run then
        toast('error', L('err_busy'))
        return false, 'busy'
    end
    local entity = type(target) == 'number' and target or NZA.Target.Entity(target)
    local s = { entity = entity, injury = injuryId }
    run = s
    local ok, res = NZA.Proc.Run('suture', target, { injury = injuryId }, function(ctx)
        s.ctx = ctx
        ctx.onEnd(function(outcome)
            s.ended = true
            if s.anim then NZA.Anim.Stop(PlayerPedId(), { token = s.anim }) s.anim = nil end
            -- a finished closure keeps the NUI open for the result card; anything else closes it
            if not outcome then cleanup(s) end
        end)
        startAnim(s)
        if ctx.done() then return end
        local data = ctx.data or {}
        data.locale = NZA.LocaleTable('suture')
        data.cfg = gameCfg()
        NZA.UI.Open(APP, data, { focus = true, cursor = true })
        -- the NUI drives the session (finish / abort callbacks); wait here until it ends
        while not ctx.done() and not s.closed do Wait(100) end
        if not ctx.done() then ctx.abort('cancel') end
    end, { label = L('label') })
    if ok and NZA.UI.IsOpen(APP) then
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

-- Choose a wound on this patient, then start
function Su.Pick(entity, target)
    target = target or NZA.Target.FromEntity(entity)
    if not target then return end
    local snap = NZA.Patient.Get(target)
    if not snap then toast('error', L('err_no_patient')) return end
    local list = candidates(snap)
    local ready = {}
    for _, c in ipairs(list) do if c.ok then ready[#ready + 1] = c end end
    if #ready == 0 then
        toast('error', (list[1] and list[1].why) or L('err_nothing'))
        return
    end
    if #ready == 1 then
        Su.Start(entity ~= 0 and entity or target, ready[1].inj.id)
        return
    end
    local options = {}
    for _, c in ipairs(list) do
        local inj = c.inj
        options[#options + 1] = {
            title = ('%s · %s'):format(NZA.Util.InjuryLabel(inj.type), NZA.Util.RegionLabel(inj.region)),
            description = c.ok and L('pick_desc', tonumber(inj.length) or 0, tonumber(inj.bleed) or 0) or c.why,
            icon = 'scissors', disabled = not c.ok,
            onSelect = function()
                CreateThread(function() Su.Start(entity ~= 0 and entity or target, inj.id) end)
            end,
        }
    end
    lib.registerContext({ id = 'nza_suture_pick', title = L('pick_title'), options = options })
    lib.showContext('nza_suture_pick')
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

NZA.UI.On(APP, 'abort', function(_, cb)
    cb({ ok = true })
    local s = run
    if s and s.ctx and not s.ctx.done() then s.ctx.abort('cancel') end
end)

NZA.UI.On(APP, 'flinch', function(data, cb)
    cb({ ok = true })
    NZA.Bus.Emit('suture:flinch', run and run.entity or 0, type(data) == 'table' and tonumber(data.pain) or 0)
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
    for key, n in pairs(cfg().items or {}) do
        local name = Config.Items and Config.Items[key]
        if name and (tonumber(n) or 0) > 0 then out[name] = math.floor(tonumber(n)) end
    end
    return out
end

NZA.ExamRoutes = NZA.ExamRoutes or {}
table.insert(NZA.ExamRoutes, {
    id = 'suture', label = L('route_label'), icon = 'needle', perm = cfg().perm or 'suture', order = 30,
    types = routeTypes(), regions = nil,
    items = routeItems(),
    available = function(inj)
        if inj and inj.condition then return false end
        return Su.Eligible(inj)
    end,
    run = function(target, inj)
        Su.Start(target, inj.id)
    end,
})

if cfg().interact ~= false then
    NZA.Interact.Add({
        name = 'nza_suture', label = L('opt_suture'), icon = 'scissors', faIcon = 'fa-solid fa-scissors',
        order = tonumber(cfg().order) or 62, perm = cfg().perm or 'suture',
        states = { alive = true, wounded = true }, self = cfg().allowSelf == true, npc = true, player = true, distance = 2.0,
        canInteract = function(_, _, bag)
            if run then return false end
            if type(bag) ~= 'table' or not bag.tags then return true end
            for _, tag in ipairs(bag.tags) do
                if (cfg().types or {})[tag] then return true end
            end
            return false
        end,
        onSelect = function(entity, target) Su.Pick(entity, target) end,
    })
end

-- ════════════════════════════════════════════════════════════════════════
-- USABLE ITEM
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

RegisterNetEvent('nza:suture:use', function()
    if run then return end
    local ped = nearestPatient(tonumber(cfg().useRange) or 3.0)
    if not ped and cfg().allowSelf then ped = PlayerPedId() end
    if not ped then toast('error', L('err_no_patient')) return end
    local target = NZA.Target.FromEntity(ped, true)
    if not target then toast('error', L('err_no_patient')) return end
    CreateThread(function() Su.Pick(ped, target) end)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if run then cleanup(run) end
end)
