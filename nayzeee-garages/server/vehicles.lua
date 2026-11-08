--[[
  nayzeee-garages — server/vehicles.lua (NZ.Vehicles)

  Everything that moves a vehicle in or out of a garage on the server:
  garage menu data (GarageOpenData), retrieve ("Drive", §7.1), store (§7.2), track,
  recover lost vehicles, nearest garage with free space, and the out-vehicle registry
  (NZ.Vehicles.out) used for duplication protection and restart adoption (§7.5).
]]

local Vehicles = NZ.Vehicles
local Utils = NZ.Utils

---@type table<string, table> plate -> { netId, entity, src, identifier, garageKey, at, spawner, job }
Vehicles.out = Vehicles.out or {}

local SPAWN_GRACE = 60          -- seconds a retrieved vehicle may stay unreported before it counts as lost
local LOCK_TIMEOUT = 30000      -- ms after which a plate lock is considered stale
local SPAWN_CLEARANCE = 2.5     -- metres; a spawn point with a vehicle closer than this is occupied
local TRAILER_RANGE = 20.0      -- metres; max distance of an unattached trailer from its vehicle
local HITCH_RANGE = 16.0        -- metres; centre distance of a vehicle and the trailer on its hitch
                                -- (long semi trailers ~12 m), used when the server sees no attachment
local HITCH_ANGLE = 100.0       -- degrees; max heading difference of truck and unseen-hitch trailer
local TRAILER_BACK = 20.0       -- metres behind the spawn point a server-created trailer appears,
                                -- frozen (the owner client then moves it onto the hitch); clear of
                                -- the truck's rear even for long semi trailers
local TRAILER_UNFREEZE_MS = 20000 -- the server unfreezes a server-created trailer after this anyway
local MAX_PLATE_LENGTH = 16
local MAX_PROPS_BYTES = 32768
local MAX_DAMAGE_BYTES = 65536

-- Network entity types a vehicle may be server-created as (never 'train').
local ENTITY_TYPES = {
  automobile = true, bike = true, boat = true, heli = true,
  plane = true, submarine = true, trailer = true,
}
local ENTITY_CATEGORY = { boat = 'sea', submarine = 'sea', heli = 'air', plane = 'air' }
-- Entity types that fit a location category (client hints are only trusted within these).
local CATEGORY_ENTITY_TYPES = {
  car = { automobile = true, bike = true, trailer = true },
  sea = { boat = true, submarine = true },
  air = { heli = true, plane = true },
}
local AWAIT_ENTITY_MS = 3000    -- how long a reported netId may take to reach the server
local SUNK_Z = -3.0             -- a vehicle this far under sea level is lost

local entityPlates = {}   -- [entity handle] = plate, for fast clean-up on entityRemoved
local locks = {}          -- [plate] = GetGameTimer() at lock time
local blacklist = nil     -- lazily built set of blacklisted model hashes
local entityTypes = {}    -- [model hash] = network entity type seen on a real entity (false = unknown)
local trailerOwners = {}  -- ['<hash>:<plate>'] = plate of the vehicle whose saved trailer is out in the world
local trailerOf = {}      -- [plate] = '<hash>:<plate>' key of its tracked trailer (reverse of trailerOwners)
local booted = false

---------------------------------------------------------------------------------------
-- Small helpers
---------------------------------------------------------------------------------------

local function ok(data) return Utils.ok(data) end
local function fail(message) return Utils.fail(message) end

local function setting(path, default)
  local value
  if NZ.Settings and NZ.Settings.get then value = NZ.Settings.get(path, default) end
  if value == nil then return default end
  return value
end

local function maxDistance()
  return tonumber(setting('garages.maxDistance', 25.0)) or 25.0
end

local function log(event, src, data)
  if not (NZ.Logs and NZ.Logs.add) then return end
  local success, err = pcall(NZ.Logs.add, event, src, data)
  if not success then
    lib.print.warn(('[nayzeee-garages] could not log %s: %s'):format(event, err))
  end
end

local function toInt(value, min, max)
  local n = tonumber(value)
  if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
  n = math.floor(n)
  if min and n < min then return nil end
  if max and n > max then return nil end
  return n
end

local function readPlate(value)
  local plate = Utils.plate(value)
  if plate and #plate <= MAX_PLATE_LENGTH then return plate end
  return nil
end

local function money(amount)
  local digits = tostring(math.max(0, math.floor(tonumber(amount) or 0)))
  local grouped = (digits:reverse():gsub('(%d%d%d)', '%1,')):reverse()
  grouped = grouped:gsub('^,', '')
  return tostring(setting('interface.currency', '$') or '$') .. grouped
end

--- Normalize a model hash to the signed 32-bit form GTA uses.
local function toSigned(hash)
  local n = tonumber(hash)
  if not n or n ~= n then return nil end
  n = math.floor(n) % 4294967296
  if n >= 2147483648 then n = n - 4294967296 end
  return math.tointeger(n) or n
end

local function rowHash(row)
  local h = tonumber(row.hash)
  if h and h ~= 0 then return toSigned(h) end
  if type(row.model) == 'string' and row.model ~= '' then return toSigned(joaat(row.model)) end
  return nil
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

--- The registration of a vehicle entity: the real plate under a fake plate
--- (NZ.FakePlates), else the plate text.
local function identityOf(entity)
  local fake = NZ.FakePlates
  if type(fake) == 'table' and type(fake.realPlateOf) == 'function' then
    local okReal, real = pcall(fake.realPlateOf, entity)
    if okReal and real then return real end
  end
  return plateOf(entity)
end

--- Entity of the vehicle registered as `plate` (fake plates see through), or nil. With
--- `hash` only an entity of that model counts: another player's car of another model that
--- shows the same text (a fake plate, a plate changer) is never taken for this vehicle.
---@param plate string
---@param hash number|nil signed model hash (rowHash)
local function findEntityByPlate(plate, hash)
  for _, entity in ipairs(GetAllVehicles() or {}) do
    if isVehicleEntity(entity) and identityOf(entity) == plate
      and (not hash or hash == 0 or toSigned(GetEntityModel(entity)) == hash) then
      return entity
    end
  end
  return nil
end

local function pedCoords(src)
  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return nil end
  return GetEntityCoords(ped)
end

local function deleteVehicle(entity)
  if type(entity) == 'number' and entity ~= 0 and DoesEntityExist(entity) then
    entityPlates[entity] = nil
    DeleteEntity(entity)
  end
end

local function firstOpenPoint(location)
  local points = type(location) == 'table' and location.openPoints
  if type(points) ~= 'table' then return nil end
  for _, point in ipairs(points) do
    local coords = Utils.v3(type(point) == 'table' and point.coords or point)
    if coords then return coords end
  end
  return nil
end

--- 'personal' | 'spawner' | 'owned' for any location kind.
local function sourceOf(location)
  local kind = location.kind
  if kind == 'garage' then return location.source == 'spawner' and 'spawner' or 'personal' end
  if kind == 'job' then return location.source == 'spawner' and 'spawner' or 'owned' end
  return 'personal'
end

local function groupIdOf(session)
  if type(session) ~= 'table' then return nil end
  local gid = tonumber(session.groupId)
  if gid then return gid end
  local kind, id = Utils.key.parse(session.garageKey)
  if kind == 'G' then return id end
  return nil
end

local function keyName(key, cache)
  if not key then return nil end
  if cache and cache.keyNames and cache.keyNames[key] ~= nil then
    return cache.keyNames[key] or nil
  end
  local name = NZ.Locations.keyName(key)
  if cache and cache.keyNames then cache.keyNames[key] = name or false end
  return name
end

local function hasSpace(capacity)
  if type(capacity) ~= 'table' or capacity.mode == 'unlimited' then return true end
  local total = tonumber(capacity.total)
  if not total then return true end
  return (tonumber(capacity.used) or 0) < total
end

local function sanitize(value, maxBytes)
  if type(value) ~= 'table' then return nil end
  local encoded, result = pcall(json.encode, value)
  if not encoded or type(result) ~= 'string' or #result > maxBytes then return nil end
  return value
end

local function sanitizeDamage(value, keepDeformation)
  local damage = sanitize(value, MAX_DAMAGE_BYTES)
  if not damage then return nil end
  if not keepDeformation and damage.deform ~= nil then
    local copy = {}
    for k, v in pairs(damage) do
      if k ~= 'deform' then copy[k] = v end
    end
    damage = copy
  end
  return damage
end

local function percent(value)
  local n = tonumber(value)
  if not n or n ~= n then return nil end
  return Utils.round(Utils.clamp(n, 0, 100), 1)
end

local function isBlacklisted(hash)
  if not blacklist then
    blacklist = {}
    for k, v in pairs(Config.BlacklistedModels or {}) do
      local model = type(k) == 'string' and v and k or (type(v) == 'string' and v) or nil
      if model then blacklist[toSigned(joaat(model))] = true end
    end
  end
  return hash ~= nil and blacklist[hash] == true
end

--- Category of a live vehicle entity from the server-side vehicle type.
local function categoryOfEntity(entity)
  local success, vtype = pcall(GetVehicleType, entity)
  if not success or type(vtype) ~= 'string' then return nil end
  return ENTITY_CATEGORY[vtype] or 'car'
end

--- Remember the network entity type of a real entity's model (used for server spawns).
local function learnEntityType(entity)
  if not isVehicleEntity(entity) then return end
  local success, vtype = pcall(GetVehicleType, entity)
  if not success or not ENTITY_TYPES[vtype] then return end
  local hash = toSigned(GetEntityModel(entity))
  if not hash or entityTypes[hash] == vtype then return end
  entityTypes[hash] = vtype
  if SetResourceKvp then pcall(SetResourceKvp, 'nz:vtype:' .. hash, vtype) end
end

--- Network entity type to server-create `hash` with, derived server-side: the type seen on a
--- real entity of that model, else the client's hint when it fits the vehicle category.
--- nil when unknown (callers then let the client create the vehicle).
---@param hash number model hash
---@param hint string|nil client-computed entity type
---@param category string|nil 'car'|'sea'|'air'
---@return string|nil
function Vehicles.resolveEntityType(hash, hint, category)
  hash = toSigned(hash)
  if not hash then return nil end
  local known = entityTypes[hash]
  if known == nil then
    known = false
    if GetResourceKvpString then
      local success, stored = pcall(GetResourceKvpString, 'nz:vtype:' .. hash)
      if success and ENTITY_TYPES[stored] then known = stored end
    end
    entityTypes[hash] = known
  end
  if known then return known end
  local allowed = CATEGORY_ENTITY_TYPES[category or 'car'] or CATEGORY_ENTITY_TYPES.car
  if type(hint) == 'string' and allowed[hint] then return hint end
  return nil
end

--- Destroyed, burnt out or sunk: such a vehicle can never be driven back to a garage.
local function isWrecked(entity)
  if not isVehicleEntity(entity) then return false end
  local success, health = pcall(GetEntityHealth, entity)
  if success and tonumber(health) and tonumber(health) <= 0 then return true end
  if (tonumber(GetVehicleEngineHealth(entity)) or 1000) <= -3500 then return true end
  local coords = GetEntityCoords(entity)
  return coords ~= nil and tonumber(coords.z) ~= nil and coords.z < SUNK_Z
end

--- Wait until the entity of a client-reported netId reaches the server with the expected
--- plate (the clone and the plate travel separately from the event that reports them).
---@return number|nil entity, boolean plateMatches
local function awaitVehicle(netId, plate, timeoutMs)
  local deadline = GetGameTimer() + (timeoutMs or AWAIT_ENTITY_MS)
  while true do
    local entity = NetworkGetEntityFromNetworkId(netId)
    if isVehicleEntity(entity) and plateOf(entity) == plate then return entity, true end
    if GetGameTimer() >= deadline then
      if isVehicleEntity(entity) then return entity, false end
      return nil, false
    end
    Wait(50)
  end
end

---------------------------------------------------------------------------------------
-- Trailers left in the world by a retrieved vehicle
---------------------------------------------------------------------------------------

--- Plate a saved trailer gets when spawned (client rule: data.plate, else props.plate, 8 chars).
local function trailerPlateOf(data)
  if type(data) ~= 'table' then return nil end
  local text = data.plate
  if type(text) ~= 'string' or Utils.trim(text) == '' then
    text = type(data.props) == 'table' and data.props.plate or nil
  end
  if type(text) ~= 'string' then return nil end
  return Utils.plate(Utils.trim(text):sub(1, 8))
end

local function trailerHashOf(data)
  if type(data) ~= 'table' then return nil end
  local hash = toSigned(data.hash)
  if hash and hash ~= 0 then return hash end
  if type(data.model) == 'string' and data.model ~= '' then return toSigned(joaat(data.model)) end
  local props = type(data.props) == 'table' and data.props or nil
  return props and toSigned(props.model) or nil
end

local function trailerKey(hash, plate)
  if not hash or not plate then return nil end
  return tostring(hash) .. ':' .. plate
end

local function trailerKeyOfData(data)
  return trailerKey(trailerHashOf(data), trailerPlateOf(data))
end

local function trailerKeyOfEntity(entity)
  return trailerKey(toSigned(GetEntityModel(entity)), plateOf(entity))
end

local function untrackTrailers(plate)
  local key = trailerOf[plate]
  if key and trailerOwners[key] == plate then trailerOwners[key] = nil end
  trailerOf[plate] = nil
end

--- `data` is the saved trailer of `plate` (in its garage or out in the world): no other
--- vehicle may absorb an entity of it. A vehicle has one saved trailer.
local function trackTrailer(plate, data)
  local key = trailerKeyOfData(data)
  if not key then return end
  untrackTrailers(plate)
  -- a key moving to another vehicle leaves no stale reverse entry behind
  local previous = trailerOwners[key]
  if previous and previous ~= plate and trailerOf[previous] == key then trailerOf[previous] = nil end
  trailerOwners[key] = plate
  trailerOf[plate] = key
end

--- Live, unoccupied entity of a saved trailer (model + plate), or nil.
local function findSavedTrailer(data)
  local key = trailerKeyOfData(data)
  if not key then return nil end
  for _, entity in ipairs(GetAllVehicles() or {}) do
    if isVehicleEntity(entity) and trailerKeyOfEntity(entity) == key and not isOccupied(entity) then
      local success, vtype = pcall(GetVehicleType, entity)
      if not success or vtype == nil or vtype == 'trailer' then return entity end
    end
  end
  return nil
end

--- Is the saved trailer of `plate` (database row `row`) standing in the world right now
--- (parked separately from its vehicle)? The phone valet delivers such a vehicle alone.
---@param plate string
---@param row table|nil NZVehicleRow (read when nil)
---@return boolean parked
function Vehicles.trailerParked(plate, row)
  plate = readPlate(plate)
  if not plate then return false end
  if type(row) ~= 'table' then row = NZ.DB.getVehicle(plate) end
  if type(row) ~= 'table' or type(row.trailer) ~= 'table' then return false end
  return findSavedTrailer(row.trailer) ~= nil
end

--- Track every saved trailer (boot): one parked away from its vehicle (or in the world after
--- a resource restart) is never taken by another vehicle.
local function trackSavedTrailers()
  if type(NZ.DB.getSavedTrailers) ~= 'function' then return 0 end
  local count = 0
  for _, entry in ipairs(NZ.DB.getSavedTrailers() or {}) do
    if type(entry) == 'table' and entry.plate and type(entry.trailer) == 'table' then
      trackTrailer(entry.plate, entry.trailer)
      count = count + 1
    end
  end
  return count
end

--- Delete the saved trailer of a vehicle that is being put away without being driven to a
--- garage (recover, impound), so the next retrieve does not create a second copy of it.
--- The saved trailer data is kept: a trailer that no longer exists is restored once.
---@param plate string
---@param row table|nil NZVehicleRow (its saved trailer is looked for too)
---@return boolean removed
function Vehicles.removeTrailerOf(plate, row)
  plate = readPlate(plate)
  if not plate then return false end
  local keys = {}
  local tracked = trailerOf[plate]
  if tracked and trailerOwners[tracked] == plate then keys[tracked] = true end
  local own = type(row) == 'table' and trailerKeyOfData(row.trailer) or nil
  if own and (trailerOwners[own] == nil or trailerOwners[own] == plate) then keys[own] = true end
  local removed = false
  if next(keys) then
    for _, entity in ipairs(GetAllVehicles() or {}) do
      if isVehicleEntity(entity) and keys[trailerKeyOfEntity(entity) or ''] and not isOccupied(entity) then
        local success, vtype = pcall(GetVehicleType, entity)
        if not success or vtype == nil or vtype == 'trailer' then
          deleteVehicle(entity)
          removed = true
        end
      end
    end
  end
  untrackTrailers(plate)
  -- still its saved trailer (it comes back with the vehicle on the next retrieve)
  if type(row) == 'table' and type(row.trailer) == 'table' then trackTrailer(plate, row.trailer) end
  return removed
end

---------------------------------------------------------------------------------------
-- Plate locks (one in-flight operation per vehicle)
---------------------------------------------------------------------------------------

--- Run `fn(...)` while holding an exclusive lock on `plate`. Returns the result of `fn`,
--- or a failure result when another operation on the same vehicle is still running.
--- `fn` must return a callback result table.
---@param plate string
---@param fn function
---@return table
function Vehicles.withLock(plate, fn, ...)
  local now = GetGameTimer()
  local held = locks[plate]
  if held and now - held < LOCK_TIMEOUT then
    return fail(L('This vehicle is busy, try again in a moment'))
  end
  locks[plate] = now
  local results = table.pack(pcall(fn, ...))
  if locks[plate] == now then locks[plate] = nil end
  if not results[1] then error(results[2], 0) end
  return table.unpack(results, 2, results.n)
end

---------------------------------------------------------------------------------------
-- Out-vehicle registry
---------------------------------------------------------------------------------------

--- Register a vehicle as out in the world (used by retrieve, spawners and adoption).
---@param plate string
---@param entry table { netId?, entity?, src?, identifier?, garageKey?, spawner?, job? }
function Vehicles.setOut(plate, entry)
  plate = readPlate(plate)
  if not plate or type(entry) ~= 'table' then return end
  entry.at = entry.at or os.time()
  if entry.netId and not entry.entity then
    local entity = NetworkGetEntityFromNetworkId(entry.netId)
    if isVehicleEntity(entity) then entry.entity = entity end
  end
  if entry.entity then entityPlates[entry.entity] = plate end
  Vehicles.out[plate] = entry
end

--- Forget a tracked out vehicle (does not touch the database or the entity).
---@param plate string
function Vehicles.clearOut(plate)
  plate = readPlate(plate)
  if not plate then return end
  local entry = Vehicles.out[plate]
  if entry and entry.entity then entityPlates[entry.entity] = nil end
  Vehicles.out[plate] = nil
end

--- Is the vehicle out in the world right now? While a freshly retrieved vehicle has not
--- reported its entity yet (grace period) this returns true without an entity.
---@param plate string
---@return boolean out, number|nil entity
function Vehicles.isOut(plate)
  plate = readPlate(plate)
  if not plate then return false, nil end
  local entry = Vehicles.out[plate]
  if not entry then return false, nil end
  if entry.entity and isVehicleEntity(entry.entity) then
    return true, entry.entity
  end
  if entry.netId then
    local entity = NetworkGetEntityFromNetworkId(entry.netId)
    if isVehicleEntity(entity) and identityOf(entity) == plate then
      entry.entity = entity
      entityPlates[entity] = plate
      return true, entity
    end
    return false, nil
  end
  if os.time() - (tonumber(entry.at) or 0) < SPAWN_GRACE then
    return true, nil
  end
  return false, nil
end

---------------------------------------------------------------------------------------
-- Player condition
---------------------------------------------------------------------------------------

-- Player state bags set by common death / police resources (only `true` counts).
local CONDITION_BAGS = {
  'isDead', 'dead', 'inLaststand', 'laststand', 'isCuffed', 'isHandcuffed', 'handcuffed',
  'cuffed', 'isEscorted', 'escorted',
}

--- Is the player unable to act right now: dead, downed, cuffed, or carried / escorted by
--- another ped? Server mirror of NZ.Points.incapacitated (client) from what the server sees:
--- ped health and attachment, player state bags and qb / qbx metadata.
---@param src number
---@return boolean
function Vehicles.incapacitated(src)
  src = tonumber(src)
  if not src or src <= 0 then return false end
  local okPed, down = pcall(function()
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return false end
    local health = tonumber(GetEntityHealth(ped))
    if health and health <= 0 then return true end
    local parent = GetEntityAttachedTo(ped)
    return parent ~= nil and parent ~= 0 and GetEntityType(parent) == 1
  end)
  if okPed and down then return true end
  local okBag, bag = pcall(function() return Player(src).state end)
  if okBag and bag then
    for i = 1, #CONDITION_BAGS do
      if bag[CONDITION_BAGS[i]] == true then return true end
    end
  end
  if NZ.Framework == 'qb' or NZ.Framework == 'qbx' then
    local okPlayer, player = pcall(NZ.Bridge.getPlayer, src)
    local data = okPlayer and type(player) == 'table' and player.PlayerData or nil
    local md = type(data) == 'table' and data.metadata or nil
    if type(md) == 'table' and (md.isdead == true or md.inlaststand == true or md.ishandcuffed == true) then
      return true
    end
  end
  return false
end

---------------------------------------------------------------------------------------
-- Ownership / access
---------------------------------------------------------------------------------------

--- Vehicle category of a database row ('car' when unknown).
---@param row table NZVehicleRow
---@return 'car'|'sea'|'air'
function Vehicles.vehicleTypeOf(row)
  if type(row) ~= 'table' then return 'car' end
  local vtype = row.vehicleType
  -- Rows never stored by this resource have no nz_type on QBCore/Qbox: ask the framework's
  -- shared vehicle list (boats / helicopters / planes) before assuming a car.
  if not row.vehicleTypeKnown and NZ.Bridge.getSharedVehicleType then
    local ok, shared = pcall(NZ.Bridge.getSharedVehicleType, row.model, row.hash)
    if ok and shared and Utils.vehicleTypes[shared] then return shared end
  end
  if vtype and Utils.vehicleTypes[vtype] then return vtype end
  return 'car'
end

--- Fleet kind and name of a job/gang owned vehicle, or nil for private vehicles.
---@return 'job'|'gang'|nil kind, string|nil name
function Vehicles.fleetOf(row)
  if type(row) ~= 'table' then return nil, nil end
  if row.ownerType == 'gang' and row.gang then return 'gang', row.gang end
  if row.ownerType == 'job' and row.job then return 'job', row.job end
  if row.gang then return 'gang', row.gang end
  if row.job then return 'job', row.job end
  return nil, nil
end

--- True when `location` is a job location that serves the fleet of `row`.
local function servesFleet(location, row)
  if type(location) ~= 'table' or location.kind ~= 'job' then return false end
  local kind, name = Vehicles.fleetOf(row)
  if not kind then return false end
  if (location.owner == 'gang' and 'gang' or 'job') ~= kind then return false end
  for _, rule in ipairs(type(location.jobs) == 'table' and location.jobs or {}) do
    if type(rule) == 'table' and rule.name == name then return true end
  end
  return false
end

--- Rules of `location` for the fleet `name`.
local function fleetRules(location, name, into)
  into = into or {}
  for _, rule in ipairs(type(location.jobs) == 'table' and location.jobs or {}) do
    if type(rule) == 'table' and rule.name == name then into[#into + 1] = rule end
  end
  return into
end

--- May `src` use this job / gang fleet vehicle here? At a garage of the fleet its grade rules
--- apply; elsewhere the player must pass the rules of at least one enabled garage of the fleet
--- (never a grade-0 fallback). The job garage the vehicle is parked at (or was last taken
--- from) keeps its own grade rules, so a lower-grade garage of the same job cannot be used
--- to reach it.
local function fleetAllowed(src, row, session)
  local kind, name = Vehicles.fleetOf(row)
  if not kind then return false end
  local location = type(session) == 'table' and session.location or nil
  local allowed
  if servesFleet(location, row) then
    allowed = NZ.Access.jobAllowed(src, fleetRules(location, name), kind) == true
  else
    local rules = {}
    for _, candidate in ipairs(NZ.Locations.all('job') or {}) do
      if candidate.enabled ~= false and servesFleet(candidate, row) then fleetRules(candidate, name, rules) end
    end
    allowed = #rules > 0 and NZ.Access.jobAllowed(src, rules, kind) == true
  end
  if not allowed then return false end

  if row.garageKey and not (type(session) == 'table' and row.garageKey == session.garageKey) then
    local resolved = NZ.Locations.resolveKey(row.garageKey)
    local home = resolved and resolved.kind == 'L' and resolved.location or nil
    if home and servesFleet(home, row) and not (type(location) == 'table' and home.id == location.id) then
      return NZ.Access.jobAllowed(src, fleetRules(home, name), kind) == true
    end
  end
  return true
end

--- A fleet vehicle parked somewhere that is not a garage of its fleet (public / private /
--- house garage, or a deleted location): any garage of the fleet may take it back.
local function strandedFleet(row)
  if not Vehicles.fleetOf(row) or not row.garageKey then return false end
  local resolved = NZ.Locations.resolveKey(row.garageKey)
  return not (resolved and resolved.kind == 'L' and servesFleet(resolved.location, row))
end

--- Is `plate` shared with `identifier`?
---@param plate string
---@param identifier string
---@return boolean
function Vehicles.isSharedWith(plate, identifier)
  if not plate or not identifier then return false end
  for _, share in ipairs(NZ.DB.shares.forPlate(plate) or {}) do
    if type(share) == 'table' and share.identifier == identifier then return true end
  end
  return false
end

--- Set of plates shared with `identifier`: { [plate] = true }.
local function sharedPlateSet(identifier)
  local set = {}
  if not identifier then return set end
  for _, entry in ipairs(NZ.DB.shares.forIdentifier(identifier) or {}) do
    local plate = Utils.plate(type(entry) == 'table' and entry.plate or entry)
    if plate then set[plate] = true end
  end
  return set
end

--- How the player may use a vehicle: 'owner' | 'shared' | 'group' | 'fleet' | nil.
--- `cache` (optional) may hold `identifier` and `shared` (plate set) to avoid lookups.
---@param src number
---@param row table NZVehicleRow
---@param session table|nil
---@param cache table|nil
---@return string|nil
function Vehicles.accessOf(src, row, session, cache)
  if type(row) ~= 'table' then return nil end
  cache = cache or {}
  local identifier = cache.identifier or NZ.Bridge.getIdentifier(src)
  if not identifier then return nil end
  if row.owner and row.owner == identifier then return 'owner' end
  local shared
  if cache.shared then
    shared = cache.shared[row.plate] == true
  else
    shared = Vehicles.isSharedWith(row.plate, identifier)
  end
  if shared then return 'shared' end
  if type(session) == 'table' and row.garageKey and row.garageKey == session.garageKey
    and not Vehicles.fleetOf(row) then
    local location = session.location
    if type(location) == 'table' and location.kind == 'private' and location.storage == 'shared' then
      local gid = groupIdOf(session)
      if gid and NZ.Private.role(gid, identifier) then return 'group' end
    end
  end
  if Vehicles.fleetOf(row) and fleetAllowed(src, row, session) then return 'fleet' end
  return nil
end

--- Shared drive check. `access` may be precomputed (false = no access).
local function evaluate(src, row, session, cache, allowImpounded, access)
  if row.blocked then return false, L('This vehicle is blocked') end
  local state = row.state or 'garaged'
  if state == 'impounded' and not allowImpounded then
    local where = type(row.impound) == 'table' and row.impound.locationName or nil
    return false, L('Impounded at {impound}', { impound = where or L('the impound') })
  end
  if state == 'out' then return false, L('Vehicle is already out') end
  -- Config.Finance.missedAction 'none' leaves an overdue vehicle usable
  local financeBlocks
  if NZ.Finance and type(NZ.Finance.blocks) == 'function' then
    financeBlocks = NZ.Finance.blocks(row)
  else
    financeBlocks = type(row.finance) == 'table' and row.finance.overdue == true
  end
  if financeBlocks then
    return false, L('Finance payment overdue')
  end
  local location = type(session) == 'table' and session.location or nil
  if type(location) ~= 'table' then return false, L('The garage is not open') end
  if Vehicles.vehicleTypeOf(row) ~= (location.vehicleType or 'car') then
    return false, L('Wrong vehicle type for this garage')
  end
  if location.kind == 'impound' then
    if not (allowImpounded and state == 'impounded') then
      return false, L('This vehicle cannot be taken out here')
    end
    local info = row.impound
    if type(info) == 'table' and info.locationId and tonumber(info.locationId) ~= tonumber(location.id) then
      return false, L('Impounded at {impound}', { impound = info.locationName or L('the impound') })
    end
  else
    if sourceOf(location) == 'spawner' then return false, L('This vehicle cannot be taken out here') end
    if location.kind == 'job' and not servesFleet(location, row) then
      return false, L('This vehicle cannot be taken out here')
    end
    local mode = (cache and cache.retrieveMode) or setting('garages.retrieveMode', 'last')
    if mode ~= 'anywhere' and row.garageKey and row.garageKey ~= session.garageKey
      and not (location.kind == 'job' and strandedFleet(row)) then
      return false, L('Parked at {garage}', { garage = keyName(row.garageKey, cache) or L('another garage') })
    end
  end
  if access == nil then access = Vehicles.accessOf(src, row, session, cache) end
  if not access then return false, L('You do not have access to this vehicle') end
  -- Fleet members take fleet vehicles out of a garage of that fleet only.
  if access == 'fleet' and location.kind ~= 'impound' and not servesFleet(location, row) then
    return false, L('This vehicle cannot be taken out here')
  end
  return true, nil
end

--- Can `src` drive `row` out of the garage of `session`?
--- opts (optional): { allowImpounded = boolean } — impound retrieval.
---@param src number
---@param row table NZVehicleRow
---@param session table
---@param opts table|nil
---@return boolean allowed, string|nil reason
function Vehicles.canDrive(src, row, session, opts)
  if type(row) ~= 'table' then return false, L('Vehicle not found') end
  opts = type(opts) == 'table' and opts or {}
  return evaluate(src, row, session, opts.cache or {}, opts.allowImpounded == true, nil)
end

--- Can this location accept `row` (impounds, spawners and job fleets are restricted)?
--- Job / gang fleet vehicles live in the garages of their fleet only.
local function storableHere(row, location)
  if location.kind == 'impound' then return false, L('Vehicles cannot be stored at an impound') end
  if sourceOf(location) == 'spawner' then return false, L('Only vehicles from this garage can be returned here') end
  if Vehicles.fleetOf(row) then
    if not servesFleet(location, row) then
      return false, L('Fleet vehicles can only be stored at their job garage')
    end
  elseif location.kind == 'job' then
    return false, L('Only fleet vehicles can be stored here')
  end
  return true, nil
end

--- Can the owner of `row` reach garage `key`? Prevents a shared player from parking the
--- owner's vehicle in a private group, house or restricted public garage the owner cannot
--- open (the owner storing their own vehicle already passed NZ.Access.canUse).
local function ownerCanReach(row, key)
  if not row.owner then return true end
  local kind, id = Utils.key.parse(key)
  if kind == 'G' then return NZ.Private.role(id, row.owner) ~= nil end
  if kind == 'H' and NZ.Housing and NZ.Housing.hasAccess then
    return NZ.Housing.hasAccess(row.owner, id) == true
  end
  if kind == 'L' then
    local location = NZ.Locations.get(id)
    if type(location) == 'table' and location.kind == 'garage' then
      local restriction = type(location.restriction) == 'table' and location.restriction or {}
      local rtype = restriction.type or 'everyone'
      if rtype == 'everyone' then return true end
      if rtype == 'identifier' then
        for _, identifier in ipairs(type(restriction.identifiers) == 'table' and restriction.identifiers or {}) do
          if identifier == row.owner then return true end
        end
        return false
      end
      -- job / gang restriction: only verifiable for an online owner (refuse otherwise)
      local ownerSrc = NZ.Bridge.getSourceByIdentifier(row.owner)
      return ownerSrc ~= nil and NZ.Access.canUse(ownerSrc, location) == true
    end
  end
  return true
end

---------------------------------------------------------------------------------------
-- Garage resolution (open / store)
---------------------------------------------------------------------------------------

local function houseIdOf(value)
  if type(value) == 'number' then value = tostring(math.floor(value)) end
  if type(value) ~= 'string' or #value == 0 or #value > 64 then return nil end
  if value:find('[%c<>]') then return nil end
  return value
end

--- Resolve the garage a player is addressing: location, garage key and private group.
--- Checks the location exists, is enabled, is not an impound and that the player may use
--- it. Does NOT check distance.
---@param src number
---@param payload table { locationId?, groupId?, houseId? }
---@return table|nil target { location, garageKey, groupId, houseId, identifier }, string|nil error
function Vehicles.resolveGarage(src, payload)
  payload = type(payload) == 'table' and payload or {}
  local identifier = NZ.Bridge.getIdentifier(src)
  if not identifier then return nil, L('Your character is not loaded') end

  local location, houseId
  if payload.houseId ~= nil then
    houseId = houseIdOf(payload.houseId)
    if not houseId then return nil, L('Garage not found') end
    location = NZ.Locations.get(Utils.key.house(houseId))
  elseif type(payload.locationId) == 'string' and payload.locationId:sub(1, 1) == 'H' then
    houseId = houseIdOf(payload.locationId:sub(2))
    if not houseId then return nil, L('Garage not found') end
    location = NZ.Locations.get(Utils.key.house(houseId))
  else
    local id = toInt(payload.locationId, 1)
    location = id and NZ.Locations.get(id) or nil
  end
  if type(location) ~= 'table' then return nil, L('Garage not found') end
  if location.enabled == false then return nil, L('This garage is closed') end
  if location.kind == 'impound' then return nil, L('This garage is not available') end

  local allowed, reason = NZ.Access.canUse(src, location)
  if not allowed then return nil, reason or L('You cannot use this garage') end

  local garageKey, groupId
  if houseId or location.kind == 'house' then
    if not houseId and type(location.id) == 'string' then houseId = location.id:sub(2) end
    if not houseId then return nil, L('Garage not found') end
    garageKey = Utils.key.house(houseId)
  elseif location.kind == 'private' then
    local groups = NZ.Private.groupsFor(identifier, location.id) or {}
    local wanted = toInt(payload.groupId, 1)
    if wanted then
      for _, group in ipairs(groups) do
        if tonumber(group.id) == wanted then groupId = wanted break end
      end
      if not groupId then return nil, L('You do not own this garage') end
    elseif groups[1] then
      groupId = tonumber(groups[1].id)
    end
    if not groupId then return nil, L('You do not own this garage') end
    garageKey = Utils.key.group(groupId)
  else
    garageKey = Utils.key.location(location.id)
  end

  return {
    location = location,
    garageKey = garageKey,
    groupId = groupId,
    houseId = houseId,
    identifier = identifier,
  }, nil
end

---------------------------------------------------------------------------------------
-- Garage menu data
---------------------------------------------------------------------------------------

--- Build the per-request context used by toGarageVehicle (favourites, shares and name
--- caches are loaded once per request).
---@param src number|nil
---@param session table|nil
---@param identifier string|nil
---@return table
function Vehicles.newContext(src, session, identifier)
  identifier = identifier or (src and NZ.Bridge.getIdentifier(src)) or nil
  local favourites, shared = {}, {}
  if identifier then
    local stored = NZ.DB.favourites.get(identifier)
    if type(stored) == 'table' then
      for k, v in pairs(stored) do
        local plate = (type(k) == 'string' and Utils.plate(k)) or (type(v) == 'string' and Utils.plate(v)) or nil
        if plate and v then favourites[plate] = true end
      end
    end
    shared = sharedPlateSet(identifier)
  end
  return {
    _nz = true,
    src = src,
    session = session,
    identifier = identifier,
    favourites = favourites,
    shared = shared,
    names = {},
    keyNames = {},
    retrieveMode = setting('garages.retrieveMode', 'last'),
    recoverFee = math.max(0, toInt(setting('garages.recoverFee', 250)) or 0),
    needsServiceBelow = tonumber(setting('vehicles.needsServiceBelow', 60)) or 60,
  }
end

--- Accept a partial context from other modules and fill whatever is missing.
---@param ctx table|nil
---@return table
function Vehicles.ensureContext(ctx)
  ctx = type(ctx) == 'table' and ctx or {}
  if ctx._nz then return ctx end
  local full = Vehicles.newContext(ctx.src, ctx.session, ctx.identifier)
  for k, v in pairs(full) do
    if ctx[k] == nil then ctx[k] = v end
  end
  return ctx
end

local function characterName(identifier, ctx)
  local cached = ctx.names[identifier]
  if cached == nil then
    cached = NZ.Bridge.getCharacterName(identifier) or ''
    ctx.names[identifier] = cached
  end
  return cached
end

local function ownerNameOf(row, ctx)
  local kind, name = Vehicles.fleetOf(row)
  if kind and row.ownerType ~= 'player' then
    local key = 'viewer' .. kind
    if ctx[key] == nil then
      local info = nil
      if ctx.src then
        if kind == 'gang' then
          info = NZ.Bridge.getGang and NZ.Bridge.getGang(ctx.src) or nil
        else
          info = NZ.Bridge.getJob(ctx.src)
        end
      end
      ctx[key] = info or false
    end
    local info = ctx[key]
    if info and info.name == name and info.label then return info.label end
    return name
  end
  if row.owner then return characterName(row.owner, ctx) end
  return name or ''
end

--- Per-viewer GarageVehicle view of a database row (types.ts GarageVehicle).
---@param row table NZVehicleRow
---@param ctx table context from NZ.Vehicles.newContext (partial tables are completed)
---@return table GarageVehicle
local function indexOf(key)
  local n = tonumber(key)
  return n and math.tointeger(n) or nil
end

--- Compact damage summary for the interface (DamageSummary in types.ts) from the stored
--- NZ.Damage table. Keys may be numbers or strings after the JSON round trip.
---@param damage table|nil
---@return table|nil
function Vehicles.damageSummary(damage)
  if type(damage) ~= 'table' then return nil end
  local out = {
    engine = tonumber(damage.engine) or 1000.0,
    body = tonumber(damage.body) or 1000.0,
    tank = tonumber(damage.tank) or 1000.0,
    doors = {}, windows = {}, tyres = {},
    deformed = type(damage.deform) == 'table' and next(damage.deform) ~= nil,
  }
  for key, broken in pairs(type(damage.doors) == 'table' and damage.doors or {}) do
    local i = indexOf(key)
    if i and broken == true then out.doors[#out.doors + 1] = i end
  end
  for key, broken in pairs(type(damage.windows) == 'table' and damage.windows or {}) do
    local i = indexOf(key)
    if i and broken == true then out.windows[#out.windows + 1] = i end
  end
  for key, state in pairs(type(damage.tyres) == 'table' and damage.tyres or {}) do
    local i, v = indexOf(key), tonumber(state)
    if i and (v == 1 or v == 2) then out.tyres[#out.tyres + 1] = { index = i, state = v } end
  end
  table.sort(out.doors); table.sort(out.windows)
  table.sort(out.tyres, function(a, b) return a.index < b.index end)
  return out
end

local MOD_KEYS = { engine = 'modEngine', brakes = 'modBrakes', transmission = 'modTransmission',
  suspension = 'modSuspension', armor = 'modArmor' }

--- Installed performance upgrades (ModSummary in types.ts): level 0 = stock.
---@param props table|nil
---@return table|nil
function Vehicles.modSummary(props)
  if type(props) ~= 'table' then return nil end
  local out = { turbo = props.modTurbo == true or props.modTurbo == 1 }
  for name, key in pairs(MOD_KEYS) do
    local v = tonumber(props[key])
    out[name] = (v and v >= 0) and (math.floor(v) + 1) or 0
  end
  return out
end

function Vehicles.toGarageVehicle(row, ctx)
  ctx = Vehicles.ensureContext(ctx)
  local plate = row.plate or Utils.plate(row.dbPlate) or ''
  local identifier = ctx.identifier
  local session = ctx.session
  local isOwner = identifier ~= nil and row.owner == identifier
  local sharedWithViewer = (not isOwner) and ctx.shared[plate] == true
  local access = Vehicles.accessOf(ctx.src, row, session, ctx)
  local drivable, reason = evaluate(ctx.src, row, session, ctx, false, access or false)
  local state = row.state or 'garaged'

  local canRecover = false
  if state == 'out' and access and not row.blocked then
    local out, entity = Vehicles.isOut(plate)
    -- a destroyed / sunk vehicle nobody sits in can be recovered as well (it can never be
    -- driven back, and server-created entities are kept until someone deletes them)
    canRecover = (not out) or (entity ~= nil and not isOccupied(entity) and isWrecked(entity))
  end

  local ownerName = ownerNameOf(row, ctx)
  local sharedWith = 0
  if isOwner and plate ~= '' then
    if type(ctx.shareCounts) == 'table' then
      -- loaded once for the whole menu by buildGarageData
      sharedWith = tonumber(ctx.shareCounts[plate]) or 0
    else
      sharedWith = #(NZ.DB.shares.forPlate(plate) or {})
    end
  end

  local trailer = nil
  if type(row.trailer) == 'table' then
    trailer = {
      model = type(row.trailer.model) == 'string' and row.trailer.model or '',
      label = '',
      hash = toSigned(row.trailer.hash),
    }
  end

  local engine = percent(row.engine) or 100
  local nickname = (type(row.nickname) == 'string' and row.nickname ~= '') and row.nickname or nil

  return {
    plate = plate,
    model = row.model or '',
    hash = rowHash(row) or 0,
    vehicleType = Vehicles.vehicleTypeOf(row),
    nickname = nickname,
    state = state,
    garageKey = row.garageKey,
    garageName = keyName(row.garageKey, ctx),
    here = session ~= nil and row.garageKey ~= nil and row.garageKey == session.garageKey and state == 'garaged',
    fuel = percent(row.fuel) or 100,
    engine = engine,
    body = percent(row.body) or 100,
    mileage = Utils.round(tonumber(row.mileage) or 0, 1),
    favourite = ctx.favourites[plate] == true,
    isOwner = isOwner,
    ownerName = ownerName,
    sharedBy = sharedWithViewer and ownerName or nil,
    sharedWith = sharedWith,
    finance = type(row.finance) == 'table' and row.finance or nil,
    impound = type(row.impound) == 'table' and row.impound or nil,
    trailer = trailer,
    canDrive = drivable == true,
    reason = reason,
    canRecover = canRecover,
    recoverFee = ctx.recoverFee,
    needsService = engine < ctx.needsServiceBelow,
    blocked = row.blocked == true,
    lastUsed = tonumber(row.lastOut),
    damage = Vehicles.damageSummary(row.damage),
    mods = Vehicles.modSummary(row.props),
  }
end

local function isPersonalRow(row)
  return row.ownerType == nil or row.ownerType == 'player'
end

--- Rows listed in the garage menu for this session (see §5.4 / task spec).
--- `ctx` (newContext of this request) provides the plates shared with the player.
local function collectRows(src, session, identifier, source, ctx)
  local location = session.location
  local key = session.garageKey
  local vtype = location.vehicleType or 'car'
  local rows, seen = {}, {}

  local function add(row, checkType)
    if type(row) ~= 'table' or not row.plate or seen[row.plate] then return end
    if checkType and Vehicles.vehicleTypeOf(row) ~= vtype then return end
    seen[row.plate] = true
    rows[#rows + 1] = row
  end

  if source == 'spawner' then return rows end

  if location.kind == 'job' then
    if NZ.Jobs and NZ.Jobs.ownedVehicles then
      for _, row in ipairs(NZ.Jobs.ownedVehicles(src, location) or {}) do add(row, false) end
    end
    return rows
  end

  if not identifier then return rows end

  if location.kind == 'private' and location.storage == 'shared' then
    for _, row in ipairs(NZ.DB.getVehiclesInGarage(key) or {}) do add(row, false) end
  end

  for _, row in ipairs(NZ.DB.getVehiclesByOwner(identifier) or {}) do
    if row.garageKey == key then
      add(row, false)
    elseif isPersonalRow(row) then
      add(row, true)
    end
  end

  if location.kind ~= 'private' then
    local plates = {}
    local shared = type(ctx) == 'table' and type(ctx.shared) == 'table' and ctx.shared or sharedPlateSet(identifier)
    for plate in pairs(shared) do plates[#plates + 1] = plate end
    if #plates > 0 then
      local found = {}
      for _, row in ipairs(NZ.DB.getVehiclesByPlates(plates) or {}) do
        if row.plate then found[row.plate] = true end
        add(row, true)
      end
      -- Shares of a vehicle another resource deleted: drop them (confirmed missing only;
      -- plateExists answers true on database errors) so every open does not look them up
      -- again, and a vehicle created later with the same plate is not shared by accident.
      for _, plate in ipairs(plates) do
        if not found[plate] and NZ.DB.plateExists(plate) == false then
          NZ.DB.shares.clear(plate)
          if shared[plate] then shared[plate] = nil end
          Utils.debug('removed the shares of missing vehicle', plate)
        end
      end
    end
  end

  return rows
end

local function garageOptions()
  return {
    retrieveMode = setting('garages.retrieveMode', 'last') == 'anywhere' and 'anywhere' or 'last',
    garageTransfer = setting('transfers.garageEnabled', true) == true,
    playerTransfer = setting('transfers.playerEnabled', true) == true,
    sell = setting('transfers.sellEnabled', true) == true,
    share = setting('transfers.shareEnabled', true) == true,
    garageFee = math.max(0, toInt(setting('transfers.garageFee', 0)) or 0),
    playerFee = math.max(0, toInt(setting('transfers.playerFee', 0)) or 0),
  }
end

--- Full garage menu payload for the session (types.ts GarageOpenData).
---@param src number
---@param session table
---@return table GarageOpenData
function Vehicles.buildGarageData(src, session)
  local location = session.location
  local key = session.garageKey
  local identifier = NZ.Bridge.getIdentifier(src)
  local kind = location.kind
  local source = sourceOf(location)
  local groupId = kind == 'private' and groupIdOf(session) or nil

  local role = nil
  if groupId and identifier then role = NZ.Private.role(groupId, identifier) end

  local groups = {}
  if kind == 'private' and identifier then
    for _, group in ipairs(NZ.Private.groupsFor(identifier, location.id) or {}) do
      groups[#groups + 1] = { id = tonumber(group.id), label = group.label or location.name }
    end
  end

  local canGoInside = false
  local access = type(location.access) == 'table' and location.access or nil
  if access and access.mode ~= 'quick' and access.interiorId and NZ.Interiors and NZ.Interiors.get then
    local interior = NZ.Interiors.get(access.interiorId)
    -- an interior without vehicle slots shows no vehicle: use the quick menu instead
    canGoInside = type(interior) == 'table' and interior.enabled ~= false
      and type(interior.slots) == 'table' and #interior.slots > 0
  end

  local canManage = role == 'owner'
  local canSellGarage = false
  if canManage then canSellGarage = (tonumber(NZ.DB.countInGarage(key, nil)) or 0) == 0 end

  local jobLabel = nil
  if kind == 'job' then
    local info
    if location.owner == 'gang' then
      info = NZ.Bridge.getGang and NZ.Bridge.getGang(src) or nil
    else
      info = NZ.Bridge.getJob(src)
    end
    jobLabel = type(info) == 'table' and info.label or nil
  end

  local ctx = Vehicles.newContext(src, session, identifier)
  local rows = collectRows(src, session, identifier, source, ctx)
  -- Share counts of the viewer's own vehicles in one query (not one per vehicle).
  local owned = {}
  for _, row in ipairs(rows) do
    if identifier and row.owner == identifier and row.plate then owned[#owned + 1] = row.plate end
  end
  if type(NZ.DB.shares.counts) == 'function' then
    ctx.shareCounts = #owned > 0 and NZ.DB.shares.counts(owned) or {}
  end
  local vehicles = {}
  for _, row in ipairs(rows) do
    vehicles[#vehicles + 1] = Vehicles.toGarageVehicle(row, ctx)
  end
  table.sort(vehicles, function(a, b)
    if a.here ~= b.here then return a.here end
    return a.plate < b.plate
  end)

  local spawner = {}
  if source == 'spawner' and NZ.Jobs and NZ.Jobs.spawnerList then
    spawner = NZ.Jobs.spawnerList(src, location) or {}
  end

  return {
    garage = {
      key = key,
      locationId = location.id,
      kind = kind,
      name = keyName(key, ctx) or location.name,
      vehicleType = location.vehicleType or 'car',
      source = source,
      isPrivate = kind == 'private',
      groupId = groupId,
      groups = groups,
      role = role,
      canGoInside = canGoInside,
      canManage = canManage,
      canSellGarage = canSellGarage,
      jobLabel = jobLabel,
    },
    capacity = NZ.Locations.capacity(location, key, identifier),
    vehicles = vehicles,
    spawner = spawner,
    options = garageOptions(),
  }
end

---------------------------------------------------------------------------------------
-- Spawning
---------------------------------------------------------------------------------------

local function vehiclePositions()
  local list = {}
  for _, entity in ipairs(GetAllVehicles() or {}) do
    if DoesEntityExist(entity) then list[#list + 1] = GetEntityCoords(entity) end
  end
  return list
end

local function spotFree(point, positions)
  for i = 1, #positions do
    if Utils.dist(point, positions[i]) < SPAWN_CLEARANCE then return false end
  end
  return true
end

--- Requested spawn point when free, else the first free one. nil when all are taken.
local function pickSpawn(points, wanted)
  if type(points) ~= 'table' or #points == 0 then return nil, nil end
  local positions = vehiclePositions()
  local index = toInt(wanted, 1, #points) or 1
  local point = Utils.v4(points[index])
  if point and spotFree(point, positions) then return index, point end
  for i = 1, #points do
    local candidate = Utils.v4(points[i])
    if candidate and spotFree(candidate, positions) then return i, candidate end
  end
  return nil, nil
end

--- Create a vehicle on the server and attach the 'nzInit' (replicated) and 'nzPlate'
--- state bags the client uses to finish it (props, damage, fuel, trailer ...).
---@param hash number model hash
---@param entityType string automobile|bike|boat|heli|plane|submarine|trailer|train
---@param coords table {x,y,z,w}
---@param init table { plate, props, damage, fuel, engine, body, mileage, trailer }
---@param bucket number|nil routing bucket for the entity
---@param noPlateBag boolean|nil true: no 'nzPlate' bag / plate tracking (a saved trailer is
---                  not a registered vehicle)
---@return number|nil entity, number|nil netId
function Vehicles.spawnServer(hash, entityType, coords, init, bucket, noPlateBag)
  local point = Utils.v4(coords)
  hash = toSigned(hash)
  if not point or not hash then return nil, nil end
  if not ENTITY_TYPES[entityType] then entityType = 'automobile' end
  init = type(init) == 'table' and init or {}

  local entity = CreateVehicleServerSetter(hash, entityType, point.x + 0.0, point.y + 0.0, point.z + 0.0, point.w + 0.0)
  if not entity or entity == 0 then return nil, nil end

  local deadline = GetGameTimer() + 5000
  while not DoesEntityExist(entity) do
    if GetGameTimer() > deadline then return nil, nil end
    Wait(50)
  end

  local prepared, err = pcall(function()
    if bucket then SetEntityRoutingBucket(entity, bucket) end
    if SetEntityOrphanMode then SetEntityOrphanMode(entity, 2) end
    if type(init.plate) == 'string' then SetVehicleNumberPlateText(entity, init.plate) end
    local bag = Entity(entity).state
    bag:set('nzInit', init, true)
    local plate = Utils.plate(init.plate)
    if plate and not noPlateBag then
      bag:set('nzPlate', plate, true)
      entityPlates[entity] = plate
    end
  end)
  if not prepared then
    lib.print.error(('[nayzeee-garages] server spawn setup failed: %s'):format(err))
    deleteVehicle(entity)
    return nil, nil
  end
  return entity, NetworkGetNetworkIdFromEntity(entity)
end

--- Server-create the saved trailer of a server-spawned vehicle TRAILER_BACK metres behind
--- the spawn point. Its own 'nzInit' (plate, props, damage) is applied by its owner client;
--- the client that finishes the vehicle moves it onto the hitch and attaches it.
---@return number|nil entity, number|nil netId
local function spawnServerTrailer(trailer, spawn, bucket)
  local hash = trailerHashOf(trailer)
  local point = Utils.v4(spawn)
  if not hash or not point then return nil, nil end
  local heading = math.rad(tonumber(point.w) or 0.0)
  -- GTA headings: forward = (-sin h, cos h); behind = point - forward * distance
  local coords = {
    x = point.x + math.sin(heading) * TRAILER_BACK,
    y = point.y - math.cos(heading) * TRAILER_BACK,
    z = point.z,
    w = point.w,
  }
  local init = {
    plate = trailerPlateOf(trailer),
    props = type(trailer.props) == 'table' and trailer.props or nil,
    damage = trailer.damage,
    isTrailer = true,
  }
  local entity, netId = Vehicles.spawnServer(hash, 'trailer', coords, init, bucket, true)
  -- Frozen until the client that hitches it moves it (client/vehicle.lua hitchServerTrailer
  -- unfreezes it): no physics push on the truck or on whatever stands behind the spot.
  if entity then
    FreezeEntityPosition(entity, true)
    -- safety net: a trailer no client could take control of does not stay frozen forever
    SetTimeout(TRAILER_UNFREEZE_MS, function()
      if DoesEntityExist(entity) then FreezeEntityPosition(entity, false) end
    end)
  end
  return entity, netId
end

---------------------------------------------------------------------------------------
-- Retrieve (§7.1)
---------------------------------------------------------------------------------------

local function charge(src, amount, reason)
  if amount <= 0 then return true, nil end
  local paid, account = NZ.Bridge.pay(src, amount, reason)
  if not paid then return false, nil end
  return true, account
end

local function refund(src, amount, account, reason)
  if amount <= 0 then return end
  if not NZ.Bridge.addMoney(src, account or 'bank', amount, reason) then
    log('security.refund', src, { amount = amount, account = account, reason = reason })
  end
end

local function doRetrieve(src, plate, session, opts)
  local identifier = NZ.Bridge.getIdentifier(src)
  if not identifier then return fail(L('Your character is not loaded')) end

  local row = NZ.DB.getVehicle(plate)
  if not row then return fail(L('Vehicle not found')) end
  if opts.fromImpound and row.state ~= 'impounded' then return fail(L('This vehicle is not impounded')) end

  -- Impound staff (validated by server/impound.lua) may release vehicles they do not own.
  local access = (opts.fromImpound and opts.staff == true) and 'staff' or nil
  local allowed, reason = evaluate(src, row, session, { identifier = identifier }, opts.fromImpound == true, access)
  if not allowed then return fail(reason) end

  if Vehicles.isOut(plate) then return fail(L('Vehicle is already out')) end

  local hash = rowHash(row)
  if not hash then return fail(L('Unknown vehicle model')) end

  -- An untracked entity of this vehicle (same model) is a duplicate: remove it when nobody
  -- uses it. Another model showing this plate text is somebody else's car (fake plate).
  local stray = findEntityByPlate(plate, hash)
  if stray then
    if isOccupied(stray) then
      log('security.dupe', src, { plate = plate, reason = 'retrieve while an occupied copy exists' })
      return fail(L('Vehicle is already out'))
    end
    -- still on its way to the impound on the NPC tow truck: not a duplicate (NZ.Tow.release
    -- deletes it and the truck leaves empty)
    local tow = NZ.Tow
    local released = type(tow) == 'table' and type(tow.isTowing) == 'function' and type(tow.release) == 'function'
      and tow.isTowing(stray) and tow.release(stray)
    if not released then
      deleteVehicle(stray)
      log('security.dupe', src, { plate = plate, reason = 'removed an untracked copy before retrieve' })
    end
  end

  local points = session.location.spawnPoints
  if type(points) ~= 'table' or #points == 0 then return fail(L('This garage has no parking spots')) end
  local spawnIndex, spawn = pickSpawn(points, opts.spawnIndex)
  if not spawnIndex then return fail(L('All parking spots are occupied')) end

  -- Derived server-side (never the client's word alone); nil = let the client create it.
  local entityType = Vehicles.resolveEntityType(hash, opts.entityType, Vehicles.vehicleTypeOf(row))
  local fee = math.max(0, toInt(opts.fee) or 0)

  -- The saved trailer comes out with the vehicle. It needs a plate the server can recognise
  -- it by later (recover / impound remove it, no other vehicle may absorb it).
  local trailer, trailerParked = nil, false
  if setting('vehicles.trailers', true) and type(row.trailer) == 'table' then
    trailer = row.trailer
    if not trailerPlateOf(trailer) then
      trailer = Utils.deepCopy(row.trailer)
      trailer.props = type(trailer.props) == 'table' and trailer.props or {}
      trailer.props.plate = Utils.generatePlate('TR*****')
    end
    -- Parked separately: its entity is still where it was left, never a second copy.
    trailerParked = findSavedTrailer(trailer) ~= nil
  end
  -- What the client (or the server spawn) creates behind the vehicle.
  local trailerSpawn = nil
  if trailer and not trailerParked then
    trailerSpawn = {}
    for k, v in pairs(trailer) do trailerSpawn[k] = v end
    if not setting('vehicles.saveDamage', true) then trailerSpawn.damage = nil end
  end

  local paid, account = charge(src, fee, 'nayzeee-garages:retrieve')
  if not paid then return fail(L('You cannot afford this ({amount})', { amount = money(fee) })) end

  local now = os.time()
  local fields = { state = 'out', lastOut = now }
  if opts.fromImpound then fields.impound = false end
  if trailer and trailer ~= row.trailer then fields.trailer = trailer end
  if not NZ.DB.updateVehicle(plate, fields) then
    refund(src, fee, account, 'nayzeee-garages:retrieve-refund')
    return fail(L('Something went wrong'))
  end

  local function rollback(why)
    local entry = Vehicles.out[plate]
    if entry and entry.entity then deleteVehicle(entry.entity) end
    if entry and entry.trailerEntity then deleteVehicle(entry.trailerEntity) end
    Vehicles.clearOut(plate)
    -- the database record is unchanged: it stays this vehicle's saved trailer
    untrackTrailers(plate)
    if type(row.trailer) == 'table' then trackTrailer(plate, row.trailer) end
    local restore = { state = row.state or 'garaged', lastOut = row.lastOut or false }
    if opts.fromImpound then restore.impound = row.impound or false end
    NZ.DB.updateVehicle(plate, restore)
    refund(src, fee, account, 'nayzeee-garages:retrieve-refund')
    log('vehicle.retrieve', src, { plate = plate, garage = session.garageKey, rolledBack = true, reason = why })
  end

  Vehicles.setOut(plate, {
    src = src,
    identifier = identifier,
    garageKey = row.garageKey or session.garageKey,
    at = now,
    spawner = false,
    job = select(2, Vehicles.fleetOf(row)),
    -- trailerSeen: the server saw an entity of its saved trailer while the vehicle was out;
    -- only then may a store without it drop the record (doStore)
    trailerExpected = trailerSpawn ~= nil or nil,
    trailerSeen = trailerParked or nil,
  })

  local built, result = pcall(function()
    local vehicle = {
      plate = plate,
      hash = hash,
      model = row.model or '',
      props = type(row.props) == 'table' and row.props or {},
      damage = setting('vehicles.saveDamage', true) and row.damage or nil,
      fuel = percent(row.fuel) or 100,
      engine = percent(row.engine) or 100,
      body = percent(row.body) or 100,
      mileage = tonumber(row.mileage) or 0,
      trailer = trailerSpawn,
    }

    if setting('vehicles.serverSpawn', false) and entityType then
      local bucket = GetPlayerRoutingBucket(src)
      local entry = Vehicles.out[plate]
      -- The trailer first: the vehicle's 'nzInit' tells its client which entity to hitch.
      -- When it cannot be created here, that client creates it (vehicle.trailer without netId).
      if trailerSpawn then
        local tEntity, tNetId = spawnServerTrailer(trailerSpawn, spawn, bucket)
        if tEntity then
          if entry then
            entry.trailerEntity = tEntity
            entry.trailerSeen = true
          end
          local hitch = {}
          for k, v in pairs(trailerSpawn) do hitch[k] = v end
          hitch.netId = tNetId
          vehicle.trailer = hitch
        end
      end
      local entity, netId = Vehicles.spawnServer(hash, entityType, spawn, vehicle, bucket)
      if not entity then return nil end
      if entry then
        entry.entity = entity
        entry.netId = netId
      end
      return { netId = netId, spawn = spawn, spawnIndex = spawnIndex, vehicle = vehicle }
    end
    return { spawn = spawn, spawnIndex = spawnIndex, vehicle = vehicle }
  end)

  if not built or not result then
    rollback(built and 'spawn failed' or tostring(result))
    return fail(L('The vehicle could not be spawned'))
  end
  if trailer then trackTrailer(plate, trailer) end
  if trailerParked then
    NZ.Bridge.notify(src, L('Your trailer is still where you parked it'), 'info')
  end

  log('vehicle.retrieve', src, {
    plate = plate,
    garage = session.garageKey,
    garageName = NZ.Locations.keyName(session.garageKey),
    fee = fee,
    fromImpound = opts.fromImpound == true,
    fromInterior = opts.fromInterior == true,
    serverSpawn = result.netId ~= nil,
    trailer = trailerParked and 'parked' or (trailerSpawn and 'spawned') or nil,
  })
  return ok(result)
end

--- Take a vehicle out of the garage (§7.1). Re-checks session distance unless
--- `opts.fromInterior`, rate limits, validates permission and charges `opts.fee`.
---@param src number
---@param plate string
---@param session table|nil session to use (nil = the player's current session)
---@param opts table|nil { spawnIndex, entityType, fromInterior, fromImpound, fee }
---@return table result ok({ spawn, vehicle, netId? }) | fail
function Vehicles.retrieve(src, plate, session, opts)
  opts = type(opts) == 'table' and opts or {}
  plate = readPlate(plate)
  if not plate then return fail(L('Invalid vehicle')) end

  if opts.fromInterior then
    session = session or NZ.Access.getSession(src)
    if type(session) ~= 'table' then return fail(L('The garage is not open')) end
  elseif type(session) == 'table' then
    if not NZ.Access.nearLocation(src, session.location, maxDistance()) then return fail(L('You are too far from the garage')) end
  else
    local err
    session, err = NZ.Access.requireSession(src, maxDistance())
    if not session then return fail(err or L('The garage is not open')) end
  end
  if type(session.location) ~= 'table' then return fail(L('The garage is not open')) end
  -- The ped would be warped into the vehicle: not while dead, downed, cuffed or escorted.
  if Vehicles.incapacitated(src) then return fail(L('You cannot do that right now')) end

  if not NZ.Access.rateLimit(src, 'vehicles:retrieve', 1500) then
    return fail(L('Please wait a moment before trying again'))
  end
  return Vehicles.withLock(plate, doRetrieve, src, plate, session, opts)
end

--- Record the entity a client created for a retrieved vehicle (validated server-side).
---@param src number
---@param plate string
---@param netId number
---@return boolean success, string|nil error
function Vehicles.markSpawned(src, plate, netId)
  plate = readPlate(plate)
  netId = toInt(netId, 1)
  if not plate or not netId then return false, L('Invalid vehicle') end
  local entry = Vehicles.out[plate]
  if not entry or entry.src ~= src then return false, L('This vehicle was not taken out by you') end

  -- The client reports in the frame it created the vehicle: give the clone (and its plate)
  -- time to reach the server instead of rejecting a legitimate spawn.
  local entity, plateMatches = awaitVehicle(netId, plate, AWAIT_ENTITY_MS)
  if not entity then return false, L('Vehicle not found') end
  if not plateMatches then
    log('security.plate', src, { plate = plate, netId = netId, reason = 'spawned entity plate mismatch' })
    return false, L('Vehicle not found')
  end
  -- Re-read: the entry may have been cleared or replaced while waiting.
  entry = Vehicles.out[plate]
  if not entry or entry.src ~= src then return false, L('This vehicle was not taken out by you') end

  local row = nil
  if not entry.spawner then
    row = NZ.DB.getVehicle(plate)
    if not row or row.state ~= 'out' then return false, L('This vehicle is not out') end
    -- the reported entity must be the stored model (fake plates / phone deliveries)
    local want = rowHash(row)
    if want and want ~= 0 and toSigned(GetEntityModel(entity)) ~= want then
      log('security.model', src, { plate = plate, netId = netId, expected = want,
        actual = toSigned(GetEntityModel(entity)), reason = 'spawned entity model mismatch' })
      return false, L('This vehicle does not match its registration')
    end
  end

  if entry.entity and entry.entity ~= entity and isVehicleEntity(entry.entity) then
    deleteVehicle(entity)
    log('security.dupe', src, { plate = plate, netId = netId, reason = 'second entity reported for one retrieve' })
    return false, L('Vehicle is already out')
  end

  if entry.entity and entry.entity ~= entity then entityPlates[entry.entity] = nil end
  entry.netId = netId
  entry.entity = entity
  entry.spawnedAt = os.time()
  entityPlates[entity] = plate
  learnEntityType(entity)
  local bag = Entity(entity).state
  bag:set('nzPlate', plate, true)
  -- The client's own first write may have raced the entity's creation on the server.
  if row and bag.nzMileage == nil then bag:set('nzMileage', tonumber(row.mileage) or 0, true) end
  -- its trailer is normally created (and networked) before the vehicle is reported
  if row and entry.trailerExpected and not entry.trailerSeen and type(row.trailer) == 'table'
    and findSavedTrailer(row.trailer) then
    entry.trailerSeen = true
  end

  if setting('vehicles.giveKeys', true) and NZ.KeysServer and NZ.KeysServer.give then
    local given, err = pcall(NZ.KeysServer.give, src, netId, plate)
    if not given then lib.print.warn(('[nayzeee-garages] key hand-out failed for %s: %s'):format(plate, err)) end
  end
  return true, nil
end

--- The client could not create a vehicle it retrieved: put it back where it was, unless any
--- copy of it exists on the server (prevents using a fake failure report to duplicate).
---@param src number
---@param plate string
---@return boolean released, string|nil error
function Vehicles.spawnFailed(src, plate)
  plate = readPlate(plate)
  if not plate then return false, L('Invalid vehicle') end
  local entry = Vehicles.out[plate]
  if not entry or entry.src ~= src then return false, L('This vehicle was not taken out by you') end
  if entry.entity and isVehicleEntity(entry.entity) then return false, L('Vehicle is already out') end
  local stored = not entry.spawner and NZ.DB.getVehicle(plate) or nil
  if findEntityByPlate(plate, stored and rowHash(stored) or nil) then return false, L('Vehicle is already out') end
  if (os.time() - (entry.at or 0)) > 120 then return false, L('This vehicle was not taken out by you') end

  if entry.spawner then
    -- refunds a paid spawner / rental vehicle and frees its slot
    if NZ.Jobs and NZ.Jobs.spawnFailed then
      pcall(NZ.Jobs.spawnFailed, plate, src)
    elseif NZ.Jobs and NZ.Jobs.release then
      pcall(NZ.Jobs.release, plate)
    end
    Vehicles.clearOut(plate)
    return true, nil
  end
  local done, err = Vehicles.withLock(plate, function()
    local row = NZ.DB.getVehicle(plate)
    Vehicles.clearOut(plate)
    -- the database record is unchanged: it stays this vehicle's saved trailer
    untrackTrailers(plate)
    if row and type(row.trailer) == 'table' then trackTrailer(plate, row.trailer) end
    if row and row.state == 'out' then
      NZ.DB.updateVehicle(plate, { state = 'garaged' })
      log('vehicle.spawnFailed', src, { plate = plate, garage = row.garageKey })
    end
    return true, nil
  end)
  if type(done) == 'table' then return false, done.error end -- lock busy result
  return done == true, err
end

---------------------------------------------------------------------------------------
-- Store (§7.2)
---------------------------------------------------------------------------------------

local function storePointsOf(location)
  if location.useOpenForStore ~= false or type(location.storePoints) ~= 'table' or #location.storePoints == 0 then
    return type(location.openPoints) == 'table' and location.openPoints or {}
  end
  return location.storePoints
end

--- The driver (server ped position) is at a store point of the location, or anywhere inside
--- its garage zone (no store circle needed there).
local function nearStorePoint(src, location)
  local pos = pedCoords(src)
  if not pos then return false end
  if type(location.zone) == 'table' and NZ.Access.inZone(src, location) then return true end
  for _, point in ipairs(storePointsOf(location)) do
    local coords = Utils.v3(type(point) == 'table' and point.coords or point)
    if coords then
      local radius = tonumber(type(point) == 'table' and point.radius) or 4.0
      if Utils.dist(pos, coords) <= math.max(radius + 4.0, 8.0) then return true end
    end
  end
  return false
end

local function returnToOf(location)
  if not location.returnToEntrance then return nil end
  local point = type(location.openPoints) == 'table' and location.openPoints[1] or nil
  if type(point) ~= 'table' then return nil end
  return Utils.v4(point.coords or point)
end

--- Validate and package the trailer of `vehicle` (plate `plate`, database row `row`):
--- a trailer hitched to it, or its own saved trailer standing loose nearby. Returns entity,
--- data (saved with the vehicle) or entity, nil, trailerRow when the trailer is a registered
--- vehicle of its own (it is parked separately), or nil.
local function collectTrailer(src, vehicle, info, saveDamage, saveDeformation, plate, row)
  if type(info) ~= 'table' then return nil, nil end
  local netId = toInt(info.netId, 1)
  if not netId then return nil, nil end
  local trailer = NetworkGetEntityFromNetworkId(netId)
  if not isVehicleEntity(trailer) or trailer == vehicle or isOccupied(trailer) then return nil, nil end

  local vtype = GetVehicleType(trailer)
  if type(vtype) == 'string' and vtype ~= 'trailer' then return nil, nil end

  -- The saved trailer of another vehicle belongs to that vehicle.
  local key = trailerKeyOfEntity(trailer)
  local owner = key and trailerOwners[key] or nil
  if owner and owner ~= plate then return nil, nil end

  local attachedTo = GetEntityAttachedTo(trailer)
  if attachedTo ~= vehicle then
    -- hitched to something else (another truck, a tow truck, a cargobob)
    if attachedTo and attachedTo ~= 0 and DoesEntityExist(attachedTo) then return nil, nil end
    -- The server does not always see the hitch (attachment not replicated yet): a trailer
    -- right behind the vehicle counts as hitched; its own saved trailer within TRAILER_RANGE.
    local own = key ~= nil and (owner == plate or key == trailerKeyOfData(type(row) == 'table' and row.trailer or nil))
    local vPos, tPos = GetEntityCoords(vehicle), GetEntityCoords(trailer)
    if not own then
      -- Any other loose trailer only counts when the server can tell it is on this hitch:
      -- the storing client drives it (a towed trailer migrates to the truck's driver), it
      -- stands behind the truck and points roughly the same way (a jackknife stays < 90).
      if NetworkGetEntityOwner(trailer) ~= src then return nil, nil end
      local h = math.rad(tonumber(GetEntityHeading(vehicle)) or 0.0)
      local fx, fy = -math.sin(h), math.cos(h)
      if (tPos.x - vPos.x) * fx + (tPos.y - vPos.y) * fy > 0.0 then return nil, nil end
      local diff = math.abs(((tonumber(GetEntityHeading(trailer)) or 0.0) - math.deg(h) + 180.0) % 360.0 - 180.0)
      if diff > HITCH_ANGLE then return nil, nil end
    end
    local range = own and TRAILER_RANGE or HITCH_RANGE
    if Utils.dist(tPos, vPos) > range then return nil, nil end
  end

  -- A trailer that is a registered vehicle of its own is never absorbed: it is parked as
  -- itself (doStore). A spawner / rental one stays out.
  local trailerPlate = identityOf(trailer)
  if trailerPlate then
    local trailerRow = NZ.DB.getVehicle(trailerPlate)
    if trailerRow then return trailer, nil, trailerRow end
    if Vehicles.out[trailerPlate] then return nil, nil end
  end

  local hash = toSigned(GetEntityModel(trailer))
  if not hash then return nil, nil end
  return trailer, {
    hash = hash,
    model = Utils.cleanText(info.model, 32),
    props = sanitize(info.props, MAX_PROPS_BYTES),
    damage = saveDamage and sanitizeDamage(info.damage, saveDeformation) or nil,
  }
end

--- A fake plate comes off before a vehicle goes into a garage (the item goes back to the
--- player with Config.FakePlates.returnOnStore). Returns true when it wore one.
local function dropFakePlate(src, entity, plate)
  if not (NZ.FakePlates and type(NZ.FakePlates.onStore) == 'function') then return false end
  local okFake, res = pcall(NZ.FakePlates.onStore, src, entity)
  if not okFake then lib.print.warn(('[nayzeee-garages] fake plate on store failed for %s: %s'):format(plate, tostring(res))) end
  return okFake and res == true
end

local function doStore(src, session, entity, plate, payload)
  local location = session.location
  local key = session.garageKey
  local identifier = NZ.Bridge.getIdentifier(src)
  if not identifier then return fail(L('Your character is not loaded')) end
  local data = type(payload.data) == 'table' and payload.data or {}

  -- Spawner vehicles (rentals, job spawns): returning = deleting + releasing the slot.
  if NZ.Jobs and NZ.Jobs.isSpawnerVehicle then
    local isSpawner, info = NZ.Jobs.isSpawnerVehicle(plate)
    if isSpawner then
      dropFakePlate(src, entity, plate)
      deleteVehicle(entity)
      Vehicles.clearOut(plate)
      if NZ.Jobs.release then
        local released, err = pcall(NZ.Jobs.release, plate)
        if not released then lib.print.warn(('[nayzeee-garages] spawner release failed for %s: %s'):format(plate, err)) end
      end
      log('vehicle.store', src, {
        plate = plate, garage = key, spawner = true,
        job = type(info) == 'table' and info.job or nil,
      })
      return ok({ returnTo = returnToOf(location) })
    end
  end

  local row = NZ.DB.getVehicle(plate)
  if not row then return fail(L('This vehicle is not registered to anyone')) end

  -- Duplication guard: an entity of a vehicle that is already in a garage cannot exist.
  if row.state == 'garaged' then
    deleteVehicle(entity)
    Vehicles.clearOut(plate)
    log('security.dupe', src, {
      plate = plate, garage = key, owner = row.owner, storedAt = row.garageKey,
      reason = 'tried to store a vehicle that is already garaged',
    })
    return fail(L('This vehicle is already stored'))
  end
  if row.state == 'impounded' then
    log('security.impounded', src, { plate = plate, garage = key, reason = 'tried to store an impounded vehicle' })
    return fail(L('This vehicle is impounded'))
  end

  local storable, notStorable = storableHere(row, location)
  if not storable then return fail(notStorable) end

  if setting('garages.storeOnlyOwned', true) then
    if not Vehicles.accessOf(src, row, session, { identifier = identifier }) then
      return fail(L('You cannot store a vehicle you do not own'))
    end
  end
  if not ownerCanReach(row, key) then return fail(L('The owner of this vehicle cannot use this garage')) end

  local entityHash = toSigned(GetEntityModel(entity))
  local expected = rowHash(row)
  if setting('vehicles.checkModel', true) and expected and entityHash and expected ~= entityHash then
    log('security.model', src, { plate = plate, expected = expected, actual = entityHash })
    return fail(L('This vehicle does not match its registration'))
  end
  if isBlacklisted(expected or entityHash) then return fail(L('This vehicle cannot be stored in a garage')) end

  local category = categoryOfEntity(entity) or Vehicles.vehicleTypeOf(row)
  if category ~= (location.vehicleType or 'car') then return fail(L('Wrong vehicle type for this garage')) end

  local capacity = NZ.Locations.capacity(location, key, row.owner or identifier)
  if not hasSpace(capacity) then
    if setting('garages.suggestWhenFull', true) then
      return { ok = false, error = L('This garage is full'), data = { full = true } }
    end
    return fail(L('This garage is full'))
  end

  local saveDamage = setting('vehicles.saveDamage', true) == true
  local saveDeformation = saveDamage and setting('vehicles.saveDeformation', true) == true
  local plateText = row.dbPlate or plate
  local fields = {
    state = 'garaged',
    garageKey = key,
    garageName = keyName(key) or location.name,
  }

  if setting('vehicles.saveMods', true) then
    local props = sanitize(data.props, MAX_PROPS_BYTES)
    if props then
      props.plate = plateText
      if props.model ~= nil and expected then props.model = expected end
      fields.props = props
    end
  elseif type(row.props) == 'table' and Utils.plate(row.props.plate) ~= plate then
    local props = Utils.deepCopy(row.props)
    props.plate = plateText
    fields.props = props
  end

  -- Health and fuel: the server's view of the entity is the authority. A client may report
  -- more damage than the server sees, never less (no free repairs / refuels).
  local rawEngine = tonumber(GetVehicleEngineHealth(entity))
  local rawBody = tonumber(GetVehicleBodyHealth(entity))
  local rawTank = GetVehiclePetrolTankHealth and tonumber(GetVehiclePetrolTankHealth(entity)) or nil
  local function atMost(reported, server)
    if reported and server then return math.min(reported, server) end
    return reported or server
  end
  local fuel = percent(Entity(entity).state.fuel) or percent(data.fuel)
  if fuel then fields.fuel = fuel end
  local engine = atMost(percent(data.engine), rawEngine and percent(rawEngine / 10) or nil)
  if engine then fields.engine = engine end
  local body = atMost(percent(data.body), rawBody and percent(rawBody / 10) or nil)
  if body then fields.body = body end
  if fields.props and rawTank and tonumber(fields.props.tankHealth) then
    fields.props.tankHealth = math.min(tonumber(fields.props.tankHealth), rawTank)
  end

  local reported = tonumber(data.mileage)
  if reported and reported == reported then
    local current = tonumber(row.mileage) or 0
    local since = os.time() - (tonumber(row.lastOut) or (os.time() - 86400))
    local maxGain = math.max(10, since / 3600 * 600)
    fields.mileage = Utils.round(Utils.clamp(reported, current, current + maxGain), 2)
  end

  if saveDamage then
    local damage = sanitizeDamage(data.damage, saveDeformation)
    if damage then
      if rawEngine then damage.engine = atMost(tonumber(damage.engine), rawEngine) end
      if rawBody then damage.body = atMost(tonumber(damage.body), rawBody) end
      if rawTank then damage.tank = atMost(tonumber(damage.tank), rawTank) end
      fields.damage = damage
    end
  end

  -- Trailer: the one hitched to the vehicle is saved with it (and replaces its saved trailer).
  -- Without one, its own saved trailer standing close by goes in with it; one parked further
  -- away stays where it is and keeps being its saved trailer (it is not spawned a second
  -- time while it exists). One the server saw out and that no longer exists is dropped; one
  -- the client never managed to spawn is kept (it comes back on the next retrieve). A hitched
  -- trailer that is a registered vehicle of its own is parked as itself (after the vehicle).
  local trailerEntity, trailerNote, separate = nil, nil, nil
  if setting('vehicles.trailers', true) then
    local tEntity, tData, tRow = nil, nil, nil
    if type(data.trailer) == 'table' then
      tEntity, tData, tRow = collectTrailer(src, entity, data.trailer, saveDamage, saveDeformation, plate, row)
    end
    if tEntity and tData then
      trailerEntity, trailerNote = tEntity, 'stored'
      fields.trailer = tData
    elseif tEntity and tRow then
      separate = { entity = tEntity, row = tRow, info = data.trailer }
    end
    if not fields.trailer and type(row.trailer) == 'table' then
      local parked = findSavedTrailer(row.trailer)
      if parked and parked ~= entity then
        local attachedTo = GetEntityAttachedTo(parked)
        local free = not attachedTo or attachedTo == 0 or attachedTo == entity or not DoesEntityExist(attachedTo)
        if free and Utils.dist(GetEntityCoords(parked), GetEntityCoords(entity)) <= TRAILER_RANGE then
          trailerEntity, trailerNote = parked, 'stored'
        else
          trailerNote = 'parked'
        end
      elseif not parked then
        -- The trailer was out with this vehicle (the server saw its entity) and is gone now
        -- (destroyed, deleted, cleaned up): the vehicle goes in without it. One the client
        -- never managed to spawn is kept (it comes back on the next retrieve).
        local entry = Vehicles.out[plate]
        if entry and entry.trailerSeen == true then
          fields.trailer = false
          trailerNote = 'lost'
        end
      end
    end
  else
    fields.trailer = false
  end

  if row.vehicleType ~= category then fields.vehicleType = category end
  if not expected and entityHash then fields.hash = entityHash end

  if not NZ.DB.updateVehicle(plate, fields) then return fail(L('Something went wrong')) end

  -- Another live copy of this plate (tracked) is a duplicate once this one is stored.
  local tracked = Vehicles.out[plate]
  if tracked and tracked.entity and tracked.entity ~= entity and isVehicleEntity(tracked.entity) then
    log('security.dupe', src, { plate = plate, reason = 'stored while another tracked copy existed' })
    if not isOccupied(tracked.entity) then deleteVehicle(tracked.entity) end
  end

  local hadFake = dropFakePlate(src, entity, plate)

  learnEntityType(entity)
  deleteVehicle(entity)
  if trailerEntity then deleteVehicle(trailerEntity) end
  Vehicles.clearOut(plate)
  -- The saved trailer is now whatever was stored with the vehicle (or the one it had).
  if type(fields.trailer) == 'table' then
    trackTrailer(plate, fields.trailer)
  elseif fields.trailer == false then
    untrackTrailers(plate)
  elseif type(row.trailer) == 'table' then
    trackTrailer(plate, row.trailer)
  end

  log('vehicle.store', src, {
    plate = plate,
    garage = key,
    garageName = fields.garageName,
    owner = row.owner,
    fuel = fields.fuel,
    engine = fields.engine,
    body = fields.body,
    mileage = fields.mileage,
    trailer = trailerNote,
    fakePlate = hadFake or nil,
  })

  -- A registered trailer it was towing goes into the same garage as a vehicle of its own,
  -- with every check a stored vehicle gets (access, capacity, model, duplicates).
  local separateStored = nil
  if separate and payload.towing == nil then
    local tPlate = separate.row.plate
    local res = Vehicles.withLock(tPlate, doStore, src, session, separate.entity, tPlate,
      { data = separate.info, towing = plate })
    separateStored = type(res) == 'table' and res.ok == true
    if not separateStored then
      NZ.Bridge.notify(src, L('The trailer {plate} was not stored: {reason}', {
        plate = tPlate, reason = type(res) == 'table' and res.error or L('Something went wrong'),
      }), 'error')
    end
  end

  if trailerNote == 'parked' then
    NZ.Bridge.notify(src, L('Your trailer stays where you parked it'), 'info')
  end
  return ok({
    returnTo = payload.towing == nil and returnToOf(location) or nil,
    trailer = trailerNote,
    trailerStored = separateStored,
  })
end

--- Store the vehicle the player is driving into the garage of `session` (§7.2).
---@param src number
---@param session table
---@param payload table { netId, data = NZ.Veh.collect() result }
---@return table result ok({ returnTo = vec4|nil }) | fail (data.full when the garage is full)
function Vehicles.store(src, session, payload)
  payload = type(payload) == 'table' and payload or {}
  if type(session) ~= 'table' or type(session.location) ~= 'table' or not session.garageKey then
    return fail(L('The garage is not open'))
  end
  if not NZ.Access.rateLimit(src, 'vehicles:store', 1500) then
    return fail(L('Please wait a moment before trying again'))
  end

  local netId = toInt(payload.netId, 1)
  if not netId then return fail(L('Invalid vehicle')) end
  local entity = NetworkGetEntityFromNetworkId(netId)
  if not isVehicleEntity(entity) then return fail(L('Vehicle not found')) end

  local ped = GetPlayerPed(src)
  if not ped or ped == 0 or GetPedInVehicleSeat(entity, -1) ~= ped then
    return fail(L('You must be the driver to store this vehicle'))
  end
  if not nearStorePoint(src, session.location) then return fail(L('You are too far from the garage')) end

  -- the registration, also under a fake plate (it comes off in doStore)
  local plate = identityOf(entity)
  if not plate or #plate > MAX_PLATE_LENGTH then return fail(L('Invalid vehicle')) end
  return Vehicles.withLock(plate, doStore, src, session, entity, plate, payload)
end

---------------------------------------------------------------------------------------
-- Boot, adoption and clean-up (§7.5)
---------------------------------------------------------------------------------------

local function adoptExisting()
  local byPlate = {}
  for _, row in ipairs(NZ.DB.getOutVehicles() or {}) do
    if type(row) == 'table' and row.plate then
      byPlate[row.plate] = row
      -- its saved trailer may still be standing in the world
      if type(row.trailer) == 'table' then trackTrailer(row.plate, row.trailer) end
    end
  end
  local adopted = 0
  for _, entity in ipairs(GetAllVehicles() or {}) do
    if isVehicleEntity(entity) then
      -- the registration, also under a fake plate (server/fakeplates.lua restores its
      -- records before this boot step): a fake-plated car is adopted, never spawned twice
      local plate = identityOf(entity)
      local row = plate and byPlate[plate]
      if row and not Vehicles.out[plate] then
        local _, fleetName = Vehicles.fleetOf(row)
        Vehicles.setOut(plate, {
          netId = NetworkGetNetworkIdFromEntity(entity),
          entity = entity,
          src = row.owner and NZ.Bridge.getSourceByIdentifier(row.owner) or nil,
          identifier = row.owner,
          garageKey = row.garageKey,
          at = os.time(),
          spawner = false,
          job = fleetName,
          adopted = true,
          trailerSeen = type(row.trailer) == 'table' and findSavedTrailer(row.trailer) ~= nil or nil,
        })
        Entity(entity).state:set('nzPlate', plate, true)
        learnEntityType(entity)
        adopted = adopted + 1
      end
    end
  end
  lib.print.info(('[nayzeee-garages] resource restart: re-adopted %d vehicle(s) still in the world'):format(adopted))
end

--- Nearest enabled impound for a vehicle category (from `origin`), or nil.
local function nearestImpound(origin, vtype)
  local best, bestDist = nil, math.huge
  for _, location in ipairs(NZ.Locations.all('impound') or {}) do
    if location.enabled ~= false and (location.vehicleType or 'car') == vtype then
      local point = firstOpenPoint(location)
      local dist = (origin and point) and Utils.dist(origin, point) or math.huge
      if not best or dist < bestDist then best, bestDist = location, dist end
    end
  end
  return best
end

local function applyOutOnRestart()
  local mode = setting('garages.outOnRestart', 'garage')
  if mode == 'keep' then return end
  if mode == 'impound' then
    local impoundId = toInt(setting('garages.restartImpound', nil), 1)
    local location = impoundId and NZ.Locations.get(impoundId) or nil
    if type(location) == 'table' and location.kind == 'impound' then
      local now = os.time()
      local function infoFor(target)
        return {
          locationId = target.id,
          locationName = target.name,
          reason = L('Left out during a server restart'),
          fee = math.max(0, toInt(setting('garages.recoverFee', 250)) or 0),
          by = nil,
          byName = L('Server'),
          at = now,
          releaseAt = now,
          retrievable = true,
        }
      end

      -- An impound only hands out vehicles of its own category: boats / aircraft go to the
      -- nearest impound of their category, or back to their garage when there is none.
      local restartType = location.vehicleType or 'car'
      local origin = firstOpenPoint(location)
      local targets, redirected, returned = {}, 0, 0
      for _, row in ipairs(NZ.DB.getOutVehicles() or {}) do
        local vtype = Vehicles.vehicleTypeOf(row)
        if row.plate and vtype ~= restartType then
          if targets[vtype] == nil then targets[vtype] = nearestImpound(origin, vtype) or false end
          local target = targets[vtype]
          if target then
            if NZ.DB.updateVehicle(row.plate, { state = 'impounded', impound = infoFor(target) }) then
              redirected = redirected + 1
            end
          else
            local fields = { state = 'garaged' }
            if not row.garageKey and NZ.Private and NZ.Private.fallbackGarage then
              local key, name = NZ.Private.fallbackGarage(origin, vtype)
              if key then
                fields.garageKey = key
                fields.garageName = name
              end
            end
            if NZ.DB.updateVehicle(row.plate, fields) then returned = returned + 1 end
          end
        end
      end

      local count = NZ.DB.resetOutVehicles('impound', infoFor(location)) or 0
      log('vehicle.restart', nil, {
        mode = 'impound', impound = location.id, count = count,
        otherImpounds = redirected, returnedToGarage = returned,
      })
      lib.print.info(('[nayzeee-garages] server start: %d vehicle(s) left out were impounded'):format(count + redirected))
      return
    end
    lib.print.warn('[nayzeee-garages] outOnRestart is "impound" but restartImpound is not a valid impound; returning vehicles to their garage instead')
  end
  local count = NZ.DB.resetOutVehicles('garage', nil) or 0
  log('vehicle.restart', nil, { mode = 'garage', count = count })
  lib.print.info(('[nayzeee-garages] server start: %d vehicle(s) left out were returned to their garage'):format(count))
end

--- A retrieved vehicle whose trailer the client spawns: note once the server sees that
--- trailer (doStore may then drop the record when it is gone). Gives up after 5 minutes.
local function watchTrailer(plate, entry)
  if entry.spawner or not entry.trailerExpected or entry.trailerSeen then return end
  if os.time() - (tonumber(entry.at) or 0) > 300 then
    entry.trailerExpected = nil
    return
  end
  local row = NZ.DB.getVehicle(plate)
  if type(row) == 'table' and type(row.trailer) == 'table' and findSavedTrailer(row.trailer) then
    entry.trailerSeen = true
  end
end

local function sweep()
  for plate, entry in pairs(Vehicles.out) do
    local alive = Vehicles.isOut(plate)
    if alive then watchTrailer(plate, entry) end
    if not alive then
      local adopted = false
      if not entry.netId then
        -- The client never reported its entity: adopt it if it exists after all.
        local stored = not entry.spawner and NZ.DB.getVehicle(plate) or nil
        local entity = findEntityByPlate(plate, stored and rowHash(stored) or nil)
        if entity then
          entry.entity = entity
          entry.netId = NetworkGetNetworkIdFromEntity(entity)
          entityPlates[entity] = plate
          adopted = true
        end
      end
      if not adopted then
        if entry.entity then entityPlates[entry.entity] = nil end
        Vehicles.out[plate] = nil
      end
    end
  end
end

--- Boot the vehicle module (§7.5): adopt live vehicles after a resource restart, or apply
--- garages.outOnRestart on a fresh server start; then start the 60 s clean-up thread.
function Vehicles.boot()
  if booted then return end
  booted = true
  if #GetPlayers() > 0 then
    adoptExisting()
  else
    applyOutOnRestart()
  end
  -- every saved trailer, also those of vehicles in a garage (one may be parked in the world)
  local tracked, err = pcall(trackSavedTrailers)
  if not tracked then lib.print.warn(('[nayzeee-garages] could not load saved trailers: %s'):format(tostring(err))) end
  CreateThread(function()
    while true do
      Wait(60000)
      local success, err = pcall(sweep)
      if not success then lib.print.error(('[nayzeee-garages] out-vehicle sweep failed: %s'):format(err)) end
    end
  end)
end

AddEventHandler('entityRemoved', function(entity)
  local plate = entityPlates[entity]
  if not plate then return end
  entityPlates[entity] = nil
  local entry = Vehicles.out[plate]
  if entry and entry.entity == entity then Vehicles.out[plate] = nil end
end)

---------------------------------------------------------------------------------------
-- Callbacks
---------------------------------------------------------------------------------------

local function register(name, handler)
  lib.callback.register(name, Utils.safe(function(src, payload)
    if not NZ.Ready then return fail(L('Garages are still loading')) end
    if type(payload) ~= 'table' then payload = {} end
    return handler(src, payload)
  end))
end

local function rateLimited(src, bucket, ms)
  return not NZ.Access.rateLimit(src, bucket, ms)
end

-- { locationId, groupId?, houseId? } -> GarageOpenData
register('nz:garage:open', function(src, payload)
  if rateLimited(src, 'garage:open', 750) then return fail(L('Please wait a moment before trying again')) end
  local target, err = Vehicles.resolveGarage(src, payload)
  if not target then return fail(err) end
  if not NZ.Access.nearLocation(src, target.location, maxDistance()) then
    return fail(L('You are too far from the garage'))
  end
  local session = NZ.Access.openSession(src, target.garageKey, target.location, {
    groupId = target.groupId,
    houseId = target.houseId,
  })
  if type(session) ~= 'table' then return fail(L('Something went wrong')) end
  return ok(Vehicles.buildGarageData(src, session))
end)

-- {} -> GarageOpenData for the open session
register('nz:garage:refresh', function(src)
  local session, err = NZ.Access.requireSession(src, maxDistance())
  if not session then return fail(err or L('The garage is not open')) end
  if rateLimited(src, 'garage:refresh', 500) then return fail(L('Please wait a moment before trying again')) end
  return ok(Vehicles.buildGarageData(src, session))
end)

-- { plate, spawnIndex, entityType } -> { spawn, vehicle, netId? }
register('nz:garage:retrieve', function(src, payload)
  local plate = readPlate(payload.plate)
  if not plate then return fail(L('Invalid vehicle')) end
  return Vehicles.retrieve(src, plate, nil, {
    spawnIndex = toInt(payload.spawnIndex, 1),
    entityType = type(payload.entityType) == 'string' and payload.entityType or nil,
  })
end)

-- { plate, netId } -> null
register('nz:garage:spawned', function(src, payload)
  if rateLimited(src, 'garage:spawned', 250) then return fail(L('Please wait a moment before trying again')) end
  if payload.failed == true then
    local released, why = Vehicles.spawnFailed(src, payload.plate)
    if not released then return fail(why) end
    return ok(nil)
  end
  local success, err = Vehicles.markSpawned(src, payload.plate, payload.netId)
  if not success then return fail(err) end
  return ok(nil)
end)

-- { locationId|houseId, groupId?, netId, data } -> { returnTo? }
register('nz:garage:store', function(src, payload)
  if rateLimited(src, 'garage:store', 500) then return fail(L('Please wait a moment before trying again')) end
  local target, err = Vehicles.resolveGarage(src, payload)
  if not target then return fail(err) end
  local session = NZ.Access.openSession(src, target.garageKey, target.location, {
    groupId = target.groupId,
    houseId = target.houseId,
  })
  if type(session) ~= 'table' then return fail(L('Something went wrong')) end
  return Vehicles.store(src, session, payload)
end)

-- { plate } -> { coords }
register('nz:garage:track', function(src, payload)
  local session, err = NZ.Access.requireSession(src, maxDistance())
  if not session then return fail(err or L('The garage is not open')) end
  if rateLimited(src, 'garage:track', 1000) then return fail(L('Please wait a moment before trying again')) end
  local plate = readPlate(payload.plate)
  if not plate then return fail(L('Invalid vehicle')) end
  local identifier = NZ.Bridge.getIdentifier(src)
  local row = NZ.DB.getVehicle(plate)
  if not row or not identifier then return fail(L('Vehicle not found')) end
  if row.owner ~= identifier and not Vehicles.isSharedWith(plate, identifier) then
    return fail(L('You do not have access to this vehicle'))
  end

  if row.state == 'out' then
    local out, entity = Vehicles.isOut(plate)
    if out and entity then return ok({ coords = Utils.v3(GetEntityCoords(entity)) }) end
  end

  local location = nil
  if row.state == 'impounded' and type(row.impound) == 'table' and row.impound.locationId then
    location = NZ.Locations.get(tonumber(row.impound.locationId))
  end
  if not location and row.garageKey then
    local resolved = NZ.Locations.resolveKey(row.garageKey)
    location = resolved and resolved.location or nil
  end
  local coords = firstOpenPoint(location)
  if not coords then return fail(L('This vehicle could not be located')) end
  return ok({ coords = coords })
end)

-- { plate } -> null
register('nz:garage:recover', function(src, payload)
  local session, err = NZ.Access.requireSession(src, maxDistance())
  if not session then return fail(err or L('The garage is not open')) end
  if rateLimited(src, 'garage:recover', 2000) then return fail(L('Please wait a moment before trying again')) end
  local plate = readPlate(payload.plate)
  if not plate then return fail(L('Invalid vehicle')) end

  return Vehicles.withLock(plate, function()
    local identifier = NZ.Bridge.getIdentifier(src)
    if not identifier then return fail(L('Your character is not loaded')) end
    local row = NZ.DB.getVehicle(plate)
    if not row then return fail(L('Vehicle not found')) end
    if row.state ~= 'out' then return fail(L('This vehicle is not out')) end
    if row.blocked then return fail(L('This vehicle is blocked')) end
    if not Vehicles.accessOf(src, row, session, { identifier = identifier }) then
      return fail(L('You do not have access to this vehicle'))
    end

    local location = session.location
    local storable, reason = storableHere(row, location)
    if not storable then return fail(reason) end
    if not ownerCanReach(row, session.garageKey) then
      return fail(L('The owner of this vehicle cannot use this garage'))
    end
    if Vehicles.vehicleTypeOf(row) ~= (location.vehicleType or 'car') then
      return fail(L('Wrong vehicle type for this garage'))
    end

    local out, entity = Vehicles.isOut(plate)
    if out and not entity then return fail(L('Please wait a moment before trying again')) end
    entity = entity or findEntityByPlate(plate, rowHash(row))
    if entity and isOccupied(entity) then return fail(L('Someone is using this vehicle')) end

    local key = session.garageKey
    if not hasSpace(NZ.Locations.capacity(location, key, row.owner or identifier)) then
      return fail(L('This garage is full'))
    end

    local fee = math.max(0, toInt(setting('garages.recoverFee', 250)) or 0)
    local paid, account = charge(src, fee, 'nayzeee-garages:recover')
    if not paid then return fail(L('You cannot afford this ({amount})', { amount = money(fee) })) end

    local garageName = keyName(key) or location.name
    if not NZ.DB.updateVehicle(plate, { state = 'garaged', garageKey = key, garageName = garageName }) then
      refund(src, fee, account, 'nayzeee-garages:recover-refund')
      return fail(L('Something went wrong'))
    end

    if entity then
      -- a fake plate comes off first (the item goes back with Config.FakePlates.returnOnStore)
      dropFakePlate(src, entity, plate)
      deleteVehicle(entity)
    end
    Vehicles.clearOut(plate)
    -- its saved trailer comes back with it: never leave a second copy in the world
    Vehicles.removeTrailerOf(plate, row)
    log('vehicle.recover', src, {
      plate = plate, garage = key, garageName = garageName, fee = fee,
      owner = row.owner, removedEntity = entity ~= nil,
    })
    return ok(nil)
  end)
end)

-- {} -> { coords, name } of the nearest usable garage with free space
register('nz:garage:nearestWithSpace', function(src)
  if rateLimited(src, 'garage:nearest', 1000) then return fail(L('Please wait a moment before trying again')) end
  local session = NZ.Access.getSession(src)
  if type(session) ~= 'table' or type(session.location) ~= 'table' then return fail(L('The garage is not open')) end
  local identifier = NZ.Bridge.getIdentifier(src)
  local pos = pedCoords(src)
  if not identifier or not pos then return fail(L('Your character is not loaded')) end

  local vtype = session.location.vehicleType or 'car'
  local candidates = {}
  for _, location in ipairs(NZ.Locations.all('garage') or {}) do
    if location.enabled ~= false and (location.vehicleType or 'car') == vtype
      and sourceOf(location) ~= 'spawner' and location.id ~= session.location.id then
      local coords = firstOpenPoint(location)
      if coords then
        candidates[#candidates + 1] = { location = location, coords = coords, distance = Utils.dist(pos, coords) }
      end
    end
  end
  table.sort(candidates, function(a, b) return a.distance < b.distance end)

  for _, candidate in ipairs(candidates) do
    local location = candidate.location
    if NZ.Access.canUse(src, location) then
      local capacity = NZ.Locations.capacity(location, Utils.key.location(location.id), identifier)
      if hasSpace(capacity) then
        return ok({ coords = candidate.coords, name = location.name })
      end
    end
  end
  return fail(L('No garage with free space was found nearby'))
end)
