--[[
  nayzeee-garages — server exports (docs/ARCHITECTURE.md §10).

  exports['nayzeee-garages']:X(...) for dealerships, police / mechanic scripts and housing
  resources. Every input is validated here; the work is delegated to NZ.DB, NZ.Impound,
  NZ.Housing, NZ.Locations and NZ.Vehicles. Failing calls return nil/false plus an error.
]]

local Utils = NZ.Utils

local MAX_MONEY = 1000000000
local MAX_MILEAGE = 10000000
local PLATE_TRIES = 20

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function log(event, data)
  if type(NZ.Logs.add) ~= 'function' then return end
  data = data or {}
  data.resource = GetInvokingResource()
  local ok, err = pcall(NZ.Logs.add, event, nil, data)
  if not ok then lib.print.warn(('exports: log "%s" failed: %s'):format(event, tostring(err))) end
end

local function safeText(value, maxLen)
  local s = Utils.cleanText(value, maxLen)
  if not s then return nil end
  while #s > 0 and not utf8.len(s) do s = s:sub(1, -2) end
  if s == '' then return nil end
  return s
end

local function num(value, min, max, default, integer)
  local n = (type(value) == 'number' or type(value) == 'string') and tonumber(value) or nil
  if not n or n ~= n or n == math.huge or n == -math.huge then return default end
  if n < min then n = min elseif n > max then n = max end
  if integer then n = math.floor(n) end
  return n
end

--- Positive integer id (database ids, net ids) or nil. Never clamps: 0 / -1 / 1.5 are invalid.
local function positiveId(value)
  local n = (type(value) == 'number' or type(value) == 'string') and tonumber(value) or nil
  if not n or n ~= n or n < 1 or n > 2147483647 or n ~= math.floor(n) then return nil end
  return math.tointeger(n)
end

local function identifierArg(value)
  if type(value) ~= 'string' then return nil end
  local s = Utils.trim(value)
  if s == '' or #s > 64 or s:find('%c') then return nil end
  return s
end

--- Plate from another resource: trimmed, upper-case, at most 8 letters/digits/spaces.
local function plateArg(value)
  local p = Utils.plate(value)
  if not p or #p > 8 or not p:match('^[%w ]+$') then return nil end
  return p
end

--- GTA model hashes are signed 32-bit integers.
local function signedHash(h)
  h = math.tointeger(h) or math.floor(tonumber(h) or 0)
  h = h & 0xFFFFFFFF
  if h >= 0x80000000 then h = h - 0x100000000 end
  return h
end

local function characterName(identifier)
  if not identifier or type(NZ.Bridge.getCharacterName) ~= 'function' then return '' end
  local ok, name = pcall(NZ.Bridge.getCharacterName, identifier)
  if ok and type(name) == 'string' then return name end
  return ''
end

--- Vehicle row as exposed to other resources (damage data stays internal).
local function publicRow(row)
  if type(row) ~= 'table' then return nil end
  local out = {}
  for k, v in pairs(row) do
    if k ~= 'damage' then out[k] = v end
  end
  if type(row.trailer) == 'table' then
    local trailer = {}
    for k, v in pairs(row.trailer) do
      if k ~= 'damage' then trailer[k] = v end
    end
    out.trailer = trailer
  end
  return out
end

--- Validate a garage key. L / G keys must resolve; house keys may belong to a house that the
--- housing integration has not registered yet.
local function garageKeyArg(value)
  if type(value) ~= 'string' or #value > 64 then return nil end
  local kind = Utils.key.parse(value)
  if not kind then return nil end
  local resolved = NZ.Locations.resolveKey(value)
  if kind ~= 'H' and not resolved then return nil end
  return value, resolved
end

--- First enabled public garage (personal vehicles, no restriction) for a vehicle type.
local function defaultGarageKey(vehicleType)
  for _, loc in ipairs(NZ.Locations.all('garage')) do
    local restriction = loc.restriction and loc.restriction.type or 'everyone'
    if loc.enabled and loc.source == 'personal' and restriction == 'everyone' and loc.vehicleType == vehicleType then
      return Utils.key.location(loc.id)
    end
  end
  return nil
end

local function uniquePlate()
  for _ = 1, PLATE_TRIES do
    local candidate = Utils.generatePlate()
    -- generated plates are trimmed upper-case: the indexed exact lookup is enough here
    -- (DB.insertVehicle runs the full check before inserting)
    if not NZ.DB.plateExists(candidate, true) then return candidate end
  end
  return nil
end

--- Register an export; runtime errors are printed and returned as (nil, message).
local function export(name, fn)
  exports(name, function(...)
    local ok, a, b = pcall(fn, ...)
    if not ok then
      lib.print.error(('export %s failed (called by %s): %s'):format(name, tostring(GetInvokingResource()), tostring(a)))
      return nil, L('Something went wrong')
    end
    return a, b
  end)
end

local function notReady()
  return not NZ.Ready
end

---------------------------------------------------------------------------------------
-- Vehicles
---------------------------------------------------------------------------------------

--- GetVehicle(plate) -> normalized vehicle row (without damage) | nil
export('GetVehicle', function(plate)
  local p = Utils.plate(plate)
  if not p then return nil end
  return publicRow(NZ.DB.getVehicle(p))
end)

--- GetPlayerVehicles(identifier) -> { vehicle rows (without damage) }
export('GetPlayerVehicles', function(identifier)
  identifier = identifierArg(identifier)
  if not identifier then return {} end
  local rows = NZ.DB.getVehiclesByOwner(identifier)
  local out = {}
  if type(rows) == 'table' then
    for i = 1, #rows do out[#out + 1] = publicRow(rows[i]) end
  end
  return out
end)

--- AddVehicle(identifier, model, plate|nil, props|nil, garageKey|nil, vehicleType|nil)
--- -> plate | nil, error. Generates a unique plate when none is given.
export('AddVehicle', function(identifier, model, plate, props, garageKey, vehicleType)
  if notReady() then return nil, L('Garages are still loading') end
  identifier = identifierArg(identifier)
  if not identifier then return nil, L('Invalid identifier') end

  local modelName, hash
  if type(model) == 'string' then
    modelName = Utils.trim(model)
    if #modelName == 0 or #modelName > 32 or not modelName:match('^[%w_%-]+$') then
      return nil, L('Invalid vehicle model')
    end
    hash = signedHash(joaat(modelName))
  elseif type(model) == 'number' and model == model and model ~= 0 then
    hash = signedHash(model)
  else
    return nil, L('Invalid vehicle model')
  end

  if plate ~= nil and plate ~= '' then
    plate = plateArg(plate)
    if not plate then return nil, L('Invalid plate') end
    if NZ.DB.plateExists(plate) then return nil, L('This plate is already in use') end
  else
    plate = uniquePlate()
    if not plate then return nil, L('Could not generate a unique plate') end
  end

  if vehicleType ~= nil and not Utils.vehicleTypes[vehicleType] then
    return nil, L('Invalid vehicle type')
  end

  local key, resolved = nil, nil
  if garageKey ~= nil then
    key, resolved = garageKeyArg(garageKey)
    if not key then return nil, L('Unknown garage') end
  end
  -- Vehicle type: explicit argument, else the garage's type, else 'car'.
  if not vehicleType then
    vehicleType = resolved and resolved.location.vehicleType or 'car'
  end
  if not key then key = defaultGarageKey(vehicleType) end

  local vehicleProps = {}
  if type(props) == 'table' then
    for k, v in pairs(props) do vehicleProps[k] = v end
  end
  vehicleProps.plate = plate
  vehicleProps.model = hash

  local garageName = key and (NZ.Locations.keyName(key) or key) or nil
  local inserted = NZ.DB.insertVehicle({
    owner = identifier,
    model = modelName,
    hash = hash,
    plate = plate,
    props = vehicleProps,
    garageKey = key,
    garageName = garageName,
    state = 'garaged',
    vehicleType = vehicleType,
    ownerType = 'player',
  })
  if not inserted then return nil, L('Could not add the vehicle') end

  local ownerName = characterName(identifier)
  NZ.DB.events.add(plate, 'owner', { identifier = identifier, name = ownerName, via = 'dealership', at = os.time() })
  log('vehicle.add', {
    plate = plate, owner = identifier, ownerName = ownerName, model = modelName, hash = hash,
    garageKey = key, vehicleType = vehicleType,
  })
  return plate
end)

--- SetVehicleGarage(plate, garageKey) -> true | false, error
--- Parks the vehicle in that garage (clears an impound). Refused while it is out in the world.
export('SetVehicleGarage', function(plate, garageKey)
  if notReady() then return false, L('Garages are still loading') end
  local p = Utils.plate(plate)
  if not p then return false, L('Invalid plate') end
  local key = garageKeyArg(garageKey)
  if not key then return false, L('Unknown garage') end

  -- Same plate lock as retrieve / store / recover: no concurrent operation on the vehicle.
  local function apply()
    local row = NZ.DB.getVehicle(p)
    if not row then return Utils.fail(L('Vehicle not found')) end
    local rowPlate = row.plate or p

    if type(NZ.Vehicles.isOut) == 'function' and NZ.Vehicles.isOut(rowPlate) then
      return Utils.fail(L('This vehicle is out, store it first'))
    end

    local fields = { garageKey = key, garageName = NZ.Locations.keyName(key) or key, state = 'garaged' }
    if row.impound ~= nil or row.state == 'impounded' then fields.impound = false end
    if not NZ.DB.updateVehicle(rowPlate, fields) then return Utils.fail(L('Could not update the vehicle')) end

    -- The entity no longer exists: forget the stale "out" entry.
    if type(NZ.Vehicles.clearOut) == 'function' then
      NZ.Vehicles.clearOut(rowPlate)
    elseif type(NZ.Vehicles.out) == 'table' then
      NZ.Vehicles.out[rowPlate] = nil
    end
    -- Its saved trailer comes back with it: never leave a second copy in the world.
    if row.state ~= 'garaged' and type(NZ.Vehicles.removeTrailerOf) == 'function' then
      pcall(NZ.Vehicles.removeTrailerOf, rowPlate, row)
    end

    log('vehicle.garage', { plate = rowPlate, from = row.garageKey, to = key, previousState = row.state })
    return Utils.ok(nil)
  end

  local result
  if type(NZ.Vehicles.withLock) == 'function' then
    result = NZ.Vehicles.withLock(p, apply)
  else
    result = apply()
  end
  if type(result) == 'table' and result.ok == true then return true end
  return false, type(result) == 'table' and result.error or L('Something went wrong')
end)

--- ImpoundVehicle(plate, { locationId, reason, fee, hours, retrievable, netId }) -> ok, error
export('ImpoundVehicle', function(plate, opts)
  if notReady() then return false, L('Garages are still loading') end
  local p = Utils.plate(plate)
  if not p then return false, L('Invalid plate') end
  if type(NZ.Impound.impound) ~= 'function' then return false, L('Impounds are not available') end
  opts = type(opts) == 'table' and opts or {}
  local clean = {
    locationId = positiveId(opts.locationId),
    reason = safeText(opts.reason, 120),
    fee = num(opts.fee, 0, MAX_MONEY, nil, true),
    hours = num(opts.hours, 0, 720, nil),
    retrievable = type(opts.retrievable) == 'boolean' and opts.retrievable or nil,
    netId = positiveId(opts.netId),
    byName = safeText(opts.byName, 60),
  }
  return NZ.Impound.impound(p, clean, nil)
end)

--- AddServiceRecord(plate, { item, mileage, shop, at }) -> true | false, error
export('AddServiceRecord', function(plate, entry)
  local p = Utils.plate(plate)
  if not p then return false, L('Invalid plate') end
  if type(entry) ~= 'table' then return false, L('Invalid service record') end
  local item = safeText(entry.item, 64)
  if not item then return false, L('A service item is required') end
  local row = NZ.DB.getVehicle(p)
  if not row then return false, L('Vehicle not found') end

  local now = os.time()
  local record = {
    item = item,
    mileage = Utils.round(num(entry.mileage, 0, MAX_MILEAGE, tonumber(row.mileage) or 0), 1),
    shop = safeText(entry.shop, 64) or '',
    at = num(entry.at, 0, now + 86400, now, true),
  }
  if NZ.DB.events.add(row.plate or p, 'service', record) == false then
    return false, L('Could not save the record')
  end
  log('vehicle.service', { plate = row.plate or p, item = record.item, shop = record.shop, mileage = record.mileage })
  return true
end)

--- AddOwnershipRecord(plate, { identifier, name, via, at, price }) -> true | false, error
export('AddOwnershipRecord', function(plate, entry)
  local p = Utils.plate(plate)
  if not p then return false, L('Invalid plate') end
  if type(entry) ~= 'table' then return false, L('Invalid ownership record') end
  if not NZ.DB.plateExists(p) then return false, L('Vehicle not found') end

  local now = os.time()
  local identifier = identifierArg(entry.identifier)
  local record = {
    identifier = identifier,
    name = safeText(entry.name, 100) or characterName(identifier),
    via = safeText(entry.via, 32) or 'script',
    at = num(entry.at, 0, now + 86400, now, true),
    price = num(entry.price, 0, MAX_MONEY, nil, true),
  }
  if NZ.DB.events.add(p, 'owner', record) == false then
    return false, L('Could not save the record')
  end
  log('vehicle.ownerRecord', { plate = p, identifier = identifier, name = record.name, via = record.via, price = record.price })
  return true
end)

--- IsVehicleOut(plate) -> boolean (out in the world and its entity still exists)
export('IsVehicleOut', function(plate)
  local p = Utils.plate(plate)
  if not p or type(NZ.Vehicles.isOut) ~= 'function' then return false end
  return NZ.Vehicles.isOut(p) == true
end)

---------------------------------------------------------------------------------------
-- Locations & houses
---------------------------------------------------------------------------------------

local LOCATION_KINDS = { garage = true, job = true, private = true, impound = true }

--- GetLocations(kind|nil) -> { Location } (database locations, houses excluded)
export('GetLocations', function(kind)
  if kind ~= nil and not LOCATION_KINDS[kind] then return {} end
  return Utils.deepCopy(NZ.Locations.all(kind))
end)

local function houseIdArg(value)
  if type(value) == 'number' then
    if value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
  end
  if type(value) ~= 'string' then return nil end
  local s = Utils.trim(value)
  if s == '' or #s > 60 or s:find('%c') then return nil end
  return s
end

--- RegisterHouseGarage(houseId, { name, coords = vec4, spawn = vec4|nil, hidden = boolean|nil })
--- -> ok, error. hidden = true: the housing script draws the garage interaction itself and
--- calls the OpenHouseGarage / StoreHouseGarage client exports (no marker / target from us).
export('RegisterHouseGarage', function(houseId, data)
  houseId = houseIdArg(houseId)
  if not houseId then return false, L('Invalid house id') end
  if type(data) ~= 'table' or not Utils.v4(data.coords) then return false, L('Invalid house coordinates') end
  if data.spawn ~= nil and not Utils.v4(data.spawn) then return false, L('Invalid house coordinates') end
  local clean = {
    name = safeText(data.name or data.label, 60),
    coords = Utils.v4(data.coords),
    spawn = data.spawn ~= nil and Utils.v4(data.spawn) or nil,
    hidden = data.hidden == true,
  }
  if type(NZ.Housing.register) == 'function' then
    local res, err = NZ.Housing.register(houseId, clean)
    if res == false then return false, err end
    return true
  end
  local loc, err = NZ.Locations.registerHouse(houseId, clean)
  return loc ~= nil, err
end)

--- RemoveHouseGarage(houseId) -> ok
export('RemoveHouseGarage', function(houseId)
  houseId = houseIdArg(houseId)
  if not houseId then return false, L('Invalid house id') end
  if type(NZ.Housing.remove) == 'function' then
    local res, err = NZ.Housing.remove(houseId)
    if res == false then return false, err end
    return true
  end
  NZ.Locations.removeHouse(houseId)
  return true
end)

--- SetHouseAccess(houseId, { identifier, ... }) -> ok, error
export('SetHouseAccess', function(houseId, identifiers)
  houseId = houseIdArg(houseId)
  if not houseId then return false, L('Invalid house id') end
  if type(identifiers) ~= 'table' then return false, L('Invalid identifier list') end
  local list, seen = {}, {}
  for _, value in ipairs(identifiers) do
    if #list >= 100 then break end
    local identifier = identifierArg(value)
    if identifier and not seen[identifier] then
      seen[identifier] = true
      list[#list + 1] = identifier
    end
  end
  if type(NZ.Housing.setAccess) ~= 'function' then return false, L('House garages are not available') end
  local res, err = NZ.Housing.setAccess(houseId, list)
  if res == false then return false, err end
  return true
end)

--- RefreshHousing(resource|nil) -> ok. Re-reads the housing data (throttled, asynchronous):
--- one supported housing script (resource name or house id prefix such as 'qs') or all (nil).
--- For housing scripts' garage add / update / remove hooks (install/housing/*).
export('RefreshHousing', function(resource)
  if type(NZ.Housing.refresh) ~= 'function' then return false, L('House garages are not available') end
  if resource ~= nil then
    resource = safeText(resource, 64)
    if not resource then return false, L('Invalid request') end
  end
  if NZ.Housing.refresh(resource) == false then
    if resource ~= nil then return false, L('Unknown housing resource') end
    return false, L('Garages are still loading')
  end
  return true
end)
