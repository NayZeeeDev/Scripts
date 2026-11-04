--[[
  Headless test for the built-in car lock core (no FiveM needed).

  Loads the real shared files, bridge/server/{inventory,keys,listeners}.lua and
  server/carlock/{keys,main,exports}.lua in a stubbed server runtime with an in-memory vehicle
  database, a fake ox_inventory (metadata) and a fake world (players, vehicles, seats,
  population types, state bags, KVP), then traces the flows end to end:

    garage retrieve -> key item (physical) / temporary key (virtual) -> lock / unlock ->
    engine; forged / edited / copied key items; key item use; rekey; hand-over (physical) and
    shared virtual keys (share / holders / revoke); spawner vehicles; admin /givekey; other
    scripts' events and exports (qb-vehiclekeys, qbx_vehiclekeys, jaksam) incl. ambient /
    owned / far vehicles; a key script starting later (server boot: hand-over; players
    online: warning); keys of never key-checked vehicles; keys through a share / fleet access
    ending with it; qb-inventory ItemUsed hook for shared items; resource restart (temporary
    keys, plates, lock state) vs server restart.

  Usage (from the resource root):  lua5.4 tools/smoke/carlock.lua
]]

local failures, checks = {}, 0
local function check(cond, label)
  checks = checks + 1
  if not cond then failures[#failures + 1] = label end
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
local function vec3(x, y, z) return setmetatable({ x = x or 0.0, y = y or 0.0, z = z or 0.0 }, vmeta) end
vector3 = vec3
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

function DoesEntityExist(h) return entities[h] ~= nil or (h > 1000 and h < 2000 and online[h - 1000] ~= nil) end
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
function GetVehicleType() return 'automobile' end
function GetEntityPopulationType(h) return entities[h] and entities[h].pop or 0 end
function GetEntityCoords(h)
  if entities[h] then return entities[h].coords end
  local src = h - 1000
  return playerPos[src] or vec3(0, 0, 0)
end
function SetVehicleDoorsLocked(h, s) if entities[h] then entities[h].lock = s end end
function GetVehicleDoorLockStatus(h) return entities[h] and entities[h].lock or 0 end
function DeleteEntity(h)
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

local function loadServer()
  load_('bridge/server/inventory.lua')
  load_('bridge/server/keys.lua')
  load_('bridge/server/listeners.lua')
  load_('server/carlock/keys.lua')
  load_('server/carlock/main.lua')
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

---------------------------------------------------------------------------------------
-- 1. Physical mode: garage retrieve -> key item -> lock / unlock -> engine
---------------------------------------------------------------------------------------

check(run(CarLock.mode) == 'physical', 'auto mode with ox_inventory is physical')
check(NZ.Inventory.name() == 'ox_inventory', 'ox_inventory detected')

local car, carNet = spawnVehicle('ABC123', 'sultan', vec3(3, 0, 0), 7)
entities[car].lock = 2
NZ.Vehicles.out.ABC123 = { src = 1, identifier = 'CID001', entity = car, netId = carNet, spawner = false }
check(run(NZ.KeysServer.give, 1, carNet, 'ABC123') == true, 'garage hand-out succeeded')
local keys1 = itemsOf(1, 'vehicle_key')
check(#keys1 == 1, 'physical: one key item given on retrieve')
local md = keys1[1] and keys1[1].item.metadata or {}
check(md.plate == 'ABC123' and md.kind == 'key' and type(md.sig) == 'string' and md.display == false,
  'key metadata: plate, kind, signature, display = false')
check(type(md.version) == 'number' and md.version > 0 and md.version == rows.ABC123.version and rows.ABC123.mark ~= nil,
  'first key of a row: random first version, owner recorded with it')
check(type(md.label) == 'string' and md.label:find('ABC123') ~= nil and type(md.description) == 'string', 'key metadata: label / description')
check(stateOf(car).nzLocked == false and entities[car].lock == 1, 'retrieved vehicle starts unlocked')
check(clientEventsFor('nz:client:carlock:keys', 1) >= 1, 'key change pushed to the player')
local has, kind = hasKey(1, 'ABC123')
check(has == true and kind == 'item', 'owner has the key through the item')

-- retrieving again with a valid key gives no second item
NZ.KeysServer.give(1, carNet, 'ABC123') -- deduplicated window
advance(11000)
run(NZ.KeysServer.give, 1, carNet, 'ABC123')
check(#itemsOf(1, 'vehicle_key') == 1, 'no second key item while a valid one is carried')

-- lock / unlock from 3 m
local res = cb('nz:carlock:toggleLock', 1, { netIds = { carNet } })
check(res.ok and res.data.locked == true and stateOf(car).nzLocked == true and entities[car].lock == 2, 'lock with the key item')
local fx = clientEvents[#clientEvents]
check(fx and fx.name == 'nz:client:carlock:fx' and fx.payload.locked == true and fx.payload.netId == carNet,
  'lock feedback sent to the players nearby (server event, not a client-writable bag)')
res = cb('nz:carlock:toggleLock', 1, { netIds = { carNet } })
check(res.ok and res.data.locked == false and entities[car].lock == 1, 'unlock with the key item')
res = cb('nz:carlock:toggleLock', 2, { netIds = { carNet } })
check(not res.ok and stateOf(car).nzLocked == false, 'a player without a key cannot lock')
playerPos[1] = vec3(20, 0, 0)
res = cb('nz:carlock:toggleLock', 1, { netIds = { carNet } })
check(not res.ok and res.error == 'The vehicle is too far away', 'key range is measured from the server ped')
playerPos[1] = vec3(0, 0, 0)

-- engine: driver seat + key
seat(1, car)
res = cb('nz:carlock:engine', 1, { netId = carNet, on = true, class = 0 })
check(res.ok and res.data.on == true and res.data.kind == 'item', 'engine starts for the key holder')
seat(1, nil)
seat(2, car)
res = cb('nz:carlock:engine', 2, { netId = carNet, on = true, class = 0 })
check(not res.ok, 'engine refused without a key')
res = cb('nz:carlock:engine', 2, { netId = carNet, on = true, class = 13 })
check(res.ok and res.data.kind == 'bypass', 'bypass class (13) starts without a key')
res = cb('nz:carlock:hasKey', 2, { netId = carNet, class = 0 })
check(res.ok and res.data.has == false and res.data.ignition == false and res.data.plate == 'ABC123', 'hasKey answer for a stranger')
seat(2, nil)
res = cb('nz:carlock:engine', 1, { netId = carNet, on = true })
check(not res.ok, 'engine needs the driver seat')

---------------------------------------------------------------------------------------
-- 2. Forged / edited / copied key items never open anything
---------------------------------------------------------------------------------------

ox.AddItem(2, 'vehicle_key', 1, { plate = 'ABC123', version = 0, kind = 'key', id = 'abcd1234', sig = string.rep('0', 24) })
check(not hasKey(2, 'ABC123'), 'forged signature refused')
local copy = oxCopy(md)
copy.plate = 'FOB777'
ox.AddItem(2, 'vehicle_key', 1, copy)
check(not hasKey(2, 'FOB777'), 'a signature copied onto another plate is refused')
ox.AddItem(2, 'vehicle_key', 1, { plate = 'ABC123' })
check(not hasKey(2, 'ABC123'), 'unsigned key refused by default')
Config.CarLock.trustUnsignedKeys = true
check(hasKey(2, 'ABC123'), 'unsigned key accepted with trustUnsignedKeys')
Config.CarLock.trustUnsignedKeys = false
inv[2] = {}

---------------------------------------------------------------------------------------
-- 3. Key item use (ox export path, consume = 0)
---------------------------------------------------------------------------------------

local slot = itemsOf(1, 'vehicle_key')[1].slot
check(type(exported.useNzItem) == 'function', 'useNzItem export registered')
local before = stateOf(car).nzLocked
exported.useNzItem('usingItem', { name = 'vehicle_key' }, { id = 1, items = { [slot] = ox.GetSlot(1, slot) } }, slot)
advance(200)
check(stateOf(car).nzLocked == not before, 'using the key item toggles the lock')
check(clientEventsFor('nz:client:carlock:used', 1) == 1, 'fob animation event sent')
TriggerEvent('ox_inventory:usedItem', 1, 'vehicle_key', slot, ox.GetSlot(1, slot).metadata)
advance(200)
check(stateOf(car).nzLocked == not before, 'ox usedItem event after the export is not handled twice')
check(#itemsOf(1, 'vehicle_key') == 1, 'the key item is not consumed')

---------------------------------------------------------------------------------------
-- 4. Change of locks: old key stops working, new key works
---------------------------------------------------------------------------------------

local oldVersion = rows.ABC123.version
local newVersion = run(exported.Rekey, 'ABC123')
check(newVersion == oldVersion + 1 and run(exported.GetKeyVersion, 'ABC123') == newVersion, 'rekey raises the version')
local okV, reason = CarLock.verifyKeyItem(itemsOf(1, 'vehicle_key')[1].item.metadata, 'ABC123')
check(not okV and reason == 'version', 'old key item is refused after the rekey')
check(not hasKey(1, 'ABC123'), 'old key no longer counts')
check(run(exported.GiveKeyItem, 1, 'ABC123') == true, 'GiveKeyItem export')
check(hasKey(1, 'ABC123'), 'new key item works')

---------------------------------------------------------------------------------------
-- 5. Physical hand-over (Keys app "share" in physical mode)
---------------------------------------------------------------------------------------

res = cb('nz:carlock:share', 1, { plate = 'ABC123', target = 2 })
check(res.ok, 'hand the key item to a nearby player')
check(hasKey(2, 'ABC123') and #itemsOf(2, 'vehicle_key') == 1, 'the receiver holds the valid key item')
playerPos[2] = vec3(30, 0, 0)
res = cb('nz:carlock:share', 2, { plate = 'ABC123', target = 1 })
check(not res.ok, 'hand-over refused when the players are apart')
playerPos[2] = vec3(1, 0, 0)

---------------------------------------------------------------------------------------
-- 6. Virtual mode: owner key, shared virtual keys, holders, revoke
---------------------------------------------------------------------------------------

Config.CarLock.keyMode = 'virtual'
check(run(CarLock.mode) == 'virtual', 'virtual mode')
has, kind = hasKey(1, 'FOB777')
check(has and kind == 'owner', 'virtual: the owner always has a key')
check(not hasKey(2, 'FOB777'), 'virtual: a stranger has no key')
res = cb('nz:carlock:share', 1, { plate = 'FOB777', target = 2 })
check(res.ok and nzKeys.FOB777 and nzKeys.FOB777.CID002 ~= nil, 'virtual key stored in nz_keys')
has, kind = hasKey(2, 'FOB777')
check(has and kind == 'virtual', 'the shared player has a virtual key')
res = cb('nz:carlock:holders', 1, { plate = 'FOB777' })
check(res.ok and #res.data == 1 and res.data[1].identifier == 'CID002' and res.data[1].kind == 'virtual', 'holders list')
res = cb('nz:carlock:holders', 2, { plate = 'FOB777' })
check(not res.ok, 'only the owner sees the holders')
res = cb('nz:carlock:share', 2, { plate = 'FOB777', target = 3 })
check(not res.ok, 'only the owner shares virtual keys')
local pushesBefore = clientEventsFor('nz:client:carlock:keys', 2)
res = cb('nz:carlock:revoke', 1, { plate = 'FOB777', identifier = 'CID002' })
check(res.ok and not hasKey(2, 'FOB777'), 'revoke removes the virtual key')
check(clientEventsFor('nz:client:carlock:keys', 2) > pushesBefore, 'revoke pushed to the holder')
res = cb('nz:carlock:keys', 1, {})
local plates = {}
for _, k in ipairs(res.ok and res.data.keys or {}) do plates[k.plate] = k.kind end
check(res.ok and res.data.mode == 'virtual' and plates.FOB777 == 'owner', 'keys list for the Keys app')

-- keys of a vehicle nobody key-checked yet (first key version not claimed: fresh install /
-- upgrade) survive its first key check
rows.NEW001 = { plate = 'NEW001', owner = 'CID001', model = 'sultan', hash = joaat_('sultan'), version = 0 }
res = cb('nz:carlock:share', 1, { plate = 'NEW001', target = 2 })
check(res.ok and rows.NEW001.mark ~= nil and nzKeys.NEW001 and nzKeys.NEW001.CID002 ~= nil,
  'share of a never keyed vehicle: the key version is claimed before the key is stored')
has, kind = hasKey(2, 'NEW001')
check(has and kind == 'virtual' and nzKeys.NEW001 and nzKeys.NEW001.CID002 ~= nil, 'the first key check keeps that shared key')
rows.NEW002 = { plate = 'NEW002', owner = 'CID001', model = 'sultan', hash = joaat_('sultan'), version = 0 }
check(run(exported.GiveKey, 3, 'NEW002') == true and rows.NEW002.mark ~= nil, 'GiveKey export on a never keyed vehicle claims its version')
has, kind = hasKey(3, 'NEW002')
check(has and kind == 'temp', 'the first key check keeps the temporary key of a non-owner')

-- virtual garage retrieve by a shared (non-owner) player: temporary key
shares.CID002 = { { plate = 'FOB777' } }
local fob, fobNet = spawnVehicle('FOB777', 'zentorno', vec3(4, 0, 0), 7)
NZ.Vehicles.out.FOB777 = { src = 2, identifier = 'CID002', entity = fob, netId = fobNet, spawner = false }
check(run(NZ.KeysServer.give, 2, fobNet, 'FOB777') == true, 'virtual hand-out for a shared player')
has, kind = hasKey(2, 'FOB777')
check(has and (kind == 'owner' or kind == 'temp'), 'shared player can drive it')
shares.CID002 = nil

-- spawner (job / rental) vehicle: temporary key for the player who took it out
local rental, rentalNet = spawnVehicle('RENT01', 'blista', vec3(2, 2, 0), 7)
NZ.Vehicles.out.RENT01 = { src = 2, identifier = 'CID002', entity = rental, netId = rentalNet, spawner = true }
run(NZ.KeysServer.give, 2, rentalNet, 'RENT01')
has, kind = hasKey(2, 'RENT01')
check(has and kind == 'temp', 'spawner vehicle: temporary key')
check(not hasKey(1, 'RENT01'), 'spawner key only for that player')

---------------------------------------------------------------------------------------
-- 7. Admin command /givekey
---------------------------------------------------------------------------------------

local npc = spawnVehicle('NPC0001', 'asea', vec3(2, 1, 0), 2)
seat(1, npc)
check(type(commands.givekey) == 'function', '/givekey registered')
run(commands.givekey, 1, {})
check(not hasKey(1, 'NPC0001'), '/givekey refused for a non-admin')
run(commands.givekey, 3, { '1' })
has, kind = hasKey(1, 'NPC0001')
check(has and kind == 'temp', '/givekey 1 by an admin: temporary key of the vehicle player 1 sits in')
check(logs[#logs] and logs[#logs].event == 'admin.giveKey', '/givekey logged')
seat(1, nil)
run(commands.givekey, 3, { '2' })
check(not hasKey(2, 'NPC0001'), '/givekey needs the target to sit in a vehicle')

---------------------------------------------------------------------------------------
-- 8. Other scripts: events and exports
---------------------------------------------------------------------------------------

Config.CarLock.keyMode = 'auto'
local ambient, ambientNet = spawnVehicle('AMB0001', 'asea', vec3(2, -1, 0), 2)
local mission, missionNet = spawnVehicle('JOB0001', 'taxi', vec3(2, -2, 0), 7)
local farMission, farNet = spawnVehicle('JOB0002', 'taxi', vec3(40, 0, 0), 7)
fireNet('qb-vehiclekeys:server:AcquireVehicleKeys', 2, ambientNet)
check(not hasKey(2, 'AMB0001'), 'client event: ambient NPC car refused (compatAmbient = false)')
fireNet('qb-vehiclekeys:server:AcquireVehicleKeys', 2, missionNet)
has, kind = hasKey(2, 'JOB0001')
check(has and kind == 'temp', 'client event: script-spawned vehicle nearby -> temporary key')
fireNet('qb-vehiclekeys:server:AcquireVehicleKeys', 2, farNet)
check(not hasKey(2, 'JOB0002'), 'client event: far vehicle refused')
fireNet('vehiclekeys:client:SetOwner', 2, 'ABC123') -- client name: not a server event here
fireNet('qb-vehiclekeys:server:AcquireVehicleKeys', 3, 'ABC123')
check(not hasKey(3, 'ABC123'), "client event: another player's owned car refused")
advance(2000) -- compat requests: a burst of 4, then one every 400 ms
fireNet('qb-vehiclekeys:server:RemoveVehicleKeys', 2, 'JOB0001')
check(not hasKey(2, 'JOB0001'), 'client event: remove own temporary key')
fireNet('vehicles_keys:selfGiveVehicleKeys', 2, 'JOB0001')
check(hasKey(2, 'JOB0001'), 'jaksam self give (plate) -> temporary key')

-- lock state from a client: needs a key and the range
local lockBefore = entities[farMission].lock
fireNet('qb-vehiclekeys:server:setVehLockState', 2, farNet, 2)
check(entities[farMission].lock == lockBefore, 'setVehLockState refused without a key')
fireNet('qb-vehiclekeys:server:setVehLockState', 2, missionNet, 2)
check(entities[mission].lock == 2, 'setVehLockState with a key in range')

-- export shims (server code is trusted)
local function shim(alias, name)
  local fn
  TriggerEvent(('__cfx_export_%s_%s'):format(alias, name), function(f) fn = f end)
  return fn
end
local qbGive = shim('qb-vehiclekeys', 'GiveKeys')
check(type(qbGive) == 'function', 'qb-vehiclekeys GiveKeys export shim')
check(qbGive and run(qbGive, 3, 'JOB0002') == true and hasKey(3, 'JOB0002'), 'qb GiveKeys(src, plate) -> key')
local qbHas = shim('qb-vehiclekeys', 'HasKeys')
check(qbHas and run(qbHas, 3, 'JOB0002') == true and run(qbHas, 3, 'NOPE') == false, 'qb HasKeys strict boolean')
local qbxGive = shim('qbx_vehiclekeys', 'GiveKeys')
check(qbxGive and run(qbxGive, 1, ambient) == true, 'qbx GiveKeys(src, entity) -> true when new')
check(qbxGive and run(qbxGive, 1, ambient) == nil, 'qbx GiveKeys -> nil when already held')
local qbxLock = shim('qbx_vehiclekeys', 'SetLockState')
run(qbxLock, ambient, 'lock')
check(stateOf(ambient).nzLocked == true and entities[ambient].lock == 2, 'qbx SetLockState')

-- a key script started later takes its names back
resourceStates['qb-vehiclekeys'] = 'started'
local removedBefore = removedHandlers
TriggerEvent('onResourceStart', 'qb-vehiclekeys')
check(removedHandlers > removedBefore and shim('qb-vehiclekeys', 'GiveKeys') == nil, 'export shims removed when qb-vehiclekeys starts')
fireNet('qb-vehiclekeys:server:AcquireVehicleKeys', 1, missionNet)
check(not hasKey(1, 'JOB0001'), 'events ignored while qb-vehiclekeys runs')
resourceStates['qb-vehiclekeys'] = nil
TriggerEvent('onResourceStop', 'qb-vehiclekeys')
advance(1500)
check(shim('qb-vehiclekeys', 'GiveKeys') ~= nil, 'export shims back after qb-vehiclekeys stopped')

-- our own exports
check(run(exported.GiveKey, 3, 'NPC0001') == true and hasKey(3, 'NPC0001'), 'GiveKey export')
check(run(exported.HasKey, 3, 'NPC0001') == true, 'HasKey export')
run(exported.RemoveKey, 3, 'NPC0001')
check(not hasKey(3, 'NPC0001'), 'RemoveKey export')
check(run(exported.SetVehicleLocked, ambientNet, false) == true and run(exported.IsVehicleLocked, ambientNet) == false, 'Set / IsVehicleLocked exports')
check(run(exported.HasKey, 3, nil) == false and run(exported.GiveKey, 3, {}) == false, 'exports tolerate bad arguments')

---------------------------------------------------------------------------------------
-- 9. Resource restart keeps temporary keys, plates and locks; a server restart does not
---------------------------------------------------------------------------------------

CarLock.setRealPlate(ambient, 'REAL001')
check(CarLock.realPlate(ambient) == 'REAL001', 'recorded real plate wins over the plate text')
check(hasKey(2, 'JOB0001'), 'temporary key before the restart')
TriggerEvent('onResourceStop', 'nayzeee-garages')
check(type(kvp['nz:carlock:session']) == 'string', 'session snapshot written on stop')
local savedKvp = kvp['nz:carlock:session']
handlers, callbacks = {}, {}
for k in pairs(bagHandlers) do bagHandlers[k] = nil end
loadServer()
advance(3000)
CarLock = NZ.CarLock
check(hasKey(2, 'JOB0001'), 'resource restart: temporary key kept')
check(CarLock.realPlate(ambient) == 'REAL001', 'resource restart: recorded plate kept')
check(stateOf(car).nzLocked ~= nil and CarLock.isLocked(mission) == true, 'resource restart: lock states stay on the entities')
check(hasKey(2, 'ABC123'), 'resource restart: key items still valid (same secret)')

kvp['nz:carlock:session'] = savedKvp
bootOffset = 3600 -- the game timer started again: a server restart
handlers, callbacks = {}, {}
for k in pairs(bagHandlers) do bagHandlers[k] = nil end
loadServer()
advance(3000)
check(not hasKey(2, 'JOB0001'), 'server restart: temporary keys dropped')

---------------------------------------------------------------------------------------
-- 10. Ownership changes retire the old keys (sale through the garage, other scripts)
---------------------------------------------------------------------------------------

CarLock = NZ.CarLock
Config.CarLock.keyMode = 'auto'
check(GlobalState.nzCarLockOther == false, 'server publishes "no other key resource" for the clients')

-- sale: the garage changes the owner and calls rekey(plate, buyer) (afterOwnerChange)
rows.SELL01 = { plate = 'SELL01', owner = 'CID001', model = 'sultan', hash = joaat_('sultan'), version = 0 }
check(run(exported.GiveKeyItem, 1, 'SELL01') == true, 'seller holds a key item')
local sellerKey = itemsOf(1, 'vehicle_key')
sellerKey = sellerKey[#sellerKey].item.metadata
check(sellerKey.plate == 'SELL01' and hasKey(1, 'SELL01'), 'seller key works before the sale')
nzKeys.SELL01 = { CID003 = 'CID001' }            -- a friend's persistent key
run(CarLock.grantTemp, 3, 'SELL01', 'garage')    -- and a temporary one
run(CarLock.grantTemp, 2, 'SELL01', 'garage')    -- the buyer test-drove it
rows.SELL01.owner = 'CID002'
local saleVersion = run(CarLock.rekey, 'SELL01', 'CID002')
local okSell, whySell = run(CarLock.verifyKeyItem, sellerKey, 'SELL01')
check(saleVersion and not okSell and whySell == 'version', 'after the sale the seller key item is refused (version)')
check(not hasKey(1, 'SELL01'), 'after the sale the seller has no key')
check(nzKeys.SELL01 == nil, "after the sale the friend's virtual key is gone")
check(not hasKey(3, 'SELL01'), "after the sale the friend's temporary key is gone")
has, kind = hasKey(2, 'SELL01')
check(has and kind == 'temp', "the buyer's temporary key is kept")

-- another script writes the owner column without telling us: noticed on the next check
rows.LAZY01 = { plate = 'LAZY01', owner = 'CID001', model = 'sultan', hash = joaat_('sultan'), version = 0 }
check(run(exported.GiveKeyItem, 1, 'LAZY01') == true and hasKey(1, 'LAZY01'), 'owner key item (LAZY01)')
local lazyKey = itemsOf(1, 'vehicle_key')
lazyKey = lazyKey[#lazyKey].item.metadata
local lazyVersion = rows.LAZY01.version
rows.LAZY01.owner = 'CID003'
advance(16000) -- cached vehicle rows expire
check(not hasKey(1, 'LAZY01'), 'owner changed by another script: the old key stops working')
check(rows.LAZY01.version == lazyVersion + 1, 'owner changed by another script: new key version')
okSell, whySell = run(CarLock.verifyKeyItem, lazyKey, 'LAZY01')
check(not okSell and whySell == 'version', 'owner changed by another script: old item refused (version)')
local rekeyLogged = false
for _, l in ipairs(logs) do if l.event == 'vehicle.rekey' and l.data.plate == 'LAZY01' and l.data.reason == 'owner' then rekeyLogged = true end end
check(rekeyLogged, 'owner change noticed and logged')

-- a deleted vehicle's plate given to a new vehicle: old keys do not fit
rows.REUSE1 = { plate = 'REUSE1', owner = 'CID001', model = 'sultan', hash = joaat_('sultan'), version = 0 }
run(exported.GiveKeyItem, 1, 'REUSE1')
local reuseKey = itemsOf(1, 'vehicle_key')
reuseKey = reuseKey[#reuseKey].item.metadata
rows.REUSE1 = { plate = 'REUSE1', owner = 'CID001', model = 'sultan', hash = joaat_('sultan'), version = 0 } -- deleted + inserted again
run(CarLock.invalidate, 'REUSE1')
okSell, whySell = run(CarLock.verifyKeyItem, reuseKey, 'REUSE1')
check(not okSell and whySell == 'version', 'plate reused by a new row: the old key item does not fit')

-- vehicle shop: an unowned plate is bought, the key is cut right away and keeps working
local shop = spawnVehicle('SHOP01', 'blista', vec3(2, 0, 0), 7)
check(not hasKey(1, 'SHOP01'), 'unowned test-drive vehicle: no key')
rows.SHOP01 = { plate = 'SHOP01', owner = 'CID001', model = 'blista', hash = joaat_('blista'), version = 0 }
check(run(exported.GiveKeyItem, 1, shop) == true, 'GiveKeyItem(src, entity) right after the purchase')
advance(400000)
check(hasKey(1, 'SHOP01'), 'the key cut right after the purchase keeps working')

---------------------------------------------------------------------------------------
-- 11. Unshare (physical): a temporary key from a share ends with the share
---------------------------------------------------------------------------------------

rows.SHR001 = { plate = 'SHR001', owner = 'CID001', model = 'sultan', hash = joaat_('sultan'), version = 0 }
shares.CID002 = { { plate = 'SHR001' } }
local shr, shrNet = spawnVehicle('SHR001', 'sultan', vec3(2, 0, 0), 7)
NZ.Vehicles.out.SHR001 = { src = 2, identifier = 'CID002', entity = shr, netId = shrNet, spawner = false }
run(NZ.KeysServer.give, 2, shrNet, 'SHR001')
has, kind = hasKey(2, 'SHR001')
check(has and kind == 'temp', 'shared player retrieving in physical mode: temporary key')
shares.CID002 = nil
advance(16000)
check(not hasKey(2, 'SHR001'), 'unshared: the temporary key from the share is gone')
advance(2000)
res = cb('nz:carlock:compat', 2, { action = 'acquire', netId = shrNet, export = true })
check(not res.ok and not hasKey(2, 'SHR001'), 'unshared: taking it out through the share no longer lets other scripts give a key')

-- keys other scripts give through a share / fleet access end with that access too
rows.SHR002 = { plate = 'SHR002', owner = 'CID001', model = 'sultan', hash = joaat_('sultan'), version = 0 }
shares.CID002 = { { plate = 'SHR002' } }
local _, shr2Net = spawnVehicle('SHR002', 'sultan', vec3(2, 0.3, 0), 7)
advance(2000)
res = cb('nz:carlock:compat', 2, { action = 'acquire', netId = shr2Net, export = true })
has, kind = hasKey(2, 'SHR002')
check(res.ok and has and kind == 'temp', 'shared player: other scripts may give a temporary key')
shares.CID002 = nil
advance(16000)
check(not hasKey(2, 'SHR002'), 'unshared: that temporary key is gone')
rows.FLT001 = { plate = 'FLT001', owner = 'CID001', job = 'police', model = 'police', hash = joaat_('police'), version = 0 }
jobsOf.CID003 = 'police'
local _, fltNet = spawnVehicle('FLT001', 'police', vec3(2, 0.6, 0), 7)
playerPos[3] = vec3(2, 1, 0)
advance(2000)
fireNet('qb-vehiclekeys:server:AcquireVehicleKeys', 3, fltNet)
has, kind = hasKey(3, 'FLT001')
check(has and kind == 'temp', 'job member: other scripts may give a key of a fleet vehicle')
jobsOf.CID003 = nil
advance(16000)
check(not hasKey(3, 'FLT001'), 'left the job: the fleet key from another script is gone')
playerPos[3] = vec3(2, 0, 0)

---------------------------------------------------------------------------------------
-- 12. Database errors never reset key versions
---------------------------------------------------------------------------------------

local liveVersion = run(CarLock.keyVersion, 'ABC123')
dbDown = true
advance(301000) -- cached version expired
check(run(CarLock.keyVersion, 'ABC123') == liveVersion, 'database error: the last known version is kept (not 0)')
run(CarLock.invalidate, 'ABC123')
check(run(CarLock.keyVersion, 'ABC123') == nil, 'database error and nothing known: no version')
local holderKey = itemsOf(2, 'vehicle_key')[1]
okSell, whySell = run(CarLock.verifyKeyItem, holderKey.item.metadata, 'ABC123')
check(not okSell and whySell == 'error', 'database error: keys refused, not guessed')
dbDown = false
check(run(CarLock.keyVersion, 'ABC123') == liveVersion and hasKey(2, 'ABC123'), 'database back: the key works again')

---------------------------------------------------------------------------------------
-- 13. Lock state is the server's; forged state bags are put back
---------------------------------------------------------------------------------------

run(CarLock.setLocked, car, true, true)
stateOf(car):set('nzLocked', false)            -- the entity owner's client writes the bag
check(run(CarLock.isLocked, car) == true, 'isLocked answers from the server record, not the bag')
advance(200)
check(stateOf(car).nzLocked == true, 'a forged nzLocked bag is put back')
stateOf(shr):set('nzAlarm', { id = 99, mode = 'custom', seconds = 60 })
advance(200)
check(stateOf(shr).nzAlarm == false, 'an alarm a client made up is switched off')
run(CarLock.alarm, shr, 5, 'custom')
local alarmId = stateOf(shr).nzAlarm.id
stateOf(shr):set('nzAlarm', false)
advance(200)
check(type(stateOf(shr).nzAlarm) == 'table' and stateOf(shr).nzAlarm.id == alarmId, 'a server alarm a client switched off is put back')
advance(6000)
check(stateOf(shr).nzAlarm == false, 'the alarm ends after its time')

---------------------------------------------------------------------------------------
-- 14. Other scripts: lending, the client GiveKey export, players without a character
---------------------------------------------------------------------------------------

-- physical mode: a temporary key never makes more keys, a key item is handed over
spawnVehicle('LEND01', 'taxi', vec3(2, 0.5, 0), 7)
run(CarLock.grantTemp, 1, 'LEND01', 'compat')
advance(2000)
fireNet('qb-vehiclekeys:server:GiveVehicleKeys', 1, 2, 'LEND01')
check(not hasKey(2, 'LEND01'), 'physical: a temporary key holder cannot lend keys')
rows.LEND01 = { plate = 'LEND01', owner = 'CID001', model = 'taxi', hash = joaat_('taxi'), version = 0 }
run(CarLock.revokeTemp, 1, 'LEND01')
run(exported.GiveKeyItem, 1, 'LEND01')
advance(2000)
local before1 = #itemsOf(1, 'vehicle_key')
fireNet('qb-vehiclekeys:server:GiveVehicleKeys', 1, 2, 'LEND01')
has, kind = hasKey(2, 'LEND01')
check(has and kind == 'item' and #itemsOf(1, 'vehicle_key') == before1 - 1, 'physical: lending with a key item hands the item over')

-- virtual mode: a temporary key (hotwire, robbery, other scripts) never makes more keys either
Config.CarLock.keyMode = 'virtual'
local _, lend2Net = spawnVehicle('LEND02', 'taxi', vec3(2, 0.4, 0), 7)
run(CarLock.grantTemp, 1, 'LEND02', 'hotwire')
advance(2000)
res = cb('nz:carlock:compat', 1, { action = 'lend', netId = lend2Net, target = 2 })
check(not res.ok and not hasKey(2, 'LEND02'), 'virtual: a temporary key holder cannot lend keys')
Config.CarLock.keyMode = 'auto'

-- qb-vehiclekeys:server:setVehLockState: server scripts (local event) are trusted, players need a key
local lockCar, lockNet = spawnVehicle('LOCK01', 'asea', vec3(2, 0.1, 0), 2)
TriggerEvent('qb-vehiclekeys:server:setVehLockState', lockNet, 2)
check(stateOf(lockCar).nzLocked == true, 'setVehLockState from a server script locks')
advance(2000)
fireNet('qb-vehiclekeys:server:setVehLockState', 99, lockNet, 1)
check(stateOf(lockCar).nzLocked == true, 'setVehLockState from an unknown source number is ignored')
fireNet('qb-vehiclekeys:server:setVehLockState', 2, lockNet, 1)
check(stateOf(lockCar).nzLocked == true, 'setVehLockState from a player without a key is ignored')

-- the client export GiveKey can be closed
local _, mission2Net = spawnVehicle('JOB0003', 'taxi', vec3(2, -0.5, 0), 7)
Config.CarLock.clientGiveKeyExport = false
advance(2000)
res = cb('nz:carlock:compat', 3, { action = 'acquire', netId = mission2Net, export = true })
check(res.ok and res.data == false and not hasKey(3, 'JOB0003'), 'client GiveKey export closed by clientGiveKeyExport = false')
Config.CarLock.clientGiveKeyExport = true
advance(2000)
res = cb('nz:carlock:compat', 3, { action = 'acquire', netId = mission2Net, export = true })
check(res.ok and hasKey(3, 'JOB0003'), 'client GiveKey export open by default')

-- a connected player without a character gets nothing from other scripts' events
advance(2000)
res = cb('nz:carlock:compat', 4, { action = 'acquire', netId = mission2Net })
check(not res.ok and not run(CarLock.hasKey, 4, 'JOB0003'), 'no character loaded: compat key refused')

-- a burst of compat requests is limited per player (not per vehicle)
advance(3000)
local refused = 0
for _ = 1, 6 do
  local r = cb('nz:carlock:compat', 3, { action = 'remove', plate = 'NOPE01' })
  if not r.ok and r.error == 'Please wait a moment' then refused = refused + 1 end
end
check(refused >= 1, 'compat requests: a burst beyond 4 is refused')

-- an entity that reaches the server a moment after the event
advance(3000)
local lateNet = nextNet + 1
local lateRes
CreateThread(function() lateRes = callbacks['nz:carlock:compat'](3, { action = 'acquire', netId = lateNet }) end)
advance(300)
spawnVehicle('LATE01', 'taxi', vec3(2, 0.2, 0), 7)
advance(500)
check(lateRes and lateRes.ok and hasKey(3, 'LATE01'), 'compat waits for a vehicle that is not on the server yet')

---------------------------------------------------------------------------------------
-- 15. Exports take entities; QBCore callbacks are rate limited; jaksam shims
---------------------------------------------------------------------------------------

local entCar = spawnVehicle('ENT001', 'asea', vec3(2, 0, 0), 2)
check(run(exported.GiveKey, 3, entCar) == true and hasKey(3, 'ENT001'), 'GiveKey(src, entity handle)')
check(run(exported.HasKey, 3, entCar) == true, 'HasKey(src, entity handle)')
check(run(exported.SetVehicleLocked, entCar, true) == true and run(exported.IsVehicleLocked, entCar) == true, 'Set / IsVehicleLocked with an entity handle')

local qbcb = qbCallbacks['qb-vehiclekeys:server:GetVehicleKeys']
check(type(qbcb) == 'function', 'qb-vehiclekeys:server:GetVehicleKeys callback registered')
local got
rateOpen = false
qbcb(3, function(v) got = v end)
check(type(got) == 'table' and next(got) == nil, 'QBCore keys callback: rate limited -> empty')
rateOpen = true
run(qbcb, 3, function(v) got = v end)
check(type(got) == 'table' and got.ENT001 == true, 'QBCore keys callback answers')

local refresh = shim('vehicles_keys', 'refreshPlayerOwnedVehicles')
local pushes = clientEventsFor('nz:client:carlock:keys', 1)
check(refresh and run(refresh, 1, true) == true and clientEventsFor('nz:client:carlock:keys', 1) == pushes + 1, 'jaksam refreshPlayerOwnedVehicles shim')
local idKeys = shim('vehicles_keys', 'getIdentifierKeys')
check(idKeys and type(run(idKeys, 'CID002')) == 'table', 'jaksam getIdentifierKeys shim')

---------------------------------------------------------------------------------------
-- 16. Learned classes, key items missing from the inventory
---------------------------------------------------------------------------------------

local exotic = spawnVehicle('CLS001', 'exotic1', vec3(2, 0, 0), 2)
run(CarLock.learnClass, 1, exotic, 0)
check(run(CarLock.classOf, exotic) == 0, 'a single uncontested class vote counts')
run(CarLock.learnClass, 2, exotic, 7)
check(run(CarLock.classOf, exotic) == nil, 'contested 1:1 votes: class unknown (standard profile)')
run(CarLock.learnClass, 3, exotic, 7)
check(run(CarLock.classOf, exotic) == 7, 'two players agree: their class wins')

oxDefined.vehicle_fob = nil
advance(61000)
local warnsBefore = #printed.warn
check(run(CarLock.mode) == 'virtual', 'vehicle_fob missing from ox_inventory: virtual keys')
check(#printed.warn == warnsBefore + 1 and printed.warn[#printed.warn]:find('vehicle_fob') ~= nil, 'missing key item reported once')
oxDefined.vehicle_fob = true
advance(61000)
check(run(CarLock.mode) == 'physical', 'items defined again: physical keys')

---------------------------------------------------------------------------------------
-- 17. qb-inventory: keys cannot be given with client-made metadata
---------------------------------------------------------------------------------------

Config.Integrations.inventory = 'qb-inventory'
resourceStates['qb-inventory'] = 'started'
TriggerEvent('onResourceStart', 'qb-inventory')
advance(2500)
check(NZ.Inventory.name() == 'qb-inventory' and type(qbHooks.ItemMoved) == 'function', 'qb-inventory ItemMoved hook registered')
local hook = qbHooks.ItemMoved
check(hook and hook('given', { fromId = 1, fromSlot = 3, fromInventory = { items = { [3] = { name = 'vehicle_key', slot = 3 } } } }) == false,
  'giving a key item from qb-inventory is refused')
check(hook and hook('given', { fromId = 1, fromSlot = 4, fromInventory = { items = { [4] = { name = 'water', slot = 4 } } } }) == nil,
  'giving other items is untouched')
check(hook and hook('given', { fromId = 1, fromInventory = { items = { [3] = { name = 'vehicle_fob', slot = 3 } } } }) == false,
  'a give without a slot is refused while the giver carries a key')
check(hook and hook('move', { fromSlot = 3, fromInventory = { items = { [3] = { name = 'vehicle_key' } } } }) == nil,
  'moving keys inside inventories is untouched')

-- qb-inventory 2.2+: a shared item (lockpick) stays registered by its owner script; the
-- ItemUsed hook gives our handler the first look
local hookUses, hookHandled = 0, false
NZ.Inventory.registerUsable('lockpick', function() hookUses = hookUses + 1 return hookHandled end, { fallthrough = true })
advance(1500)
local usedHook = qbHooks.ItemUsed
check(type(usedHook) == 'function', 'qb-inventory: ItemUsed hook registered for shared items')
check(qbUsable.lockpick.resource == 'qb-smallresources', 'qb-inventory: the lockpick is not taken over in QBCore')
local usedRes = usedHook and usedHook('item', { source = 1, item = { name = 'lockpick', slot = 5, info = {} } })
advance(100)
check(usedRes == false and hookUses == 1 and #qbPrevUses == 1, 'qb-inventory: nothing for us -> the owner script runs the lockpick (houses, stores)')
hookHandled = true
advance(2500)
usedRes = usedHook and usedHook('item', { source = 1, item = { name = 'lockpick', slot = 5, info = {} } })
advance(100)
check(usedRes == false and hookUses == 2 and #qbPrevUses == 1, 'qb-inventory: handled by the car lock -> the owner script does not run')
check(usedHook and usedHook('item', { source = 1, item = { name = 'water', slot = 6 } }) == nil, 'qb-inventory: other items pass the ItemUsed hook')
for i = #qbPrevUses, 1, -1 do qbPrevUses[i] = nil end
Config.Integrations.inventory = 'auto'
resourceStates['qb-inventory'] = nil
TriggerEvent('onResourceStart', 'ox_inventory')
advance(2500)
check(NZ.Inventory.name() == 'ox_inventory', 'back to ox_inventory')

---------------------------------------------------------------------------------------
-- 18. Shared items (lockpick): the previous QBCore handler gets the uses we do not handle
---------------------------------------------------------------------------------------

local lockpickHandled = false
local ourUses = 0
NZ.Inventory.registerUsable('lockpick', function() ourUses = ourUses + 1 return lockpickHandled end, { fallthrough = true })
advance(1500)
check(qbUsable.lockpick.resource == 'nayzeee-garages', 'lockpick registered with QBCore')
qbUsable.lockpick.func(1, { name = 'lockpick', slot = 5, info = {} })
advance(100)
check(ourUses == 1 and #qbPrevUses == 1, 'no vehicle for us: the previous lockpick handler runs (houses, stores)')
lockpickHandled = true
advance(2500)
qbUsable.lockpick.func(1, { name = 'lockpick', slot = 5, info = {} })
advance(100)
check(ourUses == 2 and #qbPrevUses == 1, 'handled by the car lock: the previous handler does not run')
TriggerEvent('onResourceStop', 'nayzeee-garages')
qbUsable.lockpick.func(1, { name = 'lockpick', slot = 5, info = {} })
check(#qbPrevUses == 2, 'resource stop: the previous lockpick handler is put back')
check(qbHookRemoved == 7, 'resource stop: the qb-inventory hook is removed')

---------------------------------------------------------------------------------------
-- 19. auto: another key resource running when we start -> built-in off
---------------------------------------------------------------------------------------

resourceStates['qb-vehiclekeys'] = 'started'
local warnCount = #printed.warn
handlers, callbacks = {}, {}
for k in pairs(bagHandlers) do bagHandlers[k] = nil end
load_('shared/carlock.lua')
loadServer()
advance(3000)
CarLock = NZ.CarLock
check(CarLock.enabled() == false and CarLock.otherKeyResource() == 'qb-vehiclekeys', 'auto + qb-vehiclekeys running: the built-in car lock is off')
check(GlobalState.nzCarLockOther == 'qb-vehiclekeys', 'the decision is published for the clients')
local startupWarned = false
for i = warnCount + 1, #printed.warn do
  if printed.warn[i]:find('qb-vehiclekeys is running: the built-in car lock is off', 1, true) then startupWarned = true end
end
check(startupWarned, 'startup warning printed')
check(NZ.KeysServer.resource() == 'qb-vehiclekeys', 'garage keys go to qb-vehiclekeys')
Config.Integrations.keys = 'nayzeee'
check(CarLock.enabled() == true, "keys = 'nayzeee' forces the built-in car lock")
Config.Integrations.keys = 'auto'
resourceStates['qb-vehiclekeys'] = nil
load_('shared/carlock.lua')
check(CarLock.enabled() == true, 'no other key resource: built-in car lock on')

---------------------------------------------------------------------------------------
-- 20. auto: a key resource that starts after us while the server boots takes over; once
--     players are online nothing flips (warning only)
---------------------------------------------------------------------------------------

local playerCount = 0
function GetNumPlayerIndices() return playerCount end
local function reloadServer()
  handlers, callbacks, commands = {}, {}, {}
  for k in pairs(bagHandlers) do bagHandlers[k] = nil end
  GlobalState.nzCarLockOther = nil
  load_('shared/carlock.lua')
  loadServer()
  advance(3000)
  CarLock = NZ.CarLock
end
local function shimCount(alias, name)
  return #(handlers[('__cfx_export_%s_%s'):format(alias, name)] or {})
end

reloadServer()
check(CarLock.enabled() == true and shimCount('qb-vehiclekeys', 'GiveKeys') == 1 and GlobalState.nzCarLockOther == false,
  'boot: built-in car lock on, qb-vehiclekeys exports answered')
resourceStates.wasabi_carlock = 'started'
local warnsBoot = #printed.warn
TriggerEvent('onResourceStart', 'wasabi_carlock')
advance(100)
check(CarLock.enabled() == false and CarLock.otherKeyResource() == 'wasabi_carlock', 'boot: wasabi_carlock started after us -> built-in car lock off')
check(GlobalState.nzCarLockOther == 'wasabi_carlock', 'boot: the hand-over is published for the clients that join')
check(NZ.KeysServer.resource() == 'wasabi_carlock', 'boot: garage keys go to wasabi_carlock')
check(shimCount('qb-vehiclekeys', 'GiveKeys') == 0 and shimCount('wasabi_carlock', 'GiveKey') == 0, 'boot: no compat export answered any more')
local bootWarned = false
for i = warnsBoot + 1, #printed.warn do
  if printed.warn[i]:find('Start wasabi_carlock before nayzeee-garages in server.cfg', 1, true) then bootWarned = true end
end
check(bootWarned, 'boot: the server.cfg order is reported')
local bootCar = spawnVehicle('BOOT01', 'asea', vec3(2, 0, 0), 2)
seat(3, bootCar)
local notesBefore = #notifications
run(commands.givekey, 3, {})
check(not hasKey(3, 'BOOT01') and #notifications == notesBefore + 1
  and notifications[#notifications].message == 'Vehicle keys are handled by another script', 'boot: /givekey says another script handles keys')
seat(3, nil)
res = cb('nz:carlock:toggleLock', 1, { netIds = {} })
check(not res.ok and res.error == 'Vehicle keys are handled by another script', 'boot: lock callbacks off')

resourceStates.wasabi_carlock = nil
reloadServer()
playerCount = 2
local warnsLive = #printed.warn
resourceStates.wasabi_carlock = 'started'
TriggerEvent('onResourceStart', 'wasabi_carlock')
advance(100)
check(CarLock.enabled() == true and GlobalState.nzCarLockOther == false, 'players online: nothing flips under them')
local liveWarned = false
for i = warnsLive + 1, #printed.warn do
  if printed.warn[i]:find('set Config.Integrations.keys = "wasabi_carlock"', 1, true) then liveWarned = true end
end
check(liveWarned, 'players online: the conflict is reported with the fix')
resourceStates.wasabi_carlock = nil

---------------------------------------------------------------------------------------
-- Report
---------------------------------------------------------------------------------------

for _, line in ipairs(printed.error) do failures[#failures + 1] = 'lib.print.error: ' .. line end
if #failures > 0 then
  for _, f in ipairs(failures) do print('FAIL ' .. f) end
  print(('%d of %d checks failed'):format(#failures, checks))
  os.exit(1)
end
print(('carlock OK (%d checks)'):format(checks))
