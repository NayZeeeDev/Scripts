--[[
  Headless test of trailer storage (server side, no FiveM needed).

  Runs the real server/db.lua and server/vehicles.lua (QBCore schema, fake oxmysql and a small
  OneSync world from tools/smoke/vehfin_lib.lua) and stores / retrieves a truck with a
  trailer end to end:
    store with the trailer on the hitch (nz_trailer saved with model / props / damage, both
    entities deleted); retrieve (client spawn: the trailer travels with the vehicle data);
    the server not seeing the hitch (trailer right behind the truck still counts, one far away
    does not, one hitched to something else never); the truck's own saved trailer standing
    loose nearby; a trailer parked separately (kept, not spawned twice, comes back once it is
    gone, never taken by another truck, also after a restart); server-spawn mode (trailer
    created by the server behind the spawn point, its own 'nzInit', no 'nzPlate', the truck's
    'nzInit' names it; rollback deletes it); a registered trailer stored as its own vehicle
    (and refused for somebody else's); impound / recover removing the world copy; the
    trailers setting off.

  Usage (from the resource root):  lua5.4 tools/smoke/trailer.lua
]]

local H = dofile('tools/smoke/vehfin_lib.lua')
local check = H.check
H.setup('qb', { financeColumn = true })
H.load('server/vehicles.lua')
NZ.Ready = true
local Vehicles = NZ.Vehicles
local vec3 = H.vec3

NZ.DB.getOutVehicles = function() return {} end   -- (state SQL not emulated by the fake MySQL)

local loc = H.locations[1]
local TRAILER = H.joaat('trailers')

H.addRow({ plate = 'TRUCK01', model = 'phantom', state = 0 })
H.addRow({ plate = 'TRUCK02', model = 'packer', state = 0, owner = 'CID002' })
-- a vehicle in its garage whose saved trailer stands in the world (left there before a restart)
H.addRow({ plate = 'HAUL003', model = 'hauler', state = 1,
  extra = { nz_trailer = json.encode({ hash = H.joaat('tanker'), model = 'tanker', props = { plate = 'TNK0003', model = H.joaat('tanker') } }) } })
H.addRow({ plate = 'BOATTR1', model = 'boattrailer', state = 0 })
H.addRow({ plate = 'BOATTR2', model = 'boattrailer', state = 0, owner = 'CID002' })

---------------------------------------------------------------------------------------
H.scenario = 'boot'
Vehicles.boot()
-- the tanker of HAUL003 is in the world: tracked, nobody else can take it
local tanker = H.spawn('TNK0003', 'tanker', { vtype = 'trailer', coords = vec3(14, 0, 0) })

local function truckWithTrailer(plate, model, trailerPlate, opts)
  opts = opts or {}
  local truck = H.spawn(plate, model, { coords = opts.truckAt or vec3(12, 0, 0) })
  local trailer = nil
  if trailerPlate then
    trailer = H.spawn(trailerPlate, opts.trailerModel or 'trailers', { vtype = 'trailer', coords = opts.trailerAt or vec3(12, -9, 0) })
    if opts.hitched ~= false then H.entities[trailer].attachedTo = truck end
  end
  return truck, trailer
end

local function collected(truck, trailer, extra)
  local t = H.entities[truck]
  local data = {
    netId = t.netId, plate = t.plate, hash = t.model, model = 'phantom',
    props = { model = t.model, plate = t.plate, color1 = 12 },
    damage = { v = 1, engine = 900.0, body = 950.0, doors = {}, windows = {}, tyres = {} },
    fuel = 60, engine = 90, body = 95, mileage = 10, entityType = 'automobile',
  }
  if trailer then
    local e = H.entities[trailer]
    data.trailer = {
      netId = e.netId, hash = e.model, model = 'trailers',
      props = { model = e.model, plate = e.plate, livery = 3 },
      damage = { v = 1, engine = 1000.0, body = 700.0, doors = {}, windows = {}, tyres = { [0] = 1 } },
    }
  end
  for k, v in pairs(extra or {}) do data[k] = v end
  return data
end

local function store(src, truck, data)
  H.seat(src, truck)
  return H.cb('nz:garage:store', src, { locationId = 1, netId = H.entities[truck].netId, data = data })
end

local function retrieve(src, plate)
  NZ.Access.openSession(src, 'L1', loc)
  return H.cb('nz:garage:retrieve', src, { plate = plate, spawnIndex = 1, entityType = 'automobile' })
end

local function savedTrailer(plate)
  local raw = H.raw(plate)
  return raw and raw.nz_trailer and json.decode(raw.nz_trailer) or nil
end

---------------------------------------------------------------------------------------
H.scenario = 'store with trailer'
local truck, trailer = truckWithTrailer('TRUCK01', 'phantom', 'TRL0001')
local res = store(1, truck, collected(truck, trailer))
check(res.ok == true, 'stored: ' .. tostring(res.error))
check(res.data and res.data.trailer == 'stored', 'result says the trailer went in')
local saved = savedTrailer('TRUCK01')
check(saved and saved.hash == TRAILER and saved.model == 'trailers', 'nz_trailer: model + hash')
check(saved and saved.props and saved.props.livery == 3 and saved.props.plate == 'TRL0001', 'nz_trailer: props with plate')
check(saved and saved.damage and saved.damage.body == 700.0, 'nz_trailer: damage')
check(not H.entities[truck] and not H.entities[trailer], 'truck and trailer entities deleted')
check(NZ.DB.getVehicle('TRUCK01').state == 'garaged', 'truck garaged')
check(H.logs[#H.logs].event == 'vehicle.store' and H.logs[#H.logs].data.trailer == 'stored', 'store logged with trailer')

---------------------------------------------------------------------------------------
H.scenario = 'retrieve with trailer'
res = retrieve(1, 'TRUCK01')
check(res.ok == true, 'retrieved: ' .. tostring(res.error))
local v = res.data and res.data.vehicle
check(v and type(v.trailer) == 'table' and v.trailer.hash == TRAILER and v.trailer.props.plate == 'TRL0001'
  and v.trailer.damage and v.trailer.netId == nil, 'trailer travels with the vehicle data (client spawn)')
check(NZ.DB.getVehicle('TRUCK01').state == 'out', 'truck out')
-- the client spawns both and reports the truck
truck, trailer = truckWithTrailer('TRUCK01', 'phantom', 'TRL0001', { truckAt = vec3(100, 0, 0), trailerAt = vec3(100, -9, 0) })
local spawned = H.cb('nz:garage:spawned', 1, { plate = 'TRUCK01', netId = H.entities[truck].netId })
check(spawned.ok == true, 'spawn reported')

-- another truck cannot take TRUCK01's trailer
H.addRow({ plate = 'THIEF01', model = 'phantom', state = 0, owner = 'CID002' })
local thief = H.spawn('THIEF01', 'phantom', { coords = vec3(12, 0, 0) })
H.entities[trailer].attachedTo = thief
H.entities[trailer].coords = vec3(12, -9, 0)
H.playerPos[2] = vec3(10, 0, 0)
res = store(2, thief, collected(thief, trailer))
check(res.ok == true and res.data.trailer == nil, 'thief stored without the trailer')
check(H.entities[trailer] ~= nil and savedTrailer('THIEF01') == nil, 'the trailer stays in the world, not saved for the thief')
H.entities[trailer].attachedTo = 0
H.entities[trailer].coords = vec3(100, -9, 0)

---------------------------------------------------------------------------------------
H.scenario = 'hitch not replicated'
-- the server does not see the attachment: right behind the truck still counts
H.entities[truck].coords = vec3(12, 0, 0)
H.entities[trailer].coords = vec3(12, -11, 0)
res = store(1, truck, collected(truck, trailer))
check(res.ok and res.data.trailer == 'stored' and not H.entities[trailer], 'trailer 11 m behind stored without a visible hitch')
res = retrieve(1, 'TRUCK01')
truck, trailer = truckWithTrailer('TRUCK01', 'phantom', 'TRL0001', { truckAt = vec3(100, 0, 0), trailerAt = vec3(100, -9, 0) })
H.cb('nz:garage:spawned', 1, { plate = 'TRUCK01', netId = H.entities[truck].netId })

-- a random trailer 30 m away is not absorbed
local random = H.spawn('RND0001', 'trailers2', { vtype = 'trailer', coords = vec3(12, -40, 0) })
H.entities[truck].coords = vec3(12, 0, 0)
H.entities[trailer].coords = vec3(12, -9, 0)
H.entities[trailer].attachedTo = truck
local data = collected(truck, random)
res = store(1, truck, data)
check(res.ok and H.entities[random] ~= nil, 'far random trailer not taken')
check(not H.entities[trailer] and res.data.trailer == 'stored', 'its own saved trailer close by went in instead')
check(savedTrailer('TRUCK01').props.plate == 'TRL0001', 'saved trailer unchanged')

-- hitched to something else: never
res = retrieve(1, 'TRUCK01')
truck, trailer = truckWithTrailer('TRUCK01', 'phantom', 'TRL0001', { truckAt = vec3(12, 0, 0), trailerAt = vec3(12, -9, 0) })
H.cb('nz:garage:spawned', 1, { plate = 'TRUCK01', netId = H.entities[truck].netId })
local other = H.spawn('', 'flatbed', { coords = vec3(30, 30, 0) })
local random2 = H.spawn('RND0002', 'trailers3', { vtype = 'trailer', coords = vec3(12, -10, 0) })
H.entities[random2].attachedTo = other
H.entities[trailer].attachedTo = truck
res = store(1, truck, collected(truck, random2))
check(res.ok and H.entities[random2] ~= nil, 'trailer hitched to another vehicle not taken')

---------------------------------------------------------------------------------------
H.scenario = 'parked separately'
res = retrieve(1, 'TRUCK01')
check(res.ok and res.data.vehicle.trailer ~= nil, 'trailer comes out')
truck, trailer = truckWithTrailer('TRUCK01', 'phantom', 'TRL0001', { truckAt = vec3(100, 0, 0), trailerAt = vec3(100, -9, 0) })
H.cb('nz:garage:spawned', 1, { plate = 'TRUCK01', netId = H.entities[truck].netId })
-- unhitched and left 200 m away; the truck is stored alone
H.entities[trailer].attachedTo = 0
H.entities[trailer].coords = vec3(300, 0, 0)
H.entities[truck].coords = vec3(12, 0, 0)
res = store(1, truck, collected(truck, nil))
check(res.ok and res.data.trailer == 'parked', 'stored; trailer parked elsewhere')
check(H.entities[trailer] ~= nil, 'parked trailer left where it is')
check(savedTrailer('TRUCK01') ~= nil, 'still its saved trailer')
check(H.notified(1, 'stays where you parked it'), 'player told the trailer stays')
res = retrieve(1, 'TRUCK01')
check(res.ok and res.data.vehicle.trailer == nil, 'not spawned a second time while it exists')
check(H.notified(1, 'still where you parked it'), 'player told where it is')
truck = H.spawn('TRUCK01', 'phantom', { coords = vec3(100, 0, 0) })
H.cb('nz:garage:spawned', 1, { plate = 'TRUCK01', netId = H.entities[truck].netId })
-- another truck hitches the parked trailer: refused
local t2 = H.spawn('TRUCK02', 'packer', { coords = vec3(300, 9, 0) })
H.entities[trailer].attachedTo = t2
H.entities[t2].coords = vec3(12, 0, 0)
H.entities[trailer].coords = vec3(12, -9, 0)
res = store(2, t2, collected(t2, trailer))
check(res.ok and H.entities[trailer] ~= nil and savedTrailer('TRUCK02') == nil, 'someone else\'s parked trailer is never absorbed')
-- the parked trailer is destroyed / culled while the truck is out: the truck goes in alone
-- and the record is dropped (no ghost trailer on every retrieve, phone valet not refused)
DeleteEntity(trailer)
H.entities[truck].coords = vec3(12, 0, 0)
res = store(1, truck, collected(truck, nil))
check(res.ok and res.data.trailer == 'lost' and savedTrailer('TRUCK01') == nil, 'record dropped once the seen trailer is gone')
check(H.logs[#H.logs].data.trailer == 'lost', 'store logged with the lost trailer')
res = retrieve(1, 'TRUCK01')
check(res.ok and res.data.vehicle.trailer == nil, 'no ghost trailer on the next retrieve')
-- a new trailer hitched (the truck's driver owns it) is saved again
truck, trailer = truckWithTrailer('TRUCK01', 'phantom', 'TRL0001')
H.cb('nz:garage:spawned', 1, { plate = 'TRUCK01', netId = H.entities[truck].netId })
res = store(1, truck, collected(truck, trailer))
check(res.ok and res.data.trailer == 'stored' and savedTrailer('TRUCK01').props.plate == 'TRL0001', 'hitched again and saved')

H.scenario = 'trailer never spawned'
-- the client fails to create the trailer: the truck is stored alone, the record is kept
res = retrieve(1, 'TRUCK01')
check(res.ok and res.data.vehicle.trailer ~= nil, 'trailer expected with the truck')
truck = H.spawn('TRUCK01', 'phantom', { coords = vec3(12, 0, 0) })
H.cb('nz:garage:spawned', 1, { plate = 'TRUCK01', netId = H.entities[truck].netId })
check(Vehicles.out.TRUCK01 and Vehicles.out.TRUCK01.trailerExpected == true and not Vehicles.out.TRUCK01.trailerSeen,
  'trailer not seen yet')
H.advance(61000) -- the sweep looks again: still nothing
check(not Vehicles.out.TRUCK01.trailerSeen, 'sweep: still not seen')
res = store(1, truck, collected(truck, nil))
check(res.ok and res.data.trailer == nil and savedTrailer('TRUCK01') ~= nil, 'record kept for a trailer that never spawned')
res = retrieve(1, 'TRUCK01')
check(res.ok and res.data.vehicle.trailer ~= nil and res.data.vehicle.trailer.props.plate == 'TRL0001', 'it comes back with the truck')
-- the truck is reported before the trailer's clone reaches the server: the sweep sees it
truck = H.spawn('TRUCK01', 'phantom', { coords = vec3(100, 0, 0) })
H.cb('nz:garage:spawned', 1, { plate = 'TRUCK01', netId = H.entities[truck].netId })
check(not Vehicles.out.TRUCK01.trailerSeen, 'trailer clone not there yet')
trailer = H.spawn('TRL0001', 'trailers', { vtype = 'trailer', coords = vec3(100, -9, 0) })
H.entities[trailer].attachedTo = truck
H.advance(61000)
check(Vehicles.out.TRUCK01 and Vehicles.out.TRUCK01.trailerSeen == true, 'sweep: trailer seen')
check(Vehicles.trailerParked('TRUCK01') == true, 'trailerParked: its trailer is in the world')

-- a garaged vehicle's saved trailer standing in the world (tracked at boot)
local h2 = H.spawn('TRUCK02', 'packer', { coords = vec3(12, 0, 0) })
NZ.DB.updateVehicle('TRUCK02', { state = 'out' })
H.entities[tanker].attachedTo = h2
H.entities[tanker].coords = vec3(12, -10, 0)
res = store(2, h2, collected(h2, tanker))
check(res.ok and H.entities[tanker] ~= nil and savedTrailer('TRUCK02') == nil, 'saved trailer of a garaged vehicle (boot tracking) not taken')

---------------------------------------------------------------------------------------
H.scenario = 'impound / recover'
check(H.entities[trailer] ~= nil, 'trailer out with the truck')
local removed = Vehicles.removeTrailerOf('TRUCK01', NZ.DB.getVehicle('TRUCK01'))
check(removed == true and not H.entities[trailer], 'impound / recover removes the world copy')
check(savedTrailer('TRUCK01') ~= nil, 'saved data kept (comes back on the next retrieve)')
-- still tracked: a copy reappearing is not someone else's to take
local copy = H.spawn('TRL0001', 'trailers', { vtype = 'trailer', coords = vec3(12, -9, 0) })
local h3 = H.spawn('TRUCK02', 'packer', { coords = vec3(12, 0, 0) })
NZ.DB.updateVehicle('TRUCK02', { state = 'out' })
H.entities[copy].attachedTo = h3
res = store(2, h3, collected(h3, copy))
check(res.ok and H.entities[copy] ~= nil, 'still tracked after removal')
DeleteEntity(copy)
DeleteEntity(truck)
Vehicles.clearOut('TRUCK01')
NZ.DB.updateVehicle('TRUCK01', { state = 'garaged' })

---------------------------------------------------------------------------------------
H.scenario = 'server spawn'
H.settings['vehicles.serverSpawn'] = true
H.serverSpawns = {}
res = retrieve(1, 'TRUCK01')
check(res.ok == true and res.data.netId ~= nil, 'server spawned: ' .. tostring(res.error))
local trailerSpawn, truckSpawn = nil, nil
for _, s in ipairs(H.serverSpawns) do
  if s.vtype == 'trailer' then trailerSpawn = s else truckSpawn = s end
end
check(trailerSpawn ~= nil and truckSpawn ~= nil, 'trailer and truck created by the server')
-- spawn point (100, 0, 0) heading 90: forward is -x, so 20 m behind is x = 120
check(trailerSpawn and math.abs(trailerSpawn.x - 120) < 0.01 and math.abs(trailerSpawn.y) < 0.01 and trailerSpawn.w == 90.0,
  'trailer behind the spawn point, same heading')
check(trailerSpawn and H.frozen[trailerSpawn.handle] == true, 'server-created trailer frozen until hitched')
check(Vehicles.out.TRUCK01 and Vehicles.out.TRUCK01.trailerSeen == true, 'server-created trailer counts as seen')
local tBag = trailerSpawn and H.stateOf(trailerSpawn.handle)
check(tBag and type(tBag.nzInit) == 'table' and tBag.nzInit.isTrailer == true and tBag.nzInit.plate == 'TRL0001'
  and tBag.nzInit.props and tBag.nzInit.props.livery == 3, 'trailer nzInit: plate, props, isTrailer')
check(tBag and tBag.nzPlate == nil, 'no nzPlate on the trailer')
local vBag = truckSpawn and H.stateOf(truckSpawn.handle)
check(vBag and vBag.nzInit and vBag.nzInit.trailer and vBag.nzInit.trailer.netId == H.entities[trailerSpawn.handle].netId,
  'truck nzInit names the trailer to hitch')
check(H.entities[truckSpawn.handle].plate == 'TRUCK01' and vBag.nzPlate == 'TRUCK01', 'truck plate and nzPlate')
-- tidy: the truck is stored again with that trailer
H.entities[trailerSpawn.handle].attachedTo = truckSpawn.handle
H.entities[truckSpawn.handle].coords = vec3(12, 0, 0)
H.entities[trailerSpawn.handle].coords = vec3(12, -9, 0)
res = store(1, truckSpawn.handle, collected(truckSpawn.handle, trailerSpawn.handle))
check(res.ok and not H.entities[trailerSpawn.handle], 'server-spawned pair stored again')

-- the truck cannot be created: the trailer is removed again and the retrieve rolled back
local realSetter = CreateVehicleServerSetter
CreateVehicleServerSetter = function(hash, vtype, ...)
  if vtype ~= 'trailer' then return 0 end
  return realSetter(hash, vtype, ...)
end
H.serverSpawns = {}
res = retrieve(1, 'TRUCK01')
CreateVehicleServerSetter = realSetter
check(res.ok == false, 'retrieve fails when the truck cannot be created')
check(#H.serverSpawns == 1 and not H.entities[H.serverSpawns[1].handle], 'its trailer deleted again')
check(NZ.DB.getVehicle('TRUCK01').state == 'garaged' and not Vehicles.out.TRUCK01, 'rolled back')
-- still TRUCK01's saved trailer after the rollback: another truck cannot absorb a copy of it
do
  local copy2 = H.spawn('TRL0001', 'trailers', { vtype = 'trailer', coords = vec3(12, -9, 0) })
  local h4 = H.spawn('TRUCK02', 'packer', { coords = vec3(12, 0, 0) })
  NZ.DB.updateVehicle('TRUCK02', { state = 'out' })
  H.entities[copy2].attachedTo = h4
  res = store(2, h4, collected(h4, copy2))
  check(res.ok and H.entities[copy2] ~= nil and savedTrailer('TRUCK02') == nil, 'rollback keeps the trailer tracked')
  DeleteEntity(copy2)
end
-- the safety net unfreezes a server-created trailer nobody hitched
do
  local realSpawn = Vehicles.spawnServer
  H.serverSpawns = {}
  res = retrieve(1, 'TRUCK01')
  local t = nil
  for _, sp in ipairs(H.serverSpawns) do if sp.vtype == 'trailer' then t = sp.handle end end
  check(t and H.frozen[t] == true, 'frozen at creation')
  H.advance(21000)
  check(t and H.frozen[t] == false, 'unfrozen by the server after the timeout')
  -- tidy: back in the garage
  for _, sp in ipairs(H.serverSpawns) do DeleteEntity(sp.handle) end
  Vehicles.clearOut('TRUCK01')
  NZ.DB.updateVehicle('TRUCK01', { state = 'garaged' })
  Vehicles.spawnServer = realSpawn
end
H.settings['vehicles.serverSpawn'] = nil

---------------------------------------------------------------------------------------
H.scenario = 'registered trailer'
res = retrieve(1, 'TRUCK01')
truck = H.spawn('TRUCK01', 'phantom', { coords = vec3(12, 0, 0) })
H.cb('nz:garage:spawned', 1, { plate = 'TRUCK01', netId = H.entities[truck].netId })
local regTrailer = nil
for _, h in ipairs(H.find(function(e) return e.plate == 'TRL0001' end)) do DeleteEntity(h) end
regTrailer = H.spawn('BOATTR1', 'boattrailer', { vtype = 'trailer', coords = vec3(12, -8, 0) })
H.entities[regTrailer].attachedTo = truck
res = store(1, truck, collected(truck, regTrailer))
check(res.ok and res.data.trailerStored == true, 'truck stored, registered trailer stored as itself')
local boat = NZ.DB.getVehicle('BOATTR1')
check(boat.state == 'garaged' and boat.garageKey == 'L1', 'registered trailer garaged in the same garage')
check(not H.entities[regTrailer], 'its entity deleted')
check(savedTrailer('TRUCK01') and savedTrailer('TRUCK01').props.plate == 'TRL0001', 'truck keeps its own saved trailer')
-- somebody else's registered trailer: refused, left in the world
res = retrieve(1, 'TRUCK01')
truck = H.spawn('TRUCK01', 'phantom', { coords = vec3(12, 0, 0) })
H.cb('nz:garage:spawned', 1, { plate = 'TRUCK01', netId = H.entities[truck].netId })
for _, h in ipairs(H.find(function(e) return e.plate == 'TRL0001' end)) do DeleteEntity(h) end
local foreign = H.spawn('BOATTR2', 'boattrailer', { vtype = 'trailer', coords = vec3(12, -8, 0) })
H.entities[foreign].attachedTo = truck
res = store(1, truck, collected(truck, foreign))
check(res.ok and res.data.trailerStored == false, 'truck stored, foreign trailer not')
check(H.entities[foreign] ~= nil and NZ.DB.getVehicle('BOATTR2').state == 'out', 'foreign trailer stays out')
check(H.notified(1, 'BOATTR2 was not stored'), 'player told why')

---------------------------------------------------------------------------------------
H.scenario = 'new trailer, hitch not seen'
res = retrieve(1, 'TRUCK01')
truck = H.spawn('TRUCK01', 'phantom', { coords = vec3(12, 0, 0) })
H.cb('nz:garage:spawned', 1, { plate = 'TRUCK01', netId = H.entities[truck].netId })
for _, h in ipairs(H.find(function(e) return e.plate == 'TRL0001' end)) do DeleteEntity(h) end
local far = H.spawn('NEW0002', 'trailers2', { vtype = 'trailer', coords = vec3(12, -18, 0) })
res = store(1, truck, collected(truck, far))
check(res.ok and H.entities[far] ~= nil and res.data.trailer == nil, 'a new trailer 18 m away is not on the hitch')
res = retrieve(1, 'TRUCK01')
truck = H.spawn('TRUCK01', 'phantom', { coords = vec3(12, 0, 0) })
H.cb('nz:garage:spawned', 1, { plate = 'TRUCK01', netId = H.entities[truck].netId })
for _, h in ipairs(H.find(function(e) return e.plate == 'TRL0001' end)) do DeleteEntity(h) end
-- a loose trailer the storing client does not own (another player's job trailer): refused
H.entities[far].coords = vec3(12, -12, 0)
H.entities[far].owner = 2
res = store(1, truck, collected(truck, far))
check(res.ok and H.entities[far] ~= nil and res.data.trailer == nil and savedTrailer('TRUCK01').props.plate == 'TRL0001',
  'a loose trailer owned by another client is never grabbed')
-- in front of the truck: not on its hitch
for _, plate in ipairs({ 'front', 'crossways' }) do
  res = retrieve(1, 'TRUCK01')
  truck = H.spawn('TRUCK01', 'phantom', { coords = vec3(12, 0, 0) })
  H.cb('nz:garage:spawned', 1, { plate = 'TRUCK01', netId = H.entities[truck].netId })
  for _, h in ipairs(H.find(function(e) return e.plate == 'TRL0001' end)) do DeleteEntity(h) end
  H.entities[far].owner = 1
  if plate == 'front' then
    H.entities[far].coords, H.entities[far].heading = vec3(12, 12, 0), 0.0
  else
    H.entities[far].coords, H.entities[far].heading = vec3(12, -12, 0), 180.0
  end
  res = store(1, truck, collected(truck, far))
  check(res.ok and H.entities[far] ~= nil and res.data.trailer == nil, 'unseen hitch refused: trailer ' .. plate)
end
H.entities[far].heading = 0.0
res = retrieve(1, 'TRUCK01')
truck = H.spawn('TRUCK01', 'phantom', { coords = vec3(12, 0, 0) })
H.cb('nz:garage:spawned', 1, { plate = 'TRUCK01', netId = H.entities[truck].netId })
for _, h in ipairs(H.find(function(e) return e.plate == 'TRL0001' end)) do DeleteEntity(h) end
H.entities[far].coords = vec3(12, -12, 0)
-- heading 0, the truck's driver owns it, 12 m right behind: on the hitch
res = store(1, truck, collected(truck, far))
check(res.ok and not H.entities[far] and res.data.trailer == 'stored', 'a new trailer 12 m behind replaces the saved one')
check(savedTrailer('TRUCK01').props.plate == 'NEW0002', 'new saved trailer')

---------------------------------------------------------------------------------------
H.scenario = 'trailers off'
H.settings['vehicles.trailers'] = false
res = retrieve(1, 'TRUCK01')
check(res.ok and res.data.vehicle.trailer == nil, 'setting off: no trailer comes out')
truck = H.spawn('TRUCK01', 'phantom', { coords = vec3(12, 0, 0) })
H.cb('nz:garage:spawned', 1, { plate = 'TRUCK01', netId = H.entities[truck].netId })
res = store(1, truck, collected(truck, nil))
check(res.ok and savedTrailer('TRUCK01') == nil, 'setting off: the saved trailer is dropped on store')
H.settings['vehicles.trailers'] = nil

H.finish('trailer')
