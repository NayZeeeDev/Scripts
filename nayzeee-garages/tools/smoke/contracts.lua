--[[
  Headless test for sale contracts and fake plates (no FiveM needed).

  Loads the real shared files, server/access.lua, server/vehicles.lua, server/actions.lua,
  server/carlock/keys.lua, server/contracts.lua and server/fakeplates.lua in a stubbed server
  runtime (in-memory vehicle database + key state, fake inventory with metadata, money, a fake
  world with peds, vehicles, seats, headings, state bags and KVP, a controllable clock) and
  traces the flows end to end:

    contracts: blank contract use -> draft (own vehicles nearby, blocked reasons, buyers in
    range) -> send (every refusal) -> review; buyer cannot pay; seller moved away; vehicle
    financed after sending; expiry; decline / withdraw; a party leaving; success (owner,
    money, blank consumed, rekey: old key dead and buyer key item, history entry, signed
    copies, logs); reuse attempts; signed copy view (verified / edited / garbage); the
    garage sale helper (NZ.Actions.sellVehicle) and its rollback; resend cooldown after a "no";
    the draft reopened in its sent state; the buyer's balance poll; another model / an untracked
    copy wearing the registration's text; a garaged registration; keys moving with an external
    key resource; money reasons.
    fake plates: item use; start refusals (rear, screwdriver, occupied, towed); server timer
    (too early = attempt used up); install (unique plate from the pattern, real plate kept for
    keys / locks, state bags, client tampering put back, police lookup, contract blocked);
    pattern collisions; removal (item back, bags cleared); screwdriver breaking; garage store
    (real plate saved, fake plate returned); garage retrieve never deleting another model
    showing the plate but removing a fake-plated copy of the vehicle itself; resource restart
    (the garage adopts the fake-plated vehicle back: no second copy); recover returning the item;
    pattern with a space; rear corner refused; keys for the fake text with an external key
    resource (installer with access, absent owner; never a stranger).

  Usage (from the resource root):  lua5.4 tools/smoke/contracts.lua
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
local realTime = os.time
os.time = function(t) -- luacheck: ignore 122
  if t then return realTime(t) end
  return BASE_TIME + clock // 1000
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
function AddEventHandler(name, fn)
  handlers[name] = handlers[name] or {}
  table.insert(handlers[name], fn)
  return name
end
function RegisterNetEvent(name, fn) if fn then AddEventHandler(name, fn) end end
function TriggerEvent(name, ...)
  for _, fn in ipairs(handlers[name] or {}) do
    source = '' -- luacheck: ignore 111
    fn(...)
  end
end
function TriggerClientEvent(name, target, payload) clientEvents[#clientEvents + 1] = { name = name, target = target, payload = payload } end

local function lastEvent(name, target)
  for i = #clientEvents, 1, -1 do
    local e = clientEvents[i]
    if e.name == name and (target == nil or e.target == target) then return e end
  end
  return nil
end

local function countEvents(name, target)
  local n = 0
  for _, e in ipairs(clientEvents) do
    if e.name == name and (target == nil or e.target == target) then n = n + 1 end
  end
  return n
end

local function notified(target, pattern)
  for i = #clientEvents, 1, -1 do
    local e = clientEvents[i]
    if e.name == 'nz:client:notify' and e.target == target and type(e.payload) == 'table'
      and tostring(e.payload.message):find(pattern, 1, true) then
      return true
    end
  end
  return false
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
local names = { [1] = 'Marcus Hale', [2] = 'Jade Ortiz', [3] = 'Far Away', [4] = 'Tomas Reyes' }
local playerPos = { [1] = vec3(0, 0, 0), [2] = vec3(2, 0, 0), [3] = vec3(60, 0, 0), [4] = vec3(3, 1, 0) }
local playerStates = {}
function GetPlayerName(src) return online[tonumber(src)] and ('Player' .. tostring(src)) or nil end
function GetPlayerPed(src) return online[tonumber(src)] and (1000 + tonumber(src)) or 0 end
function GetPlayerRoutingBucket() return 0 end
function GetEntityRoutingBucket() return 0 end
function GetPlayers() local out = {} for src in pairs(online) do out[#out + 1] = tostring(src) end table.sort(out) return out end
function GetNumPlayerIndices() local n = 0 for _ in pairs(online) do n = n + 1 end return n end
function IsPlayerAceAllowed() return false end
function IsDuplicityVersion() return true end
function GetCurrentResourceName() return 'nayzeee-garages' end
function GetInvokingResource() return nil end
function GetConvar(_, default) return default end
function IsPedAPlayer(ped) return type(ped) == 'number' and ped > 1000 and ped < 2000 end
function GetEntityHealth() return 200 end
function GetEntityAttachedTo() return 0 end
function Player(src)
  playerStates[src] = playerStates[src] or {}
  return { state = playerStates[src] }
end
local resourceStates = { ['qb-core'] = 'started' }
function GetResourceState(name) return resourceStates[name] or 'missing' end
GlobalState = {}

local bagHandlers = {}
function AddStateBagChangeHandler(key, _, fn) bagHandlers[key] = bagHandlers[key] or {} table.insert(bagHandlers[key], fn) end
function GetEntityFromStateBagName(name) return tonumber(tostring(name):match('^entity:(%d+)$')) or 0 end

local kvp = {}
function GetResourceKvpString(k) return kvp[k] end
function SetResourceKvp(k, v) kvp[k] = v end
function DeleteResourceKvp(k) kvp[k] = nil end

-- Vehicles: [handle] = { plate, model, netId, seats = { [-1] = ped }, coords, heading, vtype }
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

local function spawnVehicle(plate, model, coords, heading)
  nextHandle, nextNet = nextHandle + 1, nextNet + 1
  entities[nextHandle] = { plate = plate, model = joaat_(model or 'sultan'), netId = nextNet, seats = {},
    coords = coords or vec3(4, 0, 0), heading = heading or 0.0, vtype = 'automobile', lock = 0 }
  return nextHandle, nextNet
end

local function seat(src, handle)
  for _, e in pairs(entities) do
    for s, ped in pairs(e.seats) do if ped == 1000 + src then e.seats[s] = nil end end
  end
  if handle then entities[handle].seats[-1] = 1000 + src end
end

function DoesEntityExist(h) return entities[h] ~= nil or (type(h) == 'number' and h > 1000 and h < 2000 and online[h - 1000] ~= nil) end
function GetEntityType(h) return entities[h] and 2 or ((type(h) == 'number' and h > 1000 and h < 2000) and 1 or 0) end
function GetAllVehicles() local out = {} for h in pairs(entities) do out[#out + 1] = h end table.sort(out) return out end
function GetVehicleNumberPlateText(h) local e = entities[h] return e and (e.plate .. '        '):sub(1, 8) or '' end
function SetVehicleNumberPlateText(h, text) if entities[h] then entities[h].plate = tostring(text) end end
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
function GetVehicleType(h) return entities[h] and entities[h].vtype or nil end
function GetEntityHeading(h) return entities[h] and entities[h].heading or 0.0 end
function GetEntityCoords(h)
  if entities[h] then return entities[h].coords end
  return playerPos[h - 1000] or vec3(0, 0, 0)
end
function GetVehicleEngineHealth() return 880.0 end
function GetVehicleBodyHealth() return 640.0 end
function GetVehiclePetrolTankHealth() return 1000.0 end
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
exports = setmetatable({}, {
  __call = function() end,
  __index = function() return setmetatable({}, { __index = function() return function() return nil end end }) end,
})
function RegisterCommand() end

local dk = require('dkjson')
json = { encode = function(v) return dk.encode(v) end, decode = function(s) if type(s) ~= 'string' then return nil end return (dk.decode(s)) end }

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
local Utils = NZ.Utils
local CarLock = NZ.CarLock

---------------------------------------------------------------------------------------
-- In-memory modules
---------------------------------------------------------------------------------------

NZ.Settings.get = function(path, default)
  local node = Config.DefaultSettings
  for part in path:gmatch('[^%.]+') do
    if type(node) ~= 'table' then return default end
    node = node[part]
  end
  if node == nil then return default end
  return node
end

local logs = {}
NZ.Logs.add = function(event, src, data) logs[#logs + 1] = { event = event, src = src, data = data or {} } end
local function lastLog(event, field, value)
  for i = #logs, 1, -1 do
    local l = logs[i]
    if l.event == event and (field == nil or l.data[field] == value) then return l end
  end
  return nil
end

-- money
local bank = { [1] = 1000, [2] = 60000, [3] = 0, [4] = 0 }
local cash = { [1] = 0, [2] = 0, [3] = 0, [4] = 0 }
local payoutFails = false
local function wallet(account) return account == 'cash' and cash or bank end
NZ.Bridge.getIdentifier = function(src) return online[tonumber(src)] end
NZ.Bridge.getName = function(src) return names[tonumber(src)] end
NZ.Bridge.getCharacterName = function(id) return 'Name ' .. tostring(id) end
NZ.Bridge.getSourceByIdentifier = function(id) for src, cid in pairs(online) do if cid == id then return src end end return nil end
NZ.Bridge.getJob = function() return nil end
NZ.Bridge.getGang = function() return nil end
NZ.Bridge.getPlayer = function() return nil end
NZ.Bridge.notify = function(src, message, kind) TriggerClientEvent('nz:client:notify', src, { type = kind, message = message }) end
NZ.Bridge.getMoney = function(src, account) return wallet(account)[tonumber(src)] or 0 end
local reasons = {}           -- money reasons in call order: { op, src, reason }
NZ.Bridge.removeMoney = function(src, account, amount, reason)
  reasons[#reasons + 1] = { op = 'remove', src = tonumber(src), reason = reason }
  local w = wallet(account)
  src = tonumber(src)
  if not w[src] or w[src] < amount then return false end
  w[src] = w[src] - amount
  return true
end
NZ.Bridge.addMoney = function(src, account, amount, reason)
  reasons[#reasons + 1] = { op = 'add', src = tonumber(src), reason = reason }
  if payoutFails and tonumber(src) == 1 then return false end
  local w = wallet(account)
  src = tonumber(src)
  if not online[src] then return false end
  w[src] = (w[src] or 0) + amount
  return true
end
NZ.Bridge.pay = function(src, amount, reason)
  if NZ.Bridge.removeMoney(src, 'bank', amount, reason) then return true, 'bank' end
  return false, nil
end
NZ.Bridge.isAdmin = function() return false end

-- inventory with metadata: [src] = { { name, count, metadata, slot } }
local inv = { [1] = {}, [2] = {}, [3] = {}, [4] = {} }
local metaOn = true
local carryLimit = {}
local function invCopy(t) local o = {} for k, v in pairs(t or {}) do o[k] = v end return o end
local function matches(md, want)
  if want == nil then return true end
  for k, v in pairs(want) do if (md or {})[k] ~= v then return false end end
  return true
end
NZ.Inventory.name = function() return 'ox_inventory' end
NZ.Inventory.supportsMetadata = function() return metaOn end
NZ.Inventory.itemDefined = function() return true end
NZ.Inventory.items = function(src)
  local out = {}
  for slot, it in pairs(inv[tonumber(src)] or {}) do
    out[#out + 1] = { slot = slot, name = it.name, count = it.count, metadata = invCopy(it.metadata) }
  end
  table.sort(out, function(a, b) return a.slot < b.slot end)
  return out
end
NZ.Inventory.find = function(src, item, fn)
  local out = {}
  for _, e in ipairs(NZ.Inventory.items(src)) do
    if e.name == item and (not fn or fn(e.metadata, e) == true) then out[#out + 1] = e end
  end
  return out
end
NZ.Inventory.count = function(src, item, md)
  local n = 0
  for _, e in ipairs(NZ.Inventory.find(src, item)) do if matches(e.metadata, md) then n = n + e.count end end
  return n
end
NZ.Inventory.hasItem = function(src, item, count, md) return NZ.Inventory.count(src, item, md) >= (count or 1) end
NZ.Inventory.canCarry = function(src) return not carryLimit[tonumber(src)] end
NZ.Inventory.addItem = function(src, item, count, md)
  src = tonumber(src)
  if not inv[src] or carryLimit[src] then return false end
  local list = inv[src]
  local slot = 1
  while list[slot] do slot = slot + 1 end
  list[slot] = { name = item, count = count or 1, metadata = invCopy(md) }
  return true
end
NZ.Inventory.removeItem = function(src, item, count, md, slot)
  src = tonumber(src)
  local list = inv[src] or {}
  count = count or 1
  if slot then
    local it = list[slot]
    if not it or it.name ~= item or it.count < count or not matches(it.metadata, md) then return false end
    it.count = it.count - count
    if it.count <= 0 then list[slot] = nil end
    return true
  end
  for s, it in pairs(list) do
    if it.name == item and it.count >= count and matches(it.metadata, md) then
      it.count = it.count - count
      if it.count <= 0 then list[s] = nil end
      return true
    end
  end
  return false
end
NZ.Inventory.setMetadata = function() return true end
NZ.Inventory.protect = function() return true end
NZ.Inventory.registerUsable = function() return true end
local function count(src, item) return NZ.Inventory.count(src, item) end
local function give(src, item, n, md) NZ.Inventory.addItem(src, item, n or 1, md) end

-- dispatch, tow
local alerts = {}
NZ.Dispatch.alert = function(src, alert) alerts[#alerts + 1] = { src = src, alert = alert } return true end
local towed = {}
NZ.Tow.isTowing = function(entity) return towed[entity] == true end

-- locations
local function location(id, extra)
  local loc = {
    id = id, kind = 'garage', name = 'Garage ' .. tostring(id), vehicleType = 'car', enabled = true,
    source = 'personal', restriction = { type = 'everyone', rules = {}, identifiers = {} },
    openPoints = { { coords = vec3(10, 0, 0), radius = 4.0 } }, storePoints = {}, useOpenForStore = true,
    spawnPoints = { vector4(200, 200, 0, 90) },
  }
  for k, v in pairs(extra or {}) do loc[k] = v end
  return loc
end
local locations = { [1] = location(1, { name = 'Legion Square' }), [7] = location(7, { kind = 'private', name = 'Private lot' }) }
NZ.Locations.get = function(id) return locations[tonumber(id)] end
NZ.Locations.all = function(kind)
  local out = {}
  for _, l in pairs(locations) do if not kind or l.kind == kind then out[#out + 1] = l end end
  return out
end
NZ.Locations.resolveKey = function(key)
  local kind, id = Utils.key.parse(key)
  if kind == 'L' and locations[id] then return { kind = 'L', key = key, location = locations[id], locationId = id } end
  return nil
end
NZ.Locations.keyName = function(key)
  local r = NZ.Locations.resolveKey(key)
  return r and r.location.name or nil
end
NZ.Locations.capacity = function() return nil end
NZ.Private.role = function() return nil end
NZ.Private.groupsFor = function() return {} end
NZ.Private.getGroup = function() return nil end
NZ.Jobs.isSpawnerVehicle = function() return false end
NZ.Interiors.instances = {}

-- vehicle table + key state + events
local db = {}
local function addRow(plate, fields)
  local row = {
    plate = plate, dbPlate = plate, owner = 'CID001', model = 'sultan', hash = joaat_('sultan'),
    props = { model = joaat_('sultan'), plate = plate }, garageKey = 'L1', state = 'out', vehicleType = 'car',
    ownerType = 'player', mileage = 1200.5, fuel = 80, engine = 90, body = 95, blocked = false, lastOut = BASE_TIME,
    version = 0,
  }
  for k, v in pairs(fields or {}) do row[k] = v end
  db[plate] = row
end
addRow('ABC123')
addRow('FIN001', { finance = { balance = 1000, payment = 100, paymentsLeft = 10 } })
addRow('PRV001', { garageKey = 'G7' })
addRow('GAR001', { state = 'garaged' })
addRow('GAR002')
addRow('DEF456', { state = 'garaged' })
addRow('OTH001', { owner = 'CID003' })
addRow('XYZ789', { owner = 'CID003', state = 'garaged' })

local function copy(t) return Utils.deepCopy(t) end
NZ.DB.getVehicle = function(plate) local r = db[Utils.plate(plate) or ''] return r and copy(r) or nil end
NZ.DB.getVehiclesByOwner = function(id)
  local out = {}
  for _, r in pairs(db) do if r.owner == id then out[#out + 1] = copy(r) end end
  return out
end
NZ.DB.getVehiclesByPlates = function(plates)
  local out = {}
  for _, p in ipairs(plates) do if db[p] then out[#out + 1] = copy(db[p]) end end
  return out
end
NZ.DB.plateExists = function(plate) return db[Utils.plate(plate) or ''] ~= nil end
NZ.DB.updateVehicle = function(plate, fields)
  local r = db[Utils.plate(plate) or '']
  if not r then return false end
  for k, v in pairs(fields) do
    if v == false and (k == 'finance' or k == 'impound' or k == 'trailer' or k == 'damage' or k == 'lastOut' or k == 'nickname') then
      r[k] = nil
    elseif k ~= 'garageName' then
      r[k] = v
    end
  end
  return true
end
NZ.DB.getOutVehicles = function() return {} end
NZ.DB.countInGarage = function() return 0 end
local favourites = {}
NZ.DB.favourites = { get = function() return {} end, set = function(id, plate, v) favourites[id .. plate] = v return true end }
local shareRows = { ABC123 = { 'CID004' } }
NZ.DB.shares = {
  forPlate = function(plate)
    local out = {}
    for _, id in ipairs(shareRows[plate] or {}) do out[#out + 1] = { identifier = id, name = 'x' } end
    return out
  end,
  forIdentifier = function() return {} end,
  clear = function(plate) shareRows[plate] = nil return true end,
}
local history = {}
NZ.DB.events = {
  add = function(plate, kind, data)
    history[plate] = history[plate] or {}
    table.insert(history[plate], 1, { kind = kind, data = copy(data), at = os.time() })
    return #history[plate]
  end,
  list = function(plate, kind)
    local out = {}
    for _, e in ipairs(history[plate] or {}) do if not kind or e.kind == kind then out[#out + 1] = e end end
    return out
  end,
}
local secretStore = nil
NZ.DB.keys = {
  list = function() return {} end,
  forIdentifier = function() return {} end,
  add = function() return true end,
  remove = function() return true end,
  clear = function() return true end,
  count = function() return 0 end,
  state = function(plate)
    local r = db[plate]
    if not r then return false end
    return { version = r.version, mark = r.mark, owner = r.owner, job = r.job, gang = r.gang, markSupported = true }
  end,
  version = function(plate) local r = db[plate] return r and r.version or nil end,
  claim = function(plate, mark, initial)
    local r = db[plate]
    if not r then return false end
    if r.mark == mark then return false end
    r.version = r.mark == nil and initial or r.version + 1
    r.mark = mark
    return true
  end,
  bumpVersion = function(plate, mark, initial)
    local r = db[plate]
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
    secretStore = secretStore or candidate
    return secretStore
  end,
}

load_('server/access.lua')
load_('server/vehicles.lua')
load_('server/actions.lua')
load_('server/carlock/keys.lua')
load_('server/contracts.lua')
load_('server/fakeplates.lua')
NZ.Ready = true
local rateOpen = true
NZ.Access.rateLimit = function() return rateOpen end
advance(3000) -- key secret, restore threads

local Contracts, FakePlates, Vehicles = NZ.Contracts, NZ.FakePlates, NZ.Vehicles

local function cb(name, src, payload)
  local fn = callbacks[name]
  if not fn then failures[#failures + 1] = 'callback missing: ' .. name return { ok = false } end
  return run(fn, src, payload)
end

local SIG = 'M40 80L60 50L80 90L100 40L130 85L160 45L190 88L220 50L250 80'

---------------------------------------------------------------------------------------
-- Contracts
---------------------------------------------------------------------------------------

check(run(CarLock.mode) == 'physical', 'physical key mode')
local car, carNet = spawnVehicle('ABC123', 'sultan', vec3(4, 0, 0))
spawnVehicle('FIN001', 'sultan', vec3(6, 0, 0))
spawnVehicle('OTH001', 'sultan', vec3(5, 2, 0))
Vehicles.setOut('ABC123', { netId = carNet, entity = car, src = 1, identifier = 'CID001', garageKey = 'L1' })
check(run(CarLock.giveKeyItem, 1, 'ABC123', { model = 'sultan' }) == true, 'seller has a key item')
check(run(CarLock.hasKey, 1, 'ABC123') == true, 'seller key works')
give(1, 'vehicle_contract', 1)

-- 1. draft
check(run(Contracts.useItem, 1, 'vehicle_contract', 1, {}, 'contract') == true, 'blank contract use handled')
local draftEv = lastEvent('nz:client:contract:open', 1)
local draft = draftEv and draftEv.payload or {}
check(draft.mode == 'draft', 'draft opened for the seller')
local listed = {}
for _, v in ipairs(draft.vehicles or {}) do listed[v.plate] = v end
check(listed.ABC123 ~= nil and listed.ABC123.blocked == nil, 'own vehicle nearby listed and sellable')
check(listed.FIN001 ~= nil and type(listed.FIN001.blocked) == 'string', 'financed vehicle listed with its reason')
check(listed.OTH001 == nil, "someone else's vehicle is not listed")
check(listed.ABC123 and listed.ABC123.engine == 88 and listed.ABC123.body == 64, 'condition from the server entity')
local buyerIds = {}
for _, b in ipairs(draft.buyers or {}) do buyerIds[b.serverId] = b.name end
check(buyerIds[2] == 'Jade Ortiz' and buyerIds[4] ~= nil and buyerIds[3] == nil and buyerIds[1] == nil, 'buyers: nearby players only')
check(draft.maxPrice == 10000000 and draft.account == 'bank' and draft.expireSeconds == 120, 'draft limits from Config.Contracts')

-- 2. refusals
local function send(src, patch)
  local payload = { plate = 'ABC123', buyer = 2, price = 50000, terms = 'Sold as seen.', signature = SIG }
  for k, v in pairs(patch or {}) do payload[k] = v end
  return cb('nz:contract:send', src, payload)
end
check(send(3).ok == false, 'no draft session (no item use): refused')
check(send(1, { signature = 'M10 10' }).ok == false, 'a dot is not a signature')
check(send(1, { signature = SIG .. '<script>' }).ok == false, 'malformed signature refused')
check(send(1, { signature = string.rep('L10 10', 800) }).ok == false, 'signature over 4000 characters refused')
check(send(1, { price = 0 }).ok == false, 'price 0 refused')
check(send(1, { price = 10000001 }).ok == false, 'price over Config.Contracts.maxPrice refused')
check(send(1, { price = 12.5 }).ok == false, 'fractional price refused')
check(send(1, { buyer = 3 }).ok == false, 'buyer out of range refused')
check(send(1, { buyer = 1 }).ok == false, 'selling to yourself refused')
check(send(1, { buyer = 99 }).ok == false, 'offline buyer refused')
check(send(1, { plate = 'FIN001' }).ok == false, 'financed vehicle refused')
check(send(1, { plate = 'OTH001' }).ok == false, "someone else's vehicle refused")
check(send(1, { plate = 'GAR001' }).ok == false, 'vehicle not next to the seller refused')
check(send(1, { terms = string.rep('line\n', 14) }).ok == false, 'terms over 12 lines refused')
check(send(1, { terms = string.rep('x', 601) }).ok == false, 'terms over 600 characters refused')
local savedPos = playerPos[1]
spawnVehicle('PRV001', 'sultan', vec3(-3, 0, 0))
check(send(1, { plate = 'PRV001' }).ok == false, 'vehicle whose last garage the buyer cannot open refused')
-- only the vehicle itself counts: the tracked car is elsewhere, look-alikes stand next to the seller
entities[car].coords = vec3(80, 0, 0)
local lookalike = spawnVehicle('ABC123', 'blista', vec3(3, -1, 0))
local res = send(1)
check(res.ok == false and tostring(res.error):find('next to you', 1, true) ~= nil, 'another model wearing the plate: not the vehicle')
local twin = spawnVehicle('ABC123', 'sultan', vec3(3, 1, 0))
check(send(1).ok == false, 'untracked same-model copy while the tracked car is elsewhere: not the vehicle')
local refreshed = cb('nz:contract:refresh', 1, {})
local listedAgain = {}
for _, v in ipairs(refreshed.ok and refreshed.data.vehicles or {}) do listedAgain[v.plate] = true end
check(refreshed.ok and not listedAgain.ABC123, 'draft list: look-alikes are not offered')
DeleteEntity(lookalike)
DeleteEntity(twin)
entities[car].coords = vec3(4, 0, 0)
-- a registration parked in a garage (a copy stands next to the seller)
local garCopy = spawnVehicle('GAR001', 'sultan', vec3(2, -2, 0))
res = send(1, { plate = 'GAR001' })
check(res.ok == false and tostring(res.error):find('out of the garage', 1, true) ~= nil, 'garaged registration: refused')
DeleteEntity(garCopy)

-- 3. buyer cannot pay: one attempt, voided, nothing changes, blank given back
bank[2] = 100
res = send(1)
check(res.ok and type(res.data) == 'table' and type(res.data.contractId) == 'string', 'contract sent')
local id1 = res.data and res.data.contractId
local review = lastEvent('nz:client:contract:open', 2)
check(review and review.payload.mode == 'review' and review.payload.contractId == id1, 'buyer gets the review')
check(review and review.payload.canAfford == false, 'review says the buyer cannot afford it')
check(review and review.payload.expiresIn == 120 and review.payload.sellerSignature == SIG, 'review: countdown + seller signature')
check(send(1).ok == false, 'one pending contract per seller')
-- the buyer's balance poll
check(cb('nz:contract:balance', 3, { contractId = id1 }).ok == false, 'balance: only the buyer may ask')
local bal = cb('nz:contract:balance', 2, { contractId = id1 })
check(bal.ok and bal.data.canAfford == false, 'balance: cannot afford yet')
bank[2] = 60000
bal = cb('nz:contract:balance', 2, { contractId = id1 })
check(bal.ok and bal.data.canAfford == true, 'balance: money arrived, can afford now')
bank[2] = 100
-- the seller closed the window: using a blank contract again reopens it in its sent state
run(Contracts.useItem, 1, 'vehicle_contract', 1, {}, 'contract')
local reopened = lastEvent('nz:client:contract:open', 1).payload
local sentInfo = type(reopened.sent) == 'table' and reopened.sent or {}
check(reopened.mode == 'draft' and sentInfo.id == id1 and sentInfo.price == 50000 and sentInfo.signature == SIG
  and sentInfo.buyer and sentInfo.buyer.serverId == 2 and sentInfo.plate == 'ABC123'
  and type(sentInfo.expiresIn) == 'number' and sentInfo.expiresIn <= 120, 'draft reopened in its sent state')
check(#reopened.vehicles == 1 and reopened.vehicles[1].plate == 'ABC123', 'reopened draft: the contract vehicle')
check(cb('nz:contract:sign', 3, { contractId = id1, signature = SIG }).ok == false, 'only the buyer can sign')
check(cb('nz:contract:sign', 2, { contractId = id1, signature = 'M1 1' }).ok == false, 'buyer needs a real signature')
check(Contracts.pending()[1] and Contracts.pending()[1].state == 'pending', 'a bad signature does not use the contract up')
res = cb('nz:contract:sign', 2, { contractId = id1, signature = SIG })
check(res.ok == false and tostring(res.error):find('afford', 1, true) ~= nil, 'buyer cannot pay: refused')
check(db.ABC123.owner == 'CID001' and bank[1] == 1000 and bank[2] == 100, 'cannot pay: owner and money unchanged')
check(count(1, 'vehicle_contract') == 1, 'cannot pay: the blank contract is given back')
check(notified(1, 'could not afford'), 'cannot pay: the seller is told')
check(lastEvent('nz:client:contract:status', 1).payload.status == 'failed', 'cannot pay: status pushed to the seller')
check(cb('nz:contract:sign', 2, { contractId = id1, signature = SIG }).ok == false, 'reuse after a failed attempt refused')
bank[2] = 60000

-- 4. seller moved away
res = send(1)
local id2 = res.data and res.data.contractId
check(res.ok and id2 ~= id1, 'second contract sent (new id)')
playerPos[1] = vec3(40, 0, 0)
res = cb('nz:contract:sign', 2, { contractId = id2, signature = SIG })
check(res.ok == false, 'seller moved away: refused')
check(db.ABC123.owner == 'CID001' and bank[2] == 60000 and count(1, 'vehicle_contract') == 1, 'seller moved away: nothing changed')
playerPos[1] = savedPos

-- 5. vehicle financed after sending
res = send(1)
local id3 = res.data and res.data.contractId
db.ABC123.finance = { balance = 500, payment = 50, paymentsLeft = 10 }
res = cb('nz:contract:sign', 2, { contractId = id3, signature = SIG })
check(res.ok == false and db.ABC123.owner == 'CID001', 'financed after sending: refused')
db.ABC123.finance = nil

-- 6. expiry
res = send(1)
local id4 = res.data and res.data.contractId
advance(121000)
check(lastEvent('nz:client:contract:status', 1).payload.status == 'expired', 'expiry pushed to the seller')
check(lastEvent('nz:client:contract:status', 2).payload.status == 'expired', 'expiry pushed to the buyer')
check(lastEvent('nz:client:contract:status', 1).payload.resendIn == 60
  and lastEvent('nz:client:contract:status', 2).payload.resendIn == nil, 'expiry: the seller is told the resend cooldown')
check(notified(1, 'expired') and notified(2, 'expired'), 'expiry: both notified')
local statusCount = countEvents('nz:client:contract:status', 2)
check(cb('nz:contract:sign', 2, { contractId = id4, signature = SIG }).ok == false, 'expired contract cannot be signed')
check(countEvents('nz:client:contract:status', 2) == statusCount, 'signing an expired contract changes nothing more')
-- the draft session lasts 15 minutes after the item use: use the item again
run(Contracts.useItem, 1, 'vehicle_contract', 1, {}, 'contract')
-- an expired contract is a "no": the same buyer cannot be sent another one for a minute
res = send(1)
check(res.ok == false and tostring(res.error):find('did not sign', 1, true) ~= nil
  and not tostring(res.error):find('turned down', 1, true), 'resend after expiry within the cooldown: refused (not "turned down")')
advance(60000)

-- 7. decline / withdraw / player leaving
res = send(1)
check(cb('nz:contract:decline', 2, { contractId = res.data.contractId }).ok == true, 'buyer declines')
check(notified(1, 'declined'), 'decline: seller notified')
check(lastEvent('nz:client:contract:status', 1).payload.status == 'declined'
  and lastEvent('nz:client:contract:status', 1).payload.resendIn == 60, 'decline: the seller is told the resend cooldown')
res = send(1)
check(res.ok == false and tostring(res.error):find('turned down', 1, true) ~= nil, 'resend to the buyer who declined: refused for a while')
res = send(1, { buyer = 4 })
check(res.ok == true, 'another buyer can get a contract during the cooldown')
cb('nz:contract:decline', 1, { contractId = res.data and res.data.contractId })
advance(60000)
res = send(1)
check(res.ok == true, 'after the cooldown the buyer can get a contract again')
check(cb('nz:contract:decline', 1, { contractId = res.data.contractId }).ok == true, 'seller withdraws')
check(notified(2, 'withdrew'), 'withdraw: buyer notified')
check(lastEvent('nz:client:contract:status', 2).payload.status == 'withdrawn', 'withdraw: status pushed')
check(lastEvent('nz:client:contract:status', 1).payload.resendIn == nil, 'withdraw: no resend cooldown')
res = send(1)
check(res.ok == true, 'a withdrawal starts no cooldown')
local idDrop = res.data.contractId
online[2] = nil
TriggerEvent('playerDropped', 'quit')
for _, fn in ipairs(handlers.playerDropped or {}) do source = 2 fn('quit') end -- luacheck: ignore 111
online[2] = 'CID002'
check(notified(1, 'left'), 'buyer left: seller notified')
check(cb('nz:contract:sign', 2, { contractId = idDrop, signature = SIG }).ok == false, 'contract of a player who left is void')

-- 8. success
res = send(1, { terms = 'Sold as seen.\nKeys on signing.' })
local id5 = res.data.contractId
local oldKey = NZ.Inventory.find(1, 'vehicle_key')[1]
-- another operation holds the vehicle at this instant: nothing checked, the attempt is kept
local holding = true
CreateThread(function()
  Vehicles.withLock('ABC123', function() while holding do Wait(100) end end)
end)
advance(100)
local sellerStatus = countEvents('nz:client:contract:status', 1)
res = cb('nz:contract:sign', 2, { contractId = id5, signature = SIG })
check(res.ok == false and tostring(res.error):find('busy', 1, true) ~= nil, 'vehicle busy: refused with the busy message')
check(Contracts.pending()[1] and Contracts.pending()[1].id == id5 and Contracts.pending()[1].state == 'pending',
  'vehicle busy: the contract stays pending (the attempt is not used up)')
check(countEvents('nz:client:contract:status', 1) == sellerStatus and db.ABC123.owner == 'CID001'
  and count(1, 'vehicle_contract') == 1, 'vehicle busy: nothing told, charged or consumed')
holding = false
advance(200)
res = cb('nz:contract:sign', 2, { contractId = id5, signature = SIG })
check(res.ok == true and type(res.data) == 'table' and type(res.data.signedAt) == 'number', 'buyer signs and pays')
check(res.data and res.data.key == 'item' and res.data.copy == true, 'sign result: key item and signed copy given')
check(db.ABC123.owner == 'CID002', 'owner changed to the buyer')
check(bank[2] == 10000 and bank[1] == 51000, 'buyer charged, seller paid (Config.Contracts.account)')
check(count(1, 'vehicle_contract') == 0, 'blank contract consumed')
check(shareRows.ABC123 == nil, 'shares cleared')
check(favourites['CID001ABC123'] == false, "seller's favourite removed")
local entry = history.ABC123 and history.ABC123[1]
check(entry and entry.data.via == 'contract' and entry.data.contractId == id5 and entry.data.price == 50000
  and entry.data.identifier == 'CID002' and entry.data.from == 'CID001', 'ownership history entry via contract')
check(entry and entry.data.signedAt == res.data.signedAt and entry.data.model == 'sultan'
  and type(entry.data.digest) == 'string' and #entry.data.digest == 8, 'history keeps signedAt, model and the terms / signatures digest')
local saleReasons = {}
for _, r in ipairs(reasons) do saleReasons[r.op .. r.src .. ':' .. tostring(r.reason)] = true end
check(saleReasons['remove2:nayzeee-garages:vehicle-purchase-contract'] and saleReasons['add1:nayzeee-garages:vehicle-sale-contract'],
  'contract money reasons: purchase for the buyer, sale for the seller')
check(Vehicles.out.ABC123 and Vehicles.out.ABC123.identifier == 'CID002', 'tracked vehicle follows the new owner')
check(Vehicles.out.ABC123 and Vehicles.out.ABC123.src == 2, 'tracked vehicle: the buyer has it out now (key bridges trust out.src)')
check(entry and entry.data.digestVersion == 2, 'history entry: digest version 2')
check(oldKey ~= nil and not run(CarLock.verifyKeyItem, oldKey.metadata, 'ABC123'), "seller's old key no longer works (rekey)")
check(run(CarLock.hasKey, 1, 'ABC123') == false, 'seller has no key any more')
local buyerHas, buyerKind = run(CarLock.hasKey, 2, 'ABC123')
check(buyerHas == true and buyerKind == 'item', 'buyer got a key item (physical mode)')
local copies = { NZ.Inventory.find(1, 'signed_contract')[1], NZ.Inventory.find(2, 'signed_contract')[1] }
check(copies[1] and copies[2], 'both parties got a signed copy')
local md = copies[2] and copies[2].metadata or {}
check(md.contractId == id5 and md.plate == 'ABC123' and md.price == 50000 and md.copy == 'buyer'
  and md.sellerSignature == SIG and md.buyerSignature == SIG and md.seller == 'Marcus Hale', 'signed copy metadata')
check(lastLog('vehicle.sell', 'action', 'contract') ~= nil, 'sale logged')
check(lastEvent('nz:client:contract:status', 1).payload.status == 'signed', 'seller window told: signed')
check(lastEvent('nz:client:contract:status', 1).payload.copy == true, 'seller window told: signed copy given')

-- 9. reuse attempts
check(cb('nz:contract:sign', 2, { contractId = id5, signature = SIG }).ok == false, 'signed contract cannot be signed again')
check(send(1).ok == false, 'no blank contract left: cannot send')

-- 10. signed copy view
run(Contracts.useItem, 2, 'signed_contract', 1, md, 'signedContract')
local viewEv = lastEvent('nz:client:contract:open', 2)
check(viewEv and viewEv.payload.mode == 'view' and viewEv.payload.verified == true, 'signed copy opens verified')
check(viewEv and viewEv.payload.buyerSignature == SIG and viewEv.payload.price == 50000, 'view shows the contract')
local edited = copy(md)
edited.price = 1
run(Contracts.useItem, 2, 'signed_contract', 1, edited, 'signedContract')
check(lastEvent('nz:client:contract:open', 2).payload.verified == false, 'edited copy is not verified')
edited = copy(md)
edited.sellerSignature = 'M1 1<img onerror=x>'
edited.seller = '<b>Hacker</b>'
run(Contracts.useItem, 2, 'signed_contract', 1, edited, 'signedContract')
local v2 = lastEvent('nz:client:contract:open', 2).payload
check(v2.sellerSignature == '' and not tostring(v2.seller.name):find('<', 1, true), 'copy fields cleaned again')
run(Contracts.useItem, 2, 'signed_contract', 1, { plate = 'x' }, 'signedContract')
check(notified(2, 'unreadable'), 'garbage metadata: error notification')
local function verifiedWith(patch)
  local m = copy(md)
  for k, v in pairs(patch) do m[k] = v end
  run(Contracts.useItem, 2, 'signed_contract', 1, m, 'signedContract')
  return lastEvent('nz:client:contract:open', 2).payload.verified
end
check(verifiedWith({}) == true, 'untouched copy verified')
check(verifiedWith({ buyer = 'Someone Else' }) == false, 'edited buyer name: not verified')
check(verifiedWith({ seller = 'Someone Else' }) == false, 'edited seller name: not verified')
check(verifiedWith({ terms = 'Sold with a full warranty.' }) == false, 'edited terms: not verified')
check(verifiedWith({ signedAt = md.signedAt - 86400 }) == false, 'edited date: not verified')
check(verifiedWith({ model = 'adder' }) == false, 'edited model: not verified')
check(verifiedWith({ buyerSignature = 'M10 10L200 100L300 20' }) == false, 'replaced signature: not verified')
check(verifiedWith({ hash = joaat('adder') }) == false, 'edited vehicle hash (the label shown): not verified')
check(verifiedWith({ mileage = (tonumber(md.mileage) or 0) + 1000 }) == false, 'edited mileage: not verified')
check(verifiedWith({ engine = 100, body = 100 }) == false, 'edited condition: not verified')
check(verifiedWith({ account = 'cash' }) == false, 'edited payment account: not verified')
check(verifiedWith({ createdAt = (tonumber(md.createdAt) or 0) - 3600 }) == false, 'edited date written: not verified')
-- metadata coming back from an inventory as JSON: 1234.0 read as 1234, integers as floats
check(verifiedWith({ mileage = (tonumber(md.mileage) or 0) + 0.0, hash = (tonumber(md.hash) or 0) + 0.0,
  engine = (tonumber(md.engine) or 0) + 0.0, createdAt = (tonumber(md.createdAt) or 0) + 0.0 }) == true,
  'number forms after a JSON round trip: still verified')
-- a copy signed before the digest covered these fields (no digestVersion) keeps verifying
local function fnv(text)
  local h = 2166136261
  for i = 1, #text do h = ((h ~ text:byte(i)) * 16777619) & 0xFFFFFFFF end
  return ('%08x'):format(h)
end
local v2Data = copy(history.ABC123[1].data)
history.ABC123[1].data.digestVersion = nil
history.ABC123[1].data.digest = fnv(table.concat({ md.terms, md.sellerSignature, md.buyerSignature }, '\n'))
check(verifiedWith({}) == true, 'version 1 copy (terms and signatures only): still verified')
check(verifiedWith({ terms = 'Sold with a full warranty.' }) == false, 'version 1 copy: edited terms still caught')
history.ABC123[1].data = v2Data

-- 11. disabled
Config.Contracts.enabled = false
give(1, 'vehicle_contract', 1)
run(Contracts.useItem, 1, 'vehicle_contract', 1, {}, 'contract')
check(notified(1, 'disabled'), 'disabled: blank contract does nothing')
Config.Contracts.enabled = true

-- 12. garage sale helper and its rollback
local garRow = NZ.DB.getVehicle('GAR001')
local okSale = run(NZ.Actions.sellVehicle, garRow, { source = 1, identifier = 'CID001', name = 'Marcus Hale' },
  { source = 2, identifier = 'CID002', name = 'Jade Ortiz' }, { via = 'sale', price = 100 })
check(okSale == true and db.GAR001.owner == 'CID002' and bank[2] == 9900, 'garage sale helper: sold')
check(history.GAR001 and history.GAR001[1].data.via == 'sale', 'garage sale helper: history via sale')
payoutFails = true
db.GAR001.owner = 'CID001'
garRow = NZ.DB.getVehicle('GAR001')
local okFail, _, code = run(NZ.Actions.sellVehicle, garRow, { source = 1, identifier = 'CID001', name = 'Marcus Hale' },
  { source = 2, identifier = 'CID002', name = 'Jade Ortiz' }, { via = 'sale', price = 100 })
check(okFail == false and code == 'error' and db.GAR001.owner == 'CID001' and bank[2] == 9900, 'payout failure: sale reverted, buyer refunded')
payoutFails = false
-- the payout and its rollback both fail (database): the buyer paid and keeps it, logged for staff
payoutFails = true
db.GAR001.owner = 'CID001'
garRow = NZ.DB.getVehicle('GAR001')
local updateVehicle = NZ.DB.updateVehicle
NZ.DB.updateVehicle = function(plate, fields)
  if fields.owner == 'CID001' then return false end
  return updateVehicle(plate, fields)
end
local okUnpaid, _, _, unpaid = run(NZ.Actions.sellVehicle, garRow, { source = 1, identifier = 'CID001', name = 'Marcus Hale' },
  { source = 2, identifier = 'CID002', name = 'Jade Ortiz' }, { via = 'sale', price = 100 })
check(okUnpaid == true and unpaid == true and db.GAR001.owner == 'CID002' and bank[2] == 9800,
  'payout and rollback failed: the buyer keeps the vehicle they paid for, flagged unpaid')
check(lastLog('security.sell', 'reason', 'payout and rollback failed: buyer keeps the vehicle, not refunded, seller unpaid') ~= nil,
  'payout and rollback failed: logged for staff')
NZ.DB.updateVehicle = updateVehicle
payoutFails = false
bank[2] = 9900
-- garage sale of a vehicle standing in the world: the buyer gets a key, the seller loses theirs
addRow('OUT001')
local outCar, outNet = spawnVehicle('OUT001', 'sultan', vec3(3, -3, 0))
Vehicles.setOut('OUT001', { netId = outNet, entity = outCar, src = 1, identifier = 'CID001', garageKey = 'L1' })
check(run(CarLock.giveKeyItem, 1, 'OUT001', { model = 'sultan' }) == true, 'out vehicle: seller has a key item')
local outKey = NZ.Inventory.find(1, 'vehicle_key')
outKey = outKey[#outKey]
local outRow = NZ.DB.getVehicle('OUT001')
check(run(NZ.Actions.sellVehicle, outRow, { source = 1, identifier = 'CID001', name = 'Marcus Hale' },
  { source = 2, identifier = 'CID002', name = 'Jade Ortiz' }, { via = 'sale', price = 100 }) == true, 'out vehicle: sold')
check(Vehicles.out.OUT001.src == 2 and Vehicles.out.OUT001.identifier == 'CID002', 'out vehicle: tracked entry moves to the buyer')
check(run(NZ.Actions.handBuyerKey, 2, 'OUT001', 'sultan', 'sale') == 'item', 'handBuyerKey: key item in physical mode')
local outHas, outKind = run(CarLock.hasKey, 2, 'OUT001')
check(outHas == true and outKind == 'item', 'out vehicle: the buyer holds a working key')
check(run(CarLock.hasKey, 1, 'OUT001') == false and not run(CarLock.verifyKeyItem, outKey.metadata, 'OUT001'),
  "out vehicle: the seller's key stopped working")
local carLockOnFn = NZ.CarLock.enabled
NZ.CarLock.enabled = function() return false end
check(run(NZ.Actions.handBuyerKey, 2, 'OUT001', 'sultan', 'sale') == nil, 'handBuyerKey: nothing when the built-in car lock is off')
NZ.CarLock.enabled = carLockOnFn
local gsReasons = {}
for _, r in ipairs(reasons) do gsReasons[r.op .. r.src .. ':' .. tostring(r.reason)] = true end
check(gsReasons['remove2:nayzeee-garages:vehicle-purchase'] and gsReasons['add1:nayzeee-garages:vehicle-sale']
  and gsReasons['add2:nayzeee-garages:vehicle-purchase-refund'], 'garage sale money reasons unchanged (purchase / sale / purchase-refund)')

-- 13. external key resource (built-in car lock off): keys move with the sale
addRow('EXT001')
local ext, extNet = spawnVehicle('EXT001', 'sultan', vec3(-2, 2, 0))
Vehicles.setOut('EXT001', { netId = extNet, entity = ext, src = 1, identifier = 'CID001', garageKey = 'L1' })
local carLockEnabled = NZ.CarLock.enabled
local keysServer = { give = NZ.KeysServer.give, remove = NZ.KeysServer.remove, resource = NZ.KeysServer.resource }
local serverKeyCalls = {}
NZ.CarLock.enabled = function() return false end
NZ.KeysServer.resource = function() return 'qb-vehiclekeys' end
NZ.KeysServer.give = function(src, netId, plate) serverKeyCalls[#serverKeyCalls + 1] = { 'give', src, netId, plate } return false end
NZ.KeysServer.remove = function(src, netId, plate) serverKeyCalls[#serverKeyCalls + 1] = { 'remove', src, netId, plate } return false end
run(Contracts.useItem, 1, 'vehicle_contract', 1, {}, 'contract')
res = send(1, { plate = 'EXT001', price = 5000 })
check(res.ok == true, 'external keys: contract sent')
res = cb('nz:contract:sign', 2, { contractId = res.data and res.data.contractId, signature = SIG })
check(res.ok == true and res.data.key == 'external' and db.EXT001.owner == 'CID002', 'external keys: sold, key kind external')
local bk, sk = lastEvent('nz:client:contract:keys', 2), lastEvent('nz:client:contract:keys', 1)
check(bk and bk.payload.give == true and bk.payload.plate == 'EXT001' and bk.payload.netId == extNet, 'external keys: buyer client gets the keys')
check(sk and sk.payload.give == false and sk.payload.plate == 'EXT001', "external keys: seller client loses theirs")
check(#serverKeyCalls == 2 and serverKeyCalls[1][1] == 'give' and serverKeyCalls[1][2] == 2
  and serverKeyCalls[2][1] == 'remove' and serverKeyCalls[2][2] == 1, 'external keys: server-side systems asked first')
NZ.KeysServer.resource = function() return nil end
give(1, 'vehicle_contract', 1)
addRow('EXT002')
local ext2, ext2Net = spawnVehicle('EXT002', 'sultan', vec3(-2, -2, 0))
Vehicles.setOut('EXT002', { netId = ext2Net, entity = ext2, src = 1, identifier = 'CID001', garageKey = 'L1' })
run(Contracts.useItem, 1, 'vehicle_contract', 1, {}, 'contract')
local keyEvents = countEvents('nz:client:contract:keys')
res = send(1, { plate = 'EXT002', price = 100 })
res = cb('nz:contract:sign', 2, { contractId = res.data and res.data.contractId, signature = SIG })
check(res.ok == true and res.data.key == nil and countEvents('nz:client:contract:keys') == keyEvents, 'no key system: no key promised')
NZ.CarLock.enabled = carLockEnabled
NZ.KeysServer.give, NZ.KeysServer.remove, NZ.KeysServer.resource = keysServer.give, keysServer.remove, keysServer.resource

---------------------------------------------------------------------------------------
-- Fake plates
---------------------------------------------------------------------------------------

Config.FakePlates.screwdriverBreakChance = 0
local gar2, gar2Net = spawnVehicle('GAR002', 'sultan', vec3(10, 0, 0), 0.0)
Vehicles.setOut('GAR002', { netId = gar2Net, entity = gar2, src = 1, identifier = 'CID001', garageKey = 'L1' })
run(CarLock.onVehicleOut, 1, gar2, 'GAR002')
check(run(CarLock.hasKey, 1, 'GAR002') == true, 'owner key for the fake plate test car')
give(1, 'fake_plate', 3)
give(1, 'screwdriver', 1)
playerPos[1] = vec3(10, -2.6, 0) -- behind (heading 0 faces +y)

run(FakePlates.useItem, 1)
check(lastEvent('nz:client:fakeplates:use', 1) ~= nil, 'fake plate item: client picks the vehicle')

local function start(src, netId, action) return cb('nz:fakeplates:start', src, { netId = netId, action = action or 'install' }) end
local function finish(src, token, cancel) return cb('nz:fakeplates:finish', src, { token = token, cancel = cancel }) end

playerPos[1] = vec3(10, 2.6, 0)
check(start(1, gar2Net).ok == false, 'in front of the vehicle: refused')
playerPos[1] = vec3(10, -2.6, 0)
NZ.Inventory.removeItem(1, 'screwdriver', 1)
check(start(1, gar2Net).ok == false, 'no screwdriver: refused')
give(1, 'screwdriver', 1)
seat(4, gar2)
check(start(1, gar2Net).ok == false, 'someone inside: refused')
seat(4, nil)
towed[gar2] = true
check(start(1, gar2Net).ok == false, 'being towed: refused')
towed[gar2] = nil
check(start(3, gar2Net).ok == false, 'far away player: refused')
playerPos[1] = vec3(10 + 1.9, -2.6, 0)
check(start(1, gar2Net).ok == false, 'rear corner, off the long axis: refused')
playerPos[1] = vec3(10 + 1.4, -0.6, 0)
check(start(1, gar2Net).ok == false, 'beside the rear wheel (not behind): refused')
playerPos[1] = vec3(10, -2.6, 0)

res = start(1, gar2Net)
check(res.ok and res.data.duration == 6000, 'install started (server timer)')
check(start(4, gar2Net).ok == false, 'second worker on the same vehicle: refused')
local early = finish(1, res.data.token)
check(early.ok == false, 'finished too early: refused')
check(finish(1, res.data.token).ok == false, 'the attempt is used up')
check(GetVehicleNumberPlateText(gar2):match('^GAR002') ~= nil and count(1, 'fake_plate') == 3, 'nothing changed')

res = start(1, gar2Net)
advance(6000)
local done = finish(1, res.data.token)
local fake = done.ok and done.data.plate or nil
check(done.ok and type(fake) == 'string', 'fake plate installed')
check(fake and fake:match('^%d%d%u%u%u%d%d%d$') ~= nil, 'plate follows Config.FakePlates.pattern')
check(Utils.plate(GetVehicleNumberPlateText(gar2)) == fake, 'the vehicle shows the fake plate')
check(NZ.DB.getVehicle(fake) == nil, 'police plate check: the fake plate is not registered')
check(run(CarLock.realPlate, gar2) == 'GAR002', 'keys / locks: real plate kept (NZ.CarLock.realPlate)')
check(FakePlates.plateOf(gar2) == 'GAR002' and FakePlates.isFake(gar2), 'NZ.FakePlates.plateOf = real plate')
check(Entity(gar2).state.nzPlate == 'GAR002' and Entity(gar2).state.nzFakePlate == fake, 'state bags nzPlate / nzFakePlate')
check(run(CarLock.hasKey, 1, 'GAR002') == true, 'owner key still works under the fake plate')
check(run(CarLock.findVehicle, 'GAR002', 1) == gar2, 'findVehicle by the real plate')
check(run(CarLock.plateFromText, fake, 1) == 'GAR002', "other scripts' plate text maps to the real plate")
local found, rec = FakePlates.lookup(fake)
check(found == gar2 and rec.real == 'GAR002', 'NZ.FakePlates.lookup(fake)')
check(count(1, 'fake_plate') == 2 and count(1, 'screwdriver') == 1, 'fake plate consumed, screwdriver kept')
check(lastLog('vehicle.fakeplate', 'action', 'install') ~= nil, 'install logged')

Entity(gar2).state:set('nzFakePlate', 'HACKED', true)
advance(200)
check(Entity(gar2).state.nzFakePlate == fake, 'client change of nzFakePlate put back')

res = start(1, gar2Net)
check(res.ok == false, 'second fake plate on the same vehicle refused')

-- contract draft: the fake-plated vehicle cannot be sold
give(1, 'vehicle_contract', 1)
playerPos[1] = vec3(10, -2.6, 0)
run(Contracts.useItem, 1, 'vehicle_contract', 1, {}, 'contract')
local d2 = lastEvent('nz:client:contract:open', 1).payload
local gar2Listed = nil
for _, v in ipairs(d2.vehicles or {}) do if v.plate == 'GAR002' then gar2Listed = v end end
check(gar2Listed and type(gar2Listed.blocked) == 'string' and gar2Listed.blocked:find('fake', 1, true), 'contract: fake-plated vehicle blocked')

-- pattern collisions: never a registered plate, never a plate in the world
local npc, npcNet = spawnVehicle('NPC111', 'blista', vec3(20, 0, 0), 0.0)
playerPos[1] = vec3(20, -2.6, 0)
Config.FakePlates.pattern = 'XYZ789' -- a registered plate (no wildcard characters)
res = start(1, npcNet)
advance(6000)
done = finish(1, res.data.token)
check(done.ok == false and count(1, 'fake_plate') == 2, 'pattern only giving a registered plate: refused, item kept')
Config.FakePlates.pattern = 'ZZZ999'
res = start(1, npcNet)
advance(6000)
done = finish(1, res.data.token)
check(done.ok and done.data.plate == 'ZZZ999', 'NPC vehicle gets the fake plate')
check(Entity(npc).state.nzPlate == 'NPC111', 'NPC vehicle: nzPlate set to its real plate')
check(run(CarLock.realPlate, npc) == 'NPC111', 'NPC vehicle: NZ.CarLock.realPlate is the real plate')
local _, npc2Net = spawnVehicle('NPC222', 'blista', vec3(30, 0, 0), 0.0)
playerPos[1] = vec3(30, -2.6, 0)
res = start(1, npc2Net)
advance(6000)
check(finish(1, res.data.token).ok == false, 'plate already on a vehicle in the world: refused')
Config.FakePlates.pattern = '11AAA111'

-- removal
playerPos[1] = vec3(20, -2.6, 0)
local before = count(1, 'fake_plate')
res = start(1, npcNet, 'remove')
check(res.ok and res.data.duration == 5000, 'removal started')
advance(5000)
done = finish(1, res.data.token)
check(done.ok and done.data.plate == 'NPC111' and Utils.plate(GetVehicleNumberPlateText(npc)) == 'NPC111', 'real plate restored')
check(count(1, 'fake_plate') == before + 1, 'fake plate item returned')
check(Entity(npc).state.nzFakePlate == nil and Entity(npc).state.nzPlate == nil, 'state bags cleared')
check(not FakePlates.isFake(npc), 'no fake plate any more')
check(start(1, npcNet, 'remove').ok == false, 'nothing to remove: refused')

-- screwdriver breaking (and an ESX style pattern with a space)
Config.FakePlates.screwdriverBreakChance = 100
Config.FakePlates.pattern = 'AAA 111'
res = start(1, npcNet)
advance(6000)
done = finish(1, res.data.token)
check(done.ok and count(1, 'screwdriver') == 0, 'screwdriver can break')
check(done.ok and tostring(done.data.plate):match('^%u%u%u %d%d%d$') ~= nil, "pattern 'AAA 111' keeps its space")
Config.FakePlates.pattern = '11AAA111'
check(notified(1, 'screwdriver broke'), 'player told the screwdriver broke')
Config.FakePlates.screwdriverBreakChance = 0
give(1, 'screwdriver', 1)

-- resource restart keeps fake plates (same server session)
local npcFake = Utils.plate(GetVehicleNumberPlateText(npc))
TriggerEvent('onResourceStop', 'nayzeee-garages')
check(kvp['nz:fakeplates:session'] ~= nil, 'snapshot written on stop')
load_('server/fakeplates.lua')
advance(500)
check(FakePlates.realPlateOf(npc) == 'NPC111' and FakePlates.isFake(npc), 'fake plate restored after a restart')
check(FakePlates.realPlateOf(gar2) == 'GAR002', 'garage vehicle fake plate restored after a restart')
check(npcFake ~= 'NPC111', 'npc still shows its fake plate')
-- the garage adopts the fake-plated vehicle back by its real plate: no second copy is spawned
Vehicles.clearOut('GAR002')
local getOut = NZ.DB.getOutVehicles
NZ.DB.getOutVehicles = function() return { copy(db.GAR002) } end
run(Vehicles.boot)
check(Vehicles.out.GAR002 and Vehicles.out.GAR002.entity == gar2 and Vehicles.out.GAR002.adopted == true,
  'restart: fake-plated garage vehicle adopted by its real plate')
check(Entity(gar2).state.nzPlate == 'GAR002', 'restart: nzPlate is the real plate')
Vehicles.out.GAR002.entity = nil -- only the network id known
local isOutNow, outEntity = Vehicles.isOut('GAR002')
check(isOutNow and outEntity == gar2, 'restart: the registration is out (garage / phone see it, no duplicate)')
NZ.DB.getOutVehicles = getOut

-- garage store: the fake plate comes off, the real plate is saved, the item comes back
playerPos[1] = vec3(10, 0, 0)
seat(1, gar2)
local session = { location = locations[1], garageKey = 'L1', locationId = 1 }
local fakeBefore = count(1, 'fake_plate')
res = run(Vehicles.store, 1, session, { netId = gar2Net, data = { props = { plate = fake, model = joaat_('sultan') }, fuel = 70 } })
check(res.ok == true, 'fake-plated garage vehicle stored')
check(db.GAR002.state == 'garaged' and db.GAR002.props.plate == 'GAR002', 'stored with its real plate')
check(entities[gar2] == nil, 'entity removed')
check(count(1, 'fake_plate') == fakeBefore + 1, 'fake plate returned on store (returnOnStore)')
check(lastLog('vehicle.store') and lastLog('vehicle.store').data.fakePlate == true, 'store log notes the fake plate')
seat(1, nil)

-- garage retrieve: another model showing the plate is never deleted
local other = spawnVehicle('DEF456', 'blista', vec3(50, 50, 0), 0.0)
playerPos[1] = vec3(10, 0, 0)
rateOpen = true
res = run(Vehicles.retrieve, 1, 'DEF456', session, { spawnIndex = 1 })
check(res.ok == true, 'retrieve works while another model shows the plate')
check(entities[other] ~= nil, "another player's car of another model is not deleted")
Vehicles.clearOut('DEF456')
db.DEF456.state = 'garaged'
-- an untracked copy of the same model is a duplicate and is removed
local dupe = spawnVehicle('DEF456', 'sultan', vec3(60, 60, 0), 0.0)
res = run(Vehicles.retrieve, 1, 'DEF456', session, { spawnIndex = 1 })
check(res.ok == true and entities[dupe] == nil, 'same-model untracked copy removed before retrieve')
check(entities[other] ~= nil, 'the other model is still there')
Vehicles.clearOut('DEF456')
db.DEF456.state = 'garaged'
-- the vehicle itself, untracked under a fake plate (e.g. after a restart), is found by its real plate
local hidden, hiddenNet = spawnVehicle('DEF456', 'sultan', vec3(70, 0, 0), 0.0)
playerPos[1] = vec3(70, -2.6, 0)
res = start(1, hiddenNet)
advance(6000)
done = finish(1, res.data.token)
check(done.ok and Utils.plate(GetVehicleNumberPlateText(hidden)) ~= 'DEF456', 'copy now wears a fake plate')
playerPos[1] = vec3(10, 0, 0)
res = run(Vehicles.retrieve, 1, 'DEF456', session, { spawnIndex = 1 })
check(res.ok == true and entities[hidden] == nil, 'fake-plated copy of the vehicle found by its real plate and removed')

-- external key resource keyed on the plate text (built-in car lock off)
addRow('KEY001')
local kc, kcNet = spawnVehicle('KEY001', 'sultan', vec3(90, 0, 0), 0.0)
local carLockOn, keysResource = NZ.CarLock.enabled, NZ.KeysServer.resource
NZ.CarLock.enabled = function() return false end
NZ.KeysServer.resource = function() return 'qb-vehiclekeys' end
give(1, 'fake_plate', 1)
playerPos[1] = vec3(90, -2.6, 0)
res = start(1, kcNet)
advance(6000)
done = finish(1, res.data.token)
check(done.ok and done.data.keys == true, 'external keys: the owner fitting a fake plate keeps keys (fake text)')
res = start(1, kcNet, 'remove')
advance(5000)
check(finish(1, res.data.token).ok, 'external keys: fake plate removed again')
give(4, 'fake_plate', 1)
give(4, 'screwdriver', 1)
playerPos[1] = vec3(0, 0, 0)
playerPos[4] = vec3(90, -2.6, 0)
local ownerKeyEvents = countEvents('nz:client:fakeplates:keys', 1)
res = start(4, kcNet)
advance(6000)
done = finish(4, res.data.token)
check(done.ok and done.data.keys == false, 'external keys: a stranger gets no keys for the fake text')
local ownerEv = lastEvent('nz:client:fakeplates:keys', 1)
check(countEvents('nz:client:fakeplates:keys', 1) == ownerKeyEvents + 1 and ownerEv.payload.plate == done.data.plate
  and ownerEv.payload.netId == kcNet, 'external keys: the absent owner keeps keys to their car')
check(countEvents('nz:client:fakeplates:keys', 4) == 0, 'external keys: nothing sent to the stranger')
NZ.CarLock.enabled, NZ.KeysServer.resource = carLockOn, keysResource
playerPos[4] = vec3(3, 1, 0)

-- recover: the fake plate comes off and the item comes back before the entity is removed
local requireSession = NZ.Access.requireSession
NZ.Access.requireSession = function() return session end

-- garage sale (offer + accept) of a vehicle standing next to the seller: the buyer gets a key
addRow('OUT002')
local o2, o2Net = spawnVehicle('OUT002', 'sultan', vec3(2, -3, 0))
Vehicles.setOut('OUT002', { netId = o2Net, entity = o2, src = 1, identifier = 'CID001', garageKey = 'L1' })
run(CarLock.giveKeyItem, 1, 'OUT002', { model = 'sultan' })
bank[2] = 50000
res = cb('nz:garage:sell', 1, { plate = 'OUT002', serverId = 2, price = 1000 })
check(res.ok == true, 'garage sale of an out vehicle: offer sent')
local offerEv = lastEvent('nz:client:sellOffer', 2)
res = cb('nz:garage:sellRespond', 2, { offerId = offerEv and offerEv.payload.offerId, accept = true })
check(res.ok == true and db.OUT002.owner == 'CID002', 'garage sale of an out vehicle: sold')
local o2Has, o2Kind = run(CarLock.hasKey, 2, 'OUT002')
check(o2Has == true and o2Kind == 'item', 'garage sale of an out vehicle: the buyer got a key item')
check(run(CarLock.hasKey, 1, 'OUT002') == false and Vehicles.out.OUT002.src == 2, 'garage sale of an out vehicle: the seller has no key and no claim')
check(lastLog('vehicle.sell', 'key', 'item') ~= nil, 'garage sale: key hand-out logged')
local fpBefore = count(1, 'fake_plate')
res = cb('nz:garage:recover', 1, { plate = 'KEY001' })
check(res.ok == true and entities[kc] == nil and db.KEY001.state == 'garaged', 'recover: fake-plated vehicle back in the garage')
check(count(1, 'fake_plate') == fpBefore + 1, 'recover: fake plate item returned (returnOnStore)')
check(lastLog('vehicle.fakeplate', 'action', 'store') ~= nil, 'recover: fake plate removal logged')
NZ.Access.requireSession = requireSession

---------------------------------------------------------------------------------------

for _, line in ipairs(printed.error) do failures[#failures + 1] = 'lib.print.error: ' .. line end
if #failures > 0 then
  print(('contracts: %d of %d checks failed'):format(#failures, checks))
  for _, f in ipairs(failures) do print('  - ' .. f) end
  os.exit(1)
end
print(('contracts OK (%d checks)'):format(checks))
