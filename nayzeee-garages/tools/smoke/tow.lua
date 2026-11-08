--[[
  Scenario test for the impound flatbed tow truck: server/towtruck.lua, client/towtruck.lua
  and the hook in server/impound.lua. No FiveM needed.

  Runs the real server file and one real client file per player together against a small
  simulated OneSync world (entities with owners and routing buckets, control requests and
  SetNetworkIdCanMigrate, state bags, attachments synced from the attached entity's owner,
  driving tasks, traffic lights, routes, player drops with ownership migration) on a shared
  fake clock, and checks the whole sequence and every failure path end to end: full tow
  (stops in front of the vehicle, in line; the runner keeps truck, driver and vehicle; drives
  off with it on the bed), remote attach / the runner taking the vehicle, two impounds at once
  (one officer / two officers on the same node), runner disconnect (handed over / no one left),
  runner walking away (the same truck carries on), silent runner, boat, oversized truck, target
  deleted / moved / entered meanwhile, stuck in sight (reverse, then a new truck) and out of
  sight (skips ahead), red lights, spawn nodes without a route, forged reports (`loaded` with
  nothing on the bed), resource stop, the impound form hook, recycled handles
  (`entityRemoved`), tow state bags cleared by a cheating owner, a player taking the truck, the
  vehicle coming off the leaving truck (held + pulled back on), long vehicles on the bed, the
  truck stopping beside the vehicle and pulls from beside the bed, a wrong-way stop on screen
  with the other side taken (loads from where it stands, along the truck's side, never lifted
  over it), a nose-to-nose stop on screen (never lifted over the cab: a new truck comes),
  backing up to the vehicle, the tilt up the ramp, trucks the server gives up on (dismissed:
  driven off empty; mid-load: the vehicle is put onto the deck, the driver back at the wheel),
  the failure notice, the leaving truck let go far from the runner, never moved in front of
  another player.

  Invariants checked across the scenarios: a towed vehicle never vanishes near a player before
  it is on the bed, a tow truck never vanishes near a player, a truck never drives off without
  the vehicle it loaded; what is left after a failure goes once every player is far away.

  Usage (from the resource root):  lua5.4 tools/smoke/tow.lua [-v]
]]

local VERBOSE = select(1, ...) == '-v'
local failures, checks = {}, 0
local scenarioName = '?'
local function check(cond, label)
  checks = checks + 1
  if not cond then failures[#failures + 1] = ('[%s] %s'):format(scenarioName, label) end
  return cond
end
local function say(...) if VERBOSE then print(...) end end

local function joaat(s)
  local h = 0
  s = tostring(s):lower()
  for i = 1, #s do
    h = (h + s:byte(i)) & 0xffffffff
    h = (h + (h << 10)) & 0xffffffff
    h = h ~ (h >> 6)
  end
  h = (h + (h << 3)) & 0xffffffff
  h = h ~ (h >> 11)
  h = (h + (h << 15)) & 0xffffffff
  if h > 0x7fffffff then h = h - 0x100000000 end
  return h
end

local vmeta = {}
local function vec(x, y, z) return setmetatable({ x = (x or 0) + 0.0, y = (y or 0) + 0.0, z = (z or 0) + 0.0 }, vmeta) end
vmeta.__add = function(a, b) return vec(a.x + b.x, a.y + b.y, a.z + b.z) end
vmeta.__sub = function(a, b) return vec(a.x - b.x, a.y - b.y, a.z - b.z) end
vmeta.__mul = function(a, b) if type(a) == 'number' then a, b = b, a end return vec(a.x * b, a.y * b, a.z * b) end
local function vec4(x, y, z, w) return { x = x, y = y, z = z, w = w } end

---------------------------------------------------------------------------------------
-- Clock and threads
---------------------------------------------------------------------------------------

local TICK = 50
local now, threads, runtimeErrors, printedErrors = 0, {}, {}, {}

local function addThread(env, fn, ...)
  threads[#threads + 1] = { co = coroutine.create(fn), wake = now, env = env, args = table.pack(...) }
end

local W -- world, set per scenario

local function resumeAll()
  local list = threads
  threads = {}
  local keep = {}
  for _, t in ipairs(list) do
    if t.env and t.env.dead then
      -- the client is gone: its threads stop with it
    elseif t.wake <= now then
      local ok, res
      if t.args then
        local args = t.args
        t.args = nil
        ok, res = coroutine.resume(t.co, table.unpack(args, 1, args.n))
      else
        ok, res = coroutine.resume(t.co)
      end
      if not ok then
        runtimeErrors[#runtimeErrors + 1] = ('[%s] %s'):format(scenarioName, debug.traceback(t.co, res))
      elseif coroutine.status(t.co) ~= 'dead' then
        t.wake = now + math.max(0, tonumber(res) or 0)
        keep[#keep + 1] = t
      end
    else
      keep[#keep + 1] = t
    end
  end
  for _, t in ipairs(threads) do keep[#keep + 1] = t end
  threads = keep
end

---------------------------------------------------------------------------------------
-- World
---------------------------------------------------------------------------------------

local MODELS = {
  flatbed = { class = 10, vtype = 'automobile', min = vec(-1.535, -6.027, -1.117), max = vec(1.536, 4.511, 3.455) },
  sultan = { class = 1, vtype = 'automobile', min = vec(-0.95, -2.3, -0.6), max = vec(0.95, 2.3, 0.9) },
  dinghy = { class = 14, vtype = 'boat', min = vec(-1.2, -3.0, -0.8), max = vec(1.2, 3.0, 1.2) },
  mule = { class = 20, vtype = 'automobile', min = vec(-1.3, -4.5, -1.0), max = vec(1.3, 4.5, 2.5) },
  -- a long car within maxSize (6.8 m), its centre ahead of the model origin
  longcar = { class = 1, vtype = 'automobile', min = vec(-1.1, -3.1, -0.6), max = vec(1.1, 3.7, 1.0) },
  s_m_m_trucker_01 = { ped = true },
  mp_m_freemode_01 = { ped = true },
}
local BY_HASH = {}
for name, m in pairs(MODELS) do m.name = name BY_HASH[joaat(name)] = m end

local function rotate(lx, ly, h)
  local r = math.rad(h)
  local rx, ry = math.cos(r), math.sin(r)       -- right
  local fx, fy = -math.sin(r), math.cos(r)      -- forward
  return rx * lx + fx * ly, ry * lx + fy * ly
end

local function ent(e) return W.entities[e] end

local function worldPos(e)
  local en = ent(e)
  if en.vehicle and ent(en.vehicle) then return worldPos(en.vehicle) end
  if en.attached and ent(en.attached.parent) then
    local p = ent(en.attached.parent)
    local px, py, pz = worldPos(en.attached.parent)
    local ox, oy = rotate(en.attached.x, en.attached.y, p.h)
    return px + ox, py + oy, pz + en.attached.z
  end
  return en.x, en.y, en.z
end

local function worldHeading(e)
  local en = ent(e)
  if en.vehicle and ent(en.vehicle) then return worldHeading(en.vehicle) end
  if en.attached and ent(en.attached.parent) then return (worldHeading(en.attached.parent) + en.attached.h) % 360 end
  return en.h
end

local function toLocal(e, wx, wy, wz)
  local x, y, z = worldPos(e)
  local h = math.rad(worldHeading(e))
  local dx, dy = wx - x, wy - y
  return dx * math.cos(h) + dy * math.sin(h), dx * -math.sin(h) + dy * math.cos(h), wz - z
end

local function newEntity(kind, model, x, y, z, h, owner, extra)
  W.nextId = W.nextId + 1
  local id = W.nextId
  local en = {
    id = id, type = kind, model = joaat(model), name = model, x = x, y = y, z = z, h = h or 0.0,
    owner = owner or -1, bucket = 0, netId = id + 5000, state = {}, orphan = 0, plate = ('T%05d'):format(id),
  }
  for k, v in pairs(extra or {}) do en[k] = v end
  W.entities[id] = en
  W.byNet[en.netId] = id
  return id
end

local function pedInSeat(veh, seat)
  for id, en in pairs(W.entities) do
    if en.type == 1 and en.vehicle == veh and en.seat == seat then return id end
  end
  return 0
end

local function nearestPlayerDist(x, y)
  local best = math.huge
  for _, p in pairs(W.players) do
    if not p.dropped and ent(p.ped) then
      local px, py = worldPos(p.ped)
      best = math.min(best, math.sqrt((px - x) ^ 2 + (py - y) ^ 2))
    end
  end
  return best
end

local function deleteWorld(e)
  local en = ent(e)
  if not en then return end
  local x, y, z = worldPos(e)
  -- invariant: a towed vehicle never vanishes near a player before it is on a bed; a tow
  -- truck never vanishes near a player (resource stop / instant deletions are excluded by the
  -- scenarios that expect them)
  local near = nearestPlayerDist(x, y)
  if en.state.nzTowing == true and not en.attached and near < 150.0 then
    W.nearDeletes[#W.nearDeletes + 1] = { what = 'vehicle', near = near, at = now }
  elseif en.name == 'flatbed' and near < 150.0 then
    W.nearDeletes[#W.nearDeletes + 1] = { what = 'truck', near = near, at = now }
  end
  for id, other in pairs(W.entities) do
    if other.attached and other.attached.parent == e then
      other.x, other.y, other.z = worldPos(id)
      other.h = worldHeading(id)
      other.attached = nil
    end
    if other.vehicle == e then
      other.vehicle, other.seat = nil, nil
      other.x, other.y, other.z = x + 2, y, z
    end
  end
  W.byNet[en.netId] = nil
  W.entities[e] = nil
  W.deleted[e] = en
  -- OneSync fires `entityRemoved` before the handle can be given to another entity
  if W.server then
    for _, fn in ipairs(W.server.handlers.entityRemoved or {}) do fn(e) end
  end
end

local function count(name)
  local n = 0
  for _, en in pairs(W.entities) do if en.name == name then n = n + 1 end end
  return n
end

--- What OneSync does with server-created entities: unowned until the nearest player of their
--- bucket within the culling range takes them over (a moment later); a ped in a vehicle is
--- simulated by the vehicle's owner.
local function assignOwners()
  for id, en in pairs(W.entities) do
    if en.serverCreated and en.owner == -1 and now - en.serverCreated >= (W.ownerDelay or 300) then
      local best, bestD = W.ownerOverride, W.cull
      if not best then
        local x, y = worldPos(id)
        for src, p in pairs(W.players) do
          if not p.dropped and p.bucket == en.bucket then
            local px, py = worldPos(p.ped)
            local d = math.sqrt((px - x) ^ 2 + (py - y) ^ 2)
            if d < bestD then best, bestD = src, d end
          end
        end
      end
      if best then en.owner = best end
    end
  end
  for _, en in pairs(W.entities) do
    if en.type == 1 and not en.isPlayer and en.vehicle and ent(en.vehicle) and ent(en.vehicle).owner ~= -1 then
      en.owner = ent(en.vehicle).owner
    end
  end
end

local function worldTick(dt)
  assignOwners()
  -- invariant: a truck never drives off (wander) without the vehicle it loaded
  for id, en in pairs(W.entities) do
    if en.name == 'flatbed' and en.drive and en.drive.wander and W.loadedBy[id] then
      local child = W.loadedBy[id]
      if ent(child) and not (ent(child).attached and ent(child).attached.parent == id) then
        local tx, ty = worldPos(id)
        local cx, cy = worldPos(child)
        if math.sqrt((tx - cx) ^ 2 + (ty - cy) ^ 2) > 3.0 then
          W.leftBehind[#W.leftBehind + 1] = { truck = id, at = now }
        end
      end
    end
  end
  for id, en in pairs(W.entities) do
    if en.type == 2 and en.drive and not en.attached and not W.blocked[id] and pedInSeat(id, -1) ~= 0 then
      local d = en.drive
      if d.wander then
        local fx, fy = rotate(0, 1, en.h)
        en.x, en.y = en.x + fx * d.speed * dt, en.y + fy * d.speed * dt
      else
        local dx, dy = d.x - en.x, d.y - en.y
        local dist = math.sqrt(dx * dx + dy * dy)
        if dist <= math.max(d.stop or 1.0, 0.5) then
          en.drive = nil
        else
          local s = math.min(dist, d.speed * dt)
          en.x, en.y = en.x + dx / dist * s, en.y + dy / dist * s
          -- backing up (DriveInReverse) keeps the heading
          if not d.reverse then en.h = math.deg(math.atan(-dx, dy)) % 360 end
        end
      end
    end
  end
end

local function run(ms)
  local untilAt = now + ms
  while now < untilAt do
    resumeAll()
    worldTick(TICK / 1000)
    now = now + TICK
  end
end

local function runUntil(cond, ms)
  local untilAt = now + ms
  while now < untilAt do
    if cond() then return true end
    resumeAll()
    worldTick(TICK / 1000)
    now = now + TICK
  end
  return cond()
end

---------------------------------------------------------------------------------------
-- Environments (server + one client per player)
---------------------------------------------------------------------------------------

local function readFile(p) local f = assert(io.open(p, 'r')) local s = f:read('a') f:close() return s end

local function connected(src)
  local p = W.players[tonumber(src) or -1]
  return p and not p.dropped and p or nil
end

--- A replicated state bag change: the change handlers of the server and of every client run.
local function bagChanged(en, key, value)
  local envs = { W.server }
  for _, p in pairs(W.players) do envs[#envs + 1] = p.env end
  for _, env in ipairs(envs) do
    if env and not env.dead then
      for _, h in ipairs(env.bagHandlers) do
        if h.key == key then addThread(env, h.fn, 'entity:' .. en.netId, key, value) end
      end
    end
  end
end

--- What `Entity(e).state:set(key, value, true)` on the entity's owning client does without
--- sv_stateBagStrictMode (a cheat menu clearing a tow bag).
local function ownerSetsBag(e, key, value)
  local en = ent(e)
  en.state[key] = value
  bagChanged(en, key, value)
end

local function stateProxy(e)
  local bag = setmetatable({}, {
    __index = function(_, k)
      if k == 'set' then
        return function(_, key, value)
          local en = ent(e)
          if not en then error('state bag of a missing entity') end
          en.state[key] = value
          bagChanged(en, key, value)
        end
      end
      local en = ent(e)
      return en and en.state[k] or nil
    end,
  })
  return { state = bag }
end

local function makeEnv(side, src)
  local env = { side = side, src = src, handlers = {}, bagHandlers = {} }
  for _, k in ipairs({ 'assert', 'error', 'ipairs', 'pairs', 'next', 'pcall', 'xpcall', 'select', 'tonumber',
    'tostring', 'type', 'setmetatable', 'getmetatable', 'rawget', 'rawset', 'rawequal', 'rawlen', 'string',
    'table', 'math', 'coroutine', 'utf8', 'os', 'print', 'load' }) do
    env[k] = _G[k]
  end
  env._G = env
  env.vector3, env.vec3, env.vec = vec, vec, vec
  env.vector4, env.vec4 = vec4, vec4
  env.joaat, env.GetHashKey = joaat, joaat
  env.json = { encode = function() return '{}' end, decode = function() return nil end }
  env.Wait = function(ms) if coroutine.isyieldable() then coroutine.yield(ms or 0) end end
  env.CreateThread = function(fn) addThread(env, fn) end
  env.SetTimeout = function(ms, fn) addThread(env, function() env.Wait(ms) fn() end) end
  env.Citizen = { CreateThread = env.CreateThread, Wait = env.Wait, SetTimeout = env.SetTimeout }
  env.GetGameTimer = function() return now end
  env.GetCurrentResourceName = function() return 'nayzeee-garages' end
  env.IsDuplicityVersion = function() return side == 'server' end
  env.GetResourceState = function() return 'missing' end
  env.GetInvokingResource = function() return nil end
  env.RegisterNetEvent = function(name, fn) if fn then env.AddEventHandler(name, fn) end end
  env.AddEventHandler = function(name, fn)
    env.handlers[name] = env.handlers[name] or {}
    table.insert(env.handlers[name], fn)
  end
  env.TriggerEvent = function(name, ...)
    for _, fn in ipairs(env.handlers[name] or {}) do addThread(env, fn, ...) end
  end
  env.AddStateBagChangeHandler = function(key, _, fn) env.bagHandlers[#env.bagHandlers + 1] = { key = key, fn = fn } return 1 end
  env.Entity = stateProxy
  env.exports = setmetatable({}, {
    __index = function() return {} end,
    __call = function(_, name, fn) if side == 'server' then W.exports[name] = fn end end,
  })
  env.lib = {
    print = {
      info = function() end,
      warn = function(...) W.warnings[#W.warnings + 1] = table.concat({ ... }, ' ') end,
      error = function(...) W.errors[#W.errors + 1] = ('[%s] %s %s'):format(scenarioName, side, table.concat({ ... }, ' ')) end,
    },
    callback = {
      register = function(name, fn) W.callbacks[name] = fn end,
      await = function(name, _, payload)
        local fn = W.callbacks[name]
        if not fn then error('no server callback ' .. name) end
        local entry = { src = src, at = now, stage = type(payload) == 'table' and payload.stage, id = type(payload) == 'table' and payload.id }
        W.reports[#W.reports + 1] = entry
        -- the server runs the handler in its own thread: it finishes even when this client drops
        local box = {}
        addThread(W.server, function() box.result = fn(src, payload) box.done = true end)
        while not box.done do coroutine.yield(0) end
        local result = box.result
        entry.ok, entry.code = type(result) == 'table' and result.ok, type(result) == 'table' and result.code
        return result
      end,
    },
    requestModel = function() return true end,
    requestAnimDict = function() return true end,
  }

  -- shared natives
  env.DoesEntityExist = function(e) return ent(e) ~= nil end
  env.GetEntityType = function(e) local en = ent(e) return en and en.type or 0 end
  env.GetEntityModel = function(e) local en = ent(e) return en and en.model or 0 end
  env.GetEntityCoords = function(e) if not ent(e) then return vec(0, 0, 0) end return vec(worldPos(e)) end
  env.GetEntityHeading = function(e) if not ent(e) then return 0.0 end return worldHeading(e) end
  env.NetworkGetEntityFromNetworkId = function(netId) return W.byNet[netId] or 0 end
  env.NetworkGetNetworkIdFromEntity = function(e) local en = ent(e) return en and en.netId or 0 end
  env.NetworkGetEntityOwner = function(e) local en = ent(e) return en and en.owner or -1 end
  env.GetPlayerPed = function(id) local p = connected(id) return p and p.ped or 0 end
  env.GetPlayerName = function(id) local p = connected(id) return p and p.name or nil end
  env.GetVehicleNumberPlateText = function(e) local en = ent(e) return en and en.plate or '' end
  env.GetPedInVehicleSeat = function(veh, seat) return pedInSeat(veh, seat) end
  env.GetVehiclePedIsIn = function(ped) local en = ent(ped) return en and en.vehicle or 0 end
  env.GetEntityFromStateBagName = function(bag) local n = tonumber(bag:match('entity:(%d+)')) return n and W.byNet[n] or 0 end

  if side == 'server' then
    env.GetPlayers = function()
      local list = {}
      for id, p in pairs(W.players) do if not p.dropped then list[#list + 1] = tostring(id) end end
      table.sort(list)
      return list
    end
    env.GetPlayerRoutingBucket = function(id) local p = connected(id) return p and p.bucket or 0 end
    env.GetEntityRoutingBucket = function(e) local en = ent(e) return en and en.bucket or 0 end
    env.IsPedAPlayer = function(e) local en = ent(e) return en ~= nil and en.isPlayer == true end
    env.GetVehicleType = function(e) local en = ent(e) local m = en and BY_HASH[en.model] return m and m.vtype or nil end
    env.SetVehicleDoorsLocked = function(e, n) local en = ent(e) if en then en.locked = n end end
    env.SetEntityOrphanMode = function(e, m) local en = ent(e) if en then en.orphan = m end end
    env.GetEntityAttachedTo = function(e) local en = ent(e) return en and en.attached and en.attached.parent or 0 end
    env.DeleteEntity = function(e) deleteWorld(e) end
    env.CreateVehicleServerSetter = function(model, vtype, x, y, z, h)
      local m = BY_HASH[model]
      if W.noServerSetter then error('CreateVehicleServerSetter: unknown native') end
      if not m or m.ped or vtype ~= 'automobile' then return 0 end
      W.created[#W.created + 1] = { kind = 'vehicle', x = x, y = y, z = z, h = h }
      return newEntity(2, m.name, x, y, z, h, -1, { serverCreated = now })
    end
    env.CreatePed = function(_, model, x, y, z, h)
      local m = BY_HASH[model]
      if not m or not m.ped then return 0 end
      W.created[#W.created + 1] = { kind = 'ped', x = x, y = y, z = z, h = h }
      return newEntity(1, m.name, x, y, z, h, -1, { serverCreated = now })
    end
    env.SetEntityRoutingBucket = function(e, b) local en = ent(e) if en then en.bucket = b end end
    -- RPC natives: carried out by the entity's owner (nothing happens without one)
    env.SetPedIntoVehicle = function(ped, veh, seat)
      local en = ent(ped)
      if en and en.owner ~= -1 and ent(veh) and not W.seatRpcLost then en.vehicle, en.seat = veh, seat end
    end
    env.SetVehicleNumberPlateText = function(e, text) local en = ent(e) if en and en.owner ~= -1 then en.plate = text end end
    env.TriggerClientEvent = function(name, target, ...)
      W.sent[#W.sent + 1] = { name = name, target = target, args = table.pack(...) }
      if name == 'nz:client:notify' then
        local payload = ...
        W.notified[#W.notified + 1] = { target = target, message = type(payload) == 'table' and payload.message }
        return
      end
      local p = connected(target)
      if not p or not p.env or p.env.dead or p.deaf then return end
      for _, fn in ipairs(p.env.handlers[name] or {}) do addThread(p.env, fn, ...) end
    end
  else
    local function owns(e) local en = ent(e) return en and en.owner == src end
    env.PlayerId = function() return src end
    env.PlayerPedId = function() return W.players[src].ped end
    env.GetActivePlayers = function()
      local list = {}
      for id, p in pairs(W.players) do if not p.dropped then list[#list + 1] = id end end
      return list
    end
    env.NetworkDoesNetworkIdExist = function(netId) return W.byNet[netId] ~= nil end
    env.NetworkGetEntityIsNetworked = function(e) return ent(e) ~= nil end
    env.GetEntityForwardVector = function(e) local fx, fy = rotate(0, 1, worldHeading(e)) return vec(fx, fy, 0) end
    env.GetOffsetFromEntityInWorldCoords = function(e, x, y, z)
      local px, py, pz = worldPos(e)
      local ox, oy = rotate(x, y, worldHeading(e))
      return vec(px + ox, py + oy, pz + z)
    end
    env.GetOffsetFromEntityGivenWorldCoords = function(e, x, y, z) return vec(toLocal(e, x, y, z)) end
    env.GetModelDimensions = function(model)
      local m = BY_HASH[model] or MODELS.sultan
      return m.min or vec(-0.3, -0.3, -1), m.max or vec(0.3, 0.3, 1)
    end
    env.GetVehicleClass = function(e) local en = ent(e) local m = en and BY_HASH[en.model] return m and m.class or 0 end
    env.IsThisModelABoat = function(model) local m = BY_HASH[model] return m ~= nil and m.vtype == 'boat' end
    env.IsThisModelAHeli = function() return false end
    env.IsThisModelAPlane = function() return false end
    env.IsThisModelATrain = function() return false end
    env.IsModelInCdimage = function(model) return BY_HASH[model] ~= nil end
    env.IsModelAVehicle = function(model) local m = BY_HASH[model] return m ~= nil and not m.ped end
    env.IsModelAPed = function(model) local m = BY_HASH[model] return m ~= nil and m.ped == true end
    env.HasModelLoaded = function() return true end
    env.IsEntityAttached = function(e) local en = ent(e) return en ~= nil and en.attached ~= nil end
    env.IsEntityAttachedToEntity = function(a, b) local en = ent(a) return en ~= nil and en.attached ~= nil and en.attached.parent == b end
    env.IsVehicleAttachedToTrailer = function() return false end
    env.IsVehicleSeatFree = function(veh, seat) return pedInSeat(veh, seat) == 0 end
    env.GetVehicleNumberOfPassengers = function(veh)
      local n = 0
      for _, en in pairs(W.entities) do if en.vehicle == veh and en.seat ~= -1 then n = n + 1 end end
      return n
    end
    env.AreNodesLoadedForArea = function() return true end
    -- roads run east-west every 40 m
    env.GetClosestVehicleNodeWithHeading = function(x, y, z)
      return true, vec(math.floor(x / 5 + 0.5) * 5, math.floor(y / 40 + 0.5) * 40, z), 270.0
    end
    env.GetNthClosestVehicleNodeWithHeading = function(x, y, z, n)
      return true, vec(x + n * 8, math.floor(y / 40 + 0.5) * 40, z), 270.0, 2
    end
    env.IsSphereVisible = function(x, y, z)
      local px, py, pz = worldPos(W.players[src].ped)
      return math.sqrt((x - px) ^ 2 + (y - py) ^ 2 + (z - pz) ^ 2) < W.sight
    end
    env.IsEntityOnScreen = function(e)
      local x, y, z = worldPos(e)
      return env.IsSphereVisible(x, y, z) and W.screenRealistic == true
    end
    env.GetGamePool = function(kind)
      local list = {}
      if kind == 'CVehicle' then for id, en in pairs(W.entities) do if en.type == 2 then list[#list + 1] = id end end end
      return list
    end
    env.IsAnyVehicleNearPoint = function() return false end
    env.IsPointOnRoad = function() return true end
    env.IsVehicleStopped = function(e) local en = ent(e) return en ~= nil and (en.drive == nil or W.blocked[e] == true) end
    env.CreateVehicle = function(model, x, y, z, h, isNet)
      W.clientCreated = (W.clientCreated or 0) + 1
      local m = BY_HASH[model]
      if not m or m.ped or not isNet or W.lockdown then return 0 end
      return newEntity(2, m.name, x, y, z, h, src, { bucket = W.players[src].bucket })
    end
    env.CreatePedInsideVehicle = function(veh, _, model, seat)
      local m = BY_HASH[model]
      if not m or not m.ped or not ent(veh) then return 0 end
      return newEntity(1, m.name, 0, 0, 0, 0, src, { vehicle = veh, seat = seat, bucket = W.players[src].bucket })
    end
    env.SetVehicleNumberPlateText = function(e, text) if owns(e) then ent(e).plate = text end end
    env.SetPedIntoVehicle = function(ped, veh, seat) if owns(ped) and ent(veh) then local en = ent(ped) en.vehicle, en.seat = veh, seat end end
    env.NetworkFadeOutEntity = function(e) if owns(e) then W.faded[e] = (W.faded[e] or 0) + 1 end end
    env.TaskVehicleDriveToCoordLongrange = function(ped, veh, x, y, z, speed, style, stop)
      W.longrange[#W.longrange + 1] = { speed = speed, style = math.tointeger(style) or 0, at = now }
      if owns(ped) and ent(veh) then ent(veh).drive = { x = x, y = y, speed = speed, stop = stop } end
    end
    env.TaskVehicleDriveToCoord = function(ped, veh, x, y, z, speed, _, _, style, stop)
      local reverse = ((math.tointeger(style) or 0) & 1024) ~= 0
      if owns(ped) and ent(veh) then ent(veh).drive = { x = x, y = y, speed = speed, stop = stop, reverse = reverse } end
    end
    -- line of sight from another player to an entity (the caller checks the distance)
    env.HasEntityClearLosToEntity = function() return W.los == true end
    env.TaskVehicleTempAction = function(ped, veh, action)
      if owns(ped) and ent(veh) then
        local en = ent(veh)
        en.drive = nil
        W.tempActions[#W.tempActions + 1] = { action = action, at = now }
        if action == 3 and not W.blocked[veh] and not en.attached then
          -- backs out a little
          local fx, fy = rotate(0, 1, en.h)
          en.x, en.y = en.x - fx * 2.0, en.y - fy * 2.0
        end
      end
    end
    env.GetEntitySpeed = function(e)
      local en = ent(e)
      if not en or not en.drive or W.blocked[e] or en.attached then return 0.0 end
      return en.drive.speed or 0.0
    end
    env.IsVehicleStoppedAtTrafficLights = function(e) return W.redLight == e end
    env.CalculateTravelDistanceBetweenPoints = function(x1, y1, z1, x2, y2, z2)
      if W.route then return W.route(x1, y1, x2, y2) end
      return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2) * 1.3
    end
    -- OneSync control: granted unless the owner keeps the entity (SetNetworkIdCanMigrate false)
    env.NetworkRequestControlOfEntity = function(e)
      local en = ent(e)
      W.controlRequests[#W.controlRequests + 1] = { src = src, e = e }
      if not en or en.isPlayer or W.noControl or en.owner == src then return end
      if en.noMigrate and connected(en.owner) then return end
      en.owner, en.noMigrate = src, nil
    end
    env.SetNetworkIdCanMigrate = function(netId, can)
      local e = W.byNet[netId]
      if e and owns(e) then ent(e).noMigrate = not can end
    end
    env.TaskVehicleDriveWander = function(ped, veh, speed)
      if owns(ped) then W.pedTask[ped] = 'wander' end
      if owns(ped) and ent(veh) then ent(veh).drive = { wander = true, speed = speed } end
    end
    -- the driver's latest task (enter / warp / wander / clear)
    env.ClearPedTasks = function(ped) if owns(ped) then W.pedTask[ped] = 'clear' end end
    env.IsEntityDead = function() return false end
    env.TaskLeaveVehicle = function(ped, veh)
      local en = ent(ped)
      if owns(ped) and en.vehicle == veh then
        local x, y, z = worldPos(veh)
        en.vehicle, en.seat, en.x, en.y, en.z = nil, nil, x - 2, y, z
      end
    end
    env.IsPedInVehicle = function(ped, veh) local en = ent(ped) return en ~= nil and en.vehicle == veh end
    env.TaskGoStraightToCoord = function(ped, x, y, z) if owns(ped) then local en = ent(ped) en.x, en.y, en.z = x, y, z end end
    env.TaskEnterVehicle = function(ped, veh)
      if owns(ped) then W.pedTask[ped] = 'enter' end
      if owns(ped) and ent(veh) then local en = ent(ped) en.vehicle, en.seat = veh, -1 end
    end
    env.TaskWarpPedIntoVehicle = function(ped, veh)
      if owns(ped) then W.pedTask[ped] = 'warp' end
      if owns(ped) and ent(veh) then local en = ent(ped) en.vehicle, en.seat = veh, -1 end
    end
    env.SetEntityCoords = function(e, x, y, z) if owns(e) then local en = ent(e) en.x, en.y, en.z = x, y, z end end
    env.SetEntityHeading = function(e, h) if owns(e) then ent(e).h = h end end
    env.GetEntityBoneIndexByName = function() return 5 end
    env.GetWorldPositionOfEntityBone = function(e) return vec(worldPos(e)) end
    env.StartExpensiveSynchronousShapeTestLosProbe = function(x, y) W.probe = { x = x, y = y } return 1 end
    env.GetShapeTestResult = function()
      for id, en in pairs(W.entities) do
        if en.name == 'flatbed' then
          local tx, ty, tz = worldPos(id)
          if math.sqrt((tx - W.probe.x) ^ 2 + (ty - W.probe.y) ^ 2) < 8 then return 2, true, vec(W.probe.x, W.probe.y, tz + 0.6), vec(0, 0, 1), id end
        end
      end
      return 2, false, vec(0, 0, 0), vec(0, 0, 0), 0
    end
    env.AttachEntityToEntity = function(child, parent, _, x, y, z, rx, _, rz)
      if owns(child) and ent(parent) then
        ent(child).attached = { parent = parent, x = x, y = y, z = z, h = rz }
        W.loadedBy[parent] = child
        W.attachLog[child] = W.attachLog[child] or {}
        table.insert(W.attachLog[child], { x = x, y = y, z = z, p = rx, h = rz, truckH = worldHeading(parent), targetH = ent(child).h })
      end
    end
    env.DeleteEntity = function(e) if owns(e) then deleteWorld(e) end end
    env.GetVehiclePedIsTryingToEnter = function() return 0 end
  end

  setmetatable(env, {
    __index = function(_, k)
      if type(k) == 'string' and k:match('^[A-Z]') then return function() return nil end end
      return nil
    end,
  })
  return env
end

local function loadInto(env, file)
  local chunk, err = load(readFile(file), '@' .. file, 't', env)
  if not chunk then error(err) end
  chunk()
end

local BASE = { 'config/config.lua', 'config/interiors.lua', 'config/carlock.lua', 'shared/init.lua', 'shared/utils.lua' }

--- Fresh world: server (tow + impound) and the given players (each with a client).
local function scenario(name, players)
  scenarioName = name
  threads = {}
  W = {
    entities = {}, byNet = {}, deleted = {}, nextId = 100, players = {}, callbacks = {}, sent = {}, notified = {},
    exports = {}, logs = {}, warnings = {}, errors = printedErrors, reports = {}, blocked = {}, sight = 100.0, rate = {}, rows = {},
    created = {}, faded = {}, attachLog = {}, cull = 424.0, pedTask = {},
    nearDeletes = {}, leftBehind = {}, loadedBy = {}, tempActions = {}, controlRequests = {}, longrange = {},
  }
  local server = makeEnv('server', nil)
  for _, f in ipairs(BASE) do loadInto(server, f) end
  local NZ = server.NZ
  NZ.Ready = true
  NZ.Logs.add = function(event, src, data) W.logs[#W.logs + 1] = { event = event, src = src, data = data, at = now } end
  NZ.Access.rateLimit = function(src, bucket, ms)
    local key = tostring(src) .. ':' .. bucket
    if W.rate[key] and now - W.rate[key] < ms then return false end
    W.rate[key] = now
    return true
  end
  NZ.Access.jobAllowed = function() return true end
  NZ.Locations.get = function(id) if id == 1 then return W.impound end return nil end
  NZ.Locations.all = function() return { W.impound } end
  NZ.DB.getVehicle = function(plate) return W.rows[plate] end
  NZ.DB.updateVehicle = function(plate, fields)
    W.updated = { plate = plate, fields = fields }
    return true
  end
  NZ.Vehicles.out = {}
  NZ.Vehicles.withLock = function(_, fn) return fn() end
  NZ.Vehicles.vehicleTypeOf = function(row) return row.vehicleType or 'car' end
  NZ.CarLock.setLocked = function(e, locked) W.carlockLocked = { e = e, locked = locked } return true end
  W.impound = { id = 1, kind = 'impound', name = 'LS Impound', vehicleType = 'car', jobs = { { name = 'police' } },
    openPoints = { { coords = { x = 400.0, y = 0.0, z = 30.0 } } }, defaultFee = 100, defaultHours = 0 }
  loadInto(server, 'server/impound.lua')
  loadInto(server, 'server/towtruck.lua')
  W.server = server

  for _, p in ipairs(players or {}) do
    local env = makeEnv('client', p.src)
    local ped = newEntity(1, 'mp_m_freemode_01', p.x, p.y, 30.0, 0.0, p.src)
    W.players[p.src] = { src = p.src, name = 'Player' .. p.src, ped = ped, bucket = p.bucket or 0, env = env }
    ent(ped).isPlayer = true
    for _, f in ipairs(BASE) do loadInto(env, f) end
    loadInto(env, 'client/towtruck.lua')
  end
  run(200)
  return server.NZ
end

local function car(model, x, y, owner, extra)
  return newEntity(2, model or 'sultan', x, y, 30.0, extra and extra.h or 0.0, owner, extra)
end

local function drop(src)
  local p = W.players[src]
  p.dropped = true
  p.env.dead = true
  -- what OneSync does: the dropped client's entities migrate to the nearest relevant player;
  -- with nobody around they are kept unowned (orphan mode 2 / existing vehicles) or removed
  for id, en in pairs(W.entities) do
    if en.owner == src and id ~= p.ped then
      local best, bestD = nil, 424.0
      local x, y = worldPos(id)
      for other, q in pairs(W.players) do
        if not q.dropped then
          local px, py = worldPos(q.ped)
          local d = math.sqrt((px - x) ^ 2 + (py - y) ^ 2)
          if d < bestD then best, bestD = other, d end
        end
      end
      en.noMigrate = nil
      if best then en.owner = best
      elseif en.orphan == 2 or en.persistent or en.serverCreated then en.owner = -1
      else deleteWorld(id) end
    end
  end
  deleteWorld(p.ped)
  for _, fn in ipairs(W.server.handlers.playerDropped or {}) do
    W.server.source = src
    fn('quit')
    W.server.source = nil
  end
end

local function lastLog(event)
  for i = #W.logs, 1, -1 do if W.logs[i].event == event then return W.logs[i] end end
  return nil
end

local function towOutcome() local l = lastLog('impound.tow') return l and l.data.outcome, l and l.data.reason end

local function stopResource()
  for _, env in ipairs({ W.server }) do
    for _, fn in ipairs(env.handlers.onResourceStop or {}) do fn('nayzeee-garages') end
  end
  for _, p in pairs(W.players) do
    if not p.dropped then for _, fn in ipairs(p.env.handlers.onResourceStop or {}) do fn('nayzeee-garages') end end
  end
end

local function noNpcs(label)
  check(count('flatbed') == 0, label .. ': no tow truck left')
  check(count('s_m_m_trucker_01') == 0, label .. ': no driver left')
end

--- A report of this stage was answered by the server.
local function sawStage(stage, src)
  for _, r in ipairs(W.reports) do if r.stage == stage and r.ok ~= nil and (src == nil or r.src == src) then return true end end
  return false
end

--- The tow ended and what faded out is gone (FADE_MS on the server).
local FADE_WAIT = 1300
local function finished()
  local l = lastLog('impound.tow')
  return l ~= nil and now - l.at >= FADE_WAIT
end

--- Every player walks far away: what was retired near them goes (cleanup only far from players).
local function leaveScene()
  for _, p in pairs(W.players) do
    if not p.dropped and ent(p.ped) then ent(p.ped).x = ent(p.ped).x + 5000.0 end
  end
  run(2500)
end

--- Invariants: no towed vehicle (not on a bed) and no tow truck vanished near a player, and no
--- truck drove off without the vehicle it had loaded.
local function nothingVanished(label)
  local first = W.nearDeletes[1]
  check(first == nil, ('%s: nothing vanished near a player%s'):format(label,
    first and (' (%s %.0f m away at %d ms)'):format(first.what, first.near, first.at) or ''))
  check(#W.leftBehind == 0, label .. ': no truck left without its vehicle')
end

local function find(name)
  for id, en in pairs(W.entities) do if en.name == name then return id end end
  return nil
end

local function trucks()
  local n = 0
  for _, c in ipairs(W.created) do if c.kind == 'vehicle' then n = n + 1 end end
  return n
end

--- The `stop` + `dismiss` event the server sent (to `src` when given), or nil.
local function dismissedTo(src)
  for _, ev in ipairs(W.sent) do
    local d = ev.args[1]
    if ev.name == 'nz:client:tow:stop' and type(d) == 'table' and d.dismiss == true and (src == nil or ev.target == src) then
      return d
    end
  end
  return nil
end

local FAILED_TEXT = 'The tow truck could not collect the vehicle'
local function notifiedOf(src, message)
  for _, n in ipairs(W.notified) do if n.target == src and n.message == message then return true end end
  return false
end

--- -v: the reports of the scenario and how its tows ended.
local function trace()
  if not VERBOSE then return end
  local parts = {}
  for _, r in ipairs(W.reports) do
    parts[#parts + 1] = ('%s@%d:%s%s'):format(r.stage, r.src, tostring(r.at // 100 / 10),
      r.ok == false and ('!' .. tostring(r.code)) or '')
  end
  print(('-- %s: %s'):format(scenarioName, table.concat(parts, ' ')))
  for _, l in ipairs(W.logs) do
    if l.event == 'impound.tow' then
      print(('   tow %s: %s / %s (handovers %s, %ss)'):format(tostring(l.data.plate), tostring(l.data.outcome),
        tostring(l.data.reason), tostring(l.data.handovers), tostring(l.data.seconds)))
    end
  end
end

---------------------------------------------------------------------------------------
-- Scenarios
---------------------------------------------------------------------------------------

do -- 1. the whole sequence: officer runs it, owns the vehicle (attaches it himself)
  local NZ = scenario('full', { { src = 1, x = 0.0, y = -6.0 } })
  local target = car('sultan', 5.0, 0.0, 1)
  local started = NZ.Tow.start(target, 1)
  check(started == true, 'tow started')
  check(ent(target).locked == 2, 'vehicle locked server-side')
  check(ent(target).state.nzTowing == true, 'nzTowing state bag set')
  check(W.carlockLocked and W.carlockLocked.e == target and W.carlockLocked.locked == true, 'car lock state kept in line')
  check(NZ.Tow.isTowing(target), 'isTowing(vehicle)')
  check(runUntil(function() return count('flatbed') == 1 end, 5000), 'truck spawned')
  local truck
  for id, en in pairs(W.entities) do if en.name == 'flatbed' then truck = id end end
  local tx, ty = worldPos(truck)
  local d = math.sqrt((tx - 5) ^ 2 + ty ^ 2)
  check(d >= 80 and d <= 150, ('truck spawned 80-150 m away (%.1f)'):format(d))
  check(ent(truck).orphan == 2 and ent(truck).state.nzTowTruck == true, 'server keeps the truck (orphan mode 2, nzTowTruck)')
  check(ent(target).orphan == 2, 'server keeps the impounded vehicle (orphan mode 2)')
  check(ent(truck).serverCreated ~= nil, 'truck created by the server')
  check(runUntil(function() return sawStage('spawned') end, 5000), 'spawned reported')
  check(ent(truck).owner == 1 and ent(truck).noMigrate == true, 'the runner simulates the truck and keeps it')
  check(ent(truck).plate == 'IMPOUND', 'truck plate')
  run(500)
  local told = false
  for _, n in ipairs(W.notified) do if n.target == 1 and n.message == 'Tow truck dispatched' then told = true end end
  check(told, 'officer told "Tow truck dispatched"')
  check(runUntil(function() return sawStage('arrived') end, 40000), 'truck arrived')
  do
    -- in front of the vehicle (heading 0 at 5,0), in line with it, the rear of the bed to its nose
    local lx, ly = toLocal(target, worldPos(truck))
    check(ly > 4.0 and math.abs(lx) < 1.5 and math.abs((worldHeading(truck) + 180) % 360 - 180) < 35,
      ('stopped in front of the vehicle, in line (x=%.1f y=%.1f h=%.0f)'):format(lx, ly, worldHeading(truck)))
  end
  check(runUntil(function() return sawStage('load') end, 20000), 'driver at the controls, loading')
  check(ent(target).owner == 1 and ent(target).noMigrate == true, 'the runner keeps the vehicle while loading')
  local driver
  for id, en in pairs(W.entities) do if en.name == 's_m_m_trucker_01' then driver = id end end
  check(driver and ent(driver).vehicle == nil, 'driver stepped out to work the controls')
  check(runUntil(function() return ent(target) and ent(target).attached ~= nil end, 4000), 'vehicle being pulled onto the bed')
  check(runUntil(function() return sawStage('loaded') end, 15000), 'loaded')
  local a = ent(target).attached
  check(a and a.parent == truck, 'vehicle attached to the truck')
  check(a and math.abs(a.y - (-2.35)) < 0.01 and math.abs(a.z - (0.6 + 0.6)) < 0.01, ('vehicle sits on the bed (y=%.2f z=%.2f)'):format(a and a.y or 0, a and a.z or 0))
  do
    -- tilted nose up (nose first: positive pitch) while it climbs, level on the bed
    local poses, most = W.attachLog[target] or {}, 0.0
    for _, p in ipairs(poses) do most = math.max(most, p.p or 0.0) end
    check(most > 5.0 and most <= 10.01, ('tilted up the ramp (%.1f deg)'):format(most))
    check(poses[#poses] and poses[#poses].p == 0.0, 'level on the bed')
  end
  check(runUntil(function() return sawStage('leaving') end, 15000), 'leaving')
  check(driver and ent(driver) and ent(driver).vehicle == truck, 'driver back in the truck')
  -- a few seconds into the drive: still on the bed
  run(3000)
  check(ent(target) and ent(target).attached and ent(target).attached.parent == truck, 'drives off with the vehicle on the bed')
  check(runUntil(finished, 70000), 'tow finished')
  local outcome, reason = towOutcome()
  check(outcome == 'done', 'outcome done (' .. tostring(outcome) .. '/' .. tostring(reason) .. ')')
  check(ent(target) == nil, 'impounded vehicle deleted')
  noNpcs('full')
  nothingVanished('full')
  check(ent(W.players[1].ped) ~= nil, 'runner still there')
  check(not NZ.Tow.isTowing(target), 'nothing tracked any more')
  check(not notifiedOf(1, FAILED_TEXT) and dismissedTo() == nil, 'no failure notice, nothing dismissed')
  say('full: ' .. tostring(outcome) .. ' ' .. tostring(reason) .. ' at ' .. now .. ' ms')
  trace()
end

do -- 2. another player owns the vehicle and keeps it (control refused): that client attaches it
  local NZ = scenario('remote attach', { { src = 1, x = 0.0, y = -6.0 }, { src = 2, x = 12.0, y = -8.0 } })
  W.ownerOverride = 1 -- the officer simulates the truck (runs the tow), player 2 the vehicle
  W.noControl = true
  local target = car('sultan', 5.0, 0.0, 2)
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(function() return sawStage('load', 1) end, 60000), 'loading')
  local attachSent = false
  for _, s in ipairs(W.sent) do if s.name == 'nz:client:tow:attach' and s.target == 2 then attachSent = true end end
  check(attachSent, 'attach asked from the vehicle owner')
  check(runUntil(function() return sawStage('attached', 2) end, 15000), 'owner reported the attachment')
  check(runUntil(function() return sawStage('loaded', 1) end, 15000), 'runner saw it loaded')
  check(runUntil(finished, 90000), 'finished')
  check(towOutcome() == 'done', 'outcome done')
  check(ent(target) == nil, 'vehicle deleted')
  noNpcs('remote attach')
  nothingVanished('remote attach')
  trace()
end

do -- 2b. another player owns the vehicle: the runner takes control of it and pulls it on itself
  local NZ = scenario('runner takes the vehicle', { { src = 1, x = 0.0, y = -6.0 }, { src = 2, x = 12.0, y = -8.0 } })
  W.ownerOverride = 1
  local target = car('sultan', 5.0, 0.0, 2)
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(function() return sawStage('load', 1) end, 60000), 'loading')
  local asked = false
  for _, r in ipairs(W.controlRequests) do if r.src == 1 and r.e == target then asked = true end end
  check(asked and ent(target).owner == 1 and ent(target).noMigrate == true, 'runner took control of the vehicle and keeps it')
  local remote = false
  for _, ev in ipairs(W.sent) do if ev.name == 'nz:client:tow:attach' then remote = true end end
  check(not remote, 'no other client asked to attach')
  check(runUntil(finished, 90000) and towOutcome() == 'done', 'done (' .. tostring(select(2, towOutcome())) .. ')')
  noNpcs('runner takes the vehicle')
  nothingVanished('runner takes the vehicle')
  trace()
end

do -- 3. two impounds at once by the same officer
  local NZ = scenario('two at once', { { src = 1, x = 0.0, y = -6.0 } })
  local a = car('sultan', 5.0, 0.0, 1)
  local b = car('sultan', 5.0, -14.0, 1, { h = 180.0 })
  check(NZ.Tow.start(a, 1) and NZ.Tow.start(b, 1), 'both tows started')
  check(NZ.Tow.start(a, 1) == true and count('flatbed') == 0, 'impounding the same vehicle again adds nothing')
  check(runUntil(function() return count('flatbed') == 2 end, 8000), 'two trucks')
  local p = {}
  for _, c in ipairs(W.created) do if c.kind == 'vehicle' then p[#p + 1] = { c.x, c.y } end end
  say(('two at once: nodes %.0f,%.0f / %.0f,%.0f'):format(p[1][1], p[1][2], p[2] and p[2][1] or 0, p[2] and p[2][2] or 0))
  check(#p == 2 and math.sqrt((p[1][1] - p[2][1]) ^ 2 + (p[1][2] - p[2][2]) ^ 2) > 10, 'different spawn nodes')
  check(runUntil(function()
    local n = 0
    for _, l in ipairs(W.logs) do if l.event == 'impound.tow' then n = n + 1 end end
    return n == 2
  end, 150000), 'both finished')
  run(FADE_WAIT)
  for _, l in ipairs(W.logs) do
    if l.event == 'impound.tow' then check(l.data.outcome == 'done', 'tow ' .. tostring(l.data.plate) .. ' done (' .. tostring(l.data.reason) .. ')') end
  end
  check(ent(a) == nil and ent(b) == nil, 'both vehicles deleted')
  noNpcs('two at once')
  nothingVanished('two at once')
  trace()
end

do -- 4. the runner disconnects on the way: the nearby player adopts truck + driver
  local NZ = scenario('runner drops, handed over', { { src = 1, x = 0.0, y = -6.0 }, { src = 2, x = 30.0, y = -10.0 } })
  local target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(function() return sawStage('spawned', 1) end, 6000), 'spawned by the officer')
  run(1000)
  drop(1)
  check(runUntil(function() return sawStage('spawned', 2) end, 8000), 'player 2 adopted the NPCs')
  local adopted = false
  for _, s in ipairs(W.sent) do
    if s.name == 'nz:client:tow:start' and s.target == 2 and type(s.args[1]) == 'table' and s.args[1].truck then adopted = true end
  end
  check(adopted, 'start sent with the truck + driver to adopt')
  check(count('flatbed') == 1, 'still one truck')
  check(runUntil(finished, 120000), 'finished')
  check(towOutcome() == 'done', 'outcome done (' .. tostring(select(2, towOutcome())) .. ')')
  check(ent(target) == nil, 'vehicle deleted')
  noNpcs('handover')
  nothingVanished('handover')
  trace()
end

do -- 5. the runner disconnects and nobody else is around: fall back
  local NZ = scenario('runner drops, nobody left', { { src = 1, x = 0.0, y = -6.0 } })
  local target = car('sultan', 5.0, 0.0, 1, { persistent = true })
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(function() return sawStage('spawned', 1) end, 6000), 'spawned')
  run(1000)
  drop(1)
  check(runUntil(finished, 10000), 'finished')
  local outcome, reason = towOutcome()
  check(outcome == 'fallback' and reason == 'runner:dropped', 'fell back: ' .. tostring(reason))
  check(ent(target) == nil, 'vehicle deleted')
  noNpcs('dropped')
  trace()
end

do -- 6. the runner walks away: another player sends a new truck
  local NZ = scenario('runner leaves', { { src = 1, x = 0.0, y = -6.0 }, { src = 2, x = 20.0, y = -10.0 } })
  local target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(function() return sawStage('spawned', 1) end, 6000), 'spawned')
  ent(W.players[1].ped).x = 900.0
  check(runUntil(function() return sawStage('spawned', 2) end, 15000), 'player 2 took over')
  run(FADE_WAIT)
  check(count('flatbed') == 1 and trucks() == 1, 'the same truck carries on (released by the old runner, taken by the new one)')
  check(runUntil(finished, 120000), 'finished')
  check(towOutcome() == 'done', 'outcome done')
  noNpcs('leaves')
  nothingVanished('leaves')
  trace()
end

do -- 7. the runner's client never answers
  local NZ = scenario('silent runner', { { src = 1, x = 0.0, y = -6.0 } })
  W.players[1].deaf = true
  local target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(finished, 40000), 'finished')
  local outcome, reason = towOutcome()
  check(outcome == 'fallback' and reason == 'runner:silent', 'fell back: ' .. tostring(reason))
  check(ent(target) == nil, 'vehicle deleted')
  trace()
end

do -- 8. boat: no tow at all (old delete)
  local NZ = scenario('boat', { { src = 1, x = 0.0, y = -6.0 } })
  local boat = car('dinghy', 5.0, 0.0, 1)
  local started, reason = NZ.Tow.start(boat, 1)
  check(started == false and reason == 'type', 'boat refused: ' .. tostring(reason))
  check(ent(boat).state.nzTowing == nil, 'boat not marked')
  -- through the impound form hook: deleted at once
  W.rows[ent(boat).plate] = { plate = ent(boat).plate, owner = 'CID1', vehicleType = 'car', state = 'out' }
  local ok = NZ.Impound.impound(ent(boat).plate, { locationId = 1, netId = ent(boat).netId, tow = true }, 1)
  check(ok == true and ent(boat) == nil, 'impound deleted the boat at once')
  check(lastLog('impound.add') and lastLog('impound.add').data.towed == nil, 'logged without a tow')
  trace()
end

do -- 9. a commercial truck (class 20): the runner refuses, the vehicle is deleted at once
  local NZ = scenario('too big', { { src = 1, x = 0.0, y = -6.0 } })
  local mule = car('mule', 5.0, 0.0, 1)
  check(NZ.Tow.start(mule, 1), 'server accepts (it cannot see the class)')
  check(runUntil(finished, 6000), 'finished quickly')
  local outcome, reason = towOutcome()
  check(outcome == 'fallback' and reason == 'client:class', 'fell back: ' .. tostring(reason))
  check(ent(mule) == nil, 'vehicle deleted')
  noNpcs('too big')
  local told = false
  for _, n in ipairs(W.notified) do if n.message == 'Tow truck dispatched' then told = true end end
  check(not told, 'officer not told about a tow that never came')
  trace()
end

do -- 10. the vehicle is deleted by something else meanwhile: the empty truck leaves
  local NZ = scenario('target deleted', { { src = 1, x = 0.0, y = -6.0 } })
  local target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(function() return sawStage('spawned', 1) end, 6000), 'spawned')
  run(1500)
  deleteWorld(target)
  W.nearDeletes = {} -- deleted by the test itself
  check(runUntil(function() return sawStage('leaving', 1) end, 5000), 'runner reported it gone')
  check(runUntil(finished, 80000), 'finished')
  check(towOutcome() == 'done', 'outcome done (' .. tostring(select(2, towOutcome())) .. ')')
  noNpcs('target deleted')
  nothingVanished('target deleted')
  trace()
end

do -- 11. the vehicle is towed away by somebody else (moved far)
  local NZ = scenario('target moved', { { src = 1, x = 0.0, y = -6.0 } })
  local target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(function() return sawStage('spawned', 1) end, 6000), 'spawned')
  run(1000)
  ent(target).x = 5.0 + 6.0 -- pushed: new parking spot, carries on
  run(2000)
  check(not finished(), 'small push: still going')
  ent(target).x = 200.0
  check(runUntil(finished, 6000), 'finished')
  local outcome, reason = towOutcome()
  check(outcome == 'fallback' and reason == 'client:moved', 'fell back: ' .. tostring(reason))
  check(ent(target) == nil, 'vehicle deleted (nobody near it)')
  check(count('flatbed') == 1, 'the truck stays while the player is near')
  leaveScene()
  noNpcs('moved')
  nothingVanished('moved')
  trace()
end

do -- 12. somebody forces their way into the vehicle
  local NZ = scenario('entered', { { src = 1, x = 0.0, y = -6.0 }, { src = 2, x = 8.0, y = -6.0 } })
  local target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  run(2000)
  ent(W.players[2].ped).vehicle, ent(W.players[2].ped).seat = target, -1
  check(runUntil(finished, 3000), 'finished')
  local outcome, reason = towOutcome()
  check(outcome == 'fallback' and reason == 'occupied', 'fell back: ' .. tostring(reason))
  check(ent(target) == nil and ent(W.players[2].ped).vehicle == nil, 'vehicle deleted under the player (no fade)')
  run(FADE_WAIT)
  check(count('flatbed') == 1, 'the truck stays while players are near')
  leaveScene()
  noNpcs('entered')
  trace()
end

do -- 13. the truck is stuck in sight: re-paths, reverses, gives up; a new truck comes
  local NZ = scenario('stuck', { { src = 1, x = 0.0, y = -6.0 } })
  W.sight = 1000.0 -- everything is in sight: no unseen skip ahead possible
  local target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(function() return count('flatbed') == 1 end, 6000), 'spawned')
  local first = find('flatbed')
  W.blocked[first] = true
  check(runUntil(function() return trucks() == 2 end, 120000), 'gave up on the stuck truck, a new one comes')
  local nudged = false
  for _, t in ipairs(W.tempActions) do if t.action == 3 then nudged = true end end
  check(nudged, 'reversed out before giving up')
  local stuckReported = false
  for _, r in ipairs(W.reports) do if r.stage == 'failed' then stuckReported = true end end
  check(stuckReported and lastLog('impound.tow') == nil, 'reported stuck, the tow carries on')
  check(ent(target) ~= nil and ent(target).state.nzTowing == true, 'the vehicle never vanished')
  check(runUntil(finished, 150000), 'finished')
  local outcome, reason = towOutcome()
  check(outcome == 'done', 'done with the second truck (' .. tostring(reason) .. ')')
  check(lastLog('impound.tow').data.attempts == 2, 'two attempts logged')
  check(ent(first) ~= nil, 'the stuck truck stays while the player is near')
  leaveScene()
  noNpcs('stuck')
  nothingVanished('stuck')
  trace()
  -- every attempt stuck: the vehicle stays (locked) until nobody is near
  NZ = scenario('stuck twice', { { src = 1, x = 0.0, y = -6.0 } })
  W.sight = 1000.0
  W.server.Config.Tow.attempts = 1
  target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(function() return count('flatbed') == 1 end, 6000), 'spawned')
  W.blocked[find('flatbed')] = true
  check(runUntil(finished, 120000), 'finished')
  outcome, reason = towOutcome()
  check(outcome == 'fallback' and reason == 'client:stuck', 'fell back: ' .. tostring(reason))
  check(notifiedOf(1, FAILED_TEXT), 'officer told the tow truck could not collect the vehicle')
  check(ent(target) ~= nil and ent(target).locked == 2 and NZ.Tow.isTowing(target), 'the vehicle stays, locked')
  leaveScene()
  check(ent(target) == nil, 'removed once nobody is near')
  noNpcs('stuck twice')
  nothingVanished('stuck twice')
  trace()
end

do -- 14. stuck, but out of sight: skips ahead and completes
  local NZ = scenario('stuck unseen', { { src = 1, x = 0.0, y = -6.0 } })
  W.sight = 5.0
  local target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(function() return count('flatbed') == 1 end, 6000), 'spawned')
  local truck
  for id, en in pairs(W.entities) do if en.name == 'flatbed' then truck = id W.blocked[id] = true end end
  check(runUntil(function() return sawStage('arrived', 1) end, 60000), 'arrived after skipping ahead')
  check(trucks() == 1, 'the same truck (moved unseen, not replaced)')
  local reversed = false
  for _, t in ipairs(W.tempActions) do if t.action == 3 then reversed = true end end
  check(reversed, 'reversed out before skipping ahead')
  -- the careful style is the approach style (steers around what blocks it) + stop at red lights;
  -- the normal driving style already stops at lights, so the exact value is checked
  local carefulStyle = math.tointeger(W.players[1].env.Config.Tow.approachStyle) | 128
  check((math.tointeger(W.players[1].env.Config.Tow.approachStyle) & 128) == 0, 'approach style alone runs red lights')
  local careful = false
  for _, c in ipairs(W.longrange) do if c.speed <= 8.0 and c.style == carefulStyle then careful = true end end
  check(careful, 'after a recovery: slower and still stops at red lights')
  W.blocked[truck] = nil
  check(runUntil(finished, 90000), 'finished')
  check(towOutcome() == 'done', 'outcome done (' .. tostring(select(2, towOutcome())) .. ')')
  noNpcs('stuck unseen')
  nothingVanished('stuck unseen')
  trace()
end

--- Call the progress callback as `src` from a server thread and wait for the answer.
local function call(src, payload)
  local box = {}
  addThread(W.server, function() box.r = W.callbacks['nz:tow:progress'](src, payload) end)
  runUntil(function() return box.r ~= nil end, 20000)
  run(200) -- per-job report gap
  return box.r or {}
end

do -- 15. forged reports: no client ever names the truck, the driver or an arbitrary place
  local NZ = scenario('forged reports', { { src = 1, x = 0.0, y = -6.0 }, { src = 2, x = 20.0, y = -6.0 } })
  W.players[1].deaf = true -- the officer's client does nothing on its own here
  local target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  local r = call(2, { id = 1, stage = 'arrived' })
  check(r.ok == false and r.code == 'gone', 'a player who is not the runner is refused')
  r = call(1, { id = 1, stage = 'teleport' })
  check(r.ok == false, 'unknown stage refused')
  r = call(1, { id = 1, stage = 'arrived' })
  check(r.ok == false, 'out-of-order stage refused')
  -- the runner claims a stranger's car + ped are its truck and driver
  local fake = car('flatbed', 40.0, 0.0, 1)
  local ped = newEntity(1, 's_m_m_trucker_01', 40, 0, 30, 0, 1)
  r = call(1, { id = 1, stage = 'spawned', truck = ent(fake).netId, driver = ent(ped).netId })
  check(r.ok == false, 'claimed truck + driver refused (no truck exists yet)')
  r = call(1, { id = 1, stage = 'node', x = 'a', y = 0, z = 30, heading = 0 })
  check(r.ok == false, 'malformed node refused')
  check(ent(target) ~= nil and not finished() and #W.created == 0, 'refusals change nothing')
  r = call(1, { id = 1, stage = 'node', x = 5000.0, y = 0.0, z = 30.0, heading = 0.0 })
  check(r.ok == false, 'node far from the vehicle refused')
  check(lastLog('security.tow') and lastLog('security.tow').data.reason == 'node:distance', 'security log written')
  run(FADE_WAIT)
  check(towOutcome() == 'fallback' and ent(target) == nil, 'fell back (vehicle deleted)')
  check(#W.created == 0, 'nothing created at the forged place')
  check(ent(fake) ~= nil and ent(ped) ~= nil, 'the claimed entities were not touched')
  r = call(1, { id = 1, stage = 'tick' })
  check(r.ok == false and r.code == 'gone', 'finished job refuses reports')
  trace()
end

do -- 15b. the runner proposes a node; the server creates the NPCs; forged adoption refused
  local NZ = scenario('server creation', { { src = 1, x = 0.0, y = -6.0 }, { src = 2, x = 100.0, y = 0.0 } })
  W.players[1].deaf = true
  local target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  local r = call(1, { id = 1, stage = 'node', x = 101.0, y = 1.0, z = 30.0, heading = 0.0 })
  check(r.ok == false and r.code == 'retry' and towOutcome() == nil and #W.created == 0,
    'node on a player refused: the runner tries another one')
  for _ = 1, 3 do r = call(1, { id = 1, stage = 'node', x = 101.0, y = 1.0, z = 30.0, heading = 0.0 }) end
  check(r.ok == false and r.code ~= 'retry' and select(2, towOutcome()) == 'node:player' and #W.created == 0,
    'refused nodes are bounded (3 retries): falls back')
  check(lastLog('security.tow') == nil, 'not logged as forged (a player may walk there)')
  NZ = scenario('server creation', { { src = 1, x = 0.0, y = -6.0 } })
  W.players[1].deaf = true
  target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started again')
  r = call(1, { id = 1, stage = 'node', x = 105.0, y = 0.0, z = 30.0, heading = 90.0 })
  check(r.ok == true and type(r.data) == 'table' and r.data.truck and r.data.driver, 'node accepted: truck + driver net ids')
  local truck, driver = W.byNet[r.data.truck], W.byNet[r.data.driver]
  check(truck and ent(truck).serverCreated and ent(truck).name == 'flatbed' and ent(truck).owner == 1, 'truck created by the server, simulated by the runner')
  check(driver and ent(driver).vehicle == truck and ent(driver).seat == -1, 'driver seated by the server')
  check(ent(truck).orphan == 2 and ent(driver).orphan == 2, 'orphan mode 2')
  check(ent(truck).state.nzTowTruck == true and ent(driver).state.nzTowDriver == true, 'state bags set')
  local fake = car('flatbed', 40.0, 0.0, 1)
  r = call(1, { id = 1, stage = 'spawned', truck = ent(fake).netId, driver = r.data.driver })
  check(r.ok == false and lastLog('security.tow') and lastLog('security.tow').data.reason == 'spawn:entity', 'adopting another truck refused + logged')
  r = call(1, { id = 1, stage = 'node', x = 105.0, y = 0.0, z = 30.0, heading = 90.0 })
  check(r.ok == false and count('flatbed') == 2, 'a second node is refused (one truck per job)')
  -- another tow's runner proposes a node next to this tow's truck: refused, try another one
  local second = car('sultan', 5.0, 14.0, 1)
  check(NZ.Tow.start(second, 1), 'second tow started')
  r = call(1, { id = 2, stage = 'node', x = 110.0, y = 2.0, z = 30.0, heading = 90.0 })
  check(r.ok == false and r.code == 'retry' and count('flatbed') == 2, 'node next to another tow truck refused (retry)')
  r = call(1, { id = 2, stage = 'node', x = 105.0, y = 60.0, z = 30.0, heading = 90.0 })
  check(r.ok == true and count('flatbed') == 3, 'a free node is accepted')
  r = call(1, { id = 1, stage = 'spawned', truck = ent(truck).netId, driver = ent(driver).netId })
  check(r.ok == true, 'adoption confirmed')
  local told = false
  for _, n in ipairs(W.notified) do if n.target == 1 and n.message == 'Tow truck dispatched' then told = true end end
  check(told, 'officer told once the truck is on its way')
  r = call(1, { id = 1, stage = 'spawned', truck = ent(truck).netId, driver = ent(driver).netId })
  check(r.ok == true, 'repeated confirmation is harmless')
  stopResource()
  check(ent(target) == nil and ent(truck) == nil and ent(driver) == nil and ent(fake) ~= nil, 'resource stop: job entities gone at once, nothing else')
  check(ent(second) == nil and count('flatbed') == 1, 'resource stop: the second tow too')
  trace()
end

do -- 16. resource stop in the middle of a tow
  local NZ = scenario('resource stop', { { src = 1, x = 0.0, y = -6.0 } })
  local target = car('sultan', 5.0, 0.0, 1)
  local other = car('sultan', 5.0, -14.0, 1)
  check(NZ.Tow.start(target, 1) and NZ.Tow.start(other, 1), 'tows started')
  check(runUntil(function() return sawStage('arrived', 1) end, 40000), 'one arrived')
  stopResource()
  run(500)
  check(ent(target) == nil and ent(other) == nil, 'vehicles deleted')
  noNpcs('resource stop')
  check(not NZ.Tow.isTowing(target), 'nothing tracked')
  check(NZ.Tow.start(car('sultan', 50.0, 0.0, 1), 1) == false, 'no new tow while stopping')
  trace()
end

do -- 17. limits: someone inside, disabled, too many at once
  local NZ = scenario('limits', { { src = 1, x = 0.0, y = -6.0 } })
  local inside = car('sultan', 5.0, 0.0, 1)
  newEntity(1, 'mp_m_freemode_01', 0, 0, 0, 0, 1, { vehicle = inside, seat = -1 })
  local started, reason = NZ.Tow.start(inside, 1)
  check(started == false and reason == 'occupied', 'occupied refused')
  W.server.Config.Tow.maxActive = 1
  check(NZ.Tow.start(car('sultan', 5.0, 20.0, 1), 1) == true, 'first tow')
  started, reason = NZ.Tow.start(car('sultan', 5.0, 40.0, 1), 1)
  check(started == false and reason == 'busy', 'busy refused')
  W.server.Config.Tow.enabled = false
  started, reason = NZ.Tow.start(car('sultan', 5.0, 60.0, 1), 1)
  check(started == false and reason == 'disabled', 'disabled refused')
  W.server.Config.Tow.enabled = true
  W.server.Config.Tow.maxActive = 6
  -- nobody near the vehicle: no runner, deleted at once by the caller
  started, reason = NZ.Tow.start(car('sultan', 3000.0, 0.0, -1), 1)
  check(started == false and reason == 'runner', 'no runner refused')
  stopResource()
  trace()
end

do -- 18. the impound form hook (owned and NPC vehicles; admin / export impounds never tow)
  local NZ = scenario('impound hook', { { src = 1, x = 0.0, y = -6.0 } })
  local owned = car('sultan', 5.0, 0.0, 1)
  local plate = ent(owned).plate
  W.rows[plate] = { plate = plate, owner = 'CID1', vehicleType = 'car', state = 'out' }
  local submit = W.callbacks['nz:impoundForm:submit']
  local r = submit(1, { impoundId = 1, netId = ent(owned).netId, reason = 'Parking', fee = 100, hours = 0, retrievable = true })
  check(r.ok == true, 'form submit ok: ' .. tostring(r.error))
  check(W.updated and W.updated.plate == plate and W.updated.fields.state == 'impounded', 'database impound at once')
  check(ent(owned) ~= nil and ent(owned).state.nzTowing == true, 'vehicle kept for the tow')
  check(lastLog('impound.add').data.towed == true, 'logged as towed')
  local npc = car('sultan', 5.0, -14.0, 1)
  run(2500) -- form rate limit
  r = submit(1, { impoundId = 1, netId = ent(npc).netId })
  check(r.ok == true and ent(npc) ~= nil and ent(npc).state.nzTowing == true, 'NPC vehicle towed too')
  local adminCar = car('sultan', 5.0, 14.0, 1)
  local p2 = ent(adminCar).plate
  W.rows[p2] = { plate = p2, owner = 'CID2', vehicleType = 'car', state = 'out' }
  check(NZ.Impound.impound(p2, { locationId = 1, netId = ent(adminCar).netId }, 1) == true and ent(adminCar) == nil,
    'admin / export impound deletes at once')
  check(runUntil(function()
    local n = 0
    for _, l in ipairs(W.logs) do if l.event == 'impound.tow' then n = n + 1 end end
    return n == 2
  end, 150000), 'both tows finished')
  run(FADE_WAIT)
  check(ent(owned) == nil and ent(npc) == nil, 'towed vehicles deleted')
  noNpcs('hook')
  nothingVanished('hook')
  trace()
end

do -- 18b. a fake-plated vehicle (NZ.FakePlates): officers see the plate it shows, the real
  -- registration is found and impounded (docs/CARLOCK.md section 13)
  local NZ = scenario('impound fake plate', { { src = 1, x = 0.0, y = -6.0 } })
  local faked = car('sultan', 5.0, 0.0, 1)
  local shown = ent(faked).plate
  W.rows.REAL0001 = { plate = 'REAL0001', owner = 'CID1', vehicleType = 'car', state = 'out' }
  NZ.FakePlates.realPlateOf = function(e) if e == faked then return 'REAL0001' end return nil end
  local form = W.callbacks['nz:impound:formData'](1, { netId = ent(faked).netId })
  check(form.ok == true and form.data.plate == shown and form.data.owned == true,
    'fake plate: the form shows the plate the vehicle shows, the row is found by its registration')
  local submit = W.callbacks['nz:impoundForm:submit']
  local r = submit(1, { impoundId = 1, netId = ent(faked).netId, plate = 'NOPE01' })
  check(r.ok == false, 'fake plate: a plate the vehicle neither shows nor is registered under is refused')
  run(2500) -- form rate limit
  r = submit(1, { impoundId = 1, netId = ent(faked).netId, plate = shown })
  check(r.ok == true and W.updated and W.updated.plate == 'REAL0001' and W.updated.fields.state == 'impounded',
    'fake plate: the shown plate is accepted and the registration is impounded')
  stopResource()
  trace()
end

do -- 19. entity lockdown (relaxed / strict): clients cannot create entities, the server does
  local NZ = scenario('lockdown', { { src = 1, x = 0.0, y = -6.0 } })
  W.lockdown = true
  local target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(finished, 90000), 'finished')
  local outcome, reason = towOutcome()
  check(outcome == 'done', 'tow done: ' .. tostring(reason))
  check((W.clientCreated or 0) == 0, 'no client created an entity')
  check(ent(target) == nil, 'vehicle deleted')
  noNpcs('lockdown')
  nothingVanished('lockdown')
  trace()
end

do -- 19b. a server build without CreateVehicleServerSetter: falls back at once, warns once
  local NZ = scenario('no server setter', { { src = 1, x = 0.0, y = -6.0 } })
  W.noServerSetter = true
  local target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(finished, 8000), 'finished')
  local outcome, reason = towOutcome()
  check(outcome == 'fallback' and reason == 'spawn:truck', 'fell back: ' .. tostring(reason))
  local warnedSetter = 0
  for _, w in ipairs(W.warnings) do if w:find('CreateVehicleServerSetter') then warnedSetter = warnedSetter + 1 end end
  check(warnedSetter == 1, 'warned once')
  check(ent(target) == nil, 'vehicle deleted')
  noNpcs('no server setter')
  trace()
end

do -- 20. an officer impounds the tow truck itself on its way
  local NZ = scenario('truck impounded', { { src = 1, x = 0.0, y = -6.0 } })
  local target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(function() return sawStage('spawned', 1) end, 6000), 'spawned')
  local truck
  for id, en in pairs(W.entities) do if en.name == 'flatbed' then truck = id end end
  check(NZ.Tow.start(truck, 1) == true, 'handled (the caller does not delete it again)')
  run(FADE_WAIT)
  local outcome, reason = towOutcome()
  check(outcome == 'fallback' and reason == 'truckImpounded', 'that tow ended: ' .. tostring(reason))
  check(count('flatbed') == 0 and count('s_m_m_trucker_01') == 0, 'the impounded truck and its driver are gone')
  check(ent(target) ~= nil and NZ.Tow.isTowing(target), 'its vehicle stays (locked) while the officer is near')
  check(NZ.Tow.start(target, 1) == true and ent(target) ~= nil, 'impounding it again changes nothing')
  leaveScene()
  check(ent(target) == nil, 'its vehicle removed once nobody is near')
  noNpcs('truck impounded')
  trace()
end

do -- 22. the StartTow export (another resource's impound): runs, or refuses without touching anything
  scenario('export', { { src = 1, x = 0.0, y = -6.0 } })
  local export = W.exports.StartTow
  check(type(export) == 'function', 'StartTow exported')
  local target = car('sultan', 5.0, 0.0, 1)
  local started = export(ent(target).netId, nil)
  check(started == true and ent(target).state.nzTowing == true, 'tow started from a net id (no officer)')
  local boat = car('dinghy', 5.0, 20.0, 1)
  local ok2, reason = export(ent(boat).netId)
  check(ok2 == false and reason == 'type' and ent(boat) ~= nil, 'boat refused, left alone')
  ok2, reason = export('nope')
  check(ok2 == false and reason == 'entity', 'bad net id refused')
  check(runUntil(finished, 90000) and towOutcome() == 'done', 'export tow done')
  noNpcs('export')
  nothingVanished('export')
  trace()
end

do -- 21. the runner drops while the vehicle is half way onto the bed
  local NZ = scenario('runner drops mid-load', { { src = 1, x = 0.0, y = -6.0 }, { src = 2, x = 25.0, y = -10.0 } })
  local target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(function() return sawStage('load', 1) end, 40000), 'loading')
  run(2500)
  check(ent(target).attached ~= nil, 'vehicle on its way up')
  drop(1)
  check(runUntil(function() return sawStage('spawned', 2) end, 8000), 'player 2 adopted')
  check(runUntil(function() return sawStage('load', 2) end, 20000), 'loading again without driving around')
  local drove = false
  for _, r in ipairs(W.reports) do if r.src == 2 and r.stage == 'tick' then drove = true end end
  check(not drove, 'no approach drive (truck already parked)')
  check(runUntil(finished, 90000), 'finished')
  check(towOutcome() == 'done', 'outcome done (' .. tostring(select(2, towOutcome())) .. ')')
  check(ent(target) == nil, 'vehicle deleted')
  noNpcs('mid-load')
  nothingVanished('mid-load')
  trace()
end

local function headingGap(a, b) return math.abs((a - b + 180.0) % 360.0 - 180.0) end

--- The pull of `target`: starts behind the bed, never ahead of its place on the bed, with the
--- truck in line with the vehicle.
local function checkPull(target, label)
  local poses = W.attachLog[target] or {}
  local first, rear = poses[1], W.server.Config.Tow.bed.rear
  check(first ~= nil, label .. ': pulled onto the bed')
  if not first then return end
  check(first.y < rear, ('%s: starts behind the bed (y=%.2f < %.2f)'):format(label, first.y, rear))
  local rel = headingGap(first.truckH, first.targetH)
  check(rel <= 35.0 or rel >= 145.0, ('%s: truck in line with the vehicle (%.0f deg)'):format(label, rel))
  -- ahead of its place on the bed only straight up from where it stood, or above the cab roof
  local final, roof = poses[#poses], MODELS.flatbed.max.z + 0.5 - MODELS.sultan.min.z
  local through = nil
  for _, p in ipairs(poses) do
    local inPlace = math.abs(p.x - first.x) < 0.01 and math.abs(p.y - first.y) < 0.01
    if p.y > final.y + 0.01 and p.z < roof - 0.01 and not inPlace then through = through or p end
  end
  check(through == nil, ('%s: never pulled through the truck%s'):format(label,
    through and (' (x=%.2f y=%.2f z=%.2f)'):format(through.x, through.y, through.z) or ''))
end

do -- 23. the truck parks rear first whatever the vehicle's heading (turned unseen when needed)
  for _, h in ipairs({ 0.0, 90.0, 180.0, 270.0 }) do
    local NZ = scenario('heading ' .. h, { { src = 1, x = 0.0, y = -6.0 } })
    local target = car('sultan', 5.0, 0.0, 1, { h = h })
    check(NZ.Tow.start(target, 1), 'tow started')
    check(runUntil(function() return sawStage('loaded') end, 90000), 'loaded')
    checkPull(target, 'heading ' .. h)
    check(runUntil(finished, 90000) and towOutcome() == 'done', 'done (' .. tostring(select(2, towOutcome())) .. ')')
    noNpcs('heading ' .. h)
    nothingVanished('heading ' .. h)
    trace()
  end
end

do -- 24. same, everything on screen: a wrong-way stop drives past the vehicle to its other side
  for _, h in ipairs({ 90.0, 180.0 }) do
    local NZ = scenario('heading on screen ' .. h, { { src = 1, x = 0.0, y = -6.0 } })
    W.screenRealistic, W.sight = true, 1000.0
    local target = car('sultan', 5.0, 0.0, 1, { h = h })
    check(NZ.Tow.start(target, 1), 'tow started')
    check(runUntil(function() return sawStage('loaded') end, 120000), 'loaded')
    checkPull(target, 'on screen ' .. h)
    check(runUntil(finished, 90000) and towOutcome() == 'done', 'done (' .. tostring(select(2, towOutcome())) .. ')')
    noNpcs('on screen ' .. h)
    nothingVanished('on screen ' .. h)
    trace()
  end
end

do -- 25. the new NPCs are simulated by another nearby player: the runner takes control of them
  local NZ = scenario('owner elsewhere', { { src = 1, x = 0.0, y = -6.0 }, { src = 2, x = 60.0, y = -10.0 } })
  W.ownerOverride = 2
  local target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(function() return sawStage('spawned', 1) end, 8000), 'the officer adopted the new NPCs')
  local truck, driver = find('flatbed'), find('s_m_m_trucker_01')
  check(ent(truck).owner == 1 and ent(driver).owner == 1, 'the officer simulates truck and driver')
  check(ent(truck).noMigrate == true and ent(driver).noMigrate == true, 'and keeps them (no migration)')
  check(runUntil(finished, 120000) and towOutcome() == 'done', 'done (' .. tostring(select(2, towOutcome())) .. ')')
  check(not sawStage('spawned', 2), 'player 2 never ran it')
  local told = false
  for _, n in ipairs(W.notified) do if n.target == 1 and n.message == 'Tow truck dispatched' then told = true end end
  check(told, 'the officer is told')
  check(ent(target) == nil, 'vehicle deleted')
  noNpcs('owner elsewhere')
  nothingVanished('owner elsewhere')
  trace()
end

do -- 26. the NPCs are simulated by a player far from the vehicle who keeps them: fall back
  local NZ = scenario('owner far away', { { src = 1, x = 0.0, y = -6.0 }, { src = 3, x = 2000.0, y = 0.0 } })
  W.ownerOverride = 3
  W.noControl = true
  local target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(finished, 15000), 'finished')
  local outcome, reason = towOutcome()
  check(outcome == 'fallback' and reason == 'runner:owner', 'fell back: ' .. tostring(reason))
  check(ent(target) == nil, 'vehicle deleted (no truck ever came: as without a tow)')
  noNpcs('owner far away')
  trace()
end

do -- 27. nobody ever simulates the NPCs (culling range): fall back after the owner wait
  local NZ = scenario('no owner', { { src = 1, x = 0.0, y = -6.0 } })
  W.cull = 0.0
  local target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(finished, 12000), 'finished')
  local outcome, reason = towOutcome()
  check(outcome == 'fallback' and reason == 'spawn:owner', 'fell back: ' .. tostring(reason))
  check(ent(target) == nil, 'vehicle deleted')
  noNpcs('no owner')
  trace()
end

do -- 28. the runner drops while the server creates the NPCs: the remaining player takes them
  local NZ = scenario('runner drops during creation', { { src = 1, x = 0.0, y = -6.0 }, { src = 2, x = 30.0, y = -10.0 } })
  W.ownerDelay, W.ownerOverride = 2000, nil
  local target = car('sultan', 5.0, 0.0, 1, { persistent = true })
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(function() return #W.created == 2 end, 8000), 'NPCs being created')
  drop(1)
  check(runUntil(function() return sawStage('spawned', 2) end, 10000), 'player 2 adopted them')
  check(runUntil(finished, 120000) and towOutcome() == 'done', 'done (' .. tostring(select(2, towOutcome())) .. ')')
  check(ent(target) == nil, 'vehicle deleted')
  noNpcs('drop during creation')
  nothingVanished('drop during creation')
  trace()
end

do -- 29. the owner retrieves the vehicle meanwhile (Vehicles.retrieve -> NZ.Tow.release)
  local NZ = scenario('release', { { src = 1, x = 0.0, y = -6.0 } })
  local target = car('sultan', 5.0, 0.0, 1)
  local other = car('sultan', 30.0, 30.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(function() return sawStage('spawned', 1) end, 8000), 'spawned')
  run(2000)
  check(NZ.Tow.release(other) == false, 'a vehicle that is not towed is not released')
  check(NZ.Tow.release(target) == true and ent(target) == nil, 'released: deleted at once')
  W.nearDeletes = {} -- the owner took it out of the impound (a new copy spawns elsewhere)
  check(not NZ.Tow.isTowing(target), 'no longer towing')
  check(runUntil(function() return sawStage('leaving', 1) end, 8000), 'the empty truck leaves')
  check(runUntil(finished, 90000) and towOutcome() == 'done', 'done (' .. tostring(select(2, towOutcome())) .. ')')
  check(ent(other) ~= nil, 'other vehicle untouched')
  noNpcs('release')
  nothingVanished('release')
  -- before any truck exists: the job just ends
  NZ = scenario('release early', { { src = 1, x = 0.0, y = -6.0 } })
  W.players[1].deaf = true
  target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  check(NZ.Tow.release(target) == true and ent(target) == nil, 'released before the truck')
  run(FADE_WAIT)
  check(select(2, towOutcome()) == 'released', 'ended: ' .. tostring(select(2, towOutcome())))
  trace()
end

do -- 30. the towed vehicle is deleted and its handle reused by another car of the same model
  local NZ = scenario('recycled handle', { { src = 1, x = 0.0, y = -6.0 } })
  local target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(function() return sawStage('spawned', 1) end, 8000), 'spawned')
  local old = ent(target)
  deleteWorld(target)
  W.nearDeletes = {} -- deleted by the test itself
  -- a new sultan on the same handle (no nzTowing bag): never the job's vehicle
  W.entities[target] = { id = target, type = 2, model = old.model, name = 'sultan', x = 300.0, y = 300.0, z = 30.0, h = 0.0,
    owner = 1, bucket = 0, netId = 9999, state = {}, orphan = 0, plate = 'NEWCAR' }
  W.byNet[9999] = target
  check(not NZ.Tow.isTowing(target), 'the new car is not taken for the towed one')
  check(runUntil(finished, 90000), 'finished')
  check(towOutcome() == 'done', 'the empty truck left (' .. tostring(select(2, towOutcome())) .. ')')
  check(ent(target) ~= nil and ent(target).plate == 'NEWCAR', 'the new car survives')
  noNpcs('recycled handle')
  nothingVanished('recycled handle')
  trace()
end

do -- 31. what is retired near players fades out after cleanupSeconds; resource stop is immediate
  local NZ = scenario('fade', { { src = 1, x = 0.0, y = -6.0 } })
  W.sight = 1000.0
  W.server.Config.Tow.attempts = 1
  W.server.Config.Tow.cleanupSeconds = 30
  local target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(function() return sawStage('spawned', 1) end, 8000), 'spawned')
  for id, en in pairs(W.entities) do if en.name == 'flatbed' then W.blocked[id] = true end end
  check(runUntil(function() return lastLog('impound.tow') ~= nil end, 120000), 'fell back (stuck)')
  local endedAt = now
  check(count('flatbed') == 1 and ent(target) ~= nil, 'everything stays while the player is near')
  check(runUntil(function()
    for _, ev in ipairs(W.sent) do if ev.name == 'nz:client:tow:fade' and ev.target == 1 then return true end end
    return false
  end, 40000), 'fade sent to the client that simulates them')
  check(now - endedAt >= 29000, ('after cleanupSeconds (%.0f s)'):format((now - endedAt) / 1000))
  run(200)
  local faded = 0
  for _ in pairs(W.faded) do faded = faded + 1 end
  check(faded == 3, 'vehicle, truck and driver faded out (' .. faded .. ')')
  run(FADE_WAIT)
  check(ent(target) == nil, 'vehicle deleted after the fade')
  noNpcs('fade')
  -- resource stop while things are retired: gone at once
  NZ = scenario('retired + stop', { { src = 1, x = 0.0, y = -6.0 } })
  W.sight = 1000.0
  W.server.Config.Tow.attempts = 1
  target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(function() return sawStage('spawned', 1) end, 8000), 'spawned')
  for id, en in pairs(W.entities) do if en.name == 'flatbed' then W.blocked[id] = true end end
  check(runUntil(function() return lastLog('impound.tow') ~= nil end, 120000), 'fell back')
  check(NZ.Tow.isTowing(target), 'a retired vehicle counts as towing')
  stopResource()
  check(ent(target) == nil, 'vehicle deleted at once')
  noNpcs('retired + stop')
  trace()
end

do -- 32. loadSeconds is clamped to 20: a long pull never looks like a silent runner
  local NZ = scenario('long load', { { src = 1, x = 0.0, y = -6.0 } })
  W.server.Config.Tow.loadSeconds = 28
  W.players[1].env.Config.Tow.loadSeconds = 28
  local target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(function() return sawStage('load', 1) end, 60000), 'loading')
  local loadAt = now
  check(runUntil(function() return sawStage('loaded', 1) end, 40000), 'loaded')
  local took = (now - loadAt) / 1000
  check(took <= 22.0, ('loading took %.1f s (<= 20 + margin)'):format(took))
  check(runUntil(finished, 90000) and towOutcome() == 'done', 'done (' .. tostring(select(2, towOutcome())) .. ')')
  check(lastLog('impound.tow').data.handovers == 0, 'never handed over')
  trace()
end

do -- 33. the server's seat request does not land: the runner seats the driver itself
  local NZ = scenario('seat lost', { { src = 1, x = 0.0, y = -6.0 } })
  W.seatRpcLost = true
  local target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(function() return sawStage('arrived', 1) end, 60000), 'arrived')
  check(runUntil(finished, 90000) and towOutcome() == 'done', 'done (' .. tostring(select(2, towOutcome())) .. ')')
  noNpcs('seat lost')
  nothingVanished('seat lost')
  trace()
end


--- Security log entries with this reason.
local function securityCount(reason)
  local n = 0
  for _, l in ipairs(W.logs) do if l.event == 'security.tow' and l.data.reason == reason then n = n + 1 end end
  return n
end

do -- 34. the vehicle's owner clears its nzTowing bag (cheat menu, no sv_stateBagStrictMode)
  local NZ = scenario('target bag cleared', { { src = 1, x = 0.0, y = -6.0 }, { src = 2, x = 7.0, y = 2.0 } })
  W.ownerOverride = 1
  local target = car('sultan', 5.0, 0.0, 2)
  check(NZ.Tow.start(target, 1), 'tow started')
  run(1000)
  ownerSetsBag(target, 'nzTowing', false)
  run(300)
  check(ent(target).state.nzTowing == true, 'the server put the bag back')
  check(NZ.Tow.isTowing(target), 'still towing: the bag proves nothing')
  local l = lastLog('security.tow')
  check(l and l.data.reason == 'bag:nzTowing' and l.src == 2, 'logged against the vehicle owner')
  ownerSetsBag(target, 'nzTowing', nil)
  run(300)
  check(ent(target).state.nzTowing == true and securityCount('bag:nzTowing') == 1, 'put back again, logged once')
  check(runUntil(finished, 150000), 'finished')
  check(towOutcome() == 'done', 'outcome done (' .. tostring(select(2, towOutcome())) .. ')')
  check(ent(target) == nil, 'vehicle deleted at the end')
  noNpcs('target bag cleared')
  nothingVanished('target bag cleared')
  -- worst case: the bag stays cleared (no handler ever saw it): the server deletes it all the same
  NZ = scenario('target bag cleared silently', { { src = 1, x = 0.0, y = -6.0 }, { src = 2, x = 7.0, y = 2.0 } })
  W.ownerOverride = 1
  target = car('sultan', 5.0, 0.0, 2)
  check(NZ.Tow.start(target, 1), 'tow started')
  run(1000)
  ent(target).state.nzTowing = false
  check(NZ.Tow.isTowing(target), 'still towing')
  check(runUntil(function() return lastLog('impound.tow') ~= nil end, 150000), 'ended')
  run(FADE_WAIT)
  check(ent(target) == nil, 'vehicle deleted at the end (' .. tostring(select(2, towOutcome())) .. ')')
  check(not NZ.Tow.isTowing(target), 'nothing tracked')
  noNpcs('target bag cleared silently')
  trace()
end

do -- 35. the bags of the truck and driver are cleared: never left behind
  local NZ = scenario('truck bag cleared', { { src = 1, x = 0.0, y = -6.0 } })
  local target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(function() return sawStage('spawned', 1) end, 8000), 'spawned')
  local truck, driver = find('flatbed'), find('s_m_m_trucker_01')
  ent(truck).state.nzTowTruck = false -- unseen by any handler
  ownerSetsBag(driver, 'nzTowDriver', false)
  run(300)
  check(ent(driver).state.nzTowDriver == true and securityCount('bag:nzTowDriver') == 1, 'driver bag put back + logged')
  check(NZ.Tow.isTowing(truck) and NZ.Tow.isTowing(driver), 'still the tow truck and driver')
  check(runUntil(finished, 150000), 'finished')
  check(towOutcome() == 'done', 'outcome done (' .. tostring(select(2, towOutcome())) .. ')')
  check(ent(target) == nil, 'vehicle deleted')
  noNpcs('truck bag cleared')
  nothingVanished('truck bag cleared')
  trace()
end

do -- 36. the bags of retired entities are cleared: put back, still removed later
  local NZ = scenario('bag cleared while retired', { { src = 1, x = 0.0, y = -6.0 } })
  W.sight = 1000.0
  W.server.Config.Tow.attempts = 1
  local target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(function() return sawStage('spawned', 1) end, 8000), 'spawned')
  local truck = find('flatbed')
  W.blocked[truck] = true
  check(runUntil(function() return lastLog('impound.tow') ~= nil end, 120000), 'fell back (stuck)')
  check(ent(target) ~= nil and ent(truck) ~= nil, 'retired')
  ent(target).state.nzTowing = nil
  ownerSetsBag(truck, 'nzTowTruck', false)
  run(300)
  check(ent(truck).state.nzTowTruck == true and securityCount('bag:nzTowTruck') == 1,
    ('retired truck bag put back, logged (%d)'):format(securityCount('bag:nzTowTruck')))
  check(NZ.Tow.isTowing(target), 'the vehicle is still known (server data, not the bag)')
  leaveScene()
  check(ent(target) == nil, 'vehicle deleted once nobody is near')
  noNpcs('bag cleared while retired')
  trace()
end

do -- 37. the vehicle comes off the leaving truck: the truck waits, it is pulled back on
  local NZ = scenario('off the bed while leaving', { { src = 1, x = 0.0, y = -6.0 } })
  local target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(function() return sawStage('leaving', 1) end, 120000), 'leaving')
  run(600)
  local truck = find('flatbed')
  local x, y, z = worldPos(target)
  ent(target).attached = nil
  ent(target).x, ent(target).y, ent(target).z = x, y, z
  W.loadedBy[truck] = nil -- this test checks the distance itself
  local maxGap = 0
  check(runUntil(function()
    local tx, ty = worldPos(truck)
    maxGap = math.max(maxGap, math.sqrt((tx - x) ^ 2 + (ty - y) ^ 2))
    return ent(target).attached ~= nil and ent(target).attached.parent == truck
  end, 15000), 'pulled back onto the bed')
  check(maxGap < 25.0, ('the truck waited nearby (%.1f m)'):format(maxGap))
  local asked = false
  for _, ev in ipairs(W.sent) do if ev.name == 'nz:client:tow:attach' then asked = true end end
  check(asked, 'the server asked the vehicle owner to pull it back on')
  W.loadedBy[truck] = target
  check(runUntil(finished, 90000) and towOutcome() == 'done', 'done (' .. tostring(select(2, towOutcome())) .. ')')
  check(ent(target) == nil, 'vehicle deleted with the truck')
  noNpcs('off the bed')
  nothingVanished('off the bed')
  trace()
  -- it cannot be put back (dragged 50 m away): retired, removed once nobody is near
  NZ = scenario('off the bed, far', { { src = 1, x = 0.0, y = -6.0 } })
  target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(function() return sawStage('leaving', 1) end, 120000), 'leaving')
  truck = find('flatbed')
  W.loadedBy[truck] = nil
  ent(target).attached = nil
  ent(target).x, ent(target).y, ent(target).z = 5.0, -50.0, 30.0
  check(runUntil(function() return lastLog('impound.tow') ~= nil end, 30000), 'ended')
  local outcome, reason = towOutcome()
  check(outcome == 'fallback' and reason == 'detached', 'fell back: ' .. tostring(reason))
  check(ent(target) ~= nil, 'the vehicle stays while the player is near')
  check(dismissedTo(1) ~= nil, 'the empty truck is dismissed')
  check(runUntil(function() return ent(truck) == nil or (ent(truck).drive and ent(truck).drive.wander) end, 5000),
    'the empty truck drives off instead of standing there')
  check(notifiedOf(1, FAILED_TEXT), 'officer told the tow truck could not collect the vehicle')
  leaveScene()
  check(ent(target) == nil, 'removed once nobody is near')
  noNpcs('off the bed, far')
  nothingVanished('off the bed, far')
  trace()
end

do -- 38. a player takes the tow truck while the driver works the controls
  local NZ = scenario('truck occupied', { { src = 1, x = 0.0, y = -6.0 }, { src = 2, x = 8.0, y = -12.0 } })
  local target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(function() return sawStage('load', 1) end, 60000), 'loading')
  local truck = find('flatbed')
  W.players[2].env.dead = true -- a modified client: no guard pulls the player back out
  local ped = ent(W.players[2].ped)
  ped.vehicle, ped.seat = truck, -1
  check(runUntil(function() return lastLog('impound.tow') ~= nil end, 2500), 'ended at once')
  local outcome, reason = towOutcome()
  check(outcome == 'fallback' and reason == 'truckOccupied', 'fell back: ' .. tostring(reason))
  check(ent(truck) == nil and ped.vehicle == nil, 'truck deleted under the player (no fade)')
  run(FADE_WAIT)
  check(ent(target) ~= nil and NZ.Tow.isTowing(target), 'the vehicle stays while players are near')
  leaveScene()
  check(ent(target) == nil, 'vehicle removed once nobody is near')
  noNpcs('truck occupied')
  -- a passenger while it drives away
  NZ = scenario('truck occupied leaving', { { src = 1, x = 0.0, y = -6.0 }, { src = 2, x = 8.0, y = -12.0 } })
  target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(function() return sawStage('leaving', 1) end, 120000), 'leaving')
  truck = find('flatbed')
  W.players[2].env.dead = true
  ped = ent(W.players[2].ped)
  ped.vehicle, ped.seat = truck, 0
  check(runUntil(function() return lastLog('impound.tow') ~= nil end, 2500), 'ended at once')
  check(select(2, towOutcome()) == 'truckOccupied' and ent(truck) == nil, 'truck deleted under the passenger')
  run(FADE_WAIT)
  check(ent(target) ~= nil, 'the vehicle (dropped off the deleted truck) stays while players are near')
  leaveScene()
  check(ent(target) == nil, 'vehicle removed once nobody is near')
  noNpcs('truck occupied leaving')
  trace()
end

--- Deepest overlap of the vehicle (sultan) with the truck footprint at ground level (before it
--- climbs the ramp), over the attach poses (relative to the truck), or nil.
local function groundOverlap(poses)
  local tMin, tMax, cMin, cMax = MODELS.flatbed.min, MODELS.flatbed.max, MODELS.sultan.min, MODELS.sultan.max
  local halfW, halfL = (cMax.x - cMin.x) / 2, (cMax.y - cMin.y) / 2
  local worst
  for _, p in ipairs(poses) do
    local depthX = (tMax.x + halfW) - math.abs(p.x)
    local depthY = math.min((p.y + halfL) - tMin.y, tMax.y - (p.y - halfL))
    if depthX > 0 and depthY > 0 and p.z <= 0.05 then
      local depth = math.min(depthX, depthY)
      if not worst or depth > worst.depth then worst = { depth = depth, p = p } end
    end
  end
  return worst
end

do -- 39. the truck stops beside the vehicle, facing the right way: it carries on to the spot
  -- vehicle heading 0: loads nose first; 180: the truck parks at its rear (loads tail first)
  for _, heading in ipairs({ 0.0, 180.0 }) do
    local label = 'stops beside, vehicle heading ' .. heading
    local NZ = scenario(label, { { src = 1, x = 0.0, y = -30.0 } })
    local target = car('sultan', 5.0, 0.0, 1, { h = heading })
    check(NZ.Tow.start(target, 1), 'tow started')
    local truck
    -- the final approach (NEAR_SPEED) to one of the two spots in line with the vehicle
    check(runUntil(function()
      truck = find('flatbed')
      local d = truck and ent(truck).drive
      return d ~= nil and not d.wander and d.speed == 5.0
    end, 90000), 'final approach')
    local spotY = ent(truck).drive.y
    local h = spotY > 0 and 0.0 or 180.0 -- the spot's heading: the truck faces away from the vehicle
    say(('%s: spot at y=%.1f, truck heading %d'):format(label, spotY, h))
    -- stopped next to the vehicle's side, its rear corner level with the vehicle (in traffic)
    local ox, oy = rotate(3.5, -6.8, h)
    local en = ent(truck)
    en.x, en.y, en.h, en.drive = 5.0 - ox, 0.0 - oy, h, nil
    W.blocked[truck] = true
    run(6000)
    check(lastLog('impound.tow') == nil and not sawStage('arrived', 1), 'not taken as parked')
    W.blocked[truck] = nil
    check(runUntil(function() return sawStage('loaded') end, 60000), 'loaded')
    local poses = W.attachLog[target] or {}
    check(poses[1] and math.abs(poses[1].x) < 1.0, ('pulled from behind the bed (x=%.2f)'):format(poses[1] and poses[1].x or 0))
    local worst = groundOverlap(poses)
    check(worst == nil, 'never through the truck at ground level' ..
      (worst and (' (%.2f m at %.2f, %.2f)'):format(worst.depth, worst.p.x, worst.p.y) or ''))
    checkPull(target, label)
    check(runUntil(finished, 90000) and towOutcome() == 'done', 'done (' .. tostring(select(2, towOutcome())) .. ')')
    noNpcs(label)
    trace()
  end
end

do -- 40. the pull itself from beside the bed (a handed-over job, a parked truck): backs out first
  for _, case in ipairs({ { x = 3.5, y = -6.8, label = 'beside the rear corner' }, { x = -3.4, y = -5.5, label = 'beside, left' },
    { x = 0.0, y = -9.8, label = 'in line' } }) do
    scenario('pull ' .. case.label, { { src = 1, x = 0.0, y = -20.0 } })
    local truck = newEntity(2, 'flatbed', 0.0, 0.0, 30.0, 0.0, 1, { serverCreated = 0 })
    local target = car('sultan', case.x, case.y, 1)
    ent(target).state.nzTowing = true
    for _, fn in ipairs(W.players[1].env.handlers['nz:client:tow:attach'] or {}) do
      addThread(W.players[1].env, fn, { id = 77, netId = ent(target).netId, truck = ent(truck).netId, seconds = 6 })
    end
    run(8000)
    local poses = W.attachLog[target] or {}
    check(#poses > 10, case.label .. ': pulled on')
    local final = poses[#poses]
    check(final and math.abs(final.x) < 0.01 and math.abs(final.y + 2.35) < 0.01, case.label .. ': ends on the bed')
    local worst = groundOverlap(poses)
    check(worst == nil, case.label .. ': never through the truck at ground level' ..
      (worst and (' (%.2f m at %.2f, %.2f)'):format(worst.depth, worst.p.x, worst.p.y) or ''))
  end
end

do -- 41. two officers impound two cars at the same scene at once: never two trucks on one node
  local NZ = scenario('two officers', { { src = 1, x = 0.0, y = -6.0 }, { src = 2, x = 4.0, y = -8.0 } })
  W.ownerOverride = nil
  local a = car('sultan', 5.0, 0.0, 1)
  local b = car('sultan', 5.0, -14.0, 2, { h = 180.0 })
  check(NZ.Tow.start(a, 1) and NZ.Tow.start(b, 2), 'both tows started')
  check(runUntil(function() return count('flatbed') == 2 end, 15000), 'two trucks')
  local p = {}
  for _, c in ipairs(W.created) do if c.kind == 'vehicle' then p[#p + 1] = c end end
  local gap = #p == 2 and math.sqrt((p[1].x - p[2].x) ^ 2 + (p[1].y - p[2].y) ^ 2) or 0
  check(gap >= 12.0, ('trucks created %.1f m apart'):format(gap))
  local retried = false
  for _, r in ipairs(W.reports) do if r.stage == 'node' and r.code == 'retry' then retried = true end end
  say('two officers: a node was refused and another one proposed: ' .. tostring(retried))
  check(runUntil(function()
    local n = 0
    for _, l in ipairs(W.logs) do if l.event == 'impound.tow' then n = n + 1 end end
    return n == 2
  end, 180000), 'both finished')
  run(FADE_WAIT)
  for _, l in ipairs(W.logs) do
    if l.event == 'impound.tow' then check(l.data.outcome == 'done', 'tow ' .. tostring(l.data.plate) .. ' done (' .. tostring(l.data.reason) .. ')') end
  end
  check(ent(a) == nil and ent(b) == nil, 'both vehicles deleted')
  noNpcs('two officers')
  nothingVanished('two officers')
  trace()
end

do -- 42. waiting at a red light is no lack of progress
  local NZ = scenario('red light', { { src = 1, x = 0.0, y = -6.0 } })
  local target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(function() return sawStage('spawned', 1) end, 8000), 'spawned')
  run(1000)
  local truck = find('flatbed')
  W.blocked[truck], W.redLight = true, truck
  run(25000)
  check(#W.tempActions == 0 and not sawStage('failed', 1), 'no recovery while waiting at the lights (25 s)')
  W.blocked[truck], W.redLight = nil, nil
  check(runUntil(finished, 120000) and towOutcome() == 'done', 'done (' .. tostring(select(2, towOutcome())) .. ')')
  check(trucks() == 1, 'one truck')
  noNpcs('red light')
  nothingVanished('red light')
  trace()
end

do -- 43. spawn nodes without a route to the vehicle (other side of a motorway) are skipped
  local NZ = scenario('no route', { { src = 1, x = 0.0, y = -6.0 } })
  W.route = function(x1, y1, x2, y2)
    if y1 < 0 then return 100000.0 end -- south of the vehicle: no way there
    return math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2) * 1.2
  end
  local target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(function() return #W.created >= 1 end, 8000), 'truck created')
  check(W.created[1].y >= 0, ('created on a node with a route (y=%.0f)'):format(W.created[1].y))
  check(runUntil(finished, 120000) and towOutcome() == 'done', 'done (' .. tostring(select(2, towOutcome())) .. ')')
  nothingVanished('no route')
  trace()
end

do -- 44. a long vehicle never ends up in the cab: its front stops at bed.front
  for _, case in ipairs({ { h = 0.0, label = 'nose first' }, { h = 180.0, label = 'tail first' } }) do
    scenario('long vehicle ' .. case.label, { { src = 1, x = 0.0, y = -20.0 } })
    local env = W.players[1].env
    env.Config.Tow.bed.y = -1.0 -- a bed centre far forward: the clamp has to act
    local truck = newEntity(2, 'flatbed', 0.0, 0.0, 30.0, 0.0, 1, { serverCreated = 0 })
    local target = car('longcar', 0.0, -10.5, 1, { h = case.h })
    ent(target).state.nzTowing = true
    for _, fn in ipairs(env.handlers['nz:client:tow:attach'] or {}) do
      addThread(env, fn, { id = 78, netId = ent(target).netId, truck = ent(truck).netId, seconds = 4 })
    end
    run(6000)
    local poses = W.attachLog[target] or {}
    local final = poses[#poses]
    local m = MODELS.longcar
    local front = final and (case.h == 0.0 and final.y + m.max.y or final.y - m.min.y) or math.huge
    check(final ~= nil and front <= 1.2 + 0.01, ('%s: front of the vehicle at %.2f (bed.front 1.2)'):format(case.label, front))
    check(ent(target).attached and ent(target).attached.parent == truck, case.label .. ': stays attached')
  end
end

do -- 45. the runner says `loaded` but the server does not see the vehicle on the bed: no leaving
  local NZ = scenario('forged loaded', { { src = 1, x = 0.0, y = -6.0 } })
  W.players[1].deaf = true
  local target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  local r = call(1, { id = 1, stage = 'node', x = 125.0, y = 40.0, z = 30.0, heading = 90.0 })
  check(r.ok == true, 'node accepted: ' .. tostring(r.error))
  local truck, driver = find('flatbed'), find('s_m_m_trucker_01')
  r = call(1, { id = 1, stage = 'spawned', truck = ent(truck).netId, driver = ent(driver).netId })
  check(r.ok == true, 'spawned')
  r = call(1, { id = 1, stage = 'arrived' })
  r = call(1, { id = 1, stage = 'load' })
  check(r.ok == false and lastLog('impound.tow') == nil, 'load refused: the truck is not at the vehicle (server positions)')
  check(trucks() == 1 and count('flatbed') == 1, 'that truck is retired (still there: the player is near), no new one yet')
  -- the next attempt: a truck next to the vehicle, but nothing on the bed
  r = call(1, { id = 1, stage = 'node', x = 125.0, y = 80.0, z = 30.0, heading = 90.0 })
  check(r.ok == true, 'second node accepted')
  truck, driver = 0, 0 -- the newest truck and driver
  for id, en in pairs(W.entities) do
    if en.name == 'flatbed' and id > truck then truck = id end
    if en.name == 's_m_m_trucker_01' and id > driver then driver = id end
  end
  ent(truck).x, ent(truck).y = 5.0, 10.0
  r = call(1, { id = 1, stage = 'spawned', truck = ent(truck).netId, driver = ent(driver).netId })
  r = call(1, { id = 1, stage = 'arrived' })
  r = call(1, { id = 1, stage = 'load' })
  check(r.ok == true, 'load accepted next to the vehicle')
  r = call(1, { id = 1, stage = 'loaded' })
  check(r.ok == false and r.code == 'attach', 'loaded refused: the server sees nothing on the bed')
  r = call(1, { id = 1, stage = 'leaving' })
  check(r.ok == false, 'leaving refused')
  check(ent(target) ~= nil and ent(target).attached == nil, 'the vehicle stays where it was')
  run(FADE_WAIT)
  check(towOutcome() == 'fallback', 'no attempts left: ended (' .. tostring(select(2, towOutcome())) .. ')')
  check(ent(target) ~= nil, 'the vehicle stays while the player is near')
  leaveScene()
  check(ent(target) == nil, 'removed once nobody is near')
  noNpcs('forged loaded')
  nothingVanished('forged loaded')
  trace()
end

do -- 46. the runner drops with the vehicle already on the bed: the next player only drives off
  local NZ = scenario('runner drops when loaded', { { src = 1, x = 0.0, y = -6.0 }, { src = 2, x = 25.0, y = -10.0 } })
  local target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(function() return sawStage('loaded', 1) end, 120000), 'loaded by the officer')
  local truck = find('flatbed')
  drop(1)
  check(runUntil(function() return sawStage('leaving', 2) end, 20000), 'player 2 drives it off')
  check(trucks() == 1, 'the same truck')
  local poses = W.attachLog[target] or {}
  local slid = 0
  for _, p in ipairs(poses) do if math.abs(p.y + 2.35) > 0.01 then slid = slid + 1 end end
  check(ent(target).attached and ent(target).attached.parent == truck, 'the vehicle stayed on the bed')
  check(runUntil(finished, 90000) and towOutcome() == 'done', 'done (' .. tostring(select(2, towOutcome())) .. ')')
  say(('runner drops when loaded: %d slide poses'):format(slid))
  noNpcs('runner drops when loaded')
  nothingVanished('runner drops when loaded')
  trace()
end

do -- 47. the server gives up on a truck (it stands too far from the vehicle to load): the driver
   -- stops working the controls, gets back in and drives the empty truck off; a new one comes
  local NZ = scenario('dismissed on retry', { { src = 1, x = 0.0, y = -6.0 } })
  local target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(function() return sawStage('arrived', 1) end, 60000), 'arrived')
  local first, driver = find('flatbed'), find('s_m_m_trucker_01')
  -- pushed 35 m along the road while the driver walks to the controls: the server refuses `load`
  ent(target).x = 40.0
  check(runUntil(function() return trucks() == 2 end, 15000), 'a new truck comes')
  local d = dismissedTo(1)
  check(d ~= nil and d.truck == ent(first).netId and d.driver == ent(driver).netId, 'the old truck is dismissed (net ids)')
  check(runUntil(function() local dr = ent(first) and ent(first).drive return dr ~= nil and dr.wander == true end, 15000),
    'the old truck drives off')
  check(ent(driver) and ent(driver).vehicle == first, 'its driver is back at the wheel')
  check(not ent(first).noMigrate and not ent(driver).noMigrate, 'the old truck and driver may migrate again')
  check(lastLog('impound.tow') == nil and not notifiedOf(1, FAILED_TEXT), 'the tow carries on, no failure notice')
  check(runUntil(finished, 150000), 'finished')
  check(towOutcome() == 'done', 'done with the second truck (' .. tostring(select(2, towOutcome())) .. ')')
  check(ent(first) == nil, 'the dismissed truck is gone (removed once far from the player)')
  noNpcs('dismissed on retry')
  nothingVanished('dismissed on retry')
  trace()
end

do -- 48. everything on screen: the truck stops beside the vehicle the wrong way round and the other
   -- side is taken: it loads from where it stands (side path), no new truck
  local NZ = scenario('wrong way, other side taken', { { src = 1, x = 0.0, y = -30.0 } })
  W.screenRealistic, W.sight = true, 1000.0
  local target = car('sultan', 5.0, 0.0, 1)
  car('sultan', 5.0, -9.8, nil) -- parked on the spot behind the vehicle
  check(NZ.Tow.start(target, 1), 'tow started')
  local truck
  check(runUntil(function()
    truck = find('flatbed')
    local d = truck and ent(truck).drive
    return d ~= nil and not d.wander and d.speed == 5.0
  end, 90000), 'final approach')
  check(ent(truck).drive.y > 0, 'heads for the spot in front of the vehicle')
  local en = ent(truck)
  en.x, en.y, en.h, en.drive = 8.5, 0.0, 180.0, nil -- beside it, facing the other way
  W.blocked[truck] = true
  check(runUntil(function() return sawStage('arrived', 1) end, 20000), 'takes it from there')
  W.blocked[truck] = nil
  check(math.abs(en.x - 8.5) < 0.01 and math.abs(en.y) < 0.01 and en.h == 180.0, 'not moved in view of the player')
  check(runUntil(function() return sawStage('loaded', 1) end, 30000), 'loaded')
  check(trucks() == 1 and not sawStage('failed'), 'the same truck, no failure')
  local poses = W.attachLog[target] or {}
  local final = poses[#poses]
  check(final and math.abs(final.x) < 0.01 and math.abs(final.y + 2.35) < 0.01, 'ends on the bed')
  local worst = groundOverlap(poses)
  check(worst == nil, 'never through the truck at ground level' ..
    (worst and (' (%.2f m at %.2f, %.2f)'):format(worst.depth, worst.p.x, worst.p.y) or ''))
  -- the side path: along the truck's side at ground level, behind the bed, up the ramp; never
  -- lifted over the truck
  local top = -math.huge
  for _, p in ipairs(poses) do top = math.max(top, p.z) end
  check(final and top <= final.z + 0.3, ('never lifted over the truck (highest z %.2f, on the bed %.2f)'):format(top,
    final and final.z or 0))
  check(poses[1] and math.abs(poses[1].x - 3.5) < 0.05, ('starts where it stands (x=%.2f)'):format(poses[1] and poses[1].x or 0))
  -- about 12 m along the ground: about 3 s more than the configured loading time (one pose a tick)
  local seconds = W.players[1].env.Config.Tow.loadSeconds
  check(#poses >= (seconds * 1000 + 2500) / 50 and #poses <= (seconds * 1000 + 6500) / 50,
    ('the long slide gets more time (%d poses)'):format(#poses))
  check(runUntil(finished, 90000) and towOutcome() == 'done', 'done (' .. tostring(select(2, towOutcome())) .. ')')
  noNpcs('wrong way, other side taken')
  nothingVanished('wrong way, other side taken')
  trace()
end

do -- 49. parked in line but several metres short: backs up to the vehicle before loading
  local NZ = scenario('backs up', { { src = 1, x = 0.0, y = -30.0 } })
  local target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  local truck
  check(runUntil(function()
    truck = find('flatbed')
    local d = truck and ent(truck).drive
    return d ~= nil and not d.wander and d.speed == 5.0 and d.y > 0
  end, 90000), 'final approach to the front spot')
  local en = ent(truck)
  en.x, en.y, en.h, en.drive = 5.0, 15.3, 0.0, nil -- rear of the bed 7 m from the vehicle
  W.blocked[truck] = true
  check(runUntil(function() return en.drive ~= nil and en.drive.reverse == true end, 15000), 'backs up')
  check(en.drive.speed <= 2.0, 'slowly')
  W.blocked[truck] = nil
  check(runUntil(function() return sawStage('arrived', 1) end, 15000), 'arrived')
  local rear = en.y + MODELS.flatbed.min.y
  check(rear - MODELS.sultan.max.y < 3.0 and rear - MODELS.sultan.max.y > 0.5,
    ('rear of the bed close to the vehicle (%.1f m)'):format(rear - MODELS.sultan.max.y))
  check(en.h == 0.0, 'still in line')
  check(runUntil(function() return sawStage('loaded', 1) end, 30000), 'loaded')
  local poses = W.attachLog[target] or {}
  check(poses[1] and poses[1].y > -12.0, ('short slide on the ground (starts at y=%.1f)'):format(poses[1] and poses[1].y or 0))
  checkPull(target, 'backs up')
  check(runUntil(finished, 90000) and towOutcome() == 'done', 'done (' .. tostring(select(2, towOutcome())) .. ')')
  noNpcs('backs up')
  nothingVanished('backs up')
  trace()
end

do -- 50. the leaving truck is let go once far from the runner: a player near its route can
   -- simulate it (the runner no longer streams the roads there)
  local NZ = scenario('leaving migrates', { { src = 1, x = 0.0, y = -6.0 }, { src = 2, x = 3000.0, y = 0.0 } })
  local target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(function() return sawStage('leaving', 1) end, 120000), 'leaving')
  local truck, driver = find('flatbed'), find('s_m_m_trucker_01')
  check(ent(truck).noMigrate == true and ent(target).noMigrate == true, 'kept by the runner near the scene')
  -- player 2 drives along behind the truck
  local p2 = ent(W.players[2].ped)
  local function follow()
    local tx, ty = worldPos(truck)
    p2.x, p2.y = tx + 15.0, ty
  end
  check(runUntil(function()
    follow()
    local tx, ty = worldPos(truck)
    return math.sqrt(tx * tx + (ty + 6.0) ^ 2) > 210.0
  end, 60000), 'the truck is 200 m from the runner')
  runUntil(function() follow() return false end, 1500)
  check(lastLog('impound.tow') == nil, 'still running (a player is near the truck)')
  check(not ent(truck).noMigrate and not ent(driver).noMigrate and not ent(target).noMigrate,
    'truck, driver and vehicle may migrate again')
  check(ent(target).attached and ent(target).attached.parent == truck, 'the vehicle is still on the bed')
  p2.x = p2.x + 5000.0
  check(runUntil(finished, 90000) and towOutcome() == 'done', 'done (' .. tostring(select(2, towOutcome())) .. ')')
  noNpcs('leaving migrates')
  nothingVanished('leaving migrates')
  trace()
end

do -- 51. stuck out of the runner's sight, but another player watches the truck: never moved in
   -- front of them; a new truck comes
  local NZ = scenario('stuck, watched', { { src = 1, x = 0.0, y = -6.0 }, { src = 2, x = 3000.0, y = 0.0 } })
  W.sight, W.los = 5.0, true
  local target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(function() return sawStage('spawned', 1) end, 8000), 'spawned')
  local first = find('flatbed')
  W.blocked[first] = true
  local fx, fy = worldPos(first)
  local p2 = ent(W.players[2].ped)
  p2.x, p2.y = fx + 20.0, fy
  check(runUntil(function() return trucks() == 2 end, 120000), 'gave up on the stuck truck, a new one comes')
  local x, y = worldPos(first)
  check(math.abs(x - fx) < 0.01 and math.abs(y - fy) < 0.01, 'never moved in front of the other player')
  check(runUntil(finished, 150000) and towOutcome() == 'done', 'done (' .. tostring(select(2, towOutcome())) .. ')')
  leaveScene()
  noNpcs('stuck, watched')
  nothingVanished('stuck, watched')
  trace()
end

do -- 52. everything on screen: the truck stops nose to nose with the vehicle (in line ahead of the
   -- cab) and the other side is taken: never lifted over the cab; this truck drives off empty and
   -- a new one loads it from behind the bed
  local NZ = scenario('nose to nose, on screen', { { src = 1, x = 0.0, y = -30.0 } })
  W.screenRealistic, W.sight = true, 1000.0
  local target = car('sultan', 5.0, 0.0, 1)
  local parked = car('sultan', 5.0, -9.8, nil) -- parked on the spot behind the vehicle
  check(NZ.Tow.start(target, 1), 'tow started')
  local first
  check(runUntil(function()
    first = find('flatbed')
    local d = first and ent(first).drive
    return d ~= nil and not d.wander and d.speed == 5.0
  end, 90000), 'final approach')
  local en = ent(first)
  -- facing the vehicle's nose, 1.5 m apart: the rear of the bed about 12 m from it
  en.x, en.y, en.h, en.drive = 5.0, 2.3 + 1.5 + MODELS.flatbed.max.y, 180.0, nil
  W.blocked[first] = true
  check(runUntil(function() return trucks() == 2 end, 40000), 'a new truck comes')
  W.blocked[first] = nil
  check(#(W.attachLog[target] or {}) == 0 and W.loadedBy[first] == nil, 'the first truck never touched the vehicle')
  check(runUntil(function() local d = ent(first) and ent(first).drive return d ~= nil and d.wander == true end, 15000),
    'the first truck drives off empty')
  -- the parked car leaves meanwhile: the second truck may use either spot
  ent(parked).x = 600.0
  check(runUntil(function() return sawStage('loaded', 1) end, 120000), 'loaded by the second truck')
  local poses = W.attachLog[target] or {}
  local final = poses[#poses]
  local top = -math.huge
  for _, p in ipairs(poses) do top = math.max(top, p.z) end
  check(final and top <= final.z + 0.3, ('never lifted over a truck (highest z %.2f)'):format(top))
  check(W.loadedBy[first] == nil, 'only the second truck carries it')
  checkPull(target, 'nose to nose')
  check(runUntil(finished, 90000) and towOutcome() == 'done', 'done (' .. tostring(select(2, towOutcome())) .. ')')
  leaveScene()
  noNpcs('nose to nose, on screen')
  nothingVanished('nose to nose, on screen')
  trace()
end

do -- 53. the server gives up on the truck while the vehicle is half way up the ramp (self pull):
   -- the driver goes back to the wheel and stays there (stopWorking leaves him alone), the
   -- vehicle is put onto the deck instead of hanging off the ramp
  scenario('dismissed mid-load', { { src = 1, x = 0.0, y = -6.0 } })
  local NZ = W.server.NZ
  local target = car('sultan', 5.0, 0.0, 1)
  check(NZ.Tow.start(target, 1), 'tow started')
  check(runUntil(function() return sawStage('load', 1) end, 60000), 'loading')
  run(2000)
  local truck, driver = find('flatbed'), find('s_m_m_trucker_01')
  local half = ent(target).attached
  check(half ~= nil and half.parent == truck and (half.y < -3.0 or half.z < 0.5), 'half way onto the bed')
  check(ent(driver).vehicle == nil, 'the driver works the controls')
  local id
  for _, ev in ipairs(W.sent) do
    if ev.name == 'nz:client:tow:start' and ev.target == 1 then id = ev.args[1].id end
  end
  for _, fn in ipairs(W.players[1].env.handlers['nz:client:tow:stop'] or {}) do
    fn({ id = id, dismiss = true, truck = ent(truck).netId, driver = ent(driver).netId, netId = ent(target).netId })
  end
  -- the dismiss thread may run before the scene notices (any order in game)
  table.insert(threads, 1, table.remove(threads))
  run(1500)
  check(W.pedTask[driver] == 'enter' or W.pedTask[driver] == 'warp' or W.pedTask[driver] == 'wander',
    'the driver is sent back to the wheel, not cleared (' .. tostring(W.pedTask[driver]) .. ')')
  check(ent(driver).vehicle == truck, 'the driver sits at the wheel')
  local poses = W.attachLog[target] or {}
  local last = poses[#poses]
  check(last and math.abs(last.x) < 0.01 and math.abs(last.y + 2.35) < 0.01 and (last.p or 0) == 0,
    'the vehicle is put onto the deck, level')
  check(ent(target).attached and ent(target).attached.parent == truck, 'still on the truck')
  check(not (ent(truck).drive and ent(truck).drive.wander), 'the truck does not drive off with it')
  check(runUntil(finished, 120000), 'finished')
  leaveScene()
  noNpcs('dismissed mid-load')
  trace()
end

---------------------------------------------------------------------------------------

for _, e in ipairs(runtimeErrors) do failures[#failures + 1] = 'runtime: ' .. e end
for _, e in ipairs(printedErrors) do failures[#failures + 1] = 'lib.print.error: ' .. e end
if #failures > 0 then
  print(('tow: %d of %d checks failed'):format(#failures, checks))
  for _, f in ipairs(failures) do print('  - ' .. f) end
  os.exit(1)
end
print(('tow OK (%d checks)'):format(checks))
