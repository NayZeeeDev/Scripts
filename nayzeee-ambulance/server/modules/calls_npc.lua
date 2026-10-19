--[[
    NAYZEEE AMBULANCE - NPC calls (server): NPC patients on scene, speech, extrication,
    release on scene, hand-over & rewards, scene effects

    State bags written here (replicated, server only):
      NPC patient ped  'nzaNpc' = { s = scenario, c = sceneId, tr = trapped, pose = hint, dp = damage packs,
                                    wet, esc = escorting medic, rel = released, ho = handed over, veh, seat, sex }
                       (every NPC patient gets it, not only call victims, so every client can animate them)
      bystander ped    'nzaBy'  = { role = 'caller'|'cpr'|'watch', v = victim net, scenario }
    Speech: while an on-duty medic is within Config.Calls.npc.speech.radius of a conscious NPC
    patient, the server picks a line from the patient's real condition (worst injury, bleeding,
    breathing, overdose, cold, trapped, just treated) and sends 'nza:calls:say' to the players
    within speech.subtitles m → subtitle + GTA pain / ambient speech on the ped.

    Callbacks
      nza:calls:extricate (target, phase 'start'|'finish'|'cancel', token) → { ok, token, time } | { ok, veh, seat } | { ok = false, err, msg }
      nza:calls:release (target) → { ok, msg } | { ok = false, err, msg }
    Net events
      C→S nza:calls:fxOut (sceneId, fxId, how 'cut'|'spray'|'smother')
      S→C nza:calls:say ({ net, name, text, ms, sound }) · nza:calls:fade (nets) · nza:calls:released (net)
    Bus listened: transport:bed, hospital:bed, treat:done, proc:done, calls:built
    Bus emitted: calls:handover (scene, p, outcome, amount), calls:released (scene, p)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Calls = NZA.Calls or {}
NZA.Calls.Internal = NZA.Calls.Internal or {}
local C = NZA.Calls
local I = C.Internal
local U = NZA.Util

local lastSig = {}          -- [pid] = bag signature
local nextSay = {}          -- [pid] = os.time() of the next line
local lastTreat = {}        -- [pid] = os.time() of the last treatment (thanks lines)
local byGreeted = {}        -- [net] = times greeted
local extricating = {}      -- [pid] = { src, token, at }
local lineCache = {}        -- [group] = { keys }

local function cfg(section)
    local c = Config.Calls or {}
    if section then return c[section] or {} end
    return c
end

local function npcCfg(section)
    local n = cfg('npc')
    if section then return n[section] or {} end
    return n
end

local function L(key, ...) return NZA.L(key, ...) end
local function now() return os.time() end

local function fail(err, msg)
    return { ok = false, err = err, msg = msg or L('calls.err_' .. err) }
end

local function rate(src, bucket, n, ms)
    return NZA.Core.Rate('calls_' .. bucket, src, n, ms)
end

local function toast(src, msg, kind)
    NZA.Core.Notify(src, msg, kind or 'info')
end

-- ════════════════════════════════════════════════════════════════════════
-- STATE BAGS
-- ════════════════════════════════════════════════════════════════════════

local function npcBag(p)
    local scene, v = C.SceneOf(p.pid)
    local bag = {
        esc = p.meta and p.meta.escort or nil,
        s = (scene and scene.key) or (p.meta and p.meta.scenario) or nil,
        c = scene and scene.id or nil,
        sex = p.sex,
    }
    if v then
        bag.tr = v.trapped or nil
        bag.pose = v.pose
        bag.dp = v.dp
        bag.wet = v.wet
        bag.rel = v.released or nil
        bag.ho = v.handed or nil
        if v.trapped then bag.veh, bag.seat = v.vehicle, v.seat end
    end
    return bag
end

local function pushBag(p, force)
    if not p or p.kind ~= 'npc' or not p.net then return end
    local bag = npcBag(p)
    local sig = json.encode(bag)
    if not force and lastSig[p.pid] == sig then return end
    local ent = I.Ent(p.net)
    if ent == 0 then return end
    Entity(ent).state:set('nzaNpc', bag, true)
    lastSig[p.pid] = sig
end
I.PushBag = pushBag

function I.PublishBags(scene)
    for pid in pairs(scene.victims or {}) do
        local p = NZA.Patients.Get(pid)
        if p then pushBag(p, true) end
    end
    local victimNet = nil
    for _, v in pairs(scene.victims or {}) do
        if v.idx == 1 then victimNet = v.net end
    end
    for idx, net in pairs(scene.entities and scene.entities.bystanders or {}) do
        local spec = scene.plan.bystanders[idx]
        local ent = I.Ent(net)
        if spec and ent ~= 0 then
            Entity(ent).state:set('nzaBy', {
                role = spec.role or 'caller', v = spec.role == 'cpr' and victimNet or nil, scenario = spec.scenario,
            }, true)
        end
    end
end

-- every NPC patient (from calls or any other module) keeps an up-to-date 'nzaNpc' bag
CreateThread(function()
    while true do
        Wait(1000)
        for pid, p in pairs(NZA.Patients.All()) do
            if p.kind == 'npc' then
                local ok, err = pcall(pushBag, p, false)
                if not ok then NZA.Debug('calls: npc bag', pid, err) end
            end
        end
        for pid in pairs(lastSig) do
            if not NZA.Patients.Get(pid) then lastSig[pid] = nil; nextSay[pid] = nil; lastTreat[pid] = nil end
        end
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- SPEECH
-- ════════════════════════════════════════════════════════════════════════

local function lines(group)
    if lineCache[group] then return lineCache[group] end
    local out, prefix = {}, 'calls.say.' .. group .. '_'
    for _, lang in ipairs({ 'en', Config.Locale or 'en' }) do
        for k in pairs(NZA.Locales[lang] or {}) do
            if k:sub(1, #prefix) == prefix then out[k] = true end
        end
    end
    local list = {}
    for k in pairs(out) do list[#list + 1] = k end
    table.sort(list)
    lineCache[group] = list
    return list
end

local function byLines(key)
    local list = {}
    for _, pre in ipairs({ 'calls.by.' .. tostring(key) .. '_', 'calls.by.generic_' }) do
        for k in pairs(NZA.Locales.en or {}) do
            if k:sub(1, #pre) == pre then list[#list + 1] = k end
        end
    end
    table.sort(list)
    return list
end

local LEG = { l_upper_leg = true, r_upper_leg = true, l_lower_leg = true, r_lower_leg = true, pelvis = true }
local ARM = { l_upper_arm = true, r_upper_arm = true, l_lower_arm = true, r_lower_arm = true }

-- what this patient would complain about right now → group, sound kind
local function speechGroup(p, v, sceneKey)
    if p.state == 'dead' or p.state == 'arrest' then return nil end
    local avpu = p.vitals and p.vitals.avpu or 'A'
    if avpu == 'P' or avpu == 'U' then return false, 'groan' end
    local t = now()
    if lastTreat[p.pid] and t - lastTreat[p.pid] < 25 and math.random() < 0.5 then
        return math.random() < 0.5 and 'thanks' or 'calm', 'thanks'
    end
    if v and v.trapped then return 'trapped', 'pain' end
    local cond = p.conditions or {}
    if cond.overdose and p.state == 'alive' then return 'od', 'confused' end
    if (cond.hypoxia or cond.airway or cond.pneumothorax or cond.haemothorax) and math.random() < 0.6 then return 'breath', 'pain' end
    if cond.hypothermia and math.random() < 0.6 then return 'cold', 'pain' end
    if cond.concussion and math.random() < 0.45 then return 'head', 'confused' end
    -- worst open injury
    local worst
    for _, inj in pairs(p.injuries or {}) do
        if inj.status == 'open' or inj.status == 'controlled' then
            if not worst or (inj.severity or 0) > (worst.severity or 0) then worst = inj end
        end
    end
    local bleed = tonumber(p.bleedTotal) or 0
    if bleed <= 0 then
        for _, inj in pairs(p.injuries or {}) do bleed = bleed + (tonumber(inj.bleed) or 0) end
    end
    if bleed >= 25 and math.random() < 0.6 then return 'bleed', 'pain' end
    if worst then
        if worst.type == 'burn' then return 'burn', 'pain' end
        if worst.type == 'fracture' and LEG[worst.region] then
            if (tonumber(p.age) or 30) >= 68 and (worst.region == 'l_upper_leg' or worst.region == 'r_upper_leg' or worst.region == 'pelvis') then
                return 'hip', 'pain'
            end
            return 'leg', 'pain'
        end
        if worst.type == 'fracture' and ARM[worst.region] then return 'arm', 'pain' end
        if worst.region == 'chest' then return 'chest', 'pain' end
        if worst.region == 'abdomen' or worst.type == 'internal' then return 'belly', 'pain' end
        if (sceneKey == 'gunshot' or sceneKey == 'stabbing') and math.random() < 0.3 then return 'scared', 'scared' end
        return 'pain', 'pain'
    end
    if p.stabilized or (tonumber(p.pain) or 0) < 20 then return 'calm', nil end
    return 'pain', 'pain'
end

local function sendSay(coords, radius, data)
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        local c = I.SrcCoords(src)
        if c and #(c - coords) <= radius then TriggerClientEvent('nza:calls:say', src, data) end
    end
end

local function speechTick()
    local sp = npcCfg('speech')
    if sp.enabled == false then return end
    local medics = sp.medicOnly ~= false and I.Medics() or {}
    if sp.medicOnly == false then
        for _, id in ipairs(GetPlayers()) do
            local c = I.SrcCoords(tonumber(id))
            if c then medics[#medics + 1] = { src = tonumber(id), coords = c } end
        end
    end
    if #medics == 0 then return end
    local radius = tonumber(sp.radius) or 6.0
    local subRadius = tonumber(sp.subtitles) or 10.0
    local t = now()
    for pid, p in pairs(NZA.Patients.All()) do
        if p.kind == 'npc' and p.net and (nextSay[pid] or 0) <= t then
            local c = NZA.Core.PatientCoords(p)
            local near = false
            if c then
                for _, m in ipairs(medics) do
                    if #(m.coords - c) <= radius then near = true break end
                end
            end
            if near then
                local sc, v = C.SceneOf(pid)
                local group, sound = speechGroup(p, v, sc and sc.key or (p.meta and p.meta.scenario))
                nextSay[pid] = t + (I.Range(sp.interval or { 9, 18 }) or 12)
                if group ~= nil then
                    local key = group and I.Pick(lines(group)) or nil
                    sendSay(c, subRadius, {
                        net = p.net, name = p.name, text = key and L(key) or nil, ms = tonumber(sp.ms) or 3800,
                        sound = sp.sounds ~= false and sound or nil,
                    })
                end
            else
                nextSay[pid] = t + 2
            end
        end
    end
end

-- bystanders: greet the first medic, the CPR bystander steps back when a medic takes over
local function bystanderTick()
    local medics = nil
    for _, scene in pairs(I.scenes) do
        if scene.state == 'active' and scene.entities then
            for idx, net in pairs(scene.entities.bystanders or {}) do
                local ent = I.Ent(net)
                if ent ~= 0 then
                    medics = medics or I.Medics()
                    local c = GetEntityCoords(ent)
                    local spec = scene.plan.bystanders[idx] or {}
                    local bag = Entity(ent).state.nzaBy
                    local closest = math.huge
                    for _, m in ipairs(medics) do
                        local d = #(m.coords - c)
                        if d < closest then closest = d end
                    end
                    if type(bag) == 'table' and bag.role == 'cpr' and closest <= 4.0 then
                        Entity(ent).state:set('nzaBy', { role = 'watch', v = bag.v, scenario = 'WORLD_HUMAN_STAND_IMPATIENT' }, true)
                    end
                    local greeted = byGreeted[net] or 0
                    if spec.role ~= 'onlooker' and closest <= 5.0 and greeted < 2 and (greeted == 0 or math.random() < 0.15) then
                        byGreeted[net] = greeted + 1
                        local key = I.Pick(byLines(scene.key))
                        if key then
                            sendSay(c, 12.0, { net = net, name = scene.caller and scene.caller.name or nil, text = L(key), ms = 4200, sound = 'shout', by = true })
                        end
                        if spec.role == 'caller' and greeted == 0 then
                            Entity(ent).state:set('nzaBy', { role = 'watch', scenario = 'WORLD_HUMAN_STAND_IMPATIENT', wave = true }, true)
                        end
                    end
                end
            end
        end
    end
    for net in pairs(byGreeted) do
        if I.Ent(net) == 0 then byGreeted[net] = nil end
    end
end

CreateThread(function()
    while true do
        Wait(1500)
        local ok, err = pcall(speechTick)
        if not ok then NZA.Warn('calls speech: ' .. tostring(err)) end
        if next(I.scenes) ~= nil then
            ok, err = pcall(bystanderTick)
            if not ok then NZA.Warn('calls bystanders: ' .. tostring(err)) end
        end
    end
end)

-- ════════════════════════════════════════════════════════════════════════
-- TREATMENTS (crew + procedure count + "thank you")
-- ════════════════════════════════════════════════════════════════════════

local function treated(src, p)
    if type(p) ~= 'table' or p.kind ~= 'npc' then return end
    lastTreat[p.pid] = now()
    local _, v = C.SceneOf(p.pid)
    if not v then
        local o = I.orphans[p.pid]
        v = o and o.scene and o.scene.victims[p.pid] or nil
    end
    if v then
        v.procedures = (v.procedures or 0) + 1
        src = tonumber(src)
        if src and src > 0 then v.crew[src] = now() end
    end
end

NZA.Bus.On('treat:done', function(src, p) treated(src, p) end)
NZA.Bus.On('proc:done', function(src, p) treated(src, p) end)

-- ════════════════════════════════════════════════════════════════════════
-- REWARDS
-- ════════════════════════════════════════════════════════════════════════

local function isMedic(src)
    local rec = NZA.Staff.Get(src)
    return type(rec) == 'table' and rec.medic == true
end

local function societyFor(src)
    local soc = cfg('rewards').society or {}
    if soc.name then return soc.name end
    local rec = src and NZA.Staff.Get(src)
    if rec and rec.dept and NZA.Hospitals and NZA.Hospitals.Society then
        local ok, name = pcall(NZA.Hospitals.Society, rec.dept)
        if ok and type(name) == 'string' and name ~= '' then return name end
    end
    return Config.Billing and Config.Billing.society or 'ambulance'
end

function I.Reward(scene, v, p, mult, bySrc)
    local r = cfg('rewards')
    if r.enabled == false then return 0 end
    local base = (r.base or {})[v.triage or 2] or 600
    local amount = base * (tonumber(mult) or 1.0) * (tonumber(scene.tpl.reward) or 1.0)
    amount = amount + math.min(tonumber(r.maxProcedureBonus) or 600, (tonumber(r.perProcedure) or 60) * (v.procedures or 0))
    local fr = r.fastResponse
    if type(fr) == 'table' and scene.firstArrival and scene.firstArrival - scene.created <= (tonumber(fr.within) or 300) then
        amount = amount + (tonumber(fr.amount) or 0)
    end
    amount = math.floor(amount)
    if amount <= 0 then return 0 end

    local t = now()
    local window = tonumber(r.crewTimeout) or 1800
    local set, crew = {}, {}
    local function add(src)
        src = tonumber(src)
        if src and src > 0 and not set[src] and NZA.Core.Online(src) and isMedic(src) then
            set[src] = true
            crew[#crew + 1] = src
        end
    end
    add(bySrc)
    for src, at in pairs(v.crew or {}) do if t - at <= window then add(src) end end
    for src, at in pairs(scene.crewOf or {}) do if t - at <= window then add(src) end end
    if #crew == 0 then return 0 end

    local share = amount
    if r.split ~= 'each' then share = math.max(tonumber(r.minShare) or 0, math.floor(amount / #crew)) end
    local reason = L('calls.reward_reason')
    for _, src in ipairs(crew) do
        I.Bridge('AddMoney', src, r.account or 'bank', share, reason)
        if cfg('handover').notify ~= false then
            toast(src, { title = L(scene.tpl.title or ('calls.t_' .. scene.key)),
                message = L('calls.reward', p.name or '?', share), type = 'success', duration = 6000, icon = 'cash' })
        end
    end
    local soc = r.society or {}
    if soc.enabled ~= false and (tonumber(soc.cut) or 0) > 0 then
        local cut = math.floor(amount * tonumber(soc.cut))
        if cut > 0 then
            I.Bridge('Society.Add', societyFor(bySrc or crew[1]), cut)
            if cfg('handover').notify ~= false then toast(bySrc or crew[1], L('calls.reward_society', cut), 'info') end
        end
    end
    return amount
end

-- ════════════════════════════════════════════════════════════════════════
-- HAND-OVER (patient placed on a hospital bed)
-- ════════════════════════════════════════════════════════════════════════

local function findVictim(pid)
    local scene, v = C.SceneOf(pid)
    if v then return scene, v end
    local o = I.orphans[pid]
    if o and o.scene and o.scene.victims[pid] then return o.scene, o.scene.victims[pid] end
    return nil
end

local function handover(src, p, pointType)
    local scene, v = findVictim(p.pid)
    if not v or v.handed or v.released or v.removed then return end
    local types = cfg('handover').types or { bed = true }
    if not types[pointType] then return end
    v.handed = true
    v.handedAt = now()
    local r = cfg('rewards')
    local mult = (r.outcome or {})[p.state] or 0.5
    local amount = I.Reward(scene, v, p, mult, src)
    pushBag(p, true)
    if src and tonumber(src) and cfg('handover').notify ~= false then toast(src, L('calls.handover', p.name or '?'), 'success') end
    NZA.Bus.Emit('calls:handover', scene, p, p.state, amount)
    -- the patient stays in the bed so the crew can finish treatment and release them; this is
    -- only the safety net for one nobody releases
    local pid = p.pid
    SetTimeout(math.max(30, tonumber(cfg('handover').despawnDelay) or 900) * 1000, function()
        local cur = NZA.Patients.Get(pid)
        if not cur or v.released then return end
        I.orphans[pid] = nil
        I.RemoveVictim(scene, pid, 'handover')
    end)
end

I.Handover = handover

NZA.Bus.On('transport:bed', function(src, p, pt)
    if type(p) ~= 'table' or p.kind ~= 'npc' or type(pt) ~= 'table' then return end
    handover(src, p, pt.type)
end)

NZA.Bus.On('hospital:bed', function(pointId, pid, on)
    if not on then return end
    local p = NZA.Patients.Get(pid)
    if not p or p.kind ~= 'npc' then return end
    local b = p.meta and p.meta.bed
    local t = type(b) == 'table' and b.type or 'bed'
    handover(nil, p, t)
end)

-- ════════════════════════════════════════════════════════════════════════
-- RELEASE ON SCENE (walking wounded who need no hospital)
-- ════════════════════════════════════════════════════════════════════════

local function releasable(p)
    if p.state ~= 'alive' then return false end
    for _, inj in pairs(p.injuries or {}) do
        if inj.status == 'open' then return false end
        if inj.type == 'fracture' and not (inj.treat and (inj.treat.splinted or inj.treat.cast)) then return false end
    end
    for name, val in pairs(p.conditions or {}) do
        if not (name == 'concussion' and type(val) == 'table' and (tonumber(val.grade) or 1) <= 1) then return false end
    end
    return true
end

C.Releasable = releasable   -- core/care.lua: 'Release on scene' step

lib.callback.register('nza:calls:release', function(src, target)
    local rc = npcCfg('release')
    if rc.enabled == false then return fail('state') end
    if not rate(src, 'release', 3, 5000) then return fail('rate') end
    if not NZA.Staff.Can(src, rc.perm or 'assess') then return fail('perm') end
    local p = NZA.Patients.Resolve(target)
    if not p or p.kind ~= 'npc' then return fail('state', L('calls.scene_unknown')) end
    local scene, v = findVictim(p.pid)
    if not v or v.released then return fail('state', L('calls.scene_unknown')) end
    if NZA.Core.DistanceTo(src, p) > 4.0 then return fail('far') end
    if not releasable(p) then return fail('state', L('calls.release_fail')) end
    v.released = true
    -- handed over at the hospital: already paid at the hand-over, this is the discharge
    if not v.handed then I.Reward(scene, v, p, tonumber(cfg('rewards').released) or 0.55, src) end
    if NZA.Patients.SetMeta then pcall(NZA.Patients.SetMeta, p, 'escort', nil) end
    -- off the bed / stretcher / seat first: the transport module stands them up beside it
    local m = p.meta or {}
    local held = m.bed ~= nil or m.inBed ~= nil or m.stretcher ~= nil or m.carried ~= nil or m.bay ~= nil or m.vehicle ~= nil
    local T = NZA.Transport
    if held and T and type(T.Free) == 'function' then pcall(T.Free, p) end
    pushBag(p, true)
    local net = p.net
    if held then
        SetTimeout(2500, function() TriggerClientEvent('nza:calls:released', -1, net) end)
    else
        TriggerClientEvent('nza:calls:released', -1, net)
    end
    NZA.Bus.Emit('calls:released', scene, p)
    local pid = p.pid
    SetTimeout(math.max(5, tonumber(rc.walkTime) or 25) * 1000 + (held and 2500 or 0), function()
        if NZA.Patients.Get(pid) then
            I.orphans[pid] = nil
            I.RemoveVictim(scene, pid, 'released')
        end
    end)
    return { ok = true, msg = L('calls.released', p.name or '?') }
end)

-- ════════════════════════════════════════════════════════════════════════
-- EXTRICATION (trapped in a crashed car / pinned under a load)
-- ════════════════════════════════════════════════════════════════════════

lib.callback.register('nza:calls:extricate', function(src, target, phase, token)
    local ec = cfg('extricate')
    if ec.enabled == false then return fail('state') end
    if not rate(src, 'extricate', 6, 5000) then return fail('rate') end
    local p = NZA.Patients.Resolve(target)
    if not p or p.kind ~= 'npc' then return fail('state', L('calls.scene_unknown')) end
    local scene, v = findVictim(p.pid)
    if not v or not v.trapped then return fail('state') end
    local t = now()
    if phase == 'cancel' then
        local e = extricating[p.pid]
        if e and e.src == src then extricating[p.pid] = nil end
        return { ok = true }
    end
    if not NZA.Staff.Can(src, ec.perm or 'transport') then return fail('perm') end
    if NZA.Core.DistanceTo(src, p) > (tonumber(ec.distance) or 2.6) + 2.0 then return fail('far') end
    local time = tonumber(ec.time) or 12
    if phase == 'start' then
        local e = extricating[p.pid]
        if e and e.src ~= src and NZA.Core.Online(e.src) and t - e.at < time + 10 then return fail('busy') end
        local tok = ('%d-%d'):format(math.random(100000, 999999), GetGameTimer())
        extricating[p.pid] = { src = src, token = tok, at = t }
        return { ok = true, token = tok, time = time }
    end
    if phase == 'finish' then
        local e = extricating[p.pid]
        if not e or e.src ~= src or e.token ~= token then return fail('state') end
        if t - e.at + 1 < time then return fail('state') end
        extricating[p.pid] = nil
        v.trapped = false
        if NZA.Patients.SetMeta then pcall(NZA.Patients.SetMeta, p, 'trapped', nil) end
        pushBag(p, true)
        I.PushScene(scene)
        v.crew[src] = t
        v.procedures = (v.procedures or 0) + 1
        return { ok = true, veh = v.vehicle, seat = v.seat, breakDoor = ec.breakDoor ~= false, msg = L('calls.extricated', p.name or '?') }
    end
    return fail('state')
end)

-- ════════════════════════════════════════════════════════════════════════
-- SCENE EFFECTS (cut the engine, extinguish, smother)
-- ════════════════════════════════════════════════════════════════════════

local function fxCoords(fx)
    if fx.net then
        local ent = I.Ent(fx.net)
        if ent ~= 0 then return GetEntityCoords(ent) end
        return nil
    end
    if fx.at then return vector3(fx.at.x, fx.at.y, fx.at.z) end
    return nil
end

local HOW_KINDS = {
    cut = { smoke = true },
    spray = { fire = true, groundFire = true, groundSmoke = true, smoke = true },
    smother = { fire = true, groundFire = true, groundSmoke = true },
}

RegisterNetEvent('nza:calls:fxOut', function(sceneId, fxId, how)
    local src = source
    if not rate(src, 'fx', 6, 4000) then return end
    local scene = I.scenes[sceneId]
    if not scene or (scene.state ~= 'active' and scene.state ~= 'closing') then return end
    local fx
    for _, f in ipairs(scene.fx or {}) do if f.id == fxId then fx = f end end
    if not fx or not fx.on or not HOW_KINDS[how] or not HOW_KINDS[how][fx.kind] then return end
    local fc = cfg('fx')
    local maxD
    if how == 'cut' then
        maxD = (tonumber((fc.cutEngine or {}).distance) or 3.2) + 3.0
        -- the engine can't be reached while it's still burning
        for _, f in ipairs(scene.fx) do
            if f.on and f.kind == 'fire' and f.net == fx.net then return end
        end
    elseif how == 'spray' then
        maxD = (tonumber((fc.spray or {}).distance) or 9.0) + 3.0
        local weapon = joaat((fc.spray or {}).weapon or 'WEAPON_FIREEXTINGUISHER')
        local ok, cur = pcall(GetSelectedPedWeapon, GetPlayerPed(src))
        if ok and cur and cur ~= 0 and cur ~= weapon and (cur + 4294967296) ~= weapon and cur ~= (weapon + 4294967296) then return end
    else
        if fc.fireNeedsExtinguisher ~= false and (fx.kind == 'fire' or fx.kind == 'groundFire') then return end
        maxD = (tonumber((fc.smother or {}).distance) or 2.6) + 3.0
    end
    local at = fxCoords(fx)
    local me = I.SrcCoords(src)
    if not at or not me or #(at - me) > maxD then return end
    fx.on = false
    -- a car fire that is out leaves the smoke; cutting the engine afterwards clears it
    if how == 'spray' and fx.kind == 'groundFire' then
        for _, f in ipairs(scene.fx) do
            if f.on and f.kind == 'groundSmoke' and not f.net then f.untilAt = math.min(f.untilAt or math.huge, now() + 20) end
        end
    end
    I.PushScene(scene)
    toast(src, L(how == 'cut' and 'calls.engine_cut' or 'calls.fire_out'), 'success')
end)

-- ════════════════════════════════════════════════════════════════════════
-- HOUSEKEEPING
-- ════════════════════════════════════════════════════════════════════════

NZA.Bus.On('patient:removed', function(pid)
    if type(pid) == 'table' then pid = pid.pid end
    if type(pid) ~= 'string' then return end
    extricating[pid] = nil
end)

AddEventHandler('playerDropped', function()
    local src = source
    for pid, e in pairs(extricating) do
        if e.src == src then extricating[pid] = nil end
    end
end)
