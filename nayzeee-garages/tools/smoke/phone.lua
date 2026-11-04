--[[
  Headless test for the phone garage-app integration (server/phone.lua). No FiveM needed.

  Loads the real shared files, server/access.lua, server/vehicles.lua and server/phone.lua in
  a stubbed server runtime with an in-memory vehicle database, a fake world (entities,
  plates, net ids, seats, state bags) and a controllable clock, then runs the valet flow end
  to end through the exports and net events a phone adapter uses:

    list -> claim -> phone spawns -> report (or watchdog adoption) -> keys / nzPlate / nzInit
    -> store in a garage; release / client failure / timeout / player drop roll back;
    server-side spawn whose plate arrives late; refusals (access, state, finance, type,
    trailer, garage access, closed / deleted garage, rate limit, pending limit, duplicates);
    another model wearing the plate (stray check, generic callback, watchdog, restart
    re-adoption); bounded report waits; plate that never arrives; generic failure report;
    resource restart with undelivered claims (KVP); boot hint; adapters in install/phone/.

  Usage (from the resource root):  lua5.4 tools/smoke/phone.lua
]]

local failures, checks = {}, 0
local function check(cond, label)
  checks = checks + 1
  if not cond then failures[#failures + 1] = label end
end

---------------------------------------------------------------------------------------
-- Runtime: clock, scheduler, events
---------------------------------------------------------------------------------------

local clock = 0                 -- ms
local BASE_TIME = 1700000000
local realTime = os.time
os.time = function(t)           -- luacheck: ignore 122
  if t then return realTime(t) end
  return BASE_TIME + clock // 1000
end

local threads = {}
function CreateThread(fn) threads[#threads + 1] = { co = coroutine.create(fn), wake = clock } end
function Wait(ms)
  if not coroutine.isyieldable() then error('Wait() outside a thread', 2) end
  coroutine.yield(ms or 0)
end
Citizen = { CreateThread = CreateThread, Wait = Wait }
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
    clock = math.min(target, clock + 50)
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

local handlers, netHandlers, clientEvents = {}, {}, {}
function AddEventHandler(name, fn) handlers[name] = handlers[name] or {} table.insert(handlers[name], fn) return name end
function RegisterNetEvent(name, fn) netHandlers[name] = fn end
function TriggerEvent(name, ...) for _, fn in ipairs(handlers[name] or {}) do fn(...) end end
function TriggerClientEvent(name, target, payload, ...)
  clientEvents[#clientEvents + 1] = { name = name, target = target, payload = payload, extra = { ... } }
end

--- Fire a net event as player `src` (the handler sees the global `source`).
local function fireNet(name, src, ...)
  local fn = netHandlers[name]
  if not fn then failures[#failures + 1] = 'net event not registered: ' .. name return end
  local args = table.pack(...)
  return run(function()
    source = src  -- luacheck: ignore 111
    fn(table.unpack(args, 1, args.n))
  end)
end

local function fireDropped(src)
  for _, fn in ipairs(handlers.playerDropped or {}) do
    source = src  -- luacheck: ignore 111
    fn('quit')
  end
end

---------------------------------------------------------------------------------------
-- FiveM natives: players, entities, state bags, KVP
---------------------------------------------------------------------------------------

local function vec3(x, y, z) return { x = x or 0.0, y = y or 0.0, z = z or 0.0 } end
function vector3(x, y, z) return vec3(x, y, z) end
function vector4(x, y, z, w) return { x = x or 0.0, y = y or 0.0, z = z or 0.0, w = w or 0.0 } end

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

local online = { [1] = 'CID001', [2] = 'CID002' }
function GetPlayerName(src) return online[tonumber(src)] and ('Player' .. tostring(src)) or nil end
function GetPlayers() local out = {} for src in pairs(online) do out[#out + 1] = tostring(src) end return out end
function GetPlayerPed(src) return online[tonumber(src)] and (1000 + tonumber(src)) or 0 end
function GetPlayerRoutingBucket() return 0 end
function IsPlayerAceAllowed() return false end
function IsDuplicityVersion() return true end
function GetCurrentResourceName() return 'nayzeee-garages' end
local invoking = 'lb-phone'
function GetInvokingResource() return invoking end
local resourceStates = { ['qb-core'] = 'started', ['lb-phone'] = 'started' }
function GetResourceState(name) return resourceStates[name] or 'missing' end

local kvp = {}
function GetResourceKvpString(k) return kvp[k] end
function SetResourceKvp(k, v) kvp[k] = v end
function DeleteResourceKvp(k) kvp[k] = nil end
local kvpFinds, kvpHandle = {}, 0
function StartFindKvp(prefix)
  local keys = {}
  for k in pairs(kvp) do if k:sub(1, #prefix) == prefix then keys[#keys + 1] = k end end
  table.sort(keys)
  kvpHandle = kvpHandle + 1
  kvpFinds[kvpHandle] = { keys = keys, i = 0 }
  return kvpHandle
end
function FindKvp(handle)
  local f = kvpFinds[handle]
  if not f then return nil end
  f.i = f.i + 1
  return f.keys[f.i]
end
function EndFindKvp(handle) kvpFinds[handle] = nil end

-- Entities: [handle] = { plate, model, netId, seats = { [-1] = ped }, coords, vtype }
local entities, nextHandle, nextNet = {}, 5000, 100
local states = {}
local function stateOf(handle)
  local s = states[handle]
  if not s then
    s = setmetatable({}, { __index = { set = function(self, k, v) rawset(self, k, v) end } })
    states[handle] = s
  end
  return s
end
function Entity(handle) return { state = stateOf(handle) } end
function Player() return { state = {} } end

local function spawnEntity(plate, model, opts)
  opts = opts or {}
  nextHandle = nextHandle + 1
  nextNet = nextNet + 1
  entities[nextHandle] = {
    plate = plate, model = joaat_(model or 'sultan'), netId = nextNet, seats = opts.seats or {},
    coords = opts.coords or vec3(0, 0, 0), vtype = opts.vtype or 'automobile',
  }
  return nextHandle, nextNet
end

function DoesEntityExist(h) return entities[h] ~= nil end
function GetEntityType(h) return entities[h] and 2 or 0 end
function GetAllVehicles() local out = {} for h in pairs(entities) do out[#out + 1] = h end table.sort(out) return out end
function GetVehicleNumberPlateText(h)
  local e = entities[h]
  if not e then return '' end
  return (e.plate .. '        '):sub(1, 8)
end
function SetVehicleNumberPlateText(h, text) if entities[h] then entities[h].plate = tostring(text) end end
function NetworkGetEntityFromNetworkId(netId)
  for h, e in pairs(entities) do if e.netId == netId then return h end end
  return 0
end
function NetworkGetNetworkIdFromEntity(h) return entities[h] and entities[h].netId or 0 end
function GetPedInVehicleSeat(h, seat) local e = entities[h] return e and e.seats[seat] or 0 end
function GetEntityModel(h) return entities[h] and entities[h].model or 0 end
function GetVehicleType(h) return entities[h] and entities[h].vtype or nil end
function GetEntityCoords(h)
  local e = entities[h]
  if e then return e.coords end
  return vec3(0, 0, 0) -- player peds stand at the garage open point
end
function GetEntityHealth() return 1000 end
function GetVehicleEngineHealth() return 900.0 end
function GetVehicleBodyHealth() return 950.0 end
function GetVehiclePetrolTankHealth() return 1000.0 end
function GetEntityAttachedTo() return 0 end
function DeleteEntity(h)
  if not entities[h] then return end
  entities[h] = nil
  states[h] = nil
  TriggerEvent('entityRemoved', h)
end

-- Any other PascalCase native answers nil.
setmetatable(_G, { __index = function(_, k)
  if type(k) == 'string' and k:match('^%u') then return function() return nil end end
  return nil
end })

---------------------------------------------------------------------------------------
-- ox_lib / exports / json
---------------------------------------------------------------------------------------

local printed = { info = {}, warn = {}, error = {} }
lib = {
  print = {
    info = function(...) printed.info[#printed.info + 1] = table.concat({ ... }, ' ') end,
    warn = function(...) printed.warn[#printed.warn + 1] = table.concat({ ... }, ' ') end,
    error = function(...) printed.error[#printed.error + 1] = table.concat({ ... }, ' ') end,
    debug = function() end,
  },
  callback = { register = function() end },
}

local exported = {}
exports = setmetatable({}, {
  __call = function(_, name, fn) exported[name] = fn end,
  __index = function()
    return setmetatable({}, { __index = function() return function() return nil end end })
  end,
})

local hasDk, dk = pcall(require, 'dkjson')
if hasDk then
  json = { encode = function(v) return dk.encode(v) end,
    decode = function(text) if type(text) ~= 'string' then return nil end return (dk.decode(text)) end }
else
  -- flat objects of numbers / strings are all server/phone.lua stores
  json = {
    encode = function(v)
      local parts = {}
      for k, x in pairs(v) do
        parts[#parts + 1] = ('%q:%s'):format(k, type(x) == 'number' and tostring(x) or ('%q'):format(tostring(x)))
      end
      return '{' .. table.concat(parts, ',') .. '}'
    end,
    decode = function(text)
      if type(text) ~= 'string' or not text:match('^%b{}$') then return nil end
      local out = {}
      for k, x in text:gmatch('"([^"]+)":("?[^,}"]*"?)') do
        out[k] = x:match('^"(.*)"$') or tonumber(x)
      end
      return out
    end,
  }
end

---------------------------------------------------------------------------------------
-- Load the shared files
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
load_('shared/init.lua')
load_('shared/utils.lua')
load_('bridge/shared.lua')
NZ.Framework = 'qb'
local Utils = NZ.Utils

---------------------------------------------------------------------------------------
-- In-memory modules the vehicle code depends on
---------------------------------------------------------------------------------------

local settingsOverride = {}
NZ.Settings.get = function(path, default)
  if settingsOverride[path] ~= nil then return settingsOverride[path] end
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
local function lastLog(event)
  for i = #logs, 1, -1 do if logs[i].event == event then return logs[i] end end
  return nil
end

NZ.Bridge.getIdentifier = function(src) return online[tonumber(src)] end
NZ.Bridge.getPlayer = function() return nil end
NZ.Bridge.getJob = function() return nil end
NZ.Bridge.getGang = function() return nil end
NZ.Bridge.getCharacterName = function(identifier) return 'Name ' .. tostring(identifier) end
NZ.Bridge.getSourceByIdentifier = function(identifier)
  for src, id in pairs(online) do if id == identifier then return src end end
  return nil
end
NZ.Bridge.pay = function() return true, 'bank' end
NZ.Bridge.addMoney = function() return true end
NZ.Bridge.isAdmin = function() return false end

local keysGiven = {}
NZ.KeysServer.give = function(src, netId, plate) keysGiven[#keysGiven + 1] = { src = src, netId = netId, plate = plate } end
local keysClientSide = false -- a client-side key resource (qb-vehiclekeys, ...) is in use
NZ.KeysServer.clientSide = function() return keysClientSide end
local function giveKeysEvents(plate)
  local list = {}
  for _, ev in ipairs(clientEvents) do
    if ev.name == 'nz:client:giveKeys' and (plate == nil or ev.extra[1] == plate) then list[#list + 1] = ev end
  end
  return list
end

NZ.Private.role = function() return nil end
NZ.Private.groupsFor = function() return {} end
NZ.Private.getGroup = function() return nil end
local houseAccess = {}
NZ.Housing.hasAccess = function(identifier, houseId) return houseAccess[tostring(houseId) .. ':' .. identifier] == true end
local interiorOf = {}
NZ.Interiors.playerInstance = function(src) return interiorOf[tonumber(src)] end
NZ.Interiors.instances = {}
NZ.Jobs.isSpawnerVehicle = function() return false end

-- Locations
local function location(id, kind, extra)
  local loc = {
    id = id, kind = kind, name = 'Location ' .. tostring(id), vehicleType = 'car', enabled = true,
    source = 'personal', restriction = { type = 'everyone', rules = {}, identifiers = {} },
    openPoints = { { coords = vec3(0, 0, 0), radius = 2.0 } }, storePoints = {}, useOpenForStore = true,
    spawnPoints = { vector4(5, 5, 0, 90) },
  }
  for k, v in pairs(extra or {}) do loc[k] = v end
  return loc
end
local locations = {
  [1] = location(1, 'garage', { name = 'Legion Square' }),
  [2] = location(2, 'garage', { name = 'Closed lot', enabled = false }),
  [3] = location(3, 'impound', { name = 'Davis Impound', openPoints = { { coords = vec3(100, 0, 0), radius = 2.0 } } }),
  [5] = location(5, 'garage', { name = 'Marina', vehicleType = 'sea' }),
}
local houses = {
  Hgrove_1 = location('Hgrove_1', 'house', { name = 'Grove St 1', houseId = 'grove_1' }),
}
NZ.Locations.get = function(id)
  if type(id) == 'string' and id:sub(1, 1) == 'H' then return houses[id] end
  return locations[tonumber(id)]
end
NZ.Locations.all = function(kind)
  local out = {}
  for _, loc in pairs(locations) do if not kind or loc.kind == kind then out[#out + 1] = loc end end
  return out
end
NZ.Locations.resolveKey = function(key)
  local kind, id = Utils.key.parse(key)
  if kind == 'L' and locations[id] then return { kind = 'L', key = key, location = locations[id], locationId = id } end
  if kind == 'H' and houses[key] then return { kind = 'H', key = key, location = houses[key], locationId = key, houseId = id } end
  return nil
end
NZ.Locations.keyName = function(key)
  local resolved = NZ.Locations.resolveKey(key)
  return resolved and resolved.location.name or nil
end
NZ.Locations.capacity = function() return nil end

-- Vehicle database (NZVehicleRow)
local db = {}
local shares = { SHR001 = { 'CID001' } }
local function addRow(plate, fields)
  local row = {
    plate = plate, dbPlate = plate, owner = 'CID001', model = 'sultan', hash = joaat_('sultan'),
    props = { model = joaat_('sultan'), plate = plate, colorPrimary = 3 },
    garageKey = 'L1', frameworkGarage = 'Legion Square', state = 'garaged', vehicleType = 'car',
    vehicleTypeKnown = true, ownerType = 'player', mileage = 120.5, fuel = 80, engine = 90, body = 95,
    damage = { v = 1, engine = 900.0, body = 950.0, doors = { [0] = true } }, blocked = false, lastOut = 1000,
  }
  for k, v in pairs(fields or {}) do row[k] = v end
  db[plate] = row
end
addRow('ABC123')
addRow('SHR001', { owner = 'CID002' })
addRow('IMP001', { state = 'impounded', impound = { locationId = 3, locationName = 'Davis Impound', reason = 'Parking',
  fee = 500, byName = 'Officer Hayes', at = BASE_TIME - 60, releaseAt = BASE_TIME + 3600, retrievable = true } })
addRow('BLK001', { blocked = true })
addRow('FIN001', { finance = { balance = 1000, payment = 100, paymentsLeft = 10, overdue = true } })
addRow('TRL001', { trailer = { hash = joaat_('trailers'), props = { plate = 'TR12345' } } })
addRow('BOAT01', { garageKey = 'L5', vehicleType = 'sea', model = 'dinghy', hash = joaat_('dinghy') })
addRow('HSE001', { garageKey = 'Hgrove_1' })
addRow('CLS001', { garageKey = 'L2' })
addRow('GON001', { garageKey = 'L99' })
addRow('FLT001', { job = 'police', ownerType = 'job' })
addRow('OTH001', { owner = 'CID002' })
addRow('DEF456')
addRow('GHI789')
addRow('JKL012')
addRow('MNO345')

local function copy(t) return Utils.deepCopy(t) end
local dbFail = false
NZ.DB.getVehicle = function(plate)
  if dbFail then return nil end
  local row = db[Utils.plate(plate) or '']
  return row and copy(row) or nil
end
NZ.DB.getVehiclesByOwner = function(identifier)
  local out = {}
  for _, row in pairs(db) do if row.owner == identifier then out[#out + 1] = copy(row) end end
  table.sort(out, function(a, b) return a.plate < b.plate end)
  return out
end
NZ.DB.getVehiclesByPlates = function(plates)
  local out = {}
  for _, p in ipairs(plates) do if db[p] then out[#out + 1] = copy(db[p]) end end
  return out
end
NZ.DB.plateExists = function(plate) return db[Utils.plate(plate) or ''] ~= nil end
local updates = 0
NZ.DB.updateVehicle = function(plate, fields)
  if dbFail then return false end
  local row = db[Utils.plate(plate) or '']
  if not row then return false end
  updates = updates + 1
  for k, v in pairs(fields) do
    if k == 'garageName' then
      row.frameworkGarage = v
    elseif v == false and (k == 'lastOut' or k == 'impound' or k == 'damage' or k == 'trailer' or k == 'nickname' or k == 'finance') then
      row[k] = nil
    else
      row[k] = v
    end
  end
  return true
end
NZ.DB.getOutVehicles = function()
  local out = {}
  for _, row in pairs(db) do if row.state == 'out' then out[#out + 1] = copy(row) end end
  return out
end
NZ.DB.shares = {}
NZ.DB.favourites = {}
NZ.DB.shares.forPlate = function(plate)
  local out = {}
  for _, id in ipairs(shares[plate] or {}) do out[#out + 1] = { identifier = id, name = 'x', sharedBy = 'y' } end
  return out
end
NZ.DB.shares.forIdentifier = function(identifier)
  local out = {}
  for plate, ids in pairs(shares) do
    for _, id in ipairs(ids) do if id == identifier then out[#out + 1] = plate end end
  end
  return out
end
NZ.DB.favourites.get = function() return {} end
NZ.DB.countInGarage = function() return 0 end

---------------------------------------------------------------------------------------
-- Load the real modules under test
---------------------------------------------------------------------------------------

load_('server/access.lua')
load_('server/vehicles.lua')
load_('server/phone.lua')
NZ.Ready = true

local Vehicles = NZ.Vehicles
for _, name in ipairs({ 'GetPhoneVehicles', 'ClaimVehicleForValet', 'ReleaseValetClaim', 'MarkValetSpawned' }) do
  check(type(exported[name]) == 'function', 'export ' .. name .. ' registered')
end
check(netHandlers['nz:phone:spawned'] ~= nil, 'net event nz:phone:spawned registered')
check(netHandlers['nz:phone:failed'] ~= nil, 'net event nz:phone:failed registered')

local function call(name, ...) return run(exported[name], ...) end
local function waitRate() advance(2600) end   -- past the per-player claim rate limit

---------------------------------------------------------------------------------------
-- 1. Vehicle list
---------------------------------------------------------------------------------------

local list, listErr = call('GetPhoneVehicles', 1)
check(type(list) == 'table', 'GetPhoneVehicles returns a list (' .. tostring(listErr) .. ')')
local byPlate = {}
for _, item in ipairs(list or {}) do byPlate[item.plate] = item end
local own = byPlate.ABC123
check(own ~= nil, 'own vehicle listed')
if own then
  check(own.state == 'garaged' and own.garageName == 'Legion Square' and own.garageKey == 'L1', 'garage name / key / state')
  check(own.fuel == 80 and own.engine == 90 and own.body == 95 and own.mileage == 120.5, 'fuel / engine / body / mileage')
  check(own.hash == joaat_('sultan') and own.model == 'sultan' and own.vehicleType == 'car', 'model / hash / type')
  check(own.canValet == true and own.valetReason == nil, 'own garaged car can be delivered')
  check(own.isOwner == true and own.shared == false, 'owner flags')
  check(type(own.garageCoords) == 'table' and own.garageCoords.x == 0, 'garage coords')
  check(own.damage == nil and own.props == nil, 'no damage / props in the list')
end
check(byPlate.SHR001 and byPlate.SHR001.shared == true and byPlate.SHR001.ownerName == 'Name CID002'
  and byPlate.SHR001.canValet == true, 'shared vehicle listed, flagged and deliverable')
check(byPlate.OTH001 == nil, 'unshared vehicle of another player not listed')
local imp = byPlate.IMP001
check(imp and imp.state == 'impounded' and type(imp.impound) == 'table' and imp.impound.reason == 'Parking'
  and imp.impound.fee == 500 and imp.impound.by == 'Officer Hayes' and imp.impound.releaseAt == BASE_TIME + 3600
  and imp.impound.location == 'Davis Impound' and imp.impound.coords and imp.impound.coords.x == 100
  and imp.canValet == false, 'impound info')
check(byPlate.FIN001 and byPlate.FIN001.financed == true and byPlate.FIN001.finance.overdue == true
  and byPlate.FIN001.canValet == false, 'finance flags')
check(byPlate.FLT001 and byPlate.FLT001.canValet == false, 'fleet vehicle not deliverable')
check(byPlate.TRL001 and byPlate.TRL001.canValet == false, 'vehicle with a saved trailer not deliverable')
check(byPlate.BOAT01 and byPlate.BOAT01.canValet == false and byPlate.BOAT01.vehicleType == 'sea', 'boat not deliverable by default')
check(byPlate.HSE001 and byPlate.HSE001.canValet == false, 'house garage without access')
check(byPlate.CLS001 and byPlate.CLS001.canValet == false, 'closed garage')
check(byPlate.GON001 and byPlate.GON001.canValet == false, 'deleted garage')

-- rate limited right after: the previous answer is served
local again = call('GetPhoneVehicles', 1)
check(type(again) == 'table' and #again == #list, 'rate-limited list served from the cache')
local none, noneErr = call('GetPhoneVehicles', 99)
check(none == nil and type(noneErr) == 'string', 'unknown player refused')

---------------------------------------------------------------------------------------
-- 2. Claim -> client spawn -> report -> store
---------------------------------------------------------------------------------------

advance(1100)
local data, err = call('ClaimVehicleForValet', 1, 'abc123')
check(type(data) == 'table', 'claim accepted (' .. tostring(err) .. ')')
if data then
  check(data.plate == 'ABC123' and data.hash == joaat_('sultan') and data.props.plate == 'ABC123'
    and data.props.model == joaat_('sultan') and data.props.fuelLevel == 80 and data.fuel == 80, 'valet data: props / plate / model / fuel')
  check(type(data.damage) == 'table' and data.damage.engine == 900.0, 'valet data: damage')
  check(data.engine == 90 and data.body == 95 and data.mileage == 120.5, 'valet data: health / mileage')
end
check(db.ABC123.state == 'out' and db.ABC123.lastOut == os.time(), 'database marked out')
local entry = Vehicles.out.ABC123
check(entry and entry.src == 1 and entry.phone ~= nil, 'out entry registered for the claimant')
check(Vehicles.isOut('ABC123') == true, 'isOut during the delivery grace')
check(NZ.Phone.pending('ABC123') ~= nil, 'claim pending')
local stored1 = json.decode(kvp['nz_phone_claim:ABC123'])
check(type(stored1) == 'table' and stored1.at == os.time() and stored1.prev == 1000 and stored1.identifier == 'CID001'
  and stored1.hash == joaat_('sultan'), 'pending claim remembered in the resource KVP')
local retrieveLog = lastLog('vehicle.retrieve')
check(retrieveLog and retrieveLog.data.via == 'phone' and retrieveLog.data.resource == 'lb-phone', 'retrieve logged with via = phone')

waitRate()
local second, secondErr = call('ClaimVehicleForValet', 1, 'ABC123')
check(second == nil and type(secondErr) == 'string', 'second claim of the same car refused')

-- the phone's client creates the car and reports it
local car, carNet = spawnEntity('ABC123', 'sultan')
fireNet('nz:phone:spawned', 1, 'ABC123', carNet)
entry = Vehicles.out.ABC123
check(entry and entry.entity == car and entry.netId == carNet, 'reported entity tracked')
check(stateOf(car).nzPlate == 'ABC123', 'nzPlate state bag set')
check(type(stateOf(car).nzInit) == 'table' and stateOf(car).nzInit.damage ~= nil, 'nzInit (saved damage / fuel) attached')
check(#keysGiven == 1 and keysGiven[1].plate == 'ABC123' and keysGiven[1].netId == carNet, 'server-side keys given')
check(#giveKeysEvents() == 0, 'no client key event while keys are given on the server')
check(NZ.Phone.pending('ABC123') == nil, 'claim finished')
check(kvp['nz_phone_claim:ABC123'] == nil, 'delivered claim forgotten in the KVP')

-- a duplicate report (phone server + client) is harmless
local dupOk = call('MarkValetSpawned', 1, 'ABC123', carNet)
check(dupOk == true, 'second report of the same entity accepted')

-- another player cannot report or release it
local foreign = call('MarkValetSpawned', 2, 'ABC123', carNet)
check(foreign ~= true, 'report by another player refused')

-- store it at the garage later
entities[car].seats[-1] = GetPlayerPed(1)
local session = { garageKey = 'L1', location = locations[1], locationId = 1 }
local stored = run(Vehicles.store, 1, session, { netId = carNet, data = { props = { model = joaat_('sultan') }, fuel = 70, mileage = 130 } })
check(type(stored) == 'table' and stored.ok == true, 'valet car stored in a garage (' .. tostring(stored and stored.error) .. ')')
check(db.ABC123.state == 'garaged' and db.ABC123.garageKey == 'L1' and entities[car] == nil and Vehicles.out.ABC123 == nil,
  'stored: garaged, entity deleted, out entry cleared')

---------------------------------------------------------------------------------------
-- 3. Watchdog adoption (the phone never reports the entity)
---------------------------------------------------------------------------------------

waitRate()
keysClientSide = true -- client-side key resource: the keys reach the claimant's client
data = call('ClaimVehicleForValet', 1, 'DEF456')
check(type(data) == 'table', 'claim 2 accepted')
local car2, car2Net = spawnEntity('DEF456', 'sultan')
advance(2500)
entry = Vehicles.out.DEF456
check(entry and entry.entity == car2, 'watchdog adopted the unreported valet car')
check(NZ.Phone.pending('DEF456') == nil and stateOf(car2).nzPlate == 'DEF456', 'adopted: claim finished, nzPlate set')
local keyEvents = giveKeysEvents()
check(#keyEvents == 1 and keyEvents[1].target == 1 and keyEvents[1].payload == car2Net
  and keyEvents[1].extra[1] == 'DEF456', 'client-side key resource: nz:client:giveKeys sent to the claimant')
keysClientSide = false

---------------------------------------------------------------------------------------
-- 4. Timeout rollback (no copy ever appears) + player notification
---------------------------------------------------------------------------------------

waitRate()
local before = db.GHI789.lastOut
data = call('ClaimVehicleForValet', 1, 'GHI789')
check(type(data) == 'table' and db.GHI789.state == 'out', 'claim 3 accepted')
advance(30000)
check(db.GHI789.state == 'out' and Vehicles.isOut('GHI789') == true, 'still on its way after 30 s (grace kept alive)')
advance(32000)
check(db.GHI789.state == 'garaged' and db.GHI789.lastOut == before, 'rolled back after the timeout (state + lastOut)')
check(Vehicles.out.GHI789 == nil and NZ.Phone.pending('GHI789') == nil, 'rollback cleared the out entry and the claim')
check(kvp['nz_phone_claim:GHI789'] == nil, 'rolled-back claim forgotten in the KVP')
local failLog = lastLog('vehicle.spawnFailed')
check(failLog and failLog.data.plate == 'GHI789' and failLog.data.via == 'phone', 'rollback logged')
local notified = false
for _, ev in ipairs(clientEvents) do
  if ev.name == 'nz:client:notify' and ev.target == 1 then notified = true end
end
check(notified, 'player told the car went back')

---------------------------------------------------------------------------------------
-- 5. Release (phone server failure branch) and client failure report
---------------------------------------------------------------------------------------

waitRate()
data = call('ClaimVehicleForValet', 1, 'JKL012')
check(type(data) == 'table', 'claim 4 accepted')
local relForeign = call('ReleaseValetClaim', 2, 'JKL012')
check(relForeign ~= true and db.JKL012.state == 'out', 'release by another player refused')
local blocker = spawnEntity('JKL012', 'sultan')
advance(600)
local relBlocked = call('ReleaseValetClaim', 1, 'JKL012')
check(relBlocked ~= true and db.JKL012.state == 'out', 'release refused while a copy exists')
DeleteEntity(blocker)
advance(600)
local rel, relErr = call('ReleaseValetClaim', 1, 'JKL012')
check(rel == true and db.JKL012.state == 'garaged' and Vehicles.out.JKL012 == nil, 'released back to the garage (' .. tostring(relErr) .. ')')

waitRate()
data = call('ClaimVehicleForValet', 1, 'JKL012')
check(type(data) == 'table', 'claim 5 accepted')
advance(600)
fireNet('nz:phone:failed', 1, 'JKL012')
check(db.JKL012.state == 'garaged' and NZ.Phone.pending('JKL012') == nil, 'client failure report rolled back')

---------------------------------------------------------------------------------------
-- 6. Server-side spawn: plate arrives late, MarkValetSpawned waits for it
---------------------------------------------------------------------------------------

waitRate()
data = call('ClaimVehicleForValet', 1, 'MNO345')
check(type(data) == 'table', 'claim 6 accepted')
local srvCar, srvNet = spawnEntity('TMP00000', 'sultan')
local marked
CreateThread(function() marked = exported.MarkValetSpawned(1, 'MNO345', srvNet) end)
advance(1000)
entities[srvCar].plate = 'MNO345'   -- the client applies the props a moment later
advance(1500)
check(marked == true and Vehicles.out.MNO345 and Vehicles.out.MNO345.entity == srvCar, 'server-spawned car tracked once its plate arrived')
check(#printed.error == 0, 'no errors so far: ' .. table.concat(printed.error, ' | '))

---------------------------------------------------------------------------------------
-- 7. Refusals
---------------------------------------------------------------------------------------

local function refused(plate, label, src)
  waitRate()
  local d, e = call('ClaimVehicleForValet', src or 1, plate)
  if os.getenv('PHONE_VERBOSE') then print(('refused %-28s -> %s'):format(label, tostring(e))) end
  check(d == nil and type(e) == 'string' and e ~= '', label .. ' refused (' .. tostring(e) .. ')')
  check(db[plate] == nil or db[plate].state ~= 'out' or plate == 'ABC123', label .. ': state untouched')
end
refused('IMP001', 'impounded')
refused('BLK001', 'blocked')
refused('FIN001', 'finance overdue')
refused('TRL001', 'saved trailer')
refused('BOAT01', 'boat')
refused('HSE001', 'house garage without access')
refused('CLS001', 'closed garage')
refused('GON001', 'deleted garage')
refused('FLT001', 'fleet vehicle')
refused('OTH001', 'someone else\'s car')
refused('NOPE01', 'unknown plate')

-- house access granted -> allowed; retrieveMode 'anywhere' -> deleted garage allowed
houseAccess['grove_1:CID001'] = true
waitRate()
data = call('ClaimVehicleForValet', 1, 'HSE001')
check(type(data) == 'table', 'house garage with access accepted')
settingsOverride['garages.retrieveMode'] = 'anywhere'
waitRate()
data = call('ClaimVehicleForValet', 1, 'GON001')
check(type(data) == 'table', 'retrieveMode anywhere: vehicle of a deleted garage accepted')
settingsOverride['garages.retrieveMode'] = nil
waitRate()
local limited, limitedErr = call('ClaimVehicleForValet', 1, 'SHR001')
check(limited == nil and type(limitedErr) == 'string' and db.SHR001.state == 'garaged', 'pending limit (2) reached')

-- shared vehicle (owner CID002, shared with CID001)
advance(65000) -- the HSE001 / GON001 claims time out and return
check(db.HSE001.state == 'garaged' and db.GON001.state == 'garaged', 'pending claims back after their timeout')
waitRate()
data = call('ClaimVehicleForValet', 1, 'SHR001')
check(type(data) == 'table' and Vehicles.out.SHR001.src == 1, 'shared vehicle accepted for the share holder')

-- rate limit: two claims inside 2 s
waitRate()
call('ClaimVehicleForValet', 1, 'DEF999')
local rl, rlErr = call('ClaimVehicleForValet', 1, 'BLK001')
check(rl == nil and type(rlErr) == 'string', 'claim rate limit')

-- inside a garage interior
interiorOf[2] = 'L1:CID002'
addRow('PQR678', { owner = 'CID002' })
waitRate()
local inside = call('ClaimVehicleForValet', 2, 'PQR678')
check(inside == nil and db.PQR678.state == 'garaged', 'refused inside a garage interior')
interiorOf[2] = nil

-- duplicates: an occupied stray copy blocks the claim, an empty one is removed
local stray = spawnEntity('PQR678', 'sultan', { seats = { [-1] = 7777 } })
waitRate()
local dupe = call('ClaimVehicleForValet', 2, 'PQR678')
check(dupe == nil and entities[stray] ~= nil and db.PQR678.state == 'garaged', 'occupied stray copy blocks the claim')
entities[stray].seats = {}
waitRate()
dupe = call('ClaimVehicleForValet', 2, 'PQR678')
check(type(dupe) == 'table' and entities[stray] == nil, 'empty stray copy removed before the claim')
check(lastLog('security.dupe') ~= nil, 'stray copy logged')

-- wrong entity reported (plate mismatch) is not tracked
local wrong, wrongNet = spawnEntity('ZZZ999', 'sultan')
local wrongOk = call('MarkValetSpawned', 2, 'PQR678', wrongNet)
check(wrongOk ~= true and (Vehicles.out.PQR678 == nil or Vehicles.out.PQR678.entity ~= wrong), 'mismatching entity refused')

-- player drop: the pending claim goes back on the next watchdog tick
fireDropped(2)
advance(2500)
check(db.PQR678.state == 'garaged' and NZ.Phone.pending('PQR678') == nil, 'claim of a dropped player rolled back')

-- database failure while claiming: nothing changes
dbFail = true
waitRate()
local dbData = call('ClaimVehicleForValet', 1, 'DEF999')
check(dbData == nil, 'database failure refused')
dbFail = false

-- invalid inputs never throw
for _, args in ipairs({ { nil, 'ABC123' }, { 1, nil }, { 1, {} }, { 'x', 'ABC123' }, { 1, ('A'):rep(40) } }) do
  local d = call('ClaimVehicleForValet', args[1], args[2])
  check(d == nil, 'invalid claim input refused')
  local r = call('ReleaseValetClaim', args[1], args[2])
  check(r ~= true, 'invalid release input refused')
  local m = call('MarkValetSpawned', args[1], args[2], -5)
  check(m ~= true, 'invalid spawned input refused')
end

---------------------------------------------------------------------------------------
-- 8. Private group membership, model checks, character unload, report at the deadline
---------------------------------------------------------------------------------------

advance(70000) -- every pending claim above times out
for plate, row in pairs(db) do
  if row.state == 'out' and not Vehicles.isOut(plate) then row.state = 'garaged' end
end

-- private garage instance G7 (location 6); CID001 is a member of G8 at the same location only
locations[6] = location(6, 'private', { name = 'Crew lot' })
local groups = {
  [7] = { id = 7, locationId = 6, label = 'Crew lot #7', members = { CID002 = { role = 'owner' } } },
  [8] = { id = 8, locationId = 6, label = 'Crew lot #8', members = { CID001 = { role = 'owner' } } },
}
NZ.Private.getGroup = function(id) return groups[tonumber(id)] end
NZ.Private.role = function(gid, identifier)
  local g = groups[tonumber(gid) or -1]
  local m = g and g.members[identifier]
  return m and m.role or nil
end
NZ.Private.groupsFor = function(identifier, locationId)
  local out = {}
  for _, g in pairs(groups) do
    if g.members[identifier] and (not locationId or g.locationId == locationId) then out[#out + 1] = g end
  end
  return out
end
local baseResolve = NZ.Locations.resolveKey
NZ.Locations.resolveKey = function(key)
  local kind, id = Utils.key.parse(key)
  if kind == 'G' and groups[id] then
    return { kind = 'G', key = key, location = locations[groups[id].locationId], locationId = 6, group = groups[id], groupId = id }
  end
  return baseResolve(key)
end
addRow('PRV001', { garageKey = 'G7' })
refused('PRV001', 'parked in another private group of the same location')
groups[7].members.CID001 = { role = 'member' }
waitRate()
data = call('ClaimVehicleForValet', 1, 'PRV001')
check(type(data) == 'table', 'private group member accepted')
fireNet('nz:phone:failed', 1, 'PRV001')
check(db.PRV001.state == 'garaged', 'private claim released')

-- a reported entity of another model is refused (and logged)
addRow('MOD001')
waitRate()
data = call('ClaimVehicleForValet', 1, 'MOD001')
check(type(data) == 'table', 'claim 7 accepted')
local fake, fakeNet = spawnEntity('MOD001', 'adder')
local fakeOk = call('MarkValetSpawned', 1, 'MOD001', fakeNet)
check(fakeOk ~= true and (Vehicles.out.MOD001 == nil or Vehicles.out.MOD001.entity ~= fake), 'other model refused')
check(lastLog('security.model') ~= nil, 'other model logged')
-- the watchdog does not adopt it either, and the claim still times out
advance(62000)
check(db.MOD001.state == 'garaged' and NZ.Phone.pending('MOD001') == nil, 'same plate, other model: claim rolled back')
DeleteEntity(fake)

-- character unload: the pending claim goes back
addRow('UNL001')
waitRate()
data = call('ClaimVehicleForValet', 1, 'UNL001')
check(type(data) == 'table', 'claim 8 accepted')
TriggerEvent('nz:server:playerUnloaded', 1)
advance(2500)
check(db.UNL001.state == 'garaged' and NZ.Phone.pending('UNL001') == nil, 'claim of an unloaded character rolled back')

-- a report still waiting for the plate at the deadline keeps the claim alive
addRow('LAT001')
waitRate()
data = call('ClaimVehicleForValet', 1, 'LAT001')
check(type(data) == 'table', 'claim 9 accepted')
advance(55000)
local late, lateNet = spawnEntity('TMP00001', 'sultan')
local lateOk
CreateThread(function() lateOk = exported.MarkValetSpawned(1, 'LAT001', lateNet) end)
advance(7000)             -- past the 60 s timeout while the report waits
check(db.LAT001.state == 'out', 'claim kept while a report waits for the plate')
entities[late].plate = 'LAT001'
advance(1000)
check(lateOk == true and Vehicles.out.LAT001 and Vehicles.out.LAT001.entity == late, 'late plate: vehicle tracked')

---------------------------------------------------------------------------------------
-- 8b. Review round 1: model-aware strays, wrong model through the generic callback,
--     bounded report waits, plate that never arrives, generic failure report
---------------------------------------------------------------------------------------

local function logCount(event, plate)
  local n = 0
  for _, entryLog in ipairs(logs) do
    if entryLog.event == event and (not plate or entryLog.data.plate == plate) then n = n + 1 end
  end
  return n
end

-- an unoccupied car of ANOTHER model showing the plate is neither deleted nor blocking
addRow('OTM001')
local otherCar = spawnEntity('OTM001', 'blista')
waitRate()
data = call('ClaimVehicleForValet', 1, 'OTM001')
check(type(data) == 'table' and entities[otherCar] ~= nil and logCount('security.dupe', 'OTM001') == 0,
  'same plate, other model: not deleted, claim accepted')
advance(600)
fireNet('nz:phone:failed', 1, 'OTM001')
check(db.OTM001.state == 'garaged' and NZ.Phone.pending('OTM001') == nil, 'same plate, other model: release not blocked')
DeleteEntity(otherCar)

-- another model reported through the generic 'nz:garage:spawned' (NZ.Vehicles.markSpawned)
addRow('TRK001')
waitRate()
data = call('ClaimVehicleForValet', 1, 'TRK001')
check(type(data) == 'table', 'claim 10 accepted')
local blista, blistaNet = spawnEntity('TRK001', 'blista')
local genericOk = run(Vehicles.markSpawned, 1, 'TRK001', blistaNet)
-- Vehicles.markSpawned compares the model with the vehicle row: another model is refused there
check(genericOk ~= true and (not Vehicles.out.TRK001 or Vehicles.out.TRK001.entity ~= blista), 'generic callback (plate-only) refuses the other model')
local realCar, realNet = spawnEntity('TRK001', 'sultan')
fireNet('nz:phone:spawned', 1, 'TRK001', realNet)
check(entities[realCar] ~= nil and Vehicles.out.TRK001 and Vehicles.out.TRK001.entity == realCar
  and NZ.Phone.pending('TRK001') == nil and type(stateOf(realCar).nzInit) == 'table' and stateOf(blista).nzInit == nil,
  'real car still accepted after another model was reported (not deleted as a duplicate)')
check(lastLog('security.model') and lastLog('security.model').data.plate == 'TRK001', 'other model tracked: logged')
DeleteEntity(blista)
DeleteEntity(realCar)
db.TRK001.state = 'garaged'

-- same, but the watchdog finds the wrong model first: dropped, the claim goes on
addRow('TRK002')
waitRate()
data = call('ClaimVehicleForValet', 1, 'TRK002')
check(type(data) == 'table', 'claim 10b accepted')
local blista2, blista2Net = spawnEntity('TRK002', 'blista')
run(Vehicles.markSpawned, 1, 'TRK002', blista2Net)
advance(2500)
check(NZ.Phone.pending('TRK002') ~= nil and Vehicles.out.TRK002 and Vehicles.out.TRK002.entity == nil
  and stateOf(blista2).nzInit == nil and stateOf(blista2).nzPlate == nil, 'watchdog: other model dropped, claim still pending')
local real2 = spawnEntity('TRK002', 'sultan')
advance(2500)
check(Vehicles.out.TRK002 and Vehicles.out.TRK002.entity == real2 and NZ.Phone.pending('TRK002') == nil,
  'watchdog: real car adopted afterwards')
DeleteEntity(blista2)
DeleteEntity(real2)
db.TRK002.state = 'garaged'

-- a plate that never arrives: refused after the wait, without a false plate alarm
addRow('NOP001')
waitRate()
data = call('ClaimVehicleForValet', 1, 'NOP001')
check(type(data) == 'table', 'claim 10c accepted')
local noPlate, noPlateNet = spawnEntity('TMP00002', 'sultan')
local plateLogs = logCount('security.plate')
local npOk, npErr = call('MarkValetSpawned', 1, 'NOP001', noPlateNet)
check(npOk == false and type(npErr) == 'string' and logCount('security.plate') == plateLogs
  and (Vehicles.out.NOP001 == nil or Vehicles.out.NOP001.entity == nil), 'plate never arrived: refused, no plate alarm')
entities[noPlate].plate = 'NOP001'
advance(2500)
check(Vehicles.out.NOP001 and Vehicles.out.NOP001.entity == noPlate, 'plate arrived later: adopted by the watchdog')
DeleteEntity(noPlate)
db.NOP001.state = 'garaged'

-- repeated bogus reports cannot hold a claim forever
addRow('WAI001')
waitRate()
data = call('ClaimVehicleForValet', 1, 'WAI001')
check(type(data) == 'table', 'claim 11 accepted')
local heldAt70 = nil
for i = 1, 24 do
  CreateThread(function() exported.MarkValetSpawned(1, 'WAI001', 99999) end)
  advance(5000)
  if i == 14 then heldAt70 = db.WAI001.state end
end
check(heldAt70 == 'out', 'a waiting report extends the claim past its timeout')
check(db.WAI001.state == 'garaged' and NZ.Phone.pending('WAI001') == nil, 'repeated reports: rolled back after timeout + grace')

-- generic failure report ('nz:garage:spawned' failed = true -> NZ.Vehicles.spawnFailed)
addRow('GFL001', { lastOut = 777 })
waitRate()
data = call('ClaimVehicleForValet', 1, 'GFL001')
check(type(data) == 'table', 'claim 12 accepted')
advance(600)
local gfOk = run(Vehicles.spawnFailed, 1, 'GFL001')
advance(2500)
check(gfOk == true and db.GFL001.state == 'garaged' and db.GFL001.lastOut == 777 and NZ.Phone.pending('GFL001') == nil
  and kvp['nz_phone_claim:GFL001'] == nil, 'generic failure report: claim closed, previous lastOut restored')

check(#printed.error == 0, 'no lib.print.error: ' .. table.concat(printed.error, ' | '))

---------------------------------------------------------------------------------------
-- 9. Adapters in install/phone/ (loaded in their own environment, calling the exports)
---------------------------------------------------------------------------------------

resourceStates['nayzeee-garages'] = 'started'
local adapterExports = {
  ['nayzeee-garages'] = setmetatable({}, {
    __index = function(_, name)
      return function(_, ...) return exported[name](...) end
    end,
  }),
}
local registered = {}
local function loadAdapter(file, extra)
  local env = extra or {}
  env.exports = adapterExports
  env.lib = env.lib or { callback = { register = function(name, fn) registered[name] = fn end } }
  env._G = env
  -- real globals first; the harness' catch-all stubs only for natives (not the helper's table)
  setmetatable(env, { __index = function(_, k)
    local v = rawget(_G, k)
    if v ~= nil or (type(k) == 'string' and k:match('^Nayzeee')) then return v end
    return _G[k]
  end })
  local f = assert(io.open(file, 'r'), 'missing ' .. file)
  local src = f:read('a')
  f:close()
  local chunk = assert(load(src, '@' .. file, 't', env))
  local okLoad, err = xpcall(chunk, debug.traceback)
  check(okLoad, 'adapter loads: ' .. file .. ' ' .. tostring(err))
  return env
end

-- lb-phone (qb / qbox / esx files)
for _, fw in ipairs({ 'qb', 'qbox', 'esx' }) do
  local env = loadAdapter(('install/phone/lb-phone/server/custom/frameworks/%s/vehicles.lua'):format(fw),
    { Config = { Framework = fw } })
  check(type(env.GetPlayerVehicles) == 'function' and type(env.GetVehicle) == 'function', 'lb-phone ' .. fw .. ': functions defined')
  local other = loadAdapter(('install/phone/lb-phone/server/custom/frameworks/%s/vehicles.lua'):format(fw),
    { Config = { Framework = 'ox' } })
  check(rawget(other, 'GetPlayerVehicles') == nil, 'lb-phone ' .. fw .. ': guarded by Config.Framework')
end
local lb = loadAdapter('install/phone/lb-phone/server/custom/frameworks/qb/vehicles.lua', { Config = { Framework = 'qb' } })
addRow('IMP002', { state = 'impounded', impound = { locationId = 3, locationName = 'Davis Impound', reason = 'Evidence',
  fee = 0, byName = 'Officer Hayes', at = BASE_TIME - 60, releaseAt = BASE_TIME + 7200, retrievable = false } })
advance(1100)
local lbList = run(lb.GetPlayerVehicles, 1)
local lbBy = {}
for _, v in ipairs(lbList or {}) do lbBy[v.plate] = v end
check(lbBy.ABC123 and lbBy.ABC123.location == 'Legion Square' and lbBy.ABC123.impounded == false
  and lbBy.ABC123.model == joaat_('sultan') and lbBy.ABC123.type == 'car'
  and lbBy.ABC123.statistics.fuel == math.floor(db.ABC123.fuel + 0.5)
  and lbBy.ABC123.statistics.engine == math.floor(db.ABC123.engine + 0.5), 'lb-phone VehicleData (garaged)')
check(lbBy.IMP001 and lbBy.IMP001.impounded == true and lbBy.IMP001.location == 'Davis Impound'
  and lbBy.IMP001.impoundReason.retrievable == (BASE_TIME + 3600) * 1000 and lbBy.IMP001.impoundReason.price == 500
  and lbBy.IMP001.impoundReason.impounder == 'Officer Hayes', 'lb-phone VehicleData (impounded, JS ms)')
check(lbBy.IMP002 and lbBy.IMP002.impounded == true and lbBy.IMP002.impoundReason
  and lbBy.IMP002.impoundReason.retrievable == nil, 'lb-phone VehicleData: no release time for a police hold')
check(lbBy.LAT001 and lbBy.LAT001.location == 'out', 'lb-phone VehicleData (out)')
check(lbBy.BOAT01 and lbBy.BOAT01.type == 'boat', 'lb-phone VehicleData (boat type)')

addRow('LBP001')
waitRate()
local lbData = run(lb.GetVehicle, 1, 'LBP001')
check(type(lbData) == 'table' and lbData.hash == joaat_('sultan') and lbData.model == joaat_('sultan')
  and type(lbData.mods) == 'table' and lbData.mods.plate == 'LBP001' and type(lbData.vehicle) == 'string'
  and lbData.plate == 'LBP001' and db.LBP001.state == 'out', 'lb-phone GetVehicle claims and returns spawn data')
local lbCar, lbNet = spawnEntity('LBP001', 'sultan')
fireNet('nz:phone:spawned', 1, 'LBP001', lbNet)
check(Vehicles.out.LBP001 and Vehicles.out.LBP001.entity == lbCar, 'lb-phone client report tracked')
waitRate()
local before2 = #clientEvents
local lbNone = run(lb.GetVehicle, 1, 'IMP001')
check(lbNone == nil and #clientEvents > before2 and clientEvents[#clientEvents].name == 'nz:client:notify',
  'lb-phone GetVehicle refusal: nil + toast')

-- NPWD (Qbox): lib.callback
loadAdapter('install/phone/npwd_qbx_garages/server/server.lua')
local qbxCb = registered['npwd_qbx_garages:server:getPlayerVehicles']
check(type(qbxCb) == 'function', 'npwd_qbx_garages callback registered')
advance(1100)
local qbxList = qbxCb and run(qbxCb, 1) or {}
local qbxBy = {}
for _, v in ipairs(qbxList) do qbxBy[v.plate] = v end
check(qbxBy.ABC123 and qbxBy.ABC123.engine == math.floor(db.ABC123.engine * 10 + 0.5)
  and qbxBy.ABC123.body == math.floor(db.ABC123.body * 10 + 0.5) and qbxBy.ABC123.state == 'garaged'
  and qbxBy.ABC123.garage == 'Legion Square' and qbxBy.ABC123.fuel == math.floor(db.ABC123.fuel + 0.5),
  'npwd_qbx_garages GarageItem')
check(qbxBy.IMP001 and qbxBy.IMP001.state == 'impounded' and qbxBy.IMP001.garage == 'Davis Impound', 'npwd_qbx_garages impounded item')

-- NPWD (QBCore / ESX): net event -> client event, always answered
for _, spec in ipairs({
  { file = 'install/phone/npwd_qb_garage/server/server.lua', ev = 'npwd:qb-garage:getVehicles', reply = 'npwd:qb-garage:sendVehicles' },
  { file = 'install/phone/npwd_esx_garage/server/server.lua', ev = 'npwd:esx-garage:getVehicles', reply = 'npwd:esx-garage:sendVehicles' },
}) do
  loadAdapter(spec.file)
  advance(1100)
  local n = #clientEvents
  fireNet(spec.ev, 1)
  local reply = clientEvents[#clientEvents]
  check(#clientEvents == n + 1 and reply.name == spec.reply and reply.target == 1 and type(reply.payload) == 'table'
    and #reply.payload > 0, spec.reply .. ' answered with the list')
  online[3] = 'CID003'
  advance(1100)
  fireNet(spec.ev, 3)
  reply = clientEvents[#clientEvents]
  check(reply.name == spec.reply and reply.target == 3 and type(reply.payload) == 'table' and #reply.payload == 0,
    spec.reply .. ' answered (empty) for a player without vehicles')
  online[3] = nil
end
houses.Hh_a = location('Hh_a', 'house', { name = 'House garage', houseId = 'h_a',
  openPoints = { { coords = vec3(500, 0, 0), radius = 2.0 } } })
houses.Hh_b = location('Hh_b', 'house', { name = 'House garage', houseId = 'h_b',
  openPoints = { { coords = vec3(900, 0, 0), radius = 2.0 } } })
addRow('HSA001', { garageKey = 'Hh_a' })
addRow('HSA002', { garageKey = 'Hh_a' })
addRow('HSB001', { garageKey = 'Hh_b' })
local esxItems = {}
advance(1100)
fireNet('npwd:esx-garage:getVehicles', 1)
for _, v in ipairs(clientEvents[#clientEvents].payload or {}) do esxItems[v.plate] = v end
check(esxItems.HSA001 and esxItems.HSB001 and esxItems.HSA001.parking ~= esxItems.HSB001.parking
  and esxItems.HSA001.parking == esxItems.HSA002.parking and esxItems.HSA001.key == esxItems.HSA001.parking
  and esxItems.HSB001.parking:find('House garage', 1, true) == 1,
  'npwd_esx_garage: same name, other place -> distinct parking text (' .. tostring(esxItems.HSA001 and esxItems.HSA001.parking)
  .. ' / ' .. tostring(esxItems.HSB001 and esxItems.HSB001.parking) .. ')')
check(esxItems.GHI789 and esxItems.GHI789.parking == 'Legion Square', 'npwd_esx_garage: same garage keeps its plain name')
check(esxItems.ABC123 and esxItems.ABC123.stored == true and esxItems.ABC123.parking == 'Legion Square'
  and esxItems.ABC123.type == 'car' and esxItems.ABC123.coords, 'npwd_esx_garage item (garaged)')
check(esxItems.LBP001 and esxItems.LBP001.stored == false, 'npwd_esx_garage item (out)')
check(esxItems.IMP001 and esxItems.IMP001.pound == 'Davis Impound' and esxItems.IMP001.stored == true, 'npwd_esx_garage item (impounded)')
check(esxItems.BOAT01 and esxItems.BOAT01.type == 'boat', 'npwd_esx_garage item (boat)')

-- generic helper
local gen = loadAdapter('install/phone/generic/nayzeee_phone.lua')
local NP = gen.NayzeeePhone
check(type(NP) == 'table' and type(NP.qbRows) == 'function', 'generic helper defines NayzeeePhone')
advance(1100)
local qbRows = run(NP.qbRows, 1)
local qbBy = {}
for _, r in ipairs(qbRows or {}) do qbBy[r.plate] = r end
check(qbBy.ABC123 and qbBy.ABC123.state == 1 and qbBy.ABC123.engine == math.floor(db.ABC123.engine * 10 + 0.5)
  and qbBy.ABC123.garage == 'Legion Square',
  'generic qbRows (garaged)')
check(qbBy.IMP001 and qbBy.IMP001.state == 2 and qbBy.IMP001.depotprice == 500, 'generic qbRows (impounded)')
check(qbBy.LBP001 and qbBy.LBP001.state == 0, 'generic qbRows (out)')
advance(1100)
local esxRows = run(NP.esxRows, 1)
local esxBy = {}
for _, r in ipairs(esxRows or {}) do esxBy[r.plate] = r end
check(esxBy.ABC123 and esxBy.ABC123.stored == 1 and esxBy.IMP001 and esxBy.IMP001.pound == 'Davis Impound'
  and esxBy.IMP001.stored == 0, 'generic esxRows')
addRow('GEN001')
waitRate()
local gData = run(NP.claim, 1, 'GEN001')
check(type(gData) == 'table' and gData.model == joaat_('sultan') and db.GEN001.state == 'out', 'generic claim')
advance(600)
check(run(NP.release, 1, 'GEN001') == true and db.GEN001.state == 'garaged', 'generic release')

check(#printed.error == 0, 'no lib.print.error: ' .. table.concat(printed.error, ' | '))

---------------------------------------------------------------------------------------
-- 10. Resource restart with undelivered claims (KVP recovery) and the boot hint
---------------------------------------------------------------------------------------

addRow('RST001')
addRow('RST002', { lastOut = 1000 })
addRow('RST003', { owner = 'CID002' })
waitRate()
check(type(call('ClaimVehicleForValet', 1, 'RST001')) == 'table', 'restart: claim A accepted')
waitRate()
check(type(call('ClaimVehicleForValet', 1, 'RST002')) == 'table', 'restart: claim B accepted')
waitRate()
check(type(call('ClaimVehicleForValet', 2, 'RST003')) == 'table', 'restart: claim C accepted')
local claimedAt = os.time()
kvp['nz_phone_claim:ABC123'] = json.encode({ at = 12345, identifier = 'CID001' }) -- stale: the row moved on
kvp['nz_phone_claim:BAD001'] = 'not json'
local abcBefore = Utils.deepCopy(db.ABC123)

-- stop: every thread and the in-memory out registry die; player 2 leaves meanwhile
for i = #threads, 1, -1 do table.remove(threads, i) end
for plate in pairs(Vehicles.out) do Vehicles.out[plate] = nil end
online[2] = nil
-- NZ.Vehicles re-adopts by plate only: a car of another model wearing RST002's plate
local wearer, wearerNet = spawnEntity('RST002', 'blista')
Vehicles.setOut('RST002', { entity = wearer, netId = wearerNet, src = 1, identifier = 'CID001', adopted = true })
resourceStates['npwd_qbx_garages'] = 'started'
resourceStates['npwd_qb_garage'] = 'started' -- provided by npwd_qbx_garages
resourceStates['okokPhone'] = 'started'
printed.info = {}

-- start again
load_('server/phone.lua')
advance(100)
check(NZ.Phone.pending('RST001') ~= nil and NZ.Phone.pending('RST002') ~= nil, 'restart: undelivered claims resumed')
check(Vehicles.out.RST001 and Vehicles.out.RST001.src == 1, 'restart: out entry re-created for the online claimant')
check(kvp['nz_phone_claim:ABC123'] == nil and kvp['nz_phone_claim:BAD001'] == nil, 'restart: stale / broken entries removed')
check(db.ABC123.state == abcBefore.state and db.ABC123.lastOut == abcBefore.lastOut, 'restart: stale entry left the vehicle alone')
check(db.RST001.state == 'out' and db.RST002.state == 'out', 'restart: resumed claims keep the vehicles out')
check(Vehicles.out.RST002 and Vehicles.out.RST002.entity == nil and Vehicles.out.RST002.phone ~= nil,
  'restart: re-adopted car of another model dropped from the resumed claim')

local rstCar, rstNet = spawnEntity('RST001', 'sultan') -- the phone delivers after the restart
local keysBefore = #keysGiven
advance(2500)
check(Vehicles.out.RST001 and Vehicles.out.RST001.entity == rstCar and NZ.Phone.pending('RST001') == nil
  and kvp['nz_phone_claim:RST001'] == nil, 'restart: late delivery adopted')
check(#keysGiven > keysBefore and keysGiven[#keysGiven].plate == 'RST001' and keysGiven[#keysGiven].src == 1
  and keysGiven[#keysGiven].netId == rstNet, 'restart: keys for the online claimant')
check(db.RST003.state == 'garaged' and NZ.Phone.pending('RST003') == nil and kvp['nz_phone_claim:RST003'] == nil,
  'restart: claim of an offline player put back at once')

advance(5000)
local hints = table.concat(printed.info, '\n')
check(hints:find('npwd_qbx_garages found', 1, true) and hints:find('okokPhone found', 1, true)
  and hints:find('Config.Phone.hints = false', 1, true), 'boot hint for phones that never called the exports')
check(not hints:find('npwd_qb_garage found', 1, true), 'no hint for npwd_qb_garage provided by npwd_qbx_garages')
check(not hints:find('lb-phone found', 1, true), 'no hint for a phone that already calls the exports')

advance(50000 - (os.time() - claimedAt) * 1000)
check(db.RST002.state == 'out' and NZ.Phone.pending('RST002') ~= nil, 'restart: resumed claim not put back before its timeout')
advance(13000)
check(db.RST002.state == 'garaged' and db.RST002.lastOut == 1000 and NZ.Phone.pending('RST002') == nil
  and kvp['nz_phone_claim:RST002'] == nil, 'restart: undelivered claim put back after its original timeout')
check(entities[wearer] ~= nil and stateOf(wearer).nzInit == nil, 'restart: the other model was left alone')
DeleteEntity(wearer)

Config.Phone = { hints = false }
printed.info = {}
NZ.Phone.boot()
check(#printed.info == 0, 'Config.Phone.hints = false: no hint')
Config.Phone = nil
online[2] = 'CID002'

---------------------------------------------------------------------------------------
-- Valet of a vehicle still on its way to the impound on the NPC tow truck (NZ.Tow): released,
-- not deleted raw and not logged as a duplicate
---------------------------------------------------------------------------------------

addRow('TOW001')
local towedCar = spawnEntity('TOW001', 'sultan')
local towedSet = { [towedCar] = true }
NZ.Tow.isTowing = function(e) return towedSet[e] == true end
NZ.Tow.release = function(e)
  if not towedSet[e] then return false end
  towedSet[e] = nil
  DeleteEntity(e)
  return true
end
local function countLogs(event)
  local n = 0
  for _, l in ipairs(logs) do if l.event == event then n = n + 1 end end
  return n
end
local dupesBefore = countLogs('security.dupe')
waitRate()
local towClaim = call('ClaimVehicleForValet', 1, 'TOW001')
check(type(towClaim) == 'table' and entities[towedCar] == nil and towedSet[towedCar] == nil
  and countLogs('security.dupe') == dupesBefore, 'valet of a vehicle on the tow truck: NZ.Tow.release, no dupe log')
NZ.Tow.isTowing, NZ.Tow.release = nil, nil
waitRate()
call('ReleaseValetClaim', 1, 'TOW001')

check(#printed.error == 0, 'no lib.print.error: ' .. table.concat(printed.error, ' | '))

---------------------------------------------------------------------------------------
-- Report
---------------------------------------------------------------------------------------

if #failures > 0 then
  for _, f in ipairs(failures) do print('FAIL ' .. f) end
  print(('%d of %d check(s) failed'):format(#failures, checks))
  os.exit(1)
end
print(('phone OK (%d checks)'):format(checks))
