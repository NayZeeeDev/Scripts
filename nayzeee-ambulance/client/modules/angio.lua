--[[
    NAYZEEE AMBULANCE - Angiography (client): the suite, entry points, registries

    THE SUITE - point type 'angio' (NZA.Points, ARCHITECTURE §8)
        The builder places ONE point: the angiography table. The table model
        (Config.Angio.suite.table, false for MLO tables) is the point's prop; onSpawn puts
        the boom monitor, the power injector tray and the red contrast button around it
        using Config.Angio.suite.layout (table space: +X right side, +Y head end, +Z up).
        Per point the builder may override pieces: point.data.layout[key] = { pos, h } | false.
        The type def also carries `parts` (the same layout as a list) so the builder can show
        the whole set as a ghost while placing, and `lie` (patient position on the table).
        Target options on the table: "Start angiography" (perm angio) on the patient lying on it.

    ENTRY POINTS
        NZA.Interact option 'nza_angio' (order 60) on patients with an internal / fracture bleed
        NZA.ExamRoutes 'angio' (internal + bleeding pelvic / thigh fractures) - greyed with
            "Needs the angiography suite" until the patient lies on an angio table (not in easy mode)
        NZA.RadialItems 'angio_start' (parent 'patient')
        Usable item Config.Items.angio_kit → net event 'nza:angio:use'

    Lua API (client)
        NZA.Angio.Start(entity|nil, target|nil, injuryId|nil)   blocking (call from a thread)
        NZA.Angio.Suite(pointId) → suite { id, point, ents = { table, monitor, injector, button,
                                   plunger }, base, heading, screenOk } | nil
        NZA.Angio.SuiteNear(coords, range) → suite, dist      NZA.Angio.ToWorld(suite, vec3) → vec3
        NZA.Angio.PatientOnTable(suite) → entity, target       NZA.Angio.Eligible(injury) → bool
        NZA.Angio.Runner(ctx)  (client/modules/angio_proc.lua) the minigame for NZA.Proc.Run

    Net events handled: nza:angio:use
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Angio = NZA.Angio or {}
local Angio = NZA.Angio
local U = NZA.Util

local suites = {}        -- [pointId] = suite

local function cfg() return Config.Angio or {} end
local function suiteCfg() return cfg().suite or {} end
local function perm() return cfg().perm or 'angio' end
local function L(key, ...) return NZA.L('angio.' .. key, ...) end

local function toast(key, kind, ...)
    NZA.UI.Toast({ title = L('title'), message = L(key, ...), type = kind or 'info', icon = 'scan' })
end

local function model(key)
    if type(key) ~= 'string' or key == '' then return nil end
    return (Config.Props and Config.Props[key]) or key
end

local function valid(ent)
    return ent ~= nil and ent ~= 0 and DoesEntityExist(ent)
end

-- ════════════════════════════════════════════════════════════════════════
-- GEOMETRY
-- ════════════════════════════════════════════════════════════════════════

local function rotate(heading, off)
    local h = math.rad(heading or 0.0)
    local c, s = math.cos(h), math.sin(h)
    return vector3(off.x * c - off.y * s, off.x * s + off.y * c, off.z)
end

-- table space → world (the table entity when it exists, else the point itself)
function Angio.ToWorld(suite, off)
    off = U.vec(off) or vector3(0.0, 0.0, 0.0)
    if suite.ents and valid(suite.ents.table) then
        return GetOffsetFromEntityInWorldCoords(suite.ents.table, off.x, off.y, off.z)
    end
    return suite.base + rotate(suite.heading, off)
end

local function pointCoords(point)
    local c = point.coords
    if type(c) == 'vector4' then return vector3(c.x, c.y, c.z), c.w end
    if type(c) == 'vector3' then return c, tonumber(point.heading) or 0.0 end
    if type(c) == 'table' then
        return vector3(tonumber(c.x or c[1]) or 0.0, tonumber(c.y or c[2]) or 0.0, tonumber(c.z or c[3]) or 0.0),
            tonumber(c.w or c.h or c[4]) or 0.0
    end
    return nil, 0.0
end

-- the layout entry of one piece, with the point's own override applied
local function layoutFor(point, key)
    local def = (suiteCfg().layout or {})[key]
    local data = type(point.data) == 'table' and point.data or {}
    local over = type(data.layout) == 'table' and data.layout[key] or nil
    if over == false then return nil end
    if type(def) ~= 'table' then
        if type(over) ~= 'table' then return nil end
        def = {}
    end
    local out = {
        prop = def.prop, fallback = def.fallback, pos = U.vec(def.pos) or vector3(0.0, 0.0, 0.0),
        h = tonumber(def.h) or 0.0, anchor = U.vec(def.anchor) or vector3(0.0, 0.0, 1.0),
    }
    if type(over) == 'table' then
        if over.pos then out.pos = U.vec(over.pos) or out.pos end
        if over.h then out.h = tonumber(over.h) or out.h end
        if type(over.prop) == 'string' then out.prop = over.prop end
    end
    return out
end

-- ════════════════════════════════════════════════════════════════════════
-- SPAWN / REMOVE THE EQUIPMENT
-- ════════════════════════════════════════════════════════════════════════

local function spawnPiece(suite, lay)
    local pos = Angio.ToWorld(suite, vector3(lay.pos.x, lay.pos.y, 0.0))
    local heading = (suite.heading or 0.0) + lay.h
    local opts = { group = suite.group, heading = heading, freeze = true, collision = true, ground = suiteCfg().ground ~= false }
    local name = model(lay.prop)
    local ent = name and NZA.Props.Spawn(name, pos, opts) or 0
    local native = false
    if (not ent or ent == 0) and lay.fallback then
        ent = NZA.Props.Spawn(lay.fallback, pos, opts) or 0
        native = ent ~= 0
    end
    if ent ~= 0 and lay.pos.z ~= 0.0 then
        local p = GetEntityCoords(ent)
        SetEntityCoordsNoOffset(ent, p.x, p.y, p.z + lay.pos.z, false, false, false)
    end
    return ent or 0, native
end

local function buildSuite(point, tableEnt)
    local base, heading = pointCoords(point)
    if not base then return end
    local id = point.id
    local group = 'nza:angio:' .. tostring(id)
    NZA.Props.Clear(group)
    local suite = { id = id, point = point, group = group, base = base, heading = heading, ents = {}, layout = {} }
    if valid(tableEnt) then
        suite.ents.table = tableEnt
        suite.heading = GetEntityHeading(tableEnt)
    end
    suites[id] = suite

    for _, key in ipairs({ 'monitor', 'injector', 'button' }) do
        if suites[id] ~= suite then NZA.Props.Clear(group) return end
        local lay = layoutFor(point, key)
        if lay then
            local ent, native = spawnPiece(suite, lay)
            suite.ents[key] = ent
            suite.layout[key] = lay
            if key == 'monitor' then suite.screenOk = ent ~= 0 and not native end
        end
    end

    -- optional separate plunger for the injector animation
    local pl = suiteCfg().plunger
    local inj = suite.ents.injector
    if type(pl) == 'table' and valid(inj) and Config.Props and Config.Props[pl.prop] then
        local off = U.vec(pl.pos) or vector3(0.0, 0.0, 1.0)
        local pos = GetOffsetFromEntityInWorldCoords(inj, off.x, off.y, off.z)
        local ent = NZA.Props.Spawn(Config.Props[pl.prop], pos, { group = group, heading = GetEntityHeading(inj), freeze = true, collision = false })
        if ent ~= 0 then
            local ax = U.vec(pl.axis) or vector3(-1.0, 0.0, 0.0)
            suite.ents.plunger = ent
            suite.plungerRest = pos
            suite.plungerAxis = GetOffsetFromEntityInWorldCoords(inj, ax.x, ax.y, ax.z) - GetEntityCoords(inj)
        end
    end
    if suites[id] ~= suite then NZA.Props.Clear(group) end
end

local function removeSuite(point)
    local id = type(point) == 'table' and point.id or point
    local s = suites[id]
    if not s then return end
    suites[id] = nil
    NZA.Props.Clear(s.group)
    NZA.Bus.Emit('angio:suiteRemoved', id)
end

function Angio.Suite(id)
    return id ~= nil and suites[id] or nil
end

function Angio.Suites()
    return suites
end

function Angio.SuiteNear(coords, range)
    coords = U.vec(coords)
    if not coords then return nil, nil end
    local best, bestD = nil, range or 3.0
    for _, s in pairs(suites) do
        local centre = Angio.ToWorld(s, vector3(0.0, 0.0, 0.0))
        local d = #(vector3(coords.x, coords.y, 0.0) - vector3(centre.x, centre.y, 0.0))
        if d <= bestD then best, bestD = s, d end
    end
    if not best then return nil, nil end
    return best, bestD
end

-- ════════════════════════════════════════════════════════════════════════
-- PATIENTS
-- ════════════════════════════════════════════════════════════════════════

function Angio.Eligible(inj)
    if type(inj) ~= 'table' then return false end
    if type(inj.treat) == 'table' and inj.treat.coiled then return false end
    local c = cfg()
    if inj.type == 'internal' then
        local organ = type(inj.internal) == 'table' and inj.internal.organ or inj.organ
        return organ ~= nil and (c.organs or {})[organ] == true
    elseif inj.type == 'fracture' then
        return (c.fractures or {})[inj.region] == true and (tonumber(inj.bleed) or 0) >= (tonumber(c.minFractureBleed) or 1.0)
    end
    return false
end

local function hasTag(bag, tag)
    if type(bag) ~= 'table' or type(bag.tags) ~= 'table' then return false end
    for _, t in ipairs(bag.tags) do
        if t == tag then return true end
    end
    return false
end

local function candidate(bag)
    return hasTag(bag, 'internal') or hasTag(bag, 'fracture')
end

-- every patient ped (players and NPC patients) around coords
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

-- target scripts ask every frame while aiming: scan the ped pool at most twice a second
function Angio.PatientOnTable(suite)
    if not suite then return nil, nil end
    local now = GetGameTimer()
    local c = suite.onTable
    if c and now - c.at < 500 and (not c.ent or DoesEntityExist(c.ent)) then return c.ent, c.target end
    local lie = U.vec(suiteCfg().lie) or vector3(0.0, 0.0, 0.95)
    local list = patientsNear(Angio.ToWorld(suite, lie), (tonumber(cfg().tableRange) or 1.8) + 0.4)
    -- someone lying down (head level with the hips), not a colleague standing beside the table
    local first = nil
    for _, p in ipairs(list) do
        local head = GetPedBoneCoords(p.ent, 31086, 0.0, 0.0, 0.0)
        if head.z - GetEntityCoords(p.ent).z < 0.4 then
            first = p
            break
        end
    end
    suite.onTable = { at = now, ent = first and first.ent or nil, target = first and first.target or nil }
    if first then return first.ent, first.target end
    return nil, nil
end

-- the patient to work on from wherever the medic stands: one on a nearby table first
local function nearestPatient(range)
    local me = GetEntityCoords(PlayerPedId())
    local suite = Angio.SuiteNear(me, 4.0)
    if suite then
        local ent, target = Angio.PatientOnTable(suite)
        if ent then return ent, target end
    end
    local list = patientsNear(me, range or 3.0)
    for _, p in ipairs(list) do
        if candidate(NZA.Target.State(p.ent)) then return p.ent, p.target end
    end
    if list[1] then return list[1].ent, list[1].target end
    return nil, nil
end

local function onTable(entity)
    if not valid(entity) then return false end
    local suite = Angio.SuiteNear(GetEntityCoords(entity), tonumber(cfg().tableRange) or 1.8)
    return suite ~= nil
end

-- ════════════════════════════════════════════════════════════════════════
-- START
-- ════════════════════════════════════════════════════════════════════════

function Angio.Start(entity, target, injury)
    if NZA.Proc.Active() then
        toast('err.busy_self', 'error')
        return false
    end
    if not NZA.Perm(perm()) then
        toast('err.no_perm', 'error')
        return false
    end
    if not target and valid(entity) then target = NZA.Target.FromEntity(entity) end
    if not target then
        entity, target = nearestPatient(3.0)
        if not target then
            toast('err.nobody', 'error')
            return false
        end
    end
    local c = cfg()
    return NZA.Proc.Run('angio', target, { injury = injury }, function(ctx)
        Angio.Runner(ctx)
    end, { label = L('title'), maxDist = tonumber(c.maxDist) or 6.0 })
end

-- ════════════════════════════════════════════════════════════════════════
-- REGISTRIES
-- ════════════════════════════════════════════════════════════════════════

-- the suite as a list (the builder shows these as ghosts next to the table)
local function partsList()
    local out = {}
    for _, key in ipairs({ 'monitor', 'injector', 'button' }) do
        local lay = (suiteCfg().layout or {})[key]
        if type(lay) == 'table' and model(lay.prop) then
            out[#out + 1] = { key = key, model = model(lay.prop), pos = U.vec(lay.pos), h = tonumber(lay.h) or 0.0 }
        end
    end
    return out
end

-- patient position from the point: on the spawned table top, or the point itself when the
-- map's own table is used (the builder then places the point on the table top)
local function lieOffset()
    if suiteCfg().table == false then return vector3(0.0, 0.0, 0.0) end
    return U.vec(suiteCfg().lie) or vector3(0.0, 0.0, 0.825)
end

local function tableModel()
    local t = suiteCfg().table
    if t == false or t == nil then return nil end
    return model(t)
end

NZA.Points.RegisterType('angio', {
    label = L('point'),
    icon = 'scan',
    prop = tableModel(),
    needsHeading = true,
    ground = suiteCfg().ground ~= false,
    radius = 1.3,
    distance = 2.2,
    parts = partsList(),
    lie = { pos = lieOffset(), heading = 0.0 },
    -- the transport module lays the patient at point coords + data.lie (point space)
    data = { lie = { x = lieOffset().x, y = lieOffset().y, z = lieOffset().z } },
    onSpawn = function(point, entity)
        CreateThread(function() buildSuite(point, entity) end)
    end,
    onRemove = function(point)
        removeSuite(point)
    end,
    target = {
        {
            name = 'start', label = L('opt_table'), icon = 'scan', perm = perm(),
            canInteract = function(point)
                return Angio.PatientOnTable(suites[point.id]) ~= nil and not NZA.Proc.Active()
            end,
            onSelect = function(point)
                local ent, target = Angio.PatientOnTable(suites[point.id])
                if not ent then
                    toast('err.nobody_table', 'error')
                    return
                end
                Angio.Start(ent, target)
            end,
        },
    },
})

if cfg().interact ~= false then
    NZA.Interact.Add({
        name = 'nza_angio', label = L('opt'), icon = 'scan', order = 60, perm = perm(),
        states = { alive = true, wounded = true }, npc = true, player = true, distance = 2.5,
        canInteract = function(entity, target, bag)
            if not candidate(bag) then return false end
            return onTable(entity) or NZA.Easy(perm()) or cfg().requireSuite == false
        end,
        onSelect = function(entity, target)
            Angio.Start(entity, target)
        end,
    })
end

-- Examination → "Next care step" card
NZA.ExamRoutes = NZA.ExamRoutes or {}
do
    local items = {}
    for key, n in pairs(cfg().items or {}) do
        local name = Config.Items and Config.Items[key]
        if name and (tonumber(n) or 0) > 0 then items[name] = tonumber(n) end
    end
    table.insert(NZA.ExamRoutes, {
        id = 'angio', label = L('route'), icon = 'scan', perm = perm(), order = 45,
        types = { 'internal', 'fracture' },
        items = items,
        available = function(inj, snap)
            if not Angio.Eligible(inj) then return false end
            if inj.type == 'internal' and (tonumber(inj.bleed) or 0) <= 0 and (tonumber(inj.bleedBase) or 0) <= 0 then return false end
            if NZA.Easy(perm()) or cfg().requireSuite == false then return true end
            local bed = type(snap) == 'table' and type(snap.meta) == 'table' and snap.meta.bed or nil
            if type(bed) == 'table' and bed.type == 'angio' then return true end
            return false, L('route_suite')
        end,
        run = function(target, inj)
            Angio.Start(nil, target, inj and inj.id or nil)
        end,
    })
end

-- EMS radial → Patient → Angiography
NZA.RadialItems = NZA.RadialItems or {}
if cfg().radial ~= false then
    table.insert(NZA.RadialItems, {
        id = 'angio_start', parent = 'patient', label = L('opt'), icon = 'scan', order = 60, perm = perm(),
        canShow = function()
            if NZA.Proc.Active() then return false end
            local suite = Angio.SuiteNear(GetEntityCoords(PlayerPedId()), 4.0)
            return suite ~= nil and Angio.PatientOnTable(suite) ~= nil
        end,
        onSelect = function()
            CreateThread(function()
                local ent, target = nearestPatient(3.0)
                if not ent then
                    toast('err.nobody_table', 'error')
                    return
                end
                Angio.Start(ent, target)
            end)
        end,
    })
end

-- the angio kit item was used
RegisterNetEvent('nza:angio:use', function()
    if cfg().usable == false then return end
    CreateThread(function()
        local ent, target = nearestPatient(3.0)
        if not ent then
            toast('err.nobody', 'error')
            return
        end
        Angio.Start(ent, target)
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(suites) do removeSuite(id) end
end)
