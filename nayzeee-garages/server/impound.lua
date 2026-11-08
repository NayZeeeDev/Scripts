--[[
  nayzeee-garages — server/impound.lua (NZ.Impound)

  Impound system (§5.5, §7.4): impounding vehicles (staff form, admin panel and the
  ImpoundVehicle export), the impound menu (owners see their own impounded vehicles,
  staff see every vehicle at that impound), retrieval with the fee routed to the
  impound's society account, staff release (to the owner or back to a garage) and the
  data for the impound form.
]]

local Impound = NZ.Impound
local Utils = NZ.Utils

local MAX_FEE = 1000000
local MAX_HOURS = 720
local MAX_REASON = 120
local MAX_PLATE_LENGTH = 16
local FORM_RANGE = 10.0          -- metres between the officer and the vehicle being impounded

-- Client hint only: NZ.Vehicles.retrieve derives the type it spawns with server-side.
local ENTITY_TYPES = {
  automobile = true, bike = true, boat = true, heli = true,
  plane = true, submarine = true, trailer = true,
}

local LOCK_MARKER = {}           -- identifies results produced inside withPlateLock

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function ok(data) return Utils.ok(data) end
local function fail(message) return Utils.fail(message) end

local function log(event, src, data)
  if type(NZ.Logs.add) ~= 'function' then return end
  local success, err = pcall(NZ.Logs.add, event, src, data)
  if not success then lib.print.warn(('impound: could not log %s: %s'):format(event, tostring(err))) end
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

local function notify(src, kind, message)
  if not src then return end
  TriggerClientEvent('nz:client:notify', src, { type = kind, message = message })
end

--- Finite number or nil.
local function toNumber(value)
  local n = tonumber(value)
  if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
  return n
end

--- Integer within [min, max] or nil.
local function toInt(value, min, max)
  local n = toNumber(value)
  if not n then return nil end
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

local function identifierOf(src)
  if not src or type(NZ.Bridge.getIdentifier) ~= 'function' then return nil end
  local success, identifier = pcall(NZ.Bridge.getIdentifier, src)
  if success and type(identifier) == 'string' and identifier ~= '' then return identifier end
  return nil
end

local function playerName(src)
  if not src or type(NZ.Bridge.getName) ~= 'function' then return nil end
  local success, name = pcall(NZ.Bridge.getName, src)
  if success and type(name) == 'string' and name ~= '' then return name end
  return nil
end

local function sourceOf(identifier)
  if type(identifier) ~= 'string' or type(NZ.Bridge.getSourceByIdentifier) ~= 'function' then return nil end
  local success, src = pcall(NZ.Bridge.getSourceByIdentifier, identifier)
  if success then return tonumber(src) end
  return nil
end

--- Human readable wait, e.g. "in 3h 20m".
local function formatWait(seconds)
  seconds = math.max(0, math.floor(tonumber(seconds) or 0))
  local days = seconds // 86400
  local hours = (seconds % 86400) // 3600
  local minutes = (seconds % 3600) // 60
  if days > 0 then return L('in {days}d {hours}h', { days = days, hours = hours }) end
  if hours > 0 then return L('in {hours}h {minutes}m', { hours = hours, minutes = minutes }) end
  if minutes > 0 then return L('in {minutes} min', { minutes = minutes }) end
  return L('in less than a minute')
end

local function vehicleTypeOf(row)
  if type(NZ.Vehicles.vehicleTypeOf) == 'function' then return NZ.Vehicles.vehicleTypeOf(row) end
  local vtype = type(row) == 'table' and row.vehicleType or nil
  return Utils.vehicleTypes[vtype] and vtype or 'car'
end

local function firstOpenPoint(location)
  local points = type(location) == 'table' and location.openPoints or nil
  if type(points) ~= 'table' then return nil end
  for _, point in ipairs(points) do
    local coords = Utils.v3(type(point) == 'table' and point.coords or point)
    if coords then return coords end
  end
  return nil
end

local function pedCoords(src)
  local ped = GetPlayerPed(src)
  if not ped or ped == 0 then return nil end
  return GetEntityCoords(ped)
end

--- Enabled impound location by id, or nil.
local function impoundLocation(id)
  id = toInt(id, 1)
  if not id then return nil end
  local location = NZ.Locations.get(id)
  if type(location) ~= 'table' or location.kind ~= 'impound' or location.enabled == false then return nil end
  return location
end

--- Nearest enabled impound that takes vehicles of category `vtype` (from `origin`), or nil.
local function nearestImpoundOfType(origin, vtype)
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

---------------------------------------------------------------------------------------
-- Entities
---------------------------------------------------------------------------------------

local function isVehicleEntity(entity)
  return type(entity) == 'number' and entity ~= 0 and DoesEntityExist(entity) and GetEntityType(entity) == 2
end

local function entityFromNetId(netId)
  netId = toInt(netId, 1)
  if not netId then return nil end
  local entity = NetworkGetEntityFromNetworkId(netId)
  if isVehicleEntity(entity) then return entity end
  return nil
end

--- The plate text the vehicle shows (a fake plate included): what officers see.
local function shownPlateOf(entity)
  return Utils.plate(GetVehicleNumberPlateText(entity))
end

--- The registration of a vehicle: the real plate under a fake plate (NZ.FakePlates), else the
--- plate text. Every row lookup and tracked-entity match uses it.
local function plateOf(entity)
  local fake = NZ.FakePlates
  if type(fake) == 'table' and type(fake.realPlateOf) == 'function' then
    local okReal, real = pcall(fake.realPlateOf, entity)
    if okReal and real then return real end
  end
  return shownPlateOf(entity)
end

--- True when any player sits in the vehicle.
local function playerInside(entity)
  for _, id in ipairs(GetPlayers()) do
    local ped = GetPlayerPed(id)
    if ped and ped ~= 0 and GetVehiclePedIsIn(ped, false) == entity then return true end
  end
  return false
end

local function withinRange(src, entity, range)
  local pos = pedCoords(src)
  if not pos or not isVehicleEntity(entity) then return false end
  return Utils.dist(pos, GetEntityCoords(entity)) <= range
end

--- Entity of a tracked out vehicle (NZ.Vehicles.out), or nil.
local function trackedEntity(plate)
  local out = type(NZ.Vehicles.out) == 'table' and NZ.Vehicles.out[plate] or nil
  if type(out) ~= 'table' then return nil end
  if isVehicleEntity(out.entity) and plateOf(out.entity) == plate then return out.entity end
  local entity = entityFromNetId(out.netId)
  if entity and plateOf(entity) == plate then return entity end
  return nil
end

local function deleteEntity(entity)
  if not isVehicleEntity(entity) then return false end
  DeleteEntity(entity)
  return true
end

--- Take an impounded vehicle out of the world. With `tow` (impound form) an NPC flatbed
--- collects it when Config.Tow allows (NZ.Tow locks it at once and removes it after the tow;
--- once a truck is on its way it never vanishes in front of players: a failed tow leaves it
--- locked until nobody is near); otherwise, or when the tow cannot run (disabled, boat /
--- aircraft, somebody inside, nobody nearby ...), it is deleted at once. Never yields.
---@return boolean removed, boolean towed
local function removeEntity(entity, tow, src)
  if not isVehicleEntity(entity) then return false, false end
  if tow and type(NZ.Tow.start) == 'function' then
    local success, started = pcall(NZ.Tow.start, entity, src)
    if success and started == true then return true, true end
    if not success then lib.print.warn(('impound: tow truck failed: %s'):format(tostring(started))) end
  end
  DeleteEntity(entity)
  return true, false
end

local function clearOut(plate)
  if type(NZ.Vehicles.clearOut) == 'function' then
    NZ.Vehicles.clearOut(plate)
  elseif type(NZ.Vehicles.out) == 'table' then
    NZ.Vehicles.out[plate] = nil
  end
end

--- Free the spawner slot of a job / rental vehicle that is being removed.
local function releaseSpawner(plate)
  if type(NZ.Jobs.isSpawnerVehicle) ~= 'function' or type(NZ.Jobs.release) ~= 'function' then return end
  local success, isSpawner = pcall(NZ.Jobs.isSpawnerVehicle, plate)
  if success and isSpawner then pcall(NZ.Jobs.release, plate) end
end

---------------------------------------------------------------------------------------
-- Plate locks (shared with the vehicles module when it provides them)
---------------------------------------------------------------------------------------

--- Run fn() (returning boolean, err) while holding the vehicles module's plate lock.
local function withPlateLock(plate, fn)
  if type(NZ.Vehicles.withLock) ~= 'function' then return fn() end
  local res = NZ.Vehicles.withLock(plate, function()
    return { marker = LOCK_MARKER, values = table.pack(fn()) }
  end)
  if type(res) == 'table' and res.marker == LOCK_MARKER then
    return table.unpack(res.values, 1, res.values.n)
  end
  return false, (type(res) == 'table' and res.error) or L('This vehicle is busy, try again in a moment')
end

--- Run fn() (returning a callback result) while holding the plate lock.
local function lockedResult(plate, fn)
  if type(NZ.Vehicles.withLock) ~= 'function' then return fn() end
  return NZ.Vehicles.withLock(plate, fn)
end

---------------------------------------------------------------------------------------
-- Permissions
---------------------------------------------------------------------------------------

--- Is the player impound staff at this impound (job matches one of its rules with a high
--- enough grade)?
---@param src number
---@param location table|number impound location or its id
---@return boolean
function Impound.isStaff(src, location)
  if type(location) ~= 'table' then location = impoundLocation(location) end
  if type(location) ~= 'table' or location.kind ~= 'impound' then return false end
  if type(location.jobs) ~= 'table' or #location.jobs == 0 then return false end
  return NZ.Access.jobAllowed(src, location.jobs, 'job') == true
end

--- May the player impound vehicles anywhere? Also returns the impound ids they staff.
---@param src number
---@return boolean allowed, number[] locationIds
function Impound.canImpound(src)
  local ids = {}
  for _, location in ipairs(NZ.Locations.all('impound') or {}) do
    if location.enabled ~= false and Impound.isStaff(src, location) then ids[#ids + 1] = location.id end
  end
  return #ids > 0, ids
end

---------------------------------------------------------------------------------------
-- Impounding
---------------------------------------------------------------------------------------

--- Impound a vehicle. Owned vehicles get state 'impounded' + ImpoundInfo (their entity is
--- deleted); unowned (NPC / spawner) vehicles given by netId are just deleted.
--- An impound only hands out vehicles of its own category (car / sea / air): a vehicle of
--- another category goes to the nearest impound of its category instead (refused when the
--- server has none), otherwise its owner could never collect it.
--- Used by the impound form, the admin panel and the ImpoundVehicle export. `opts.tow`
--- (impound form only): an NPC flatbed collects the vehicle instead of it vanishing (NZ.Tow).
---@param plate string
---@param opts table { locationId, reason?, fee?, hours?, retrievable?, netId?, byName?, tow? }
---@param src number|nil player who impounds (nil for exports / automation)
---@return boolean success, string|nil error (translated), table|nil location actually used
function Impound.impound(plate, opts, src)
  plate = readPlate(plate)
  if not plate then return false, L('Invalid plate') end
  opts = type(opts) == 'table' and opts or {}
  src = toInt(src, 1)

  local location = impoundLocation(opts.locationId)
  if not location then return false, L('Impound not found') end

  local fee = toNumber(opts.fee)
  if fee == nil then fee = toNumber(location.defaultFee) or 0 end
  fee = math.floor(Utils.clamp(fee, 0, MAX_FEE))
  local hours = toNumber(opts.hours)
  if hours == nil then hours = toNumber(location.defaultHours) or 0 end
  hours = Utils.clamp(hours, 0, MAX_HOURS)
  local retrievable = true
  if type(opts.retrievable) == 'boolean' then retrievable = opts.retrievable end
  local reason = Utils.cleanText(opts.reason, MAX_REASON) or ''
  local netId = toInt(opts.netId, 1)
  local tow = opts.tow == true

  local by = identifierOf(src)
  local byName = playerName(src) or Utils.cleanText(opts.byName, 60) or L('Impound service')

  return withPlateLock(plate, function()
    -- Never delete an unrelated entity: the netId must carry this plate.
    local entity = netId and entityFromNetId(netId) or nil
    if entity and plateOf(entity) ~= plate then entity = nil end

    local row = NZ.DB.getVehicle(plate)
    if not row then
      if not entity then return false, L('Vehicle not found') end
      local _, towed = removeEntity(entity, tow, src)
      releaseSpawner(plate)
      log('impound.add', src, {
        plate = plate, npc = true, impound = location.id, impoundName = location.name,
        reason = reason, by = by, byName = byName, towed = towed or nil,
      })
      return true, nil, location
    end

    local requested = location
    local vtype = vehicleTypeOf(row)
    if vtype ~= (location.vehicleType or 'car') then
      location = nearestImpoundOfType(firstOpenPoint(requested), vtype)
      if not location then return false, L('No impound accepts this type of vehicle') end
      if toNumber(opts.fee) == nil then fee = math.floor(Utils.clamp(toNumber(location.defaultFee) or 0, 0, MAX_FEE)) end
      if toNumber(opts.hours) == nil then hours = Utils.clamp(toNumber(location.defaultHours) or 0, 0, MAX_HOURS) end
    end

    local now = os.time()
    local info = {
      locationId = location.id,
      locationName = location.name,
      reason = reason,
      fee = fee,
      by = by,
      byName = byName,
      at = now,
      releaseAt = now + math.floor(hours * 3600 + 0.5),
      retrievable = retrievable,
    }
    if not NZ.DB.updateVehicle(plate, { state = 'impounded', impound = info }) then
      return false, L('Could not impound the vehicle')
    end

    -- the vehicle the officer pointed at (else the tracked one) may be towed; a second copy
    -- with the same plate is deleted at once
    local tracked = trackedEntity(plate)
    local primary = entity or tracked
    local removed, towed = removeEntity(primary, tow, src)
    if tracked and tracked ~= primary then removed = deleteEntity(tracked) or removed end
    clearOut(plate)
    releaseSpawner(plate)
    -- its saved trailer is impounded with it: never leave a second copy in the world
    if type(NZ.Vehicles.removeTrailerOf) == 'function' then pcall(NZ.Vehicles.removeTrailerOf, plate, row) end

    log('impound.add', src, {
      plate = plate,
      owner = row.owner,
      job = row.job,
      gang = row.gang,
      previousState = row.state,
      previousImpound = type(row.impound) == 'table' and row.impound.locationId or nil,
      impound = location.id,
      impoundName = location.name,
      requestedImpound = requested.id ~= location.id and requested.id or nil,
      reason = reason,
      fee = fee,
      hours = hours,
      retrievable = retrievable,
      by = by,
      byName = byName,
      removedEntity = removed,
      towed = towed or nil,
    })

    local ownerSrc = sourceOf(row.owner)
    if ownerSrc then
      notify(ownerSrc, 'warning', L('Your vehicle {plate} was impounded at {impound}', {
        plate = plate, impound = location.name,
      }))
    end
    return true, nil, location
  end)
end

---------------------------------------------------------------------------------------
-- Impound menu data
---------------------------------------------------------------------------------------

--- ImpoundInfo with every field present (older rows may miss some).
local function impoundInfoOf(row, location)
  local info = type(row.impound) == 'table' and row.impound or {}
  return {
    locationId = toInt(info.locationId) or location.id,
    locationName = type(info.locationName) == 'string' and info.locationName or location.name,
    reason = type(info.reason) == 'string' and info.reason or '',
    fee = math.max(0, toInt(info.fee) or 0),
    by = type(info.by) == 'string' and info.by or nil,
    byName = type(info.byName) == 'string' and info.byName or '',
    at = toInt(info.at) or 0,
    releaseAt = toInt(info.releaseAt) or 0,
    retrievable = info.retrievable ~= false,
  }
end

--- Can the viewer take this impounded vehicle out here? Owners must wait for releaseAt and
--- need `retrievable`; staff may always (fees per settings.impound.staffBypassFee).
---@return boolean allowed, string|nil reason (translated)
local function retrievalCheck(row, info, location, staff, isOwner, now)
  if row.blocked then return false, L('This vehicle is blocked') end
  if vehicleTypeOf(row) ~= (location.vehicleType or 'car') then
    return false, L('This vehicle cannot be taken out at this impound')
  end
  if NZ.Finance and NZ.Finance.blocks and NZ.Finance.blocks(row) then return false, L('Finance payment overdue') end
  if staff then return true, nil end
  if not isOwner then return false, L('You do not have access to this vehicle') end
  if info.retrievable == false then return false, L('Contact the authorities to release this vehicle') end
  if info.releaseAt > now then
    return false, L('Available {time}', { time = formatWait(info.releaseAt - now) })
  end
  return true, nil
end

local function impoundedHere(row, location)
  return type(row) == 'table' and row.state == 'impounded' and type(row.impound) == 'table'
    and tonumber(row.impound.locationId) == location.id
end

local NAME_CHUNK = 200
local esxNameColumns = nil       -- users.firstname / lastname exist (checked once)

local function joinName(first, last)
  first = type(first) == 'string' and first or ''
  last = type(last) == 'string' and last or ''
  local name = Utils.trim(first .. ' ' .. last)
  return name ~= '' and name or nil
end

--- Character names of offline owners in one query per 200 owners (the staff list can hold
--- thousands of vehicles), written into `names` (the toGarageVehicle name cache). Owners that
--- are online, or that the query could not answer, are left to NZ.Bridge.getCharacterName.
---@param owners table<string, true>
---@param names table<string, string>
local function prefetchNames(owners, names)
  local framework = NZ.Framework
  if framework ~= 'qb' and framework ~= 'qbx' and framework ~= 'esx' then return end
  local list = {}
  for owner in pairs(owners) do
    local online = type(NZ.Bridge.getSourceByIdentifier) == 'function' and NZ.Bridge.getSourceByIdentifier(owner)
    if names[owner] == nil and not online then list[#list + 1] = owner end
  end
  if #list < 2 then return end
  if framework == 'esx' then
    if esxNameColumns == nil then
      local success, count = pcall(MySQL.scalar.await, [[SELECT COUNT(*) FROM `INFORMATION_SCHEMA`.`COLUMNS`
        WHERE `TABLE_SCHEMA` = DATABASE() AND `TABLE_NAME` = 'users' AND `COLUMN_NAME` IN ('firstname', 'lastname')]], {})
      if not success then return end
      esxNameColumns = tonumber(count) == 2
    end
    if not esxNameColumns then return end
  end
  for i = 1, #list, NAME_CHUNK do
    local chunk = table.move(list, i, math.min(i + NAME_CHUNK - 1, #list), 1, {})
    local success, rows
    if framework == 'esx' then
      success, rows = pcall(MySQL.query.await,
        'SELECT `identifier` AS `id`, `firstname`, `lastname` FROM `users` WHERE `identifier` IN (?)', { chunk })
    else
      success, rows = pcall(MySQL.query.await,
        'SELECT `citizenid` AS `id`, `charinfo` FROM `players` WHERE `citizenid` IN (?)', { chunk })
    end
    if not success or type(rows) ~= 'table' then return end
    local found = {}
    for _, r in ipairs(rows) do
      local name
      if framework == 'esx' then
        name = joinName(r.firstname, r.lastname)
      else
        local info = r.charinfo
        if type(info) == 'string' then
          local decoded, value = pcall(json.decode, info)
          info = decoded and value or nil
        end
        if type(info) == 'table' then name = joinName(info.firstname, info.lastname) end
      end
      if type(r.id) == 'string' and name then
        names[r.id] = name
        found[r.id] = true
      end
    end
    -- characters that no longer exist: same answer as the bridge, without one query each
    for _, owner in ipairs(chunk) do
      if not found[owner] then names[owner] = L('Unknown') end
    end
  end
end

--- ImpoundOpenData for the viewer at an impound location.
---@param src number
---@param location table impound location
---@param session table|nil
---@return table ImpoundOpenData
local function buildImpoundData(src, location, session)
  local identifier = identifierOf(src)
  local staff = Impound.isStaff(src, location)

  local rows = {}
  if staff then
    for _, row in ipairs(NZ.DB.getImpounded(location.id) or {}) do
      if impoundedHere(row, location) then rows[#rows + 1] = row end
    end
  elseif identifier then
    for _, row in ipairs(NZ.DB.getVehiclesByOwner(identifier) or {}) do
      if impoundedHere(row, location) then rows[#rows + 1] = row end
    end
  end

  local ctx = { src = src, session = session, identifier = identifier, names = {} }
  if staff then
    local owners = {}
    for _, row in ipairs(rows) do
      if type(row.owner) == 'string' and row.owner ~= '' then owners[row.owner] = true end
    end
    local success, err = pcall(prefetchNames, owners, ctx.names)
    if not success then lib.print.warn(('impound: owner name prefetch failed: %s'):format(tostring(err))) end
  end
  local now = os.time()
  local vehicles = {}
  for _, row in ipairs(rows) do
    if row.plate then
      local view = NZ.Vehicles.toGarageVehicle(row, ctx)
      if type(view) == 'table' then
        local info = impoundInfoOf(row, location)
        local isOwner = identifier ~= nil and row.owner == identifier
        view.impound = info
        if type(view.ownerName) ~= 'string' or view.ownerName == '' then
          view.ownerName = (row.owner and type(NZ.Bridge.getCharacterName) == 'function'
            and NZ.Bridge.getCharacterName(row.owner)) or row.job or row.gang or ''
        end
        view.canDrive, view.reason = retrievalCheck(row, info, location, staff, isOwner, now)
        if view.canDrive then view.reason = nil end
        vehicles[#vehicles + 1] = view
      end
    end
  end

  table.sort(vehicles, function(a, b)
    if a.impound.at ~= b.impound.at then return a.impound.at > b.impound.at end
    return a.plate < b.plate
  end)

  return {
    impound = { id = location.id, name = location.name, vehicleType = location.vehicleType or 'car' },
    staff = staff,
    feeWaived = staff and setting('impound.staffBypassFee', true) == true,
    vehicles = vehicles,
  }
end

--- Where a vehicle released with mode 'garage' goes: its last garage when it still exists
--- and the owner may use it, else the nearest public garage of its type (nil = none).
---@return string|nil garageKey, string|nil garageName
local function releaseTarget(row, location)
  local key = row.garageKey
  if type(key) == 'string' then
    local resolved = NZ.Locations.resolveKey(key)
    local target = resolved and resolved.location or nil
    if type(target) == 'table' and target.enabled ~= false and target.kind ~= 'impound' then
      local reachable = true
      if resolved.kind == 'G' and row.owner then
        reachable = NZ.Private.role(resolved.groupId, row.owner) ~= nil
      elseif resolved.kind == 'H' and row.owner and type(NZ.Housing.hasAccess) == 'function' then
        local success, allowed = pcall(NZ.Housing.hasAccess, row.owner, resolved.houseId)
        reachable = success and allowed == true
      end
      if reachable then return key, NZ.Locations.keyName(key) or target.name end
    end
  end
  if type(NZ.Private.fallbackGarage) == 'function' then
    return NZ.Private.fallbackGarage(firstOpenPoint(location), vehicleTypeOf(row))
  end
  return nil, nil
end

---------------------------------------------------------------------------------------
-- Callbacks
---------------------------------------------------------------------------------------

local function register(name, handler)
  lib.callback.register(name, Utils.safe(function(source, payload)
    local src = tonumber(source)
    if not src or src <= 0 then return fail(L('Something went wrong')) end
    if not NZ.Ready then return fail(L('Garages are still loading')) end
    if type(payload) ~= 'table' then payload = {} end
    return handler(src, payload)
  end))
end

local function rateLimited(src, bucket, ms)
  return not NZ.Access.rateLimit(src, bucket, ms)
end

local function waitMessage()
  return L('Please wait a moment before trying again')
end

--- The player's open impound session (re-checks distance), or nil + error.
local function impoundSession(src)
  local session, err = NZ.Access.requireSession(src, maxDistance())
  if not session then return nil, nil, err or L('The impound is not open') end
  local location = session.location
  if type(location) ~= 'table' or location.kind ~= 'impound' then
    return nil, nil, L('The impound is not open')
  end
  return session, location, nil
end

-- { locationId } -> ImpoundOpenData
register('nz:impound:open', function(src, payload)
  if rateLimited(src, 'impound:open', 750) then return fail(waitMessage()) end
  local location = impoundLocation(payload.locationId)
  if not location then return fail(L('Impound not found')) end
  if not identifierOf(src) then return fail(L('Your character is not loaded')) end
  if not NZ.Access.nearLocation(src, location, maxDistance()) then
    return fail(L('You are too far from the impound'))
  end
  local session = NZ.Access.openSession(src, Utils.key.location(location.id), location, { impound = true })
  if type(session) ~= 'table' then return fail(L('Something went wrong')) end
  return ok(buildImpoundData(src, location, session))
end)

-- {} -> ImpoundOpenData of the open impound
register('nz:impound:refresh', function(src)
  if rateLimited(src, 'impound:refresh', 500) then return fail(waitMessage()) end
  local session, location, err = impoundSession(src)
  if not session then return fail(err) end
  return ok(buildImpoundData(src, location, session))
end)

-- { plate } -> { hash, props, damage?, engine, body } : 3D preview of an impounded vehicle
-- (client/preview.lua). Same visibility as the impound list: staff see every vehicle
-- impounded here, everyone else only their own.
register('nz:impound:preview', function(src, payload)
  if rateLimited(src, 'impound:preview', 250) then return fail(waitMessage()) end
  local session, location, err = impoundSession(src)
  if not session then return fail(err) end
  local plate = readPlate(payload.plate)
  if not plate then return fail(L('Invalid vehicle')) end
  local row = NZ.DB.getVehicle(plate)
  if not row or not impoundedHere(row, location) then return fail(L('This vehicle is not impounded here')) end
  local identifier = identifierOf(src)
  if not (identifier and row.owner == identifier) and not Impound.isStaff(src, location) then
    return fail(L('You do not have access to this vehicle'))
  end
  local function pct(value)
    local n = tonumber(value)
    if not n or n ~= n then return 100 end
    return math.floor(math.max(0, math.min(100, n)) * 10 + 0.5) / 10
  end
  return ok({
    hash = tonumber(row.hash),
    props = type(row.props) == 'table' and row.props or {},
    damage = setting('vehicles.saveDamage', true) and row.damage or nil,
    engine = pct(row.engine),
    body = pct(row.body),
  })
end)

-- { plate, spawnIndex, entityType } -> { spawn, vehicle, netId? } (retrieve flow §7.1)
register('nz:impound:retrieve', function(src, payload)
  if rateLimited(src, 'impound:retrieve', 1000) then return fail(waitMessage()) end
  local session, location, err = impoundSession(src)
  if not session then return fail(err) end
  local plate = readPlate(payload.plate)
  if not plate then return fail(L('Invalid vehicle')) end
  local identifier = identifierOf(src)
  if not identifier then return fail(L('Your character is not loaded')) end

  local row = NZ.DB.getVehicle(plate)
  if not row then return fail(L('Vehicle not found')) end
  if not impoundedHere(row, location) then return fail(L('This vehicle is not impounded here')) end

  local staff = Impound.isStaff(src, location)
  local info = impoundInfoOf(row, location)
  local allowed, reason = retrievalCheck(row, info, location, staff, row.owner == identifier, os.time())
  if not allowed then return fail(reason) end

  local fee = info.fee
  if staff and setting('impound.staffBypassFee', true) == true then fee = 0 end

  local points = location.spawnPoints
  local spawnIndex = type(points) == 'table' and toInt(payload.spawnIndex, 1, #points) or nil
  local entityType = type(payload.entityType) == 'string' and ENTITY_TYPES[payload.entityType] and payload.entityType or nil

  local result = NZ.Vehicles.retrieve(src, plate, session, {
    spawnIndex = spawnIndex,
    entityType = entityType,
    fromImpound = true,
    fee = fee,
    staff = staff,
  })
  if type(result) ~= 'table' then return fail(L('Something went wrong')) end
  if not result.ok then return result end

  local society = type(location.society) == 'string' and location.society or ''
  local societyPaid = nil
  if society ~= '' and fee > 0 then
    local success, deposited = pcall(NZ.Bridge.addSocietyMoney, society, fee)
    societyPaid = success and deposited == true
    if not societyPaid then
      lib.print.warn(('impound: could not deposit %s into society "%s" for %s'):format(fee, society, plate))
    end
  end

  log('impound.retrieve', src, {
    plate = plate,
    owner = row.owner,
    impound = location.id,
    impoundName = location.name,
    fee = fee,
    staff = staff,
    society = society ~= '' and society or nil,
    societyPaid = societyPaid,
    impoundedBy = info.byName,
    reason = info.reason,
  })
  return result
end)

-- { plate, mode = 'owner'|'garage' } (staff) -> ImpoundOpenData
register('nz:impound:release', function(src, payload)
  if rateLimited(src, 'impound:release', 1000) then return fail(waitMessage()) end
  local session, location, err = impoundSession(src)
  if not session then return fail(err) end
  if not Impound.isStaff(src, location) then return fail(L('Only impound staff can release vehicles')) end
  local plate = readPlate(payload.plate)
  if not plate then return fail(L('Invalid vehicle')) end
  local mode = payload.mode
  if mode ~= 'owner' and mode ~= 'garage' then return fail(L('Invalid request')) end

  local result = lockedResult(plate, function()
    local row = NZ.DB.getVehicle(plate)
    if not row then return fail(L('Vehicle not found')) end
    if not impoundedHere(row, location) then return fail(L('This vehicle is not impounded here')) end
    local now = os.time()
    local ownerSrc = sourceOf(row.owner)

    if mode == 'owner' then
      local info = impoundInfoOf(row, location)
      info.retrievable = true
      info.releaseAt = now
      -- state too: the vehicle may be impounded through framework columns only (no nz state)
      if not NZ.DB.updateVehicle(plate, { state = 'impounded', impound = info }) then
        return fail(L('Something went wrong'))
      end
      log('impound.release', src, {
        plate = plate, mode = mode, owner = row.owner, impound = location.id, impoundName = location.name,
        fee = info.fee,
      })
      if ownerSrc then
        notify(ownerSrc, 'success', L('Your vehicle {plate} can now be collected at {impound}', {
          plate = plate, impound = location.name,
        }))
      end
      return ok(nil)
    end

    local key, name = releaseTarget(row, location)
    local fields = { state = 'garaged', impound = false, garageKey = key or false }
    if key and name then fields.garageName = name end
    if not NZ.DB.updateVehicle(plate, fields) then return fail(L('Something went wrong')) end
    log('impound.release', src, {
      plate = plate, mode = mode, owner = row.owner, impound = location.id, impoundName = location.name,
      garage = key, garageName = name, previousGarage = row.garageKey,
    })
    if ownerSrc then
      local message
      if key and name then
        message = L('Your vehicle {plate} was released to {garage}', { plate = plate, garage = name })
      else
        message = L('Your vehicle {plate} was released from the impound', { plate = plate })
      end
      notify(ownerSrc, 'success', message)
    end
    return ok(nil)
  end)

  if type(result) ~= 'table' or not result.ok then return result end
  return ok(buildImpoundData(src, location, session))
end)

-- { plate?, netId? } (staff) -> ImpoundFormData
register('nz:impound:formData', function(src, payload)
  if rateLimited(src, 'impound:formData', 750) then return fail(waitMessage()) end
  local allowed, ids = Impound.canImpound(src)
  if not allowed then return fail(L('You are not allowed to impound vehicles')) end

  local plate = nil
  local registration = nil -- the real plate under a fake plate (row lookup only, never shown)
  if payload.plate ~= nil then
    plate = readPlate(payload.plate)
    if not plate then return fail(L('Invalid plate')) end
  end
  local netId = nil
  if payload.netId ~= nil then
    netId = toInt(payload.netId, 1)
    if not netId then return fail(L('Vehicle not found')) end
    local entity = entityFromNetId(netId)
    if entity then
      if not withinRange(src, entity, FORM_RANGE) then return fail(L('You are too far from the vehicle')) end
      -- officers see the plate the vehicle shows (a fake plate stays fake: docs/CARLOCK.md §13);
      -- the database row is found by its registration, and the submit accepts either form
      registration = plateOf(entity)
      plate = shownPlateOf(entity) or registration or plate
    else
      netId = nil
    end
  end
  if not plate then return fail(L('No vehicle nearby')) end

  -- Category of the vehicle (its row, else the entity): offer the impounds that take it.
  local row = NZ.DB.getVehicle(registration or plate)
  local vtype = row and vehicleTypeOf(row) or nil
  local formEntity = (not vtype and netId) and entityFromNetId(netId) or nil
  if formEntity then
    local success, etype = pcall(GetVehicleType, formEntity)
    if success and type(etype) == 'string' then
      vtype = (etype == 'boat' or etype == 'submarine') and 'sea'
        or ((etype == 'heli' or etype == 'plane') and 'air') or 'car'
    end
  end
  local staffed = {}
  for _, id in ipairs(ids) do
    local location = impoundLocation(id)
    if location then staffed[#staffed + 1] = location end
  end
  local matching = {}
  for _, location in ipairs(staffed) do
    if not vtype or (location.vehicleType or 'car') == vtype then matching[#matching + 1] = location end
  end
  -- None of the officer's impounds takes it: list them anyway, the impound itself is
  -- redirected to an impound of the right category on submit (see Impound.impound).
  if #matching == 0 then matching = staffed end

  local pos = pedCoords(src)
  local impounds, nearest, nearestDist = {}, nil, math.huge
  for _, location in ipairs(matching) do
    impounds[#impounds + 1] = { id = location.id, name = location.name }
    local point = firstOpenPoint(location)
    local dist = (pos and point) and Utils.dist(pos, point) or math.huge
    if not nearest or dist < nearestDist then nearest, nearestDist = location, dist end
  end
  if not nearest then return fail(L('You are not allowed to impound vehicles')) end

  return ok({
    plate = plate,
    netId = netId,
    label = '',
    owned = row ~= nil,
    impounds = impounds,
    defaults = {
      fee = math.floor(Utils.clamp(toNumber(nearest.defaultFee) or 0, 0, MAX_FEE)),
      hours = Utils.clamp(toNumber(nearest.defaultHours) or 0, 0, MAX_HOURS),
      impoundId = nearest.id,
    },
  })
end)

-- { plate, netId, impoundId, reason, fee, hours, retrievable } (staff) -> null
register('nz:impoundForm:submit', function(src, payload)
  if rateLimited(src, 'impoundForm:submit', 2000) then return fail(waitMessage()) end
  local location = impoundLocation(payload.impoundId)
  if not location then return fail(L('Impound not found')) end
  if not Impound.isStaff(src, location) then return fail(L('You are not allowed to impound vehicles here')) end

  if payload.reason ~= nil and type(payload.reason) ~= 'string' then return fail(L('Invalid request')) end
  if payload.fee ~= nil and type(payload.fee) ~= 'number' then return fail(L('Invalid request')) end
  if payload.hours ~= nil and type(payload.hours) ~= 'number' then return fail(L('Invalid request')) end
  if payload.retrievable ~= nil and type(payload.retrievable) ~= 'boolean' then return fail(L('Invalid request')) end

  local plate = nil
  if payload.plate ~= nil then
    plate = readPlate(payload.plate)
    if not plate then return fail(L('Invalid plate')) end
  end

  local netId = nil
  if payload.netId ~= nil then
    netId = toInt(payload.netId, 1)
    local entity = netId and entityFromNetId(netId) or nil
    if not entity then return fail(L('Vehicle not found')) end
    if not withinRange(src, entity, FORM_RANGE) then return fail(L('You are too far from the vehicle')) end
    local entityPlate = plateOf(entity)
    if not entityPlate then return fail(L('This vehicle has no plate')) end
    -- the form shows the plate the vehicle shows (a fake plate); its registration is accepted too
    if plate and plate ~= entityPlate and plate ~= shownPlateOf(entity) then
      return fail(L('The plate does not match this vehicle'))
    end
    if playerInside(entity) then return fail(L('Someone is using this vehicle')) end
    plate = entityPlate
  else
    -- Impounding by plate only: the vehicle must be out (lost or nearby), never parked.
    if not plate then return fail(L('Invalid plate')) end
    local row = NZ.DB.getVehicle(plate)
    if not row then return fail(L('Vehicle not found')) end
    if row.state == 'garaged' then return fail(L('This vehicle is parked in a garage')) end
    if row.state == 'impounded' then return fail(L('This vehicle is already impounded')) end
    local entity = trackedEntity(plate)
    if entity then
      if not withinRange(src, entity, FORM_RANGE) then return fail(L('You are too far from the vehicle')) end
      if playerInside(entity) then return fail(L('Someone is using this vehicle')) end
      netId = NetworkGetNetworkIdFromEntity(entity)
    end
  end

  local success, err, used = Impound.impound(plate, {
    locationId = location.id,
    reason = payload.reason,
    fee = payload.fee,
    hours = payload.hours,
    retrievable = payload.retrievable,
    netId = netId,
    tow = true, -- the vehicle in front of the officer: an NPC flatbed collects it (Config.Tow)
  }, src)
  if not success then return fail(err or L('Could not impound the vehicle')) end
  local where = type(used) == 'table' and used.name or location.name
  -- The form shows its own toast; tell it where the vehicle actually went (it can be
  -- redirected to an impound of the vehicle's category).
  return ok({ impoundName = where })
end)
