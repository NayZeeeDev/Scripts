--[[
  Headless test for the car lock client (no FiveM needed): bridge/client/{keys,inventory,
  listeners}.lua and client/carlock/{lock,ignition}.lua in a stubbed client runtime with a
  scripted server (lib.callback answers) and a tiny world (two vehicles, one ped).

    lock toggle (candidates, feedback, key cache) -> 'nzLocked' / 'nzAlarm' state bags and the
    lock feedback event -> ignition without key (engine kept off, one notification) -> key pushed by the
    server -> recheck -> engine allowed -> engine toggle -> garage key on its way
    (NZ.Keys.give) -> other scripts' client events and synchronous export shims -> exports.

  Usage (from the resource root):  lua5.4 tools/smoke/carlock_client.lua
]]

local failures, checks = {}, 0
local function check(cond, label)
  checks = checks + 1
  if not cond then failures[#failures + 1] = label end
end

local clock = 0
local threads = {}
function CreateThread(fn) threads[#threads + 1] = { co = coroutine.create(fn), wake = clock } end
function Wait(ms)
  if not coroutine.isyieldable() then error('Wait() outside a thread', 2) end
  coroutine.yield(ms or 0)
end
function SetTimeout(ms, fn) CreateThread(function() Wait(ms) fn() end) end
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
local function run(fn, ...)
  local args = table.pack(...)
  local results
  CreateThread(function() results = table.pack(fn(table.unpack(args, 1, args.n))) end)
  local guard = 0
  runDue()
  while not results do
    clock = clock + 50
    runDue()
    guard = guard + 1
    if guard > 5000 then error('run(): never returned') end
  end
  return table.unpack(results, 1, results.n)
end

local handlers = {}
function AddEventHandler(name, fn)
  handlers[name] = handlers[name] or {}
  local entry = { name = name, fn = fn }
  table.insert(handlers[name], entry)
  return entry
end
function RemoveEventHandler(entry)
  for i, e in ipairs(handlers[entry.name] or {}) do if e == entry then table.remove(handlers[entry.name], i) return end end
end
function RegisterNetEvent(name, fn) if fn then AddEventHandler(name, fn) end end
function TriggerEvent(name, ...) for _, e in ipairs(handlers[name] or {}) do e.fn(...) end end
function TriggerServerEvent() end
local commands = {}
function RegisterCommand(name, fn) commands[name] = fn end

-- world -------------------------------------------------------------------------------
local vmeta = {}
vmeta.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vmeta) end
vmeta.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
local function vec3(x, y, z) return setmetatable({ x = x, y = y, z = z }, vmeta) end
vector3 = vec3
function vector4(x, y, z, w) return { x = x, y = y, z = z, w = w } end
vec4 = vector4
local function joaat_(s)
  local h = 0
  for i = 1, #tostring(s) do h = (h * 31 + tostring(s):lower():byte(i)) & 0x7fffffff end
  return h
end
joaat = joaat_
GetHashKey = joaat_

local PED = 101
local vehicles = {
  [201] = { plate = 'ABC123', net = 55, coords = vec3(3, 0, 0), engine = false, lock = 1, class = 0 },
  [202] = { plate = 'JOB0001', net = 56, coords = vec3(5, 0, 0), engine = false, lock = 1, class = 0 },
}
local seated = nil
local engineCalls = {}
local states = {}
function Entity(h)
  states[h] = states[h] or setmetatable({}, { __index = { set = function(self, k, v) rawset(self, k, v) end } })
  return { state = states[h] }
end
function PlayerPedId() return PED end
function PlayerId() return 0 end
function GetPlayerServerId() return 1 end
function DoesEntityExist(h) return vehicles[h] ~= nil or h == PED end
function IsEntityAVehicle(h) return vehicles[h] ~= nil end
function NetworkGetEntityIsNetworked(h) return vehicles[h] ~= nil end
function NetworkGetNetworkIdFromEntity(h) return vehicles[h] and vehicles[h].net or 0 end
function NetworkGetEntityOwner() return 0 end
function GetVehicleNumberPlateText(h) return vehicles[h] and (vehicles[h].plate .. '        '):sub(1, 8) or '' end
function GetEntityModel() return joaat_('sultan') end
function GetVehicleClass(h) return vehicles[h] and vehicles[h].class or 0 end
function GetEntityCoords(h) return vehicles[h] and vehicles[h].coords or vec3(0, 0, 0) end
function GetVehiclePedIsIn() return seated or 0 end
function GetPedInVehicleSeat(h, s) if seated == h and s == -1 then return PED end return 0 end
function GetIsVehicleEngineRunning(h) return vehicles[h] and vehicles[h].engine or false end
function SetVehicleEngineOn(h, on) if vehicles[h] then vehicles[h].engine = on engineCalls[#engineCalls + 1] = on end end
function SetVehicleDoorsLocked(h, s) if vehicles[h] then vehicles[h].lock = s end end
function GetEntityFromStateBagName(bag) local net = tonumber(bag:match('(%d+)$')) for h, v in pairs(vehicles) do if v.net == net then return h end end return 0 end
local bagHandlers = {}
function AddStateBagChangeHandler(key, _, fn) bagHandlers[key] = fn return 1 end
local poolScans = 0
function GetGamePool() poolScans = poolScans + 1 local out = {} for h in pairs(vehicles) do out[#out + 1] = h end return out end
function NetworkDoesNetworkIdExist(net) for _, v in pairs(vehicles) do if v.net == net then return true end end return false end
function NetworkGetEntityFromNetworkId(net) for h, v in pairs(vehicles) do if v.net == net then return h end end return 0 end
local sounds, alarmsOn = 0, 0
function PlaySoundFromEntity() sounds = sounds + 1 end
function StartVehicleAlarm() alarmsOn = alarmsOn + 1 end
function IsPauseMenuActive() return false end
function IsNuiFocused() return false end
function IsEntityDead() return false end
function IsPedInAnyVehicle() return seated ~= nil end
function IsControlPressed() return false end
function GetResourceState(name) if name == 'qb-core' or name == 'ox_inventory' then return 'started' end return 'missing' end
function GetCurrentResourceName() return 'nayzeee-garages' end
function IsDuplicityVersion() return false end
setmetatable(_G, { __index = function(_, k)
  if type(k) == 'string' and k:match('^%u') then return function() return nil end end
  return nil
end })

-- ox_lib + scripted server ------------------------------------------------------------
local server = {}           -- [callback] = function(payload) -> result
local calls = {}            -- [callback] = { payload, ... }
local function answer(name, payload)
  calls[name] = calls[name] or {}
  table.insert(calls[name], payload)
  local fn = server[name]
  if not fn then return { ok = false, error = 'no server' } end
  return fn(payload)
end
local onCache = {}
local keybinds = {}
lib = {
  print = { info = function() end, warn = function() end, error = function(...) failures[#failures + 1] = 'lib.print.error ' .. table.concat({ ... }, ' ') end },
  callback = setmetatable({
    await = function(name, _, payload) Wait(50) return answer(name, payload) end,
  }, { __call = function(_, name, _, cb, payload) CreateThread(function() Wait(50) local r = answer(name, payload) if cb then cb(r) end end) end }),
  onCache = function(key, fn) onCache[key] = onCache[key] or {} table.insert(onCache[key], fn) end,
  addKeybind = function(o) keybinds[o.name] = o return o end,
  getNearbyVehicles = function(coords, dist)
    local out = {}
    for h, v in pairs(vehicles) do if #(v.coords - coords) <= dist then out[#out + 1] = { vehicle = h, coords = v.coords } end end
    return out
  end,
  getClosestVehicle = function() return 201, vehicles[201].coords end,
  getClosestPlayer = function() return nil end,
  requestAnimDict = function() return true end,
  requestModel = function() return true end,
}
cache = { ped = PED, playerId = 0 }

local exported = {}
exports = setmetatable({}, {
  __call = function(_, name, fn) exported[name] = fn end,
  __index = function() return setmetatable({}, { __index = function() return function() return nil end end }) end,
})
json = { encode = function() return '{}' end, decode = function() return {} end }

local function load_(file)
  local f = assert(io.open(file, 'r'), 'missing ' .. file)
  local src = f:read('a')
  f:close()
  local okLoad, err = xpcall(assert(load(src, '@' .. file, 't', _ENV)), debug.traceback)
  if not okLoad then failures[#failures + 1] = 'load ' .. file .. ': ' .. tostring(err) end
end
load_('config/config.lua')
load_('config/carlock.lua')
load_('shared/init.lua')
load_('shared/utils.lua')
load_('shared/carlock.lua')
load_('bridge/shared.lua')
local notes = {}
NZ.NUI.notify = function(kind, message) notes[#notes + 1] = { kind = kind, message = message } end
NZ.State.settings = {}
load_('bridge/client/keys.lua')
load_('bridge/client/inventory.lua')
load_('bridge/client/listeners.lua')
load_('client/carlock/lock.lua')
load_('client/carlock/ignition.lua')
advance(1500)
local CarLock = NZ.CarLock
local function lastNote() return notes[#notes] and notes[#notes].message end

-- 1. lock toggle ---------------------------------------------------------------------
check(keybinds.nz_carlock_lock and keybinds.nz_carlock_engine and commands.lock and commands.engine, 'keybinds and commands registered')
server['nz:carlock:toggleLock'] = function(p)
  return { ok = true, data = { netId = p.netIds[1], plate = 'ABC123', locked = true, kind = 'item' } }
end
local ok, locked = run(CarLock.toggleLock)
local sent = calls['nz:carlock:toggleLock'] and calls['nz:carlock:toggleLock'][1]
check(ok and locked == true, 'toggle lock round trip')
check(sent and #sent.netIds == 2, 'nearby networked vehicles sent as candidates')
check(lastNote() == 'Vehicle locked', 'lock notification')
check(CarLock.cachedKey('ABC123') == true, 'successful lock caches the key')
server['nz:carlock:toggleLock'] = function() return { ok = false, error = 'You do not have the keys of a vehicle nearby' } end
check(run(CarLock.toggleLock) == false and lastNote() == 'You do not have the keys of a vehicle nearby', 'refusal shown')

-- 2. replicated state ---------------------------------------------------------------
bagHandlers.nzLocked('entity:55', 'nzLocked', true)
advance(200)
check(vehicles[201].lock == 2, "'nzLocked' applied to the door lock")
TriggerEvent('nz:client:carlock:fx', { netId = 55, locked = false })
advance(1000)
check(sounds == 1, "lock feedback event plays the unlock sound nearby")
check(bagHandlers.nzLockFx == nil, 'no client-writable lock feedback bag is listened to')
bagHandlers.nzAlarm('entity:55', 'nzAlarm', { id = 1, mode = 'native', seconds = 10 })
advance(200)
check(alarmsOn == 1, "'nzAlarm' native alarm started")

-- 3. ignition without key, then the key arrives ---------------------------------------
local ignition = false
server['nz:carlock:hasKey'] = function(p)
  if p.netId == 56 then return { ok = true, data = { plate = 'JOB0001', has = ignition, ignition = ignition, locked = false } } end
  if p.plate then return { ok = true, data = { plate = p.plate, has = p.plate == 'ABC123' } } end
  return { ok = true, data = { plate = 'ABC123', has = true, ignition = true } }
end
vehicles[202].engine = true
seated = 202
for _, fn in ipairs(onCache.seat or {}) do fn(-1) end
advance(1000)
check(vehicles[202].engine == false, 'engine stopped without a key')
check(lastNote() == 'You do not have the keys of this vehicle', 'no-key notification')
local driver = CarLock.driverState()
check(driver and driver.allowed == false and driver.plate == 'JOB0001', 'driver state: not allowed')
local noteCount = #notes
advance(2000)
check(#notes == noteCount, 'no-key notification shown once')
ignition = true
TriggerEvent('nz:client:carlock:keys', { plate = 'JOB0001' })
advance(1000)
driver = CarLock.driverState()
check(driver and driver.allowed == true, 'key pushed by the server: ignition allowed after the recheck')

-- 4. engine toggle -------------------------------------------------------------------
server['nz:carlock:engine'] = function(p) return { ok = p.on == true, data = { on = true, kind = 'temp' } } end
local okE, running = run(CarLock.toggleEngine)
check(okE and running == true and vehicles[202].engine == true, 'engine toggle on with a key')
okE, running = run(CarLock.toggleEngine)
check(okE and running == false and vehicles[202].engine == false, 'engine toggle off')
seated = nil
for _, fn in ipairs(onCache.seat or {}) do fn(false) end
advance(600)
check(CarLock.driverState() == nil, 'driver state cleared when leaving')

-- 5. garage key on its way -------------------------------------------------------------
vehicles[203] = { plate = 'NEW0001', net = 57, coords = vec3(1, 0, 0), engine = true, lock = 1, class = 0 }
check(NZ.Keys.resource() == 'nayzeee', 'keys bridge routes to the built-in car lock')
NZ.Keys.give(203, 'NEW0001')
check(CarLock.cachedKey('NEW0001') == true, 'garage key expected right after the spawn')
server['nz:carlock:hasKey'] = function() return { ok = true, data = { plate = 'NEW0001', has = false, ignition = false } } end
seated = 203
for _, fn in ipairs(onCache.seat or {}) do fn(-1) end
advance(600)
check(vehicles[203].engine == true and CarLock.driverState().allowed == true, 'engine kept while the garage key is on its way')
seated = nil
for _, fn in ipairs(onCache.seat or {}) do fn(false) end
advance(600)

-- 6. other scripts' client events and synchronous exports -----------------------------------
server['nz:carlock:compat'] = function() return { ok = true, data = true } end
TriggerEvent('vehiclekeys:client:SetOwner', 'JOB0001')
advance(500)
local compatCall = calls['nz:carlock:compat'] and calls['nz:carlock:compat'][1]
check(compatCall and compatCall.action == 'acquire' and compatCall.netId == 56, 'SetOwner -> server acquire with the net id')
local hasKeys
TriggerEvent('__cfx_export_qb-vehiclekeys_HasKeys', function(fn) hasKeys = fn end)
check(hasKeys and hasKeys('ABC123') == true, 'qb HasKeys shim answers from the cache')
server['nz:carlock:hasKey'] = function(p) return { ok = true, data = { plate = p.plate, has = false } } end
check(hasKeys and hasKeys('NOPE') == nil, 'qb HasKeys: unknown plate -> nil (checked in the background)')
advance(300)
check(CarLock.cachedKey('NOPE') == false, 'background check cached')
check(type(exported.HasKey) == 'function' and exported.HasKey('ABC123') == true, 'HasKey client export')
check(type(exported.GiveKey) == 'function' and exported.GiveKey(202) == true, 'GiveKey client export')
advance(300)
local last = calls['nz:carlock:compat'][#calls['nz:carlock:compat']]
check(last.export == true and last.netId == 56, 'GiveKey asks the server with the net id')

-- synchronous HasKeys polled every frame: cache first, one world scan per plate per second
local scansBefore = poolScans
for _ = 1, 30 do hasKeys('POLL01') end
check(poolScans - scansBefore <= 1, 'HasKeys polled every frame scans the world at most once per second')
advance(300)
for _ = 1, 30 do hasKeys('POLL01') end
check(poolScans - scansBefore <= 1, 'answer cached after the background check (no more scans)')

-- a rate-limited answer is not re-sent on every frame (the plate waits a second)
local answerOk = server['nz:carlock:hasKey']
server['nz:carlock:hasKey'] = function(p)
  if p.plate == 'BUSY01' then return { ok = false, error = 'Please wait a moment' } end
  return answerOk(p)
end
local busyBefore = #(calls['nz:carlock:hasKey'] or {})
for _ = 1, 20 do
  CarLock.hasKeyFast('BUSY01')
  advance(50)
end
check(#calls['nz:carlock:hasKey'] - busyBefore == 1, 'a refused key check waits a second before the plate is asked again')
advance(200)
CarLock.hasKeyFast('BUSY01')
advance(100)
check(#calls['nz:carlock:hasKey'] - busyBefore == 2, 'after the pause the plate is asked again')
server['nz:carlock:hasKey'] = answerOk

local qsAuto
TriggerEvent('__cfx_export_qs-vehiclekeys_RemoveKeysAuto', function(fn) qsAuto = fn end)
check(qsAuto and qsAuto() == true, 'qs-vehiclekeys RemoveKeysAuto shim')

local picked = nil
CarLock.onLockpickEvent = function(advanced) picked = advanced end
TriggerEvent('lockpicks:UseLockpick', true)
advance(100)
check(picked == true, 'lockpicks:UseLockpick forwarded to NZ.CarLock.onLockpickEvent')

-- the server's decision about other key resources wins over local detection
GlobalState = { nzCarLockOther = 'qb-vehiclekeys' }
load_('shared/carlock.lua')
check(CarLock.enabled() == false, "server says qb-vehiclekeys runs: built-in car lock off on the client")
GlobalState = { nzCarLockOther = false }
load_('shared/carlock.lua')
check(CarLock.enabled() == true, 'server says no other key resource: built-in car lock on')

if #failures > 0 then
  for _, f in ipairs(failures) do print('FAIL ' .. f) end
  print(('%d of %d checks failed'):format(#failures, checks))
  os.exit(1)
end
print(('carlock client OK (%d checks)'):format(checks))
