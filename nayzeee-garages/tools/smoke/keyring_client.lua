--[[
  Headless test for the key ring, tracker and locksmith CLIENT side (no FiveM needed):
  client/nui.lua (real NUI bridge), client/carlock/{lock,tracker,keysapp,locksmith}.lua in the
  stubbed client runtime of tools/smoke/carlock_client.lua with a scripted server.

    /keys + keybind + OpenKeys export + server event open the key ring -> data built from
    nz:carlock:keys + nz:carlock:tracker (groups, kinds, fob, time left on the server clock,
    share rules, what this client sees itself) -> keys:lock (never another vehicle than the
    one you sit in, server answer passed through) -> keys:locate (waypoint, following blip,
    live readout, signal lost) -> keys:alarm -> keys:share / players / holders / revoke ->
    key changes refresh the open ring -> locksmith blips, NPC, prompt + keybind, window,
    services forwarded, window closes when walking away.

  Usage (from the resource root):  lua5.4 tools/smoke/keyring_client.lua
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
local pedPos = vec3(0, 0, 0)
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
function GetEntityCoords(h) if h == PED then return pedPos end return vehicles[h] and vehicles[h].coords or vec3(0, 0, 0) end
function GetVehiclePedIsIn() return seated or 0 end
function GetPedInVehicleSeat(h, s) if seated == h and s == -1 then return PED end return 0 end
function GetIsVehicleEngineRunning(h) return vehicles[h] and vehicles[h].engine or false end
function SetVehicleEngineOn(h, on) if vehicles[h] then vehicles[h].engine = on engineCalls[#engineCalls + 1] = on end end
function SetVehicleDoorsLocked(h, s) if vehicles[h] then vehicles[h].lock = s end end
function GetEntityFromStateBagName(bag) local net = tonumber(bag:match('(%d+)$')) for h, v in pairs(vehicles) do if v.net == net then return h end end return 0 end
local bagHandlers = {}  -- luacheck: ignore 241 (filled by lock.lua)
function AddStateBagChangeHandler(key, _, fn) bagHandlers[key] = fn return 1 end
local poolScans = 0
function GetGamePool() poolScans = poolScans + 1 local out = {} for h in pairs(vehicles) do out[#out + 1] = h end return out end
function NetToVeh(net) for h, v in pairs(vehicles) do if v.net == net then return h end end return 0 end
function GetVehicleDoorLockStatus(h) return vehicles[h] and vehicles[h].lock or 0 end
local waypoint = nil
function SetNewWaypoint(x, y) waypoint = { x = x, y = y } end
local blipList, nextBlip = {}, 900
function AddBlipForCoord(x, y, z) nextBlip = nextBlip + 1 blipList[nextBlip] = { x = x, y = y, z = z } return nextBlip end
function SetBlipCoords(b, x, y, z) if blipList[b] then blipList[b].x, blipList[b].y, blipList[b].z = x, y, z end end
function DoesBlipExist(b) return blipList[b] ~= nil end
function RemoveBlip(b) blipList[b] = nil end
local nuiMessages, nuiCallbacks = {}, {}
function SendNUIMessage(msg) nuiMessages[#nuiMessages + 1] = msg end
function RegisterNUICallback(name, fn) nuiCallbacks[name] = fn end
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
local points = {}
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
  points = { new = function(o) points[#points + 1] = o return o end },
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
-- module stubs ------------------------------------------------------------------------
local notes = {}
NZ.Notify.show = function(kind, message) notes[#notes + 1] = { kind = kind, message = message } end
local enriched = 0
NZ.Veh.enrichDeep = function(t) enriched = enriched + 1 return t end
NZ.Veh.categoryOf = function() return 'car' end
local downed = false
NZ.Points.incapacitated = function() return downed end
NZ.State.ready = true
NZ.State.settings = { interface = { interaction = 'prompt' } }
local targetOn = false
local targets = {}
NZ.Target.available = function() return targetOn end
NZ.Target.addLocalEntity = function(id, entity, options) targets[id] = { entity = entity, options = options } return true end
NZ.Target.addSphere = function(id, coords, radius, options) targets[id] = { coords = coords, options = options } return true end
NZ.Target.remove = function(id) targets[id] = nil end
local createdPeds = 0
function IsModelInCdimage() return true end
function IsModelAPed() return true end
function HasModelLoaded() return true end
function CreatePed() createdPeds = createdPeds + 1 return 700 + createdPeds end
function GetGroundZFor_3dCoord(_, _, z) return true, z - 1.0 end
-- model classes the client knows (hash 44 = a super car the server has no class for)
function GetVehicleClassFromName(h) if h == 44 then return 7 end return nil end

load_('client/nui.lua')
load_('client/carlock/lock.lua')
load_('client/carlock/tracker.lua')
load_('client/carlock/keysapp.lua')
load_('client/carlock/locksmith.lua')
advance(500)
local CarLock = NZ.CarLock

--- Call a NUI callback like the interface does; returns the { ok, data, error } response.
local function nui(name, data)
  local fn = nuiCallbacks[name]
  if not fn then failures[#failures + 1] = 'NUI callback missing: ' .. name return {} end
  local out
  fn(data or {}, function(r) out = r end)
  local guard = 0
  while out == nil do
    clock = clock + 50
    runDue()
    guard = guard + 1
    if guard > 4000 then error('nui(): no answer for ' .. name) end
  end
  return out
end

local function lastMsg(action, app, field)
  for i = #nuiMessages, 1, -1 do
    local m = nuiMessages[i]
    if m.action == action and (app == nil or (type(m.data) == 'table' and m.data.app == app))
      and (field == nil or (type(m.data) == 'table' and type(m.data.data) == 'table' and m.data.data[field] ~= nil)) then
      return m
    end
  end
  return nil
end

--- The tracker blip (anything but the locksmith blips), or nil.
local function trackerBlip()
  for id, b in pairs(blipList) do
    if not (math.abs(b.x - 170.58) < 0.01 or math.abs(b.x - 1186.32) < 0.01) then return id end
  end
  return nil
end

local function byPlate(list, plate)
  for _, e in ipairs(list or {}) do if e.plate == plate then return e end end
  return nil
end

-- scripted server ---------------------------------------------------------------------
local NOW = 1700000000
local keysList = {
  { plate = 'ABC123', kind = 'item', keyKind = 'key', model = 'sultan', label = 'Vehicle key · ABC123', netId = 55 },
  { plate = 'FOB777', kind = 'item', keyKind = 'fob', model = 'zentorno', netId = 57 },
  { plate = 'TMP001', kind = 'temp', expires = NOW + 3600, reason = 'hotwire', netId = 56 },
  { plate = 'SHR001', kind = 'owner', shared = true },
  { plate = 'ITM999', kind = 'item', keyKind = 'key', model = 'asea' },
}
local statusList = {
  { plate = 'ABC123', owned = true, isOwner = true, hash = 11, model = 'sultan', spawned = true, netId = 55, profile = 'standard', profileLabel = 'Standard', keyType = 'key', locked = false, tracker = false, trackable = false },
  { plate = 'FOB777', owned = true, isOwner = true, hash = 22, model = 'zentorno', nickname = 'Zen', spawned = true, netId = 57, profile = 'highend', profileLabel = 'High-end', remote = true, keyType = 'fob', locked = true, tracker = true, trackable = true, distance = 300 },
  { plate = 'TMP001', owned = false, isOwner = false, hash = 33, spawned = true, netId = 56, profile = 'standard', profileLabel = 'Standard', keyType = 'key', locked = false },
  { plate = 'SHR001', owned = true, isOwner = false, hash = 44, model = 'blista', spawned = false, profile = 'standard', profileLabel = 'Standard', keyType = 'key' },
  { plate = 'ITM999', owned = true, isOwner = false, hash = 55, model = 'asea', spawned = false, profile = 'standard', profileLabel = 'Standard', keyType = 'key' },
}
local fobStatus = { plate = 'FOB777', spawned = true, netId = 57, trackable = true, tracker = true, distance = 300, coords = { x = 300.0, y = 0.0, z = 30.0 } }
server['nz:carlock:keys'] = function() return { ok = true, data = { mode = 'physical', keys = keysList } } end
server['nz:carlock:tracker'] = function(p)
  if p.plate == 'FOB777' then return { ok = true, data = { now = NOW, tracker = true, vehicles = { fobStatus } } } end
  if p.plate == 'ABC123' then return { ok = true, data = { now = NOW, tracker = true, vehicles = { statusList[1] } } } end
  return { ok = true, data = { now = NOW, tracker = true, vehicles = statusList } }
end

---------------------------------------------------------------------------------------
-- 1. Opening
---------------------------------------------------------------------------------------

check(commands.keys ~= nil and keybinds.nz_carlock_keyring ~= nil and keybinds.nz_carlock_keyring.defaultKey == 'F7', '/keys and the F7 keybind')
check(type(exported.OpenKeys) == 'function', 'client export OpenKeys')
Entity(201).state:set('nzLocked', true)
check(run(CarLock.openKeyRing) == true, 'key ring opens')
local open = lastMsg('open')
local data = open and open.data.data
check(open and open.data.app == 'keys' and data.mode == 'physical' and data.tracker == true, 'open message: app keys, mode, tracker')
check(data and data.ranges.key == 5.0 and data.ranges.fob == 30.0 and data.ranges.give == 3.0, 'ranges from the config')
check(enriched > 0, 'vehicle labels added (enrichDeep)')
local e = byPlate(data.keys, 'ABC123')
check(e and e.group == 'owned' and e.kind == 'item' and e.locked == true and e.distance == 3 and e.canShare and e.keyType == 'key',
  'owned key item: what this client sees wins (state bag lock, local distance)')
e = byPlate(data.keys, 'FOB777')
check(e and e.kind == 'fob' and e.group == 'owned' and e.trackable and e.distance == 300 and e.remote and e.nickname == 'Zen', 'fob: trackable, server distance')
e = byPlate(data.keys, 'TMP001')
check(e and e.group == 'temp' and e.kind == 'temp' and e.expiresIn and e.expiresIn <= 3600 and e.expiresIn >= 3590
  and e.reason == 'hotwire' and not e.canShare, 'temporary key: time left on the server clock, not shareable')
e = byPlate(data.keys, 'SHR001')
check(e and e.group == 'shared' and e.kind == 'owner' and not e.spawned and not e.canShare, 'garage share: shared group')
check(e and e.profile == 'highend' and e.tracker and e.remote and e.keyType == 'fob',
  'vehicle not out: the profile comes from the class this client knows (server had none)')
e = byPlate(data.keys, 'FOB777')
check(e and e.profile == 'highend', 'vehicle out: the server profile is kept')
e = byPlate(data.keys, 'ITM999')
check(e and e.group == 'items' and e.canShare and e.model == 'asea', "someone else's key item: items group, can be handed over")
check(run(CarLock.openKeyRing) == true and #calls['nz:carlock:keys'] == 1, 'a second open while open does not reload')

---------------------------------------------------------------------------------------
-- 2. Lock / unlock
---------------------------------------------------------------------------------------

server['nz:carlock:toggleLock'] = function(p) return { ok = true, data = { netId = p.netId, plate = 'ABC123', locked = false, kind = 'item' } } end
seated = 202
local r = nui('keys:lock', { plate = 'ABC123' })
check(r.ok == false and r.error == 'Get out of your vehicle to lock another one' and calls['nz:carlock:toggleLock'] == nil, 'lock: never another vehicle than the one you sit in')
seated = nil
r = nui('keys:lock', { plate = 'abc123' })
local sent = calls['nz:carlock:toggleLock'] and calls['nz:carlock:toggleLock'][1]
check(r.ok and r.data.plate == 'ABC123' and r.data.locked == false and sent and sent.netId == 55, 'lock: server toggles that net id')
r = nui('keys:lock', { plate = 'SHR001' })
check(not r.ok and r.error == 'The vehicle is not out', 'lock: vehicle not out')
server['nz:carlock:toggleLock'] = function() return { ok = false, error = 'The vehicle is too far away' } end
r = nui('keys:lock', { plate = 'FOB777' })
check(not r.ok and r.error == 'The vehicle is too far away', 'lock: the server answer (range) is passed through')
r = nui('keys:lock', { plate = 'NOPE' })
check(not r.ok and r.error == 'You do not have the keys of this vehicle', 'lock: unknown key')

---------------------------------------------------------------------------------------
-- 3. Locate, live readout, signal lost
---------------------------------------------------------------------------------------

r = nui('keys:locate', { plate = 'FOB777' })
check(r.ok and r.data.distance == 300 and waypoint and waypoint.x == 300.0, 'locate: waypoint at the server position')
check(CarLock.locating() == 'FOB777', 'locate: following')
local blipId = trackerBlip()
check(blipId ~= nil and blipList[blipId].x == 300.0, 'locate: blip on the vehicle')
local tr = lastMsg('update', 'keys', 'tracking')
check(tr and tr.data.data.tracking.plate == 'FOB777' and tr.data.data.tracking.distance == 300 and tr.data.data.tracking.live == false, 'locate: tracker readout sent to the key ring')
vehicles[203] = { plate = 'FOB777', net = 57, coords = vec3(100, 0, 0), engine = false, lock = 2, class = 7 }
advance(1500)
tr = lastMsg('update', 'keys', 'tracking')
check(blipList[blipId] and blipList[blipId].x == 100 and tr.data.data.tracking.live == true and tr.data.data.tracking.distance == 100, 'locate: in scope -> measured on this client')
vehicles[203] = nil
fobStatus = { plate = 'FOB777', spawned = false, trackable = false, tracker = true }
advance(4000)
tr = lastMsg('update', 'keys', 'tracking')
check(tr and tr.data.data.tracking.lost == true and trackerBlip() == nil and CarLock.locating() == nil, 'locate: stored -> signal lost, blip removed')
r = nui('keys:locate', { plate = 'ABC123' })
check(not r.ok and r.error == 'This vehicle has no tracker', 'locate: no tracker')
r = nui('keys:locate', { plate = 'FOB777' })
check(not r.ok and r.error == 'The vehicle is not out', 'locate: not out')
fobStatus = { plate = 'FOB777', spawned = true, netId = 57, trackable = true, tracker = true, distance = 300, coords = { x = 300.0, y = 0.0, z = 30.0 } }
nui('keys:locate', { plate = 'FOB777' })
r = nui('keys:locate', { plate = 'FOB777', stop = true })
check(r.ok and CarLock.locating() == nil and trackerBlip() == nil, 'locate: stop')

---------------------------------------------------------------------------------------
-- 4. Alarm, share, holders, revoke
---------------------------------------------------------------------------------------

server['nz:carlock:trackerAlarm'] = function(p) return { ok = true, data = { alarm = true, seconds = 20, cooldown = 60, plate = p.plate } } end
r = nui('keys:alarm', { plate = 'FOB777' })
check(r.ok and r.data.alarm == true and r.data.seconds == 20 and r.data.cooldown == 60
  and calls['nz:carlock:trackerAlarm'][1].plate == 'FOB777' and calls['nz:carlock:trackerAlarm'][1].on == nil, 'alarm: toggled on the server')
r = nui('keys:share', { plate = 'TMP001', target = 2 })
check(not r.ok and r.error == 'You cannot lend a temporary key' and calls['nz:carlock:share'] == nil, 'share: temporary key refused here')
server['nz:carlock:share'] = function() return { ok = true } end
r = nui('keys:share', { plate = 'ITM999', target = 2 })
check(r.ok and calls['nz:carlock:share'][1].plate == 'ITM999' and calls['nz:carlock:share'][1].target == 2, 'share: key item handed over by the server')
r = nui('keys:share', { plate = 'ITM999', target = 2.5 })
check(not r.ok, 'share: bad target')
server['nz:carlock:nearbyPlayers'] = function() return { ok = true, data = { { serverId = 2, name = 'Char 2', distance = 1.2 } } } end
r = nui('keys:players', {})
check(r.ok and r.data[1].serverId == 2 and r.data[1].name == 'Char 2', 'share picker: nearby players')
server['nz:carlock:holders'] = function()
  return { ok = true, data = {
    { identifier = 'CID2', name = 'Alex Doe', kind = 'virtual', at = NOW - 7200 },
    { identifier = 'CID3', name = 'Sam Roe', kind = 'temp', expires = NOW + 600, at = NOW - 60 },
  } }
end
r = nui('keys:holders', { plate = 'ABC123' })
check(r.ok and #r.data == 2 and r.data[1].kind == 'virtual' and r.data[1].agoSeconds >= 7200 and r.data[2].kind == 'temp'
  and r.data[2].expiresIn <= 600 and r.data[2].expiresIn > 500, 'holders: times on the server clock')
server['nz:carlock:revoke'] = function() return { ok = true } end
r = nui('keys:revoke', { plate = 'ABC123', identifier = 'CID3' })
check(r.ok and #r.data == 2 and calls['nz:carlock:revoke'][1].identifier == 'CID3', 'revoke: then the new holder list')
r = nui('keys:revoke', { plate = 'ABC123', identifier = ('x'):rep(80) })
check(not r.ok, 'revoke: bad identifier')

---------------------------------------------------------------------------------------
-- 5. Live loop, key changes, close, server event, going down
---------------------------------------------------------------------------------------

local before = #nuiMessages
advance(1100)
local live = lastMsg('update', 'keys', 'live')
check(live and #nuiMessages > before and live.data.data.live.ABC123 and live.data.data.live.ABC123.distance == 3, 'live loop: distance of vehicles in scope')
local keysCalls = #calls['nz:carlock:keys']
TriggerEvent('nz:client:carlock:keysChanged', 'ABC123')
TriggerEvent('nz:client:carlock:keysChanged', 'FOB777')
advance(1500)
check(#calls['nz:carlock:keys'] == keysCalls + 1 and lastMsg('update', 'keys', 'keys') ~= nil, 'key changes: one refresh pushed to the open ring')
nui('close', { app = 'keys' })
before = #nuiMessages
advance(2500)
local after = 0
for i = before + 1, #nuiMessages do if nuiMessages[i].action == 'update' then after = after + 1 end end
check(after == 0, 'closed: no more live updates')
TriggerEvent('nz:client:carlock:keyRing', { plate = 'FOB777' })
advance(500)
open = lastMsg('open')
check(open and open.data.app == 'keys' and open.data.data.focus == 'FOB777', 'server event opens the ring on that key')
downed = true
advance(1200)
check(lastMsg('close', nil) ~= nil and NZ.NUI.isOpen('keys') == false, 'going down closes the ring')
downed = false

---------------------------------------------------------------------------------------
-- 6. Locksmith
---------------------------------------------------------------------------------------

local shopBlips = 0
for _, b in pairs(blipList) do if b.x and math.abs(b.x - 170.58) < 0.01 then shopBlips = shopBlips + 1 end end
check(shopBlips == 1, 'one blip: the legal locksmith (the illegal one has none)')
check(#points == 4 and keybinds.nz_locksmith ~= nil, 'ped area + counter point per locksmith, interaction keybind')
local area, counter = points[1], points[2]
area.onEnter()
advance(200)
check(createdPeds == 1, 'NPC created near the locksmith')
check(targets.nz_locksmith_1 == nil, 'prompt mode: no target option')
pedPos = vec3(170.58, -1799.68, 29.32)
counter.onEnter()
advance(300)
local prompt = lastMsg('prompt')
check(prompt and prompt.data and prompt.data.label == 'Locksmith', 'counter: prompt shown')
local smith = {
  id = 1, name = 'Los Santos Locksmith', illegal = false, account = 'cash', mode = 'physical', money = 900, tempHours = 24, range = 25,
  services = {}, vehicles = { { plate = 'ABC123', hash = 11, vehicleType = 'car', isOwner = true, owned = true, hasKey = true, keyItems = 1, keyType = 'key', nearby = true, towing = false, blocked = {} } },
}
server['nz:carlock:locksmith:open'] = function(p) return p.id == 1 and { ok = true, data = smith } or { ok = false, error = 'Invalid request' } end
keybinds.nz_locksmith.onPressed()
advance(300)
open = lastMsg('open')
check(open and open.data.app == 'locksmith' and open.data.data.name == 'Los Santos Locksmith' and calls['nz:carlock:locksmith:open'][1].id == 1, 'keybind at the counter opens the locksmith')
server['nz:carlock:locksmith:service'] = function(p) return { ok = true, data = { message = 'done', data = smith, got = p } } end
r = nui('locksmith:service', { locksmithId = 1, service = 'program', plate = 'abc123' })
local svc = calls['nz:carlock:locksmith:service'][1]
check(r.ok and r.data.message == 'done' and svc.id == 1 and svc.service == 'program' and svc.plate == 'ABC123', 'service forwarded with id, service and plate')
r = nui('locksmith:service', { locksmithId = 1, service = 'hack', plate = 'ABC123' })
check(not r.ok and #calls['nz:carlock:locksmith:service'] == 1, 'unknown service refused on the client')
r = nui('locksmith:refresh', { locksmithId = 1 })
check(r.ok and r.data.id == 1, 'refresh')
r = nui('locksmith:refresh', { locksmithId = 7 })
check(not r.ok, 'refresh: unknown locksmith')
pedPos = vec3(190, -1799.68, 29.32)
advance(800)
check(NZ.NUI.isOpen('locksmith') == false, 'walking away closes the locksmith')
counter.onExit()
area.onExit()
check(lastMsg('prompt') and lastMsg('prompt').data == nil, 'prompt hidden when leaving the counter')

-- target mode: an option on the NPC
NZ.State.settings = { interface = { interaction = 'target' } }
targetOn = true
pedPos = vec3(170.58, -1799.68, 29.32)
area.onEnter()
advance(200)
local opt = targets.nz_locksmith_1 and targets.nz_locksmith_1.options[1]
check(opt and opt.label == 'Locksmith' and targets.nz_locksmith_1.entity ~= nil, 'target mode: option on the NPC')
counter.onEnter()
advance(300)
check(lastMsg('prompt').data == nil, 'target mode: no prompt')
opt.onSelect()
advance(300)
check(NZ.NUI.isOpen('locksmith') == true, 'target option opens the locksmith')
nui('close', { app = 'locksmith' })
area.onExit()
check(targets.nz_locksmith_1 == nil, 'NPC gone: target option removed')

if #failures > 0 then
  for _, f in ipairs(failures) do print('FAIL ' .. f) end
  print(('%d of %d checks failed'):format(#failures, checks))
  os.exit(1)
end
print(('keyring client OK (%d checks)'):format(checks))
