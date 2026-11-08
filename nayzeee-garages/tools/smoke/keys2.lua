--[[
  Headless test for the car lock v2 core (docs/V2_CHANGES.md G; no FiveM needed).

  Same stubbed server runtime as tools/smoke/carlock.lua (in-memory vehicle database, fake
  ox_inventory with metadata and hooks, fake world), plus the v2 tables. Traces:
    admin key settings (schema, validation, live apply, reset, config migration),
    key modes flexible / limited / virtual (retrieve, reuse from the glovebox, sharing),
    key custody (pocket, ox stash move hook, ground, lost), keyless entry and the server
    auto-lock, per-player settings, immobilisers and Ghost PINs (hotwire refused, PIN gate,
    wrong-PIN cooldown + alarm, remote start refused, owner change clears the PIN),
    keys on the ground (drop, toss, throw + catch / miss, inspect / keep / return, expiry,
    resource restart), remote engine / windows and the admin key manager API.

  Usage (from the resource root):  lua5.4 tools/smoke/keys2.lua
]]

local failures, checks = {}, 0
local function check(cond, label)
  checks = checks + 1
  if not cond then failures[#failures + 1] = label; if os.getenv("NZDBG") then print("FAIL: " .. label) end end
end

---------------------------------------------------------------------------------------
-- Runtime: clock, scheduler, events
---------------------------------------------------------------------------------------

local clock = 0
local BASE_TIME = 1700000000
local bootOffset = 0          -- moves os.time vs the game timer (a "server restart")
local realTime = os.time
os.time = function(t)         -- luacheck: ignore 122
  if t then return realTime(t) end
  return BASE_TIME + bootOffset + clock // 1000
end

local threads = {}
function CreateThread(fn) threads[#threads + 1] = { co = coroutine.create(fn), wake = clock } end
function Wait(ms)
  if not coroutine.isyieldable() then error('Wait() outside a thread', 2) end
  coroutine.yield(ms or 0)
end
function SetTimeout(ms, fn) CreateThread(function() Wait(ms) fn() end) end
Citizen = { CreateThread = CreateThread, Wait = Wait, SetTimeout = SetTimeout }
function GetGameTimer() return clock end

local function runDue()
  local list = {}
  for i = 1, #threads do list[i] = threads[i] end
  for _, t in ipairs(list) do
    if coroutine.status(t.co) == 'suspended' and t.wake <= clock then
      local okR, res = coroutine.resume(t.co)
      if not okR then failures[#failures + 1] = 'thread error: ' .. debug.traceback(t.co, tostring(res)) end
      t.wake = clock + (tonumber(res) or 0)
    end
  end
  for i = #threads, 1, -1 do
    if coroutine.status(threads[i].co) == 'dead' then table.remove(threads, i) end
  end
end

local function advance(ms)
  local target = clock + ms
  runDue()
  while clock < target do
    clock = math.min(target, clock + 100)
    runDue()
  end
end

--- Run fn(...) in a thread until it returns (driving the clock); returns its results.
local function run(fn, ...)
  local args = table.pack(...)
  local results
  CreateThread(function() results = table.pack(fn(table.unpack(args, 1, args.n))) end)
  runDue()
  local guard = 0
  while not results do
    clock = clock + 50
    runDue()
    guard = guard + 1
    if guard > 20000 then error('run(): the call never returned') end
  end
  return table.unpack(results, 1, results.n)
end

local handlers, clientEvents = {}, {}
local removedHandlers = 0
function AddEventHandler(name, fn)
  handlers[name] = handlers[name] or {}
  local entry = { name = name, fn = fn }
  table.insert(handlers[name], entry)
  return entry
end
function RemoveEventHandler(entry)
  if type(entry) ~= 'table' then return end
  for i, e in ipairs(handlers[entry.name] or {}) do
    if e == entry then table.remove(handlers[entry.name], i) removedHandlers = removedHandlers + 1 return end
  end
end
function RegisterNetEvent(name, fn) if fn then AddEventHandler(name, fn) end end
function TriggerEvent(name, ...)
  for _, e in ipairs(handlers[name] or {}) do
    source = ''  -- luacheck: ignore 111
    e.fn(...)
  end
end
function TriggerClientEvent(name, target, payload) clientEvents[#clientEvents + 1] = { name = name, target = target, payload = payload } end

--- Fire a net event as player `src` (handlers see the global `source`).
local function fireNet(name, src, ...)
  local args = table.pack(...)
  return run(function()
    for _, e in ipairs(handlers[name] or {}) do
      source = src  -- luacheck: ignore 111
      e.fn(table.unpack(args, 1, args.n))
    end
  end)
end

local function clientEventsFor(name, target)
  local n = 0
  for _, e in ipairs(clientEvents) do
    if e.name == name and (target == nil or e.target == target) then n = n + 1 end
  end
  return n
end

---------------------------------------------------------------------------------------
-- Natives: players, entities, state bags, KVP
---------------------------------------------------------------------------------------

local vmeta = {}
vmeta.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vmeta) end
vmeta.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
vmeta.__add = function(a, b) return setmetatable({ x = a.x + b.x, y = a.y + b.y, z = a.z + b.z }, vmeta) end
vmeta.__mul = function(a, b)
  if type(a) == 'number' then a, b = b, a end
  return setmetatable({ x = a.x * b, y = a.y * b, z = a.z * b }, vmeta)
end
local function vec3(x, y, z) return setmetatable({ x = x or 0.0, y = y or 0.0, z = z or 0.0 }, vmeta) end
vector3 = vec3
-- like CfxLua: type(vector3(...)) is 'vector3', not 'table'
local rawtype = type
type = function(v)
  if rawtype(v) == 'table' and getmetatable(v) == vmeta then return 'vector3' end
  return rawtype(v)
end
function vector4(x, y, z, w) return { x = x or 0.0, y = y or 0.0, z = z or 0.0, w = w or 0.0 } end
vec4 = vector4

local function joaat_(s)
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
joaat = joaat_
GetHashKey = joaat_

local online = { [1] = 'CID001', [2] = 'CID002', [3] = 'CID003', [4] = 'CID004' }
local noChar = { [4] = true }  -- player 4 is connected but has no character loaded
local playerPos = { [1] = vec3(0, 0, 0), [2] = vec3(1, 0, 0), [3] = vec3(2, 0, 0), [4] = vec3(1, 1, 0) }
local admins = { [3] = true }
function GetPlayerName(src) return online[tonumber(src)] and ('Player' .. tostring(src)) or nil end
function GetPlayerPed(src) return online[tonumber(src)] and (1000 + tonumber(src)) or 0 end
function GetPlayerRoutingBucket() return 0 end
function GetEntityRoutingBucket() return 0 end
function IsPlayerAceAllowed() return false end
function IsDuplicityVersion() return true end
function GetCurrentResourceName() return 'nayzeee-garages' end
function GetInvokingResource() return nil end
function GetConvar(_, default) return default end
function IsPedAPlayer(ped) return type(ped) == 'number' and ped > 1000 and ped < 2000 end
local resourceStates = { ['qb-core'] = 'started', ox_inventory = 'started' }
function GetResourceState(name) return resourceStates[name] or 'missing' end

GlobalState = {}
function GetPlayers() local out = {} for src in pairs(online) do out[#out + 1] = tostring(src) end table.sort(out) return out end
local bagHandlers = {}    -- [key] = { fn, ... } (server-side state bag change handlers)
function AddStateBagChangeHandler(key, _, fn) bagHandlers[key] = bagHandlers[key] or {} table.insert(bagHandlers[key], fn) end
function GetEntityFromStateBagName(name) return tonumber(tostring(name):match('^entity:(%d+)$')) or 0 end

local kvp = {}
function GetResourceKvpString(k) return kvp[k] end
function SetResourceKvp(k, v) kvp[k] = v end
function DeleteResourceKvp(k) kvp[k] = nil end

-- Vehicles: [handle] = { plate, model, netId, seats = { [-1] = ped }, coords, pop, lock, engine }
local entities, nextHandle, nextNet = {}, 5000, 100
local objects, nextObject = {}, 9000
local states = {}
local function stateOf(handle)
  local s = states[handle]
  if not s then
    s = setmetatable({}, { __index = { set = function(self, k, v)
      rawset(self, k, v)
      for _, fn in ipairs(bagHandlers[k] or {}) do fn('entity:' .. tostring(handle), k, v) end
    end } })
    states[handle] = s
  end
  return s
end
function Entity(handle) return { state = stateOf(handle) } end

local function spawnVehicle(plate, model, coords, pop)
  nextHandle, nextNet = nextHandle + 1, nextNet + 1
  entities[nextHandle] = { plate = plate, model = joaat_(model or 'sultan'), netId = nextNet, seats = {},
    coords = coords or vec3(3, 0, 0), pop = pop or 7, lock = 0 }
  return nextHandle, nextNet
end

local function seat(src, handle)
  for _, e in pairs(entities) do
    for s, ped in pairs(e.seats) do if ped == 1000 + src then e.seats[s] = nil end end
  end
  if handle then entities[handle].seats[-1] = 1000 + src end
end

function DoesEntityExist(h) return entities[h] ~= nil or objects[h] ~= nil or (h > 1000 and h < 2000 and online[h - 1000] ~= nil) end
function GetEntityType(h) return entities[h] and 2 or (h > 1000 and h < 2000 and 1 or 0) end
function GetAllVehicles() local out = {} for h in pairs(entities) do out[#out + 1] = h end table.sort(out) return out end
function GetVehicleNumberPlateText(h) local e = entities[h] return e and (e.plate .. '        '):sub(1, 8) or '' end
function NetworkGetEntityFromNetworkId(netId)
  for h, e in pairs(entities) do if e.netId == netId then return h end end
  return 0
end
function NetworkGetNetworkIdFromEntity(h) return entities[h] and entities[h].netId or 0 end
function GetPedInVehicleSeat(h, s) local e = entities[h] return e and e.seats[s] or 0 end
function GetVehiclePedIsIn(ped)
  for h, e in pairs(entities) do
    for _, p in pairs(e.seats) do if p == ped then return h end end
  end
  return 0
end
function GetEntityModel(h) return entities[h] and entities[h].model or 0 end
function GetEntityHeading(h) return entities[h] and entities[h].heading or 0.0 end
function NetworkGetEntityOwner(h) return entities[h] and (entities[h].owner or 1) or -1 end
function CreateObjectNoOffset(model, x, y, z)
  nextObject = nextObject + 1
  objects[nextObject] = { model = model, coords = vec3(x, y, z) }
  return nextObject
end
function GetVehicleType() return 'automobile' end
function GetEntityPopulationType(h) return entities[h] and entities[h].pop or 0 end
function GetEntityCoords(h)
  if entities[h] then return entities[h].coords end
  if objects[h] then return objects[h].coords end
  local src = h - 1000
  return playerPos[src] or vec3(0, 0, 0)
end
function SetVehicleDoorsLocked(h, s) if entities[h] then entities[h].lock = s end end
function GetVehicleDoorLockStatus(h) return entities[h] and entities[h].lock or 0 end
function DeleteEntity(h)
  if objects[h] then objects[h] = nil return end
  if not entities[h] then return end
  entities[h], states[h] = nil, nil
  TriggerEvent('entityRemoved', h)
end

setmetatable(_G, { __index = function(_, k)
  if type(k) == 'string' and k:match('^%u') then return function() return nil end end
  return nil
end })

---------------------------------------------------------------------------------------
-- ox_lib, exports, json
---------------------------------------------------------------------------------------

local printed = { info = {}, warn = {}, error = {} }
local callbacks = {}
lib = {
  print = {
    info = function(...) printed.info[#printed.info + 1] = table.concat({ ... }, ' ') end,
    warn = function(...) printed.warn[#printed.warn + 1] = table.concat({ ... }, ' ') end,
    error = function(...) printed.error[#printed.error + 1] = table.concat({ ... }, ' ') end,
    debug = function() end,
  },
  callback = { register = function(name, fn) callbacks[name] = fn end },
}

local commands = {}
function RegisterCommand(name, fn) commands[name] = fn end

-- Fake ox_inventory: [src] = { [slot] = { name, count, metadata, slot } }
local inv = { [1] = {}, [2] = {}, [3] = {}, [4] = {} }
local function oxCopy(t) local o = {} for k, v in pairs(t or {}) do o[k] = v end return o end
local oxDefined = { vehicle_key = true, vehicle_fob = true, lockpick = true, advancedlockpick = true }
local oxHooks = {}
local ox = {
  Items = function(name) return oxDefined[name] and { name = name } or nil end,
  GetInventoryItems = function(src)
    local out = {}
    for slot, item in pairs(inv[src] or {}) do out[slot] = { name = item.name, count = item.count, metadata = oxCopy(item.metadata), slot = slot } end
    return out
  end,
  GetSlot = function(src, slot)
    local item = (inv[src] or {})[slot]
    return item and { name = item.name, count = item.count, metadata = oxCopy(item.metadata), slot = slot } or nil
  end,
  CanCarryItem = function() return true end,
  AddItem = function(src, name, count, md)
    local list = inv[src]
    if not list then return false, 'invalid_inventory' end
    local slot = 1
    while list[slot] do slot = slot + 1 end
    list[slot] = { name = name, count = count, metadata = oxCopy(md), slot = slot }
    return true, { { slot = slot } }
  end,
  RemoveItem = function(src, name, count, _, slot)
    local item = (inv[src] or {})[slot]
    if not item or item.name ~= name then return false end
    item.count = item.count - count
    if item.count <= 0 then inv[src][slot] = nil end
    return true
  end,
  SetMetadata = function(src, slot, md) if inv[src][slot] then inv[src][slot].metadata = md end end,
  registerHook = function(name, fn, opts) oxHooks[name] = { fn = fn, opts = opts } return 77 end,
  removeHooks = function() end,
}

-- Fake qb-core (one use handler per item, like QBCore.UsableItems) and qb-inventory hooks
local qbPrevUses = {}
local qbUsable = {
  lockpick = { func = function(src, item) qbPrevUses[#qbPrevUses + 1] = { src = src, item = item } end, resource = 'qb-smallresources' },
}
local qbCallbacks = {}
-- functions of another resource's object arrive as function references: callable tables
local function funcref(fn)
  return setmetatable({ __cfx_functionReference = 'ref' }, { __call = function(_, ...) return fn(...) end })
end
local qbCoreObj = {
  Functions = {
    CreateUseableItem = funcref(function(name, fn) qbUsable[name] = { func = fn, resource = 'nayzeee-garages' } end),
    CanUseItem = funcref(function(name) return qbUsable[name] end),
    CreateCallback = funcref(function(name, fn) qbCallbacks[name] = fn end),
  },
  Shared = { Vehicles = {}, Items = { vehicle_key = { name = 'vehicle_key' }, vehicle_fob = { name = 'vehicle_fob' } } },
}
local qbHooks, qbHookRemoved = {}, nil
local qbInventory = {
  AddHook = function(kind, fn) qbHooks[kind] = fn return 7 end,
  RemoveHook = function(_, id) qbHookRemoved = id end,
}

-- qb-core drops the usable items of a stopping resource (server/events.lua). It started
-- before us, so its handler runs first here; the order is not fixed in FiveM.
AddEventHandler('onResourceStop', function(resource)
  for name, entry in pairs(qbUsable) do
    if entry.resource == resource then qbUsable[name] = nil end
  end
end)

local exported = {}
local exportTables = { ox_inventory = ox, ['qb-core'] = { GetCoreObject = function() return qbCoreObj end }, ['qb-inventory'] = qbInventory }
exports = setmetatable({}, {
  __call = function(_, name, fn) exported[name] = fn end,
  __index = function(_, res)
    local t = exportTables[res]
    return setmetatable({}, { __index = function(_, fn)
      return function(_, ...)
        if t and t[fn] then return t[fn](...) end
        return nil
      end
    end })
  end,
})

local dk = require('dkjson')
json = { encode = function(v) return dk.encode(v) end, decode = function(s) if type(s) ~= 'string' then return nil end return (dk.decode(s)) end }

---------------------------------------------------------------------------------------
-- Load
---------------------------------------------------------------------------------------

local function load_(file)
  local f = assert(io.open(file, 'r'), 'missing ' .. file)
  local src = f:read('a')
  f:close()
  local chunk = assert(load(src, '@' .. file, 't', _ENV))
  local okLoad, err = xpcall(chunk, debug.traceback)
  if not okLoad then failures[#failures + 1] = 'load ' .. file .. ': ' .. tostring(err) end
end

load_('config/config.lua')
load_('config/carlock.lua')
load_('shared/init.lua')
load_('shared/utils.lua')
load_('shared/carlock.lua')
load_('bridge/shared.lua')
NZ.Framework = 'qb'
local CarLock = NZ.CarLock
NZ.Ready = true

---------------------------------------------------------------------------------------
-- In-memory modules the car lock uses
---------------------------------------------------------------------------------------

local notifications = {}
NZ.Bridge.getIdentifier = function(src) if noChar[tonumber(src)] then return nil end return online[tonumber(src)] end
NZ.Bridge.getSourceByIdentifier = function(id) for src, cid in pairs(online) do if cid == id then return src end end return nil end
NZ.Bridge.getCharacterName = function(id) return 'Name ' .. tostring(id) end
NZ.Bridge.getJob = function() return nil end
NZ.Bridge.getGang = function() return nil end
NZ.Bridge.getPlayer = function() return nil end
NZ.Bridge.notify = function(src, message, kind) notifications[#notifications + 1] = { src = src, message = message, kind = kind } end
NZ.Bridge._fw = { hasAnyGroup = function() return false end }

local rateOpen = true
NZ.Access.rateLimit = function() return rateOpen end
NZ.Access.isAdmin = function(src) return admins[tonumber(src)] == true end

local logs = {}
NZ.Logs.add = function(event, src, data) logs[#logs + 1] = { event = event, src = src, data = data } end

-- vehicle table + nz_keys + nz_shares + nz_settings
local rows = {
  ABC123 = { plate = 'ABC123', owner = 'CID001', model = 'sultan', hash = joaat_('sultan'), version = 0 },
  FOB777 = { plate = 'FOB777', owner = 'CID001', model = 'zentorno', hash = joaat_('zentorno'), version = 0 },
}
local nzKeys = {}         -- [plate] = { [identifier] = grantedBy }
local dbDown = false      -- true: every key-state query fails (database error)
local shares = {}         -- [identifier] = { plate, ... }
local settingsTable = {}
NZ.DB.getVehicle = function(plate) local r = rows[plate] return r and oxCopy(r) or nil end
NZ.DB.getVehiclesByOwner = function(id)
  local out = {}
  for _, r in pairs(rows) do if r.owner == id then out[#out + 1] = oxCopy(r) end end
  return out
end
NZ.DB.shares = { forIdentifier = function(id) return shares[id] or {} end, forPlate = function() return {} end }
NZ.DB.keys = {
  list = function(plate)
    local out = {}
    for id, by in pairs(nzKeys[plate] or {}) do out[#out + 1] = { identifier = id, grantedBy = by, createdAt = 1 } end
    table.sort(out, function(a, b) return a.identifier < b.identifier end)
    return out
  end,
  forIdentifier = function(id)
    local out = {}
    for plate, list in pairs(nzKeys) do if list[id] then out[#out + 1] = plate end end
    return out
  end,
  add = function(plate, id, by) nzKeys[plate] = nzKeys[plate] or {} nzKeys[plate][id] = by or '' return true end,
  remove = function(plate, id) if nzKeys[plate] then nzKeys[plate][id] = nil end return true end,
  clear = function(plate) nzKeys[plate] = nil return true end,
  count = function(plate) local n = 0 for _ in pairs(nzKeys[plate] or {}) do n = n + 1 end return n end,
  -- key state on the vehicle row: version (nz_key_version) + mark (nz_key_owner)
  state = function(plate)
    if dbDown then return nil, 'error' end
    local r = rows[plate]
    if not r then return false end
    return { version = r.version, mark = r.mark, owner = r.owner, job = r.job, gang = r.gang, markSupported = true }
  end,
  version = function(plate)
    if dbDown then return nil, 'error' end
    local r = rows[plate] return r and r.version or nil
  end,
  claim = function(plate, mark, initial)
    if dbDown then return nil end
    local r = rows[plate]
    if not r then return false end
    if r.mark == mark then return false end
    r.version = r.mark == nil and initial or r.version + 1
    r.mark = mark
    return true
  end,
  bumpVersion = function(plate, mark, initial)
    if dbDown then return nil end
    local r = rows[plate]
    if not r then return nil end
    if mark then
      r.version = r.mark == nil and initial or r.version + 1
      r.mark = mark
    else
      r.version = r.version + 1
    end
    return r.version
  end,
  secret = function(candidate)
    if dbDown then return nil end
    if not settingsTable.carlock_secret then settingsTable.carlock_secret = candidate end
    return settingsTable.carlock_secret
  end,
}
NZ.Vehicles.out = {}
NZ.Vehicles.fleetOf = function() return nil, nil end
local jobsOf = {}         -- [identifier] = job (fleet access to rows with that job)
NZ.Vehicles.accessOf = function(src, row, _, cache)
  local id = cache and cache.identifier or online[src]
  if row.owner == id then return 'owner' end
  for _, e in ipairs(shares[id] or {}) do
    local p = type(e) == 'table' and e.plate or e
    if p == row.plate then return 'shared' end
  end
  if row.job and jobsOf[id] == row.job then return 'fleet' end
  return nil
end

-- car lock v2 tables (server/db.lua)
local keyItemsDb = {}     -- [ref] = row
local securityDb = {}     -- [plate] = { immobiliser, pinHash }
local playersDb = {}      -- [identifier] = data
local groundDb = {}       -- [id] = row
local keySettingsDb = nil
local function copyRow(r) local o = {} for k, v in pairs(r) do o[k] = v end return o end
NZ.DB.keyTables = true
NZ.DB.keyItems = {
  upsert = function(e)
    local cur = keyItemsDb[e.id]
    if cur then cur.custody, cur.holder, cur.slot = e.custody, e.holder, e.slot return true end
    keyItemsDb[e.id] = { id = e.id, plate = e.plate, version = e.version, kind = e.kind, origin = e.origin,
      custody = e.custody, holder = e.holder, slot = e.slot, createdBy = e.createdBy }
    return true
  end,
  move = function(id, custody, holder, slot)
    local cur = keyItemsDb[id]
    if not cur then return false end
    cur.custody, cur.holder, cur.slot = custody, holder, slot
    return true
  end,
  get = function(id) return keyItemsDb[id] and copyRow(keyItemsDb[id]) or nil end,
  forPlate = function(plate)
    local out = {}
    for _, r in pairs(keyItemsDb) do if r.plate == plate then out[#out + 1] = copyRow(r) end end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
  end,
  forHolder = function(holder)
    local out = {}
    for _, r in pairs(keyItemsDb) do if r.holder == holder then out[#out + 1] = copyRow(r) end end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
  end,
  countLive = function(plate, version)
    local n = 0
    for _, r in pairs(keyItemsDb) do if r.plate == plate and r.version == version and r.custody ~= 'lost' then n = n + 1 end end
    return n
  end,
  remove = function(id) keyItemsDb[id] = nil return true end,
  totals = function() return { items = 0, lost = 0 } end,
}
NZ.DB.keySecurity = {
  get = function(plate)
    local r = securityDb[plate]
    return r and { immobiliser = r.immobiliser, pinHash = r.pinHash } or { immobiliser = 'none' }
  end,
  set = function(plate, level, pinHash)
    local r = securityDb[plate] or {}
    r.immobiliser = level
    if pinHash == false then r.pinHash = nil elseif pinHash ~= nil then r.pinHash = pinHash end
    securityDb[plate] = r
    return true
  end,
}
NZ.DB.keyPlayers = {
  get = function(id) return playersDb[id] and copyRow(playersDb[id]) or nil end,
  set = function(id, data) playersDb[id] = copyRow(data) return true end,
}
NZ.DB.groundKeys = {
  all = function() local out = {} for _, g in pairs(groundDb) do out[#out + 1] = g end return out end,
  add = function(g) groundDb[g.id] = g return true end,
  remove = function(id) groundDb[id] = nil return true end,
  clear = function() groundDb = {} return true end,
}
NZ.DB.keySettings = {
  load = function() return keySettingsDb and copyRow(keySettingsDb) or {} end,
  save = function(values) keySettingsDb = copyRow(values) return true end,
}
NZ.DB.searchPlates = function(q)
  local out = {}
  for plate, r in pairs(rows) do if plate:find(q, 1, true) then out[#out + 1] = { plate = plate, owner = r.owner } end end
  return out
end
NZ.Bridge.searchCharacters = function(q)
  local out = {}
  for _, cid in pairs(online) do if cid:find(q, 1, true) then out[#out + 1] = { identifier = cid, name = 'Name ' .. cid } end end
  return out, #out
end

local function loadServer()
  load_('bridge/server/inventory.lua')
  load_('bridge/server/keys.lua')
  load_('bridge/server/dispatch.lua')
  load_('bridge/server/listeners.lua')
  load_('server/carlock/keys.lua')
  load_('server/carlock/main.lua')
  load_('server/carlock/crime.lua')
  load_('server/carlock/locksmith.lua')
  load_('server/carlock/tracker.lua')
  load_('server/carlock/exports.lua')
end
loadServer()
advance(3000) -- usable item registration, key secret

local function cb(name, src, payload)
  local fn = callbacks[name]
  if not fn then failures[#failures + 1] = 'callback missing: ' .. name return { ok = false } end
  return run(fn, src, payload)
end

local function itemsOf(src, name)
  local out = {}
  for slot, item in pairs(inv[src]) do if item.name == name then out[#out + 1] = { slot = slot, item = item } end end
  table.sort(out, function(a, b) return a.slot < b.slot end)
  return out
end

local function hasKey(src, plate) return run(CarLock.hasKey, src, plate) end

local function notified(src, needle)
  for i = #notifications, 1, -1 do
    local n = notifications[i]
    if n.src == src and type(n.message) == 'string' and n.message:find(needle, 1, true) then return true end
  end
  return false
end
local function lastClient(name, target)
  for i = #clientEvents, 1, -1 do
    local e = clientEvents[i]
    if e.name == name and (target == nil or e.target == target) then return e end
  end
  return nil
end
local function settingsSave(values, reset) return run(CarLock.saveAdminSettings, values, reset, nil) end
local function settingOf(data, id)
  for _, s in ipairs(data.settings or {}) do if s.id == id then return s end end
  return nil
end
local function refOf(md) return CarLock.keyRef(md) end
local function fresh(plate, model, owner, coords)
  rows[plate] = { plate = plate, owner = owner or 'CID001', model = model, hash = joaat_(model), version = 0 }
  local h, net = spawnVehicle(plate, model, coords or vec3(3, 0, 0), 7)
  NZ.Vehicles.out[plate] = { src = 1, identifier = owner or 'CID001', entity = h, netId = net, spawner = false }
  return h, net
end
local function retrieve(src, net, plate)
  advance(11000) -- the hand-out bridge deduplicates the same vehicle for 10 s
  return run(NZ.KeysServer.give, src, net, plate)
end

---------------------------------------------------------------------------------------
-- 1. Admin key settings: schema, validation, live apply, reset, migration
---------------------------------------------------------------------------------------

check(CarLock.keyMode() == 'flexible' and Config.CarLock.keyMode == 'flexible', 'default key mode: flexible (written into Config.CarLock)')
Config.CarLock.keyMode = 'physical'
check(CarLock.keyMode() == 'flexible', "an older 'physical' config means flexible")
Config.CarLock.keyMode = 'auto'
check(CarLock.keyMode() == 'flexible' and run(CarLock.mode) == 'physical', "'auto' means flexible: key items with ox_inventory")
Config.CarLock.keyMode = 'flexible'
check(type(GlobalState.nzKeySettings) == 'table', 'admin values published to clients (GlobalState.nzKeySettings)')

local res = cb('nz:carlock:admin:settings', 1, {})
check(not res.ok, 'key settings: admins only')
res = cb('nz:carlock:admin:settings', 3, {})
check(res.ok and #res.data.tabs == 8 and #res.data.settings > 40, 'key settings: 8 tabs, the whole schema')
local modeEntry = res.ok and settingOf(res.data, 'keys.mode') or {}
check(modeEntry.value == 'flexible' and modeEntry.default == 'flexible' and modeEntry.type == 'enum' and #modeEntry.options == 3
  and type(modeEntry.label) == 'string' and type(modeEntry.description) == 'string', 'a setting carries value, default, options, label and description')
res = cb('nz:carlock:admin:saveSettings', 1, { values = { ['keys.remoteRange'] = 45 } })
check(not res.ok and CarLock.range('fob') == 30.0, 'non-admins cannot save')
res = cb('nz:carlock:admin:saveSettings', 3, { values = { ['keys.remoteRange'] = 45 } })
check(res.ok and CarLock.range('fob') == 45.0 and GlobalState.nzKeySettings['keys.remoteRange'] == 45
  and keySettingsDb['keys.remoteRange'] == 45 and settingOf(res.data, 'keys.remoteRange').overridden == true,
  'a saved value applies at once (server config, clients, database)')
res = cb('nz:carlock:admin:saveSettings', 3, { values = { ['keys.remoteRange'] = 9999 } })
check(not res.ok and res.error:find('Invalid value', 1, true) and CarLock.range('fob') == 45.0, 'out of range values are refused (all or nothing)')
res = cb('nz:carlock:admin:saveSettings', 3, { values = { ['ground.markerColor'] = 'teal', ['keys.keyRange'] = 7 } })
check(not res.ok and CarLock.range('key') == 5.0, 'a bad colour refuses the whole save')
res = cb('nz:carlock:admin:saveSettings', 3, { values = { ['nope.nothing'] = 1 } })
check(not res.ok, 'unknown settings are refused')
res = cb('nz:carlock:admin:saveSettings', 3, { reset = { 'keys.remoteRange' } })
check(res.ok and CarLock.range('fob') == 30.0 and keySettingsDb['keys.remoteRange'] == nil, 'reset: back to the config file value')
check(settingsSave({ ['vehicles.highendClasses'] = { 4, 6, 7, 15, 16 } }) and Config.CarLock.profileByClass[4] == 'highend'
  and select(1, CarLock.profileOf('dominator', 4)) == 'highend', 'class list setting rewrites profileByClass (profiles follow)')
check(settingsSave(nil, { 'vehicles.highendClasses' }) and Config.CarLock.profileByClass[4] == nil and Config.CarLock.profileByClass[6] == 'highend',
  'reset restores the original class map')
check(settingsSave({ ['keys.ownerHasKey'] = 'yes' }) and Config.CarLock.ownerHasKey == true, "enum 'yes' -> ownerHasKey = true")
check(settingsSave(nil, { 'keys.ownerHasKey' }) and Config.CarLock.ownerHasKey == nil, 'reset -> nil (auto)')
check(settingsSave({ ['npc.drop'] = 40 }) and Config.CarLock.npc.reactions.drop == 40, 'NPC reaction weights are admin settings')
settingsSave(nil, { 'npc.drop' })

---------------------------------------------------------------------------------------
-- 2. Flexible: key items, reuse from the glovebox, sharing makes a copy
---------------------------------------------------------------------------------------

local car, carNet = fresh('ABC123', 'sultan')
check(retrieve(1, carNet, 'ABC123') == true and #itemsOf(1, 'vehicle_key') == 1, 'flexible: a key item on retrieval')
local key1 = itemsOf(1, 'vehicle_key')[1]
local ref1 = refOf(key1.item.metadata)
check(ref1 and keyItemsDb[ref1] and keyItemsDb[ref1].custody == 'player' and keyItemsDb[ref1].holder == 'CID001',
  'custody: the new key is recorded in the owner\'s pocket')
check(oxHooks.swapItems and oxHooks.swapItems.opts.itemFilter.vehicle_key == true, 'ox_inventory swapItems hook watches the key items')
-- the owner puts the key in the glovebox (ox reports the move)
oxHooks.swapItems.fn({ action = 'move', fromInventory = 1, fromType = 'player', toInventory = 'gloveABC123', toType = 'glovebox',
  fromSlot = { name = 'vehicle_key', metadata = key1.item.metadata, slot = key1.slot }, toSlot = 3 })
inv[1][key1.slot] = nil
advance(200)
check(keyItemsDb[ref1].custody == 'stash' and keyItemsDb[ref1].holder == 'glovebox:ABC123' and keyItemsDb[ref1].slot == 3,
  'custody: the move into the glovebox is recorded')
check(retrieve(1, carNet, 'ABC123') ~= false and #itemsOf(1, 'vehicle_key') == 0 and notified(1, 'glovebox'),
  'flexible: a key stored in the vehicle is reused (no new copy)')
-- the key comes back to the pocket
ox.AddItem(1, 'vehicle_key', 1, key1.item.metadata)
oxHooks.swapItems.fn({ action = 'move', fromInventory = 'gloveABC123', fromType = 'glovebox', toInventory = 1, toType = 'player',
  fromSlot = { name = 'vehicle_key', metadata = key1.item.metadata, slot = 3 }, toSlot = 1 })
advance(200)
check(keyItemsDb[ref1].custody == 'player' and keyItemsDb[ref1].holder == 'CID001', 'custody: back in the pocket')
res = cb('nz:carlock:share', 1, { plate = 'ABC123', target = 2 })
local copy2 = itemsOf(2, 'vehicle_key')[1]
check(res.ok and res.data.how == 'copy' and #itemsOf(1, 'vehicle_key') == 1 and copy2 ~= nil
  and copy2.item.metadata.id ~= key1.item.metadata.id and hasKey(2, 'ABC123'), 'flexible share: a copy for them, you keep yours')
check(copy2 and keyItemsDb[refOf(copy2.item.metadata)].holder == 'CID002' and keyItemsDb[refOf(copy2.item.metadata)].createdBy == 'CID001',
  'custody: the copy is recorded with its maker')
settingsSave({ ['keys.maxCopies'] = 2 })
res = cb('nz:carlock:share', 1, { plate = 'ABC123', target = 3 })
check(not res.ok and res.error:find('already has 2 keys', 1, true) and #itemsOf(3, 'vehicle_key') == 0, 'sharing.maxKeys caps the copies')
settingsSave(nil, { 'keys.maxCopies' })

---------------------------------------------------------------------------------------
-- 3. Limited: a fixed set, sharing hands yours over, no free copies
---------------------------------------------------------------------------------------

check(settingsSave({ ['keys.mode'] = 'limited', ['keys.limitedKeys'] = 2 }) and CarLock.keyMode() == 'limited', 'limited mode set live')
local _, limNet = fresh('LIM111', 'sultan', 'CID001', vec3(3, 1, 0))
local function limKeys(src)
  local n = 0
  for _, e in ipairs(itemsOf(src, 'vehicle_key')) do if e.item.metadata.plate == 'LIM111' then n = n + 1 end end
  return n
end
check(retrieve(1, limNet, 'LIM111') == true and limKeys(1) == 2 and run(CarLock.liveKeyCount, 'LIM111') == 2,
  'limited: the starting set (2 keys) on the first retrieval')
res = cb('nz:carlock:share', 1, { plate = 'LIM111', target = 2 })
check(res.ok and res.data.how == 'handover' and limKeys(1) == 1 and limKeys(2) == 1 and run(CarLock.liveKeyCount, 'LIM111') == 2,
  'limited share: your key is handed over (no new copy)')
cb('nz:carlock:share', 1, { plate = 'LIM111', target = 2 })
check(limKeys(1) == 0 and limKeys(2) == 2, 'both keys are with the other player now')
notifications = {}
check(retrieve(1, limNet, 'LIM111') == false and limKeys(1) == 0 and notified(1, 'somewhere else'),
  'limited: no free copy on retrieval while copies exist somewhere')
-- both copies are lost (admin delete takes them out of the pocket and marks them lost)
local p2 = cb('nz:carlock:admin:player', 3, { identifier = 'CID002' })
for _, row in ipairs(p2.ok and p2.data.keys or {}) do
  if row.plate == 'LIM111' and row.id:match('^item:') then cb('nz:carlock:admin:delete', 3, { identifier = 'CID002', id = row.id }) end
end
check(limKeys(2) == 0 and run(CarLock.liveKeyCount, 'LIM111') == 0, 'admin delete: out of the pocket, marked lost')
check(retrieve(1, limNet, 'LIM111') == true and limKeys(1) == 2, 'limited: a new set only when no copy is left anywhere')
settingsSave(nil, { 'keys.mode', 'keys.limitedKeys' })
check(CarLock.keyMode() == 'flexible', 'reset to flexible')

---------------------------------------------------------------------------------------
-- 4. Virtual: access, optional time limit
---------------------------------------------------------------------------------------

settingsSave({ ['keys.mode'] = 'virtual' })
check(run(CarLock.mode) == 'virtual', 'virtual mode set live')
rows.FOB777.version = rows.FOB777.version or 0
res = cb('nz:carlock:share', 1, { plate = 'FOB777', target = 2 })
local has, kind = hasKey(2, 'FOB777')
check(res.ok and res.data.how == 'virtual' and has and kind == 'virtual' and hasKey(1, 'FOB777'), 'virtual share: access for them, you keep yours')
settingsSave({ ['keys.shareHours'] = 2 })
res = cb('nz:carlock:share', 1, { plate = 'LIM111', target = 2 })
local t = CarLock.tempKeyOf(2, 'LIM111')
check(res.ok and res.data.how == 'temp' and t and t.reason == 'share' and CarLock.isServiceKey('share'),
  'sharing.hours: a temporary key of that length (a real key: service reason)')
CarLock.revokeTemp(2, 'LIM111')
run(CarLock.revokeVirtual, nil, 'CID002', 'FOB777')
settingsSave(nil, { 'keys.mode', 'keys.shareHours' })

---------------------------------------------------------------------------------------
-- 5. Per-player settings
---------------------------------------------------------------------------------------

res = cb('nz:carlock:playerSettings', 1, {})
check(res.ok and res.data.settings.keylessDistance == 10.0 and res.data.limits.keylessMin == 3.0 and res.data.limits.keylessMax == 30.0
  and res.data.server.keyless == true, 'player settings: defaults and limits')
res = cb('nz:carlock:savePlayerSettings', 1, { settings = { keylessDistance = 99, units = 'banana', engineOnEnter = true } })
check(res.ok and res.data.settings.keylessDistance == 30.0 and res.data.settings.units == 'metric' and res.data.settings.engineOnEnter == true
  and playersDb.CID001 and playersDb.CID001.engineOnEnter == true, 'saved: distance clamped, bad values ignored, stored per character')
check(lastClient('nz:client:carlock:settings', 1) ~= nil, 'the saved settings are pushed to the player')
res = cb('nz:carlock:savePlayerSettings', 1, { settings = { keylessDistance = 10 } })
check(res.ok and res.data.settings.engineOnEnter == true and res.data.settings.keylessDistance == 10.0, 'partial saves merge')
res = cb('nz:carlock:savePlayerSettings', 4, { settings = { hints = false } })
check(not res.ok, 'no character: nothing saved')

---------------------------------------------------------------------------------------
-- 6. Keyless entry and the server auto-lock (fob keys)
---------------------------------------------------------------------------------------

Config.CarLock.profileByModel = { zentorno = 'highend' }
CarLock.resetProfiles()
local fobCar, fobNet = fresh('FOB777', 'zentorno', 'CID001', vec3(2, 2, 0))
check(retrieve(1, fobNet, 'FOB777') == true and #itemsOf(1, 'vehicle_fob') == 1, 'high-end vehicle: a fob item')
CarLock.setLocked(fobCar, true)
res = cb('nz:carlock:keyless', 2, { netId = fobNet })
check(not res.ok and CarLock.isLocked(fobCar), 'keyless: no fob, no unlock')
res = cb('nz:carlock:keyless', 1, { netId = fobNet })
check(res.ok and res.data.locked == false and not CarLock.isLocked(fobCar) and lastClient('nz:client:carlock:fx') ~= nil,
  'keyless: the fob on you unlocks it (server check, lock feedback)')
CarLock.setLocked(car, true)
res = cb('nz:carlock:keyless', 1, { netId = carNet })
check(not res.ok and CarLock.isLocked(car), 'keyless: a plain key does not count')
CarLock.setLocked(car, false)
cb('nz:carlock:savePlayerSettings', 1, { settings = { keylessUnlock = false } })
CarLock.setLocked(fobCar, true)
res = cb('nz:carlock:keyless', 1, { netId = fobNet })
check(not res.ok and CarLock.isLocked(fobCar), 'keyless: off in the player settings')
cb('nz:carlock:savePlayerSettings', 1, { settings = { keylessUnlock = true } })
playerPos[1] = vec3(30, 0, 0)
res = cb('nz:carlock:keyless', 1, { netId = fobNet })
check(not res.ok, 'keyless: the server ped must be at the vehicle')
playerPos[1] = vec3(0, 0, 0)
CarLock.setLocked(fobCar, false)
-- auto-lock: sit in, get out, walk away
seat(1, fobCar)
advance(1500)
seat(1, nil)
playerPos[1] = vec3(6, 2, 0)
advance(2500)
check(not CarLock.isLocked(fobCar), 'auto-lock: still open within the player\'s distance (10 m)')
playerPos[1] = vec3(20, 2, 0)
advance(2500)
check(CarLock.isLocked(fobCar) and notified(1, 'locked behind you'), 'auto-lock: the server locks it once you are farther away')
playerPos[1] = vec3(0, 0, 0)
CarLock.setLocked(fobCar, false)
seat(1, fobCar)
advance(1500)
seat(1, nil)
seat(2, fobCar)
playerPos[1] = vec3(25, 2, 0)
advance(2500)
check(not CarLock.isLocked(fobCar), 'auto-lock: never with somebody inside')
seat(2, nil)
playerPos[1] = vec3(0, 0, 0)
advance(2500)
-- parked and walked into an interior (another routing bucket) right away: locked, not just forgotten
seat(1, fobCar)
advance(1500)
seat(1, nil)
local bucketOf = GetPlayerRoutingBucket
GetPlayerRoutingBucket = function(s) return tostring(s) == '1' and 7 or 0 end
advance(2500)
GetPlayerRoutingBucket = bucketOf
check(CarLock.isLocked(fobCar), 'auto-lock: entering an interior / instance bucket locks it')
CarLock.setLocked(fobCar, false)

---------------------------------------------------------------------------------------
-- 7. Remote actions (fob)
---------------------------------------------------------------------------------------

res = cb('nz:carlock:remote', 1, { netId = fobNet, action = 'windows', on = true })
local remote = lastClient('nz:client:carlock:remote')
check(res.ok and remote and remote.target == 1 and remote.payload.action == 'windows' and remote.payload.netId == fobNet,
  'remote windows: sent to the vehicle owner\'s client')
res = cb('nz:carlock:remote', 2, { netId = fobNet, action = 'engine' })
check(not res.ok, 'remote start needs the fob')
res = cb('nz:carlock:remote', 1, { netId = carNet, action = 'engine' })
check(not res.ok, 'remote start: a plain key is not a fob')

---------------------------------------------------------------------------------------
-- 8. Immobilisers and Ghost PINs
---------------------------------------------------------------------------------------

local imm, immNet = fresh('IMM111', 'sultan', 'CID001', vec3(2, -2, 0))
retrieve(1, immNet, 'IMM111')
oxDefined.immobiliser, oxDefined.ghost_immobiliser = true, true
ox.AddItem(1, 'immobiliser', 1, {})
local immSlot = itemsOf(1, 'immobiliser')[1].slot
seat(2, imm)
check(run(CarLock.useImmobiliserItem, 2, 'immobiliser', nil) == false, 'only the owner fits an immobiliser')
seat(2, nil)
seat(1, imm)
check(run(CarLock.useImmobiliserItem, 1, 'immobiliser', immSlot) == true and securityDb.IMM111.immobiliser == 'standard'
  and #itemsOf(1, 'immobiliser') == 0, 'immobiliser item: installed in your vehicle, consumed')
seat(1, nil)
seat(2, imm)
weaponOf = weaponOf or {}
res = cb('nz:carlock:hotwire', 2, { step = 'start', netId = immNet })
check(not res.ok and res.error == 'An immobiliser stops you from hotwiring this vehicle', 'standard immobiliser: no hotwiring')
seat(2, nil)
ox.AddItem(1, 'ghost_immobiliser', 1, {})
seat(1, imm)
check(run(CarLock.useImmobiliserItem, 1, 'ghost_immobiliser', itemsOf(1, 'ghost_immobiliser')[1].slot) == true
  and securityDb.IMM111.immobiliser == 'ghost' and lastClient('nz:client:carlock:pinSetup', 1) ~= nil,
  'ghost item: upgraded, the owner is asked to set a PIN')
res = cb('nz:carlock:engine', 1, { netId = immNet, on = true, class = 0 })
check(res.ok and res.data.on == true, 'a Ghost without a PIN acts like a standard immobiliser')
res = cb('nz:carlock:setPin', 1, { plate = 'IMM111', pin = '12a4' })
check(not res.ok, 'PIN: four digits')
res = cb('nz:carlock:setPin', 2, { plate = 'IMM111', pin = '1234' })
check(not res.ok, 'PIN: owner only')
res = cb('nz:carlock:setPin', 1, { plate = 'IMM111', pin = '1234' })
check(res.ok and res.data.level == 'ghost' and res.data.pinSet and res.data.remoteStart == false and securityDb.IMM111.pinHash ~= '1234'
  and #securityDb.IMM111.pinHash == 64, 'PIN set (stored as an HMAC, never the digits)')
res = cb('nz:carlock:engine', 1, { netId = immNet, on = true, class = 0 })
check(res.ok and res.data.on == false and res.data.pin and res.data.pin.required, 'Ghost: the engine waits for the PIN, even with the keys')
res = cb('nz:carlock:hasKey', 1, { netId = immNet, class = 0 })
check(res.ok and res.data.has and res.data.ignition == false and res.data.pin and res.data.pin.plate == 'IMM111', 'hasKey tells the driver to ask for the PIN')
res = cb('nz:carlock:pin', 1, { netId = immNet, pin = '0000' })
check(res.ok and res.data.success == false and res.data.attemptsLeft == 2, 'wrong PIN: attempts left')
cb('nz:carlock:pin', 1, { netId = immNet, pin = '1111' })
res = cb('nz:carlock:pin', 1, { netId = immNet, pin = '2222' })
check(res.ok and res.data.success == false and res.data.alarm == true and res.data.cooldown == 120 and type(stateOf(imm).nzAlarm) == 'table',
  'third wrong PIN: alarm + cooldown')
res = cb('nz:carlock:pin', 1, { netId = immNet, pin = '1234' })
check(res.ok and res.data.success == false and (res.data.cooldown or 0) > 0, 'during the cooldown even the right PIN waits')
advance(121000)
res = cb('nz:carlock:pin', 1, { netId = immNet, pin = '1234' })
check(res.ok and res.data.success == true, 'right PIN after the cooldown')
res = cb('nz:carlock:engine', 1, { netId = immNet, on = true, class = 0 })
check(res.ok and res.data.on == true, 'engine starts once the PIN was entered')
local info = run(CarLock.immobiliserInfo, 1, 'IMM111')
check(info.level == 'ghost' and info.pinSet == true and info.pinRequired == false,
  'immobiliserInfo: the PIN is no longer required once entered')
check(run(CarLock.immobiliserInfo, nil, 'IMM111').pinRequired == true, 'immobiliserInfo without a player: a Ghost with a PIN needs it')
seat(1, nil)
seat(2, imm)
cb('nz:carlock:pin', 2, { netId = immNet, pin = '1234' })
res = cb('nz:carlock:engine', 2, { netId = immNet, on = true, class = 0 })
check(not res.ok, 'the PIN alone is no key')
seat(2, nil)
res = cb('nz:carlock:setPin', 1, { plate = 'IMM111', pin = '5678' })
check(not res.ok and res.error == 'The current PIN is wrong', 'changing the PIN needs the old one')
res = cb('nz:carlock:setPin', 1, { plate = 'IMM111', pin = '5678', oldPin = '1234' })
check(res.ok, 'PIN changed with the old one')
run(CarLock.setImmobiliser, 'IMM111', 'standard', nil)
check(securityDb.IMM111.immobiliser == 'standard' and securityDb.IMM111.pinHash == nil
  and run(CarLock.immobiliserInfo, nil, 'IMM111').pinSet == false, 'ghost -> standard clears the PIN')
run(CarLock.setImmobiliser, 'IMM111', 'ghost', nil)
check(run(CarLock.immobiliserInfo, nil, 'IMM111').pinSet == false, 'back to ghost: the old PIN does not come back')
cb('nz:carlock:setPin', 1, { plate = 'IMM111', pin = '5678' })
run(CarLock.setImmobiliser, 'FOB777', 'ghost', nil)
res = cb('nz:carlock:remote', 1, { netId = fobNet, action = 'engine' })
check(not res.ok and res.error == 'Remote start is disabled by the immobiliser', 'Ghost: no remote start')
run(CarLock.setImmobiliser, 'FOB777', 'none', nil)
-- sale: the new owner does not know the PIN
rows.IMM111.owner = 'CID002'
CarLock.invalidate('IMM111')
run(CarLock.rekey, 'IMM111', 'CID002')
check(securityDb.IMM111.immobiliser == 'ghost' and securityDb.IMM111.pinHash == nil, 'owner change: the PIN is cleared, the immobiliser stays')
local level, pinSet = run(exported.GetImmobiliser, 'IMM111')
check(level == 'ghost' and pinSet == false, 'GetImmobiliser export')

---------------------------------------------------------------------------------------
-- 9. Keys on the ground: drop, inspect / keep / return, toss, throw + catch / miss, expiry
---------------------------------------------------------------------------------------

local fobItem = itemsOf(1, 'vehicle_fob')[1]
local fobRef = refOf(fobItem.item.metadata)
res = cb('nz:carlock:ground:drop', 1, { slot = fobItem.slot })
local dropId = res.ok and res.data.id or nil
local added = lastClient('nz:client:carlock:ground')
check(dropId and #itemsOf(1, 'vehicle_fob') == 0 and keyItemsDb[fobRef].custody == 'ground' and keyItemsDb[fobRef].holder == 'ground:' .. dropId,
  'drop: the item leaves the pocket, custody = ground')
check(added and added.payload.add and added.payload.add.id == dropId and added.payload.add.keyKind == 'fob' and added.payload.add.plate == nil,
  'drop: clients get the marker (no plate in the broadcast)')
local prop = 0
for _ in pairs(objects) do prop = prop + 1 end
check(prop == 1, 'drop: the server spawned the prop')
res = cb('nz:carlock:ground:list', 2, {})
check(res.ok and #res.data == 1 and res.data[1].id == dropId, 'ground list for a player in the same bucket')
check(not hasKey(1, 'FOB777') or select(2, hasKey(1, 'FOB777')) ~= 'item', 'a dropped key no longer opens anything for you')
res = cb('nz:carlock:ground:inspect', 2, { id = dropId })
check(res.ok and res.data.plate == 'FOB777' and res.data.keyKind == 'fob' and res.data.model == 'zentorno', 'inspect: fob, vehicle, plate')
res = cb('nz:carlock:ground:pickup', 3, { id = dropId })
check(not res.ok and res.error == 'Someone else is looking at this key', 'an inspected key is held for the inspector')
cb('nz:carlock:ground:release', 2, { id = dropId })
playerPos[3] = vec3(30, 0, 0)
res = cb('nz:carlock:ground:pickup', 3, { id = dropId })
check(not res.ok and res.error == 'You are too far away', 'pick-up range from the server ped')
playerPos[3] = vec3(2, 0, 0)
res = cb('nz:carlock:ground:pickup', 2, { id = dropId })
check(res.ok and #itemsOf(2, 'vehicle_fob') == 1 and keyItemsDb[fobRef].custody == 'player' and keyItemsDb[fobRef].holder == 'CID002'
  and next(objects) == nil and select(2, hasKey(2, 'FOB777')) == 'item', 'keep: anyone can pick it up; custody follows; the prop is gone')
-- toss out of the window
local fob2 = itemsOf(2, 'vehicle_fob')[1]
playerPos[2] = vec3(2, 2, 0)
seat(2, fobCar)
res = cb('nz:carlock:ground:drop', 2, { slot = fob2.slot, toss = true })
local tossed = res.ok and CarLock.groundKeys('FOB777')[1] or nil
check(tossed and math.abs(tossed.coords.x - 0.4) < 0.01 and math.abs(tossed.coords.y - 2.3) < 0.01,
  'toss: lands beside the driver window (server position: vehicle left side)')
seat(2, nil)
res = cb('nz:carlock:ground:pickup', 2, { id = tossed and tossed.id })
check(res.ok and #itemsOf(2, 'vehicle_fob') == 1, 'picked up again')
-- throw and catch
playerPos[2] = vec3(1, 0, 0)
fob2 = itemsOf(2, 'vehicle_fob')[1]
res = cb('nz:carlock:ground:throw', 2, { slot = fob2.slot, target = 1 })
local catchEv = lastClient('nz:client:carlock:catch', 1)
check(res.ok and catchEv and catchEv.payload.id == res.data.id and #itemsOf(2, 'vehicle_fob') == 0, 'throw: the target is told to catch it')
local caught = cb('nz:carlock:ground:catch', 1, { id = res.data.id })
check(caught.ok and #itemsOf(1, 'vehicle_fob') == 1 and keyItemsDb[fobRef].holder == 'CID001', 'catch within the window: in your pocket')
res = cb('nz:carlock:ground:catch', 1, { id = res.data.id })
check(not res.ok, 'a key is caught once')
-- throw and miss
local fob1 = itemsOf(1, 'vehicle_fob')[1]
res = cb('nz:carlock:ground:throw', 1, { slot = fob1.slot, target = 2 })
advance(3000)
local missed = CarLock.groundKeys('FOB777')[1]
check(res.ok and missed and missed.kind == 'item' and #itemsOf(2, 'vehicle_fob') == 0 and #itemsOf(1, 'vehicle_fob') == 0,
  'missed: the key lands on the ground at the catcher')
res = cb('nz:carlock:ground:catch', 2, { id = res.data.id })
check(not res.ok and res.error == 'Too late', 'too late to catch it')
playerPos[3] = vec3(30, 0, 0)
res = cb('nz:carlock:ground:throw', 2, { slot = 1, target = 3 })
check(not res.ok, 'throw range from the server peds')
playerPos[3] = vec3(2, 0, 0)
-- the missed key is a real record at a real vector3 (CfxLua type 'vector3')
check(missed and type(vector3(1, 2, 3)) == 'vector3' and objects[next(objects)] ~= nil, 'missed key: a ground record with a prop')
-- the prop rolls: the pick-up range follows the prop, the tick moves the record
local propHandle = next(objects)
objects[propHandle].coords = vec3(4.5, 0, -0.6)
res = cb('nz:carlock:ground:inspect', 3, { id = missed and missed.id })
check(res.ok, 'pick-up range: measured to the prop where it settled')
cb('nz:carlock:ground:release', 3, { id = missed and missed.id })
advance(16000)
check(math.abs(CarLock.groundKeys('FOB777')[1].coords.x - 4.5) < 0.01, 'ground tick: the record follows the settled prop')
-- persistence switched on / off in game
check(settingsSave({ ['ground.persist'] = true }) and groundDb[missed.id] ~= nil and groundDb[missed.id].x == 4.5,
  'persist on: the live ground keys are stored')
check(settingsSave({ ['ground.persist'] = false }) and next(groundDb) == nil, 'persist off: the stored rows are cleared')
settingsSave(nil, { 'ground.persist' })
res = cb('nz:carlock:ground:pickup', 1, { id = missed.id })
check(not res.ok and res.error == 'You are too far away', 'pick-up range: measured to the prop, not the spawn point')
playerPos[1] = vec3(4, 0, 0)
res = cb('nz:carlock:ground:pickup', 1, { id = missed.id })
playerPos[1] = vec3(0, 0, 0)
check(res.ok and #itemsOf(1, 'vehicle_fob') == 1, 'picked up by the thrower')
-- the catcher walked off before catching: it lands, never lost
fob1 = itemsOf(1, 'vehicle_fob')[1]
res = cb('nz:carlock:ground:throw', 1, { slot = fob1.slot, target = 2 })
playerPos[2] = vec3(15, 0, 0)
local miss2 = cb('nz:carlock:ground:catch', 2, { id = res.data.id })
local landed = CarLock.groundKeys('FOB777')[1]
check(not miss2.ok and landed and landed.kind == 'item' and keyItemsDb[fobRef].custody == 'ground',
  'catch out of range: the key lands on the ground')
playerPos[2] = vec3(1, 0, 0)
playerPos[1] = vec3(14, 0, 0)
cb('nz:carlock:ground:pickup', 1, { id = landed and landed.id })
playerPos[1] = vec3(0, 0, 0)
-- a full pocket: the catch fails, the key lands
fob1 = itemsOf(1, 'vehicle_fob')[1]
res = cb('nz:carlock:ground:throw', 1, { slot = fob1.slot, target = 2 })
ox.CanCarryItem = function() return false end
miss2 = cb('nz:carlock:ground:catch', 2, { id = res.data.id })
ox.CanCarryItem = function() return true end
landed = CarLock.groundKeys('FOB777')[1]
check(not miss2.ok and landed and keyItemsDb[fobRef].custody == 'ground' and #itemsOf(2, 'vehicle_fob') == 0,
  'catch with a full inventory: the key lands on the ground')
cb('nz:carlock:ground:pickup', 1, { id = landed and landed.id })
-- the ground key cannot be created: back to the thrower, never silently gone
fob1 = itemsOf(1, 'vehicle_fob')[1]
res = cb('nz:carlock:ground:throw', 1, { slot = fob1.slot, target = 2 })
local realCreate = CarLock.groundCreate
CarLock.groundCreate = function() return nil end
advance(3000)
CarLock.groundCreate = realCreate
check(#itemsOf(1, 'vehicle_fob') == 1 and keyItemsDb[fobRef].custody == 'player' and keyItemsDb[fobRef].holder == 'CID001',
  'landing fails: the key goes back to the thrower')
-- pick-up rollback: the inventory refuses the item and the ground key cannot be re-made
res = cb('nz:carlock:ground:drop', 1, { slot = itemsOf(1, 'vehicle_fob')[1].slot })
local dropped2 = res.ok and res.data.id
local addItem = ox.AddItem
local refusals = 1
ox.AddItem = function(...) if refusals > 0 then refusals = refusals - 1 return false end return addItem(...) end
CarLock.groundCreate = function() return nil end
res = cb('nz:carlock:ground:pickup', 1, { id = dropped2 })
CarLock.groundCreate, ox.AddItem = realCreate, addItem
check(res.ok and #itemsOf(1, 'vehicle_fob') == 1 and keyItemsDb[fobRef].custody == 'player',
  'pick-up rollback fails: the key is forced into the pocket, not lost')
-- back on the ground for the expiry case below
res = cb('nz:carlock:ground:drop', 1, { slot = itemsOf(1, 'vehicle_fob')[1].slot })
missed = res.ok and { id = res.data.id } or missed
-- expiry
check(settingsSave({ ['ground.removeAfter'] = 1 }), 'ground removeAfter set to a minute')
cb('nz:carlock:ground:pickup', 1, { id = missed and missed.id })
fob1 = itemsOf(1, 'vehicle_fob')[1]
res = cb('nz:carlock:ground:drop', 1, { slot = fob1 and fob1.slot })
advance(76000)
check(res.ok and #CarLock.groundKeys('FOB777') == 0 and keyItemsDb[fobRef].custody == 'lost'
  and lastClient('nz:client:carlock:ground').payload.remove == res.data.id, 'expired: removed for everyone, custody lost')
settingsSave(nil, { 'ground.removeAfter' })
check(settingsSave({ ['ground.enabled'] = false }), 'ground keys off')
ox.AddItem(1, 'vehicle_fob', 1, fob1.item.metadata)
res = cb('nz:carlock:ground:drop', 1, { slot = itemsOf(1, 'vehicle_fob')[1].slot })
check(not res.ok and #itemsOf(1, 'vehicle_fob') == 1, 'ground keys off: nothing can be dropped')
settingsSave(nil, { 'ground.enabled' })
res = cb('nz:carlock:inspect', 1, { slot = itemsOf(1, 'vehicle_fob')[1].slot })
check(res.ok and res.data.plate == 'FOB777' and res.data.keyKind == 'fob' and res.data.valid == true, 'inspect a carried key')

---------------------------------------------------------------------------------------
-- 10. Admin key manager
---------------------------------------------------------------------------------------

res = cb('nz:carlock:admin:search', 1, { query = 'ABC1' })
check(not res.ok, 'key manager: admins only')
res = cb('nz:carlock:admin:search', 3, { query = 'ABC1' })
local found = false
for _, r in ipairs(res.ok and res.data.rows or {}) do
  if r.identifier == 'CID001' and r.online and r.serverId == 1 and r.matchedPlates[1] == 'ABC123' then found = true end
end
check(found, 'search by plate: the owner, online, with the plate')
res = cb('nz:carlock:admin:search', 3, { query = 'CID002' })
check(res.ok and res.data.rows[1] and res.data.rows[1].identifier == 'CID002', 'search by citizen id')
res = cb('nz:carlock:admin:player', 3, { identifier = 'CID001' })
local ownerRow, itemRow = nil, nil
for _, r in ipairs(res.ok and res.data.keys or {}) do
  if r.id == 'owner:ABC123' then ownerRow = r end
  if r.plate == 'ABC123' and r.type == 'key' and r.custody.kind == 'inventory' then itemRow = r end
end
check(ownerRow and ownerRow.deletable == false and ownerRow.spawned == true and type(ownerRow.distance) == 'number',
  'player keys: owned vehicles, spawned + distance')
check(itemRow and itemRow.current == true and itemRow.custody.slot ~= nil, 'player keys: key items with their pocket slot')
check(res.ok and res.data.totals.vehicles >= 3 and res.data.totals.keys == #res.data.keys, 'totals')
res = cb('nz:carlock:admin:give', 3, { identifier = 'CID009', plate = 'ABC123', type = 'temp', hours = 2 })
check(res.ok and CarLock.tempKeysOfHolder('CID009').ABC123 ~= nil, 'give: a temporary key to an offline character')
res = cb('nz:carlock:admin:give', 3, { identifier = 'CID009', plate = 'ABC123', type = 'item' })
check(not res.ok, 'give: key items need the player online')
res = cb('nz:carlock:admin:delete', 3, { identifier = 'CID009', id = 'temp:ABC123' })
check(res.ok and CarLock.tempKeysOfHolder('CID009').ABC123 == nil, 'delete a temporary key')
res = cb('nz:carlock:admin:give', 3, { identifier = 'CID002', plate = 'IMM111', type = 'virtual' })
check(res.ok and nzKeys.IMM111 and nzKeys.IMM111.CID002, 'give: a virtual key')
res = cb('nz:carlock:admin:delete', 3, { identifier = 'CID002', id = 'owner:IMM111' })
check(not res.ok, 'ownership is not a deletable key')
res = cb('nz:carlock:admin:plate', 3, { plate = 'ABC123' })
check(res.ok and res.data.owner == 'CID001' and #res.data.custody >= 2 and res.data.immobiliser.level == 'none' and res.data.spawned,
  'plate view: custody of every key, immobiliser, spawned')
res = cb('nz:carlock:admin:track', 3, { plate = 'FOB777' })
check(res.ok and res.data.spawned and res.data.coords and res.data.coords.x == 2, 'track a plate')
check(commands.vehiclekeysadmin ~= nil, '/vehiclekeysadmin registered')
commands.vehiclekeysadmin(1, {})
check(lastClient('nz:client:carlock:keyAdmin', 1) == nil, '/vehiclekeysadmin: not for players')
commands.vehiclekeysadmin(3, {})
check(lastClient('nz:client:carlock:keyAdmin', 3) ~= nil, '/vehiclekeysadmin opens the key manager for admins')

---------------------------------------------------------------------------------------
-- 11. Resource restart keeps keys on the ground (same server session)
---------------------------------------------------------------------------------------

res = cb('nz:carlock:ground:drop', 1, { slot = itemsOf(1, 'vehicle_fob')[1].slot })
TriggerEvent('onResourceStop', 'nayzeee-garages')
local snap = kvp['nz:carlock:ground'] and json.decode(kvp['nz:carlock:ground']) or nil
check(res.ok and snap and #snap.keys == 1 and snap.keys[1].id == res.data.id and next(objects) == nil,
  'resource stop: props removed, ground keys kept in the session snapshot')

---------------------------------------------------------------------------------------
-- Report
---------------------------------------------------------------------------------------

for _, line in ipairs(printed.error) do failures[#failures + 1] = 'lib.print.error: ' .. line end
if #failures > 0 then
  for _, f in ipairs(failures) do print('FAIL ' .. f) end
  print(('%d of %d checks failed'):format(#failures, checks))
  os.exit(1)
end
print(('keys2 OK (%d checks)'):format(checks))
