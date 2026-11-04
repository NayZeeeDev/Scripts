--[[
  Headless test for the crime client (no FiveM needed): bridge/client/{target,dispatch}.lua and
  client/carlock/crime.lua in a stubbed client runtime with a scripted server (lib.callback
  answers), a fake ox_target and a tiny world (vehicles, NPC drivers, a body).

    no-key driver hint (shown / hidden / search once) -> hotwire keybind (skill checks, finish,
    engine started once the ignition allows it) -> search (progress, loot line; no Search on
    script-spawned cars) -> lockpick: target option, the server's item-use event, qb lockpick
    event (vehicle nearby / none / living driver / a profile that does not take the tool) ->
    aim at an NPC driver (hold-up, keep aiming, finish) -> NPC steps run by the ped owner ->
    dead driver / request target options (mission bodies skipped), [E] prompt for a dead driver
    at the wheel without a target resource -> dispatch: offender-side adapters (ps-dispatch,
    cd_dispatch3d, failure report; qs-dispatch is server side), internal blip + notification
    + expiry.

  Usage (from the resource root):  lua5.4 tools/smoke/crime_client.lua
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

local handlers = {}
function AddEventHandler(name, fn)
  handlers[name] = handlers[name] or {}
  local entry = { name = name, fn = fn }
  table.insert(handlers[name], entry)
  return entry
end
function RemoveEventHandler() end
function RegisterNetEvent(name, fn) if fn then AddEventHandler(name, fn) end end
function TriggerEvent(name, ...) for _, e in ipairs(handlers[name] or {}) do e.fn(...) end end
local serverEvents = {}
function TriggerServerEvent(name, payload) serverEvents[#serverEvents + 1] = { name = name, payload = payload } end
function RegisterCommand() end

---------------------------------------------------------------------------------------
-- World
---------------------------------------------------------------------------------------

local vmeta = {}
vmeta.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vmeta) end
vmeta.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
local function vec3(x, y, z) return setmetatable({ x = x, y = y, z = z }, vmeta) end
vector3 = vec3
function vector4(x, y, z, w) return { x = x, y = y, z = z, w = w } end
vec4 = vector4
vec3 = vec3
local function joaat_(s)
  local h = 0
  for i = 1, #tostring(s) do h = (h * 31 + tostring(s):lower():byte(i)) & 0x7fffffff end
  return h
end
joaat = joaat_
GetHashKey = joaat_

local PED = 101
-- [handle] = { kind = 'veh'|'ped', net, coords, ... }
local ents = {
  [201] = { kind = 'veh', net = 51, coords = vec3(2, 0, 0), lock = 2, seats = {}, speed = 0.0 },   -- locked parked car
  [202] = { kind = 'veh', net = 52, coords = vec3(0, 0, 0), lock = 1, seats = {}, speed = 0.0, pop = 5 }, -- car we sit in
  [203] = { kind = 'veh', net = 53, coords = vec3(4, 0, 0), lock = 1, seats = {}, speed = 2.0 },   -- NPC driven
  [301] = { kind = 'ped', net = 61, coords = vec3(4, 0, 0), pop = 5, dead = false },               -- NPC driver of 203
  [302] = { kind = 'ped', net = 62, coords = vec3(1, 1, 0), pop = 5, dead = true, last = 204 },    -- body
  [204] = { kind = 'veh', net = 54, coords = vec3(5, 5, 0), lock = 1, seats = {}, lastDriver = 302, speed = 0.0, pop = 5 }, -- traffic
}
ents[203].seats[-1] = 301
local seated = nil
local aimingAt = nil
local calls = {}
local function record(name, ...) calls[name] = calls[name] or {} table.insert(calls[name], table.pack(...)) end
local function called(name) return calls[name] and #calls[name] or 0 end

local states = {}
function Entity(h)
  states[h] = states[h] or setmetatable({}, { __index = { set = function(self, k, v) rawset(self, k, v) end } })
  return { state = states[h] }
end
local bagHandlers = {}
function AddStateBagChangeHandler(key, _, fn) bagHandlers[key] = fn return 1 end
function PlayerPedId() return PED end
function PlayerId() return 0 end
function GetPlayerServerId() return 1 end
function GetPlayerFromServerId(id) return id == 1 and 0 or -1 end
function GetPlayerPed(player) return player == 0 and PED or 0 end
function DoesEntityExist(h) return ents[h] ~= nil or h == PED end
function IsEntityAVehicle(h) return ents[h] ~= nil and ents[h].kind == 'veh' end
function IsEntityAPed(h) return (ents[h] ~= nil and ents[h].kind == 'ped') or h == PED end
function NetworkGetEntityIsNetworked(h) return ents[h] ~= nil end
function NetworkGetNetworkIdFromEntity(h) return ents[h] and ents[h].net or 0 end
function NetworkDoesNetworkIdExist(net) for _, e in pairs(ents) do if e.net == net then return true end end return false end
function NetworkGetEntityFromNetworkId(net) for h, e in pairs(ents) do if e.net == net then return h end end return 0 end
function NetworkHasControlOfEntity() return true end
function GetEntityCoords(h) if ents[h] then return ents[h].coords end return vec3(0, 0, 0) end
function GetEntityModel() return joaat_('sultan') end
function GetVehicleClass(h) return ents[h] and ents[h].class or 0 end
local heading = 270.0          -- we face +X (the locked car at x = 2)
function GetEntityHeading(h) return h == PED and heading or 0.0 end
function GetVehicleDoorLockStatus(h) return ents[h] and ents[h].lock or 0 end
function GetVehiclePedIsIn(ped, last)
  if ped == PED then return seated or 0 end
  if last and ents[ped] then return ents[ped].last or 0 end
  for h, e in pairs(ents) do if e.kind == 'veh' and e.seats[-1] == ped then return h end end
  return 0
end
function GetPedInVehicleSeat(h, s)
  if seated == h and s == -1 then return PED end
  return ents[h] and ents[h].seats and ents[h].seats[s] or 0
end
function GetLastPedInVehicleSeat(h) return ents[h] and ents[h].lastDriver or 0 end
function IsPedInAnyVehicle(ped)
  if ped == PED then return seated ~= nil end
  return GetVehiclePedIsIn(ped, false) ~= 0
end
function IsPedInVehicle(ped, veh) return GetVehiclePedIsIn(ped, false) == veh end
function IsPedAPlayer(ped) return ped == PED end
function IsEntityDead(h) return ents[h] ~= nil and ents[h].dead == true end
function GetEntityPopulationType(h) return ents[h] and ents[h].pop or 0 end
function GetEntitySpeed(h) return ents[h] and ents[h].speed or 0.0 end
function IsPauseMenuActive() return false end
function IsNuiFocused() return false end
function IsPlayerFreeAiming() return aimingAt ~= nil end
function GetEntityPlayerIsFreeAimingAt() return aimingAt ~= nil, aimingAt or 0 end
function IsPlayerFreeAimingAtEntity(_, e) return aimingAt == e end
function GetWeapontypeGroup(w) return w == joaat_('WEAPON_PISTOL') and joaat_('GROUP_PISTOL') or joaat_('GROUP_MELEE') end
function GetStreetNameAtCoord() return 11, 0 end
function GetStreetNameFromHashKey(h) return h == 11 and 'Forum Drive' or '' end
function GetDisplayNameFromVehicleModel() return 'SULTAN' end
function GetLabelText() return 'Sultan' end
local pressE = false
function IsControlJustReleased(_, control)
  if control == 38 and pressE then pressE = false return true end
  return false
end
function DoesBlipExist(b) return b ~= nil and b ~= 0 end
local blipCount, removedBlips = 0, 0
function AddBlipForCoord() blipCount = blipCount + 1 record('AddBlipForCoord') return 900 + blipCount end
function AddBlipForRadius() record("AddBlipForRadius") return 800 end
function RemoveBlip() removedBlips = removedBlips + 1 end
local engineOn = {}
function SetVehicleEngineOn(h, on) engineOn[h] = on end
function GetResourceState(name)
  if name == 'ox_target' or name == 'cd_dispatch3d' or name == 'qs-dispatch' or name == 'ps-dispatch' then return 'started' end
  return 'missing'
end
function GetCurrentResourceName() return 'nayzeee-garages' end
function IsDuplicityVersion() return false end

setmetatable(_G, { __index = function(_, k)
  if type(k) == 'string' and k:match('^%u') then
    return function(...) record(k, ...) return nil end
  end
  return nil
end })

---------------------------------------------------------------------------------------
-- ox_lib, exports, scripted server
---------------------------------------------------------------------------------------

local server = {}               -- [callback] = fn(payload) -> result
local sent = {}                 -- { name, payload }
local skillResult, progressResult = true, true
local progressRunning = false
local keybindsByName, cacheHandlers = {}, {}
lib = {
  print = { info = function() end, warn = function() end, error = function(...) failures[#failures + 1] = 'lib.print.error: ' .. table.concat({ ... }, ' ') end },
  callback = setmetatable({
    await = function(name, _, payload)
      sent[#sent + 1] = { name = name, payload = payload }
      local fn = server[name]
      return fn and fn(payload) or { ok = false, error = 'no server' }
    end,
  }, { __call = function(_, name, _, cb, payload)
    sent[#sent + 1] = { name = name, payload = payload }
    local fn = server[name]
    if cb then cb(fn and fn(payload) or { ok = true }) end
  end }),
  skillCheck = function(list) record('skillCheck', list) return skillResult end,
  skillCheckActive = function() return false end,
  progressCircle = function(opts)
    record('progressCircle', opts)
    progressRunning = true
    local deadline = clock + (opts.duration or 0)
    while progressRunning and clock < deadline do Wait(50) end
    local finished = progressRunning
    progressRunning = false
    return finished and progressResult
  end,
  progressActive = function() return progressRunning end,
  cancelProgress = function() progressRunning = false end,
  requestAnimDict = function(d) return d end,
  addKeybind = function(o)
    keybindsByName[o.name] = o
    return setmetatable({ getCurrentKey = function() return o.defaultKey end }, { __index = o })
  end,
  onCache = function(key, fn) cacheHandlers[key] = fn end,
  getNearbyVehicles = function(coords, radius)
    local out = {}
    for h, e in pairs(ents) do
      if e.kind == 'veh' and #(e.coords - coords) <= radius then out[#out + 1] = { vehicle = h, coords = e.coords } end
    end
    return out
  end,
  getNearbyPeds = function(coords, radius)
    local out = {}
    for h, e in pairs(ents) do
      if e.kind == 'ped' and #(e.coords - coords) <= radius then out[#out + 1] = { ped = h, coords = e.coords } end
    end
    return out
  end,
  getClosestVehicle = function(coords, radius)
    local best, bestDist = nil, radius
    for h, e in pairs(ents) do
      if e.kind == 'veh' and #(e.coords - coords) <= bestDist then best, bestDist = h, #(e.coords - coords) end
    end
    return best
  end,
}
cache = { weapon = false }

local oxTarget = { vehicles = {}, entities = {} }
local psAlerts = {}
local exportTables = {
  ox_target = {
    addGlobalVehicle = function(options) for _, o in ipairs(options) do oxTarget.vehicles[o.label] = o end end,
    removeGlobalVehicle = function() end,
    addLocalEntity = function(e, options) oxTarget.entities[e] = options end,
    removeLocalEntity = function(e) oxTarget.entities[e] = nil end,
  },
  ['ps-dispatch'] = { CustomAlert = function(data) psAlerts[#psAlerts + 1] = data end },
  cd_dispatch3d = { GetPlayerInfo = function() return { unique_id = 'cd-42' } end },
}
exports = setmetatable({}, {
  __call = function() end,
  __index = function(_, res)
    local t = exportTables[res]
    return setmetatable({}, { __index = function(_, fn)
      return function(_, ...)
        if t and t[fn] then return t[fn](...) end
        error('No such export ' .. fn .. ' in resource ' .. res)
      end
    end })
  end,
})

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
local CarLock = NZ.CarLock

-- what lock.lua / ignition.lua / nui.lua would provide
local hints, notes, prompts = {}, {}, {}
NZ.NUI.hint = function(data) hints[#hints + 1] = data or false end
NZ.NUI.notify = function(kind, message, title) notes[#notes + 1] = { kind = kind, message = message, title = title } end
NZ.NUI.prompt = function(label) prompts[#prompts + 1] = label or false end
local driver = nil
CarLock.driverState = function() return driver end
local refreshed = 0
CarLock.refreshIgnition = function() refreshed = refreshed + 1 end
local keyCache = {}
CarLock.cachedKey = function(plate) return keyCache[plate] end
CarLock.plateOf = function(h) return 'P' .. tostring(h) end
local items = { lockpick = 1 }
NZ.Inventory.hasItem = function(item) return (items[item] or 0) > 0 end
NZ.Tow.isTowing = function() return false end
local job = nil
NZ.Bridge.getJob = function() return job end

load_('bridge/client/target.lua')
load_('bridge/client/dispatch.lua')
load_('client/carlock/crime.lua')
advance(1500)

local function lastSent(name)
  for i = #sent, 1, -1 do if sent[i].name == name then return sent[i].payload end end
  return nil
end
local function lastNote() return notes[#notes] end
local function lastHint() return hints[#hints] end
local function fire(name, ...) TriggerEvent(name, ...) end

---------------------------------------------------------------------------------------
-- 1. No-key driver hint, hotwire, search
---------------------------------------------------------------------------------------

seated = 202
driver = { vehicle = 202, netId = 52, plate = 'P202', allowed = false }
fire('nz:client:carlock:driver', driver)
local hint = lastHint()
check(type(hint) == 'table' and #hint.keys == 2 and hint.keys[1].keys[1] == 'H' and hint.keys[2].keys[1] == 'Z',
  'driver without a key: hint with Hotwire (H) and Search (Z)')
ents[202].pop = 7
fire('nz:client:carlock:driver', driver)
hint = lastHint()
check(type(hint) == 'table' and #hint.keys == 1 and hint.keys[1].label == 'Hotwire',
  'script- / player-spawned car: no Search in the hint (search.ambientOnly)')
ents[202].pop = 5
fire('nz:client:carlock:driver', driver)

server['nz:carlock:hotwire'] = function(p)
  if p.step == 'start' then return { ok = true, data = { id = 7, method = 'skillcheck', difficulty = { 'easy', 'hard', 'bogus' } } } end
  driver = { vehicle = 202, netId = 52, plate = 'P202', allowed = true }
  return { ok = true, data = { success = true } }
end
keybindsByName.nz_carlock_hotwire.onPressed()
advance(2000)
local start = sent[#sent - 1]
check(start and start.name == 'nz:carlock:hotwire' and start.payload.step == 'start' and start.payload.netId == 52
  and start.payload.street == 'Forum Drive' and start.payload.label == 'Sultan', 'hotwire start: vehicle, street and label sent')
local skill = calls.skillCheck and calls.skillCheck[#calls.skillCheck][1] or {}
check(#skill == 2 and skill[1] == 'easy' and skill[2] == 'hard', 'skill checks from the server, unknown entries dropped')
check(lastSent('nz:carlock:hotwire').step == 'finish' and lastSent('nz:carlock:hotwire').id == 7 and lastSent('nz:carlock:hotwire').success == true,
  'hotwire finish: the session id and the result')
check(engineOn[202] == true and refreshed >= 1 and lastNote().kind == 'success', 'hotwire success: engine started once allowed')
fire('nz:client:carlock:driver', driver)
check(lastHint() == false, 'driver with a key: hint hidden')

driver = { vehicle = 202, netId = 52, plate = 'P202', allowed = false }
fire('nz:client:carlock:driver', driver)
server['nz:carlock:search'] = function(p)
  if p.step == 'start' then return { ok = true, data = { id = 8, duration = 2000 } } end
  Entity(202).state.nzSearched = true
  return { ok = true, data = { success = true, found = { '$50', '2x water' } } }
end
keybindsByName.nz_carlock_search.onPressed()
advance(3000)
check(lastSent('nz:carlock:search').step == 'finish' and lastSent('nz:carlock:search').success == true, 'search: progress then finish')
check(lastNote().message:find('2x water', 1, true) ~= nil, 'search: loot shown')
bagHandlers.nzSearched('entity:202', 'nzSearched', true)
advance(100)
hint = lastHint()
check(type(hint) == 'table' and #hint.keys == 1, 'searched vehicle (state bag): only Hotwire left in the hint')
fire('nz:client:carlock:driver', driver)
hint = lastHint()
check(type(hint) == 'table' and #hint.keys == 1, 'searched vehicle: still only Hotwire after a driver update')
seated, driver = nil, nil
fire('nz:client:carlock:driver', nil)
check(lastHint() == false, 'out of the driver seat: hint hidden')

---------------------------------------------------------------------------------------
-- 2. Lockpick: target option, item use event, qb lockpick event
---------------------------------------------------------------------------------------

local pick = oxTarget.vehicles['Pick the lock']
check(pick ~= nil and oxTarget.vehicles['Take the key from the driver'] ~= nil and oxTarget.vehicles['Request the vehicle'] ~= nil,
  'target options registered (pick the lock, driver key, request the vehicle)')
check(pick and pick.canInteract(201, 1.0) == true, 'pick the lock: shown on a locked car with a tool')
check(pick and pick.canInteract(203, 1.0) == false, 'pick the lock: hidden on a car with a living driver / unlocked')
items.lockpick = 0
advance(1100)
check(pick and pick.canInteract(201, 1.0) == false, 'pick the lock: hidden without a tool of the profile')
items.lockpick = 1
advance(1100)

local lp = {}
server['nz:carlock:lockpick'] = function(p)
  lp[#lp + 1] = p
  if p.step == 'start' then return { ok = true, data = { id = 9, difficulty = { 'easy' } } } end
  return { ok = true, data = { success = false, broke = true } }
end
pick.onSelect({ entity = 201 })
advance(2000)
check(#lp == 2 and lp[1].netId == 51 and lp[1].tool == nil and lp[2].id == 9, 'target option: lockpick start (server picks the tool) + finish')
check(notes[#notes - 1].message == 'Your tool broke', 'broken tool reported')
fire('nz:client:carlock:crime', { action = 'lockpick', netId = 51, tool = 'screwdriver', slot = 3 })
advance(2000)
check(lp[3].tool == 'screwdriver' and lp[3].slot == 3, 'item use event: lockpick with that tool and slot')
-- the item use arrives while another script's progress bar runs: it waits for it (1.5 s at most)
progressRunning = true
local lpBusy = #lp
fire('nz:client:carlock:crime', { action = 'lockpick', netId = 51, tool = 'screwdriver', slot = 4 })
advance(600)
check(#lp == lpBusy, 'item use while another progress bar runs: waits')
progressRunning = false
advance(2000)
check(lp[lpBusy + 1] and lp[lpBusy + 1].step == 'start' and lp[lpBusy + 1].slot == 4,
  'item use: starts once the other progress bar ends')
progressRunning = true
lpBusy = #lp
fire('nz:client:carlock:crime', { action = 'lockpick', netId = 51, tool = 'screwdriver', slot = 4 })
advance(2000)
check(#lp == lpBusy and lastNote().message == 'You are busy', 'item use still busy after 1.5 s: told, not lost silently')
progressRunning = false
local lpMark = #lp
CarLock.onLockpickEvent(true)
advance(2000)
check(lp[lpMark + 1] and lp[lpMark + 1].tool == 'advancedLockpick', 'qb lockpick event (advanced) on a locked car nearby')
ents[201].coords = vec3(30, 0, 0)
local n = #lp
CarLock.onLockpickEvent(false)
advance(2000)
check(#lp == n, 'qb lockpick event without a locked car nearby: left to other scripts')
ents[201].coords = vec3(2, 0, 0)
ents[303] = { kind = 'ped', net = 63, coords = vec3(2, 0, 0), pop = 5, dead = false }
ents[201].seats[-1] = 303
CarLock.onLockpickEvent(false)
advance(2000)
check(#lp == n, 'qb lockpick event: a car with somebody alive at the wheel is not ours')
ents[201].seats[-1] = nil
ents[303] = nil
heading = 90.0
CarLock.onLockpickEvent(false)
advance(2000)
check(#lp == n, 'qb lockpick event: the locked car behind us is not ours (a door / register in front)')
heading = 270.0
ents[201].class = 7          -- super: high-end profile (advanced lockpick / hacking device only)
CarLock.onLockpickEvent(false)
advance(2000)
check(#lp == n, 'qb lockpick event: a plain lockpick next to a high-end car is left to other scripts')
CreateThread(function() CarLock.onLockpickEvent(true) end)   -- event handlers run in a thread
advance(2000)
check(#lp == n + 2 and lp[n + 1].tool == 'advancedLockpick' and lp[n + 2].step == 'finish',
  'qb lockpick event: an advanced lockpick opens the high-end car')
ents[201].class = nil

---------------------------------------------------------------------------------------
-- 3. NPC hold-up by aiming
---------------------------------------------------------------------------------------

local rob = {}
server['nz:carlock:npcRob'] = function(p)
  rob[#rob + 1] = p
  if p.step == 'start' then return { ok = true, data = { id = 11, outcome = 'comply', duration = 1000 } } end
  return { ok = true, data = { success = p.success } }
end
cacheHandlers.weapon(joaat_('WEAPON_KNIFE'))
aimingAt = 301
advance(1000)
check(#rob == 0, 'melee weapons do not start a hold-up')
job = { name = 'police', onDuty = true }
cacheHandlers.weapon(joaat_('WEAPON_PISTOL'))
advance(1000)
check(#rob == 0, 'on-duty assist jobs aiming at a driver: no hold-up')
check(oxTarget.vehicles['Request the vehicle'].canInteract(203, 2.0) == true, 'on-duty assist job: "Request the vehicle" on an NPC-driven car')
check(oxTarget.vehicles['Request the vehicle'].canInteract(202, 2.0) == false, '"Request the vehicle" hidden without an NPC driver')
job = nil
cacheHandlers.weapon(false)
advance(500)
check(oxTarget.vehicles['Request the vehicle'].canInteract(203, 2.0) == false, '"Request the vehicle" hidden for other jobs')
cacheHandlers.weapon(joaat_('WEAPON_PISTOL'))
advance(2000)
check(rob[1] and rob[1].step == 'start' and rob[1].netId == 53 and rob[1].pedNetId == 61, 'aiming at a slow NPC driver: hold-up start')
check(rob[2] and rob[2].step == 'finish' and rob[2].success == true, 'kept aiming through the hold-up: finish success')
advance(2000)
check(#rob == 2, 'the same driver is not asked again right away')

ents[302].coords = vec3(1, 1, 0)
local key = nil
for e, options in pairs(oxTarget.entities) do if e == 302 then key = options end end
check(key ~= nil and key[1].label == 'Search the driver', 'dead driver body: target option')
aimingAt = nil
cacheHandlers.weapon(false)
ents[302].pop = 7
advance(1100)
check(oxTarget.entities[302] == nil, 'a dead mission / script ped gets no "Search the driver" option (npc.ambientOnly)')
ents[302].pop = 5
advance(1100)
check(oxTarget.entities[302] ~= nil, 'the traffic driver\'s body gets it back')
ents[204].pop = 2
advance(1100)
check(oxTarget.entities[302] == nil, 'the last driver of a random parked car (population 2) gets no option (server rule)')
ents[204].pop = 5
advance(1100)

-- without ox_target / qb-target: [E] prompts
Config.Integrations.target = 'none'
advance(1100)
check(prompts[#prompts] == 'Search the driver', 'no target resource: [E] prompt at a body on the ground')
ents[302].coords = vec3(30, 0, 0)
ents[202].coords = vec3(50, 0, 0)
ents[304] = { kind = 'ped', net = 64, coords = vec3(2, 0, 0), pop = 5, dead = true }
ents[201].seats[-1] = 304
advance(1100)
check(prompts[#prompts] ~= 'Take the key from the driver', 'no prompt at a dead driver in a parked car (population 0 / 2)')
ents[201].pop = 4 -- the same car as traffic
advance(1100)
check(prompts[#prompts] == 'Take the key from the driver', 'no target resource: [E] prompt at a dead driver still at the wheel')
local bodySearch = nil
server['nz:carlock:deadDriver'] = function(p)
  if p.step == 'start' then bodySearch = p return { ok = false, error = 'stop here' } end
  return { ok = true, data = { success = false } }
end
pressE = true
advance(500)
check(bodySearch and bodySearch.netId == 51 and bodySearch.pedNetId == 64, '[E]: searches the driver at the wheel of that car')
ents[201].seats[-1] = nil
ents[201].pop = nil
ents[304] = nil
ents[302].coords = vec3(1, 1, 0)
ents[202].coords = vec3(0, 0, 0)
Config.Integrations.target = 'auto'
advance(1100)

---------------------------------------------------------------------------------------
-- 4. NPC steps (this client owns the ped)
---------------------------------------------------------------------------------------

local before = called('TaskVehicleTempAction')
fire('nz:client:carlock:npc', { step = 'holdup', ped = 61, vehicle = 53, robber = 1, ms = 5000 })
advance(200)
check(called('TaskVehicleTempAction') == before + 1 and called('TaskPlayAnim') > 0 and called('SetBlockingOfNonTemporaryEvents') > 0,
  'holdup: brakes, hands up')
-- control of the ped never arrives (another client owns it): no step on the local clone
local hasControl = NetworkHasControlOfEntity
NetworkHasControlOfEntity = function() return false end -- luacheck: ignore 121
fire('nz:client:carlock:npc', { step = 'flee', ped = 61, vehicle = 53, robber = 1 })
advance(1500)
check(called('TaskVehicleDriveWander') == 0, 'npc step without control of the ped: not run on the local clone')
NetworkHasControlOfEntity = hasControl -- luacheck: ignore 121
fire('nz:client:carlock:npc', { step = 'flee', ped = 61, vehicle = 53, robber = 1 })
advance(200)
check(called('TaskVehicleDriveWander') == 1, 'flee: drives off')
ents[203].seats[-1] = nil
fire('nz:client:carlock:npc', { step = 'fight', ped = 61, vehicle = 53, robber = 1, weapon = 'WEAPON_PISTOL' })
advance(500)
check(called('GiveWeaponToPed') == 1 and called('TaskCombatPed') == 1, 'fight: armed, attacks the robber')
fire('nz:client:carlock:npc', { step = 'release', ped = 61, vehicle = 53, robber = 1 })
advance(500)
check(called('TaskSmartFleePed') == 1, 'release: flees on foot')
fire('nz:client:carlock:npc', { step = 'nonsense', ped = 61 })
fire('nz:client:carlock:npc', { step = 'handover', ped = 61, vehicle = 53, robber = 1 })
advance(200)
check(called('TaskWanderStandard') >= 1, 'handover: walks away')

---------------------------------------------------------------------------------------
-- 5. Dispatch (client)
---------------------------------------------------------------------------------------

local alert = { id = 5, system = 'ps-dispatch', resource = 'ps-dispatch', kind = 'lockpick', code = '10-60', title = 'Vehicle break-in',
  message = 'Red Sultan', coords = { x = 1, y = 2, z = 3 }, plate = 'AB1', modelHash = 1, priority = 2, jobs = { 'police' },
  blip = { sprite = 225, color = 1, scale = 1.0, seconds = 90, radius = 0.0, flash = true } }
fire('nz:client:dispatch', alert)
local ps = psAlerts[#psAlerts]
check(ps and ps.dispatchCode == 'nz_lockpick' and ps.length == 2 and ps.model == 'Sultan' and ps.jobs[1] == 'police'
  and ps.coords.x == 1, 'ps-dispatch CustomAlert: server payload, length in minutes, model label filled in')
check(lastSent('nz:dispatch:sent') and lastSent('nz:dispatch:sent').id == 5, 'delivered alert reported')
alert.system, alert.resource, alert.id = 'cd_dispatch', 'cd_dispatch3d', 6
fire('nz:client:dispatch', alert)
local cdEv = serverEvents[#serverEvents]
check(cdEv.name == 'cd_dispatch:AddNotification' and cdEv.payload.unique_id == 'cd-42' and cdEv.payload.blip.time == 2,
  'cd_dispatch3d: GetPlayerInfo unique id, AddNotification')
local eventsBefore = #serverEvents
alert.system, alert.resource, alert.id = 'qs-dispatch', 'qs-dispatch', 7
fire('nz:client:dispatch', alert)
check(#serverEvents == eventsBefore and lastSent('nz:dispatch:failed').id == 7,
  'qs-dispatch is sent by the server: no client path (reported, never sent from here)')
alert.system, alert.resource, alert.id = 'cd_dispatch', 'cd_dispatch', 8
fire('nz:client:dispatch', alert)
check(lastSent('nz:dispatch:failed') and lastSent('nz:dispatch:failed').id == 8, 'system not running here: failure reported to the server')
alert.system, alert.resource, alert.id = 'custom', nil, 9
fire('nz:client:dispatch', alert)
check(lastSent('nz:dispatch:failed').id == 9, 'custom client adapter returning false: failure reported')

local blipsBefore = called('AddBlipForCoord')
fire('nz:client:dispatch:alert', { kind = 'theft', code = '10-60', title = 'Vehicle theft', message = 'Sultan', coords = { x = 1, y = 2, z = 3 },
  blip = { sprite = 225, color = 1, scale = 1.0, seconds = 10, radius = 50.0, flash = true }, sound = true })
check(called('AddBlipForCoord') == blipsBefore + 1 and called('AddBlipForRadius') == 1 and lastNote().title == '10-60 · Vehicle theft'
  and lastNote().message:find('Forum Drive', 1, true) ~= nil and called('PlaySoundFrontend') == 1,
  'internal alert: notification with street, blip + radius, sound')
advance(12000)
check(removedBlips >= 2, 'internal alert: blips removed after their time')

-- street / model text the offender's client sent: the officer's client uses its own lookup
fire('nz:client:dispatch:alert', { kind = 'lockpick', code = '10-60', title = 'Vehicle break-in',
  message = 'Red Fake Car · plate AB 12', coords = { x = 1, y = 2, z = 3 }, street = 'Nowhere Lane',
  model = 'Fake Car', modelHash = 123, streetFromClient = true, modelFromClient = true,
  blip = { sprite = 225, color = 1, scale = 1.0, seconds = 10, radius = 0.0, flash = false }, sound = false })
check(lastNote().message:find('Forum Drive', 1, true) ~= nil and lastNote().message:find('Nowhere Lane', 1, true) == nil
  and lastNote().message:find('Red Sultan', 1, true) ~= nil and lastNote().message:find('Fake Car', 1, true) == nil,
  'internal alert: street and model the offender sent are replaced by the officer client\'s lookup')
-- a crafted label that matches part of the colour must replace the model, not the colour
fire('nz:client:dispatch:alert', { kind = 'lockpick', code = '10-60', title = 'Vehicle break-in',
  message = 'Metallic Black Black · plate AB 12', coords = { x = 1, y = 2, z = 3 }, street = 'Nowhere Lane',
  model = 'Black', color = 'Metallic Black', modelHash = 123, streetFromClient = true, modelFromClient = true,
  blip = { sprite = 225, color = 1, scale = 1.0, seconds = 10, radius = 0.0, flash = false }, sound = false })
check(lastNote().message:find('Metallic Black Sultan', 1, true) ~= nil
  and lastNote().message:find('Metallic Sultan', 1, true) == nil,
  'internal alert: a model label that matches part of the colour rewrites the model, not the colour')
fire('nz:client:dispatch:alert', { kind = 'theft', code = '10-60', title = 'Vehicle theft', message = 'Sultan',
  coords = { x = 1, y = 2, z = 3 }, street = 'Server Street',
  blip = { sprite = 225, color = 1, scale = 1.0, seconds = 10, radius = 0.0, flash = false }, sound = false })
check(lastNote().message:find('Server Street', 1, true) ~= nil, 'internal alert: a street not from the offender is kept')

for _, f in ipairs(failures) do print('FAIL ' .. f) end
if #failures > 0 then
  print(('%d of %d checks failed'):format(#failures, checks))
  os.exit(1)
end
print(('crime client OK (%d checks)'):format(checks))
