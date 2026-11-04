--[[
  Headless test for the key ring server side, the vehicle tracker and the locksmith services
  (no FiveM needed). Same stubbed server runtime as tools/smoke/carlock.lua (in-memory vehicle
  database, fake ox_inventory with metadata, fake world with routing buckets, money), loading
  the real shared files, the inventory / keys / listener bridges, server/carlock/{keys,main,
  exports}.lua and the files under test: server/carlock/{tracker,locksmith}.lua.

  Traced flows:
    key ring status (nz:carlock:tracker): every key / one key, trackable only for tracker
    profiles in the player's routing bucket, distances from the server ped, coordinates only
    for one trackable key, towed vehicles unavailable, tracker switched off, no key -> refused;
    remote alarm (nz:carlock:trackerAlarm): start, silence, cooldown, no tracker / no key /
    towed refused; share picker (nz:carlock:nearbyPlayers); key ring opened by the server;
    locksmith (nz:carlock:locksmith:open / :service): counter distance, legal duplicate /
    program / rekey rules, illegal shop on any vehicle nearby + police alert, missing
    materials, cannot afford, cannot carry, refunds when the inventory refuses the key,
    rekey retires every other key, virtual mode (no duplicate, program = temporary key).

  Usage (from the resource root):  lua5.4 tools/smoke/keyring.lua
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

local commands = {}  -- luacheck: ignore 241 (filled by the code under test)
function RegisterCommand(name, fn) commands[name] = fn end

-- Fake ox_inventory: [src] = { [slot] = { name, count, metadata, slot } }
local inv = { [1] = {}, [2] = {}, [3] = {}, [4] = {} }
local function oxCopy(t) local o = {} for k, v in pairs(t or {}) do o[k] = v end return o end
local oxDefined = { vehicle_key = true, vehicle_fob = true, lockpick = true, advancedlockpick = true, key_blank = true }
local canCarry = true     -- CanCarryItem answer
local addFails = 0        -- next AddItem calls that fail (inventory refuses)
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
  CanCarryItem = function() return canCarry end,
  AddItem = function(src, name, count, md)
    if addFails > 0 then addFails = addFails - 1 return false, 'inventory_full' end
    local list = inv[src]
    if not list then return false, 'invalid_inventory' end
    local slot = 1
    while list[slot] do slot = slot + 1 end
    list[slot] = { name = name, count = count, metadata = oxCopy(md), slot = slot }
    return true, { { slot = slot } }
  end,
  RemoveItem = function(src, name, count, _, slot)
    if slot == nil then
      -- by name: every slot of that item (ox_inventory RemoveItem without a slot)
      local total = 0
      for _, it in pairs(inv[src] or {}) do if it.name == name then total = total + it.count end end
      if total < count then return false end
      for s, it in pairs(inv[src]) do
        if count <= 0 then break end
        if it.name == name then
          local take = math.min(count, it.count)
          it.count, count = it.count - take, count - take
          if it.count <= 0 then inv[src][s] = nil end
        end
      end
      return true
    end
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
local qbCallbacks = {}  -- luacheck: ignore 241
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
  Shared = { Vehicles = { zentorno = { model = 'zentorno', category = 'super' } }, Items = { vehicle_key = { name = 'vehicle_key' }, vehicle_fob = { name = 'vehicle_fob' } } },
}
local qbHooks, qbHookRemoved = {}, nil  -- luacheck: ignore 231 241
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

local exported = {}  -- luacheck: ignore 241
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

-- routing buckets, money, character names, tow truck, dispatch
local playerBucket = {}
function GetPlayerRoutingBucket(src) return playerBucket[tonumber(src)] or 0 end
function GetEntityRoutingBucket(h) return entities[h] and entities[h].bucket or 0 end
local wallet = { [1] = { cash = 10000, bank = 0 }, [2] = { cash = 10000, bank = 0 }, [3] = { cash = 100, bank = 0 }, [4] = { cash = 0, bank = 0 } }
NZ.Bridge.getMoney = function(src, account) return (wallet[tonumber(src)] or {})[account] or 0 end
NZ.Bridge.removeMoney = function(src, account, amount)
  local w = wallet[tonumber(src)]
  if not w or (w[account] or 0) < amount then return false end
  w[account] = w[account] - amount
  return true
end
NZ.Bridge.addMoney = function(src, account, amount)
  local w = wallet[tonumber(src)]
  if not w then return false end
  w[account] = (w[account] or 0) + amount
  return true
end
NZ.Bridge.getName = function(src) return 'Char ' .. tostring(src) end
local towed = {}
NZ.Tow.isTowing = function(h) return towed[h] == true end
local alerts = {}
NZ.Dispatch.alert = function(src, alert) alerts[#alerts + 1] = { src = src, alert = alert } return true end

local function loadServer()
  load_('bridge/server/inventory.lua')
  load_('bridge/server/keys.lua')
  load_('bridge/server/listeners.lua')
  load_('server/carlock/keys.lua')
  load_('server/carlock/main.lua')
  load_('server/carlock/exports.lua')
  load_('server/carlock/locksmith.lua')
  load_('server/carlock/tracker.lua')
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
local function find(list, plate)
  for _, v in ipairs(list or {}) do if v.plate == plate then return v end end
  return nil
end

local function clientEventsSince(n0, name, target)
  local out = {}
  for i = n0 + 1, #clientEvents do
    local e = clientEvents[i]
    if e.name == name and (target == nil or e.target == target) then out[#out + 1] = e end
  end
  return out
end

local function giveBlank(src, n)
  run(NZ.Inventory.addItem, src, 'key_blank', n or 1)
end

---------------------------------------------------------------------------------------
-- 1. Key ring status: every key / one key, trackable vehicles only
---------------------------------------------------------------------------------------

check(run(CarLock.mode) == 'physical', 'physical mode with ox_inventory')
local sultan = spawnVehicle('ABC123', 'sultan', vec3(4, 0, 0), 7)
local zentorno, zentornoNet = spawnVehicle('FOB777', 'zentorno', vec3(500, 0, 0), 7)
run(CarLock.onVehicleOut, 1, sultan, 'ABC123')
run(CarLock.onVehicleOut, 1, zentorno, 'FOB777')
check(#itemsOf(1, 'vehicle_key') == 1 and #itemsOf(1, 'vehicle_fob') == 1, 'owner got a key and a fob from the garage')

local res = cb('nz:carlock:tracker', 1, {})
check(res.ok and type(res.data.vehicles) == 'table', 'tracker list answers')
local st = find(res.data.vehicles, 'FOB777')
check(st and st.spawned and st.netId == zentornoNet and st.tracker and st.trackable and st.profile == 'highend'
  and st.remote and st.keyType == 'fob', 'high-end vehicle is trackable with a fob profile')
check(st and st.distance == 500 and st.coords == nil, 'list: server distance, no coordinates')
check(st and st.isOwner == true and st.owned == true and st.locked == false and st.alarm == false, 'list: owner, lock and alarm state')
local sst = find(res.data.vehicles, 'ABC123')
check(sst and sst.spawned and not sst.trackable and sst.distance == nil and sst.keyType == 'key', 'standard vehicle: spawned, not trackable, no distance')
check(type(res.data.now) == 'number' and res.data.tracker == true, 'list: server time and tracker switch')

res = cb('nz:carlock:tracker', 1, { plate = 'fob777' })
st = res.ok and res.data.vehicles[1] or nil
check(st and st.plate == 'FOB777' and st.coords and st.coords.x == 500 and st.distance == 500, 'one trackable key: coordinates for the waypoint')
res = cb('nz:carlock:tracker', 1, { plate = 'ABC123' })
st = res.ok and res.data.vehicles[1] or nil
check(st and st.coords == nil and not st.trackable, 'one standard key: no coordinates')
res = cb('nz:carlock:tracker', 2, { plate = 'FOB777' })
check(not res.ok and res.error == 'You do not have the keys of this vehicle', 'no key: no position')
res = cb('nz:carlock:tracker', 1, { plate = ('X'):rep(20) })
check(not res.ok, 'too long plate refused')

-- other routing bucket: not reported
entities[zentorno].bucket = 7
res = cb('nz:carlock:tracker', 1, {})
st = find(res.data.vehicles, 'FOB777')
check(st and not st.spawned and not st.trackable and st.netId == nil and st.distance == nil, 'other routing bucket: not out for this player')
res = cb('nz:carlock:tracker', 1, { plate = 'FOB777' })
check(res.ok and not res.data.vehicles[1].spawned and res.data.vehicles[1].coords == nil, 'other routing bucket: no coordinates')
entities[zentorno].bucket = nil

-- impound tow truck
towed[zentorno] = true
res = cb('nz:carlock:tracker', 1, { plate = 'FOB777' })
st = res.data.vehicles[1]
check(st.towing and not st.trackable and st.coords == nil, 'towed vehicle: unavailable')
res = cb('nz:carlock:trackerAlarm', 1, { plate = 'FOB777' })
check(not res.ok and res.error == 'This vehicle is being towed', 'towed vehicle: no remote alarm')
towed[zentorno] = nil

-- tracker switched off
Config.CarLock.tracker.enabled = false
res = cb('nz:carlock:tracker', 1, { plate = 'FOB777' })
check(res.ok and not res.data.vehicles[1].trackable and res.data.vehicles[1].coords == nil and res.data.tracker == false, 'tracker off: nothing trackable')
res = cb('nz:carlock:trackerAlarm', 1, { plate = 'FOB777' })
check(not res.ok and res.error == 'The vehicle tracker is not available', 'tracker off: no remote alarm')
Config.CarLock.tracker.enabled = true

---------------------------------------------------------------------------------------
-- 2. Remote alarm
---------------------------------------------------------------------------------------

res = cb('nz:carlock:trackerAlarm', 1, { plate = 'FOB777' })
check(res.ok and res.data.alarm == true and res.data.seconds == 20, 'remote alarm starts (tracker.alarmSeconds)')
local bag = Entity(zentorno).state.nzAlarm
check(type(bag) == 'table' and bag.seconds == 20 and bag.mode == 'custom', 'alarm state bag written with the profile mode')
check(logs[#logs].event == 'vehicle.remoteAlarm', 'remote alarm logged')
res = cb('nz:carlock:trackerAlarm', 1, { plate = 'FOB777' })
check(res.ok and res.data.alarm == false and Entity(zentorno).state.nzAlarm == false, 'a second press silences it')
res = cb('nz:carlock:trackerAlarm', 1, { plate = 'FOB777', on = true })
check(not res.ok and res.error:find('can be triggered again', 1, true), 'cooldown between two alarms')
advance(61000)
res = cb('nz:carlock:trackerAlarm', 1, { plate = 'FOB777', on = true })
check(res.ok and res.data.alarm == true, 'alarm again after the cooldown')
advance(21000)
check(Entity(zentorno).state.nzAlarm == false, 'alarm ends on its own')
res = cb('nz:carlock:trackerAlarm', 1, { plate = 'ABC123' })
check(not res.ok and res.error == 'This vehicle has no tracker', 'standard profile: no tracker')
res = cb('nz:carlock:trackerAlarm', 2, { plate = 'FOB777' })
check(not res.ok and res.error == 'You do not have the keys of this vehicle', 'no key: no remote alarm')
res = cb('nz:carlock:trackerAlarm', 1, { plate = 'NOPE99' })
check(not res.ok, 'unknown plate: refused')

---------------------------------------------------------------------------------------
-- 3. Share picker and key ring from the server
---------------------------------------------------------------------------------------

res = cb('nz:carlock:nearbyPlayers', 1, {})
check(res.ok and #res.data == 2 and res.data[1].serverId == 2 and res.data[2].serverId == 3
  and res.data[1].name == 'Char 2' and res.data[1].distance == 1, 'nearby players: closest first, character names, no player without a character')
playerBucket[3] = 9
res = cb('nz:carlock:nearbyPlayers', 1, {})
check(res.ok and #res.data == 1 and res.data[1].serverId == 2, 'nearby players: same routing bucket only')
playerBucket[3] = nil
local n0 = #clientEvents
check(CarLock.openKeyRing(1, ' fob777 ') == true, 'openKeyRing')
local ev = clientEventsSince(n0, 'nz:client:carlock:keyRing', 1)
check(#ev == 1 and ev[1].payload.plate == 'FOB777', 'key ring opened on that key')
check(CarLock.openKeyRing(99) == false, 'openKeyRing: unknown player')

---------------------------------------------------------------------------------------
-- 4. Locksmith (legal): counter, duplicate, program, rekey, money and materials
---------------------------------------------------------------------------------------

local shop = Config.CarLock.locksmiths[1]
local shopPos = vec3(shop.coords.x, shop.coords.y, shop.coords.z)
res = cb('nz:carlock:locksmith:open', 1, { id = 1 })
check(not res.ok and res.error == 'You are too far from the locksmith', 'locksmith: counter distance from the server ped')
playerPos[1] = vec3(shopPos.x + 1, shopPos.y, shopPos.z)
entities[sultan].coords = vec3(shopPos.x + 8, shopPos.y, shopPos.z)
res = cb('nz:carlock:locksmith:open', 1, { id = 1 })
check(res.ok and res.data.id == 1 and res.data.illegal == false and res.data.mode == 'physical' and res.data.money == 10000
  and res.data.account == 'cash' and #res.data.services == 3, 'locksmith opens with services, mode and money')
local data = res.data
local car = find(data.vehicles, 'ABC123')
check(car and car.nearby and car.distance == 8 and car.isOwner and car.keyItems == 1 and car.keyType == 'key'
  and car.blocked.duplicate == nil and car.blocked.program == nil and car.blocked.rekey == nil, 'owned vehicle nearby with its key: every service')
local fob = find(data.vehicles, 'FOB777')
check(fob and not fob.nearby and fob.keyItems == 1 and fob.keyType == 'fob' and fob.blocked.duplicate == nil
  and fob.blocked.program == 'Park the vehicle near the locksmith' and fob.blocked.rekey == 'Park the vehicle near the locksmith', 'far vehicle: duplicate only')
check(data.vehicles[1].plate == 'ABC123', 'nearby vehicles first')
local program = nil
for _, s in ipairs(data.services) do if s.id == 'program' then program = s end end
check(program and program.price == 500 and #program.materials == 1 and program.materials[1].item == 'key_blank'
  and program.materials[1].label == 'Key blank' and program.materials[1].have == 0, 'program: price and materials with what you carry')

-- a stranger's car parked at a legal shop is not listed
spawnVehicle('NPC001', 'asea', vec3(shopPos.x + 5, shopPos.y + 2, shopPos.z), 2)
res = cb('nz:carlock:locksmith:open', 1, { id = 1 })
check(res.ok and find(res.data.vehicles, 'NPC001') == nil, 'legal shop: strangers\' cars are not listed')

-- duplicate (key item in the pocket)
local cashBefore = wallet[1].cash
res = cb('nz:carlock:locksmith:service', 1, { id = 1, service = 'duplicate', plate = 'ABC123' })
check(res.ok and res.data.message == 'Spare key for ABC123 cut' and type(res.data.data) == 'table', 'duplicate: done, fresh data returned')
check(#itemsOf(1, 'vehicle_key') == 2 and wallet[1].cash == cashBefore - 250, 'duplicate: second key, paid 250')
local copy = itemsOf(1, 'vehicle_key')[2].item.metadata
check(run(CarLock.verifyKeyItem, copy, 'ABC123') == true, 'duplicate: the copy is a valid signed key')
check(logs[#logs].event == 'vehicle.locksmith' and logs[#logs].data.service == 'duplicate', 'locksmith service logged')

-- duplicate of a fob keeps the fob kind
res = cb('nz:carlock:locksmith:service', 1, { id = 1, service = 'duplicate', plate = 'FOB777' })
check(res.ok and #itemsOf(1, 'vehicle_fob') == 2 and res.data.message == 'Spare fob for FOB777 cut', 'duplicate of a fob: a fob')

-- player 2: no key, not the owner
playerPos[2] = vec3(shopPos.x - 1, shopPos.y, shopPos.z)
res = cb('nz:carlock:locksmith:service', 2, { id = 1, service = 'duplicate', plate = 'ABC123' })
check(not res.ok and res.error == 'Bring a key or the papers of this vehicle', 'duplicate: neither key nor papers')
res = cb('nz:carlock:locksmith:service', 2, { id = 1, service = 'program', plate = 'ABC123' })
check(not res.ok and res.error == 'Only the owner or a key holder can order a key', 'legal program: strangers refused')
res = cb('nz:carlock:locksmith:service', 2, { id = 1, service = 'rekey', plate = 'ABC123' })
check(not res.ok and res.error == 'Only the owner can change the locks', 'legal rekey: owner only')

-- program: missing materials, cannot afford, then done
res = cb('nz:carlock:locksmith:service', 1, { id = 1, service = 'program', plate = 'ABC123' })
check(not res.ok and res.error == 'Missing materials: 1x Key blank', 'program: missing materials')
giveBlank(1)
wallet[1].cash = 100
res = cb('nz:carlock:locksmith:service', 1, { id = 1, service = 'program', plate = 'ABC123' })
check(not res.ok and res.error == 'You cannot afford this' and wallet[1].cash == 100 and #itemsOf(1, 'key_blank') == 1, 'program: cannot afford, nothing taken')
wallet[1].cash = 5000
canCarry = false
res = cb('nz:carlock:locksmith:service', 1, { id = 1, service = 'program', plate = 'ABC123' })
check(not res.ok and res.error == 'You cannot carry the key' and wallet[1].cash == 5000 and #itemsOf(1, 'key_blank') == 1, 'program: cannot carry, nothing taken')
canCarry = true
addFails = 1
res = cb('nz:carlock:locksmith:service', 1, { id = 1, service = 'program', plate = 'ABC123' })
check(not res.ok and addFails == 0 and wallet[1].cash == 5000 and #itemsOf(1, 'key_blank') == 1 and #itemsOf(1, 'vehicle_key') == 2, 'program: inventory refuses the key -> money and blank given back')
res = cb('nz:carlock:locksmith:service', 1, { id = 1, service = 'program', plate = 'ABC123' })
check(res.ok and res.data.message == 'New key for ABC123 programmed' and #itemsOf(1, 'vehicle_key') == 3
  and #itemsOf(1, 'key_blank') == 0 and wallet[1].cash == 4500, 'program: key cut, blank and 500 taken')

-- a hotwired (temporary) key is not enough at a legal shop
run(CarLock.grantTemp, 2, 'NPC001', 'hotwire')
giveBlank(2)
res = cb('nz:carlock:locksmith:open', 2, { id = 1 })
local npcView = res.ok and find(res.data.vehicles, 'NPC001') or nil
check(npcView and npcView.keyKind == 'temp' and npcView.hasKey, 'hotwired car listed with its temporary key')
res = cb('nz:carlock:locksmith:service', 2, { id = 1, service = 'program', plate = 'NPC001' })
check(not res.ok and res.error == 'A temporary key is not enough: only the owner or a key holder', 'legal program: temporary key refused')

-- rekey: every other key stops working, old items taken back, a new key handed out
run(CarLock.grantTemp, 3, 'ABC123', 'admin')
check(hasKey(3, 'ABC123'), 'player 3 has a temporary key before the rekey')
local oldKey = itemsOf(1, 'vehicle_key')[1].item.metadata
cashBefore = wallet[1].cash
res = cb('nz:carlock:locksmith:service', 1, { id = 1, service = 'rekey', plate = 'ABC123' })
check(res.ok and res.data.message == 'Locks of ABC123 changed: every other key stops working', 'rekey: done')
check(run(CarLock.verifyKeyItem, oldKey, 'ABC123') == false, 'rekey: old keys no longer fit')
check(#itemsOf(1, 'vehicle_key') == 1 and run(CarLock.verifyKeyItem, itemsOf(1, 'vehicle_key')[1].item.metadata, 'ABC123'), 'rekey: old key items taken back, one new key')
check(not hasKey(3, 'ABC123'), 'rekey: temporary keys of others removed')
check(wallet[1].cash == cashBefore - 1500, 'rekey: paid 1500')

-- towed vehicle
towed[sultan] = true
res = cb('nz:carlock:locksmith:service', 1, { id = 1, service = 'rekey', plate = 'ABC123' })
check(not res.ok and res.error == 'This vehicle is being towed', 'locksmith: towed vehicle refused')
towed[sultan] = nil

-- bad requests
res = cb('nz:carlock:locksmith:service', 1, { id = 9, service = 'rekey', plate = 'ABC123' })
check(not res.ok and res.error == 'Invalid request', 'unknown locksmith')
res = cb('nz:carlock:locksmith:service', 1, { id = 1, service = 'steal', plate = 'ABC123' })
check(not res.ok and res.error == 'Invalid request', 'unknown service')
res = cb('nz:carlock:locksmith:service', 1, { id = 1.5, service = 'rekey', plate = 'ABC123' })
check(not res.ok, 'fractional id')
res = cb('nz:carlock:locksmith:service', 1, { id = 1, service = 'program', plate = 'ZZZ999' })
check(not res.ok and res.error == 'Vehicle not found', 'unknown vehicle')

---------------------------------------------------------------------------------------
-- 5. Locksmith (illegal): any vehicle nearby, police alert, disabled service
---------------------------------------------------------------------------------------

local den = Config.CarLock.locksmiths[2]
local denPos = vec3(den.coords.x, den.coords.y, den.coords.z)
playerPos[3] = vec3(denPos.x, denPos.y + 1, denPos.z)
wallet[3].cash = 10000
local stranger = spawnVehicle('XYZ987', 'asea', vec3(denPos.x + 6, denPos.y, denPos.z), 2)
den.alertChance = 100
res = cb('nz:carlock:locksmith:open', 3, { id = 2 })
local sv = res.ok and find(res.data.vehicles, 'XYZ987') or nil
check(res.ok and res.data.illegal and sv and sv.nearby and not sv.hasKey and sv.blocked.program == nil
  and sv.blocked.rekey == 'Not offered here' and sv.blocked.duplicate == 'Bring a key of this vehicle to copy', 'illegal shop: any vehicle nearby can get a key')
local nAlerts = #alerts
res = cb('nz:carlock:locksmith:service', 3, { id = 2, service = 'program', plate = 'XYZ987' })
check(res.ok and #itemsOf(3, 'vehicle_key') == 1 and hasKey(3, 'XYZ987') and wallet[3].cash == 6500, 'illegal program: key for a stranger\'s car')
check(#alerts == nAlerts + 1 and alerts[#alerts].alert.kind == 'locksmith' and alerts[#alerts].alert.plate == 'XYZ987'
  and alerts[#alerts].alert.code == Config.CarLock.dispatch.codes.locksmith, 'illegal program: police alert through NZ.Dispatch.alert')
den.alertChance = 0
res = cb('nz:carlock:locksmith:service', 3, { id = 2, service = 'rekey', plate = 'XYZ987' })
check(not res.ok and res.error == 'Not offered here', 'disabled service refused')
-- a player behind the wheel of someone else's car
seat(2, stranger)
res = cb('nz:carlock:locksmith:open', 3, { id = 2 })
sv = res.ok and find(res.data.vehicles, 'XYZ987') or nil
check(sv and sv.blocked.program == 'Someone else is driving this vehicle', 'illegal shop: not while another player drives it')
seat(2, nil)
-- the vehicle drives off: no longer nearby
entities[stranger].coords = vec3(denPos.x + 80, denPos.y, denPos.z)
res = cb('nz:carlock:locksmith:service', 3, { id = 2, service = 'program', plate = 'XYZ987' })
check(not res.ok and res.error == 'Park the vehicle near the locksmith', 'program: vehicle left the range')

---------------------------------------------------------------------------------------
-- 6. Virtual mode
---------------------------------------------------------------------------------------

Config.CarLock.keyMode = 'virtual'
check(run(CarLock.mode) == 'virtual', 'virtual mode')
den.services.rekey.enabled = true
res = cb('nz:carlock:locksmith:open', 1, { id = 1 })
local dup = nil
for _, s in ipairs(res.data.services) do if s.id == 'duplicate' then dup = s end end
check(res.ok and res.data.mode == 'virtual' and dup and dup.offered == false and dup.reason == 'Give virtual keys from your key ring', 'virtual: duplicate not offered')
car = find(res.data.vehicles, 'ABC123')
check(car and car.blocked.duplicate == 'Give virtual keys from your key ring' and car.blocked.program == 'You already have a key for this vehicle', 'virtual: owner already has a key')
res = cb('nz:carlock:locksmith:service', 1, { id = 1, service = 'duplicate', plate = 'ABC123' })
check(not res.ok and res.error == 'Give virtual keys from your key ring', 'virtual: duplicate refused')
-- share a virtual key, then rekey revokes it
run(CarLock.shareVirtual, 1, 2, 'ABC123')
check(hasKey(2, 'ABC123'), 'virtual key shared')
res = cb('nz:carlock:locksmith:service', 1, { id = 1, service = 'rekey', plate = 'ABC123' })
check(res.ok and not hasKey(2, 'ABC123') and hasKey(1, 'ABC123'), 'virtual rekey: others revoked, owner keeps the key')
-- illegal program in virtual mode = temporary key
entities[stranger].coords = vec3(denPos.x + 4, denPos.y, denPos.z)
local stranger2 = spawnVehicle('VIR001', 'asea', vec3(denPos.x + 3, denPos.y + 3, denPos.z), 2)
check(stranger2 ~= nil, 'second car at the den')
res = cb('nz:carlock:locksmith:service', 3, { id = 2, service = 'program', plate = 'VIR001' })
local _, kind = hasKey(3, 'VIR001')
check(res.ok and kind == 'temp' and res.data.message:find('Temporary key for VIR001', 1, true), 'virtual program: temporary key')
-- illegal rekey of a stranger's car: the requester keeps a temporary key
res = cb('nz:carlock:locksmith:service', 3, { id = 2, service = 'rekey', plate = 'VIR001' })
_, kind = hasKey(3, 'VIR001')
check(res.ok and kind == 'temp', 'virtual illegal rekey: requester keeps a temporary key')
den.services.rekey.enabled = false
Config.CarLock.keyMode = 'auto'

---------------------------------------------------------------------------------------
-- Report
---------------------------------------------------------------------------------------

for _, line in ipairs(printed.error) do failures[#failures + 1] = 'lib.print.error: ' .. line end
if #failures > 0 then
  for _, f in ipairs(failures) do print('FAIL ' .. f) end
  print(('%d of %d checks failed'):format(#failures, checks))
  os.exit(1)
end
print(('keyring OK (%d checks)'):format(checks))
