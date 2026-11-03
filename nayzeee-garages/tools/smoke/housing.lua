--[[
  Headless test for the house garage integrations (bridge/server/housing.lua + every loader in
  bridge/server/housing/*.lua + the hook exports in bridge/client/housing.lua). No FiveM needed.

  server: loads the real shared files, server/locations.lua, the housing core and every loader in
  a stubbed server runtime (clock, timers, KVP, convars, oxmysql answering per query, fake
  exports of every supported housing script with the data shapes the integrations accept),
  then checks: what each loader registers (ids, names, coords, hidden flag, access), the
  config modes, live access checks, the OpenHouseGarage / StoreHouseGarage hook callback
  (access, server-side position, property range, moves, refusals), reload hints, keeping
  houses when a read fails or comes back empty, deleted properties of incomplete loaders,
  the export API (register / access / remove) and the 'qb:' / 'ps:' / 'H..' compatibility.
  client: loads bridge/client/housing.lua with stubbed NZ.Garage / NZ.NUI / lib.callback and
  checks the hook exports (open, store while driving, refusals, busy guard).

  Usage (from the resource root):  lua5.4 tools/smoke/housing.lua [server|client]
]]

local side = arg[1] or 'server'
local dk = require('dkjson')

local failures, checks = {}, 0
local function check(cond, label)
  checks = checks + 1
  if not cond then failures[#failures + 1] = label end
end

---------------------------------------------------------------------------------------
-- Runtime: clock, threads, timers, events
---------------------------------------------------------------------------------------

local clock = 0
local threads = {}
function CreateThread(fn) threads[#threads + 1] = { co = coroutine.create(fn), wake = clock } end
function Wait(ms)
  if not coroutine.isyieldable() then error('Wait() outside a thread', 2) end
  coroutine.yield(ms or 0)
end
Citizen = { CreateThread = CreateThread, Wait = Wait }
function GetGameTimer() return clock end
function SetTimeout(ms, fn) CreateThread(function() Wait(ms) fn() end) end

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

local handlers, netHandlers, sent = {}, {}, {}
function AddEventHandler(name, fn) handlers[name] = handlers[name] or {} table.insert(handlers[name], fn) return name end
function RegisterNetEvent(name, fn) if fn then netHandlers[name] = fn end return name end
function TriggerEvent(name, ...) for _, fn in ipairs(handlers[name] or {}) do fn(...) end end
function TriggerClientEvent(name, target, payload) sent[#sent + 1] = { name = name, target = target, payload = payload } end
function TriggerServerEvent() end

local function vec3(x, y, z) return { x = x or 0.0, y = y or 0.0, z = z or 0.0 } end
function vector3(x, y, z) return vec3(x, y, z) end
function vector4(x, y, z, w) return { x = x or 0.0, y = y or 0.0, z = z or 0.0, w = w or 0.0 } end
vec4 = vector4

json = {
  encode = function(v) return dk.encode(v) end,
  decode = function(s) if type(s) ~= 'string' then return nil end return (dk.decode(s)) end,
}

local printed = { warn = {}, error = {}, info = {} }
lib = {
  print = {
    info = function(...) printed.info[#printed.info + 1] = table.concat({ ... }, ' ') end,
    warn = function(...) printed.warn[#printed.warn + 1] = table.concat({ ... }, ' ') end,
    error = function(...) printed.error[#printed.error + 1] = table.concat({ ... }, ' ') end,
    debug = function() end,
  },
}

local resourceStates = {}
function GetResourceState(name) return resourceStates[name] or 'missing' end
function GetCurrentResourceName() return 'nayzeee-garages' end
function IsDuplicityVersion() return side == 'server' end

local convars = {}
function GetConvar(name, default) if convars[name] ~= nil then return convars[name] end return default end

local function load_(file)
  local f = assert(io.open(file, 'r'), 'missing ' .. file)
  local src = f:read('a')
  f:close()
  local chunk = assert(load(src, '@' .. file, 't', _ENV))
  local okLoad, err = xpcall(chunk, debug.traceback)
  if not okLoad then failures[#failures + 1] = 'load ' .. file .. ': ' .. tostring(err) end
end

local function finish()
  if os.getenv("HOUSING_VERBOSE") then for _, w in ipairs(printed.warn) do print("warn: " .. w) end for _, w in ipairs(printed.info) do print("info: " .. w) end end
  for _, e in ipairs(printed.error) do failures[#failures + 1] = 'lib.print.error: ' .. e end
  if #failures > 0 then
    print(('housing %s: %d check(s), %d failure(s)'):format(side, checks, #failures))
    for _, f in ipairs(failures) do print('  FAIL ' .. f) end
    os.exit(1)
  end
  print(('housing %s OK (%d checks)'):format(side, checks))
end

---------------------------------------------------------------------------------------
-- Client side: the hook exports
---------------------------------------------------------------------------------------

if side == 'client' then
  local exported = {}
  exports = setmetatable({}, {
    __call = function(_, name, fn) exported[name] = fn end,
    __index = function() return setmetatable({}, { __index = function() return function() return nil end end }) end,
  })
  local driving = false
  cache = { ped = 1 }
  function PlayerPedId() return 1 end
  function GetVehiclePedIsIn() return driving and 50 or 0 end
  function GetPedInVehicleSeat() return 1 end
  setmetatable(_G, { __index = function(_, k)
    if type(k) == 'string' and k:match('^%u') then return function() return nil end end
    return nil
  end })

  local answer, awaited = nil, {}
  lib.callback = {
    register = function() end,
    await = function(name, _, payload)
      awaited[#awaited + 1] = { name = name, payload = payload }
      Wait(100)
      if type(answer) == 'function' then return answer(name, payload) end
      return answer
    end,
  }

  load_('config/config.lua')
  load_('shared/init.lua')
  load_('shared/utils.lua')
  load_('bridge/shared.lua')
  local notes, opened, stored, rebuilds = {}, {}, {}, 0
  NZ.State = { ready = true, houses = {}, locations = {} }
  NZ.NUI.notify = function(kind, msg) notes[#notes + 1] = { kind = kind, msg = msg } end
  NZ.Points.rebuild = function() rebuilds = rebuilds + 1 end
  NZ.Garage.open = function(locationId, extra) opened[#opened + 1] = { locationId = locationId, extra = extra } return true end
  NZ.Garage.store = function(view) stored[#stored + 1] = view return true end
  NZ.Bridge.getIdentifier = function() return 'CID1' end
  load_('bridge/client/housing.lua')

  check(type(exported.OpenHouseGarage) == 'function', 'client: OpenHouseGarage export')
  check(type(exported.StoreHouseGarage) == 'function', 'client: StoreHouseGarage export')
  check(type(exported.RefreshHouseGarages) == 'function', 'client: RefreshHouseGarages export')

  local view = { id = 'Hvms:12', kind = 'house', houseId = 'vms:12', name = 'VMS Villa', hidden = true,
    openPoints = { { coords = vec3(1, 2, 3), radius = 2.0 } }, spawnPoints = { vector4(1, 2, 3, 0) } }
  answer = { ok = true, data = { houseId = 'vms:12', action = 'open', views = { view } } }
  check(exported.OpenHouseGarage('vms:12', { name = 'From vms', coords = vec3(9, 9, 9) }) == true, 'client: open accepted')
  advance(500)
  check(#awaited == 1 and awaited[1].name == 'nz:housing:hook', 'client: hook callback called')
  check(awaited[1].payload.houseId == 'vms:12' and awaited[1].payload.action == 'open', 'client: hook payload')
  check(awaited[1].payload.coords == nil, 'client: no client coordinates are sent')
  check(awaited[1].payload.name == 'From vms', 'client: label passed')
  check(#opened == 1 and opened[1].extra.houseId == 'vms:12', 'client: garage menu opened for the house')
  check(NZ.State.houses['Hvms:12'] ~= nil and rebuilds == 1, 'client: house view applied, points rebuilt once')

  -- Driving: OpenHouseGarage stores instead.
  driving = true
  exported.OpenHouseGarage('vms:12')
  advance(500)
  check(awaited[2].payload.action == 'store', 'client: open while driving stores')
  check(#stored == 1 and stored[1].houseId == 'vms:12', 'client: store flow used')
  check(rebuilds == 1, 'client: unchanged list does not rebuild the points')

  -- Store on foot is refused locally.
  driving = false
  exported.StoreHouseGarage('vms:12')
  advance(500)
  check(#awaited == 2, 'client: store on foot does not call the server')
  check(notes[#notes] and notes[#notes].kind == 'error', 'client: store on foot notifies')

  -- Server refusal is shown.
  answer = { ok = false, error = 'You do not have access to this house garage' }
  exported.OpenHouseGarage(12)
  advance(500)
  check(awaited[3].payload.houseId == '12', 'client: numeric ids become strings')
  check(notes[#notes].msg == 'You do not have access to this house garage', 'client: server refusal shown')
  check(#opened == 1, 'client: refused hook opens nothing')

  -- Busy guard: a second call while the first waits is ignored.
  answer = { ok = true, data = { houseId = 'vms:12', action = 'open', views = { view } } }
  exported.OpenHouseGarage('vms:12')
  exported.OpenHouseGarage('vms:12')
  advance(500)
  check(#awaited == 4 and #opened == 2, 'client: concurrent hook calls are coalesced')

  -- Bad ids.
  exported.OpenHouseGarage({})
  advance(200)
  check(#awaited == 4, 'client: invalid id rejected locally')

  -- The answer names a house the client does not get: nothing opens.
  answer = { ok = true, data = { houseId = 'tk:3', action = 'open', views = {} } }
  exported.OpenHouseGarage('tk:3')
  advance(500)
  check(#opened == 2 and NZ.State.houses['Hvms:12'] == nil, 'client: unknown house view refused')

  -- RxHousing fmLib adapter (install/housing/RxHousing): which fmLib garage ids are houses.
  do
    local calls = {}
    local env = setmetatable({
      AdapterResources = { garage = { { key = 'other', resource = 'other_garages' } } },
      GetResourceState = function() return 'started' end,
      print = function() end,
      exports = setmetatable({}, { __index = function()
        return setmetatable({}, { __index = function(_, fn)
          return function(_, ...) calls[#calls + 1] = { fn = fn, args = { ... } } return true end
        end })
      end }),
    }, { __index = _G })
    env._G = env
    local f = assert(io.open('install/housing/RxHousing/fmLib/adapters/client/garage/nayzeee.lua', 'r'))
    local chunk = assert(load(f:read('a'), '@install/housing/RxHousing/fmLib/adapters/client/garage/nayzeee.lua', 't', env))
    f:close()
    chunk()
    local adapter = env.FM_Adapter_client_garage_nayzeee
    check(type(adapter) == 'table' and env.AdapterResources.garage[1].key == 'nayzeee', 'rx adapter: registered first in fmLib detection')
    local function last() return calls[#calls] or {} end
    local cases = {
      { 'property_12', 'OpenHouseGarage', 'rx:12' }, { 12.0, 'OpenHouseGarage', 'rx:12' },
      { 'rx:012', 'OpenHouseGarage', 'rx:12' }, { '7', 'OpenHouseGarage', 'rx:7' },
      { 'House Garage (7)', 'OpenHouseGarage', 'rx:7' }, { 'rxhousing_12', 'OpenHouseGarage', 'rx:12' },
      { 'rx_police_2', 'OpenGarage', nil }, { 'pillbox_1', 'OpenGarage', nil }, { -3, 'OpenGarage', nil },
    }
    for _, c in ipairs(cases) do
      adapter.open(c[1])
      check(last().fn == c[2] and last().args[1] == c[3], ('rx adapter: %s -> %s %s'):format(tostring(c[1]), c[2], tostring(c[3])))
    end
    check(adapter.parkVehicle('property_3') == true and last().fn == 'StoreHouseGarage' and last().args[1] == 'rx:3', 'rx adapter: park stores in the house')
  end

  finish()
  return
end

---------------------------------------------------------------------------------------
-- Server side
---------------------------------------------------------------------------------------

-- Players: server id -> identifier, position, heading, license.
local online = { [1] = 'CID1', [2] = 'CID2', [3] = 'CID3' }
local positions = { [1] = vec3(0, 0, 0), [2] = vec3(0, 0, 0), [3] = vec3(0, 0, 0) }
local jobs = { [1] = 'police' }
function GetPlayers() local out = {} for src in pairs(online) do out[#out + 1] = tostring(src) end table.sort(out) return out end
function GetPlayerPed(src) return online[tonumber(src)] and (1000 + tonumber(src)) or 0 end
function GetVehiclePedIsIn() return 0 end
function GetEntityCoords(ped) local p = positions[ped - 1000] return p and vec3(p.x, p.y, p.z) or nil end
function GetEntityHeading() return 90.0 end
function GetPlayerIdentifierByType(src) return 'license:' .. tostring(src) end
function GetPlayerName(src) return 'Player' .. tostring(src) end

local kvp = {}
function SetResourceKvp(k, v) kvp[k] = v end
function GetResourceKvpString(k) return kvp[k] end
function DeleteResourceKvp(k) kvp[k] = nil end
local kvpHandles = {}
function StartFindKvp(prefix)
  local keys = {}
  for k in pairs(kvp) do if k:sub(1, #prefix) == prefix then keys[#keys + 1] = k end end
  table.sort(keys)
  kvpHandles[#kvpHandles + 1] = { keys = keys, i = 0 }
  return #kvpHandles
end
function FindKvp(h) local s = kvpHandles[h] s.i = s.i + 1 return s.keys[s.i] end
function EndFindKvp() end

local files = {}
function LoadResourceFile(resource, name) return files[resource .. '/' .. name] end

setmetatable(_G, { __index = function(_, k)
  if type(k) == 'string' and k:match('^%u') then return function() return nil end end
  return nil
end })

-- ox_lib callbacks
local callbacks = {}
lib.callback = { register = function(name, fn) callbacks[name] = fn end }

-- Fake exports: exports[resource][name](self, ...)
local api = {}           -- [resource] = { name = fn(...) }
local exportCalls = {}   -- ['resource:name'] = count
local ownExports = {}    -- exports this resource registers (exports(name, fn))
exports = setmetatable({}, {
  __call = function(_, name, fn) ownExports[name] = fn end,
  __index = function(_, resource)
    return setmetatable({}, { __index = function(_, name)
      return function(_, ...)
        local key = resource .. ':' .. name
        exportCalls[key] = (exportCalls[key] or 0) + 1
        local set = api[resource]
        local fn = set and set[name]
        if not fn then error(('No such export %s in resource %s'):format(name, resource)) end
        return fn(...)
      end
    end })
  end,
})

-- oxmysql: answers by table name, can fail on demand.
local db = { tables = {} }
local queries = {}
MySQL = { query = { await = function(sql, params)
  queries[#queries + 1] = sql
  if db.down then error('database offline') end
  if sql:find('information_schema', 1, true) then
    return db.tables[params[1]] and { { ['1'] = 1 } } or {}
  end
  local name = sql:match('FROM `([%w_]+)`')
  if name == 'properties' and sql:find('JSON_LENGTH', 1, true) and db.psTightFails then
    error('FUNCTION JSON_LENGTH does not exist')
  end
  local source = db[name]
  if type(source) == 'function' then return source(sql, params) end
  if source == nil then error(("Table '%s' doesn't exist"):format(tostring(name))) end
  return source
end } }

---------------------------------------------------------------------------------------
-- Load the resource files
---------------------------------------------------------------------------------------

load_('config/config.lua')
load_('shared/init.lua')
load_('shared/utils.lua')
load_('bridge/shared.lua')
Config.Integrations.housing = 'auto'

local settings = { ['garages.maxDistance'] = 25.0 }
NZ.Settings.get = function(path, default) if settings[path] ~= nil then return settings[path] end return default end
NZ.Logs.add = function() end
NZ.Bridge.getIdentifier = function(src) return online[tonumber(src)] end
NZ.Bridge.getSourceByIdentifier = function(identifier)
  for src, id in pairs(online) do if id == identifier then return src end end
  return nil
end
NZ.Bridge.getJob = function(src) return jobs[tonumber(src)] and { name = jobs[tonumber(src)], grade = 0 } or nil end
local rateBlocked = false
NZ.Access.rateLimit = function() return not rateBlocked end

load_('server/locations.lua')
load_('server/exports.lua')
load_('bridge/server/housing.lua')
for _, name in ipairs({ 'qb', 'ps', 'qs', 'esx', 'loaf', 'vms', 'bcs', 'tk', 'rtx', 'rx', 'nolag' }) do
  load_('bridge/server/housing/' .. name .. '.lua')
end
NZ.Ready = true
local Housing = NZ.Housing

---------------------------------------------------------------------------------------
-- Housing script data (the shapes the integrations read)
---------------------------------------------------------------------------------------

for _, name in ipairs({ 'qb-houses', 'qs-housing', 'ps-housing', 'esx_property', 'loaf_housing', 'vms_housing',
  'bcs_housing', 'tk_housing', 'rtx_housing', 'RxHousing', 'nolag_properties' }) do
  resourceStates[name] = 'started'
end

-- qb-houses / qs-housing tables
db.houselocations = function(sql)
  local rows = {
    { name = 'grove1', label = 'Grove 1', garage = '{"x":100.0,"y":200.0,"z":30.0,"h":90.0}' },
    { name = 'vinewood', label = 'Vinewood Hills', garage = dk.encode({ coords = { x = 300.0, y = -100.0, z = 40.0, w = 180.0 },
      slots = { { x = 306.0, y = -100.0, z = 40.0, w = 180.0 } } }) },
    { name = 'samespot', adress = 'Same Spot', garage = dk.encode({ coords = { x = 350.0, y = -100.0, z = 40.0, h = 10.0 },
      slots = { { x = 350.5, y = -100.0, z = 40.0, w = 10.0 } } }) },
  }
  if not sql:find("NOT IN", 1, true) then rows[#rows + 1] = { name = 'nogarage', label = 'No garage', garage = '[]' } end
  return rows
end
db.player_houses = {
  { house = 'grove1', citizenid = 'CID1', keyholders = '["CID2"]' },
  { house = 'vinewood', citizenid = 'CID2', keyholders = '{"CID3":true}' },
  { house = 'samespot', identifier = 'CID3', keyholders = '[]' },
}

-- ps-housing
db.properties = function(sql)
  local rows = {
    { property_id = 7, owner_citizenid = 'CID1', has_access = '["CID3"]', street = 'Elgin Ave',
      garage_data = '{"x":500.0,"y":500.0,"z":20.0,"h":45.0,"length":3.0,"width":5.0}' },
  }
  if not sql:find('JSON_LENGTH', 1, true) then
    rows[#rows + 1] = { property_id = 8, owner_citizenid = 'CID2', has_access = '[]', street = 'Apt', garage_data = '{}' }
  end
  return rows
end
local psOwners = { ['7'] = { CID1 = true, CID3 = true } }
api['ps-housing'] = {
  IsOwner = function(src, id) local set = psOwners[tostring(id)] return set ~= nil and set[online[src]] == true end,
}

-- esx_property
local esxProps = {
  { Name = 'Beach House', setName = '', Owner = 'CID2', Owned = true, Keys = { CID3 = { name = 'Bob' } },
    garage = { enabled = true, pos = { x = -1000.0, y = -1500.0, z = 5.0 }, Heading = 270.0 } },
  { Name = 'Shack', setName = 'My Shack', Owner = 'CID1', Owned = true, Keys = {},
    garage = { enabled = false, pos = { x = -900.0, y = -1500.0, z = 5.0 } } },
}
api.esx_property = {
  GetProperties = function() return esxProps end,
  DoesPlayerHaveKeys = function(id, identifier)
    local p = esxProps[id]
    return p ~= nil and p.Keys[identifier] ~= nil
  end,
}

-- loaf_housing (+ loaf_keysystem table)
db.loaf_properties = {
  { owner = 'CID1', propertyid = 3, id = 'AA-0001' },
  { owner = 'CID2', propertyid = 3, id = 'AB-0002' },
  { owner = 'CID3', propertyid = 4, id = 'AA-0001' },
}
db.loaf_keys = {
  { identifier = 'CID3', key_id = 'housing_key_3_AA-0001' },
  { identifier = 'CID1', key_id = 'housing_key_3_ZZ-9999' },
}
db.tables.loaf_keys = true
api.loaf_housing = {
  GetHouse = function(id)
    if id == 3 then
      return { label = 'Mirror Park 3', garage = { entrance = vec3(1000.0, -500.0, 60.0), exit = vector4(1005.0, -505.0, 60.0, 120.0) } }
    end
    if id == 4 then return { label = 'No garage here' } end
    return nil
  end,
}

-- vms_housing (hook-driven, access only)
local vmsProps = {
  ['12'] = { id = 12, type = 'house', owner = 'CID1', keys = '{"CID2":"Bob"}', name = 'VMS Villa',
    metadata = dk.encode({ enter = { x = 2000.0, y = 2000.0, z = 10.0 } }) },
  ['13'] = { id = 13, type = 'building', owner = 'CID3', name = 'VMS Tower', metadata = '{}' },
}
local vmsFails = false
api.vms_housing = {
  GetAllProperties = function() if vmsFails then error('boom') end return vmsProps end,
  GetProperty = function(id) return vmsProps[tostring(id)] end,
  HasKeys = function() return false end,
  HasAnyPermission = function() return false end,
}
db.houses = function(sql)
  if sql:find('houseid', 1, true) then return {} end
  return {}
end

-- bcs_housing (documented shape, unconfirmed)
api.bcs_housing = {
  GetHomes = function()
    return {
      { identifier = 'h1', configuration = { garage = true },
        properties = { name = 'BCS Home', owner = 'CID3', data = { garage = vector4(3000.0, 3000.0, 20.0, 10.0) } } },
      { identifier = 'h2', properties = { name = 'BCS Flat', owner = 'CID1', entry = vec3(3100.0, 3100.0, 20.0), data = {} } },
    }
  end,
  GetHome = function(id)
    if id == 'h2' then return { identifier = 'h2', properties = { name = 'BCS Flat', owner = 'CID1', entry = vec3(3100.0, 3100.0, 20.0), data = {} } } end
    return nil
  end,
  GetKeyHolders = function(id)
    if id == 'h1' then return { CID1 = { name = 'Ann', key = 'Garage' }, CID2 = { name = 'Bob', key = 'Door 1' } } end
    return {}
  end,
  HasKey = function(id, identifier, permission)
    return id == 'h1' and permission == 'Garage' and identifier == 'CID1'
  end,
}

-- tk_housing (hook-driven)
local tkProps = {
  { id = 1, name = 'TK House', owner = 'CID2', permissions = { CID3 = { garage = true } }, coords = vec3(4000.0, 4000.0, 30.0) },
  { id = 2, name = 'TK Station', owner = 'job:police', permissions = { ['job:police'] = {} }, coords = vec3(4100.0, 4000.0, 30.0) },
}
local tkEmpty = false
api.tk_housing = {
  getProperties = function() if tkEmpty then return {} end return tkProps end,
  getPropertyKeyholders = function(id)
    if id == 1 then return { { identifier = 'CID3', name = 'Cid Three' } } end
    error('no keyholders export')
  end,
  getPropertyData = function(id) for _, p in ipairs(tkProps) do if p.id == id then return p end end return nil end,
}

-- rtx_housing
local rtxLive = false
api.rtx_housing = {
  GetAllProperties = function()
    return {
      { houseid = 5, owner = 'CID1', propertyname = 'RTX House',
        garage = { enabled = true, coords = { x = 6000.0, y = 6000.0, z = 40.0 }, heading = 90.0 },
        permissions = {
          CID2 = { identifierdata = 'CID2', permissions = { garage = true } },
          CID3 = { identifierdata = 'CID3', permissions = { garage = false } },
        } },
      { houseid = 6, owner = 'CID2', propertyname = 'RTX Disabled',
        housedata = dk.encode({ garage = { enabled = false, coords = { x = 6100.0, y = 6000.0, z = 40.0 } } }) },
    }
  end,
  GetPropertyPermission = function(src, id, perm) return rtxLive and id == 5 and perm == 'garage' and src == 3 end,
}

-- RxHousing
api.RxHousing = {
  GetAllProperties = function()
    return { ['9'] = { id = 9, owner = 'CID3', label = 'RX Flat', keyholders = { 'CID1' },
      coords = { entrance = vec3(7000.0, 7000.0, 10.0) } } }
  end,
  GetProperty = function(id)
    if tonumber(id) == 9 then return { id = 9, owner = 'CID3', coords = { entrance = vec3(7000.0, 7000.0, 10.0) } } end
    return nil
  end,
  HasKey = function(id, identifier) return tonumber(id) == 9 and identifier == 'CID1' end,
}

-- nolag_properties (hook-driven, no list export)
local nolagProps = {
  [21] = { id = 21, owner = 'CID1', ownerType = 'user', label = 'Nolag Loft', metadata = { enterData = { x = 8000.0, y = 8000.0, z = 10.0 } } },
  [22] = { id = 22, owner = 'police', ownerType = 'society', label = 'Precinct Lot', metadata = {} },
}
api.nolag_properties = {
  GetPropertyData = function(id) return nolagProps[id] end,
  GetKeyHolders = function(id) if id == 21 then return { CID2 = true } end return {} end,
  HasKey = function(identifier, id) return id == 21 and identifier == 'CID2' end,
}

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function house(id) return NZ.Locations.get('H' .. id) end
local function viewIds(identifier)
  local out = {}
  for _, v in ipairs(Housing.viewsFor(identifier)) do out[v.houseId] = v end
  return out
end
local function hook(src, houseId, action, name)
  return run(callbacks['nz:housing:hook'], src, { houseId = houseId, action = action or 'open', name = name })
end
local function near(a, b, tol) return math.abs(a - b) <= (tol or 0.01) end
local function reloadAll()
  Housing.refresh()
  advance(20000)
end

---------------------------------------------------------------------------------------
-- Boot
---------------------------------------------------------------------------------------

check(type(callbacks['nz:housing:hook']) == 'function', 'hook callback registered')
check(type(callbacks['nz:housing:refresh']) == 'function', 'refresh callback registered')
run(Housing.boot)
advance(100)

-- qb-houses is skipped in 'auto' while qs-housing runs (same tables): qs reads them.
check(house('qb:grove1') == nil, 'auto: qb-houses skipped while qs-housing runs')
local qs1 = house('qs:grove1')
check(qs1 ~= nil and qs1.name == 'Grove 1', 'qs: house with flat garage JSON')
check(qs1 and near(qs1.openPoints[1].coords.x, 100.0) and near(qs1.spawnPoints[1].w, 90.0), 'qs: coords + heading')
check(qs1 and not qs1.hidden, 'qs: our own point is drawn')
local qs2 = house('qs:vinewood')
check(qs2 and near(qs2.spawnPoints[1].x, 306.0), 'qs: parking slot far from the point is the spawn')
local qs3 = house('qs:samespot')
check(qs3 and near(qs3.spawnPoints[1].x, 350.0) and qs3.name == 'Same Spot', 'qs: slot on the point ignored, adress label')
check(house('qs:nogarage') == nil, 'qs: empty garage skipped')
check(Housing.hasAccess('CID2', 'qs:grove1') and Housing.hasAccess('CID3', 'qs:vinewood'), 'qs: key holders (array / map)')
check(Housing.hasAccess('CID3', 'qs:samespot'), 'qs: identifier column owner')
check(not Housing.hasAccess('CID3', 'qs:grove1'), 'qs: no access for others')

local ps7 = house('ps:7')
check(ps7 ~= nil and ps7.name == 'Elgin Ave 7', 'ps: property 7 registered')
check(ps7 and near(ps7.spawnPoints[1].w, 45.0), 'ps: heading from h')
check(house('ps:8') == nil, 'ps: empty garage_data skipped')
check(Housing.hasAccess('CID3', 'ps:7') and Housing.hasAccess('CID1', 'Hps:7'), 'ps: owner + has_access, H prefix accepted')
local psQuery
for _, q in ipairs(queries) do if q:find('`properties`', 1, true) then psQuery = q end end
check(psQuery and psQuery:find('JSON_LENGTH', 1, true) ~= nil, 'ps: tight query used')

local esx1 = house('esx:1')
check(esx1 ~= nil and esx1.name == 'Beach House #1', 'esx: enabled garage registered')
check(esx1 and near(esx1.spawnPoints[1].w, 270.0), 'esx: Heading applied')
check(house('esx:2') == nil, 'esx: disabled garage skipped')
check(Housing.hasAccess('CID3', 'esx:1') and not Housing.hasAccess('CID1', 'esx:1'), 'esx: Keys map + owner')

local loaf3 = house('loaf:3')
check(loaf3 ~= nil and loaf3.name == 'Mirror Park 3', 'loaf: garage from GetHouse')
check(loaf3 and near(loaf3.openPoints[1].coords.x, 1000.0) and near(loaf3.spawnPoints[1].x, 1005.0)
  and near(loaf3.spawnPoints[1].w, 120.0), 'loaf: entrance = open point, exit = spawn')
check(house('loaf:4') == nil, 'loaf: property without garage skipped')
check(Housing.hasAccess('CID1', 'loaf:3') and Housing.hasAccess('CID2', 'loaf:3') and Housing.hasAccess('CID3', 'loaf:3'),
  'loaf: every owner instance + key holder of an existing instance')

check(house('vms:12') == nil, 'vms: no garage until the hook places it')
check(Housing.hasAccess('CID2', 'vms:12'), 'vms: identifier-keyed keys map')
resourceStates.vms_housing = 'stopped' -- cached sets only
check(not Housing.hasAccess('CID3', 'vms:13'), 'vms: buildings skipped')
resourceStates.vms_housing = 'started'

local bcs1 = house('bcs:h1')
check(bcs1 ~= nil and bcs1.name == 'BCS Home' and not bcs1.hidden, 'bcs: data.garage registered, drawn by us')
check(Housing.hasAccess('CID1', 'bcs:h1') and not Housing.hasAccess('CID2', 'bcs:h1'), 'bcs: only Garage key holders')
check(house('bcs:h2') == nil and Housing.hasAccess('CID1', 'bcs:h2'), 'bcs: home without garage: access only')

check(house('tk:1') == nil and Housing.hasAccess('CID3', 'tk:1') and Housing.hasAccess('CID2', 'tk:1'), 'tk: owner + key holders')
check(viewIds('job:police')['tk:2'] == nil, 'tk: job keys are not identifiers')

local rtx5 = house('rtx:5')
check(rtx5 ~= nil and rtx5.name == 'RTX House' and near(rtx5.spawnPoints[1].w, 90.0), 'rtx: garage + heading')
check(house('rtx:6') == nil, 'rtx: disabled garage (JSON housedata) skipped')
check(Housing.hasAccess('CID2', 'rtx:5') and not Housing.hasAccess('CID3', 'rtx:5', nil), 'rtx: garage permission only')

check(house('rx:9') == nil and Housing.hasAccess('CID1', 'rx:9'), 'rx: access without garage point')

local cid1 = viewIds('CID1')
check(cid1['qs:grove1'] and cid1['ps:7'] and cid1['loaf:3'] and cid1['rtx:5'] and cid1['bcs:h1'], 'viewsFor: CID1 sees its houses')
check(cid1['vms:12'] == nil, 'viewsFor: houses without a garage are not listed')

---------------------------------------------------------------------------------------
-- Live access checks
---------------------------------------------------------------------------------------

rtxLive = true
advance(11000) -- live cache expires
check(Housing.hasAccess('CID3', 'rtx:5', 3) == true, 'rtx: live GetPropertyPermission for an online player')
check(Housing.hasAccess('CID3', 'tk:1') == true, 'tk: live permissions')
tkProps[1].permissions.CID1 = {}
check(Housing.hasAccess('CID1', 'tk:1') == true, 'tk: live check sees a new key before the reload')
check(Housing.hasAccess('CID2', 'esx:1') == true, 'esx: owner from the list')
-- ps IsOwner is only asked for a loaded player
psOwners['7'].CID2 = true
check(Housing.hasAccess('CID2', 'ps:7') == true, 'ps: live IsOwner')
online[2] = nil
advance(11000) -- live cache expires
check(Housing.hasAccess('CID2', 'ps:7') == false, 'ps: IsOwner not trusted for an offline player')
online[2] = 'CID2'

---------------------------------------------------------------------------------------
-- Hook: OpenHouseGarage / StoreHouseGarage
---------------------------------------------------------------------------------------

positions[1] = vec3(2010.0, 2005.0, 10.0)
local res = hook(1, 'vms:12', 'open', 'Client label')
check(res.ok and res.data.houseId == 'vms:12', 'hook: vms owner accepted')
local v12 = house('vms:12')
check(v12 and v12.hidden == true, 'hook: vms garage registered hidden')
check(v12 and near(v12.openPoints[1].coords.x, 2010.0) and near(v12.spawnPoints[1].w, 90.0), 'hook: placed at the server-side ped position')
check(v12 and v12.name == 'VMS Villa', 'hook: loader name wins over the client label')
check(kvp['nz_housing:spot:vms:12'] ~= nil, 'hook: position saved in KVP')
local found = false
for _, v in ipairs(res.data.views) do if v.houseId == 'vms:12' and v.hidden == true then found = true end end
check(found, 'hook: answer carries the hidden view')

positions[3] = vec3(2010.0, 2005.0, 10.0)
res = hook(3, 'vms:12')
check(not res.ok, 'hook: no access refused')

positions[2] = vec3(2600.0, 2000.0, 10.0)
advance(2000)
res = hook(2, 'vms:13')
check(not res.ok, 'hook: building ids are not houses of the loader')
res = hook(2, 'vms:12')
check(not res.ok, 'hook: garage not moved 600 m away from the property')
check(near(house('vms:12').openPoints[1].coords.x, 2010.0), 'hook: refused move keeps the garage')
convars.nayzeee_housing_hook_range = '0'
advance(2000)
res = hook(2, 'vms:12')
check(res.ok and near(house('vms:12').openPoints[1].coords.x, 2600.0), 'hook: range convar 0 disables the property range')
convars.nayzeee_housing_hook_range = nil
positions[2] = vec3(2010.0, 2005.0, 10.0)
advance(2000)
hook(2, 'vms:12')

positions[1] = vec3(2013.0, 2005.0, 10.0)
advance(2000)
hook(1, 'vms:12')
check(near(house('vms:12').openPoints[1].coords.x, 2010.0), 'hook: small step does not move the garage')
positions[1] = vec3(2030.0, 2005.0, 10.0)
advance(2000)
hook(1, 'vms:12')
check(near(house('vms:12').openPoints[1].coords.x, 2030.0), 'hook: used 20 m away moves the garage')
settings['garages.maxDistance'] = 4.0
positions[1] = vec3(2033.0, 2005.0, 10.0)
advance(2000)
hook(1, 'vms:12')
check(near(house('vms:12').openPoints[1].coords.x, 2033.0), 'hook: move distance follows a small garages.maxDistance')
settings['garages.maxDistance'] = 25.0

-- Never-hook scripts: no garage is created through the hook.
positions[1] = vec3(100.0, 200.0, 30.0)
advance(2000)
res = hook(1, 'qs:nogarage')
check(not res.ok, 'hook: qs house without garage refused')
check(house('qs:nogarage') == nil, 'hook: nothing registered for it')
res = hook(1, 'qs:grove1', 'store')
check(res.ok and res.data.action == 'store', 'hook: qs house with a garage accepted')
check(near(house('qs:grove1').openPoints[1].coords.x, 100.0), 'hook: loader coordinates of qs never move')

-- whenUsed + create: bcs home without a readable garage point, bounded by its entrance.
positions[1] = vec3(3105.0, 3100.0, 20.0)
advance(2000)
res = hook(1, 'bcs:h2')
check(res.ok and house('bcs:h2') and house('bcs:h2').hidden, 'hook: bcs garage created next to the entrance')
positions[1] = vec3(5000.0, 3100.0, 20.0)
advance(2000)
res = hook(1, 'bcs:h2')
check(not res.ok, 'hook: bcs garage not moved 1.9 km from the entrance')

-- rtx (whenUsed, no create): a known garage only.
positions[3] = vec3(6000.0, 6000.0, 40.0)
advance(2000)
res = hook(3, 'rtx:5')
check(res.ok and not house('rtx:5').hidden, 'hook: rtx live permission accepted, loader point kept')
res = hook(1, 'rtx:6')
check(not res.ok, 'hook: rtx disabled garage refused')

-- tk: hook only.
positions[2] = vec3(4005.0, 4000.0, 30.0)
advance(2000)
res = hook(2, 'tk:1')
check(res.ok and house('tk:1') and house('tk:1').hidden, 'hook: tk garage placed')
check(viewIds('CID3')['tk:1'] ~= nil, 'hook: key holders see the new garage')
local pushed = false
advance(1000)
for _, e in ipairs(sent) do if e.name == 'nz:client:houses' and e.target == 3 then pushed = true end end
check(pushed, 'hook: key holders online get the new list pushed')

-- nolag: no list export; live checks, then reloads re-read the known houses.
positions[1] = vec3(8005.0, 8000.0, 10.0)
advance(2000)
res = hook(1, 'nolag:21')
check(res.ok and house('nolag:21') and house('nolag:21').hidden, 'hook: nolag owner places the garage')
check(Housing.hasAccess('CID2', 'nolag:21'), 'nolag: live HasKey')
positions[1] = vec3(9000.0, 9000.0, 10.0)
advance(2000)
res = hook(1, 'nolag:22')
check(not res.ok, 'hook: nolag society property refused for a job member without a key (default)')
convars.nayzeee_housing_nolag_society = '1'
advance(11000) -- live cache
res = hook(1, 'nolag:22')
check(res.ok, 'hook: nolag society property for that job (society convar on)')
online[3] = 'CID3'
advance(2000)
res = hook(3, 'nolag:22')
check(not res.ok, 'hook: nolag society property refused for another job')
convars.nayzeee_housing_nolag_society = nil
local savedNolagHasKey = api.nolag_properties.HasKey
api.nolag_properties.HasKey = function() error('signature changed') end
advance(11000)
check(Housing.hasAccess('CID1', 'nolag:22', 1), 'nolag: job members of a society property when HasKey fails')
check(not Housing.hasAccess('CID3', 'nolag:22', 3), 'nolag: not other jobs when HasKey fails')
api.nolag_properties.HasKey = savedNolagHasKey
advance(11000)
reloadAll()
check(viewIds('CID2')['nolag:21'] ~= nil, 'nolag: reload reads GetKeyHolders of known houses')

-- rx (whenUsed + create): property with a garage point unknown.
positions[1] = vec3(7003.0, 7000.0, 10.0)
advance(2000)
res = hook(1, 'rx:9')
check(res.ok and house('rx:9') and house('rx:9').hidden, 'hook: rx key holder places the garage')

-- Unknown / malformed
advance(2000)
check(not hook(1, 'nope:1').ok, 'hook: unknown prefix refused')
advance(2000)
check(not hook(1, { 'x' }).ok, 'hook: bad id refused')
rateBlocked = true
check(not hook(1, 'vms:12').ok, 'hook: rate limited')
rateBlocked = false

---------------------------------------------------------------------------------------
-- Restart: hook positions come back from KVP
---------------------------------------------------------------------------------------

check(kvp['nz_housing:spot:tk:1'] ~= nil and kvp['nz_housing:spot:nolag:21'] ~= nil, 'kvp: spots saved')

---------------------------------------------------------------------------------------
-- Reloads, hints and failures
---------------------------------------------------------------------------------------

-- vms read fails (export and SQL): previous access kept
vmsFails = true
db.down = true
reloadAll()
db.down = false
check(Housing.hasAccess('CID2', 'vms:12') and house('vms:12') ~= nil, 'failure: vms houses kept when the read fails')
check(house('qs:grove1') ~= nil and house('ps:7') ~= nil, 'failure: database outage keeps qs / ps houses')
vmsFails = false

-- An empty read is only trusted when a read at least a minute later confirms it.
tkEmpty = true
reloadAll()
check(house('tk:1') ~= nil and Housing.hasAccess('CID3', 'tk:1'), 'empty: first empty read ignored')
advance(15000)
reloadAll()
check(house('tk:1') ~= nil, 'empty: a second empty read soon after (script still loading) is not trusted')
advance(30000)
reloadAll()
check(house('tk:1') == nil, 'empty: confirmed empty read removes the houses')
check(kvp['nz_housing:spot:tk:1'] == nil, 'empty: and forgets their hook position')
tkEmpty = false
reloadAll()

-- nolag: a deleted property disappears after two reads that agree.
nolagProps[22] = nil
reloadAll()
check(house('nolag:22') ~= nil, 'nolag: one "missing" answer keeps the house')
advance(15000)
reloadAll()
check(house('nolag:22') ~= nil, 'nolag: a second "missing" answer soon after keeps it too')
advance(30000)
reloadAll()
check(house('nolag:22') == nil and kvp['nz_housing:spot:nolag:22'] == nil, 'nolag: deleted property dropped')
check(house('nolag:21') ~= nil, 'nolag: other properties kept')

-- ps: tight query unsupported -> simple query, houses kept.
db.psTightFails = true
reloadAll()
check(house('ps:7') ~= nil and house('ps:8') == nil, 'ps: falls back to the simple query')

-- Event hints reload the loader.
local before = exportCalls['esx_property:GetProperties'] or 0
esxProps[2].garage.enabled = true
TriggerEvent('nz:noop')
Housing.hint('esx', 100)
advance(15000)
check((exportCalls['esx_property:GetProperties'] or 0) > before and house('esx:2') ~= nil, 'hint: esx reload picks up an enabled garage')
psOwners['7'] = { CID1 = true }
TriggerEvent('ps-housing:server:updateProperty', 'UpdateGarage', 7, {})
advance(15000)
check(house('ps:7') ~= nil, 'hint: ps updateProperty reloads')
check(netHandlers['vms_housing:sv:giveKey'] ~= nil and netHandlers['ps-housing:server:addAccess'] ~= nil
  and netHandlers['rtx_housing:Global:AddPermission'] ~= nil, 'hint: client-triggered key events are net events')

-- Resource restart hint.
local rtxBefore = exportCalls['rtx_housing:GetAllProperties'] or 0
TriggerEvent('onResourceStart', 'rtx_housing')
advance(20000)
check((exportCalls['rtx_housing:GetAllProperties'] or 0) > rtxBefore, 'hint: resource start reloads that loader')

-- Refresh callback (client request).
local r = run(callbacks['nz:housing:refresh'], 1, {})
check(r.ok and type(r.data) == 'table', 'refresh callback answers')

---------------------------------------------------------------------------------------
-- Review round 1: canonical hook ids, unknown property positions, lockdown, authoritative
-- live checks, client-triggered hints, export failures, N+1 reads, yields
---------------------------------------------------------------------------------------

local function spotCount(prefix)
  local n = 0
  for k in pairs(kvp) do if k:find('nz_housing:spot:' .. prefix .. ':', 1, true) then n = n + 1 end end
  return n
end
local function warnCount(text)
  local n = 0
  for _, w in ipairs(printed.warn) do if w:find(text, 1, true) then n = n + 1 end end
  return n
end

-- Canonical ids: one property never gets several garages.
positions[1] = vec3(8005.0, 8000.0, 10.0)
advance(2000)
local nolagSpots = spotCount('nolag')
res = hook(1, 'nolag:021')
check(res.ok and res.data.houseId == 'nolag:21', 'canonical: nolag:021 is nolag:21')
res = hook(1, 'nolag:21.0')
check(res.ok and res.data.houseId == 'nolag:21' and house('nolag:21.0') == nil and house('nolag:021') == nil,
  'canonical: nolag:21.0 is nolag:21, no alias garage')
res = hook(1, 'nolag:0x15')
check(res.ok and res.data.houseId == 'nolag:21', 'canonical: nolag:0x15 is nolag:21')
check(spotCount('nolag') == nolagSpots, 'canonical: no alias KVP spots')
check(not hook(1, 'nolag:abc').ok, 'canonical: non-numeric id refused for integer-id scripts')
reloadAll()
check(spotCount('nolag') == nolagSpots, 'canonical: still no alias after a reload')

positions[2] = vec3(4005.0, 4000.0, 30.0)
advance(2000)
res = hook(2, 'tk:1.0')
check(res.ok and res.data.houseId == 'tk:1' and house('tk:1') ~= nil and house('tk:1.0') == nil, 'canonical: tk:1.0 places tk:1')
reloadAll()
check(house('tk:1') ~= nil and kvp['nz_housing:spot:tk:1'] ~= nil, 'canonical: the tk garage survives the next reload')
positions[3] = vec3(6000.0, 6000.0, 40.0)
advance(2000)
res = hook(3, 'rtx:5.0')
check(res.ok and res.data.houseId == 'rtx:5', 'canonical: rtx:5.0 opens the loader garage rtx:5')

-- Property position unknown: an existing hook garage is never moved.
local savedMeta = nolagProps[21].metadata
nolagProps[21].metadata = nil
positions[1] = vec3(-3000.0, -3000.0, 10.0)
advance(2000)
hook(1, 'nolag:21')
check(near(house('nolag:21').openPoints[1].coords.x, 8005.0), 'anchors unknown: the garage is not moved')
positions[1] = vec3(500.0, -2500.0, 10.0)
advance(2000)
hook(1, 'nolag:21', 'store')
check(near(house('nolag:21').openPoints[1].coords.x, 8005.0), 'anchors unknown: not moved by a store call either')
check(warnCount('property position unknown') == 1, 'anchors unknown: warned once')

-- nolag: GetAllProperties coords locate the property.
api.nolag_properties.GetAllProperties = function(owner, ownerType)
  if owner == 'CID1' and ownerType == 'user' then return { { id = 21, coords = vector4(8000.0, 8000.0, 10.0, 0.0) } } end
  return {}
end
positions[1] = vec3(-3000.0, -3000.0, 10.0)
advance(2000)
check(not hook(1, 'nolag:21').ok, 'nolag: GetAllProperties coords refuse a far move')
positions[1] = vec3(8050.0, 8000.0, 10.0)
advance(2000)
res = hook(1, 'nolag:21')
check(res.ok and near(house('nolag:21').openPoints[1].coords.x, 8050.0), 'nolag: moved within range of its coords')
api.nolag_properties.GetAllProperties = nil
nolagProps[21].metadata = savedMeta

-- nolag: police lockdown closes the garage on the server.
nolagProps[21].metadata = { enterData = { x = 8000.0, y = 8000.0, z = 10.0 }, lockdown = true }
advance(11000)
check(not Housing.hasAccess('CID1', 'nolag:21', 1), 'nolag: lockdown denies the owner')
check(not Housing.hasAccess('CID2', 'nolag:21'), 'nolag: lockdown denies cached key holders')
advance(2000)
check(not hook(1, 'nolag:21').ok, 'nolag: lockdown refuses the hook')
convars.nayzeee_housing_nolag_lockdown = '0'
advance(11000)
check(Housing.hasAccess('CID1', 'nolag:21', 1), 'nolag: lockdown convar 0 mirrors DisableGarage = false')
convars.nayzeee_housing_nolag_lockdown = nil
nolagProps[21].metadata = savedMeta
advance(11000)

-- Authoritative live checks: a revoked key counts at once (tk has no change events).
check(Housing.hasAccess('CID3', 'tk:1'), 'authoritative: tk key holder before the revoke')
tkProps[1].permissions.CID3 = nil
advance(11000)
check(not Housing.hasAccess('CID3', 'tk:1'), 'authoritative: revoked tk key denied before the reload')
tkProps[1].permissions.CID3 = { garage = true }
advance(11000)
-- A failing live call is not a "no": the cached sets decide.
local savedHasKey = api.nolag_properties.HasKey
api.nolag_properties.HasKey = function() error('signature changed') end
advance(11000)
check(Housing.hasAccess('CID2', 'nolag:21'), 'authoritative: failing HasKey falls back to the cached holders')
api.nolag_properties.HasKey = savedHasKey
-- bcs is not authoritative: a live "no" keeps the cached owner.
check(Housing.hasAccess('CID3', 'bcs:h1'), 'non-authoritative: bcs owner from the cached set')

-- Client-triggered hints: rate limited per player and per loader. (The window avoids the
-- periodic 5-minute reload, which reads every loader.)
advance(61000)
do
  local nextPeriodic = (math.floor(clock / 300000) + 1) * 300000
  if nextPeriodic - clock < 70000 then advance(nextPeriodic - clock + 5000) end
end
local vmsReads = exportCalls['vms_housing:GetAllProperties'] or 0
for _ = 1, 12 do
  source = 2
  netHandlers['vms_housing:sv:giveKey']()
  source = 3
  netHandlers['vms_housing:sv:removeKey']()
  source = nil
  advance(5000)
end
local spam = (exportCalls['vms_housing:GetAllProperties'] or 0) - vmsReads
check(spam >= 1 and spam <= 2, ('nethint: 60 s of key-event spam -> %d vms read(s), at most 2'):format(spam))
-- Server-side events keep the fast path.
local rtxReads = exportCalls['rtx_housing:GetAllProperties'] or 0
TriggerEvent('rtx_housing:Global:AddLog')
advance(12000)
check((exportCalls['rtx_housing:GetAllProperties'] or 0) > rtxReads, 'hint: server-side rtx event reloads quickly')

-- tk: permissions come with getProperties (no per-property export), unowned skipped.
local tkKeyCalls = exportCalls['tk_housing:getPropertyKeyholders'] or 0
tkProps[3] = { id = 3, name = 'TK Empty', owner = '', coords = vec3(4200.0, 4000.0, 30.0) }
advance(11000)
reloadAll()
check((exportCalls['tk_housing:getPropertyKeyholders'] or 0) == tkKeyCalls, 'tk: no getPropertyKeyholders call when permissions are listed')
check(not Housing.hasAccess('CID1', 'tk:3'), 'tk: unowned property gives no access')
tkProps[3] = nil

-- loaf: one GetHouses call instead of GetHouse per property.
api.loaf_housing.GetHouses = function()
  return { [3] = api.loaf_housing.GetHouse(3), [4] = api.loaf_housing.GetHouse(4) }
end
local loafOne = exportCalls['loaf_housing:GetHouse'] or 0
advance(11000)
reloadAll()
check((exportCalls['loaf_housing:GetHouse'] or 0) == loafOne and (exportCalls['loaf_housing:GetHouses'] or 0) >= 1,
  'loaf: GetHouses read once, no GetHouse per property')
check(house('loaf:3') ~= nil and near(house('loaf:3').spawnPoints[1].x, 1005.0), 'loaf: garage from GetHouses')
api.loaf_housing.GetHouses = nil

-- bcs: holders only with a confirmed Garage permission (fail closed).
local savedBcsHasKey = api.bcs_housing.HasKey
api.bcs_housing.HasKey = function() error('wrong arguments') end
advance(11000)
reloadAll()
check(not Housing.hasAccess('CID1', 'bcs:h1') and Housing.hasAccess('CID3', 'bcs:h1'), 'bcs: holder left out when HasKey fails, owner kept')
api.bcs_housing.HasKey = savedBcsHasKey

-- Export failures are warned once (and again after a recovery).
local savedHolders = api.bcs_housing.GetKeyHolders
api.bcs_housing.GetKeyHolders = nil
advance(11000)
reloadAll()
advance(11000)
reloadAll()
check(warnCount('bcs_housing export GetKeyHolders failed') == 1, 'export: a failing export is warned once')
api.bcs_housing.GetKeyHolders = savedHolders
advance(11000)
reloadAll()
api.bcs_housing.GetKeyHolders = nil
advance(11000)
reloadAll()
check(warnCount('bcs_housing export GetKeyHolders failed') == 2, 'export: warned again after it worked in between')
api.bcs_housing.GetKeyHolders = savedHolders
advance(11000)
reloadAll()
check(Housing.hasAccess('CID1', 'bcs:h1'), 'export: bcs key holder back after the recovery')

-- qs: a build without the label column is detected once (no failing query every reload).
local origHouselocations = db.houselocations
local labelTries = 0
db.houselocations = function(sql, params)
  if sql:find('`label`', 1, true) then
    labelTries = labelTries + 1
    error("Unknown column 'label' in 'field list'")
  end
  return origHouselocations(sql, params)
end
advance(11000)
reloadAll()
advance(11000)
reloadAll()
check(labelTries == 1 and house('qs:grove1') ~= nil and house('qs:grove1').name == 'Grove 1', 'qs: label column probed once, houses kept')
db.houselocations = origHouselocations

-- Long lists: the reload yields (Wait(0)) and still applies everything.
for i = 100, 549 do vmsProps[tostring(i)] = { id = i, type = 'house', owner = 'BULK' .. i, keys = '{}', name = 'Bulk ' .. i, metadata = '{}' } end
resourceStates.vms_housing = 'stopped' -- cached sets only
advance(11000)
resourceStates.vms_housing = 'started'
local zeroWaits, realWait = 0, Wait
Wait = function(ms) if ms == 0 then zeroWaits = zeroWaits + 1 end return realWait(ms) end
reloadAll()
Wait = realWait
check(zeroWaits >= 2, ('yield: the reload yielded %d time(s)'):format(zeroWaits))
resourceStates.vms_housing = 'stopped'
check(Housing.hasAccess('BULK549', 'vms:549') and Housing.hasAccess('BULK100', 'vms:100'), 'yield: 450 extra properties applied')
resourceStates.vms_housing = 'started'
for i = 100, 549 do vmsProps[tostring(i)] = nil end
advance(11000)
reloadAll()

---------------------------------------------------------------------------------------
-- Review round 2: houses missing from a complete read, unowned / rented properties, hook
-- grants vs cached sets, failing fallback reads, read intervals, deleted nolag properties,
-- SetHouseAccess list shapes, the store point
---------------------------------------------------------------------------------------

-- (a) One partial read (vms_housing still loading after a restart) never deletes a hook garage.
-- (vms:14 keeps the reads non-empty: an empty read has its own guard.)
vmsProps['14'] = { id = 14, type = 'house', owner = 'CID3', keys = '{}', name = 'VMS Cottage', metadata = '{}' }
positions[1] = vec3(2010.0, 2005.0, 10.0)
advance(11000)
reloadAll()
check(hook(1, 'vms:12').ok and house('vms:12') ~= nil, 'missing: vms:12 has a hook garage')
local vmsSpot = kvp['nz_housing:spot:vms:12']
local saved12 = vmsProps['12']
vmsProps['12'] = nil
advance(11000)
reloadAll()
check(house('vms:12') ~= nil and kvp['nz_housing:spot:vms:12'] == vmsSpot, 'missing: a read without vms:12 keeps its garage and position')
resourceStates.vms_housing = 'stopped' -- cached sets only
check(Housing.hasAccess('CID2', 'vms:12'), 'missing: and its cached access')
resourceStates.vms_housing = 'started'
vmsProps['12'] = saved12
advance(11000)
reloadAll()
check(house('vms:12') ~= nil and kvp['nz_housing:spot:vms:12'] == vmsSpot, 'missing: the next full read keeps it (Hvms:12 registered, spot kept)')
-- A miss confirmed by a read at least a minute later drops the house.
vmsProps['12'] = nil
advance(11000)
reloadAll()
advance(15000)
reloadAll()
check(house('vms:12') ~= nil, 'missing: a second miss soon after keeps it')
advance(30000)
reloadAll()
check(house('vms:12') == nil and kvp['nz_housing:spot:vms:12'] == nil, 'missing: a miss confirmed a minute later drops it')
check(Housing.hasAccess('CID3', 'vms:14'), 'missing: the other houses stay')
vmsProps['12'] = saved12
vmsProps['14'] = nil
advance(11000)
reloadAll()

-- (b) RxHousing: an unowned property whose renter passes HasKey keeps its hook garage.
local rxApi = api.RxHousing
local rxProps = {
  ['9'] = { id = 9, owner = 'CID3', label = 'RX Flat', keyholders = { 'CID1' }, coords = { entrance = vec3(7000.0, 7000.0, 10.0) } },
  ['10'] = { id = 10, label = 'RX Rented', coords = { entrance = vec3(7100.0, 7000.0, 10.0) } },
}
local rxHolderCalls = 0
api.RxHousing = {
  GetAllProperties = function() return rxProps end,
  GetProperty = function(id) return rxProps[tostring(math.tointeger(tonumber(id)) or id)] end,
  GetPropertyKeyholders = function() rxHolderCalls = rxHolderCalls + 1 return {} end,
  HasKey = function(id, identifier)
    id = tonumber(id)
    return (id == 9 and identifier == 'CID1') or (id == 10 and identifier == 'CID2')
  end,
}
advance(11000)
reloadAll()
positions[2] = vec3(7103.0, 7000.0, 10.0)
advance(2000)
res = hook(2, 'rx:10')
check(res.ok and house('rx:10') ~= nil and kvp['nz_housing:spot:rx:10'] ~= nil, 'rx: renter (HasKey) places the garage of an unowned property')
advance(11000)
reloadAll()
advance(11000)
reloadAll()
check(house('rx:10') ~= nil and kvp['nz_housing:spot:rx:10'] ~= nil, 'rx: unowned property garage kept across reloads')
check(rxHolderCalls == 0, 'rx: no GetPropertyKeyholders call for unowned properties')
rxProps['10'].renter = 'CID2'
advance(11000)
reloadAll()
resourceStates.RxHousing = 'stopped' -- cached sets only
check(Housing.hasAccess('CID2', 'rx:10'), 'rx: renter in the cached access set')
resourceStates.RxHousing = 'started'
api.RxHousing = rxApi

-- tk: the same for an unowned property (hook garage kept, nobody in the cached set).
tkProps[3] = { id = 3, name = 'TK Empty', owner = '', coords = vec3(4200.0, 4000.0, 30.0) }
advance(11000)
reloadAll()
check(not Housing.hasAccess('CID1', 'tk:3'), 'tk: unowned property listed without access')
tkProps[3] = nil
advance(11000)
reloadAll()

-- (c) A hook grant is not kept on top of the cached sets: a revoked loaf key ends at the next read.
positions[3] = vec3(1001.0, -500.0, 60.0)
advance(2000)
res = hook(3, 'loaf:3')
check(res.ok, 'grant: loaf key holder opens through the hook')
local loafKeys = db.loaf_keys
db.loaf_keys = { { identifier = 'CID1', key_id = 'housing_key_3_ZZ-9999' } }
advance(11000)
reloadAll()
check(not Housing.hasAccess('CID3', 'loaf:3'), 'grant: revoked loaf key denied after the reload (no 30 min hook grant)')
check(viewIds('CID3')['loaf:3'] == nil, 'grant: and the house leaves the list')
db.loaf_keys = loafKeys
advance(11000)
reloadAll()
check(Housing.hasAccess('CID3', 'loaf:3'), 'grant: key given back')
-- A player with live-only access still keeps the grant (vms item keys).
positions[3] = vec3(2010.0, 2005.0, 10.0)
local vmsHasKeys = api.vms_housing.HasKeys
api.vms_housing.HasKeys = function(src) return src == 3 end
advance(2000)
check(hook(3, 'vms:12').ok, 'grant: vms item key holder (live only) accepted')
check(viewIds('CID3')['vms:12'] ~= nil, 'grant: live-only access keeps the house in the list')
api.vms_housing.HasKeys = vmsHasKeys
advance(11000)

-- (d) loaf fallback path: a failing GetHouse aborts the read (houses read before are kept).
-- (loaf:5 keeps the read non-empty: an empty read has its own guard.)
local loafGetHouse = api.loaf_housing.GetHouse
local loafRows = db.loaf_properties
db.loaf_properties = { loafRows[1], loafRows[2], loafRows[3], { owner = 'CID2', propertyid = 5, id = 'AC-0003' } }
api.loaf_housing.GetHouse = function(id)
  if id == 5 then return { label = 'Loaf 5', garage = { entrance = vec3(1200.0, -500.0, 60.0), exit = vector4(1205.0, -505.0, 60.0, 0.0) } } end
  return loafGetHouse(id)
end
advance(11000)
reloadAll()
check(house('loaf:5') ~= nil and house('loaf:3') ~= nil, 'loaf: second property with a garage')
local loafWorking = api.loaf_housing.GetHouse
api.loaf_housing.GetHouse = function(id) if id == 3 then error('timeout') end return loafWorking(id) end
advance(11000)
reloadAll()
advance(65000)
reloadAll()
check(house('loaf:3') ~= nil and Housing.hasAccess('CID1', 'loaf:3'), 'loaf: failing GetHouse keeps the house and its access')
api.loaf_housing.GetHouse = loafGetHouse
db.loaf_properties = loafRows
advance(11000)
reloadAll()
advance(65000)
reloadAll()
check(house('loaf:5') == nil and house('loaf:3') ~= nil, 'loaf: property 5 gone after a confirmed miss, 3 kept')

-- The loaf exit is passed on as the store point.
local registerHouse = NZ.Locations.registerHouse
local passed
NZ.Locations.registerHouse = function(id, data)
  if id == 'loaf:3' then passed = data end
  return registerHouse(id, data)
end
Housing.remove('loaf:3')
advance(11000)
reloadAll()
check(passed and passed.store and near(passed.store.x, 1005.0) and near(passed.coords.x, 1000.0), 'loaf: exit passed as the store point')
NZ.Locations.registerHouse = registerHouse

-- (e) Interval loaders whose reads fail are re-read at their interval, not on every tick.
local esxGet = api.esx_property.GetProperties
api.esx_property.GetProperties = function() return {} end
db.tables.esx_properties = true -- table present, query fails
local esxBefore = exportCalls['esx_property:GetProperties'] or 0
advance(300000)
local esxReads = (exportCalls['esx_property:GetProperties'] or 0) - esxBefore
check(esxReads >= 2 and esxReads <= 5, ('interval: failing esx reads -> %d read(s) in 5 minutes'):format(esxReads))
check(house('esx:1') ~= nil, 'interval: failing esx reads keep the houses')
local esxLoader = Housing.loaders.esx
esxLoader.ctx.resource = 'esx_property'
check(esxLoader.load(esxLoader.ctx) == nil, 'esx: empty export + failing table read is not trusted')
db.esx_properties = {}
local emptyRead = esxLoader.load(esxLoader.ctx)
check(type(emptyRead) == 'table' and next(emptyRead) == nil, 'esx: empty export + empty table is a valid empty read')
db.esx_properties = nil
api.esx_property.GetProperties = esxGet
advance(130000)
check(house('esx:1') ~= nil, 'esx: houses back to normal')

-- (f) nolag: every known property deleted -> dropped (after the confirming read), check says no.
local savedNolag21 = nolagProps[21]
nolagProps[21] = nil
advance(11000)
check(not Housing.hasAccess('CID1', 'nolag:21', 1) and not Housing.hasAccess('CID2', 'nolag:21'),
  'nolag: a deleted property is a live "no" for owner and cached key holders')
reloadAll()
check(house('nolag:21') ~= nil, 'nolag: first read without any known property keeps it')
advance(45000)
reloadAll()
check(house('nolag:21') == nil and kvp['nz_housing:spot:nolag:21'] == nil, 'nolag: the only known property deleted is dropped')
nolagProps[21] = savedNolag21
-- Right after nolag_properties (re)starts, "everything missing" means "still loading".
positions[1] = vec3(8005.0, 8000.0, 10.0)
advance(11000)
check(hook(1, 'nolag:21').ok, 'nolag: garage placed again')
TriggerEvent('onResourceStart', 'nolag_properties')
nolagProps[21] = nil
advance(11000)
reloadAll()
advance(45000)
reloadAll()
check(house('nolag:21') ~= nil, 'nolag: not dropped while nolag_properties may still be loading')
nolagProps[21] = savedNolag21
advance(11000)
reloadAll()

-- (g) SetHouseAccess: sparse and 0-based lists use the values, maps the keys.
Housing.register('custom_2', { name = 'Custom 2', coords = vector4(30.0, 20.0, 30.0, 0.0) })
check(ownExports.SetHouseAccess('custom_2', { [2] = 'CIDX' }) == true, 'SetHouseAccess: sparse list accepted')
check(Housing.hasAccess('CIDX', 'custom_2') and not Housing.hasAccess('2', 'custom_2'), 'SetHouseAccess: sparse list uses the value')
ownExports.SetHouseAccess('custom_2', { [0] = 'CIDY', [1] = { citizenid = 'CIDZ' } })
check(Housing.hasAccess('CIDY', 'custom_2') and Housing.hasAccess('CIDZ', 'custom_2') and not Housing.hasAccess('0', 'custom_2')
  and not Housing.hasAccess('CIDX', 'custom_2'), 'SetHouseAccess: 0-based list, table entries, replaces the previous set')
ownExports.SetHouseAccess('custom_2', '{"CIDM":true,"CIDN":false}')
check(Housing.hasAccess('CIDM', 'custom_2') and not Housing.hasAccess('CIDN', 'custom_2'), 'SetHouseAccess: JSON map, false = no access')
Housing.remove('custom_2')

---------------------------------------------------------------------------------------
-- Config modes
---------------------------------------------------------------------------------------

Config.Integrations.housing = { 'qb-houses', 'ps' }
reloadAll()
check(house('qb:grove1') ~= nil and house('qb:grove1').name == 'Grove 1', 'mode list: qb-houses loaded when listed')
check(Housing.hasAccess('CID2', 'qb:grove1') and Housing.hasAccess('CID1', 'Hqb:grove1'), 'compat: qb:<name> ids and H prefix')
check(Housing.refresh('esx') == true and Housing.refresh('unknown_script') == false, 'refresh: by prefix / unknown name')
Config.Integrations.housing = 'auto'

---------------------------------------------------------------------------------------
-- Export API
---------------------------------------------------------------------------------------

local ok = Housing.register('custom_1', { name = 'Custom', coords = vector4(10.0, 20.0, 30.0, 40.0), hidden = true })
check(ok and house('custom_1') and house('custom_1').hidden, 'export: register hidden')
check(Housing.setAccess('Hcustom_1', { 'CID2', 5, '', 'CID2' }) == true, 'export: set access')
check(viewIds('CID2')['custom_1'] ~= nil and viewIds('5')['custom_1'] ~= nil, 'export: access applied (numbers become strings)')
positions[2] = vec3(10.0, 20.0, 30.0)
advance(2000)
res = hook(2, 'custom_1')
check(res.ok, 'export: hook works for export houses')
check(near(house('custom_1').openPoints[1].coords.x, 10.0), 'export: export houses never move')
check(Housing.register('ps:7', { name = 'Override', coords = vector4(1.0, 2.0, 3.0, 0.0) }) == true, 'export: may override a loader house')
reloadAll()
check(house('ps:7').name == 'Override', 'export: registration wins over the loader')
check(Housing.remove('custom_1') == true and house('custom_1') == nil, 'export: remove')
check(not Housing.register('', { coords = vector4(0, 0, 0, 0) }), 'export: invalid id refused')
check(not Housing.register('x', { coords = 'nope' }), 'export: invalid coords refused')

---------------------------------------------------------------------------------------
-- 'whenUsed' hidden through the convar; 'none'
---------------------------------------------------------------------------------------

convars.nayzeee_housing_hooked = 'esx_property, rtx'
reloadAll()
check(house('esx:1').hidden == true and house('rtx:5').hidden == true, 'convar: hooked scripts hide our points')
check(not house('loaf:3').hidden, 'convar: other scripts unchanged')
convars.nayzeee_housing_hooked = nil

Config.Integrations.housing = 'none'
reloadAll()
check(not hook(1, 'vms:99').ok, "mode none: loaders inactive for the hook")
Config.Integrations.housing = 'auto'

Housing.onPlayerDropped(1)
advance(1000)
finish()
