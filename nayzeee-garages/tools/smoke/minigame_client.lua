--[[
  Headless test for the NUI minigames' client side (no FiveM needed): client/carlock/minigame.lua
  with client/carlock/crime.lua in the crime client's stubbed runtime (the NUI bridge stubbed).

    page not ready -> no `minigames` in the starts (skill checks) -> minigame:ready -> hotwire
    wires (answer from the page, tokens, minimum play time) -> reader the page cannot draw
    (skill-check fallback with the solution), a silent page, leaving the seat, the time limit ->
    lock pick: overset (snapped), success (set order), app closed elsewhere, malformed answer,
    invalid puzzle.

  Usage (from the resource root):  lua5.4 tools/smoke/minigame_client.lua
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
_G.vec3 = vec3 -- config/carlock.lua builds vec3() values at load
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

-- the NUI bridge (client/nui.lua): open / close / send / register / onClose
local nuiHandlers, nuiOpen, nuiSends, closeHooks = {}, {}, {}, {}
NZ.NUI.register = function(name, fn) nuiHandlers[name] = fn end
NZ.NUI.open = function(app, data) nuiOpen[app] = data or true end
NZ.NUI.isOpen = function(app) return nuiOpen[app] ~= nil end
NZ.NUI.send = function(action, data) nuiSends[#nuiSends + 1] = { action = action, data = data } end
NZ.NUI.onClose = function(app, fn) closeHooks[app] = fn end
NZ.NUI.close = function(app)
  local was = nuiOpen[app] ~= nil
  nuiOpen[app] = nil
  if was and closeHooks[app] then closeHooks[app](app, 'lua') end
end

load_('bridge/client/target.lua')
load_('bridge/client/dispatch.lua')
load_('client/carlock/crime.lua')
load_('client/carlock/minigame.lua')
advance(1500)

local function lastSent(name)
  for i = #sent, 1, -1 do if sent[i].name == name then return sent[i].payload end end
  return nil
end
local function lastNote() return notes[#notes] end
local function lastHint() return hints[#hints] end
local function fire(name, ...) TriggerEvent(name, ...) end

local function lastSent(name)
  for i = #sent, 1, -1 do if sent[i].name == name then return sent[i].payload end end
  return nil
end
local function lastNote() return notes[#notes] end
local function lastHint() return hints[#hints] end
local function fire(name, ...) TriggerEvent(name, ...) end

local function lastSent(name)
  for i = #sent, 1, -1 do if sent[i].name == name then return sent[i].payload end end
  return nil
end
local function countSent(name, step)
  local n = 0
  for _, s in ipairs(sent) do if s.name == name and (not step or s.payload.step == step) then n = n + 1 end end
  return n
end
local function lastNote() return notes[#notes] end
local function nui(name, data) return nuiHandlers[name](data or {}) end
local function app() return type(nuiOpen.minigame) == 'table' and nuiOpen.minigame or nil end
local function noKeyDriver()
  seated = 202
  driver = { vehicle = 202, netId = 52, plate = 'P202', allowed = false }
  TriggerEvent('nz:client:carlock:driver', driver)
end
local function hotwire()
  noKeyDriver()
  keybindsByName.nz_carlock_hotwire.onPressed()
end

check(type(nuiHandlers['minigame:ready']) == 'function' and type(nuiHandlers['minigame:started']) == 'function'
  and type(nuiHandlers['minigame:finish']) == 'function', 'NUI callbacks minigame:ready / started / finish registered')

---------------------------------------------------------------------------------------
-- 1. Before the page is ready: no minigames offered (skill checks)
---------------------------------------------------------------------------------------

seated = 202
driver = { vehicle = 202, netId = 52, plate = 'P202', allowed = false }
TriggerEvent('nz:client:carlock:driver', driver)
local hot = {}
server['nz:carlock:hotwire'] = function(p)
  hot[#hot + 1] = p
  if p.step == 'start' then return { ok = true, data = { id = 1, method = 'skillcheck', difficulty = { 'easy' } } } end
  return { ok = true, data = { success = false } }
end
hotwire()
advance(1000)
check(hot[1] and hot[1].step == 'start' and hot[1].minigames == nil, 'page not ready: the start offers no minigames')
check(hot[2] and hot[2].step == 'finish' and hot[2].answer == nil, 'skill-check hotwire: finish without an answer')

nui('minigame:ready')
local support = CarLock.minigameSupport()
check(type(support) == 'table' and support.pins and support.wires and support.reader, 'page ready: pins, wires and reader supported')

---------------------------------------------------------------------------------------
-- 2. Hotwire with wires: the page's answer goes to the server after the minimum time
---------------------------------------------------------------------------------------

hot = {}
server['nz:carlock:hotwire'] = function(p)
  hot[#hot + 1] = p
  if p.step == 'start' then
    return { ok = true, data = { id = 2, method = 'wires', puzzle = { left = { 'red', 'yellow', 'blue' }, right = { 'blue', 'red', 'yellow' } } } }
  end
  driver = { vehicle = 202, netId = 52, plate = 'P202', allowed = true }
  return { ok = true, data = { success = true } }
end
local t0 = clock
hotwire()
advance(100)
check(hot[1].minigames and hot[1].minigames.wires == true, 'start payload: minigames from the page')
local a = app()
check(a and a.game == 'wires' and a.puzzle.left[1] == 'red' and a.timeLimit == 85 and a.vehicle.label == 'Sultan',
  'wires: app opened with the puzzle, time limit and vehicle name')
local token = a and a.token
nui('minigame:started', { token = token, ok = true })
nui('minigame:finish', { token = token + 1, success = true, answer = { 1, 1, 1 } })
advance(100)
check(app() ~= nil, 'a finish with another token is ignored')
nui('minigame:finish', { token = token, success = true, answer = { 2, 3, 1, 9 } })
advance(200)
check(app() == nil, 'finish: the app is closed')
check(#hot == 1, 'success held back until the server minimum (2.4 s)')
advance(2600)
local fin = lastSent('nz:carlock:hotwire')
check(fin and fin.step == 'finish' and fin.success == true and fin.answer and #fin.answer == 3 and fin.answer[1] == 2
  and fin.answer[3] == 1, 'wires finish: success with the cleaned answer (3 entries)')
local finAt = nil
for i = #sent, 1, -1 do if sent[i].name == 'nz:carlock:hotwire' then finAt = clock break end end
check(finAt and finAt - t0 >= 2400, 'wires finish not before the minimum play time')
check(lastNote().kind == 'success', 'hotwire success notified')

---------------------------------------------------------------------------------------
-- 3. Reader: the page cannot draw it -> skill-check fallback with the solution
---------------------------------------------------------------------------------------

seated = 202
driver = { vehicle = 202, netId = 52, plate = 'P202', allowed = false }
hot = {}
server['nz:carlock:hotwire'] = function(p)
  hot[#hot + 1] = p
  if p.step == 'start' then
    return { ok = true, data = { id = 3, method = 'reader', puzzle = { frequency = 433.9, phase = 212, tolerance = { frequency = 1.5, phase = 8 } } } }
  end
  return { ok = true, data = { success = p.success == true } }
end
local skills = calls.skillCheck and #calls.skillCheck or 0
hotwire()
advance(100)
a = app()
check(a and a.game == 'reader', 'reader: app opened')
nui('minigame:started', { token = a.token, ok = false })
advance(3000)
fin = lastSent('nz:carlock:hotwire')
check((calls.skillCheck and #calls.skillCheck or 0) == skills + 1, 'reader not drawable: ox_lib skill checks instead')
check(fin.step == 'finish' and fin.success == true and fin.answer.frequency == 433.9 and fin.answer.phase == 212,
  'fallback passed: the finish carries the puzzle solution')

advance(4500)

-- no 'started' at all within 4 s: fallback too
hot = {}
skillResult = false
hotwire()
advance(4500)
advance(500)
fin = lastSent('nz:carlock:hotwire')
check(app() == nil and fin.step == 'finish' and fin.success == false and fin.answer == nil,
  'page silent for 4 s: closed, skill checks, failed check = failure without an answer')
skillResult = true

-- leaving the driver seat ends the attempt
hot = {}
hotwire()
advance(100)
a = app()
nui('minigame:started', { token = a.token, ok = true })
seated = nil
advance(200)
fin = lastSent('nz:carlock:hotwire')
check(app() == nil and fin.step == 'finish' and fin.success == false, 'left the driver seat: closed, failure sent at once')
advance(4500) -- the (scripted) server answered success: crime.lua waits for the engine

-- time limit
hot = {}
hotwire()
advance(100)
a = app()
nui('minigame:started', { token = a.token, ok = true })
advance(84000)
check(app() ~= nil, 'still open before the 85 s limit')
advance(1500)
fin = lastSent('nz:carlock:hotwire')
check(app() == nil and fin.step == 'finish' and fin.success == false, 'time limit: closed and failed')
advance(4500)
seated, driver = nil, nil
TriggerEvent('nz:client:carlock:driver', nil)

---------------------------------------------------------------------------------------
-- 4. Lock pick with the pin lock
---------------------------------------------------------------------------------------

local pick = oxTarget.vehicles['Pick the lock']
local lp = {}
server['nz:carlock:lockpick'] = function(p)
  lp[#lp + 1] = p
  if p.step == 'start' then
    return { ok = true, data = { id = 10, method = 'pins', snapChance = 40,
      puzzle = { pins = 5, order = { 3, 1, 5, 2, 4 }, heights = { 0.6, 0.3, 0.8, 0.5, 0.7 } } } }
  end
  return { ok = true, data = { success = false, broke = true, alarm = true } }
end
pick.onSelect({ entity = 201 })
advance(900)
check(lp[1].minigames and lp[1].minigames.pins == true, 'lockpick start offers the pin lock')
a = app()
check(a and a.game == 'pins' and a.snapChance == 40 and a.puzzle.pins == 5, 'pins: app opened with the puzzle and snap chance')
nui('minigame:started', { token = a.token, ok = true })
nui('minigame:finish', { token = a.token, success = false, snapped = true })
advance(200)
fin = lastSent('nz:carlock:lockpick')
check(fin.step == 'finish' and fin.success == false and fin.snapped == true and fin.answer == nil, 'overset: snapped reported to the server')
check(notes[#notes - 1].message == 'Your lockpick snapped', 'snapped pick that broke: "Your lockpick snapped"')

-- success: the order set, held until 800 + 5 x 450 ms after the start
lp = {}
server['nz:carlock:lockpick'] = function(p)
  lp[#lp + 1] = p
  if p.step == 'start' then
    return { ok = true, data = { id = 11, method = 'pins', snapChance = 40,
      puzzle = { pins = 5, order = { 3, 1, 5, 2, 4 }, heights = { 0.6, 0.3, 0.8, 0.5, 0.7 } } } }
  end
  return { ok = true, data = { success = true } }
end
t0 = clock
pick.onSelect({ entity = 201 })
advance(900)
a = app()
nui('minigame:started', { token = a.token, ok = true })
nui('minigame:finish', { token = a.token, success = true, answer = { 3, 1, 5, 2, 4 }, snapped = true })
advance(1500)
check(#lp == 1, 'pins success held back (minimum 3.05 s)')
advance(2000)
fin = lastSent('nz:carlock:lockpick')
check(#lp == 2 and fin.success == true and fin.answer[1] == 3 and fin.answer[5] == 4 and fin.snapped == nil, 'pins success: the set order is the answer')
check(lastNote().message == 'The lock gave way', 'lock opened notified')

-- Esc / closed by another script: given up
lp = {}
pick.onSelect({ entity = 201 })
advance(900)
a = app()
nui('minigame:started', { token = a.token, ok = true })
NZ.NUI.close('minigame')
advance(200)
fin = lastSent('nz:carlock:lockpick')
check(#lp == 2 and fin.success == false, 'app closed elsewhere: the attempt is given up (failure)')

-- a bad answer from the page is not passed on
lp = {}
pick.onSelect({ entity = 201 })
advance(900)
a = app()
nui('minigame:started', { token = a.token, ok = true })
nui('minigame:finish', { token = a.token, success = true, answer = { 3, 'x', 5 } })
advance(4000)
fin = lastSent('nz:carlock:lockpick')
check(fin.step == 'finish' and fin.answer == nil, 'malformed answer dropped (the server then fails it)')

-- invalid puzzle: nothing opens, failure
lp = {}
server['nz:carlock:lockpick'] = function(p)
  lp[#lp + 1] = p
  if p.step == 'start' then return { ok = true, data = { id = 12, method = 'pins', puzzle = { pins = 9 } } } end
  return { ok = true, data = { success = false } }
end
pick.onSelect({ entity = 201 })
advance(1200)
check(app() == nil and lp[2] and lp[2].success == false, 'invalid puzzle: no app, failure')

advance(2000)
if #failures > 0 then
  print(('minigame client: %d of %d checks failed'):format(#failures, checks))
  for _, f in ipairs(failures) do print('  - ' .. f) end
  os.exit(1)
end
print(('minigame client OK (%d checks)'):format(checks))
