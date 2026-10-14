--[[
    NAYZEEE AMBULANCE - NPC calls (server): scene plans & built-entity registration

    Pure planning from a Config.Calls template (nothing here touches the world):
      NZA.Calls.Internal.Plan(key, tpl, loc, opts) → plan
          plan.victims[i]    = { idx, model, sex, age, offset | vehicle + seat, heading, pose, state, loss,
                                 injuries = { def }, conditions = { name = value }, trapped, dp (damage packs), wet }
          plan.vehicles[i]   = { idx, model, offset, heading, damage, windows, doors, tyres, smoke, fire }
          plan.props[i]      = { idx, model, offset, rot, fx }
          plan.bystanders[i] = { idx, model, sex, offset, heading, scenario, role, victim }
          plan.fx[i]         = { id, kind, vehicle | prop | offset }
      I.PublicPlan(scene)  → what the building client needs (no injuries / conditions)
      I.Register(scene, src, result) → validates the entities the client built and turns the
                                       victims into NPC patients (NZA.Patients.CreateNPC)
      I.Ent(net) / I.DeleteNet(net) / I.KeepEntity(ent)

    Called at runtime only by server/modules/calls.lua (never at load time).
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Calls = NZA.Calls or {}
NZA.Calls.Internal = NZA.Calls.Internal or {}
local I = NZA.Calls.Internal
local U = NZA.Util
I.victimIndex = I.victimIndex or {}     -- [pid] = scene id

local function cfg(section)
    local c = Config.Calls or {}
    if section then return c[section] or {} end
    return c
end

-- ════════════════════════════════════════════════════════════════════════
-- RANDOM HELPERS
-- ════════════════════════════════════════════════════════════════════════

local function pick(list)
    if type(list) ~= 'table' or #list == 0 then return nil end
    return list[math.random(#list)]
end
I.Pick = pick

-- {a, b} → random number (integers stay integers); a plain number is returned as is
local function range(v, float)
    if type(v) ~= 'table' then return v end
    local a, b = tonumber(v[1]), tonumber(v[2] or v[1])
    if not a or not b then return nil end
    if a > b then a, b = b, a end
    if not float and math.type(a) == 'integer' and math.type(b) == 'integer' then
        return math.random(a, b)
    end
    return a + (b - a) * math.random()
end
I.Range = range

local function isRange(v)
    return type(v) == 'table' and #v == 2 and type(v[1]) == 'number' and type(v[2]) == 'number'
end

local function v3(v, dx, dy, dz)
    if not v then return vector3(dx or 0.0, dy or 0.0, dz or 0.0) end
    return vector3((v.x or v[1] or 0.0) + 0.0, (v.y or v[2] or 0.0) + 0.0, (v.z or v[3] or 0.0) + 0.0)
end

local function packV(v)
    if not v then return nil end
    return { x = U.round(v.x or 0.0, 3), y = U.round(v.y or 0.0, 3), z = U.round(v.z or 0.0, 3), w = v.w and U.round(v.w, 1) or nil }
end
I.PackV = packV

local function modelsOf(pool, poolsTable)
    if type(pool) == 'table' then return pool end
    if type(pool) == 'string' then
        local list = poolsTable[pool]
        if type(list) == 'table' then return list end
        return { pool }
    end
    return nil
end

local function pedModel(peds, sex)
    local pools = cfg().pools or {}
    peds = peds or {}
    local list = modelsOf(peds[sex], pools) or modelsOf(peds.m, pools) or modelsOf(sex == 'f' and 'civ_f' or 'civ_m', pools)
    return pick(list) or (sex == 'f' and 'a_f_y_hipster_01' or 'a_m_y_hipster_01')
end
I.PedModel = pedModel

-- ════════════════════════════════════════════════════════════════════════
-- INJURIES & CONDITIONS FROM A ROLE
-- ════════════════════════════════════════════════════════════════════════

local INJURY_SKIP = { type = true, regions = true, sev = true, chance = true, count = true }

local function buildInjuries(role)
    local out = {}
    local seen = {}
    for _, spec in ipairs(type(role.injuries) == 'table' and role.injuries or {}) do
        if type(spec) == 'table' and spec.type and NZA.Const.InjuryTypes[spec.type]
            and math.random() <= (tonumber(spec.chance) or 1.0) then
            local n = range(spec.count or { 1, 1 }) or 1
            for _ = 1, math.max(1, math.min(4, n)) do
                local regions = {}
                for _, r in ipairs(spec.regions or {}) do
                    if NZA.Const.Region[r] and not seen[r .. ':' .. spec.type] then regions[#regions + 1] = r end
                end
                local region = pick(regions)
                if not region then break end
                seen[region .. ':' .. spec.type] = true
                local def = { region = region, type = spec.type, severity = U.clamp(range(spec.sev or { 2, 2 }) or 2, 1, 4) }
                for k, v in pairs(spec) do
                    if not INJURY_SKIP[k] then def[k] = U.deepcopy(v) end
                end
                out[#out + 1] = def
            end
        end
    end
    return out
end
I.BuildInjuries = buildInjuries

local COND_SKIP = { chance = true, onlyIfState = true }

local function buildConditions(role, state)
    local out = {}
    for name, spec in pairs(type(role.conditions) == 'table' and role.conditions or {}) do
        if NZA.Const.Conditions[name] then
            local ok = true
            if type(spec) == 'table' then
                if spec.onlyIfState and spec.onlyIfState ~= state then ok = false end
                if ok and spec.chance and math.random() > (tonumber(spec.chance) or 1.0) then ok = false end
            end
            if ok then
                local val = {}
                if type(spec) == 'table' then
                    for k, v in pairs(spec) do
                        if not COND_SKIP[k] then
                            if isRange(v) then
                                local r = range(v, k == 'temp')
                                val[k] = (k == 'temp') and U.round(r, 1) or r
                            else
                                val[k] = U.deepcopy(v)
                            end
                        end
                    end
                end
                out[name] = val
            end
        end
    end
    if state == 'arrest' and not out.arrest then out.arrest = { rhythm = 'vf' } end
    if state ~= 'arrest' then out.arrest = nil end
    return out
end
I.BuildConditions = buildConditions

-- pose hint for the NPC behaviour (state + what the template says)
local function poseFor(role, state, conditions)
    if state == 'arrest' then return 'arrest' end
    if state == 'dead' then return 'dead' end
    if role.pose then return role.pose end
    if conditions and conditions.overdose then return 'overdose' end
    return state == 'alive' and 'sit' or 'writhe'
end

-- ════════════════════════════════════════════════════════════════════════
-- PLAN
-- ════════════════════════════════════════════════════════════════════════

function I.Plan(key, tpl, loc, opts)
    opts = opts or {}
    local plan = { key = key, vehicles = {}, victims = {}, props = {}, bystanders = {}, fx = {} }
    local vehPools = cfg().vehiclePools or {}
    local now = os.time()

    -- vehicles
    for _, spec in ipairs(type(tpl.vehicles) == 'table' and tpl.vehicles or {}) do
        if math.random() <= (tonumber(spec.chance) or 1.0) then
            local model = pick(spec.models) or pick(modelsOf(spec.pool, vehPools))
            if model then
                local idx = #plan.vehicles + 1
                plan.vehicles[idx] = {
                    idx = idx, model = model, offset = packV(v3(spec.offset)), heading = tonumber(spec.heading) or 0.0,
                    damage = U.deepcopy(spec.damage or {}), windows = U.deepcopy(spec.windows or {}), doors = U.deepcopy(spec.doors or {}),
                    tyres = tonumber(spec.tyres) or 0.0,
                    smoke = math.random() <= (tonumber(spec.smoke) or 0.0),
                    fire = math.random() <= (tonumber(spec.fire) or 0.0),
                    flip = spec.flip == true,
                }
            end
        end
    end
    local function vehicleFor(idx)
        return idx and plan.vehicles[idx] or nil
    end

    -- victims
    local maxV = tonumber(tpl.maxVictims) or 6
    local seats = {}
    for _, role in ipairs(type(tpl.victims) == 'table' and tpl.victims or {}) do
        if math.random() <= (tonumber(role.chance) or 1.0) then
            local n = range(role.count or { 1, 1 }) or 1
            for k = 1, n do
                if #plan.victims >= maxV then break end
                local sex = math.random() < (tonumber(role.female) or 0.4) and 'f' or 'm'
                local state = U.weightedPick(role.state or { wounded = 1 }) or 'wounded'
                local conditions = buildConditions(role, state)
                local injuries = buildInjuries(role)
                local idx = #plan.victims + 1
                local v = {
                    idx = idx, model = pedModel(role.peds, sex), sex = sex,
                    age = range(role.age or { 18, 70 }) or 30,
                    state = state, loss = U.round(range(role.loss or { 0.0, 0.0 }, true) or 0.0, 3),
                    conditions = conditions, injuries = injuries,
                    dp = U.deepcopy(role.damagePacks), wet = tpl.wet == true or nil,
                }
                v.pose = poseFor(role, state, conditions)
                local veh = vehicleFor(role.vehicle)
                local seat = tonumber(role.seat) or -1
                if veh and not seats[veh.idx .. ':' .. seat] then
                    seats[veh.idx .. ':' .. seat] = true
                    v.vehicle, v.seat = veh.idx, seat
                    v.trapped = math.random() <= (tonumber(role.trapped) or 0.0)
                    if not v.trapped and state ~= 'alive' then
                        -- not trapped: thrown / climbed out next to the car
                        v.vehicle, v.seat = nil, nil
                        v.offset = packV(v3(veh.offset, (seat == -1 and -2.0 or 2.0), 1.2 + k * 0.6, 0.0))
                        v.heading = math.random(0, 359) + 0.0
                    end
                else
                    local off = v3(role.offset)
                    if k > 1 then off = off + vector3(math.random() * 2.4 - 1.2, 1.4 * (k - 1), 0.0) end
                    v.offset = packV(off)
                    v.heading = (tonumber(role.heading) or math.random(0, 359)) + 0.0
                    -- a "trapped" role without a car is pinned under the props (crush)
                    v.trapped = role.vehicle == nil and math.random() <= (tonumber(role.trapped) or 0.0) or nil
                end
                if v.trapped and v.state == 'alive' then v.state = 'wounded' end
                if v.vehicle and v.trapped then v.pose = 'trapped' end
                plan.victims[idx] = v
            end
        end
    end
    -- always at least one victim
    if #plan.victims == 0 and type(tpl.victims) == 'table' and tpl.victims[1] then
        local role = tpl.victims[1]
        local sex = math.random() < (tonumber(role.female) or 0.4) and 'f' or 'm'
        local state = 'wounded'
        local conditions = buildConditions(role, state)
        plan.victims[1] = {
            idx = 1, model = pedModel(role.peds, sex), sex = sex, age = range(role.age or { 18, 70 }) or 30,
            state = state, loss = 0.05, conditions = conditions, injuries = buildInjuries(role),
            offset = packV(v3(role.offset)), heading = math.random(0, 359) + 0.0, pose = poseFor(role, state, conditions),
            dp = U.deepcopy(role.damagePacks), wet = tpl.wet == true or nil,
        }
    end

    -- props
    local maxProps = tonumber(cfg('scene').maxProps) or 10
    for _, spec in ipairs(type(tpl.props) == 'table' and tpl.props or {}) do
        if #plan.props >= maxProps then break end
        if math.random() <= (tonumber(spec.chance) or 1.0) then
            local model = pick(spec.models)
            if model then
                local idx = #plan.props + 1
                plan.props[idx] = { idx = idx, model = model, offset = packV(v3(spec.offset)), rot = packV(v3(spec.rot)), fx = spec.fx }
            end
        end
    end

    -- effects (smoke / fire)
    local fxCfg = cfg('fx')
    local function until_()
        return now + (range(fxCfg.duration or { 420, 720 }) or 600)
    end
    for _, veh in ipairs(plan.vehicles) do
        if veh.fire then
            plan.fx[#plan.fx + 1] = { id = #plan.fx + 1, kind = 'fire', vehicle = veh.idx, untilAt = until_() }
        end
        if veh.smoke or veh.fire then
            plan.fx[#plan.fx + 1] = { id = #plan.fx + 1, kind = 'smoke', vehicle = veh.idx, untilAt = until_() }
        end
    end
    for _, pr in ipairs(plan.props) do
        if pr.fx and fxCfg[pr.fx] then
            plan.fx[#plan.fx + 1] = { id = #plan.fx + 1, kind = pr.fx, prop = pr.idx, untilAt = until_() }
        end
    end
    for _, spec in ipairs(type(tpl.fx) == 'table' and tpl.fx or {}) do
        if fxCfg[spec.kind] and math.random() <= (tonumber(spec.chance) or 1.0) then
            plan.fx[#plan.fx + 1] = { id = #plan.fx + 1, kind = spec.kind, offset = packV(v3(spec.offset)), untilAt = until_() }
        end
    end

    -- bystander / 911 caller (same sex as the recorded caller)
    local by = tpl.bystander
    if cfg('scene').bystanders ~= false and type(by) == 'table' then
        local sex = opts.callerSex or (math.random() < 0.5 and 'f' or 'm')
        local pools = cfg().pools or {}
        local poolName
        if sex == 'f' then poolName = by.poolF or 'civ_f' else poolName = by.pool or 'civ_m' end
        local list = modelsOf(poolName, pools)
        local role, scenario, offset = by.role or 'caller', by.scenario, v3(by.offset)
        local first = plan.victims[1]
        if by.onlyIfState and not (first and first.state == by.onlyIfState) then
            role, scenario = 'caller', 'WORLD_HUMAN_STAND_MOBILE'
            offset = offset + vector3(1.6, 1.2, 0.0)
        end
        if role == 'cpr' and not (first and first.state == 'arrest' and not first.vehicle) then
            role, scenario = 'caller', 'WORLD_HUMAN_STAND_MOBILE'
            offset = offset + vector3(1.6, 1.2, 0.0)
        end
        plan.bystanders[1] = {
            idx = 1, model = pick(list) or (sex == 'f' and 'a_f_y_hipster_01' or 'a_m_y_hipster_01'), sex = sex,
            offset = packV(offset), heading = tonumber(by.heading), scenario = scenario or 'WORLD_HUMAN_STAND_MOBILE',
            role = role, victim = role == 'cpr' and 1 or nil,
        }
    end
    return plan
end

-- what the building client gets (no medical data)
function I.PublicPlan(scene)
    local plan, tpl = scene.plan, scene.tpl
    local out = {
        id = scene.id, key = scene.key, token = scene.buildToken,
        loc = packV(scene.loc), snap = tpl.snap or 'ped', roadside = tonumber(tpl.roadside) or 3.5,
        hazard = cfg('scene').hazardLights ~= false,
        modelTimeout = tonumber(cfg('scene').modelTimeout) or 8000,
        vehicles = {}, victims = {}, props = {}, bystanders = {},
        engineSmoke = cfg('fx').engineSmoke ~= false,
    }
    for _, v in ipairs(plan.vehicles) do
        out.vehicles[#out.vehicles + 1] = {
            idx = v.idx, model = v.model, offset = v.offset, heading = v.heading, damage = v.damage, windows = v.windows,
            doors = v.doors, tyres = v.tyres, smoke = v.smoke or v.fire, flip = v.flip,
        }
    end
    for _, v in ipairs(plan.victims) do
        out.victims[#out.victims + 1] = {
            idx = v.idx, model = v.model, offset = v.offset, heading = v.heading, pose = v.pose,
            vehicle = v.vehicle, seat = v.seat, trapped = v.trapped, wet = v.wet, dp = v.dp, sex = v.sex,
        }
    end
    for _, v in ipairs(plan.props) do
        out.props[#out.props + 1] = { idx = v.idx, model = v.model, offset = v.offset, rot = v.rot }
    end
    for _, v in ipairs(plan.bystanders) do
        out.bystanders[#out.bystanders + 1] = {
            idx = v.idx, model = v.model, offset = v.offset, heading = v.heading, scenario = v.scenario, role = v.role, victim = v.victim,
        }
    end
    return out
end

-- ════════════════════════════════════════════════════════════════════════
-- ENTITIES
-- ════════════════════════════════════════════════════════════════════════

function I.Ent(net)
    net = tonumber(net)
    if not net or net == 0 then return 0 end
    local ok, ent = pcall(NetworkGetEntityFromNetworkId, net)
    if not ok or not ent or ent == 0 or not DoesEntityExist(ent) then return 0 end
    return ent
end

function I.KeepEntity(ent)
    if not ent or ent == 0 then return end
    -- 2 = KeepEntity: the scene survives its builder leaving the server
    pcall(SetEntityOrphanMode, ent, 2)
end

function I.DeleteNet(net)
    local ent = I.Ent(net)
    if ent ~= 0 then
        pcall(DeleteEntity, ent)
        return true
    end
    return false
end

local function hashOf(model)
    if type(model) == 'number' then return model end
    return joaat(model)
end

-- unsigned/signed safe model compare (server GetEntityModel can return either form)
local function sameModel(ent, model)
    local m = GetEntityModel(ent)
    local h = hashOf(model)
    if m == h then return true end
    if m < 0 then m = m + 4294967296 end
    if h < 0 then h = h + 4294967296 end
    return m == h
end

-- result.<kind> = { { i = idx, n = netId }, ... }
local function collect(list, planList, origin, radius, out, bad)
    for _, e in ipairs(type(list) == 'table' and list or {}) do
        local idx, net = tonumber(e.i), tonumber(e.n)
        local spec = idx and planList[idx]
        local ent = net and I.Ent(net) or 0
        if spec and ent ~= 0 and sameModel(ent, spec.model) and #(GetEntityCoords(ent) - origin) <= radius then
            out[idx] = net
        elseif net then
            bad[#bad + 1] = net
        end
    end
end

-- Validates what the builder reported and creates the NPC patients. Runs inside a thread
-- (waits up to ~3 s for the entities to reach the server).
function I.Register(scene, src, result)
    if type(result) ~= 'table' then return false, 'bad_result' end
    local o = result.origin
    local origin = o and tonumber(o.x) and vector3(o.x + 0.0, o.y + 0.0, o.z + 0.0) or nil
    if not origin then return false, 'no_origin' end
    local radius = tonumber(cfg('scene').buildRadius) or 70.0
    if #(origin - vector3(scene.loc.x, scene.loc.y, scene.loc.z)) > radius then return false, 'origin_far' end

    -- give the server a moment to know every entity
    local deadline = GetGameTimer() + 3500
    local function allKnown()
        for _, kind in ipairs({ 'victims', 'vehicles', 'props', 'bystanders' }) do
            for _, e in ipairs(type(result[kind]) == 'table' and result[kind] or {}) do
                if I.Ent(e.n) == 0 then return false end
            end
        end
        return true
    end
    while not allKnown() and GetGameTimer() < deadline do Wait(250) end

    local plan = scene.plan
    local ents = { victims = {}, vehicles = {}, props = {}, bystanders = {} }
    local bad = {}
    collect(result.victims, plan.victims, origin, radius, ents.victims, bad)
    collect(result.vehicles, plan.vehicles, origin, radius, ents.vehicles, bad)
    collect(result.props, plan.props, origin, radius, ents.props, bad)
    collect(result.bystanders, plan.bystanders, origin, radius, ents.bystanders, bad)
    for _, net in ipairs(bad) do I.DeleteNet(net) end

    if next(ents.victims) == nil then
        for _, kind in pairs(ents) do for _, net in pairs(kind) do I.DeleteNet(net) end end
        return false, 'no_victims'
    end

    for _, kind in pairs(ents) do
        for _, net in pairs(kind) do I.KeepEntity(I.Ent(net)) end
    end

    scene.center = origin
    scene.origin = { x = origin.x, y = origin.y, z = origin.z, w = tonumber(o.w) or scene.loc.w or 0.0 }
    scene.entities = ents
    scene.victims = scene.victims or {}

    -- NPC patients
    for idx, net in pairs(ents.victims) do
        local v = plan.victims[idx]
        local p = NZA.Patients.CreateNPC({
            net = net, sex = v.sex, age = v.age, loss = v.loss, state = v.state ~= 'alive' and v.state or nil,
            injuries = v.injuries, conditions = v.conditions, reason = 'scenario',
            meta = { scenario = scene.key, callId = scene.callId, scene = scene.id, trapped = v.trapped or nil },
        })
        if p then
            local tri = 2
            local ok, level = pcall(NZA.Patients.Triage, p)
            if ok and tonumber(level) then tri = tonumber(level) end
            scene.victims[p.pid] = {
                pid = p.pid, net = net, idx = idx, triage = tri, created = os.time(), trapped = v.trapped == true,
                vehicle = v.vehicle and ents.vehicles[v.vehicle] or nil, seat = v.seat, pose = v.pose, dp = v.dp, wet = v.wet,
                procedures = 0, crew = {},
            }
            I.victimIndex[p.pid] = scene.id
        else
            I.DeleteNet(net)
            ents.victims[idx] = nil
        end
    end
    if next(scene.victims) == nil then
        for _, kind in pairs(ents) do for _, net in pairs(kind) do I.DeleteNet(net) end end
        return false, 'no_patients'
    end

    -- effects become live now
    scene.fx = {}
    for _, f in ipairs(plan.fx) do
        local fx = { id = f.id, kind = f.kind, on = true, untilAt = f.untilAt }
        if f.vehicle then
            fx.net = ents.vehicles[f.vehicle]
            if not fx.net then fx = nil end
        elseif f.prop then
            fx.net = ents.props[f.prop]
            if not fx.net then fx = nil end
        elseif f.offset then
            local h = math.rad(scene.origin.w or 0.0)
            local ox, oy = f.offset.x or 0.0, f.offset.y or 0.0
            fx.at = { x = origin.x + ox * math.cos(h) - oy * math.sin(h), y = origin.y + ox * math.sin(h) + oy * math.cos(h), z = origin.z + (f.offset.z or 0.0) }
        end
        if fx then scene.fx[#scene.fx + 1] = fx end
    end
    return true
end
