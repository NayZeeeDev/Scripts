--[[
  nayzeee-garages — server/jobs.lua (NZ.Jobs)

  Job & gang garages and public spawner garages: the spawner list filtered by grade,
  job / gang owned fleets, the 'nz:garage:spawner' callback (validation, payment, unique
  plate from the template, optional server spawn) and the registry of active spawner
  vehicles (one per player per location unless infiniteSpawns). A slot is freed when the
  vehicle is returned (NZ.Jobs.release from the vehicles module) or its entity disappears;
  slots of players who left stay taken until their vehicle is gone.
]]

local Jobs = NZ.Jobs
local Utils = NZ.Utils

---@type table<string, table> plate -> { src, identifier, locationId, at, index, model, job, garageKey, entity?, netId? }
Jobs.active = Jobs.active or {}

local SPAWN_GRACE = 90           -- seconds a spawned vehicle may stay unreported before its slot is freed
local SWEEP_INTERVAL = 20000     -- ms between clean-up passes (only while slots exist)
local ABANDON_SECONDS = 300      -- a vehicle of a player who left is removed after standing empty this long
local PLATE_TRIES = 20
local SPAWN_CLEARANCE = 2.5      -- metres; a spawn point with a vehicle closer than this is occupied
local MAX_PLATE_LENGTH = 16
local BAG_KEY = 'nzSpawner'      -- server-only entity state: lets slots survive a resource restart
local SUNK_Z = -3.0              -- a vehicle this far under sea level is lost

local entityPlates = {}          -- [entity] = plate of an active spawner vehicle
local sweeperStarted = false
local booted = false

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function ok(data) return Utils.ok(data) end
local function fail(message) return Utils.fail(message) end

local function log(event, src, data)
  if type(NZ.Logs.add) ~= 'function' then return end
  local success, err = pcall(NZ.Logs.add, event, src, data)
  if not success then lib.print.warn(('jobs: could not log %s: %s'):format(event, tostring(err))) end
end

local function setting(path, default)
  if type(NZ.Settings.get) ~= 'function' then return default end
  local success, value = pcall(NZ.Settings.get, path, default)
  if not success or value == nil then return default end
  return value
end

local function maxDistance()
  return tonumber(setting('garages.maxDistance', 25.0)) or 25.0
end

--- Integer within [min, max] or nil (NaN / infinity rejected).
local function toInt(value, min, max)
  local n = tonumber(value)
  if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
  n = math.floor(n)
  if min and n < min then return nil end
  if max and n > max then return nil end
  return n
end

--- Normalize a model hash to the signed 32-bit form GTA uses.
local function toSigned(hash)
  local n = tonumber(hash)
  if not n or n ~= n then return nil end
  n = math.floor(n) % 4294967296
  if n >= 2147483648 then n = n - 4294967296 end
  return math.tointeger(n) or n
end

local function identifierOf(src)
  if not src or type(NZ.Bridge.getIdentifier) ~= 'function' then return nil end
  local success, identifier = pcall(NZ.Bridge.getIdentifier, src)
  if success and type(identifier) == 'string' and identifier ~= '' then return identifier end
  return nil
end

local function money(amount)
  local digits = tostring(math.max(0, math.floor(tonumber(amount) or 0)))
  local grouped = (digits:reverse():gsub('(%d%d%d)', '%1,')):reverse():gsub('^,', '')
  return tostring(setting('interface.currency', '$') or '$') .. grouped
end

local function refund(src, amount, account)
  if amount <= 0 then return end
  local success, added = pcall(NZ.Bridge.addMoney, src, account or 'bank', amount, 'nayzeee-garages:spawner-refund')
  if not success or not added then
    log('security.refund', src, { amount = amount, account = account, reason = 'spawner refund failed' })
  end
end

local function vehicleTypeOf(row)
  if type(NZ.Vehicles.vehicleTypeOf) == 'function' then return NZ.Vehicles.vehicleTypeOf(row) end
  local vtype = type(row) == 'table' and row.vehicleType or nil
  return Utils.vehicleTypes[vtype] and vtype or 'car'
end

local function isVehicleEntity(entity)
  return type(entity) == 'number' and entity ~= 0 and DoesEntityExist(entity) and GetEntityType(entity) == 2
end

local function plateOf(entity)
  return Utils.plate(GetVehicleNumberPlateText(entity))
end

local function isOccupied(entity)
  for seat = -1, 14 do
    local ped = GetPedInVehicleSeat(entity, seat)
    if ped and ped ~= 0 then return true end
  end
  return false
end

--- Destroyed, burnt out or sunk: such a vehicle can never be returned to the garage.
local function isWrecked(entity)
  if not isVehicleEntity(entity) then return false end
  local success, health = pcall(GetEntityHealth, entity)
  if success and tonumber(health) and tonumber(health) <= 0 then return true end
  if (tonumber(GetVehicleEngineHealth(entity)) or 1000) <= -3500 then return true end
  local coords = GetEntityCoords(entity)
  return coords ~= nil and tonumber(coords.z) ~= nil and coords.z < SUNK_Z
end

local function findEntityByPlate(plate)
  for _, entity in ipairs(GetAllVehicles() or {}) do
    if isVehicleEntity(entity) and plateOf(entity) == plate then return entity end
  end
  return nil
end

local function outEntry(plate)
  local out = type(NZ.Vehicles.out) == 'table' and NZ.Vehicles.out[plate] or nil
  return type(out) == 'table' and out or nil
end

local function setOut(plate, entry)
  if type(NZ.Vehicles.setOut) == 'function' then
    NZ.Vehicles.setOut(plate, entry)
  elseif type(NZ.Vehicles.out) == 'table' then
    NZ.Vehicles.out[plate] = entry
  end
end

local function clearOut(plate)
  if type(NZ.Vehicles.clearOut) == 'function' then
    NZ.Vehicles.clearOut(plate)
  elseif type(NZ.Vehicles.out) == 'table' then
    NZ.Vehicles.out[plate] = nil
  end
end

---------------------------------------------------------------------------------------
-- Locations, grades and spawner entries
---------------------------------------------------------------------------------------

--- Job or public garage whose vehicles come from a spawner list.
local function isSpawnerLocation(location)
  return type(location) == 'table' and (location.kind == 'job' or location.kind == 'garage')
    and location.source == 'spawner'
end

local function ownerKind(location)
  return location.owner == 'gang' and 'gang' or 'job'
end

--- Grade (and job / gang name) of the player at a job location, nil when no rule matches.
---@return number|nil grade, string|nil name
local function jobGrade(src, location)
  local kind = ownerKind(location)
  if not NZ.Access.jobAllowed(src, location.jobs, kind) then return nil, nil end
  local getter = kind == 'gang' and NZ.Bridge.getGang or NZ.Bridge.getJob
  if type(getter) ~= 'function' then return nil, nil end
  local success, data = pcall(getter, src)
  if not success or type(data) ~= 'table' then return nil, nil end
  return tonumber(data.grade) or 0, type(data.name) == 'string' and data.name or nil
end

--- Spawner entry visible for this grade (grades empty = every grade).
local function entryAllowed(entry, grade, ignoreGrades)
  if ignoreGrades then return true end
  if type(entry.grades) ~= 'table' or #entry.grades == 0 then return true end
  for _, allowed in ipairs(entry.grades) do
    if tonumber(allowed) == grade then return true end
  end
  return false
end

local function validEntry(entry)
  return type(entry) == 'table' and type(entry.model) == 'string' and entry.model ~= ''
end

local function entryPrice(entry)
  return math.max(0, toInt(entry.price) or 0)
end

--- SpawnerVehicleView list for the player (types.ts SpawnerVehicleView, label added by the client).
---@param src number
---@param location table job or public garage location with source 'spawner'
---@return table[]
function Jobs.spawnerList(src, location)
  local list = {}
  if not isSpawnerLocation(location) or type(location.spawner) ~= 'table' then return list end
  local grade, ignoreGrades = 0, location.kind ~= 'job'
  if not ignoreGrades then
    grade = jobGrade(src, location)
    if not grade then return list end
  end
  for index, entry in ipairs(location.spawner) do
    if validEntry(entry) and entryAllowed(entry, grade, ignoreGrades) then
      list[#list + 1] = {
        index = index,
        model = entry.model,
        hash = toSigned(joaat(entry.model)) or 0,
        plate = type(entry.plate) == 'string' and entry.plate or '',
        price = entryPrice(entry),
        vehicleType = location.vehicleType or 'car',
        label = type(entry.label) == 'string' and entry.label or '',
      }
    end
  end
  return list
end

--- Fleet vehicles (job or gang owned) the player may see at a job location, filtered by
--- the location's vehicle type.
---@param src number
---@param location table job location
---@return table[] NZVehicleRow list
function Jobs.ownedVehicles(src, location)
  local rows = {}
  if type(location) ~= 'table' or location.kind ~= 'job' or type(location.jobs) ~= 'table' then return rows end
  local kind = ownerKind(location)
  local fetch = kind == 'gang' and NZ.DB.getVehiclesByGang or NZ.DB.getVehiclesByJob
  if type(fetch) ~= 'function' then return rows end
  local vtype = location.vehicleType or 'car'
  local seenName, seenPlate = {}, {}
  for _, rule in ipairs(location.jobs) do
    local name = type(rule) == 'table' and rule.name or nil
    if type(name) == 'string' and not seenName[name] and NZ.Access.jobAllowed(src, { rule }, kind) then
      seenName[name] = true
      for _, row in ipairs(fetch(name) or {}) do
        if type(row) == 'table' and row.plate and not seenPlate[row.plate] and vehicleTypeOf(row) == vtype then
          seenPlate[row.plate] = true
          rows[#rows + 1] = row
        end
      end
    end
  end
  return rows
end

---------------------------------------------------------------------------------------
-- Active spawner vehicles
---------------------------------------------------------------------------------------

--- Remember the entity of an active spawner vehicle and tag it (server-only state bag)
--- so the slot can be re-adopted after a resource restart.
local function bindEntity(plate, info, entity)
  if info.entity and info.entity ~= entity then entityPlates[info.entity] = nil end
  info.entity = entity
  info.netId = NetworkGetNetworkIdFromEntity(entity)
  entityPlates[entity] = plate
  local success, err = pcall(function()
    Entity(entity).state:set(BAG_KEY, {
      locationId = info.locationId, identifier = info.identifier, index = info.index,
      model = info.model, job = info.job, at = info.at,
    }, false)
  end)
  if not success then Utils.debug('spawner tag failed', plate, tostring(err)) end
end

--- Live entity of an active spawner vehicle (learned from the vehicles module once the
--- client reported it), or nil.
local function liveEntity(plate, info)
  if isVehicleEntity(info.entity) then return info.entity end
  local out = outEntry(plate)
  if out then
    local entity = out.entity
    if not isVehicleEntity(entity) and out.netId then entity = NetworkGetEntityFromNetworkId(out.netId) end
    if isVehicleEntity(entity) and plateOf(entity) == plate then
      bindEntity(plate, info, entity)
      return entity
    end
  end
  return nil
end

--- Free a slot. Automatic releases (entity gone, player left) are logged here; returns
--- through a garage are logged by the vehicles module.
---@return boolean released
local function releaseSlot(plate, reason)
  local info = Jobs.active[plate]
  if not info then return false end
  Jobs.active[plate] = nil
  local entity = info.entity
  if entity then
    entityPlates[entity] = nil
    if isVehicleEntity(entity) then
      pcall(function() Entity(entity).state:set(BAG_KEY, nil, false) end)
    end
  end
  local out = outEntry(plate)
  if out and out.spawner and not isVehicleEntity(out.entity) then clearOut(plate) end
  if reason then
    log('vehicle.spawnerRelease', nil, {
      plate = plate, reason = reason, location = info.locationId, model = info.model,
      identifier = info.identifier, job = info.job, heldFor = os.time() - (tonumber(info.at) or os.time()),
    })
  end
  return true
end

--- Active slot of a player at a location (by source, or identifier after a reconnect).
local function activeFor(locationId, src, identifier)
  for plate, info in pairs(Jobs.active) do
    if info.locationId == locationId and ((src and info.src == src) or (identifier and info.identifier == identifier)) then
      return plate, info
    end
  end
  return nil, nil
end

--- Is the slot still held by a vehicle that exists or is being spawned right now?
--- `reclaimWreck`: a destroyed / sunk vehicle nobody sits in is deleted and frees the slot
--- (it can never be returned, and server-created entities are kept until deleted).
local function slotInUse(plate, info, reclaimWreck)
  local live = liveEntity(plate, info)
  if live then
    if reclaimWreck and isWrecked(live) and not isOccupied(live) then
      DeleteEntity(live)
      return false
    end
    return true
  end
  if not info.entity and os.time() - (tonumber(info.at) or 0) <= SPAWN_GRACE then return true end
  if not info.entity then
    local found = findEntityByPlate(plate)
    if found then
      bindEntity(plate, info, found)
      return true
    end
  end
  return false
end

local function sweep()
  local stale = {}
  local now = os.time()
  for plate, info in pairs(Jobs.active) do
    if not slotInUse(plate, info) then
      stale[#stale + 1] = { plate = plate, reason = info.entity and 'removed' or 'never spawned' }
    elseif info.dropped and not info.src then
      -- The player left and nobody uses the vehicle: remove it once it stood empty long enough
      -- (unless the player came back: the slot is theirs again).
      local entity = liveEntity(plate, info)
      local back = nil
      if info.identifier and type(NZ.Bridge.getSourceByIdentifier) == 'function' then
        local found, value = pcall(NZ.Bridge.getSourceByIdentifier, info.identifier)
        back = found and tonumber(value) or nil
      end
      if back then
        info.src, info.dropped, info.idleSince = back, nil, nil
      elseif entity and isOccupied(entity) then
        info.idleSince = nil
      elseif entity then
        info.idleSince = info.idleSince or now
        if now - info.idleSince >= ABANDON_SECONDS then
          DeleteEntity(entity)
          stale[#stale + 1] = { plate = plate, reason = 'abandoned' }
        end
      end
    end
  end
  for _, item in ipairs(stale) do releaseSlot(item.plate, item.reason) end
end

local function ensureSweeper()
  if sweeperStarted then return end
  sweeperStarted = true
  CreateThread(function()
    while true do
      Wait(SWEEP_INTERVAL)
      if next(Jobs.active) ~= nil then
        local success, err = pcall(sweep)
        if not success then lib.print.error(('jobs: spawner sweep failed: %s'):format(tostring(err))) end
      end
    end
  end)
end

--- After a resource restart: re-adopt spawner vehicles that are still in the world.
local function adoptExisting()
  local adopted = 0
  for _, entity in ipairs(GetAllVehicles() or {}) do
    if isVehicleEntity(entity) then
      local success, tag = pcall(function() return Entity(entity).state[BAG_KEY] end)
      local plate = success and type(tag) == 'table' and plateOf(entity) or nil
      if plate and not Jobs.active[plate] then
        local identifier = type(tag.identifier) == 'string' and tag.identifier or nil
        local src = nil
        if identifier and type(NZ.Bridge.getSourceByIdentifier) == 'function' then
          local found, value = pcall(NZ.Bridge.getSourceByIdentifier, identifier)
          src = found and tonumber(value) or nil
        end
        local info = {
          src = src,
          identifier = identifier,
          locationId = tonumber(tag.locationId),
          at = tonumber(tag.at) or os.time(),
          index = tonumber(tag.index),
          model = type(tag.model) == 'string' and tag.model or nil,
          job = type(tag.job) == 'string' and tag.job or nil,
          garageKey = tonumber(tag.locationId) and Utils.key.location(tonumber(tag.locationId)) or nil,
          adopted = true,
        }
        Jobs.active[plate] = info
        bindEntity(plate, info, entity)
        adopted = adopted + 1
      end
    end
  end
  if adopted > 0 then lib.print.info(('jobs: re-adopted %d spawner vehicle(s) still in the world'):format(adopted)) end
end

--- Lazy start (first use after NZ.Ready): adopt surviving spawner vehicles, start the sweeper.
local function boot()
  if booted or not NZ.Ready then return end
  booted = true
  local success, err = pcall(adoptExisting)
  if not success then lib.print.error(('jobs: spawner adoption failed: %s'):format(tostring(err))) end
  ensureSweeper()
end

--- Is this plate an active spawner (job / rental) vehicle?
---@param plate string
---@return boolean, table|nil info copy { src, identifier, locationId, at, index, model, job, garageKey }
function Jobs.isSpawnerVehicle(plate)
  boot()
  plate = Utils.plate(plate)
  local info = plate and Jobs.active[plate] or nil
  if not info then return false, nil end
  return true, {
    src = info.src, identifier = info.identifier, locationId = info.locationId, at = info.at,
    index = info.index, model = info.model, job = info.job, garageKey = info.garageKey,
  }
end

--- Free the slot of a spawner vehicle (called when it is returned / removed).
---@param plate string
---@return boolean released
function Jobs.release(plate)
  plate = Utils.plate(plate)
  if not plate then return false end
  return releaseSlot(plate, nil)
end

--- The client of `src` could not create the spawner vehicle it was given: refund what it
--- paid (once, only while no entity was ever bound to the slot) and free the slot.
--- Called by NZ.Vehicles.spawnFailed, which already checked that no copy exists.
---@param plate string
---@param src number
---@return boolean released
function Jobs.spawnFailed(plate, src)
  plate = Utils.plate(plate)
  src = tonumber(src)
  local info = plate and Jobs.active[plate] or nil
  if not info then return false end
  local price = math.max(0, toInt(info.price) or 0)
  if price > 0 and src and info.src == src and info.entity == nil and info.netId == nil and not info.refunded then
    info.refunded = true
    refund(src, price, info.account)
    log('vehicle.spawner', src, {
      plate = plate, model = info.model, location = info.locationId, failed = true,
      reason = 'client spawn failed', refunded = price, account = info.account,
    })
  end
  return releaseSlot(plate, 'spawn failed')
end

--- Player left: free slots whose vehicle is gone or stands empty (the vehicle is removed:
--- server-created entities would otherwise stay forever); keep the slot of a vehicle that
--- someone is using (removed by the sweep once it has stood empty for a while).
---@param src number
function Jobs.onPlayerDropped(src)
  src = tonumber(src)
  if not src then return end
  local stale = {}
  for plate, info in pairs(Jobs.active) do
    if info.src == src then
      info.src = nil
      info.dropped = os.time()
      local entity = liveEntity(plate, info)
      if not entity then
        stale[#stale + 1] = plate
      elseif not isOccupied(entity) then
        DeleteEntity(entity)
        stale[#stale + 1] = plate
      end
    end
  end
  for _, plate in ipairs(stale) do releaseSlot(plate, 'owner left') end
end

AddEventHandler('entityRemoved', function(entity)
  local plate = entityPlates[entity]
  if not plate then return end
  entityPlates[entity] = nil
  local info = Jobs.active[plate]
  if info and info.entity == entity then releaseSlot(plate, 'removed') end
end)

-- The vehicles module tags reported entities with 'nzPlate': learn spawner entities at once.
AddStateBagChangeHandler('nzPlate', nil, function(bagName, _, value)
  local plate = Utils.plate(value)
  local info = plate and Jobs.active[plate] or nil
  if not info or isVehicleEntity(info.entity) then return end
  local entity = GetEntityFromStateBagName(bagName)
  if isVehicleEntity(entity) and plateOf(entity) == plate then bindEntity(plate, info, entity) end
end)

---------------------------------------------------------------------------------------
-- Spawning
---------------------------------------------------------------------------------------

local function hasWildcard(template)
  return type(template) == 'string' and template:find('[#@%*]') ~= nil
end

--- Unique plate from a template ('' = random). A fixed template that is taken falls back
--- to random plates.
---@return string|nil
local function uniquePlate(template)
  local base = type(template) == 'string' and template ~= '' and template or nil
  for attempt = 1, PLATE_TRIES do
    local use = base
    if use and attempt > 1 and not hasWildcard(use) then use = nil end
    local candidate = Utils.plate(Utils.generatePlate(use))
    if candidate and #candidate <= MAX_PLATE_LENGTH and not Jobs.active[candidate]
      and not outEntry(candidate) and not NZ.DB.plateExists(candidate) then
      return candidate
    end
  end
  return nil
end

local function spotFree(point, positions)
  for i = 1, #positions do
    if Utils.dist(point, positions[i]) < SPAWN_CLEARANCE then return false end
  end
  return true
end

--- Requested spawn point when free, else the first free one. nil when all are taken.
local function pickSpawn(points, wanted)
  local positions = {}
  for _, entity in ipairs(GetAllVehicles() or {}) do
    if DoesEntityExist(entity) then positions[#positions + 1] = GetEntityCoords(entity) end
  end
  local point = Utils.v4(points[wanted])
  if point and spotFree(point, positions) then return wanted, point end
  for i = 1, #points do
    local candidate = Utils.v4(points[i])
    if candidate and spotFree(candidate, positions) then return i, candidate end
  end
  return nil, nil
end

local function register(name, handler)
  lib.callback.register(name, Utils.safe(function(source, payload)
    local src = tonumber(source)
    if not src or src <= 0 then return fail(L('Something went wrong')) end
    if not NZ.Ready then return fail(L('Garages are still loading')) end
    if type(payload) ~= 'table' then payload = {} end
    return handler(src, payload)
  end))
end

-- { index, spawnIndex, entityType } -> { spawn, spawnIndex, vehicle = { plate, hash, model },
--   setupMenu, maxMods, livery, extras, label, netId? }
register('nz:garage:spawner', function(src, payload)
  boot()
  if not NZ.Access.rateLimit(src, 'garage:spawner', 1500) then
    return fail(L('Please wait a moment before trying again'))
  end
  local session, err = NZ.Access.requireSession(src, maxDistance())
  if not session then return fail(err or L('The garage is not open')) end
  local location = session.location
  if not isSpawnerLocation(location) or type(location.spawner) ~= 'table' then
    return fail(L('This garage has no vehicles to take out'))
  end
  local allowed, reason = NZ.Access.canUse(src, location)
  if not allowed then return fail(reason or L('You do not have access to this garage')) end
  local identifier = identifierOf(src)
  if not identifier then return fail(L('Your character is not loaded')) end

  local index = toInt(payload.index, 1, #location.spawner)
  local entry = index and location.spawner[index] or nil
  if not validEntry(entry) then return fail(L('Vehicle not found')) end

  local jobName = nil
  if location.kind == 'job' then
    local grade, name = jobGrade(src, location)
    if not grade then return fail(L('You do not have access to this garage')) end
    if not entryAllowed(entry, grade, false) then return fail(L('Your grade cannot take out this vehicle')) end
    jobName = name
  end

  if not (location.kind == 'job' and location.infiniteSpawns == true) then
    local current, info = activeFor(location.id, src, identifier)
    if current then
      if slotInUse(current, info, true) then return fail(L('Return your current vehicle first')) end
      releaseSlot(current, 'replaced')
    end
  end

  local points = location.spawnPoints
  if type(points) ~= 'table' or #points == 0 then return fail(L('This garage has no parking spots')) end
  local wanted = toInt(payload.spawnIndex, 1, #points)
  if not wanted then return fail(L('Invalid parking spot')) end
  local spawnIndex, spawn = pickSpawn(points, wanted)
  if not spawnIndex then return fail(L('All parking spots are occupied')) end

  local hash = toSigned(joaat(entry.model))
  if not hash then return fail(L('Unknown vehicle model')) end
  local plate = uniquePlate(entry.plate)
  if not plate then return fail(L('Could not generate a plate, please try again')) end

  local price = entryPrice(entry)
  local account = nil
  if price > 0 then
    local paid, used = NZ.Bridge.pay(src, price, 'nayzeee-garages:spawner')
    if not paid then return fail(L('You cannot afford this ({amount})', { amount = money(price) })) end
    account = used
  end

  local now = os.time()
  local garageKey = Utils.key.location(location.id)
  local info = {
    src = src,
    identifier = identifier,
    locationId = location.id,
    at = now,
    index = index,
    model = entry.model,
    job = jobName,
    garageKey = garageKey,
    price = price,       -- refunded when the client cannot create the vehicle
    account = account,
  }
  Jobs.active[plate] = info
  local outInfo = { src = src, identifier = identifier, garageKey = garageKey, at = now, spawner = true, job = jobName }
  setOut(plate, outInfo)
  ensureSweeper()

  local result = {
    spawn = spawn,
    spawnIndex = spawnIndex,
    vehicle = { plate = plate, hash = hash, model = entry.model },
    setupMenu = location.setupMenu == true,
    maxMods = entry.maxMods == true,
    livery = toInt(entry.livery, -1) or -1,
    extras = type(entry.extras) == 'table' and entry.extras or {},
    label = type(entry.label) == 'string' and entry.label or '',
  }

  -- Server-derived network type (the client's hint only when it fits the category); unknown
  -- -> the client creates the vehicle.
  local entityType = nil
  if type(NZ.Vehicles.resolveEntityType) == 'function' then
    entityType = NZ.Vehicles.resolveEntityType(hash, type(payload.entityType) == 'string' and payload.entityType or nil,
      location.vehicleType or 'car')
  end
  if setting('vehicles.serverSpawn', false) == true and entityType then
    local spawned, entity, netId = pcall(NZ.Vehicles.spawnServer, hash, entityType, spawn, { plate = plate },
      GetPlayerRoutingBucket(src))
    if not spawned or not entity then
      Jobs.active[plate] = nil
      clearOut(plate)
      refund(src, price, account)
      log('vehicle.spawner', src, {
        plate = plate, model = entry.model, location = location.id, failed = true,
        reason = spawned and 'server spawn failed' or tostring(entity),
      })
      return fail(L('The vehicle could not be spawned'))
    end
    bindEntity(plate, info, entity)
    outInfo.entity = entity
    outInfo.netId = netId
    setOut(plate, outInfo)
    result.netId = netId
  end

  log('vehicle.spawner', src, {
    plate = plate,
    model = entry.model,
    location = location.id,
    locationName = location.name,
    kind = location.kind,
    job = jobName,
    price = price,
    account = account,
    serverSpawn = result.netId ~= nil,
  })
  return ok(result)
end)
