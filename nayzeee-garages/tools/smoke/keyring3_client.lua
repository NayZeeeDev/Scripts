--[[
  Headless test for the key ring v2 CLIENT side (docs/V2_CHANGES.md G.3 / G.5 / G.8 / G.10 /
  G.11): client/carlock/keysapp.lua with the real NUI bridge and lock.lua / tracker.lua, in the
  stubbed client runtime of tools/smoke/keyring_client.lua (harness copied below) with a
  scripted server.

    ring data (key mode, prefs, fob design, key item slot / id, immobiliser) -> keys:remote
    (engine / windows, out of range as refused = 'range') -> keys:track (position only when
    trackable, the reason otherwise) -> keys:drop (key items only, tossed from a vehicle) ->
    keys:leave (only a key someone gave you) -> ground key inspect card (held, Keep checks the
    id, closing returns it) -> settings forwarded -> Ghost PIN pad: enter (the server's verdict,
    never the pad's), collect, the driver leaving closes it, a window in front falls back.

  Usage (from the resource root):  lua5.4 tools/smoke/keyring3_client.lua
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
rawset(_G, 'vec3', vec3) -- config/carlock.lua (fobProps) uses vec3
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
  { plate = 'DEN001', kind = 'item', keyKind = 'fob', model = 'zentorno', netId = 58 },
}
local statusList = {
  { plate = 'ABC123', owned = true, isOwner = true, hash = 11, model = 'sultan', spawned = true, netId = 55, profile = 'standard', profileLabel = 'Standard', keyType = 'key', locked = false, tracker = false, trackable = false },
  { plate = 'FOB777', owned = true, isOwner = true, hash = 22, model = 'zentorno', nickname = 'Zen', spawned = true, netId = 57, profile = 'highend', profileLabel = 'High-end', remote = true, keyType = 'fob', locked = true, tracker = true, trackable = true, distance = 300 },
  { plate = 'TMP001', owned = false, isOwner = false, hash = 33, spawned = true, netId = 56, profile = 'standard', profileLabel = 'Standard', keyType = 'key', locked = false, trackerAccess = false },
  { plate = 'SHR001', owned = true, isOwner = false, hash = 44, model = 'blista', spawned = false, profile = 'standard', profileLabel = 'Standard', keyType = 'key' },
  { plate = 'ITM999', owned = true, isOwner = false, hash = 55, model = 'asea', spawned = false, profile = 'standard', profileLabel = 'Standard', keyType = 'key' },
  { plate = 'DEN001', owned = true, isOwner = false, hash = 22, model = 'zentorno', spawned = true, netId = 58, profile = 'highend', profileLabel = 'High-end', remote = true, keyType = 'fob', tracker = true, trackerAccess = false, trackable = false, origin = 'locksmith' },
}
local fobStatus = { plate = 'FOB777', spawned = true, netId = 57, trackable = true, tracker = true, distance = 300, coords = { x = 300.0, y = 0.0, z = 30.0 } }
server['nz:carlock:tracker'] = function(p)
  if p.plate == 'FOB777' then return { ok = true, data = { now = NOW, tracker = true, vehicles = { fobStatus } } } end
  if p.plate == 'ABC123' then return { ok = true, data = { now = NOW, tracker = true, vehicles = { statusList[1] } } } end
  if p.plate == 'DEN001' then return { ok = true, data = { now = NOW, tracker = true, vehicles = { statusList[6] } } } end
  return { ok = true, data = { now = NOW, tracker = true, mode = 'physical', keys = keysList, vehicles = statusList } }
end
--- Key ring list calls (nz:carlock:tracker without a plate).
local function listCalls() -- luacheck: ignore 211
  local n = 0
  for _, p in ipairs(calls['nz:carlock:tracker'] or {}) do if p.plate == nil then n = n + 1 end end
  return n
end

---------------------------------------------------------------------------------------

-- FiveM promises (keysapp.lua waits for the keypad with them)
promise = { new = function()
  local p = { done = false }
  function p:resolve(v) if self.done then return end self.done, self.value = true, v end
  return p
end }
Citizen = { Await = function(p) while not p.done do Wait(50) end return p.value end }

keysList[1].slot, keysList[1].keyId = 3, 'kid1'
keysList[2].slot, keysList[2].keyId = 4, 'kid2'
table.insert(keysList, { plate = 'VIR001', kind = 'virtual' })
table.insert(statusList, { plate = 'VIR001', owned = true, isOwner = false, hash = 66, spawned = false, profile = 'highend',
  profileLabel = 'High-end', keyType = 'fob', immobiliser = 'ghost' })
statusList[2].immobiliser = 'ghost'

---------------------------------------------------------------------------------------
-- 1. Ring data
---------------------------------------------------------------------------------------

Entity(201).state:set('nzLocked', true)
vehicles[201].engine = true
check(run(CarLock.openKeyRing) == true, 'key ring opens')
local data = lastMsg('open', 'keys').data.data
check(data.keyMode == 'flexible' and type(data.prefs) == 'table' and data.prefs.keyOrder == 'recent', 'key mode and the player key order')
check(data.view == 'ring' and data.dialog == false, 'ring view, no dialog')
local e = byPlate(data.keys, 'ABC123')
check(e and e.slot == 3 and e.keyId == 'kid1' and e.design == 'classic' and e.engine == true and e.immobiliser == 'none',
  'key item: slot / key id, admin default design, engine this client sees')
e = byPlate(data.keys, 'FOB777')
check(e and e.immobiliser == 'ghost' and e.engine == nil, 'immobiliser from the server status')
e = byPlate(data.keys, 'VIR001')
check(e and e.slot == nil and e.keyId == nil and e.kind == 'virtual', 'a virtual key carries no item reference')

-- a window in front: the ring never stacks on it (the fob HUD without focus does not count)
nui('close', { app = 'keys' })
NZ.NUI.open('garage', {})
check(run(CarLock.openKeyRing) == false, 'no key ring over a focused window')
NZ.NUI.close('garage')
NZ.NUI.open('hud', {}, false)
check(run(CarLock.openKeyRing) == true, 'a window without focus does not block the ring')
NZ.NUI.close('hud')

---------------------------------------------------------------------------------------
-- 2. Remote (hold = engine, keep holding = windows)
---------------------------------------------------------------------------------------

server['nz:carlock:remote'] = function(p)
  if p.netId == 57 then return { ok = false, error = L('The vehicle is too far away') } end
  return { ok = true, data = { action = p.action, on = p.on, netId = p.netId, plate = 'ABC123' } }
end
local r = nui('keys:remote', { plate = 'ABC123', action = 'engine', on = false })
check(r.ok and r.data.action == 'engine' and r.data.on == false, 'engine off from the fob')
local sent = calls['nz:carlock:remote'][1]
check(sent and sent.netId == 55 and sent.plate == nil and sent.on == false, 'remote by net id of the key')
r = nui('keys:remote', { plate = 'FOB777', action = 'windows', on = true })
check(r.ok and r.data.refused == 'range', 'out of fob range is an answer')
check(not nui('keys:remote', { plate = 'ABC123', action = 'boot', on = true }).ok, 'unknown remote action refused')
check(not nui('keys:remote', { plate = 'ABC123', action = 'engine', on = 'yes' }).ok, 'on must be a boolean')
check(not nui('keys:remote', { plate = 'NOPE1', action = 'engine', on = true }).ok, 'no remote without a key')

---------------------------------------------------------------------------------------
-- 3. Track
---------------------------------------------------------------------------------------

r = nui('keys:track', { plate = 'FOB777' })
check(r.ok and r.data.trackable and r.data.coords and r.data.coords.x == 300.0 and r.data.distance == 300 and r.data.reason == nil
  and r.data.live == false and r.data.immobiliser == 'none' and r.data.me, 'trackable: the tracker position, the player position')
r = nui('keys:track', { plate = 'ABC123' })
check(r.ok and r.data.coords == nil and r.data.reason == 'notracker' and r.data.locked == true and r.data.engine == true,
  'no tracker: no position, the reason; lock / engine this client sees')
check(not nui('keys:track', { plate = '' }).ok, 'track needs a plate')

---------------------------------------------------------------------------------------
-- 4. Drop / give back
---------------------------------------------------------------------------------------

server['nz:carlock:ground:drop'] = function() return { ok = true, data = { id = 'g9' } } end
r = nui('keys:drop', { plate = 'ABC123' })
local drop = calls['nz:carlock:ground:drop'] and calls['nz:carlock:ground:drop'][1]
check(r.ok and drop and drop.slot == 3 and drop.keyId == 'kid1' and drop.toss == nil, 'drop a key item at your feet')
seated = 201
r = nui('keys:drop', { plate = 'FOB777' })
drop = calls['nz:carlock:ground:drop'][2]
check(r.ok and drop and drop.slot == 4 and drop.toss == true, 'in a vehicle the key goes out of the window')
seated = nil
check(not nui('keys:drop', { plate = 'VIR001' }).ok and #calls['nz:carlock:ground:drop'] == 2, 'a virtual key cannot be dropped')

check(not nui('keys:leave', { plate = 'ABC123' }).ok and calls['nz:carlock:leaveKey'] == nil, 'an owned key is not given back')
server['nz:carlock:leaveKey'] = function() return { ok = true } end
r = nui('keys:leave', { plate = 'VIR001' })
check(r.ok and calls['nz:carlock:leaveKey'][1].plate == 'VIR001', 'give back a virtual key')

---------------------------------------------------------------------------------------
-- 5. Ground key inspect card
---------------------------------------------------------------------------------------

nui('close', { app = 'keys' })
server['nz:carlock:ground:inspect'] = function(p)
  return { ok = true, data = { id = p.id, plate = 'GRD001', keyKind = 'fob', kind = 'item', label = 'Fob GRD001', model = 'xls', droppedAt = 0 } }
end
server['nz:carlock:ground:release'] = function() return { ok = true } end
server['nz:carlock:ground:pickup'] = function() return { ok = true, data = { plate = 'GRD001', keyKind = 'fob' } } end
check(run(CarLock.openKeyInspect, { groundId = 'g1' }) == true, 'inspect card opens')
local m = lastMsg('open', 'keys').data.data
check(m.view == 'dialog' and m.dialog.kind == 'inspect' and m.dialog.source == 'ground' and m.dialog.id == 'g1'
  and m.dialog.info.plate == 'GRD001' and m.dialog.info.keyKind == 'fob' and m.dialog.info.hash == GetHashKey('xls'),
  'card data: the key, the vehicle hash for its name')
check(run(CarLock.openKeyRing) == false, 'the ring waits while the card is open')
check(not nui('keys:groundKeep', { id = 'other' }).ok and calls['nz:carlock:ground:pickup'] == nil, 'Keep only the key on the card')
nui('close', { app = 'keys' })
advance(300)
check(calls['nz:carlock:ground:release'] and calls['nz:carlock:ground:release'][1].id == 'g1', 'closing the card returns the key')
run(CarLock.openKeyInspect, { groundId = 'g2' })
r = nui('keys:groundKeep', { id = 'g2' })
advance(1500)
check(r.ok and calls['nz:carlock:ground:pickup'][1].id == 'g2' and not NZ.NUI.isOpen('keys'), 'Keep picks it up and closes the card')
check(#calls['nz:carlock:ground:release'] == 1, 'a kept key is not released')

---------------------------------------------------------------------------------------
-- 6. Settings
---------------------------------------------------------------------------------------

server['nz:carlock:playerSettings'] = function() return { ok = true, data = { settings = { keyOrder = 'name' }, defaults = {} } } end
server['nz:carlock:savePlayerSettings'] = function(p) return { ok = true, data = { settings = p.settings, defaults = {} } } end
r = nui('keys:settings', {})
check(r.ok and r.data.settings.keyOrder == 'name', 'settings loaded')
r = nui('keys:saveSettings', { settings = { units = 'imperial' } })
check(r.ok and calls['nz:carlock:savePlayerSettings'][1].settings.units == 'imperial', 'settings saved through the server')
check(not nui('keys:saveSettings', {}).ok, 'save needs settings')

---------------------------------------------------------------------------------------
-- 7. Ghost PIN pad
---------------------------------------------------------------------------------------

local tries = 0
server['nz:carlock:pin'] = function(p)
  tries = tries + 1
  if p.pin == '4321' then return { ok = true, data = { success = true } } end
  return { ok = true, data = { success = false, error = 'Wrong PIN', attemptsLeft = 2 } }
end
seated = 201
local result
CreateThread(function() result = CarLock.enterPin(201, { plate = 'ABC123', cooldown = 0, attemptsLeft = 3 }) end)
advance(200)
m = lastMsg('open', 'keys')
local pad = m and m.data.data.dialog and m.data.data.dialog.pad
check(pad and pad.mode == 'enter' and pad.plate == 'ABC123' and pad.attemptsLeft == 3, 'the driver pad opens alone')
r = nui('keys:pinEnter', { id = pad.id, pin = '1111' })
check(r.ok and r.data.success == false and r.data.attemptsLeft == 2, 'wrong PIN: the server answer with attempts left')
check(calls['nz:carlock:pin'][1].netId == 55, 'PIN sent for the vehicle the pad is about')
check(not nui('keys:pinEnter', { id = pad.id, pin = '12a4' }).ok and tries == 1, 'four digits only')
check(not nui('keys:pinEnter', { id = pad.id + 5, pin = '1234' }).ok and tries == 1, 'an old pad id is refused')
-- the pad claims success without the server: not trusted
nui('keys:pinDone', { id = pad.id, success = true })
advance(200)
check(result == false, 'the pad cannot report success on its own')
nui('close', { app = 'keys' })

result = nil
CreateThread(function() result = CarLock.enterPin(201, { plate = 'ABC123' }) end)
advance(200)
pad = lastMsg('open', 'keys').data.data.dialog.pad
r = nui('keys:pinEnter', { id = pad.id, pin = '4321' })
nui('keys:pinDone', { id = pad.id })
advance(200)
check(r.ok and r.data.success and result == true, 'right PIN: accepted by the server')
nui('close', { app = 'keys' })

-- the driver gets out: the pad closes, nothing accepted
result = nil
CreateThread(function() result = CarLock.enterPin(201, { plate = 'ABC123' }) end)
advance(200)
seated = nil
advance(800)
check(result == false and not NZ.NUI.isOpen('keys'), 'leaving the seat closes the pad')

-- collect: the digits go back
seated = 201
local digits
CreateThread(function() digits = CarLock.pinPrompt({ plate = 'ABC123' }) end)
advance(200)
pad = lastMsg('open', 'keys').data.data.dialog.pad
check(pad.mode == 'collect', 'collect pad')
nui('keys:pinDone', { id = pad.id, pin = '9876' })
advance(200)
check(digits == '9876', 'pinPrompt returns the digits')
nui('close', { app = 'keys' })

-- set: the owner's PIN through nz:carlock:setPin
server['nz:carlock:immobiliser'] = function(p) return { ok = true, data = { plate = p.plate, level = 'ghost', pinSet = true } } end
server['nz:carlock:setPin'] = function(p) return p.oldPin == '4321' and { ok = true, data = { plate = p.plate, level = 'ghost', pinSet = true } } or { ok = false, error = 'The current PIN is wrong' } end
CarLock.openPinSetup('ABC123')
advance(300)
pad = lastMsg('open', 'keys').data.data.dialog.pad
check(pad.mode == 'set' and pad.pinSet == true, 'set pad asks the current PIN first')
check(not nui('keys:pinSet', { plate = 'ABC123', pin = '1111', oldPin = '0000' }).ok, 'wrong current PIN refused by the server')
check(nui('keys:pinSet', { plate = 'ABC123', pin = '1111', oldPin = '4321' }).ok, 'PIN changed')
nui('keys:pinDone', { id = pad.id })
advance(200)
nui('close', { app = 'keys' })

-- another window in front: the core's prompt stays the fallback
NZ.NUI.open('garage', {})
local before = #nuiMessages
CreateThread(function() digits = CarLock.pinPrompt({ plate = 'ABC123' }) end)
advance(300)
local padShown = false
for i = before + 1, #nuiMessages do
  local msg = nuiMessages[i]
  if msg.action == 'open' and msg.data.app == 'keys' then padShown = true end
end
check(not padShown, 'no pad over another window (ox_lib fallback)')
NZ.NUI.close('garage')
seated = nil

if #failures > 0 then
  for _, f in ipairs(failures) do print('FAIL ' .. f) end
  print(('%d of %d checks failed'):format(#failures, checks))
  os.exit(1)
end
print(('keyring3 client OK (%d checks)'):format(checks))
