--[[
    NAYZEEE AMBULANCE - Client core: hospital points (NZA.Points)

    Points are placed in game with the builder and owned by the hospital module on the
    server, which broadcasts them. A point = { id, hospital, type, coords = vector4,
    data = {}, model?, label? } (ARCHITECTURE §8, §17).

      NZA.Points.RegisterType(name, def)   (client modules, at their file top level)
          def = { label, icon, prop = model name or Config.Props key, needsHeading,
                  data = { defaults }, radius = 1.2 (sphere target when there is no prop),
                  distance = 2.0, ground = false (place prop on ground),
                  onSpawn = fn(point, entity|nil), onRemove = fn(point),
                  target = { { label, icon, perm, distance, name?,
                               canInteract = fn(point, entity) → bool,
                               onSelect = fn(point, entity) }, ... } }
      NZA.Points.All(type?) → { point, ... }       NZA.Points.Get(id) → point
      NZA.Points.Nearest(type, coords?, maxDist?) → point, dist
      NZA.Points.Types() → { [name] = def }        NZA.Points.Type(name) → def
      NZA.Points.Entity(id) → prop entity | 0      NZA.Points.Refresh(id?) re-spawn points

    Points within 60 m are streamed: the type's prop is spawned frozen at the point's
    coords/heading (point.model overrides it), the type's target options are registered on
    the prop (Bridge.Target.Entity) or on a sphere at the coords (Bridge.Target.Sphere),
    filtered by NZA.Perm, and onSpawn is called. Leaving 70 m (or removal) undoes it and
    calls onRemove. Types registered after the points arrived are applied lazily.

    Net events handled: nza:points:sync (points[]), nza:points:upsert (point),
                        nza:points:remove (pointId)
    Bus events emitted: points:changed (reason 'sync'|'upsert'|'remove'|'type', point|id|type)
]]

if not NAYZEEE_LOCK_OK then return end

NZA.Points = NZA.Points or {}
local Points = NZA.Points
local U = NZA.Util

local STREAM_IN = 60.0
local STREAM_OUT = 70.0
local SCAN_MS = 1000

local types = {}      -- [name] = def
local points = {}     -- [id] = point
local live = {}       -- [id] = { entity, names, sphere, type }

-- ════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ════════════════════════════════════════════════════════════════════════

local function coordsOf(point)
    local c = point.coords
    if type(c) == 'vector4' then return vector3(c.x, c.y, c.z), c.w end
    if type(c) == 'vector3' then return c, (point.heading or 0.0) end
    if type(c) == 'table' then
        local x = tonumber(c.x or c[1]) or 0.0
        local y = tonumber(c.y or c[2]) or 0.0
        local z = tonumber(c.z or c[3]) or 0.0
        local w = tonumber(c.w or c.h or c[4]) or tonumber(point.heading) or 0.0
        return vector3(x, y, z), w
    end
    return nil, 0.0
end

local function fillDefaults(point)
    local def = types[point.type]
    if type(point.data) ~= 'table' then point.data = {} end
    if def and type(def.data) == 'table' then
        for k, v in pairs(def.data) do
            if point.data[k] == nil then point.data[k] = U.deepcopy(v) end
        end
    end
end

local function targetApi()
    return Bridge and Bridge.Target or nil
end

local function safeCall(fn, ...)
    if type(fn) ~= 'function' then return end
    local ok, err = pcall(fn, ...)
    if not ok then NZA.Warn('point callback failed: ' .. tostring(err)) end
end

local function buildOptions(point, def, getEntity)
    local list = {}
    if type(def.target) ~= 'table' then return list end
    for i, opt in ipairs(def.target) do
        list[#list + 1] = {
            name = opt.name and ('nza_pt_%s_%s'):format(point.id, opt.name) or ('nza_pt_%s_%d'):format(point.id, i),
            label = opt.label,
            order = opt.order or i,
            icon = opt.icon or def.icon,
            distance = opt.distance or def.distance or 2.0,
            canInteract = function()
                if opt.perm and not NZA.Perm(opt.perm) then return false end
                if not opt.whileDown and NZA.Self and NZA.Self.State and NZA.Self.State() ~= 'alive' then return false end
                if opt.canInteract then
                    local ok, res = pcall(opt.canInteract, points[point.id] or point, getEntity())
                    return ok and res and true or false
                end
                return true
            end,
            onSelect = function()
                CreateThread(function()
                    safeCall(opt.onSelect, points[point.id] or point, getEntity())
                end)
            end,
        }
    end
    return list
end

-- ════════════════════════════════════════════════════════════════════════
-- SPAWN / DESPAWN
-- ════════════════════════════════════════════════════════════════════════

local function despawn(id)
    local l = live[id]
    if not l then return end
    live[id] = nil
    local api = targetApi()
    if api then
        if l.entity and l.entity ~= 0 and l.names and #l.names > 0 and api.RemoveEntity then
            pcall(api.RemoveEntity, l.entity, l.names)
        end
        if l.sphere and api.Remove then pcall(api.Remove, l.sphere) end
    end
    if l.entity and l.entity ~= 0 then NZA.Props.Delete(l.entity) end
    local def = types[l.type]
    local point = points[id] or l.point
    if def and point then safeCall(def.onRemove, point) end
end

local function spawn(point)
    local def = types[point.type]
    if not def then return end
    local pos, heading = coordsOf(point)
    if not pos then return end

    local l = { type = point.type, entity = 0, names = {}, point = point }
    live[point.id] = l

    local model = point.model or def.prop
    if model then
        local ent = NZA.Props.Spawn(model, pos, {
            group = 'nza:points', heading = heading, freeze = true, collision = true,
            ground = def.ground == true,
        })
        -- the point may have been removed while the model loaded
        if live[point.id] ~= l then
            if ent ~= 0 then NZA.Props.Delete(ent) end
            return
        end
        l.entity = ent or 0
    end

    local api = targetApi()
    local options = buildOptions(point, def, function() return l.entity end)
    if api and #options > 0 then
        if l.entity ~= 0 and api.Entity then
            local ok = pcall(api.Entity, l.entity, options)
            if ok then
                for i, o in ipairs(options) do l.names[i] = o.name end
            end
        elseif api.Sphere then
            local ok, id = pcall(api.Sphere, 'nza_pt_' .. tostring(point.id), pos, def.radius or 1.2, options)
            if ok then l.sphere = id end
        end
    end

    safeCall(def.onSpawn, point, l.entity ~= 0 and l.entity or nil)
end

local passing = false

-- Collect first, act after: spawning yields while models load, and the point tables may
-- change underneath (sync/upsert/remove) during that time.
local function streamPass()
    if passing then return end
    passing = true
    local me = GetEntityCoords(PlayerPedId())
    local toSpawn, toDespawn = {}, {}
    for id, point in pairs(points) do
        local l = live[id]
        if types[point.type] then
            local pos = coordsOf(point)
            if pos then
                local d = #(me - pos)
                if not l and d <= STREAM_IN then
                    toSpawn[#toSpawn + 1] = point
                elseif l and d > STREAM_OUT then
                    toDespawn[#toDespawn + 1] = id
                end
            end
        elseif l then
            toDespawn[#toDespawn + 1] = id
        end
    end
    for id in pairs(live) do
        if not points[id] then toDespawn[#toDespawn + 1] = id end
    end
    for _, id in ipairs(toDespawn) do
        local ok, err = pcall(despawn, id)
        if not ok then NZA.Warn('point despawn failed: ' .. tostring(err)) end
    end
    for _, point in ipairs(toSpawn) do
        if points[point.id] == point and not live[point.id] then
            local ok, err = pcall(spawn, point)
            if not ok then NZA.Warn(('point %s (%s) failed to spawn: %s'):format(tostring(point.id), point.type, tostring(err))) end
        end
    end
    passing = false
end

-- ════════════════════════════════════════════════════════════════════════
-- API
-- ════════════════════════════════════════════════════════════════════════

function Points.RegisterType(name, def)
    if type(name) ~= 'string' or type(def) ~= 'table' then return end
    def.name = name
    if type(def.prop) == 'string' and Config.Props and Config.Props[def.prop] then
        def.prop = Config.Props[def.prop]
    end
    local replacing = types[name] ~= nil
    types[name] = def
    for id, point in pairs(points) do
        if point.type == name then
            fillDefaults(point)
            if replacing and live[id] then despawn(id) end
        end
    end
    NZA.Bus.Emit('points:changed', 'type', name)
end

function Points.Types()
    return types
end

function Points.Type(name)
    return types[name]
end

function Points.Get(id)
    return points[id]
end

function Points.All(kind)
    local out = {}
    for _, p in pairs(points) do
        if not kind or p.type == kind then out[#out + 1] = p end
    end
    table.sort(out, function(a, b) return tostring(a.id) < tostring(b.id) end)
    return out
end

function Points.Nearest(kind, coords, maxDist)
    coords = coords and U.vec(coords) or GetEntityCoords(PlayerPedId())
    local best, bestDist = nil, maxDist or math.huge
    for _, p in pairs(points) do
        if not kind or p.type == kind then
            local pos = coordsOf(p)
            if pos then
                local d = #(coords - pos)
                if d <= bestDist then best, bestDist = p, d end
            end
        end
    end
    if not best then return nil, nil end
    return best, bestDist
end

function Points.Entity(id)
    local l = live[id]
    return l and l.entity or 0
end

function Points.Refresh(id)
    if id ~= nil then
        despawn(id)
    else
        for pid in pairs(live) do despawn(pid) end
    end
    streamPass()
end

-- ════════════════════════════════════════════════════════════════════════
-- SERVER SYNC
-- ════════════════════════════════════════════════════════════════════════

local function valid(point)
    return type(point) == 'table' and point.id ~= nil and type(point.type) == 'string' and point.coords ~= nil
end

RegisterNetEvent('nza:points:sync', function(list)
    if type(list) ~= 'table' then return end
    for id in pairs(live) do despawn(id) end
    points = {}
    for _, p in pairs(list) do
        if valid(p) then
            fillDefaults(p)
            points[p.id] = p
        end
    end
    NZA.Bus.Emit('points:changed', 'sync')
    streamPass()
end)

RegisterNetEvent('nza:points:upsert', function(point)
    if not valid(point) then return end
    fillDefaults(point)
    if live[point.id] then despawn(point.id) end
    points[point.id] = point
    NZA.Bus.Emit('points:changed', 'upsert', point)
    streamPass()
end)

RegisterNetEvent('nza:points:remove', function(id)
    if id == nil then return end
    -- ids may arrive as number or string depending on how the server stored them
    local key = points[id] and id or (points[tonumber(id)] and tonumber(id)) or (points[tostring(id)] and tostring(id))
    if key == nil then return end
    despawn(key)
    points[key] = nil
    NZA.Bus.Emit('points:changed', 'remove', key)
end)

CreateThread(function()
    Wait(500)
    while true do
        if next(points) then streamPass() end
        Wait(SCAN_MS)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= NZA.Resource then return end
    for id in pairs(live) do
        local l = live[id]
        local def = types[l.type]
        if def and l.point then safeCall(def.onRemove, l.point) end
    end
    NZA.Props.Clear('nza:points')
end)
