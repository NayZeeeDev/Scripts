--[[
  Headless test of the client trailer path in client/vehicle.lua + client/damage.lua (no FiveM).

  A small client world (entities with models, dimensions, headings, network ids, owners,
  trailer hitches, bones, state bags) and checks:
    Veh.collect: the hitched trailer (net id, model, props with plate, damage) and a trailer
    without windows is not saved with "smashed" windows;
    client spawn: Veh.spawn creates the truck, the trailer right behind it (dimension-based
    offset, same heading), restores props / plate / damage and hitches it; an entity lockdown
    that refuses the networked trailer leaves no local-only copy;
    server spawn: the truck's 'nzInit' names a server-created trailer: the client claims that
    trailer's own 'nzInit' (plate, props, no 'nzPlate'), moves it onto the hitch and attaches
    it; no second trailer is created;
    Veh.delete with and without keeping the trailer.

  Usage (from the resource root):  lua5.4 tools/smoke/trailer_client.lua
]]

local failures, checks = {}, 0
local function check(cond, label)
  checks = checks + 1
  if not cond then failures[#failures + 1] = label end
  return cond
end

---------------------------------------------------------------------------------------
-- Clock & scheduler
---------------------------------------------------------------------------------------

local clock = 0
local threads = {}
function CreateThread(fn) threads[#threads + 1] = { co = coroutine.create(fn), wake = clock } end
function Wait(ms)
  if not coroutine.isyieldable() then error('Wait() outside a thread', 2) end
  coroutine.yield(ms or 0)
end
function SetTimeout(ms, fn) CreateThread(function() Wait(ms) fn() end) end
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
    if guard > 20000 then error('run(): never returned') end
  end
  return table.unpack(results, 1, results.n)
end
local function advance(ms)
  local target = clock + ms
  while clock < target do clock = clock + 50 runDue() end
end
function AddEventHandler() end
function RegisterNetEvent() end
function TriggerServerEvent() end

---------------------------------------------------------------------------------------
-- World
---------------------------------------------------------------------------------------

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
local function vec3(x, y, z) return { x = x + 0.0, y = y + 0.0, z = z + 0.0 } end
vector3 = vec3
function vector4(x, y, z, w) return { x = x, y = y, z = z, w = w } end

local PHANTOM, TRAILERS, TANKER = joaat_('phantom'), joaat_('trailers'), joaat_('tanker')
local MODELS = {
  [PHANTOM] = { name = 'PHANTOM', min = vec3(-1.3, -4.0, -1.0), max = vec3(1.3, 4.5, 2.5), class = 20, seats = 2, windows = true },
  [TRAILERS] = { name = 'TRAILERS', min = vec3(-1.3, -6.5, -1.0), max = vec3(1.3, 6.0, 3.0), class = 11, seats = 0 },
  [TANKER] = { name = 'TANKER', min = vec3(-1.3, -6.0, -1.0), max = vec3(1.3, 5.5, 3.0), class = 11, seats = 0 },
}

local E = {}          -- [handle] = entity
local nextHandle, nextNet = 100, 500
local lockdown = false
local created = {}
local warped = {}
local ME = 1

local function newEntity(hash, x, y, z, h, networked)
  nextHandle = nextHandle + 1
  local e = { model = hash, coords = vec3(x, y, z), heading = h or 0.0, plate = 'XXXXXXXX', networked = false,
    owner = ME, engine = 1000.0, body = 1000.0, tank = 1000.0, livery = -1, trailer = nil, hitch = nil, state = {} }
  if networked and not lockdown then
    nextNet = nextNet + 1
    e.networked, e.netId = true, nextNet
  end
  E[nextHandle] = e
  return nextHandle
end

local bagHandlers = {}
function AddStateBagChangeHandler(key, _, fn) bagHandlers[key] = bagHandlers[key] or {} table.insert(bagHandlers[key], fn) end
function GetEntityFromStateBagName(name) return tonumber(tostring(name):match('^entity:(%d+)$')) or 0 end
function Entity(h)
  local e = E[h]
  local st = e and e.state or {}
  return { state = setmetatable(st, { __index = { set = function(self, k, v)
    rawset(self, k, v)
    for _, fn in ipairs(bagHandlers[k] or {}) do fn('entity:' .. tostring(h), k, v) end
  end } }) }
end

function DoesEntityExist(h) return E[h] ~= nil end
function GetEntityModel(h) return E[h] and E[h].model or 0 end
function GetEntityCoords(h) local e = E[h] return e and vec3(e.coords.x, e.coords.y, e.coords.z) or vec3(0, 0, 0) end
function GetEntityHeading(h) return E[h] and E[h].heading or 0.0 end
function SetEntityHeading(h, v) if E[h] then E[h].heading = v end end
function SetEntityCoordsNoOffset(h, x, y, z) if E[h] then E[h].coords = vec3(x, y, z) end end
function GetOffsetFromEntityInWorldCoords(h, ox, oy, oz)
  local e = E[h]
  local r = math.rad(e.heading)
  local fx, fy = -math.sin(r), math.cos(r)
  local rx, ry = math.cos(r), math.sin(r)
  return vec3(e.coords.x + rx * ox + fx * oy, e.coords.y + ry * ox + fy * oy, e.coords.z + oz)
end
function GetModelDimensions(hash)
  local m = MODELS[hash]
  if not m then return vec3(-1, -2, -1), vec3(1, 2, 1) end
  return m.min, m.max
end
function CreateVehicle(hash, x, y, z, h, networked)
  local handle = newEntity(hash, x, y, z, h, networked)
  created[#created + 1] = { handle = handle, model = hash, networked = networked }
  return handle
end
function DeleteVehicle(h) E[h] = nil end
function DeleteEntity(h) E[h] = nil end
function SetEntityAsMissionEntity() end
function SetVehicleOnGroundProperly() return true end
function NetworkGetEntityIsNetworked(h) return E[h] ~= nil and E[h].networked end
function NetworkGetNetworkIdFromEntity(h) return E[h] and E[h].netId or 0 end
function NetworkDoesNetworkIdExist(id) for _, e in pairs(E) do if e.netId == id then return true end end return false end
function NetworkGetEntityFromNetworkId(id) for h, e in pairs(E) do if e.netId == id then return h end end return 0 end
function NetworkGetEntityOwner(h) return E[h] and E[h].owner or -1 end
function PlayerId() return ME end
function PlayerPedId() return 1 end
cache = { ped = 1 }
function NetworkHasControlOfEntity(h) return E[h] ~= nil and (not E[h].networked or E[h].owner == ME) end
function NetworkRequestControlOfEntity(h) if E[h] then E[h].owner = ME end end
function SetNetworkIdCanMigrate() end
function IsModelInCdimage() return true end
function IsModelAVehicle() return true end
function HasModelLoaded() return true end
function SetModelAsNoLongerNeeded() end
function RequestCollisionAtCoord() end
function HasCollisionLoadedAroundEntity() return true end
function FreezeEntityPosition(h, state) if E[h] then E[h].frozen = state == true end end
function SetVehicleNumberPlateText(h, t) if E[h] then E[h].plate = (tostring(t) .. '        '):sub(1, 8) end end
function GetVehicleNumberPlateText(h) return E[h] and E[h].plate or '' end
function GetVehicleTrailerVehicle(h)
  local e = E[h]
  if e and e.trailer and E[e.trailer] then return true, e.trailer end
  return false, 0
end
local attachCalls = 0
function AttachVehicleToTrailer(v, t)
  attachCalls = attachCalls + 1
  if not E[v] or not E[t] then return end
  if E[t].frozen then return end -- a frozen trailer does not move onto the hitch
  -- the hitch only catches when the trailer's front is close behind the truck's rear
  local rear = GetOffsetFromEntityInWorldCoords(v, 0.0, MODELS[E[v].model].min.y, 0.0)
  local front = GetOffsetFromEntityInWorldCoords(t, 0.0, MODELS[E[t].model].max.y, 0.0)
  local d = math.sqrt((rear.x - front.x) ^ 2 + (rear.y - front.y) ^ 2)
  if d <= 2.0 then E[v].trailer, E[t].hitch = t, v end
end
function IsVehicleAttachedToTrailer(v) return E[v] ~= nil and E[v].trailer ~= nil and E[E[v].trailer] ~= nil end
function DetachVehicleFromTrailer(v) if E[v] and E[v].trailer then local t = E[v].trailer E[v].trailer = nil if E[t] then E[t].hitch = nil end end end
function GetEntityBoneIndexByName(h, name)
  local e = E[h]
  if not e then return -1 end
  if name:find('^window') or name:find('^windscreen') then return MODELS[e.model].windows and 5 or -1 end
  return -1
end
function GetWorldPositionOfEntityBone(h) return GetEntityCoords(h) end
function IsVehicleWindowIntact(h) return E[h] ~= nil and MODELS[E[h].model].windows == true end
function RollUpWindow() end
function IsVehicleDoorDamaged() return false end
function IsVehicleTyreBurst() return false end
function GetVehicleDirtLevel() return 0.0 end
function GetVehicleDeformationAtPos() return vec3(0, 0, 0) end
function GetVehicleEngineHealth(h) return E[h] and E[h].engine or 0 end
function GetVehicleBodyHealth(h) return E[h] and E[h].body or 0 end
function GetVehiclePetrolTankHealth(h) return E[h] and E[h].tank or 0 end
function SetVehicleEngineHealth(h, v) if E[h] then E[h].engine = v end end
function SetVehicleBodyHealth(h, v) if E[h] then E[h].body = v end end
function SetVehiclePetrolTankHealth(h, v) if E[h] then E[h].tank = v end end
function GetVehicleFuelLevel() return 50.0 end
function GetDisplayNameFromVehicleModel(hash) return MODELS[hash] and MODELS[hash].name or 'CARNOTFOUND' end
function GetMakeNameFromVehicleModel() return '' end
function GetLabelText(t) return t end
function GetVehicleClassFromName(hash) return MODELS[hash] and MODELS[hash].class or 0 end
function GetVehicleModelNumberOfSeats(hash) return MODELS[hash] and MODELS[hash].seats or 4 end
function IsThisModelABoat() return false end
function IsThisModelAHeli() return false end
function IsThisModelAPlane() return false end
function IsThisModelABike() return false end
function IsThisModelABicycle() return false end
function IsThisModelATrain() return false end
function IsThisModelAJetski() return false end
function IsThisModelAQuadbike() return false end
function TaskWarpPedIntoVehicle(_, v) warped[#warped + 1] = v end
function GetVehiclePedIsIn() return 0 end
function GetPedInVehicleSeat() return 0 end
function IsDuplicityVersion() return false end
function GetCurrentResourceName() return 'nayzeee-garages' end
function GetResourceState() return 'missing' end

setmetatable(_G, { __index = function(_, k)
  if type(k) == 'string' and k:match('^%u') then return function() return nil end end
  return nil
end })

local printed = { warn = {}, error = {} }
lib = {
  print = {
    info = function() end, debug = function() end,
    warn = function(...) printed.warn[#printed.warn + 1] = table.concat({ ... }, ' ') end,
    error = function(...) printed.error[#printed.error + 1] = table.concat({ ... }, ' ') end,
  },
  getVehicleProperties = function(h)
    local e = E[h]
    return { model = e.model, plate = e.plate, livery = e.livery, fuelLevel = 50.0 }
  end,
  setVehicleProperties = function(h, props)
    local e = E[h]
    if props.livery then e.livery = props.livery end
    if props.plate then e.plate = (props.plate .. '        '):sub(1, 8) end
    return true
  end,
  requestModel = function() return true end,
  getClosestVehicle = function() return nil end,
}
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
load_('shared/init.lua')
load_('shared/utils.lua')
NZ.Framework = 'qb'
NZ.State.settings = {}
local keysGiven = {}
NZ.Keys.give = function(vehicle, plate) keysGiven[#keysGiven + 1] = plate end
NZ.Fuel.set = function() end
NZ.Fuel.get = function() return 50.0 end
NZ.NUI.notify = function() end
load_('client/damage.lua')
load_('client/vehicle.lua')
local Veh = NZ.Veh

local function dist2d(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

---------------------------------------------------------------------------------------
-- collect
---------------------------------------------------------------------------------------

local truck = newEntity(PHANTOM, 0, 0, 0, 0.0, true)
SetVehicleNumberPlateText(truck, 'TRUCK01')
local trailer = newEntity(TRAILERS, 0, -11.5, 0, 0.0, true)
SetVehicleNumberPlateText(trailer, 'TRL0001')
E[trailer].livery = 3
E[trailer].body = 700.0
AttachVehicleToTrailer(truck, trailer)
check(IsVehicleAttachedToTrailer(truck), 'setup: hitched')
local data = run(Veh.collect, truck)
check(type(data) == 'table' and type(data.trailer) == 'table', 'collect includes the trailer')
local t = data and data.trailer or {}
check(t.netId == E[trailer].netId and t.hash == TRAILERS and t.model == 'trailers', 'trailer net id, hash, model')
check(type(t.props) == 'table' and t.props.livery == 3 and NZ.Utils.trim(t.props.plate) == 'TRL0001', 'trailer props with plate')
check(type(t.damage) == 'table' and t.damage.body == 700.0, 'trailer damage')
local smashed = false
for _, v in pairs(t.damage and t.damage.windows or {}) do if v then smashed = true end end
check(not smashed, 'a trailer without windows has no smashed windows')
check(data.trailer and data.entityType == 'automobile' and Veh.entityTypeOf(TRAILERS) == 'trailer', 'entity types')
NZ.State.settings = { vehicles = { trailers = false } }
check(run(Veh.collect, truck).trailer == nil, 'trailers setting off: not collected')
NZ.State.settings = {}

---------------------------------------------------------------------------------------
-- client spawn
---------------------------------------------------------------------------------------

created = {}
local spawned = run(Veh.spawn, {
  hash = PHANTOM, model = 'phantom', coords = { x = 100.0, y = 50.0, z = 0.0, w = 90.0 }, plate = 'TRUCK01',
  props = { model = PHANTOM, plate = 'TRUCK01' }, fuel = 60, mileage = 12,
  trailer = { hash = TRAILERS, model = 'trailers', props = { model = TRAILERS, plate = 'TRL0001', livery = 3 },
    damage = { v = 1, engine = 1000.0, body = 650.0 } },
})
check(spawned and E[spawned] and E[spawned].plate == 'TRUCK01 ', 'truck spawned')
local tr = nil
for _, c in ipairs(created) do if c.model == TRAILERS then tr = c.handle end end
check(tr ~= nil and E[tr] and E[tr].networked, 'trailer created networked')
if tr and E[tr] then
  check(E[tr].plate == 'TRL0001 ' and E[tr].livery == 3 and E[tr].body == 650.0, 'trailer props, plate, damage restored')
  check(E[tr].heading == 90.0, 'trailer has the truck heading')
  -- heading 90: forward is -x; trailer centre = truck rear (-4.0) - trailer front (6.0) - gap 0.5 => 10.5 m behind
  check(math.abs(E[tr].coords.x - 110.5) < 0.01 and math.abs(E[tr].coords.y - 50.0) < 0.01, 'trailer right behind the truck')
  check(E[spawned].trailer == tr, 'trailer hitched')
  check(E[tr].state.nzPlate == nil, 'no nzPlate on a client-spawned trailer')
end
check(E[spawned].state.nzPlate == 'TRUCK01', 'truck nzPlate')

-- entity lockdown: the networked trailer is refused -> no local copy left behind
lockdown = false
created = {}
local truck2 = newEntity(PHANTOM, 200, 0, 0, 0.0, true)
lockdown = true
local before = 0
for _ in pairs(E) do before = before + 1 end
NZ.Veh.spawn = NZ.Veh.spawn -- (spawnTrailer is reached through applyVehicleData)
local lockTrailer = nil
run(function()
  -- reuse the claim path: apply data with a trailer to a vehicle we own
  E[truck2].state.nzInit = { plate = 'TRUCK02', trailer = { hash = TRAILERS, model = 'trailers', props = { plate = 'TRL0002' } } }
  return Veh.spawn({ netId = E[truck2].netId, plate = 'TRUCK02', warp = false })
end)
advance(3000)
for _, c in ipairs(created) do if c.model == TRAILERS then lockTrailer = c.handle end end
check(lockTrailer ~= nil and E[lockTrailer] == nil, 'refused trailer deleted, no local-only copy')
check(#printed.warn > 0 and printed.warn[#printed.warn]:find('networked', 1, true) ~= nil, 'lockdown warned')
lockdown = false

---------------------------------------------------------------------------------------
-- server spawn
---------------------------------------------------------------------------------------

created = {}
-- server-created trailer 20 m behind the spawn point, frozen, owned by another client at first
local sTrailer = newEntity(TRAILERS, 320, 0, 0, 90.0, true)
E[sTrailer].owner = 2
E[sTrailer].frozen = true
E[sTrailer].state.nzInit = { plate = 'TRL0001', props = { model = TRAILERS, plate = 'TRL0001', livery = 5 },
  damage = { v = 1, body = 640.0 }, isTrailer = true }
local sTruck = newEntity(PHANTOM, 300, 0, 0, 90.0, true)
E[sTruck].state.nzInit = { plate = 'TRUCK01', props = { model = PHANTOM, plate = 'TRUCK01' }, fuel = 70,
  trailer = { netId = E[sTrailer].netId, hash = TRAILERS, model = 'trailers', props = { plate = 'TRL0001' } } }
local adopted = run(Veh.spawn, { netId = E[sTruck].netId, plate = 'TRUCK01', hash = PHANTOM, model = 'phantom',
  props = { model = PHANTOM, plate = 'TRUCK01' },
  trailer = { netId = E[sTrailer].netId, hash = TRAILERS, model = 'trailers', props = { plate = 'TRL0001' } } })
advance(2000)
check(adopted == sTruck, 'server truck adopted')
check(#created == 0, 'no second trailer created on the client')
check(E[sTrailer].owner == ME, 'control of the trailer taken')
check(E[sTrailer].plate == 'TRL0001 ' and E[sTrailer].livery == 5 and E[sTrailer].body == 640.0, 'trailer nzInit applied here')
check(E[sTrailer].state.nzInit == nil, 'trailer nzInit claimed (cleared)')
check(E[sTrailer].state.nzPlate == nil, 'no nzPlate written on the trailer')
check(E[sTruck].trailer == sTrailer, 'server trailer hitched to the truck')
check(E[sTrailer].frozen == false, 'server trailer unfrozen once moved')
check(dist2d(E[sTrailer].coords, vec3(310.5, 0, 0)) < 0.01, 'trailer moved onto the hitch')
check(E[sTruck].plate == 'TRUCK01 ' and E[sTruck].state.nzPlate == 'TRUCK01', 'truck data applied')

-- the server trailer never arrives: warning, nothing created
created = {}
local lonely = newEntity(PHANTOM, 400, 0, 0, 0.0, true)
E[lonely].state.nzInit = { plate = 'TRUCK03', trailer = { netId = 99999, hash = TRAILERS } }
local nWarn = #printed.warn
run(Veh.spawn, { netId = E[lonely].netId, plate = 'TRUCK03' })
advance(6000)
check(#created == 0 and #printed.warn > nWarn, 'missing server trailer: warned, no client copy')

---------------------------------------------------------------------------------------
-- delete
---------------------------------------------------------------------------------------

local keepT = E[sTruck].trailer
run(Veh.delete, sTruck, true)
check(E[sTruck] == nil and E[keepT] ~= nil and E[keepT].hitch == nil, 'delete(keepTrailer): trailer unhitched, kept')
local tr2 = E[spawned].trailer
run(Veh.delete, spawned)
check(E[spawned] == nil and E[tr2] == nil, 'delete: trailer deleted with the truck')

check(#printed.error == 0, 'no errors: ' .. table.concat(printed.error, ' | '))

if #failures > 0 then
  print(('trailer client: %d of %d checks failed'):format(#failures, checks))
  for _, f in ipairs(failures) do print('  - ' .. f) end
  os.exit(1)
end
print(('trailer client OK (%d checks)'):format(checks))
