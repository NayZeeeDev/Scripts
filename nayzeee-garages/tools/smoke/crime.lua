--[[
  Headless test for the crime tools and police alerts (no FiveM needed).

  Loads the real shared files, bridge/server/{inventory,dispatch,listeners}.lua and
  server/carlock/{keys,main,crime,exports}.lua in a stubbed server runtime: a fake world
  (players, NPC peds with health / population type / network owner, vehicles with seats,
  speed, colours, locks), a fake ox_inventory and fake dispatch resources. Traces:

    dispatch: detection order, each adapter's payload (wasabi_mdt, rcore_dispatch, cd_dispatch,
      qs-dispatch, core_dispatch, ps-dispatch 2.x / 3.x, internal, custom, none), offender-side
      routing, the one-time client fallback, unit conversions, SendDispatch export;
    lockpick: item use (fallthrough when nothing to do / car lock off / car behind the player /
      live driver / a crime action running), success, too fast for ox_lib, failure with break /
      alarm / alarm alert, the crime kind kept when the alarm also sounds, wrong tool, towing,
      key holders, busy, late, buses and trucks (wider reach);
    hotwire: skill check, progress, hack (item, break), item use in the driver seat;
    search: loot (money, items, spare key item), once per vehicle, owned vehicles, cancel,
      script-spawned vehicles, job vehicles, per-player cooldown, a stale search lock;
    NPC robbery: comply (too fast, success), flee, fight, unarmed, players, mission peds,
      owned vehicles, speed, cooldown, driver killed during the hold-up, a hold-up never
      finished (the server releases the driver);
    dead driver: recorded / seated / last driver, alive, searched twice, unrelated body,
      mission peds, a last driver far from the vehicle;
    assist: on-duty job, other jobs, off duty, no alert;
    alerts: visible (fake) plate, model label, colour, position, cooldown, markup stripped.

  Usage (from the resource root):  lua5.4 tools/smoke/crime.lua
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
    clock = clock + 10
    runDue()
    guard = guard + 1
    if guard > 20000 then error('run(): the call never returned') end
  end
  return table.unpack(results, 1, results.n)
end

local handlers, clientEvents, serverEvents = {}, {}, {}
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
function TriggerEvent(name, ...)
  serverEvents[#serverEvents + 1] = { name = name, args = table.pack(...) }
  for _, e in ipairs(handlers[name] or {}) do
    source = '' -- luacheck: ignore 111
    e.fn(...)
  end
end
function TriggerClientEvent(name, target, payload) clientEvents[#clientEvents + 1] = { name = name, target = target, payload = payload } end

local function lastClient(name, target)
  for i = #clientEvents, 1, -1 do
    local e = clientEvents[i]
    if e.name == name and (target == nil or e.target == target) then return e end
  end
  return nil
end
local function countClient(name, target)
  local n = 0
  for _, e in ipairs(clientEvents) do
    if e.name == name and (target == nil or e.target == target) then n = n + 1 end
  end
  return n
end
local function lastServer(name)
  for i = #serverEvents, 1, -1 do if serverEvents[i].name == name then return serverEvents[i] end end
  return nil
end
local function countServer(name)
  local n = 0
  for _, e in ipairs(serverEvents) do if e.name == name then n = n + 1 end end
  return n
end

---------------------------------------------------------------------------------------
-- Natives: players, peds, vehicles, state bags
---------------------------------------------------------------------------------------

local vmeta = {}
vmeta.__sub = function(a, b) return setmetatable({ x = a.x - b.x, y = a.y - b.y, z = a.z - b.z }, vmeta) end
vmeta.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
local function vec3(x, y, z) return setmetatable({ x = x or 0.0, y = y or 0.0, z = z or 0.0 }, vmeta) end
vector3 = vec3
-- like CfxLua: type(vector3(...)) is 'vector3', not 'table'
local rawtype = type
type = function(v)
  if rawtype(v) == 'table' and getmetatable(v) == vmeta then return 'vector3' end
  return rawtype(v)
end
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

-- players: 1 thief, 2 police on duty, 3 bystander (owns the NPCs), 4 sheriff off duty
local online = { [1] = 'CID001', [2] = 'CID002', [3] = 'CID003', [4] = 'CID004' }
local jobs = { [2] = { name = 'police', onDuty = true }, [4] = { name = 'sheriff', onDuty = false } }
local playerPos = { [1] = vec3(0, 0, 0), [2] = vec3(0, 1, 0), [3] = vec3(40, 0, 0), [4] = vec3(60, 0, 0) }
local weaponOf = {}            -- [ped] = weapon hash
local UNARMED = joaat_('WEAPON_UNARMED')
local PISTOL = joaat_('WEAPON_PISTOL')
function GetPlayerName(src) return online[tonumber(src)] and ('Player' .. tostring(src)) or nil end
function GetPlayerPed(src) return online[tonumber(src)] and (1000 + tonumber(src)) or 0 end
function GetPlayerRoutingBucket() return 0 end
function GetEntityRoutingBucket() return 0 end
function IsDuplicityVersion() return true end
function GetCurrentResourceName() return 'nayzeee-garages' end
function GetInvokingResource() return nil end
function GetConvar(_, default) return default end
function GetPlayers() local out = {} for src in pairs(online) do out[#out + 1] = tostring(src) end table.sort(out) return out end
function GetSelectedPedWeapon(ped) return weaponOf[ped] or UNARMED end
local resourceStates = { ['qb-core'] = 'started', ox_inventory = 'started' }
function GetResourceState(name) return resourceStates[name] or 'missing' end
local metadata = { ['ox_lib:version'] = '3.42.1' }   -- requestAnimationFrame skill checks (2000 ms a turn)
function GetResourceMetadata(res, key) return metadata[res .. ':' .. key] end

GlobalState = {}
local bagHandlers = {}
function AddStateBagChangeHandler(key, _, fn) bagHandlers[key] = bagHandlers[key] or {} table.insert(bagHandlers[key], fn) end
function GetEntityFromStateBagName(name) return tonumber(tostring(name):match('^entity:(%d+)$')) or 0 end
local kvp = {}
function GetResourceKvpString(k) return kvp[k] end
function SetResourceKvp(k, v) kvp[k] = v end
function DeleteResourceKvp(k) kvp[k] = nil end

-- entities: vehicles (type 2) and NPC peds (type 1); player peds are 1001..1004
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

local function spawnVehicle(plate, model, coords, extra)
  nextHandle, nextNet = nextHandle + 1, nextNet + 1
  local e = { kind = 2, plate = plate, model = joaat_(model or 'sultan'), netId = nextNet, seats = {}, lastSeats = {},
    coords = coords or vec3(2, 0, 0), pop = 2, lock = 2, speed = 0.0, colour = 28 }
  for k, v in pairs(extra or {}) do e[k] = v end
  entities[nextHandle] = e
  return nextHandle, nextNet
end

local function spawnPed(coords, extra)
  nextHandle, nextNet = nextHandle + 1, nextNet + 1
  local e = { kind = 1, netId = nextNet, coords = coords or vec3(3, 0, 0), pop = 5, health = 200, owner = 3 }
  for k, v in pairs(extra or {}) do e[k] = v end
  entities[nextHandle] = e
  return nextHandle, nextNet
end

local function seatIn(ped, vehicle, s)
  for _, e in pairs(entities) do
    if e.kind == 2 then
      for k, p in pairs(e.seats) do if p == ped then e.seats[k] = nil e.lastSeats[k] = ped end end
    end
  end
  if vehicle then entities[vehicle].seats[s or -1] = ped end
end

local function isPlayerPed(h) return h > 1000 and h < 1005 and online[h - 1000] ~= nil end
function DoesEntityExist(h) return entities[h] ~= nil or isPlayerPed(h) end
function GetEntityType(h) if entities[h] then return entities[h].kind end return isPlayerPed(h) and 1 or 0 end
function IsPedAPlayer(ped) return isPlayerPed(ped) end
function GetAllVehicles() local out = {} for h, e in pairs(entities) do if e.kind == 2 then out[#out + 1] = h end end table.sort(out) return out end
function GetVehicleNumberPlateText(h) local e = entities[h] return e and e.plate and (e.plate .. '        '):sub(1, 8) or '' end
function NetworkGetEntityFromNetworkId(netId)
  for h, e in pairs(entities) do if e.netId == netId then return h end end
  return 0
end
function NetworkGetNetworkIdFromEntity(h) return entities[h] and entities[h].netId or 0 end
function NetworkGetEntityOwner(h) return entities[h] and entities[h].owner or -1 end
function GetPedInVehicleSeat(h, s) local e = entities[h] return e and e.seats and e.seats[s] or 0 end
function GetLastPedInVehicleSeat(h, s) local e = entities[h] return e and e.lastSeats and e.lastSeats[s] or 0 end
function GetVehiclePedIsIn(ped)
  for h, e in pairs(entities) do
    if e.kind == 2 then for _, p in pairs(e.seats) do if p == ped then return h end end end
  end
  return 0
end
function GetEntityModel(h) return entities[h] and entities[h].model or 0 end
function GetVehicleType() return 'automobile' end
local headings = { [1001] = 270.0 }    -- the thief faces +X (towards the cars at x > 0)
function GetEntityHeading(h) return headings[h] or 0.0 end
function GetEntityPopulationType(h) return entities[h] and entities[h].pop or 0 end
function GetEntityHealth(h) return entities[h] and entities[h].health or 200 end
function GetEntityVelocity(h) return vec3(entities[h] and entities[h].speed or 0.0, 0, 0) end
function GetVehicleColours(h) return entities[h] and entities[h].colour or 0, 0 end
function GetIsVehiclePrimaryColourCustom() return false end
function GetEntityCoords(h)
  if entities[h] then return entities[h].coords end
  return playerPos[h - 1000] or vec3(0, 0, 0)
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
-- ox_lib, exports, json, inventory, dispatch resources
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
function RegisterCommand() end

local inv = { [1] = {}, [2] = {}, [3] = {}, [4] = {} }
local function copyT(t) local o = {} for k, v in pairs(t or {}) do o[k] = v end return o end
local oxDefined = { vehicle_key = true, vehicle_fob = true, lockpick = true, advancedlockpick = true, screwdriver = true,
  hacking_device = true, water = true, phone = true }
local ox = {
  Items = function(name) return oxDefined[name] and { name = name } or nil end,
  GetInventoryItems = function(src)
    local out = {}
    for slot, item in pairs(inv[src] or {}) do out[slot] = { name = item.name, count = item.count, metadata = copyT(item.metadata), slot = slot } end
    return out
  end,
  GetSlot = function(src, slot)
    local item = (inv[src] or {})[slot]
    return item and { name = item.name, count = item.count, metadata = copyT(item.metadata), slot = slot } or nil
  end,
  CanCarryItem = function() return true end,
  AddItem = function(src, name, count, md)
    local list = inv[src]
    if not list then return false end
    local slot = 1
    while list[slot] do slot = slot + 1 end
    list[slot] = { name = name, count = count, metadata = copyT(md), slot = slot }
    return true, { { slot = slot } }
  end,
  RemoveItem = function(src, name, count, _, slot)
    local list = inv[src] or {}
    if not slot then
      for s, item in pairs(list) do if item.name == name then slot = s break end end
    end
    local item = slot and list[slot]
    if not item or item.name ~= name then return false end
    item.count = item.count - count
    if item.count <= 0 then list[slot] = nil end
    return true
  end,
  SetMetadata = function(src, slot, md) if inv[src][slot] then inv[src][slot].metadata = md end end,
  Search = function(src, kind, name)
    local n = 0
    for _, item in pairs(inv[src] or {}) do if item.name == name then n = n + item.count end end
    return kind == 'count' and n or {}
  end,
}
local function give(src, name, count) return ox.AddItem(src, name, count or 1, {}) end
local function count(src, name)
  local n = 0
  for _, item in pairs(inv[src]) do if item.name == name then n = n + item.count end end
  return n
end

local qbCore = {
  Functions = {},
  Shared = { Vehicles = {
    sultan = { name = 'Sultan', brand = 'Karin', model = 'sultan', category = 'sedans', hash = joaat_('sultan') },
    zentorno = { name = 'Zentorno', brand = 'Pegassi', model = 'zentorno', category = 'super', hash = joaat_('zentorno') },
    coach = { name = 'Dashound', brand = 'Brute', model = 'coach', category = 'service', hash = joaat_('coach') },
    taxi = { name = 'Taxi', brand = 'Vapid', model = 'taxi', category = 'service', hash = joaat_('taxi') },
  }, Items = {} },
}

-- dispatch resources
local psTargeted, coreCalls, coreFails = {}, {}, false
local exportTables = {
  ox_inventory = ox,
  ['qb-core'] = { GetCoreObject = function() return qbCore end },
  ['ps-dispatch'] = { SendTargetedAlert = function(targets, data) psTargeted[#psTargeted + 1] = { targets = targets, data = data } return true end },
  core_dispatch = {
    sendAlert = function(data) if coreFails then error('no such export') end coreCalls[#coreCalls + 1] = { kind = 'sendAlert', data = data } end,
    addCall = function(...) coreCalls[#coreCalls + 1] = { kind = 'addCall', args = table.pack(...) } end,
  },
}
local exported = {}
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
NZ.Ready = true
local CarLock = NZ.CarLock
local C = Config.CarLock

local notifications, money, logs = {}, {}, {}
NZ.Bridge.getIdentifier = function(src) return online[tonumber(src)] end
NZ.Bridge.getSourceByIdentifier = function(id) for src, cid in pairs(online) do if cid == id then return src end end return nil end
NZ.Bridge.getCharacterName = function(id) return 'Name ' .. tostring(id) end
NZ.Bridge.getJob = function(src) return jobs[tonumber(src)] end
NZ.Bridge.getGang = function() return nil end
NZ.Bridge.getPlayer = function() return nil end
NZ.Bridge.notify = function(src, message, kind) notifications[#notifications + 1] = { src = src, message = message, kind = kind } end
NZ.Bridge.addMoney = function(src, account, amount) money[#money + 1] = { src = src, account = account, amount = amount } return true end
NZ.Bridge._fw = { hasAnyGroup = function() return false end }
NZ.Access.rateLimit = function() return true end
NZ.Access.isAdmin = function() return false end
NZ.Logs.add = function(event, src, data) logs[#logs + 1] = { event = event, src = src, data = data } end
local function logged(event)
  for i = #logs, 1, -1 do if logs[i].event == event then return logs[i] end end
  return nil
end

local rows = { OWN111 = { plate = 'OWN111', owner = 'CID003', model = 'sultan', hash = joaat_('sultan'), version = 0 } }
NZ.DB.getVehicle = function(plate) local r = rows[plate] return r and copyT(r) or nil end
NZ.DB.getVehiclesByOwner = function() return {} end
NZ.DB.shares = { forIdentifier = function() return {} end, forPlate = function() return {} end }
local settingsTable = {}
NZ.DB.keys = {
  list = function() return {} end, forIdentifier = function() return {} end,
  add = function() return true end, remove = function() return true end, clear = function() return true end,
  count = function() return 0 end,
  state = function(plate)
    local r = rows[plate]
    if not r then return false end
    return { version = r.version, mark = r.mark, owner = r.owner, markSupported = true }
  end,
  claim = function(plate, mark, initial)
    local r = rows[plate]
    if not r or r.mark == mark then return false end
    r.version = r.mark == nil and initial or r.version + 1
    r.mark = mark
    return true
  end,
  bumpVersion = function(plate) local r = rows[plate] if not r then return nil end r.version = r.version + 1 return r.version end,
  secret = function(candidate)
    settingsTable.secret = settingsTable.secret or candidate
    return settingsTable.secret
  end,
}
NZ.Vehicles.out = {}
NZ.Vehicles.fleetOf = function() return nil, nil end
NZ.Vehicles.accessOf = function(src, row) if row.owner == online[src] then return 'owner' end return nil end
local towingSet = {}
NZ.Tow.isTowing = function(entity) return towingSet[entity] == true end

load_('bridge/server/inventory.lua')
load_('bridge/server/dispatch.lua')
load_('bridge/server/listeners.lua')
load_('server/carlock/keys.lua')
load_('server/carlock/main.lua')
load_('server/carlock/crime.lua')
load_('server/carlock/exports.lua')
advance(3000)

local function cb(name, src, payload)
  local fn = callbacks[name]
  if not fn then failures[#failures + 1] = 'callback missing: ' .. name return { ok = false } end
  return run(fn, src, payload)
end
local function hasKey(src, plate) return run(CarLock.hasKey, src, plate) end
local function alertsTo(target) return countClient('nz:client:dispatch:alert', target) end

-- deterministic chances
local function chances(tbl, values) for k, v in pairs(values) do tbl[k] = v end end
local standard = C.profiles.standard
local highend = C.profiles.highend
chances(standard.accessTools[1], { breakChance = 0, alarmChance = 0, alertChance = 0 })
chances(standard.hotwire, { alertChance = 0, alarmChance = 0 })
chances(highend.hotwire, { alertChance = 0, alarmChance = 0, breakChance = 0 })
chances(C.search, { alertChance = 0 })
chances(C.npc, { alertChance = 0, cooldown = 0 })
C.npc.reactions = { handover = 100, drop = 0, fight = 0, flee = 0 }
C.alarm.alertChance = 0
C.dispatch.cooldown = 30

---------------------------------------------------------------------------------------
-- 1. Dispatch bridge
---------------------------------------------------------------------------------------

check(NZ.Dispatch.system() == 'internal', 'auto without a dispatch resource: internal')
local ok = run(NZ.Dispatch.alert, 1, { kind = 'lockpick', plate = 'AB 12', model = 'Karin Sultan', color = 'Red' })
local internal = lastClient('nz:client:dispatch:alert')
check(ok == true and alertsTo(2) == 1 and alertsTo(4) == 0 and alertsTo(1) == 0 and alertsTo(3) == 0,
  'internal: only on-duty players of the configured jobs get the alert')
check(internal and internal.payload.coords.x == 0 and internal.payload.coords.y == 0, 'internal: position = the offender\'s server ped')
check(internal and internal.payload.code == '10-60' and internal.payload.title == 'Vehicle break-in'
  and internal.payload.message:find('Red Karin Sultan', 1, true) and internal.payload.message:find('AB 12', 1, true),
  'internal: code, translated title and message from colour / model / plate')
check(internal and internal.payload.blip.seconds == 90 and internal.payload.blip.sprite == 225 and internal.payload.blip.flash == true,
  'internal: blip from the config')
run(NZ.Dispatch.alert, nil, { kind = 'robbery', coords = vec3(100, 200, 30) })
internal = lastClient('nz:client:dispatch:alert', 2)
check(internal.payload.coords.x == 100 and internal.payload.priority == 1 and internal.payload.blip.sprite == 229,
  'alert without an offender: given position, kind priority and per-kind blip')
check(run(NZ.Dispatch.alert, nil, { kind = 'theft' }) == false, 'no offender and no position: nothing sent')

local function startRes(name)
  resourceStates[name] = 'started'
  TriggerEvent('onResourceStart', name)
end
local function stopRes(name)
  resourceStates[name] = nil
  TriggerEvent('onResourceStop', name)
end

-- ps-dispatch: 3.x from the server (SendTargetedAlert), offender or not; 2.x on the offender's
-- client (CustomAlert), without an offender the 2.x notify event
startRes('ps-dispatch')
metadata['ps-dispatch:version'] = '2.2.1'
check(NZ.Dispatch.system() == 'ps-dispatch', 'auto: ps-dispatch detected after it started')
run(NZ.Dispatch.alert, 1, { kind = 'hotwire', plate = 'XY1' })
local toClient = lastClient('nz:client:dispatch', 1)
check(toClient and toClient.payload.system == 'ps-dispatch' and toClient.payload.resource == 'ps-dispatch'
  and type(toClient.payload.id) == 'number' and toClient.payload.jobs[1] == 'police',
  'ps-dispatch 2.x: sent to the offender\'s client with the server-built payload')
local okFb = cb('nz:dispatch:failed', 3, { id = toClient.payload.id })
check(okFb.ok and okFb.data == false, 'another player cannot replay an alert id')
local before = alertsTo(2)
okFb = cb('nz:dispatch:failed', 1, { id = toClient.payload.id, reason = 'no export' })
check(okFb.data == true and alertsTo(2) == before + 1, 'client failure: the alert goes out through internal')
okFb = cb('nz:dispatch:failed', 1, { id = toClient.payload.id })
check(okFb.data == false and alertsTo(2) == before + 1, 'client failure fallback: once per alert id')
metadata['ps-dispatch:version'] = '3.0.0'
local psClientBefore, psTargetedBefore = countClient('nz:client:dispatch', 1), #psTargeted
run(NZ.Dispatch.alert, 1, { kind = 'hotwire', plate = 'XY2' })
check(countClient('nz:client:dispatch', 1) == psClientBefore and #psTargeted == psTargetedBefore + 1
  and psTargeted[#psTargeted].data.plate == 'XY2' and psTargeted[#psTargeted].targets[1] == 2,
  'ps-dispatch 3.x with an offender: SendTargetedAlert from the server (a modified client cannot drop it)')
run(NZ.Dispatch.alert, nil, { kind = 'alarm', coords = vec3(1, 2, 3), plate = 'XY1' })
local targeted = psTargeted[#psTargeted]
check(targeted and #targeted.targets == 1 and targeted.targets[1] == 2 and targeted.data.addToList == true
  and targeted.data.alert.length == 1 and targeted.data.alert.radius == 60.0 and countServer('ps-dispatch:server:notify') == 0,
  'ps-dispatch 3.x without offender: SendTargetedAlert to on-duty police, never the notify event')
metadata['ps-dispatch:version'] = '2.2.1'
run(NZ.Dispatch.alert, nil, { kind = 'theft', coords = vec3(1, 2, 3) })
local notifyEv = lastServer('ps-dispatch:server:notify')
check(notifyEv and type(notifyEv.args[1].alert) == 'table' and notifyEv.args[1].alert.sound == 'Lose_1st'
  and notifyEv.args[1].jobs[1] == 'police', 'ps-dispatch 2.x: notify event with the full alert table and jobs')

-- cd_dispatch / cd_dispatch3d
startRes('cd_dispatch3d')
check(NZ.Dispatch.system() == 'cd_dispatch', 'auto: cd_dispatch3d before ps-dispatch')
run(NZ.Dispatch.alert, 1, { kind = 'theft' })
toClient = lastClient('nz:client:dispatch', 1)
check(toClient.payload.system == 'cd_dispatch' and toClient.payload.resource == 'cd_dispatch3d', 'cd_dispatch3d: offender client')
run(NZ.Dispatch.alert, nil, { kind = 'theft', coords = vec3(5, 5, 5) })
local cdEv = lastServer('cd_dispatch:AddNotification')
check(cdEv and cdEv.args[1].blip.time == 2 and cdEv.args[1].blip.colour == 1 and cdEv.args[1].job_table[1] == 'police'
  and type(cdEv.args[1].unique_id) == 'string', 'cd_dispatch without offender: server event, blip time in minutes')

-- qs-dispatch
startRes('qs-dispatch')
check(NZ.Dispatch.system() == 'cd_dispatch', 'auto: cd_dispatch before qs-dispatch')
stopRes('cd_dispatch3d')
check(NZ.Dispatch.system() == 'qs-dispatch', 'auto: qs-dispatch after cd stopped')
run(NZ.Dispatch.alert, nil, { kind = 'theft', coords = vec3(5, 5, 5), plate = 'QS1' })
local qsEv = lastServer('qs-dispatch:server:CreateDispatchCall')
check(qsEv and qsEv.args[1].blip.time == 90000 and qsEv.args[1].callCode.code == '10-60' and qsEv.args[1].otherData[1].text == 'QS1',
  'qs-dispatch without offender: server event, blip time in ms')
local toClientBefore = countClient('nz:client:dispatch', 1)
local qsBefore = countServer('qs-dispatch:server:CreateDispatchCall')
run(NZ.Dispatch.alert, 1, { kind = 'hotwire', plate = 'QS2', model = 'Karin Sultan', color = 'Red', street = 'Forum Dr' })
qsEv = lastServer('qs-dispatch:server:CreateDispatchCall')
check(countServer('qs-dispatch:server:CreateDispatchCall') == qsBefore + 1 and countClient('nz:client:dispatch', 1) == toClientBefore
  and qsEv.args[1].otherData[1].text == 'QS2' and qsEv.args[1].otherData[2].text == 'Red Karin Sultan'
  and qsEv.args[1].otherData[3].text == 'Forum Dr',
  'qs-dispatch with an offender: still the server event (a client cannot drop it), plate / vehicle / street')

-- core_dispatch (server), falls back to addCall
startRes('core_dispatch')
stopRes('qs-dispatch')
run(NZ.Dispatch.alert, 1, { kind = 'theft' })
check(#coreCalls == 1 and coreCalls[1].kind == 'sendAlert' and coreCalls[1].data.time == 90000 and coreCalls[1].data.job == 'police',
  'core_dispatch: sendAlert on the server (time in ms), even with an offender')
coreFails = true
run(NZ.Dispatch.alert, 1, { kind = 'theft' })
check(#coreCalls == 2 and coreCalls[2].kind == 'addCall', 'core_dispatch: addCall when sendAlert fails')
coreFails = false

-- rcore_dispatch
startRes('rcore_dispatch')
run(NZ.Dispatch.alert, 1, { kind = 'robbery' })
local rcEv = lastServer('rcore_dispatch:server:sendAlert')
check(rcEv and rcEv.args[1].blip_time == 90 and rcEv.args[1].default_priority == 'high' and rcEv.args[1].type == 'car_robbery',
  'rcore_dispatch: server event, blip time in seconds, priority name')

-- wasabi_mdt wins over everything
startRes('wasabi_mdt')
run(NZ.Dispatch.alert, 1, { kind = 'lockpick', street = 'Grove Street' })
local waEv = lastServer('wasabi_mdt:createExternalDispatch')
check(waEv and waEv.args[1].location == 'Grove Street' and waEv.args[1].type == 'robbery' and waEv.args[1].priority == 2
  and waEv.args[1].departments[1] == 'police' and waEv.args[1].coords.x == 0, 'wasabi_mdt: createExternalDispatch with departments')
for _, name in ipairs({ 'wasabi_mdt', 'rcore_dispatch', 'core_dispatch', 'ps-dispatch' }) do stopRes(name) end

-- configured systems
C.dispatch.system = 'none'
TriggerEvent('onResourceStart', 'ps-dispatch')
check(run(NZ.Dispatch.alert, 1, { kind = 'theft' }) == false, "'none': no alert")
C.dispatch.system = 'rcore_dispatch'
TriggerEvent('onResourceStop', 'rcore_dispatch')
before = alertsTo(2)
run(NZ.Dispatch.alert, 1, { kind = 'theft' })
local warnedMissing = false
for _, w in ipairs(printed.warn) do if w:find('rcore_dispatch is not running', 1, true) then warnedMissing = true end end
check(alertsTo(2) == before + 1 and warnedMissing, 'configured system not running: internal + one warning')
C.dispatch.system = 'custom'
TriggerEvent('onResourceStop', 'rcore_dispatch')
before = alertsTo(2)
run(NZ.Dispatch.alert, 1, { kind = 'theft' })
check(alertsTo(2) == before + 1, "'custom' adapter returning false: internal")
C.dispatch.system = 'auto'
TriggerEvent('onResourceStop', 'rcore_dispatch')

-- export
check(type(exported.SendDispatch) == 'function', 'SendDispatch export registered')
before = alertsTo(2)
check(run(exported.SendDispatch, { kind = 'theft', coords = vec3(9, 9, 9) }) == true and alertsTo(2) == before + 1,
  'SendDispatch(alert) without an offender')
check(run(exported.SendDispatch, 1, { kind = 'theft' }) == true, 'SendDispatch(src, alert)')
check(run(exported.SendDispatch, 1, 'nope') == false, 'SendDispatch with a bad alert returns false')

---------------------------------------------------------------------------------------
-- 2. Lockpicking doors
---------------------------------------------------------------------------------------

local car, carNet = spawnVehicle('NPC100', 'sultan', vec3(2, 0, 0))
give(1, 'lockpick', 2)
local lpSlot = nil
for slot, item in pairs(inv[1]) do if item.name == 'lockpick' then lpSlot = slot end end

check(run(CarLock.useAccessTool, 1, 'lockpick', lpSlot, {}, 'lockpick') == true, 'item use next to a locked car: handled')
local ev = lastClient('nz:client:carlock:crime', 1)
check(ev and ev.payload.action == 'lockpick' and ev.payload.netId == carNet and ev.payload.tool == 'lockpick', 'item use starts the client flow on that car')
headings[1001] = 90.0          -- back to the car (facing a house door / a register)
check(run(CarLock.useAccessTool, 1, 'lockpick', lpSlot, {}, 'lockpick') == false,
  'item use with the locked car behind the player: false (house / store robbery scripts get it)')
headings[1001] = 270.0
local bystander, bystanderNet = spawnPed(vec3(2, 0, 0))
seatIn(bystander, car)
check(run(CarLock.useAccessTool, 1, 'lockpick', lpSlot, {}, 'lockpick') == false, 'item use: a car with a living driver is not picked')
entities[bystander].health = 0
check(run(CarLock.useAccessTool, 1, 'lockpick', lpSlot, {}, 'lockpick') == true, 'item use: a dead driver does not protect the car')
seatIn(bystander, nil)
DeleteEntity(bystander)
local _ = bystanderNet
playerPos[1] = vec3(0, 3, 0)
check(run(CarLock.useAccessTool, 1, 'lockpick', lpSlot, {}, 'lockpick') == false,
  'item use: 2.5 m from the vehicle centre at most (3.6 m away: false)')
playerPos[1] = vec3(0, 0, 0)
playerPos[1] = vec3(30, 0, 0)
check(run(CarLock.useAccessTool, 1, 'lockpick', lpSlot, {}, 'lockpick') == false, 'nothing to pick in range: false (the owner script runs)')
playerPos[1] = vec3(0, 0, 0)
C.enabled = false
check(run(CarLock.useAccessTool, 1, 'lockpick', lpSlot, {}, 'lockpick') == false, 'car lock off: false')
local res = cb('nz:carlock:lockpick', 1, { step = 'start', netId = carNet, tool = 'lockpick' })
check(not res.ok, 'car lock off: callbacks refuse')
C.enabled = true

res = cb('nz:carlock:lockpick', 1, { step = 'start', netId = carNet, tool = 'lockpick', slot = lpSlot, street = 'Forum Dr', label = 'Sultan' })
check(res.ok and res.data.method == 'skillcheck' and #res.data.difficulty == 3 and res.data.difficulty[3] == 'medium',
  'lockpick start: the profile tool\'s skill checks')
local lpId = res.data.id
local res2 = cb('nz:carlock:lockpick', 1, { step = 'start', netId = carNet, tool = 'lockpick' })
check(not res2.ok and res2.error == 'You are already busy', 'one action at a time')
local fin = cb('nz:carlock:lockpick', 1, { step = 'finish', id = lpId, success = true })
check(fin.ok and fin.data.success == false and CarLock.isLocked(car) and logged('security.crimeTooFast') ~= nil,
  'success reported faster than the skill checks allow: refused and logged')
fin = cb('nz:carlock:lockpick', 1, { step = 'finish', id = lpId, success = true })
check(not fin.ok, 'a session finishes once')

-- ox_lib 3.33+: earliest pass = a third of a 2000 ms / speed turn (-10 %): easy 600, medium 400;
-- + the 800 ms turn to the door = 2400 ms for easy, easy, medium
res = cb('nz:carlock:lockpick', 1, { step = 'start', netId = carNet, tool = 'lockpick', slot = lpSlot })
check(run(CarLock.useAccessTool, 1, 'lockpick', lpSlot, {}, 'lockpick') == false
  and countClient('nz:client:carlock:crime', 1) == 2, 'item use while a crime action runs: false (not swallowed)')
advance(2300)
fin = cb('nz:carlock:lockpick', 1, { step = 'finish', id = res.data.id, success = true })
check(fin.ok and fin.data.success == false and CarLock.isLocked(car),
  'success before the earliest ox_lib pass of every check (+ the turn to the door): refused')
res = cb('nz:carlock:lockpick', 1, { step = 'start', netId = carNet, tool = 'lockpick', slot = lpSlot })
advance(2500)
fin = cb('nz:carlock:lockpick', 2, { step = 'finish', id = res.data.id, success = true })
check(not fin.ok, 'another player cannot finish my session')
fin = cb('nz:carlock:lockpick', 1, { step = 'finish', id = res.data.id, success = true })
check(fin.ok and fin.data.success == true and not CarLock.isLocked(car) and entities[car].lock == 1 and count(1, 'lockpick') == 2,
  'lockpick success: doors unlocked, tool kept')
check(not hasKey(1, 'NPC100'), 'lockpicking gives no key')
res = cb('nz:carlock:lockpick', 1, { step = 'start', netId = carNet, tool = 'lockpick' })
check(not res.ok and res.error == 'This vehicle is not locked', 'unlocked vehicle: nothing to pick')

-- communityox ox_lib 3.32.3 already turns the indicator with requestAnimationFrame (2000 ms a
-- turn); 3.32.2 and older use the 1 ms interval (1440 ms). Read again when ox_lib (re)starts.
CarLock.setLocked(car, true)
metadata['ox_lib:version'] = '3.32.3'
TriggerEvent('onResourceStart', 'ox_lib')
res = cb('nz:carlock:lockpick', 1, { step = 'start', netId = carNet, tool = 'lockpick', slot = lpSlot })
advance(2300)
fin = cb('nz:carlock:lockpick', 1, { step = 'finish', id = res.data.id, success = true })
check(fin.ok and fin.data.success == false and CarLock.isLocked(car),
  'ox_lib 3.32.3 (communityox): 2000 ms a turn, a pass after 2.3 s is refused')
metadata['ox_lib:version'] = '3.32.2'
TriggerEvent('onResourceStart', 'ox_lib')
res = cb('nz:carlock:lockpick', 1, { step = 'start', netId = carNet, tool = 'lockpick', slot = lpSlot })
advance(2300)
fin = cb('nz:carlock:lockpick', 1, { step = 'finish', id = res.data.id, success = true })
check(fin.ok and fin.data.success == true and not CarLock.isLocked(car),
  'ox_lib 3.32.2: the older 1440 ms turn, a pass after 2.3 s is accepted')
metadata['ox_lib:version'] = '3.42.1'
TriggerEvent('onResourceStart', 'ox_lib')

CarLock.setLocked(car, true)
chances(standard.accessTools[1], { breakChance = 100, alarmChance = 100, alertChance = 0 })
C.alarm.alertChance = 100
before = alertsTo(2)
res = cb('nz:carlock:lockpick', 1, { step = 'start', netId = carNet, tool = 'lockpick', slot = lpSlot })
advance(1500)
fin = cb('nz:carlock:lockpick', 1, { step = 'finish', id = res.data.id, success = false })
internal = lastClient('nz:client:dispatch:alert', 2)
check(fin.data.broke == true and fin.data.alarm == true and count(1, 'lockpick') == 1 and type(stateOf(car).nzAlarm) == 'table'
  and stateOf(car).nzAlarm.mode == 'native', 'failure: the tool breaks (that slot) and the native alarm sounds')
check(alertsTo(2) == before + 1 and internal.payload.kind == 'alarm' and internal.payload.code == '10-66',
  'alarm going off: car alarm alert (alarm.alertChance)')
chances(standard.accessTools[1], { breakChance = 0, alarmChance = 100, alertChance = 100 })
C.alarm.alertChance = 0
before = alertsTo(2)
res = cb('nz:carlock:lockpick', 1, { step = 'start', netId = carNet, tool = 'lockpick' })
advance(1500)
cb('nz:carlock:lockpick', 1, { step = 'finish', id = res.data.id, success = false })
check(alertsTo(2) == before, 'same player and vehicle within dispatch.cooldown: no second alert (one incident)')
advance(31000)
res = cb('nz:carlock:lockpick', 1, { step = 'start', netId = carNet, tool = 'lockpick' })
advance(1500)
cb('nz:carlock:lockpick', 1, { step = 'finish', id = res.data.id, success = false })
internal = lastClient('nz:client:dispatch:alert', 2)
check(alertsTo(2) == before + 1 and internal.payload.kind == 'lockpick' and internal.payload.priority == 2,
  'after the cooldown: a new break-in alert, reported as the break-in although the alarm sounded too')
chances(standard.accessTools[1], { alarmChance = 0, alertChance = 0 })

res = cb('nz:carlock:lockpick', 1, { step = 'start', netId = carNet, tool = 'hackingDevice' })
check(not res.ok and res.error == 'This tool does not work on this vehicle', 'a tool the profile does not list')
res = cb('nz:carlock:lockpick', 1, { step = 'start', netId = carNet, tool = 'screwdriver' })
check(not res.ok and res.error == 'You do not have the right tool', 'a listed tool the player does not carry')

-- pin lock (lockpicking.style = 'pins'): only for clients that say they can show it
CarLock.setLocked(car, true)
C.lockpicking = C.lockpicking or {}
local styleWas = C.lockpicking.style
C.lockpicking.style = 'pins'
res = cb('nz:carlock:lockpick', 1, { step = 'start', netId = carNet, tool = 'lockpick', slot = lpSlot })
check(res.ok and res.data.method == 'skillcheck' and res.data.puzzle == nil,
  'pins set, the client cannot show the pin lock: skill checks instead (no attempt that can never succeed)')
advance(3000)
cb('nz:carlock:lockpick', 1, { step = 'finish', id = res.data.id, success = false })
res = cb('nz:carlock:lockpick', 1, { step = 'start', netId = carNet, tool = 'lockpick', slot = lpSlot, minigames = { pins = true } })
check(res.ok and res.data.method == 'pins' and type(res.data.puzzle) == 'table', 'pins set and the client can play it: the pin lock')
advance(6000)
fin = cb('nz:carlock:lockpick', 1, { step = 'finish', id = res.data.id, success = true, answer = res.data.puzzle and res.data.puzzle.order })
check(fin.ok and fin.data.success == true and not CarLock.isLocked(car), 'pin lock solved in time: unlocked')
C.lockpicking.style = styleWas
CarLock.setLocked(car, true)
res = cb('nz:carlock:lockpick', 1, { step = 'start', netId = carNet })
check(res.ok and res.data.item == 'lockpick', 'target option (no tool): the first profile tool the player carries')
advance(200000)
fin = cb('nz:carlock:lockpick', 1, { step = 'finish', id = res.data.id, success = true })
check(fin.ok and fin.data.success == false and CarLock.isLocked(car), 'a late finish counts as a failure')
towingSet[car] = true
res = cb('nz:carlock:lockpick', 1, { step = 'start', netId = carNet, tool = 'lockpick' })
check(not res.ok and res.error == 'This vehicle is being towed', 'vehicles being towed are skipped')
check(run(CarLock.useAccessTool, 1, 'lockpick', nil, {}, 'lockpick') == false, 'item use ignores a vehicle being towed')
towingSet[car] = nil
playerPos[1] = vec3(-5, 0, 0)
res = cb('nz:carlock:lockpick', 1, { step = 'start', netId = carNet, tool = 'lockpick' })
check(not res.ok and res.error == 'You are too far from the vehicle', 'distance from the server ped')
playerPos[1] = vec3(0, 0, 0)

local super, superNet = spawnVehicle('FAST01', 'zentorno', vec3(-2, 0, 0))
res = cb('nz:carlock:lockpick', 1, { step = 'start', netId = superNet, tool = 'lockpick' })
check(not res.ok and res.error == 'This tool does not work on this vehicle', 'high-end profile: a plain lockpick does not open it')
playerPos[1] = vec3(-3, 0, 0)
check(run(CarLock.useAccessTool, 1, 'lockpick', nil, {}, 'lockpick') == false, 'item use: the nearest vehicle that takes the tool, else false')
playerPos[1] = vec3(0, 0, 0)

-- buses / coaches / trucks: the doors are far from the centre (service class: 7 m reach)
local coach, coachNet = spawnVehicle('NPC150', 'coach', vec3(5.5, 0, 0))
local far, farNet = spawnVehicle('NPC151', 'sultan', vec3(0, -5.5, 0))
res = cb('nz:carlock:lockpick', 1, { step = 'start', netId = coachNet, tool = 'lockpick' })
check(res.ok, 'coach: picked 5.5 m from its centre')
advance(2500)
fin = cb('nz:carlock:lockpick', 1, { step = 'finish', id = res.data.id, success = true })
check(fin.data.success == true and not CarLock.isLocked(coach), 'coach: the lock gives way at the door')
res = cb('nz:carlock:lockpick', 1, { step = 'start', netId = farNet, tool = 'lockpick' })
check(not res.ok and res.error == 'You are too far from the vehicle', 'a car 5.5 m away: too far')
CarLock.setLocked(coach, true)
playerPos[1] = vec3(-1, 0, 0)
check(run(CarLock.useAccessTool, 1, 'lockpick', nil, {}, 'lockpick') == true
  and lastClient('nz:client:carlock:crime', 1).payload.netId == coachNet, 'item use reaches a coach in front of the player')
playerPos[1] = vec3(0, 0, 0)
DeleteEntity(coach)
DeleteEntity(far)

-- taxis are service class (17) but car-sized: the normal reach and facing rules
playerPos[1] = vec3(0, 20, 0)
local a70 = math.rad(70)
local cab17, cab17Net = spawnVehicle('NPC152', 'taxi', vec3(5.5 * math.cos(a70), 20 + 5.5 * math.sin(a70), 0))
check(CarLock.classOf(cab17) == 17, 'taxi: service class')
check(run(CarLock.useAccessTool, 1, 'lockpick', nil, {}, 'lockpick') == false,
  'item use: a taxi 5.5 m away at 70 degrees stays with the owner script')
res = cb('nz:carlock:lockpick', 1, { step = 'start', netId = cab17Net, tool = 'lockpick' })
check(not res.ok and res.error == 'You are too far from the vehicle', 'taxi: no 7 m reach (car-sized)')
DeleteEntity(cab17)
playerPos[1] = vec3(0, 0, 0)

---------------------------------------------------------------------------------------
-- 3. Hotwire
---------------------------------------------------------------------------------------

seatIn(1001, car)
res = cb('nz:carlock:hotwire', 1, { step = 'start', netId = carNet })
check(res.ok and res.data.method == 'skillcheck' and #res.data.difficulty == 3, 'hotwire start: skill checks of the profile')
advance(1500)
fin = cb('nz:carlock:hotwire', 1, { step = 'finish', id = res.data.id, success = false })
check(fin.ok and fin.data.success == false and not hasKey(1, 'NPC100'), 'hotwire failure: no key')
-- hotwiring.style = 'wires': only for clients that can show the wires
C.hotwiring = C.hotwiring or {}
local hwStyle = C.hotwiring.style
C.hotwiring.style = 'wires'
res = cb('nz:carlock:hotwire', 1, { step = 'start', netId = carNet })
check(res.ok and res.data.method == 'skillcheck' and res.data.puzzle == nil, 'wires set, the client cannot show them: the profile method')
advance(1500)
cb('nz:carlock:hotwire', 1, { step = 'finish', id = res.data.id, success = false })
res = cb('nz:carlock:hotwire', 1, { step = 'start', netId = carNet, minigames = { wires = true, reader = true } })
check(res.ok and res.data.method == 'wires' and type(res.data.puzzle) == 'table' and #res.data.puzzle.left == 3,
  'wires set and the client can play them: the wires puzzle')
advance(1500)
cb('nz:carlock:hotwire', 1, { step = 'finish', id = res.data.id, success = false })
C.hotwiring.style = hwStyle
res = cb('nz:carlock:hotwire', 1, { step = 'start', netId = carNet })
advance(1500)
fin = cb('nz:carlock:hotwire', 1, { step = 'finish', id = res.data.id, success = true })
local has, kind = hasKey(1, 'NPC100')
check(fin.data.success == true and has and kind == 'temp', 'hotwire success: temporary key')
check(countClient('nz:client:carlock:keys', 1) > 0, 'the key change is pushed to the player')
res = cb('nz:carlock:hotwire', 1, { step = 'start', netId = carNet })
check(not res.ok and res.error == 'You already have the keys of this vehicle', 'no hotwire with a key')
CarLock.revokeTemp(1, 'NPC100')

standard.hotwire.method = 'progress'
res = cb('nz:carlock:hotwire', 1, { step = 'start', netId = carNet })
check(res.ok and res.data.method == 'progress' and res.data.duration == 6000, 'progress method: duration from the profile')
advance(3000)
fin = cb('nz:carlock:hotwire', 1, { step = 'finish', id = res.data.id, success = true })
check(fin.data.success == false, 'progress method: finishing half way is refused')
res = cb('nz:carlock:hotwire', 1, { step = 'start', netId = carNet })
advance(6000)
fin = cb('nz:carlock:hotwire', 1, { step = 'finish', id = res.data.id, success = true })
check(fin.data.success == true and hasKey(1, 'NPC100'), 'progress method: full duration gives the key')
standard.hotwire.method = 'skillcheck'
CarLock.revokeTemp(1, 'NPC100')
seatIn(1001, nil)
res = cb('nz:carlock:hotwire', 1, { step = 'start', netId = carNet })
check(not res.ok and res.error == 'You are not in the driver seat', 'hotwire needs the driver seat')

seatIn(1001, super)
res = cb('nz:carlock:hotwire', 1, { step = 'start', netId = superNet })
check(not res.ok and res.error == 'You need a hacking device to start this vehicle', 'hack method needs its item')
check(run(CarLock.useAccessTool, 1, 'hacking_device', nil, {}, 'hackingDevice') == true
  and lastClient('nz:client:carlock:crime', 1).payload.action == 'hotwire', 'hacking device used in the driver seat: hotwire flow')
give(1, 'hacking_device', 1)
res = cb('nz:carlock:hotwire', 1, { step = 'start', netId = superNet })
check(res.ok and res.data.method == 'hack' and #res.data.difficulty == 4 and res.data.inputs[1] == 'w', 'hack method: harder checks and keys')
highend.hotwire.breakChance = 100
advance(2000)
fin = cb('nz:carlock:hotwire', 1, { step = 'finish', id = res.data.id, success = false })
check(fin.data.broke == true and count(1, 'hacking_device') == 0, 'hack failure: the device breaks (breakChance)')
highend.hotwire.breakChance = 0
seatIn(1001, nil)

---------------------------------------------------------------------------------------
-- 4. Search
---------------------------------------------------------------------------------------

local van, vanNet = spawnVehicle('NPC200', 'sultan', vec3(3, 3, 0), { lock = 1 })
seatIn(1001, van)
chances(C.search.money, { chance = 100, min = 50, max = 50 })
C.search.items = { { item = 'water', chance = 100, min = 2, max = 2 }, { item = 'phone', chance = 0, min = 1, max = 1 } }
C.search.spareKeyChance = 100
res = cb('nz:carlock:search', 1, { step = 'start', netId = vanNet })
check(res.ok and res.data.duration == 7000, 'search start: progress duration')
res2 = cb('nz:carlock:search', 1, { step = 'finish', id = res.data.id, success = false })
check(res2.ok and res2.data.success == false and stateOf(van).nzSearched == nil, 'cancelled search: the vehicle can be searched again')
res = cb('nz:carlock:search', 1, { step = 'start', netId = vanNet })
advance(7000)
fin = cb('nz:carlock:search', 1, { step = 'finish', id = res.data.id, success = true })
local spare, spareOrigin = false, nil
for _, item in pairs(inv[1]) do
  if item.name == 'vehicle_key' and item.metadata.plate == 'NPC200' then spare, spareOrigin = true, item.metadata.origin end
end
check(fin.data.success and #fin.data.found == 3 and money[#money].amount == 50 and money[#money].account == 'cash'
  and count(1, 'water') == 2 and spare and hasKey(1, 'NPC200'), 'search loot: money, items and a spare key item (physical mode)')
check(spareOrigin == 'search', 'a found spare key item is a crime key (metadata.origin = search: no tracker, no nickname)')
check(stateOf(van).nzSearched == true, 'searched vehicles are marked for the hint')
CarLock.revokeTemp(1, 'NPC200')
for slot, item in pairs(inv[1]) do if item.name == 'vehicle_key' then inv[1][slot] = nil end end
res = cb('nz:carlock:search', 1, { step = 'start', netId = vanNet })
check(not res.ok and res.error == 'This vehicle was already searched', 'search once per vehicle')
local owned, ownedNet = spawnVehicle('OWN111', 'sultan', vec3(3, 3, 0), { lock = 1 })
seatIn(1001, owned)
res = cb('nz:carlock:search', 1, { step = 'start', netId = ownedNet })
check(not res.ok and res.error == 'You cannot search this vehicle', 'players\' vehicles are not searched (search.ownedVehicles)')

-- no farming: script- / player-spawned cars (mission population) and job cars are not searched
local spawned, spawnedNet = spawnVehicle('SPWN01', 'sultan', vec3(3, 3, 0), { lock = 1, pop = 7 })
seatIn(1001, spawned)
res = cb('nz:carlock:search', 1, { step = 'start', netId = spawnedNet })
check(not res.ok and res.error == 'You cannot search this vehicle', 'script- / player-spawned vehicles are not searched (search.ambientOnly)')
local jobCar, jobCarNet = spawnVehicle('JOB001', 'sultan', vec3(0, 1, 0), { lock = 1 })
NZ.Vehicles.out.JOB001 = { job = 'police' }
seatIn(1002, jobCar)
res = cb('nz:carlock:search', 2, { step = 'start', netId = jobCarNet })
check(not res.ok and res.error == 'You cannot search this vehicle', 'a vehicle of the player\'s own job (on duty) is not searched')
seatIn(1002, nil)
NZ.Vehicles.out.JOB001 = nil
DeleteEntity(jobCar)
DeleteEntity(spawned)

-- one successful search per player every search.cooldown seconds
local second, secondNet = spawnVehicle('NPC201', 'sultan', vec3(3, 3, 0), { lock = 1, pop = 5 })
seatIn(1001, second)
res = cb('nz:carlock:search', 1, { step = 'start', netId = secondNet })
check(not res.ok and res.error == 'Wait a moment before searching another vehicle', 'search.cooldown between successful searches')
advance(30000)
res = cb('nz:carlock:search', 1, { step = 'start', netId = secondNet })
check(res.ok, 'after search.cooldown: the next vehicle can be searched')

-- a search that is never finished (client error / timeout) does not block the vehicle for good
seatIn(1003, second)
res2 = cb('nz:carlock:search', 3, { step = 'start', netId = secondNet })
check(not res2.ok and res2.error == 'Someone is already searching this vehicle', 'a running search holds the vehicle')
advance(7000 + 15000 + 100)
res2 = cb('nz:carlock:search', 3, { step = 'start', netId = secondNet })
check(res2.ok, 'the search session ran out: the vehicle is free again')
fin = cb('nz:carlock:search', 1, { step = 'finish', id = res.data.id, success = true })
check(fin.ok and fin.data.success == false and stateOf(second).nzSearched == nil,
  'the expired search finishing late: no loot, and the new searcher keeps the vehicle')
seatIn(1001, nil)
res = cb('nz:carlock:search', 1, { step = 'start', netId = secondNet })
check(not res.ok, 'the late searcher is out of the seat')
cb('nz:carlock:search', 3, { step = 'finish', id = res2.data.id, success = false })
seatIn(1003, nil)
seatIn(1001, nil)

---------------------------------------------------------------------------------------
-- 5. NPC robbery
---------------------------------------------------------------------------------------

local taxi, taxiNet = spawnVehicle('NPC300', 'sultan', vec3(4, 0, 0), { lock = 1, pop = 5 })
local driver, driverNet = spawnPed(vec3(4, 0, 0), { owner = 3 })
seatIn(driver, taxi)
res = cb('nz:carlock:npcRob', 1, { step = 'start', netId = taxiNet, pedNetId = driverNet })
check(not res.ok and res.error == 'You need a weapon', 'robbery needs a weapon (server view)')
weaponOf[1001] = PISTOL
res = cb('nz:carlock:npcRob', 1, { step = 'start', netId = taxiNet, pedNetId = driverNet })
local step = lastClient('nz:client:carlock:npc')
check(res.ok and res.data.outcome == 'comply' and res.data.duration == 3500, 'comply: hold-up of npc.robTime')
check(step and step.target == 3 and step.payload.step == 'holdup' and step.payload.ped == driverNet and step.payload.robber == 1,
  'the hold-up step goes to the client that owns the ped')
advance(1000)
fin = cb('nz:carlock:npcRob', 1, { step = 'finish', id = res.data.id, success = true })
step = lastClient('nz:client:carlock:npc')
check(fin.data.success == false and step.payload.step == 'flee' and not hasKey(1, 'NPC300'), 'hold-up cut short: no key, the driver drives off')
res = cb('nz:carlock:npcRob', 1, { step = 'start', netId = taxiNet, pedNetId = driverNet })
advance(3500)
fin = cb('nz:carlock:npcRob', 1, { step = 'finish', id = res.data.id, success = true })
step = lastClient('nz:client:carlock:npc')
has, kind = hasKey(1, 'NPC300')
check(fin.data.success and has and kind == 'temp' and step.payload.step == 'release' and not CarLock.isLocked(taxi),
  'comply: temporary key, unlocked, the driver gets out and flees')
CarLock.revokeTemp(1, 'NPC300')

C.npc.reactions = { handover = 0, drop = 0, fight = 0, flee = 100 }
res = cb('nz:carlock:npcRob', 1, { step = 'start', netId = taxiNet, pedNetId = driverNet })
step = lastClient('nz:client:carlock:npc')
check(res.ok and res.data.outcome == 'flee' and res.data.id == nil and step.payload.step == 'flee' and not hasKey(1, 'NPC300'),
  'resist + flee: no key, drives off')
C.npc.reactions = { handover = 0, drop = 0, fight = 100, flee = 0 }
res = cb('nz:carlock:npcRob', 1, { step = 'start', netId = taxiNet, pedNetId = driverNet })
step = lastClient('nz:client:carlock:npc')
check(res.data.outcome == 'fight' and step.payload.step == 'fight' and step.payload.weapon == 'WEAPON_PISTOL', 'resist + fight: armed driver')

-- drop and run: the key lands on the ground next to the vehicle, whoever picks it up gets a temporary key
C.npc.reactions = { handover = 0, drop = 100, fight = 0, flee = 0 }
CarLock.setLocked(taxi, true)
res = cb('nz:carlock:npcRob', 1, { step = 'start', netId = taxiNet, pedNetId = driverNet })
step = lastClient('nz:client:carlock:npc')
check(res.ok and res.data.outcome == 'drop' and res.data.id == nil and step.payload.step == 'drop' and not CarLock.isLocked(taxi),
  'drop and run: no session, the driver gets out (step drop), the doors are unlocked')
advance(3000)
local dropped = CarLock.groundKeys('NPC300')
check(#dropped == 1 and dropped[1].kind == 'temp' and not hasKey(1, 'NPC300'), 'drop and run: a temporary-key ground key, nobody has the key yet')
if dropped[1] then
  res = cb('nz:carlock:ground:pickup', 1, { id = dropped[1].id })
  has, kind = hasKey(1, 'NPC300')
  check(res.ok and has and kind == 'temp' and #CarLock.groundKeys('NPC300') == 0, 'picking the dropped key up gives a temporary key')
  CarLock.revokeTemp(1, 'NPC300')
end

-- police requirement
C.npc.reactions = { handover = 100, drop = 0, fight = 0, flee = 0 }
C.npc.policeRequired = 50
res = cb('nz:carlock:npcRob', 1, { step = 'start', netId = taxiNet, pedNetId = driverNet })
check(not res.ok and res.error == 'There are not enough police officers around', 'npc.policeRequired: not enough officers on duty')
C.npc.policeRequired = 0

C.npc.cooldown = 60
res = cb('nz:carlock:npcRob', 1, { step = 'start', netId = taxiNet, pedNetId = driverNet })
cb('nz:carlock:npcRob', 1, { step = 'finish', id = res.data.id, success = false })
res = cb('nz:carlock:npcRob', 1, { step = 'start', netId = taxiNet, pedNetId = driverNet })
check(not res.ok and res.error == 'Wait a moment before robbing someone again', 'npc.cooldown between robberies')
advance(61000)
C.npc.cooldown = 0

entities[taxi].speed = 15.0
res = cb('nz:carlock:npcRob', 1, { step = 'start', netId = taxiNet, pedNetId = driverNet })
check(not res.ok and res.error == 'The vehicle is moving too fast', 'fast vehicles: no robbery')
entities[taxi].speed = 0.0
entities[driver].pop = 7
res = cb('nz:carlock:npcRob', 1, { step = 'start', netId = taxiNet, pedNetId = driverNet })
check(not res.ok, 'script / mission peds are left alone (npc.ambientOnly)')
entities[driver].pop = 5
seatIn(1003, taxi)
seatIn(driver, nil)
res = cb('nz:carlock:npcRob', 1, { step = 'start', netId = taxiNet, pedNetId = 1003 })
check(not res.ok and res.error == 'Invalid request', 'a player driver is never an NPC')
res = cb('nz:carlock:npcRob', 1, { step = 'start', netId = taxiNet, pedNetId = driverNet })
check(not res.ok and res.error == 'Nobody is driving this vehicle', 'the ped must drive that vehicle')
seatIn(1003, nil)
seatIn(driver, taxi)
playerPos[1] = vec3(20, 0, 0)
res = cb('nz:carlock:npcRob', 1, { step = 'start', netId = taxiNet, pedNetId = driverNet })
check(not res.ok and res.error == 'You are too far from the vehicle', 'robbery range from the server ped')
playerPos[1] = vec3(0, 0, 0)

local ownedCar, ownedCarNet = spawnVehicle('OWN111', 'sultan', vec3(4, 2, 0), { lock = 1 })
local ownedDriver, ownedDriverNet = spawnPed(vec3(4, 2, 0))
seatIn(ownedDriver, ownedCar)
res = cb('nz:carlock:npcRob', 1, { step = 'start', netId = ownedCarNet, pedNetId = ownedDriverNet })
check(not res.ok and res.error == 'This driver will not give you the keys', 'players\' vehicles are not robbed (npc.ownedVehicles)')

-- a hold-up the robber never finishes (client error, timeout): the server releases the driver
local stepsBefore = countClient('nz:client:carlock:npc')
res = cb('nz:carlock:npcRob', 1, { step = 'start', netId = taxiNet, pedNetId = driverNet })
check(res.ok and res.data.outcome == 'comply', 'hold-up started')
res2 = cb('nz:carlock:npcRob', 2, { step = 'start', netId = taxiNet, pedNetId = driverNet })
check(not res2.ok and res2.error == 'Someone else is dealing with this driver', 'a held-up driver is busy for others')
advance(3500 + 15000 + 300)
step = lastClient('nz:client:carlock:npc')
check(countClient('nz:client:carlock:npc') == stepsBefore + 2 and step.payload.step == 'flee' and step.target == 3,
  'never finished: when the session runs out the driver is released (flees)')
res2 = cb('nz:carlock:npcRob', 2, { step = 'start', netId = taxiNet, pedNetId = driverNet })
check(not res2.ok and res2.error == 'You need a weapon', 'the released driver is free again')
fin = cb('nz:carlock:npcRob', 1, { step = 'finish', id = res.data.id, success = true })
check(not fin.ok and not hasKey(1, 'NPC300'), 'the released hold-up cannot be finished any more')

-- the driver is shot during the hold-up: no key from the hold-up, but the body has it
res = cb('nz:carlock:npcRob', 1, { step = 'start', netId = taxiNet, pedNetId = driverNet })
advance(3500)
entities[driver].health = 0
fin = cb('nz:carlock:npcRob', 1, { step = 'finish', id = res.data.id, success = true })
check(fin.data.success == false and not hasKey(1, 'NPC300'), 'driver killed during the hold-up: no key from the hold-up')

---------------------------------------------------------------------------------------
-- 6. Dead driver
---------------------------------------------------------------------------------------

seatIn(driver, nil)
entities[driver].coords = vec3(6, 0, 0)
playerPos[1] = vec3(5, 0, 0)
res = cb('nz:carlock:deadDriver', 1, { step = 'start', netId = taxiNet, pedNetId = driverNet })
check(res.ok and res.data.duration == 4500, 'body of the recorded original driver: search starts')
advance(4500)
fin = cb('nz:carlock:deadDriver', 1, { step = 'finish', id = res.data.id, success = true })
check(fin.data.success and hasKey(1, 'NPC300'), 'body search: temporary key')
CarLock.revokeTemp(1, 'NPC300')
res = cb('nz:carlock:deadDriver', 1, { step = 'start', netId = taxiNet, pedNetId = driverNet })
check(not res.ok and res.error == 'This body was already searched', 'a body is searched once')

local bus, busNet = spawnVehicle('NPC400', 'sultan', vec3(6, 3, 0), { lock = 1, pop = 5 }) -- traffic
local busDriver, busDriverNet = spawnPed(vec3(6, 3, 0), { health = 0 })
seatIn(busDriver, bus)
res = cb('nz:carlock:deadDriver', 1, { step = 'start', netId = busNet, pedNetId = busDriverNet })
check(res.ok, 'dead driver still in the seat: allowed')
cb('nz:carlock:deadDriver', 1, { step = 'finish', id = res.data.id, success = false })
seatIn(busDriver, nil)
res = cb('nz:carlock:deadDriver', 1, { step = 'start', netId = busNet, pedNetId = busDriverNet })
check(res.ok, 'dead driver who fell out: the vehicle\'s last driver (server)')
cb('nz:carlock:deadDriver', 1, { step = 'finish', id = res.data.id, success = false })
local stranger, strangerNet = spawnPed(vec3(5, 1, 0), { health = 0 })
res = cb('nz:carlock:deadDriver', 1, { step = 'start', netId = busNet, pedNetId = strangerNet })
check(not res.ok and res.error == 'This person did not drive that vehicle', 'an unrelated body has no key')
entities[stranger].health = 200
res = cb('nz:carlock:deadDriver', 1, { step = 'start', netId = busNet, pedNetId = strangerNet })
check(not res.ok and res.error == 'This person is not dead', 'the living are not searched')

-- a dead mission / script ped at the wheel (another script's driver, or a ped a modified client
-- spawned into the seat of a locked car): no key
local mission, missionNet = spawnPed(vec3(6, 3, 0), { health = 0, pop = 7 })
seatIn(mission, bus)
res = cb('nz:carlock:deadDriver', 1, { step = 'start', netId = busNet, pedNetId = missionNet })
check(not res.ok and res.error == 'There is no key on this body', 'a dead mission ped at the wheel has no key (npc.ambientOnly)')
seatIn(mission, nil)
-- an ambient pedestrian warped into the seat of a random parked car (population 2) or a script
-- vehicle (7) and killed there: no key. Traffic vehicles (1/3/4/5, the bus above) keep it.
for _, pop in ipairs({ 2, 7 }) do
  local parked, parkedNet = spawnVehicle(('PARK0%d'):format(pop), 'sultan', vec3(6, 2, 0), { lock = 1, pop = pop })
  local victim, victimNet = spawnPed(vec3(6, 2, 0), { health = 0 })
  seatIn(victim, parked)
  res = cb('nz:carlock:deadDriver', 1, { step = 'start', netId = parkedNet, pedNetId = victimNet })
  check(not res.ok and res.error == 'There is no key on this body',
    ('an unrecorded dead driver in a population %d vehicle has no key'):format(pop))
  seatIn(victim, nil)
  DeleteEntity(parked)
end
-- the vehicle's last driver counts only near the vehicle
local van2, van2Net = spawnVehicle('NPC401', 'sultan', vec3(55, 3, 0), { lock = 1, pop = 5 })
local walker, walkerNet = spawnPed(vec3(6, 3, 0), { health = 0 })
seatIn(walker, van2)
seatIn(walker, nil)
res = cb('nz:carlock:deadDriver', 1, { step = 'start', netId = van2Net, pedNetId = walkerNet })
check(not res.ok and res.error == 'This person did not drive that vehicle', 'a last driver 50 m from the vehicle has no key')
entities[van2].coords = vec3(8, 3, 0)
res = cb('nz:carlock:deadDriver', 1, { step = 'start', netId = van2Net, pedNetId = walkerNet })
check(res.ok, 'the same last driver next to the vehicle: allowed')
cb('nz:carlock:deadDriver', 1, { step = 'finish', id = res.data.id, success = false })
playerPos[1] = vec3(0, 0, 0)

---------------------------------------------------------------------------------------
-- 7. Assistance (authorized jobs)
---------------------------------------------------------------------------------------

local cab, cabNet = spawnVehicle('NPC500', 'sultan', vec3(1, 2, 0), { lock = 1 })
local cabDriver, cabDriverNet = spawnPed(vec3(1, 2, 0))
seatIn(cabDriver, cab)
res = cb('nz:carlock:npcAssist', 1, { step = 'start', netId = cabNet, pedNetId = cabDriverNet })
check(not res.ok and res.error == 'You are not allowed to do that', 'no assist job: refused')
playerPos[4] = vec3(0, 2, 0)
res = cb('nz:carlock:npcAssist', 4, { step = 'start', netId = cabNet, pedNetId = cabDriverNet })
check(not res.ok, 'assist job off duty: refused')
local alertsBefore = alertsTo(2) + countClient('nz:client:dispatch')
res = cb('nz:carlock:npcAssist', 2, { step = 'start', netId = cabNet, pedNetId = cabDriverNet })
step = lastClient('nz:client:carlock:npc')
check(res.ok and step.payload.step == 'pullover' and step.payload.robber == 2, 'assist: the driver pulls over')
advance(4000)
fin = cb('nz:carlock:npcAssist', 2, { step = 'finish', id = res.data.id, success = true })
step = lastClient('nz:client:carlock:npc')
has, kind = hasKey(2, 'NPC500')
check(fin.data.success and has and kind == 'temp' and step.payload.step == 'handover', 'assist: temporary key, handover')
check(alertsTo(2) + countClient('nz:client:dispatch') == alertsBefore, 'assist: no police alert')
res = cb('nz:carlock:npcAssist', 2, { step = 'start', netId = cabNet, pedNetId = cabDriverNet })
check(not res.ok, 'assist: cooldown / key already held')
local cab2, cab2Net = spawnVehicle('NPC501', 'sultan', vec3(1, 3, 0), { lock = 1 })
local cab2Driver, cab2DriverNet = spawnPed(vec3(1, 3, 0))
seatIn(cab2Driver, cab2)
advance(10000)
res = cb('nz:carlock:npcAssist', 2, { step = 'start', netId = cab2Net, pedNetId = cab2DriverNet })
advance(4000 + 15000 + 300)
step = lastClient('nz:client:carlock:npc')
check(res.ok and step.payload.step == 'resume' and step.payload.ped == cab2DriverNet and not hasKey(2, 'NPC501'),
  'assist never finished: the driver drives on when the session runs out')

---------------------------------------------------------------------------------------
-- 8. Alert contents: visible (fake) plate, model, colour, position
---------------------------------------------------------------------------------------

local fake, fakeNet = spawnVehicle('FAKE99', 'sultan', vec3(2, -2, 0), { colour = 28 })
CarLock.setRealPlate(fake, 'REAL01')
chances(standard.accessTools[1], { alertChance = 100 })
res = cb('nz:carlock:lockpick', 1, { step = 'start', netId = fakeNet, tool = 'lockpick', street = 'Strawberry Ave', label = 'Ignored' })
advance(2500)
cb('nz:carlock:lockpick', 1, { step = 'finish', id = res.data.id, success = true })
internal = lastClient('nz:client:dispatch:alert', 2)
check(internal.payload.kind == 'lockpick' and internal.payload.plate == 'FAKE99' and internal.payload.model == 'Karin Sultan'
  and internal.payload.color == 'Red' and internal.payload.street == 'Strawberry Ave' and internal.payload.coords.y == -2,
  'alert: visible plate (fake plate), model label, colour, street, vehicle position')
check(internal.payload.modelHash == joaat_('sultan'), 'alert: model hash for clients')
check(internal.payload.streetFromClient == true and internal.payload.modelFromClient == nil,
  'alert: the street is marked as client text, the model label from the shared list is not')

-- display text from a modified client: no markup reaches police MDT / dispatch UIs
local marked, markedNet = spawnVehicle('MARK01', 'mysterymodel', vec3(2, 2, 0), { colour = 28 })
res = cb('nz:carlock:lockpick', 1, { step = 'start', netId = markedNet, tool = 'lockpick',
  street = '<img src=x onerror="alert(1)">Grove St', label = "Bob's <b>car</b> & `x`\\" })
advance(2500)
cb('nz:carlock:lockpick', 1, { step = 'finish', id = res.data.id, success = true })
internal = lastClient('nz:client:dispatch:alert', 2)
local street, model = internal.payload.street, internal.payload.model
check(internal.payload.plate == 'MARK01' and type(street) == 'string' and type(model) == 'string'
  and not street:find('[<>&"\'`\\]') and not model:find('[<>&"\'`\\]') and model:find('Bob\u{2019}s', 1, true) ~= nil
  and street:find('Grove St', 1, true) ~= nil and not internal.payload.message:find('[<>]'),
  'alert: markup stripped from the street and the model label a client sent (quotes made typographic)')
check(internal.payload.streetFromClient == true and internal.payload.modelFromClient == true,
  'alert: a model label only the client knew is marked as client text (officers look it up)')
CarLock.setLocked(marked, false)
DeleteEntity(marked)
local _ = markedNet
run(NZ.Dispatch.alert, nil, { kind = 'theft', coords = vec3(1, 1, 1), street = string.rep('a', 63) .. '\u{2019}x' })
street = lastClient('nz:client:dispatch:alert', 2).payload.street
check(#street == 63 and utf8.len(street) == 63, 'long text is cut at a whole UTF-8 character')
chances(standard.accessTools[1], { alertChance = 0 })

---------------------------------------------------------------------------------------
-- 9. Cleanup
---------------------------------------------------------------------------------------

res = cb('nz:carlock:lockpick', 1, { step = 'start', netId = fakeNet, tool = 'lockpick' })
check(not res.ok, 'unlocked: nothing to do')
CarLock.setLocked(fake, true)
res = cb('nz:carlock:lockpick', 1, { step = 'start', netId = fakeNet, tool = 'lockpick' })
for _, e in ipairs(handlers.playerDropped or {}) do
  source = 1 -- luacheck: ignore 111
  e.fn('quit')
end
res2 = cb('nz:carlock:lockpick', 1, { step = 'finish', id = res.data.id, success = true })
check(not res2.ok, 'dropped player: session gone')
DeleteEntity(taxi)
check(true, 'entity removal handled')

---------------------------------------------------------------------------------------
-- Report
---------------------------------------------------------------------------------------

for _, line in ipairs(printed.error) do failures[#failures + 1] = 'lib.print.error: ' .. line end
if #failures > 0 then
  for _, f in ipairs(failures) do print('FAIL ' .. f) end
  print(('%d of %d checks failed'):format(#failures, checks))
  os.exit(1)
end
print(('crime OK (%d checks)'):format(checks))
