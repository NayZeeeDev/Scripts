--[[
    NAYZEEE AMBULANCE - NPC calls (server): generator, scenes, lifecycle

    While Config.Calls.generation.minMedics medics are on duty with NPC calls switched on
    (Player(src).state.nzaNpcCalls, owned by the dispatch module; nil = optInDefault), a call
    is created every interval from a weighted template (config/modules/calls.lua):
      NZA.Dispatch.Create{ npc = true, voice = 'audio/calls/<line>[_full].ogg', meta.scene }
    The scene itself is built when a medic comes within scene.spawnRadius: the nearest medic's
    client gets 'nza:calls:build' with a plan (models / offsets / poses, never injuries), spawns
    networked entities and reports their net ids. The server checks every entity (model,
    distance) before the victims become NPC patients (NZA.Patients.CreateNPC with
    meta { scenario, callId, scene }). Dispatch adds them to the call by meta.callId.
    Scenes are cleaned up after the call closed and nobody is around, after sceneTimeout,
    and when no opted-in medic stayed on duty (noMedicTimeout).

    API (server)
      NZA.Calls.Create(key?, opts?) → sceneId, callId | nil, err
            opts = { coords = vector4 (exact place), src = admin (for messages), force = bool }
      NZA.Calls.Get(sceneId) → scene | nil          NZA.Calls.All() → { [id] = scene }
      NZA.Calls.SceneOf(pid) → scene, victim | nil  NZA.Calls.Remove(sceneId, reason) → bool
      NZA.Calls.OptedMedics() → { { src, coords } }  NZA.Calls.Templates() → { key, ... }
    Net events
      C→S nza:calls:built (sceneId, token, result)   nza:calls:buildFailed (sceneId, token, reason)
      S→C nza:calls:build (plan)  nza:calls:scenes (list)  nza:calls:scene (public)
          nza:calls:sceneRemove (id)  nza:calls:fallback (call)
    Callbacks: nza:calls:sync () → public scene list
    Bus emitted: calls:created (scene), calls:built (scene), calls:removed (scene, reason)
    Bus listened: dispatch:closed, dispatch:status, patient:removed, player:unloaded
    Commands (admins): Config.Calls.admin.command / clearCommand / listCommand
    Other files: calls_scene.lua (plans, entity registration), calls_npc.lua (NPC behaviour,
    speech, extricate, release, hand-over & rewards), calls_aimedic.lua (AI medic).
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Calls = NZA.Calls or {}
NZA.Calls.Internal = NZA.Calls.Internal or {}
local C = NZA.Calls
local I = C.Internal
local U = NZA.Util

I.scenes = I.scenes or {}          -- [sceneId] = scene
I.victimIndex = I.victimIndex or {} -- [pid] = sceneId
I.byCall = I.byCall or {}           -- [callId] = sceneId

local scenes = I.scenes
local seq = 0
local lastUsed = {}                 -- ['key:index'] = os.time()
local lastType = nil
local nextAt = nil
local noMedicSince = nil
local voiceCache = {}

local function cfg(section)
    local c = Config.Calls or {}
    if section then return c[section] or {} end
    return c
end
I.Cfg = cfg

local function L(key, ...) return NZA.L(key, ...) end

local function now() return os.time() end

local function bridge(path, ...)
    if NZA.Core and NZA.Core.B then return NZA.Core.B(path, ...) end
    return nil
end
I.Bridge = bridge

local function srcCoords(src)
    if NZA.Core and NZA.Core.SrcCoords then return NZA.Core.SrcCoords(src) end
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end
I.SrcCoords = srcCoords

local function notify(src, msg, kind)
    if NZA.Core and NZA.Core.Notify then NZA.Core.Notify(src, msg, kind or 'info') end
end
I.Notify = notify

-- ════════════════════════════════════════════════════════════════════════
-- MEDICS
-- ════════════════════════════════════════════════════════════════════════

local function onDuty()
    local ok, list = pcall(NZA.Staff.OnDuty)
    if ok and type(list) == 'table' then return list end
    return bridge('GetMedics', true) or {}
end
I.OnDuty = onDuty

function C.OptedMedics()
    local out = {}
    local default = cfg('generation').optInDefault == true
    for _, src in ipairs(onDuty()) do
        src = tonumber(src)
        local pl = src and Player(src)
        local st = pl and pl.state and pl.state.nzaNpcCalls
        if st == true or (st == nil and default) then
            local c = srcCoords(src)
            if c then out[#out + 1] = { src = src, coords = c } end
        end
    end
    return out
end

local function medicsWithCoords()
    local out = {}
    for _, src in ipairs(onDuty()) do
        src = tonumber(src)
        local c = src and srcCoords(src)
        if c then out[#out + 1] = { src = src, coords = c } end
    end
    return out
end
I.Medics = medicsWithCoords

local function playersNear(coords, radius)
    local n = 0
    for _, id in ipairs(GetPlayers()) do
        local c = srcCoords(tonumber(id))
        if c and #(c - coords) <= radius then n = n + 1 end
    end
    return n
end
I.PlayersNear = playersNear

-- ════════════════════════════════════════════════════════════════════════
-- PUBLIC SCENE DATA (clients: effects, bystanders)
-- ════════════════════════════════════════════════════════════════════════

local function public(scene)
    if not scene.entities then return nil end
    local e = scene.entities
    local function list(t)
        local out = {}
        for idx, net in pairs(t or {}) do out[#out + 1] = { i = idx, n = net } end
        return out
    end
    local fx = {}
    for _, f in ipairs(scene.fx or {}) do
        fx[#fx + 1] = { id = f.id, kind = f.kind, net = f.net, at = f.at, on = f.on }
    end
    local victims = {}
    for _, v in pairs(scene.victims or {}) do
        victims[#victims + 1] = { n = v.net, tr = v.trapped or nil, veh = v.vehicle, seat = v.seat }
    end
    return {
        id = scene.id, key = scene.key, type = scene.tpl.type, state = scene.state, callId = scene.callId,
        c = scene.origin, vehicles = list(e.vehicles), props = list(e.props), bystanders = list(e.bystanders),
        victims = victims, fx = fx,
    }
end
I.Public = public

local function publicList()
    local out = {}
    for _, s in pairs(scenes) do
        local p = public(s)
        if p then out[#out + 1] = p end
    end
    return out
end

local function pushScene(scene)
    local p = public(scene)
    if p then TriggerClientEvent('nza:calls:scene', -1, p) end
end
I.PushScene = pushScene

lib.callback.register('nza:calls:sync', function(src)
    if not NZA.Core.Rate('calls_sync', src, 3, 10000) then return {} end
    return publicList()
end)

-- ════════════════════════════════════════════════════════════════════════
-- TEMPLATES, LOCATIONS, CALLERS
-- ════════════════════════════════════════════════════════════════════════

function C.Templates()
    local out = {}
    for key, tpl in pairs(cfg().templates or {}) do
        if type(tpl) == 'table' and tpl.enabled ~= false then out[#out + 1] = key end
    end
    table.sort(out)
    return out
end

local function pickTemplate()
    local weights = {}
    local repeatMul = tonumber(cfg('generation').repeatType) or 0.25
    for key, tpl in pairs(cfg().templates or {}) do
        if type(tpl) == 'table' and tpl.enabled ~= false and type(tpl.locations) == 'table' and #tpl.locations > 0 then
            local w = tonumber(tpl.weight) or 1
            if key == lastType then w = w * repeatMul end
            if w > 0 then weights[#weights + 1] = { key, w } end
        end
    end
    return U.weightedPick(weights)
end

local function tooCloseToScene(v)
    local spacing = tonumber(cfg('generation').sceneSpacing) or 250.0
    for _, s in pairs(scenes) do
        local c = s.center or vector3(s.loc.x, s.loc.y, s.loc.z)
        if #(c - v) < spacing then return true end
    end
    return false
end

local function pickLocation(key, tpl, medics, ignoreDistance)
    local g = cfg('generation')
    local cooldown = tonumber(g.locationCooldown) or 1800
    local minD, maxD = tonumber(g.minDistance) or 350.0, tonumber(g.maxDistance) or 3500.0
    local strict, relaxed, any = {}, {}, {}
    local t = now()
    for i, loc in ipairs(tpl.locations or {}) do
        local id = key .. ':' .. i
        if not (lastUsed[id] and t - lastUsed[id] < cooldown) then
            local v = vector3(loc.x, loc.y, loc.z)
            if not tooCloseToScene(v) then
                any[#any + 1] = i
                if not ignoreDistance then
                    local nearest, inReach = math.huge, false
                    for _, m in ipairs(medics) do
                        local d = #(m.coords - v)
                        if d < nearest then nearest = d end
                        if d <= maxD then inReach = true end
                    end
                    if nearest >= minD then
                        if inReach then strict[#strict + 1] = i else relaxed[#relaxed + 1] = i end
                    end
                end
            end
        end
    end
    local pool = ignoreDistance and any or (#strict > 0 and strict or relaxed)
    if #pool == 0 then return nil end
    local i = pool[math.random(#pool)]
    lastUsed[key .. ':' .. i] = t
    return tpl.locations[i], i
end

local function nameList(key)
    local out = {}
    for s in tostring(L(key)):gmatch('[^,]+') do
        s = s:gsub('^%s+', ''):gsub('%s+$', '')
        if s ~= '' then out[#out + 1] = s end
    end
    return out
end

local function callerName(sex)
    local first = I.Pick(nameList(sex == 'f' and 'calls.names_f' or 'calls.names_m'))
    local last = I.Pick(nameList('calls.surnames'))
    if not first then return L('calls.caller_anon') end
    return last and (first .. ' ' .. last) or first
end

local function voiceFile(path)
    if voiceCache[path] == nil then
        local ok, data = pcall(LoadResourceFile, GetCurrentResourceName(), 'html/' .. path)
        voiceCache[path] = ok and data ~= nil and #data > 0
    end
    return voiceCache[path] and path or nil
end

local function voiceFor(tpl, line)
    local cc = cfg('call')
    if cc.voice == false then return nil end
    local folder = tostring(cc.voiceFolder or 'audio/calls/')
    if folder:sub(-1) ~= '/' then folder = folder .. '/' end
    local mode = cc.voiceMode or 'full'
    if mode == 'dispatcher' and tpl.dispatcher then return voiceFile(folder .. tpl.dispatcher .. '.ogg') end
    if mode == 'full' then
        local p = voiceFile(folder .. line .. '_full.ogg')
        if p then return p end
    end
    return voiceFile(folder .. line .. '.ogg')
end

-- ════════════════════════════════════════════════════════════════════════
-- CREATE
-- ════════════════════════════════════════════════════════════════════════

local function nextId()
    seq = seq + 1
    return ('S%03d'):format(seq)
end

local function activeCount()
    local n = 0
    for _, s in pairs(scenes) do
        if s.state ~= 'closing' then n = n + 1 end
    end
    return n
end

local function fallbackAlert(scene, call)
    -- no dispatch module: page the opted-in medics directly
    local data = {
        id = scene.id, title = call.title, code = call.code, priority = call.priority,
        x = call.coords.x, y = call.coords.y, z = call.coords.z, message = call.message, voice = call.voice,
    }
    for _, m in ipairs(C.OptedMedics()) do TriggerClientEvent('nza:calls:fallback', m.src, data) end
    bridge('Dispatch.External', call)
end

function C.Create(key, opts)
    opts = opts or {}
    if cfg().enabled == false then return nil, 'disabled' end
    local templates = cfg().templates or {}
    if key and not templates[key] then return nil, 'unknown_type' end
    key = key or pickTemplate()
    local tpl = key and templates[key]
    if type(tpl) ~= 'table' then return nil, 'no_template' end

    local loc, locIndex
    if opts.coords then
        local c = opts.coords
        loc = vector4(c.x + 0.0, c.y + 0.0, c.z + 0.0, (c.w or 0.0) + 0.0)
    else
        loc, locIndex = pickLocation(key, tpl, C.OptedMedics(), opts.force == true)
        if not loc then return nil, 'no_location' end
    end

    local callerSpec = I.Pick(tpl.callers) or {}
    local line = callerSpec.line
    local sex = callerSpec.sex == 'f' and 'f' or 'm'
    local scene = {
        id = nextId(), key = key, tpl = tpl, loc = loc, locIndex = locIndex,
        state = 'pending', created = now(), attempts = 0, victims = {}, crewOf = {},
        caller = { name = callerName(sex), sex = sex, line = line,
                   phone = (cfg('call').phonePrefix or '555-') .. ('%04d'):format(math.random(0, 9999)) },
        forceBuilder = opts.buildBy,
    }
    scene.plan = I.Plan(key, tpl, loc, { callerSex = sex })

    local call = {
        code = tpl.code or '10-52', priority = U.clamp(tonumber(tpl.priority) or 2, 1, 3),
        title = L(tpl.title or ('calls.t_' .. key)), type = tpl.type or key,
        coords = vector3(loc.x, loc.y, loc.z),
        caller = cfg('call').showCaller ~= false and scene.caller.name or nil,
        phone = cfg('call').showCaller ~= false and scene.caller.phone or nil,
        message = line and L('calls.line.' .. line) or nil,
        voice = line and voiceFor(tpl, line) or nil,
        npc = true, source = 'npc', patients = {},
        meta = { scene = scene.id, scenario = key },
    }
    if NZA.Dispatch and NZA.Dispatch.Create then
        local ok, id = pcall(NZA.Dispatch.Create, call)
        if not ok or not id then
            NZA.Warn('calls: NZA.Dispatch.Create failed: ' .. tostring(id))
            return nil, 'dispatch'
        end
        scene.callId = id
    else
        scene.callId = 'N-' .. scene.id
        fallbackAlert(scene, call)
    end
    scenes[scene.id] = scene
    I.byCall[scene.callId] = scene.id
    lastType = key
    NZA.Bus.Emit('calls:created', scene)
    NZA.Debug('calls: new scene', scene.id, key, scene.callId, ('%.1f %.1f %.1f'):format(loc.x, loc.y, loc.z))
    return scene.id, scene.callId
end

function C.Get(id) return scenes[id] end
function C.All() return scenes end

function C.SceneOf(pid)
    if type(pid) == 'table' then pid = pid.pid end
    local id = pid and I.victimIndex[pid]
    local s = id and scenes[id]
    if not s then return nil end
    return s, s.victims[pid]
end

-- ════════════════════════════════════════════════════════════════════════
-- BUILD (the nearest medic's client spawns the scene)
-- ════════════════════════════════════════════════════════════════════════

local function sendBuild(scene, src)
    scene.state = 'building'
    scene.builder = src
    scene.buildToken = ('%s-%d-%d'):format(scene.id, math.random(100000, 999999), GetGameTimer())
    scene.buildAt = now()
    scene.attempts = scene.attempts + 1
    TriggerClientEvent('nza:calls:build', src, I.PublicPlan(scene))
    NZA.Debug('calls: build', scene.id, 'by', src, 'attempt', scene.attempts)
end

local function buildFailed(scene, reason)
    scene.builder, scene.buildToken = nil, nil
    if scene.attempts >= (tonumber(cfg('scene').maxBuildAttempts) or 3) then
        NZA.Warn(('calls: scene %s could not be built (%s)'):format(scene.id, tostring(reason)))
        C.Remove(scene.id, 'build_failed')
        return
    end
    scene.state = 'pending'
end

local function assignBuilders()
    local medics = nil
    local radius = tonumber(cfg('scene').spawnRadius) or 220.0
    local timeout = tonumber(cfg('scene').buildTimeout) or 20
    for _, scene in pairs(scenes) do
        if scene.state == 'building' and now() - (scene.buildAt or 0) > timeout then
            buildFailed(scene, 'timeout')
        end
        if scene.state == 'pending' then
            local v = vector3(scene.loc.x, scene.loc.y, scene.loc.z)
            if scene.forceBuilder and NZA.Core.Online(scene.forceBuilder) then
                local c = srcCoords(scene.forceBuilder)
                if c and #(c - v) <= radius then sendBuild(scene, scene.forceBuilder) end
            else
                medics = medics or medicsWithCoords()
                local best, bestD = nil, radius
                for _, m in ipairs(medics) do
                    local d = #(m.coords - v)
                    if d <= bestD then best, bestD = m.src, d end
                end
                if best then sendBuild(scene, best) end
            end
        end
    end
end

RegisterNetEvent('nza:calls:built', function(sceneId, token, result)
    local src = source
    if not NZA.Core.Rate('calls_built', src, 4, 10000) then return end
    local scene = scenes[sceneId]
    if not scene or scene.state ~= 'building' or scene.builder ~= src or scene.buildToken ~= token then
        -- stale build: delete whatever was spawned for it
        if type(result) == 'table' then
            for _, kind in ipairs({ 'victims', 'vehicles', 'props', 'bystanders' }) do
                for _, e in ipairs(type(result[kind]) == 'table' and result[kind] or {}) do
                    local ent = I.Ent(e.n)
                    if ent ~= 0 and NetworkGetEntityOwner(ent) == src then I.DeleteNet(e.n) end
                end
            end
        end
        return
    end
    scene.state = 'registering'
    CreateThread(function()
        local ok, err = I.Register(scene, src, result)
        if not scenes[scene.id] then return end
        if not ok then
            NZA.Debug('calls: build rejected', scene.id, err)
            scene.state = 'building'
            buildFailed(scene, err)
            return
        end
        scene.state = 'active'
        scene.builtAt = now()
        scene.builder, scene.buildToken = nil, nil
        if NZA.Dispatch and NZA.Dispatch.Update and scene.center then
            pcall(NZA.Dispatch.Update, scene.callId, { coords = scene.center })
        end
        if I.PublishBags then I.PublishBags(scene) end
        pushScene(scene)
        NZA.Bus.Emit('calls:built', scene)
        NZA.Debug('calls: scene built', scene.id, U.tableCount(scene.victims) .. ' patients')
    end)
end)

RegisterNetEvent('nza:calls:buildFailed', function(sceneId, token, reason)
    local src = source
    if not NZA.Core.Rate('calls_built', src, 4, 10000) then return end
    local scene = scenes[sceneId]
    if not scene or scene.state ~= 'building' or scene.builder ~= src or scene.buildToken ~= token then return end
    buildFailed(scene, type(reason) == 'string' and reason:sub(1, 32) or 'client')
end)

-- ════════════════════════════════════════════════════════════════════════
-- REMOVE / CLEANUP
-- ════════════════════════════════════════════════════════════════════════

local DETACH_META = { 'stretcher', 'bed', 'bay', 'vehicle', 'carried', 'escort' }

local function detached(p, scene)
    if not p or not p.meta then return false end
    for _, k in ipairs(DETACH_META) do
        if p.meta[k] ~= nil and p.meta[k] ~= false then return true end
    end
    if scene.center then
        local c = NZA.Core.PatientCoords(p)
        if c and #(c - scene.center) > 45.0 then return true end
    end
    return false
end

local function fadeAndDelete(nets)
    if #nets == 0 then return end
    TriggerClientEvent('nza:calls:fade', -1, nets)
    SetTimeout(1600, function()
        for _, net in ipairs(nets) do I.DeleteNet(net) end
    end)
end
I.FadeAndDelete = fadeAndDelete

-- remove one NPC patient of a scene (hand-over done, released, cleanup)
function I.RemoveVictim(scene, pid, reason, keepEntity)
    local v = scene and scene.victims[pid]
    if not v or v.removed then return end
    v.removed = true
    I.victimIndex[pid] = nil
    local p = NZA.Patients.Get(pid)
    if p then
        if NZA.Transport and NZA.Transport.Release then pcall(NZA.Transport.Release, p) end
        local b = p.meta and p.meta.bed
        if type(b) == 'table' and b.point and NZA.Hospitals and NZA.Hospitals.ReleaseBed then
            pcall(NZA.Hospitals.ReleaseBed, b.point)
        end
        NZA.Patients.Remove(pid, reason or 'calls')
    end
    if not keepEntity then fadeAndDelete({ v.net }) end
end

function C.Remove(id, reason)
    local scene = scenes[id]
    if not scene then return false end
    scenes[id] = nil
    if scene.callId then I.byCall[scene.callId] = nil end
    local e = scene.entities or {}
    local nets = {}
    for _, kind in ipairs({ 'vehicles', 'props', 'bystanders' }) do
        for _, net in pairs(e[kind] or {}) do nets[#nets + 1] = net end
    end
    for pid, v in pairs(scene.victims or {}) do
        if not v.removed then
            local p = NZA.Patients.Get(pid)
            if p and detached(p, scene) and reason ~= 'stop' and reason ~= 'admin' then
                -- taken away from the scene: becomes an orphan, cleaned on hand-over or when left alone
                I.orphans[pid] = { scene = scene, since = now() }
            else
                I.RemoveVictim(scene, pid, reason, true)
                nets[#nets + 1] = v.net
            end
        end
    end
    if reason == 'stop' then
        for _, net in ipairs(nets) do I.DeleteNet(net) end
    else
        fadeAndDelete(nets)
    end
    if scene.callId and NZA.Dispatch and NZA.Dispatch.Get and NZA.Dispatch.Close and reason ~= 'call_closed' then
        local ok, call = pcall(NZA.Dispatch.Get, scene.callId)
        if ok and call and not call.closed then pcall(NZA.Dispatch.Close, scene.callId, 'scene_' .. tostring(reason)) end
    end
    TriggerClientEvent('nza:calls:sceneRemove', -1, id)
    NZA.Bus.Emit('calls:removed', scene, reason)
    NZA.Debug('calls: scene removed', id, reason)
    return true
end

I.orphans = I.orphans or {}

local function closeScene(scene, why)
    if scene.state == 'closing' then return end
    if scene.state ~= 'active' then
        C.Remove(scene.id, why)
        return
    end
    scene.state = 'closing'
    scene.closedAt = now()
    scene.closeWhy = why
    pushScene(scene)
end
I.CloseScene = closeScene

-- hand-over safety net: a call patient lying in a hospital bed (patient.meta.bed, set by the
-- transport module) is handed over even if the bed event was missed
local function bedCheck(pid, v)
    if v.handed or v.released or v.removed or not I.Handover then return end
    local p = NZA.Patients.Get(pid)
    local b = p and p.meta and p.meta.bed
    if type(b) == 'table' and b.point ~= nil then I.Handover(nil, p, b.type or 'bed') end
end

local function lifecycle()
    local sc = cfg('scene')
    local t = now()
    local radius = tonumber(sc.playerRadius) or 90.0
    for _, scene in pairs(scenes) do
        for pid, v in pairs(scene.victims or {}) do bedCheck(pid, v) end
    end
    for pid, o in pairs(I.orphans) do
        local v = o.scene and o.scene.victims and o.scene.victims[pid]
        if v then bedCheck(pid, v) end
    end
    for id, scene in pairs(scenes) do
        if t - scene.created > (tonumber(sc.sceneTimeout) or 2700) then
            if scene.state == 'closing' then
                if t - (scene.closedAt or t) > (tonumber(sc.maxCleanupWait) or 600) then C.Remove(id, 'timeout') end
            else
                closeScene(scene, 'timeout')
                if scenes[id] and scenes[id].state == 'closing' and scene.callId and NZA.Dispatch and NZA.Dispatch.Close then
                    pcall(NZA.Dispatch.Close, scene.callId, 'scene_timeout')
                end
            end
        elseif scene.state == 'active' then
            -- every patient gone (handed over / released / removed) → wrap up
            local left = 0
            for _, v in pairs(scene.victims) do if not v.removed and not v.handed and not v.released then left = left + 1 end end
            if left == 0 then closeScene(scene, 'done') end
            -- effects run out by themselves
            local changed = false
            for _, f in ipairs(scene.fx or {}) do
                if f.on and f.untilAt and t >= f.untilAt then f.on = false; changed = true end
            end
            if changed then pushScene(scene) end
        elseif scene.state == 'closing' then
            local waited = t - (scene.closedAt or t)
            local c = scene.center or vector3(scene.loc.x, scene.loc.y, scene.loc.z)
            if waited >= (tonumber(sc.cleanupDelay) or 45) and (playersNear(c, radius) == 0 or waited >= (tonumber(sc.maxCleanupWait) or 600)) then
                C.Remove(id, scene.closeWhy or 'closed')
            end
        end
    end
    -- patients taken away from their scene and then left alone
    for pid, o in pairs(I.orphans) do
        local p = NZA.Patients.Get(pid)
        if not p then
            I.orphans[pid] = nil
        else
            local c = NZA.Core.PatientCoords(p)
            local alone = not c or playersNear(c, radius) == 0
            if not alone then o.since = t end
            if t - o.since >= (tonumber(sc.orphanTimeout) or 300) then
                I.orphans[pid] = nil
                local v = o.scene.victims[pid]
                if v then
                    I.RemoveVictim(o.scene, pid, 'orphan')
                else
                    NZA.Patients.Remove(pid, 'orphan')
                end
            end
        end
    end
end

-- ════════════════════════════════════════════════════════════════════════
-- GENERATOR
-- ════════════════════════════════════════════════════════════════════════

local function interval(opted)
    local g = cfg('generation')
    local base = I.Range(g.interval or { 240, 540 }) or 360
    local speed = math.min(0.6, math.max(0, (opted - 1)) * (tonumber(g.perMedicSpeedup) or 0.15))
    return math.max(30, math.floor(base * (1 - speed)))
end

local function generatorTick()
    local g = cfg('generation')
    local opted = C.OptedMedics()
    local t = now()
    if #opted < (tonumber(g.minMedics) or 1) then
        nextAt = nil
        noMedicSince = noMedicSince or t
        if t - noMedicSince >= (tonumber(cfg('scene').noMedicTimeout) or 300) then
            for id, scene in pairs(scenes) do
                local hasUnits = false
                if NZA.Dispatch and NZA.Dispatch.Get and scene.callId then
                    local ok, call = pcall(NZA.Dispatch.Get, scene.callId)
                    hasUnits = ok and call and call.units and next(call.units) ~= nil or false
                end
                if not hasUnits and (scene.state == 'pending' or scene.state == 'building') then
                    C.Remove(id, 'no_medics')
                elseif not hasUnits and scene.state == 'active' then
                    closeScene(scene, 'no_medics')
                end
            end
        end
        return
    end
    noMedicSince = nil
    if g.enabled == false then return end
    if not nextAt then
        nextAt = t + (I.Range(g.firstDelay or { 45, 120 }) or 60)
        return
    end
    if t < nextAt then return end
    local cap = math.min(tonumber(g.maxActive) or 3, math.max(1, math.floor(#opted * (tonumber(g.maxPerMedic) or 2))))
    if activeCount() < cap then
        local id, err = C.Create(nil)
        if not id then NZA.Debug('calls: generator could not create a call', err) end
    end
    nextAt = t + interval(#opted)
end

CreateThread(function()
    Wait(5000)
    local lastGen = 0
    while true do
        Wait((next(scenes) ~= nil or next(I.orphans) ~= nil) and 1000 or 2500)
        local busy = next(scenes) ~= nil or next(I.orphans) ~= nil
        if cfg().enabled ~= false then
            local t = now()
            if t - lastGen >= (tonumber(cfg('generation').tick) or 5) then
                lastGen = t
                local ok, err = pcall(generatorTick)
                if not ok then NZA.Warn('calls generator: ' .. tostring(err)) end
            end
            if busy then
                local ok, err = pcall(assignBuilders)
                if not ok then NZA.Warn('calls builders: ' .. tostring(err)) end
                ok, err = pcall(lifecycle)
                if not ok then NZA.Warn('calls lifecycle: ' .. tostring(err)) end
            end
        end
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- BUS
-- ════════════════════════════════════════════════════════════════════════

-- the unit left with one patient (hospital) or cleared while others are still lying there:
-- page the remaining patients again as a follow-up call of the same scene
local REDISPATCH = { hospital = true, cleared = true }

local function redispatch(scene, oldCall)
    if not (NZA.Dispatch and NZA.Dispatch.Create) then return false end
    local remaining, worst = {}, 3
    for pid, v in pairs(scene.victims) do
        if not (v.removed or v.handed or v.released) then
            local p = NZA.Patients.Get(pid)
            if p and not detached(p, scene) and p.state ~= 'dead' then
                remaining[#remaining + 1] = pid
                local ok, tri = pcall(NZA.Patients.Triage, p)
                if ok and tonumber(tri) and tri < worst then worst = tri end
            end
        end
    end
    if #remaining == 0 then return false end
    local tpl = scene.tpl
    local ok, id = pcall(NZA.Dispatch.Create, {
        code = tpl.code or '10-52', priority = worst, title = L(tpl.title or ('calls.t_' .. scene.key)), type = tpl.type or scene.key,
        coords = scene.center or vector3(scene.loc.x, scene.loc.y, scene.loc.z),
        caller = cfg('call').showCaller ~= false and scene.caller.name or nil,
        phone = cfg('call').showCaller ~= false and scene.caller.phone or nil,
        message = L('calls.remaining', #remaining), npc = true, source = 'npc', patients = remaining,
        meta = { scene = scene.id, scenario = scene.key, followUp = oldCall and oldCall.id or true },
    })
    if not ok or not id then return false end
    if scene.callId then I.byCall[scene.callId] = nil end
    scene.callId = id
    I.byCall[id] = scene.id
    NZA.Debug('calls: follow-up call', id, 'for scene', scene.id, #remaining .. ' patients')
    return true
end

NZA.Bus.On('dispatch:closed', function(call, reason)
    if type(call) ~= 'table' then return end
    local id = I.byCall[call.id] or (call.meta and call.meta.scene)
    local scene = id and scenes[id]
    if not scene or (scene.callId and scene.callId ~= call.id) then return end
    if scene.state == 'active' then
        if REDISPATCH[reason] and redispatch(scene, call) then return end
        closeScene(scene, 'call_closed')
    elseif scene.state ~= 'closing' then
        C.Remove(scene.id, 'call_closed')
    end
end)

local function crewMark(call, src)
    if type(call) ~= 'table' then return nil end
    local id = I.byCall[call.id]
    local scene = id and scenes[id]
    src = tonumber(src)
    if scene and src then scene.crewOf[src] = now() end
    return scene
end

NZA.Bus.On('dispatch:respond', function(call, src)
    crewMark(call, src)
end)

NZA.Bus.On('dispatch:status', function(call, src, stage)
    local scene = crewMark(call, src)
    if scene and stage == 'SCN' and not scene.firstArrival then scene.firstArrival = now() end
end)

NZA.Bus.On('patient:removed', function(pid)
    if type(pid) == 'table' then pid = pid.pid end
    local id = I.victimIndex[pid]
    I.orphans[pid] = nil
    if not id then return end
    I.victimIndex[pid] = nil
    local scene = scenes[id]
    local v = scene and scene.victims[pid]
    if v then v.removed = true end
end)

NZA.Bus.On('player:unloaded', function(src)
    for _, scene in pairs(scenes) do
        if scene.builder == src and scene.state == 'building' then buildFailed(scene, 'builder_left') end
        if scene.forceBuilder == src then scene.forceBuilder = nil end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    for _, scene in pairs(scenes) do
        if scene.builder == src and scene.state == 'building' then buildFailed(scene, 'builder_left') end
        if scene.forceBuilder == src then scene.forceBuilder = nil end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(scenes) do pcall(C.Remove, id, 'stop') end
    for pid in pairs(I.orphans) do
        local p = NZA.Patients.Get(pid)
        if p and p.net then I.DeleteNet(p.net) end
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- ADMIN COMMANDS
-- ════════════════════════════════════════════════════════════════════════

local function isAdmin(src)
    if src == 0 then return true end
    return NZA.Core.IsAdmin(src) == true
end

local function reply(src, msg, kind)
    if src == 0 then print('[nayzeee-ambulance] ' .. msg) else notify(src, msg, kind) end
end

CreateThread(function()
    local a = cfg('admin')
    if a.command then
        RegisterCommand(a.command, function(src, args)
            if not isAdmin(src) then return end
            local key = args[1]
            if key == 'here' then key = nil end
            local here = false
            for _, x in ipairs(args) do if x == 'here' then here = true end end
            if key and not (cfg().templates or {})[key] then
                reply(src, L('calls.admin_types', table.concat(C.Templates(), ', ')), 'error')
                return
            end
            local opts = { force = true }
            if here and src > 0 then
                local ped = GetPlayerPed(src)
                local c = GetEntityCoords(ped)
                local h = GetEntityHeading(ped)
                local f = vector3(-math.sin(math.rad(h)), math.cos(math.rad(h)), 0.0) * 12.0
                opts.coords = vector4(c.x + f.x, c.y + f.y, c.z, h)
                opts.buildBy = src
            end
            local id, callOrErr = C.Create(key, opts)
            if id then
                reply(src, L('calls.admin_created', tostring(callOrErr), scenes[id].key), 'success')
            else
                reply(src, L('calls.admin_failed', tostring(callOrErr)), 'error')
            end
        end, false)
    end
    if a.clearCommand then
        RegisterCommand(a.clearCommand, function(src)
            if not isAdmin(src) then return end
            local n = 0
            for id in pairs(scenes) do
                if C.Remove(id, 'admin') then n = n + 1 end
            end
            reply(src, L('calls.admin_cleared', n), 'success')
        end, false)
    end
    if a.listCommand then
        RegisterCommand(a.listCommand, function(src)
            if not isAdmin(src) then return end
            if next(scenes) == nil then
                reply(src, L('calls.admin_none'))
                return
            end
            for id, s in pairs(scenes) do
                local n = 0
                for _, v in pairs(s.victims) do if not v.removed then n = n + 1 end end
                local c = s.center or vector3(s.loc.x, s.loc.y, s.loc.z)
                reply(src, L('calls.admin_row', id, s.key, tostring(s.callId), n, s.state)
                    .. (' @ %.0f %.0f %.0f'):format(c.x, c.y, c.z))
            end
        end, false)
    end
end)
