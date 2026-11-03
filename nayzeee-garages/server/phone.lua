--[[
  nayzeee-garages — phone garage app integration (server): NZ.Phone.

  Server exports for phone garage apps (lb-phone, NPWD garage apps, qs-smartphone, ...).
  Ready-to-copy adapters for each phone live in install/phone/ (see its README.md).

    GetPhoneVehicles(source)            -> { PhoneVehicle } | nil, error
    ClaimVehicleForValet(source, plate) -> ValetData | nil, error
    ReleaseValetClaim(source, plate)    -> true | false, error
    MarkValetSpawned(source, plate, netId) -> true | false, error

  Net events for phone CLIENT files (the source is the reporting player):
    'nz:phone:spawned' (plate, netId)   the phone created the valet vehicle
    'nz:phone:failed'  (plate)          the phone could not create it: put it back

  Valet flow: ClaimVehicleForValet applies the rules of taking a vehicle out of its garage
  (owner / shared access, blocked, impounded, finance overdue, already out, access to the
  garage it is parked in incl. private group membership; fleet vehicles, saved trailers and
  categories outside Config.Phone.valetTypes are refused), marks it out under
  NZ.Vehicles.withLock and returns its props / damage / fuel. The phone spawns it and
  reports the entity (MarkValetSpawned / 'nz:phone:spawned' -> NZ.Vehicles.markSpawned:
  tracking, keys, duplicate protection; plate and model must match). A watchdog adopts a
  valet vehicle found by plate + model when the phone never reports it, and puts the vehicle
  back in its garage when no copy appears before the claim times out, the phone reports a
  failure, or the claimant leaves / unloads their character. Undelivered claims are kept in
  the resource KVP ('nz_phone_claim:<plate>') and resumed after a resource restart.

  Optional Config.Phone (config/config.lua) overrides the defaults below. Built only on
  the public NZ.Vehicles / NZ.DB / NZ.Locations / NZ.Access / NZ.Bridge APIs.
]]

local Phone = NZ.Phone
local Utils = NZ.Utils

local DEFAULTS = {
  valet = true,                 -- allow phone valet claims at all
  valetTypes = { car = true },  -- vehicle categories a valet may deliver ('car' | 'sea' | 'air')
  claimTimeout = 60,            -- seconds the phone has to create the vehicle before it goes back
  applyData = true,             -- re-apply saved damage / fuel / mileage to the delivered vehicle
  maxPending = 2,               -- undelivered valet claims per player
  listShared = true,            -- GetPhoneVehicles also lists vehicles shared with the player
  hints = true,                 -- console hint at boot for detected phones without an adapter
}

local TICK_MS = 2000            -- watchdog interval while claims are pending
local SPAWN_WAIT_MS = 10000     -- MarkValetSpawned: wait this long for the entity's plate
local WAIT_GRACE = SPAWN_WAIT_MS // 1000 + 5 -- max seconds a waiting report extends a claim
local KVP_PREFIX = 'nz_phone_claim:' -- undelivered claims survive a resource restart
local MAX_STORED_CLAIMS = 500
local LIST_CACHE_SECONDS = 3    -- a rate-limited list request gets the previous answer
local MAX_PLATE_LENGTH = 16
local MAX_ID = 0x7FFFFFFF

-- Phones (and NPWD garage apps) with a file in install/phone/ or a README section.
-- skipIf: npwd_qbx_garages `provide`s npwd_qb_garage, which may then look started too.
local PHONES = {
  { name = 'lb-phone', folder = 'install/phone/lb-phone' },
  { name = 'npwd_qbx_garages', folder = 'install/phone/npwd_qbx_garages' },
  { name = 'npwd_qb_garage', folder = 'install/phone/npwd_qb_garage', skipIf = 'npwd_qbx_garages' },
  { name = 'npwd_esx_garage', folder = 'install/phone/npwd_esx_garage' },
  { name = 'qs-smartphone', folder = 'install/phone/generic' },
  { name = 'qs-smartphone-pro', folder = 'install/phone/generic' },
  { name = 'yseries', folder = 'install/phone/generic' },
  { name = 'gksphone', folder = 'install/phone/generic' },
  { name = 'okokPhone', folder = 'install/phone/generic' },
  { name = 'high-phone', folder = 'install/phone/generic' },
}

local claims = {}       -- [plate] = { token, src, identifier, at, prevLastOut, garageKey, hash, init, dropped, waiting }
local lists = {}        -- [src] = { at, identifier, list } last GetPhoneVehicles answer
local warned = {}       -- warn-once keys
local watching = false
local tokenSeq = 0
local labels = { at = nil, byName = nil, byHash = nil }

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function ok(data) return Utils.ok(data) end
local function fail(message) return Utils.fail(message) end

local function warnOnce(key, message)
  if warned[key] then return end
  warned[key] = true
  lib.print.warn(('[nayzeee-garages] phone: %s'):format(message))
end

local function option(name)
  local cfg = type(Config.Phone) == 'table' and Config.Phone or nil
  local value = cfg and cfg[name]
  if value == nil then return DEFAULTS[name] end
  return value
end

local function setting(path, default)
  if not (NZ.Settings and NZ.Settings.get) then return default end
  local okGet, value = pcall(NZ.Settings.get, path, default)
  if not okGet or value == nil then return default end
  return value
end

local function log(event, src, data)
  if not (NZ.Logs and NZ.Logs.add) then return end
  local success, err = pcall(NZ.Logs.add, event, src, data)
  if not success then warnOnce('log:' .. event, ('could not log %s: %s'):format(event, tostring(err))) end
end

local function claimTimeout()
  return Utils.clamp(tonumber(option('claimTimeout')) or DEFAULTS.claimTimeout, 15, 300)
end

--- Online player id (integer) or nil.
local function validSrc(src)
  local n = tonumber(src)
  if not n or n ~= n or n < 1 or n > MAX_ID or n ~= math.floor(n) then return nil end
  n = math.tointeger(n)
  if GetPlayerName(tostring(n)) == nil then return nil end
  return n
end

local function readPlate(value)
  if type(value) == 'number' then value = tostring(math.floor(value)) end
  local plate = Utils.plate(value)
  if plate and #plate <= MAX_PLATE_LENGTH and not plate:find('%c') then return plate end
  return nil
end

local function readNetId(value)
  local n = tonumber(value)
  if not n or n ~= n or n < 1 or n > MAX_ID or n ~= math.floor(n) then return nil end
  return math.tointeger(n)
end

local function identifierOf(src)
  local success, identifier = pcall(NZ.Bridge.getIdentifier, src)
  if success and type(identifier) == 'string' and identifier ~= '' then return identifier end
  return nil
end

local function percent(value, default)
  local n = tonumber(value)
  if not n or n ~= n then return default end
  return Utils.round(Utils.clamp(n, 0, 100), 1)
end

local function nonEmpty(value)
  if type(value) ~= 'string' then return nil end
  local s = Utils.trim(value)
  if s == '' then return nil end
  return s
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
  local h = toSigned(row.hash)
  if h and h ~= 0 then return h end
  if type(row.model) == 'string' and row.model ~= '' then return toSigned(joaat(row.model)) end
  local props = type(row.props) == 'table' and row.props or nil
  local fromProps = props and toSigned(props.model)
  if fromProps and fromProps ~= 0 then return fromProps end
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

--- Is `entity` of model `hash` (true / nil = any model)?
local function modelMatches(entity, hash)
  if hash == nil or hash == true then return true end
  return toSigned(GetEntityModel(entity)) == hash
end

--- One pass over the world: first entity of each wanted plate. `wanted` = { [plate] = hash }
--- (hash = true: any model; a copy of the claimed vehicle has the claimed model).
local function findEntities(wanted)
  local found = {}
  for _, entity in ipairs(GetAllVehicles() or {}) do
    if isVehicleEntity(entity) then
      local plate = plateOf(entity)
      local want = plate and wanted[plate]
      if want and not found[plate] and modelMatches(entity, want) then found[plate] = entity end
    end
  end
  return found
end

local function findEntity(plate, hash)
  return findEntities({ [plate] = hash or true })[plate]
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

local function notifyPlayer(src, kind, message)
  if not validSrc(src) then return end
  TriggerClientEvent('nz:client:notify', src, { type = kind, message = message })
end

--- Remember which resources call the phone exports (silences the boot hint for them).
local function rememberCaller()
  local resource = GetInvokingResource()
  if type(resource) ~= 'string' or resource == '' or resource == NZ.ResourceName then return end
  local key = 'nz_phone_seen:' .. resource
  if GetResourceKvpString(key) == nil then SetResourceKvp(key, tostring(os.time())) end
end

---------------------------------------------------------------------------------------
-- Vehicle labels (framework shared vehicle lists; optional, never required)
---------------------------------------------------------------------------------------

local function loadSharedVehicles()
  local now = os.time()
  if labels.at and now - labels.at < 300 then return end
  labels.at = now
  labels.byName, labels.byHash = nil, nil
  if NZ.Framework == 'qbx' then
    local okName, byName = pcall(function() return exports.qbx_core:GetVehiclesByName() end)
    local okHash, byHash = pcall(function() return exports.qbx_core:GetVehiclesByHash() end)
    labels.byName = okName and type(byName) == 'table' and byName or nil
    labels.byHash = okHash and type(byHash) == 'table' and byHash or nil
  elseif NZ.Framework == 'qb' then
    local okCore, core = pcall(function() return exports['qb-core']:GetCoreObject() end)
    local shared = okCore and type(core) == 'table' and type(core.Shared) == 'table' and core.Shared or nil
    labels.byName = shared and type(shared.Vehicles) == 'table' and shared.Vehicles or nil
    labels.byHash = shared and type(shared.VehicleHashes) == 'table' and shared.VehicleHashes or nil
  end
end

--- Display name and brand of a vehicle when the framework knows it.
---@return string|nil label, string|nil brand
local function vehicleLabel(row)
  local success, entry = pcall(function()
    loadSharedVehicles()
    local found = type(row.model) == 'string' and labels.byName and labels.byName[row.model] or nil
    if not found and labels.byHash then
      local hash = rowHash(row)
      found = hash and (labels.byHash[hash] or labels.byHash[tostring(hash)]) or nil
    end
    return found
  end)
  if not success or type(entry) ~= 'table' then return nil, nil end
  local name = nonEmpty(entry.name) or nonEmpty(entry.label)
  return name, nonEmpty(entry.brand)
end

---------------------------------------------------------------------------------------
-- Valet rules
---------------------------------------------------------------------------------------

local function valetTypeAllowed(vtype)
  local types = option('valetTypes')
  if type(types) ~= 'table' then return vtype == 'car' end
  if types[vtype] == true then return true end
  for _, value in ipairs(types) do
    if value == vtype then return true end
  end
  return false
end

--- Garage-session view of where the vehicle is parked, for NZ.Vehicles.canDrive.
--- retrieveMode 'anywhere' (or a vehicle with no garage): any personal garage of its type.
---@return table|nil session, string|nil error
local function parkedSession(src, row, mode, resolvedCache, ctx)
  local key = row.garageKey
  if key and mode ~= 'anywhere' then
    local resolved = resolvedCache and resolvedCache[key]
    if resolved == nil then
      resolved = NZ.Locations.resolveKey(key) or false
      if resolvedCache then resolvedCache[key] = resolved end
    end
    if not resolved then return nil, L('This garage is no longer available') end
    local location = resolved.location
    if location.enabled == false then return nil, L('This garage is closed') end
    local allowed, reason = NZ.Access.canUse(src, location)
    if not allowed then return nil, reason or L('You do not have access to this garage') end
    -- A private garage instance: membership of that very group (canUse only checks for any
    -- group of the player at this location).
    if resolved.kind == 'G' then
      local identifier = type(ctx) == 'table' and ctx.identifier or nil
      local okRole, role = pcall(NZ.Private.role, resolved.groupId, identifier)
      if not (identifier and okRole and role) then return nil, L('You do not have a garage here') end
    end
    return {
      garageKey = key,
      location = location,
      locationId = location.id,
      groupId = resolved.groupId,
      houseId = resolved.houseId,
    }, nil
  end
  local pseudo = {
    kind = 'garage', source = 'personal', enabled = true,
    vehicleType = NZ.Vehicles.vehicleTypeOf(row), name = row.frameworkGarage or '',
  }
  return { garageKey = key, location = pseudo }, nil
end

--- May `src` have this vehicle delivered by a phone valet right now? Same rules as taking it
--- out of its garage, without the proximity check (and fleet vehicles are never delivered).
---@param ctx table { identifier, shared?, keyNames, retrieveMode, resolved? }
---@return boolean allowed, string|nil reason
local function checkValet(src, row, ctx)
  if option('valet') == false then return false, L('The valet service is not available') end
  if NZ.Vehicles.fleetOf(row) then return false, L('Fleet vehicles cannot be delivered') end
  local access = NZ.Vehicles.accessOf(src, row, nil, ctx)
  if access ~= 'owner' and access ~= 'shared' then return false, L('You do not have access to this vehicle') end
  if row.blocked then return false, L('This vehicle is blocked') end
  local state = row.state or 'garaged'
  if state == 'impounded' then
    local where = type(row.impound) == 'table' and row.impound.locationName or nil
    return false, L('Impounded at {impound}', { impound = where or L('the impound') })
  end
  if state == 'out' or claims[row.plate] then return false, L('Vehicle is already out') end
  if type(row.finance) == 'table' and row.finance.overdue then return false, L('Finance payment overdue') end
  if not valetTypeAllowed(NZ.Vehicles.vehicleTypeOf(row)) then
    return false, L('The valet cannot deliver this type of vehicle')
  end
  if setting('vehicles.trailers', true) == true and type(row.trailer) == 'table' then
    return false, L('Take this vehicle out at its garage to bring its trailer')
  end
  local session, err = parkedSession(src, row, ctx.retrieveMode, ctx.resolved, ctx)
  if not session then return false, err end
  return NZ.Vehicles.canDrive(src, row, session, { cache = ctx })
end

---------------------------------------------------------------------------------------
-- Vehicle list
---------------------------------------------------------------------------------------

local function sharedSet(identifier)
  local set = {}
  local success, list = pcall(NZ.DB.shares.forIdentifier, identifier)
  if not success or type(list) ~= 'table' then return set end
  for _, entry in ipairs(list) do
    local plate = Utils.plate(type(entry) == 'table' and entry.plate or entry)
    if plate then set[plate] = true end
  end
  return set
end

local function keyName(key, ctx)
  if not key then return nil end
  local cached = ctx.keyNames[key]
  if cached ~= nil then return cached or nil end
  local name = NZ.Locations.keyName(key)
  ctx.keyNames[key] = name or false
  return name
end

local function locationCoords(key, ctx)
  if not key then return nil end
  local resolved = ctx.resolved[key]
  if resolved == nil then
    resolved = NZ.Locations.resolveKey(key) or false
    ctx.resolved[key] = resolved
  end
  return resolved and firstOpenPoint(resolved.location) or nil
end

local function impoundView(row)
  local info = row.impound
  if type(info) ~= 'table' then return nil end
  local location = tonumber(info.locationId) and NZ.Locations.get(tonumber(info.locationId)) or nil
  return {
    reason = nonEmpty(info.reason),
    fee = math.max(0, math.floor(tonumber(info.fee) or 0)),
    by = nonEmpty(info.byName),
    at = tonumber(info.at),
    releaseAt = tonumber(info.releaseAt),
    retrievable = info.retrievable ~= false,
    locationId = tonumber(info.locationId),
    location = nonEmpty(info.locationName) or (type(location) == 'table' and location.name) or nil,
    coords = firstOpenPoint(location),
  }
end

local function financeView(row)
  local finance = row.finance
  if type(finance) ~= 'table' then return nil end
  local balance = tonumber(finance.balance) or 0
  if balance <= 0 then return nil end
  return {
    balance = math.floor(balance),
    payment = math.floor(tonumber(finance.payment) or 0),
    paymentsLeft = tonumber(finance.paymentsLeft),
    nextPaymentHours = tonumber(finance.nextPaymentHours),
    overdue = finance.overdue == true,
  }
end

--- Neutral phone view of a vehicle row (types: see the header of install/phone/README.md).
local function toPhoneVehicle(src, row, ctx)
  local plate = row.plate
  local access = NZ.Vehicles.accessOf(src, row, nil, ctx)
  local state = row.state or 'garaged'
  local label, brand = vehicleLabel(row)
  local finance = financeView(row)

  local inWorld, coords = false, nil
  if state == 'out' then
    local out, entity = NZ.Vehicles.isOut(plate)
    if out and entity then
      inWorld = true
      coords = Utils.v3(GetEntityCoords(entity))
    end
  end

  local canValet, valetReason = checkValet(src, row, ctx)
  local impound = state == 'impounded' and impoundView(row) or nil

  return {
    plate = plate,
    plateText = type(row.dbPlate) == 'string' and row.dbPlate or plate,
    model = row.model,
    hash = rowHash(row),
    label = label,
    brand = brand,
    nickname = nonEmpty(row.nickname),
    vehicleType = NZ.Vehicles.vehicleTypeOf(row),
    ownerType = row.ownerType or 'player',
    state = state,
    garageKey = row.garageKey,
    garageName = keyName(row.garageKey, ctx) or nonEmpty(row.frameworkGarage),
    garageCoords = locationCoords(row.garageKey, ctx),
    impound = impound,
    fuel = percent(row.fuel, 100),
    engine = percent(row.engine, 100),
    body = percent(row.body, 100),
    mileage = Utils.round(math.max(tonumber(row.mileage) or 0, 0), 1),
    financed = finance ~= nil,
    finance = finance,
    blocked = row.blocked == true,
    isOwner = access == 'owner',
    shared = access == 'shared',
    ownerName = (access == 'shared' and row.owner) and NZ.Bridge.getCharacterName(row.owner) or nil,
    inWorld = inWorld,
    coords = coords or (impound and impound.coords) or locationCoords(row.garageKey, ctx),
    valetPending = claims[plate] ~= nil,
    canValet = canValet == true,
    valetReason = (canValet ~= true) and valetReason or nil,
  }
end

--- The player's vehicles (and vehicles shared with them) for a phone garage app.
---@param src number
---@return table|nil list, string|nil error
function Phone.vehicles(src)
  src = validSrc(src)
  if not src then return nil, L('Invalid player') end
  if not NZ.Ready then return nil, L('Garages are still loading') end
  local identifier = identifierOf(src)
  if not identifier then return nil, L('Your character is not loaded') end

  if not NZ.Access.rateLimit(src, 'phone:list', 1000) then
    local cached = lists[src]
    if cached and cached.identifier == identifier and os.time() - cached.at <= LIST_CACHE_SECONDS then
      return Utils.deepCopy(cached.list)
    end
    return nil, L('Please wait a moment before trying again')
  end

  local ctx = {
    identifier = identifier,
    shared = option('listShared') ~= false and sharedSet(identifier) or {},
    keyNames = {},
    resolved = {},
    retrieveMode = setting('garages.retrieveMode', 'last'),
  }

  local rows, seen = {}, {}
  local owned = NZ.DB.getVehiclesByOwner(identifier)
  if type(owned) ~= 'table' then owned = {} end
  for _, row in ipairs(owned) do
    if type(row) == 'table' and row.plate and not seen[row.plate] then
      seen[row.plate] = true
      rows[#rows + 1] = row
    end
  end
  if option('listShared') ~= false then
    local plates = {}
    for plate in pairs(ctx.shared) do
      if not seen[plate] then plates[#plates + 1] = plate end
    end
    if #plates > 0 then
      for _, row in ipairs(NZ.DB.getVehiclesByPlates(plates) or {}) do
        if type(row) == 'table' and row.plate and not seen[row.plate] then
          seen[row.plate] = true
          rows[#rows + 1] = row
        end
      end
    end
  end

  local list = {}
  for _, row in ipairs(rows) do
    local built, item = pcall(toPhoneVehicle, src, row, ctx)
    if built and type(item) == 'table' then
      list[#list + 1] = item
    else
      warnOnce('list:' .. tostring(row.plate), ('could not list vehicle %s: %s'):format(tostring(row.plate), tostring(item)))
    end
  end
  table.sort(list, function(a, b)
    if a.isOwner ~= b.isOwner then return a.isOwner end
    return a.plate < b.plate
  end)

  lists[src] = { at = os.time(), identifier = identifier, list = list }
  return list
end

---------------------------------------------------------------------------------------
-- Valet claims
---------------------------------------------------------------------------------------

local function pendingCount(src)
  local n = 0
  for _, claim in pairs(claims) do
    if claim.src == src then n = n + 1 end
  end
  return n
end

--- Remember an undelivered claim across a resource restart (see Phone.recover).
local function persist(plate, claim)
  local encoded, text = pcall(json.encode, {
    at = claim.at, prev = tonumber(claim.prevLastOut), identifier = claim.identifier,
    hash = claim.hash, garageKey = claim.garageKey,
  })
  if not encoded or type(text) ~= 'string' then
    warnOnce('persist', ('could not remember the valet claim of %s: %s'):format(plate, tostring(text)))
    return
  end
  SetResourceKvp(KVP_PREFIX .. plate, text)
end

local function unpersist(plate)
  DeleteResourceKvp(KVP_PREFIX .. plate)
end

--- The claim is over (delivered, put back, or superseded): forget it.
local function endClaim(plate, claim)
  if claims[plate] ~= claim then return false end
  claims[plate] = nil
  unpersist(plate)
  return true
end

--- A vehicle of another model was reported for this claim (e.g. through the generic
--- 'nz:garage:spawned' callback, which only checks the plate): stop tracking it, so the
--- real vehicle can still be reported or adopted and the claim times out normally.
--- anyEntry: also an entry this claim did not create (re-adopted by plate after a restart).
local function dropWrongModel(plate, claim, anyEntry)
  local entry = NZ.Vehicles.out[plate]
  if not (entry and (anyEntry or entry.phone == claim.token) and isVehicleEntity(entry.entity)) then return end
  local entity = entry.entity
  if modelMatches(entity, claim.hash) then return end
  log('security.model', claim.src, { plate = plate, netId = entry.netId, expected = claim.hash,
    actual = toSigned(GetEntityModel(entity)), reason = 'phone valet tracked another model' })
  pcall(function() Entity(entity).state:set('nzPlate', nil, true) end)
  NZ.Vehicles.clearOut(plate)
end

--- (Re)register the claim's out entry so NZ.Vehicles.markSpawned accepts the phone's entity.
local function ensureEntry(plate, claim)
  local entry = NZ.Vehicles.out[plate]
  if entry then
    if entry.phone == claim.token and not entry.entity then entry.at = os.time() end
    return
  end
  NZ.Vehicles.setOut(plate, {
    src = claim.src,
    identifier = claim.identifier,
    garageKey = claim.garageKey,
    at = os.time(),
    spawner = false,
    phone = claim.token,
  })
end

--- Put a claimed vehicle back in its garage when the claim still owns the database state.
---@return boolean done (false = try again later), boolean restored
local function restore(plate, claim)
  local row = NZ.DB.getVehicle(plate)
  if type(row) ~= 'table' then
    if NZ.DB.plateExists(plate) == false then
      local gone = NZ.Vehicles.out[plate]
      if gone and gone.phone == claim.token then NZ.Vehicles.clearOut(plate) end
      return true, false
    end
    return false, false
  end
  local restored = false
  if row.state == 'out' and tonumber(row.lastOut) == claim.at then
    if not NZ.DB.updateVehicle(plate, { state = 'garaged', lastOut = claim.prevLastOut or false }) then
      return false, false
    end
    restored = true
  end
  local entry = NZ.Vehicles.out[plate]
  if entry and entry.phone == claim.token and not isVehicleEntity(entry.entity) then
    NZ.Vehicles.clearOut(plate)
  end
  return true, restored
end

--- The valet vehicle exists and is tracked: hand nayzeee's saved data to its owner client.
local function finish(plate, claim, entity)
  if not endClaim(plate, claim) then return end
  if option('applyData') ~= false and type(claim.init) == 'table' and isVehicleEntity(entity) then
    local success, err = pcall(function() Entity(entity).state:set('nzInit', claim.init, true) end)
    if not success then warnOnce('nzInit', ('could not attach the saved vehicle data: %s'):format(tostring(err))) end
  end
  Utils.debug('phone valet delivered', plate)
end

local function buildData(row, plate, hash, now)
  local plateText = nonEmpty(row.dbPlate) and row.dbPlate or plate
  local props = Utils.deepCopy(type(row.props) == 'table' and row.props or {})
  local fuel = percent(row.fuel, 100)
  props.plate = plateText
  props.model = hash
  props.fuelLevel = fuel
  local damage = nil
  if setting('vehicles.saveDamage', true) == true and type(row.damage) == 'table' then
    damage = Utils.deepCopy(row.damage)
  end
  local label, brand = vehicleLabel(row)
  local vehicle = {
    plate = plateText,
    hash = hash,
    model = row.model or '',
    props = props,
    damage = damage,
    fuel = fuel,
    engine = percent(row.engine, 100),
    body = percent(row.body, 100),
    mileage = tonumber(row.mileage) or 0,
  }
  local ctx = { keyNames = {} }
  return {
    plate = plate,
    plateText = plateText,
    hash = hash,
    model = row.model,
    label = label,
    brand = brand,
    nickname = nonEmpty(row.nickname),
    vehicleType = NZ.Vehicles.vehicleTypeOf(row),
    props = props,
    damage = damage,
    fuel = vehicle.fuel,
    engine = vehicle.engine,
    body = vehicle.body,
    mileage = vehicle.mileage,
    garageKey = row.garageKey,
    garageName = keyName(row.garageKey, ctx) or nonEmpty(row.frameworkGarage),
    claimedAt = now,
    expiresAt = now + claimTimeout(),
  }, vehicle
end

local function doClaim(src, plate, identifier, resource)
  local row = NZ.DB.getVehicle(plate)
  if type(row) ~= 'table' then return fail(L('Vehicle not found')) end
  plate = row.plate or plate

  local ctx = { identifier = identifier, keyNames = {}, retrieveMode = setting('garages.retrieveMode', 'last') }
  local allowed, reason = checkValet(src, row, ctx)
  if not allowed then return fail(reason or L('You cannot do that right now')) end
  if NZ.Vehicles.isOut(plate) then return fail(L('Vehicle is already out')) end

  local hash = rowHash(row)
  if not hash then return fail(L('Unknown vehicle model')) end

  -- An untracked copy of this vehicle (same plate AND model; a car of another model that
  -- shows this plate is not touched) is a duplicate: remove it when nobody uses it.
  local stray = findEntity(plate, hash)
  if stray then
    if isOccupied(stray) then
      log('security.dupe', src, { plate = plate, reason = 'phone valet while an occupied copy exists' })
      return fail(L('Vehicle is already out'))
    end
    DeleteEntity(stray)
    log('security.dupe', src, { plate = plate, reason = 'removed an untracked copy before a phone valet' })
  end

  local now = os.time()
  tokenSeq = tokenSeq + 1
  local claim = {
    token = tokenSeq,
    src = src,
    identifier = identifier,
    at = now,
    prevLastOut = row.lastOut,
    garageKey = row.garageKey,
    hash = hash,
  }
  -- written before the database so a restart during the write is recovered too
  persist(plate, claim)
  if not NZ.DB.updateVehicle(plate, { state = 'out', lastOut = now }) then
    unpersist(plate)
    return fail(L('Something went wrong'))
  end
  NZ.Vehicles.setOut(plate, {
    src = src,
    identifier = identifier,
    garageKey = row.garageKey,
    at = now,
    spawner = false,
    phone = claim.token,
  })

  local built, data, init = pcall(buildData, row, plate, hash, now)
  if not built or type(data) ~= 'table' then
    local done = restore(plate, claim)
    if done then unpersist(plate) end -- else: put back at the next start (Phone.recover)
    lib.print.error(('[nayzeee-garages] phone valet for %s failed: %s'):format(plate, tostring(data)))
    return fail(L('Something went wrong'))
  end
  claim.init = init
  claims[plate] = claim
  Phone.watch()

  log('vehicle.retrieve', src, {
    plate = plate, garage = row.garageKey, via = 'phone', resource = resource, owner = row.owner,
  })
  return ok(data)
end

--- Mark a vehicle out for a phone valet and return what the phone needs to spawn it.
---@param src number
---@param plate string
---@return table|nil data, string|nil error
function Phone.claim(src, plate)
  src = validSrc(src)
  plate = readPlate(plate)
  if not src or not plate then return nil, L('Invalid vehicle') end
  if not NZ.Ready then return nil, L('Garages are still loading') end
  if option('valet') == false then return nil, L('The valet service is not available') end
  local identifier = identifierOf(src)
  if not identifier then return nil, L('Your character is not loaded') end
  if not NZ.Access.rateLimit(src, 'phone:claim', 2000) then
    return nil, L('Please wait a moment before trying again')
  end
  if pendingCount(src) >= math.max(1, tonumber(option('maxPending')) or DEFAULTS.maxPending) then
    return nil, L('Your other vehicle is still on its way')
  end
  if NZ.Vehicles.incapacitated(src) then return nil, L('You cannot do that right now') end
  if type(NZ.Interiors.playerInstance) == 'function' and NZ.Interiors.playerInstance(src) ~= nil then
    return nil, L('You cannot do that right now')
  end

  local resource = GetInvokingResource()
  local result = NZ.Vehicles.withLock(plate, doClaim, src, plate, identifier, resource)
  if type(result) == 'table' and result.ok == true then return result.data end
  return nil, type(result) == 'table' and result.error or L('Something went wrong')
end

--- The phone could not deliver a claimed vehicle: put it back in its garage. Refused while
--- any copy of the vehicle exists in the world.
---@param src number
---@param plate string
---@param why string|nil
---@return boolean released, string|nil error
function Phone.release(src, plate, why)
  src = validSrc(src)
  plate = readPlate(plate)
  if not src or not plate then return false, L('Invalid vehicle') end
  if not NZ.Access.rateLimit(src, 'phone:release', 500) then
    return false, L('Please wait a moment before trying again')
  end
  local claim = claims[plate]
  if not claim or claim.src ~= src then return false, L('This vehicle was not taken out by you') end
  local entry = NZ.Vehicles.out[plate]
  if (entry and isVehicleEntity(entry.entity)) or findEntity(plate, claim.hash) then
    return false, L('Vehicle is already out')
  end

  local result = NZ.Vehicles.withLock(plate, function()
    if claims[plate] ~= claim then return ok(false) end
    if findEntity(plate, claim.hash) then return fail(L('Vehicle is already out')) end
    local done, restored = restore(plate, claim)
    if not done then return fail(L('Something went wrong')) end
    endClaim(plate, claim)
    return ok(restored)
  end)
  if type(result) ~= 'table' or result.ok ~= true then
    return false, type(result) == 'table' and result.error or L('Something went wrong')
  end
  if result.data then
    log('vehicle.spawnFailed', src, { plate = plate, garage = claim.garageKey, via = 'phone', reason = why or 'released' })
  end
  return true
end

local function waitForPlate(netId, plate, timeoutMs)
  local deadline = GetGameTimer() + timeoutMs
  while true do
    local entity = NetworkGetEntityFromNetworkId(netId)
    if isVehicleEntity(entity) and plateOf(entity) == plate then return entity end
    if GetGameTimer() >= deadline then return nil end
    Wait(250)
  end
end

--- The phone created the valet vehicle: track it (keys, duplicate protection, store later).
---@param src number
---@param plate string
---@param netId number
---@return boolean success, string|nil error
function Phone.spawned(src, plate, netId)
  src = validSrc(src)
  plate = readPlate(plate)
  netId = readNetId(netId)
  if not src or not plate or not netId then return false, L('Invalid vehicle') end

  local claim = claims[plate]
  if not claim then
    -- Already recorded (e.g. reported by the phone's server and its client): not an error.
    local entry = NZ.Vehicles.out[plate]
    if entry and entry.src == src and entry.netId == netId then return true end
  end
  if not NZ.Access.rateLimit(src, 'phone:spawned', 250) then
    return false, L('Please wait a moment before trying again')
  end
  if not claim then return false, L('This vehicle was not taken out by you') end
  -- dropped: the claimant changed character meanwhile (the watchdog adopts it, no keys)
  if claim.src ~= src or claim.dropped then return false, L('This vehicle was not taken out by you') end

  -- A server-created vehicle gets its plate from the client a moment later. The claim does
  -- not time out while a report waits for it (at most WAIT_GRACE seconds past the timeout).
  claim.waiting = (claim.waiting or 0) + 1
  local entity = waitForPlate(netId, plate, SPAWN_WAIT_MS)
  claim.waiting = math.max(0, (claim.waiting or 1) - 1)
  if claims[plate] ~= claim then
    local entry = NZ.Vehicles.out[plate]
    if entry and entry.src == src and entry.netId == netId then return true end
    return false, L('This vehicle was not taken out by you')
  end
  -- The plate never arrived (e.g. the phone's client could not take control of a server-
  -- created vehicle): nothing to track. The watchdog still adopts it if the plate comes later.
  if not entity then return false, L('Vehicle not found') end
  if not modelMatches(entity, claim.hash) then
    log('security.model', src, { plate = plate, netId = netId, expected = claim.hash,
      actual = toSigned(GetEntityModel(entity)), reason = 'phone valet reported another model' })
    return false, L('This vehicle does not match its registration')
  end
  dropWrongModel(plate, claim)
  ensureEntry(plate, claim)

  local marked, err = NZ.Vehicles.markSpawned(src, plate, netId)
  if not marked then return false, err end
  finish(plate, claim, entity)
  return true
end

---------------------------------------------------------------------------------------
-- Watchdog: adopt unreported valet vehicles, roll back undelivered ones
---------------------------------------------------------------------------------------

local function adopt(plate, claim, entity)
  dropWrongModel(plate, claim)
  ensureEntry(plate, claim)
  local netId = NetworkGetNetworkIdFromEntity(entity)
  -- The claimant left (or changed character): track the vehicle, no keys for that source.
  local marked = not claim.dropped and netId and netId ~= 0 and NZ.Vehicles.markSpawned(claim.src, plate, netId)
  if marked == true then
    finish(plate, claim, entity)
    return
  end
  -- markSpawned refused (player gone, state changed): track it only while the claim still
  -- owns the database state, so duplicate protection keeps seeing the entity.
  local row = NZ.DB.getVehicle(plate)
  if type(row) == 'table' and row.state == 'out' and tonumber(row.lastOut) == claim.at then
    local entry = NZ.Vehicles.out[plate]
    if entry and entry.phone == claim.token then
      entry.netId = netId
      entry.entity = entity
      NZ.Vehicles.setOut(plate, entry)
      pcall(function() Entity(entity).state:set('nzPlate', plate, true) end)
    end
    finish(plate, claim, entity)
  elseif type(row) == 'table' then
    -- Stored, recovered or impounded meanwhile: the claim is over.
    endClaim(plate, claim)
  end
end

local function expire(plate, claim)
  if findEntity(plate, claim.hash) then return end -- created this very moment: adopted on the next tick
  local result = NZ.Vehicles.withLock(plate, function()
    if claims[plate] ~= claim then return ok(false) end
    if findEntity(plate, claim.hash) then return fail('spawned') end
    local done, restored = restore(plate, claim)
    if not done then return fail('restore') end
    endClaim(plate, claim)
    return ok(restored)
  end)
  if type(result) ~= 'table' or result.ok ~= true then
    if type(result) == 'table' and result.error == 'restore' then
      warnOnce('restore:' .. plate, ('could not put %s back in its garage yet, retrying'):format(plate))
    end
    return
  end
  if result.data then
    local why = claim.dropped and 'player left' or 'not delivered in time'
    log('vehicle.spawnFailed', claim.src, { plate = plate, garage = claim.garageKey, via = 'phone', reason = why })
    if not claim.dropped then
      notifyPlayer(claim.src, 'info', L('The valet could not deliver {plate}, it is back in its garage', { plate = plate }))
    end
  end
end

--- Keep an undelivered claim's out entry alive (no recover / retrieve while it is on its way).
local function keepAlive(plate, claim)
  local entry = NZ.Vehicles.out[plate]
  if entry then
    if entry.phone == claim.token and not entry.entity then entry.at = os.time() end
    return
  end
  -- The entry is gone (released through another path?): only re-create it while the claim
  -- still owns the database state.
  local row = NZ.DB.getVehicle(plate)
  if type(row) ~= 'table' then return end
  if row.state == 'out' and tonumber(row.lastOut) == claim.at then
    ensureEntry(plate, claim)
  elseif claims[plate] == claim then
    -- Put back through nayzeee's generic failure report ('nz:garage:spawned' failed = true),
    -- which keeps the claim's lastOut: restore the previous one.
    if row.state == 'garaged' and tonumber(row.lastOut) == claim.at then
      local result = NZ.Vehicles.withLock(plate, function()
        local fresh = NZ.DB.getVehicle(plate)
        if type(fresh) == 'table' and fresh.state == 'garaged' and tonumber(fresh.lastOut) == claim.at then
          NZ.DB.updateVehicle(plate, { lastOut = claim.prevLastOut or false })
        end
        return ok(true)
      end)
      if type(result) ~= 'table' or result.ok ~= true then return end -- busy: next tick
    end
    endClaim(plate, claim)
  end
end

local function tick()
  local snapshot, wanted = {}, {}
  for plate, claim in pairs(claims) do
    snapshot[#snapshot + 1] = { plate = plate, claim = claim }
    wanted[plate] = claim.hash or true
  end
  if #snapshot == 0 then return end
  local found = findEntities(wanted)
  local now = os.time()
  local timeout = claimTimeout()
  for _, item in ipairs(snapshot) do
    local plate, claim = item.plate, item.claim
    if claims[plate] == claim then
      dropWrongModel(plate, claim)
      local entry = NZ.Vehicles.out[plate]
      local tracked = entry and isVehicleEntity(entry.entity) and entry.entity or nil
      local age = now - claim.at
      -- a report waiting for its plate holds the claim, at most WAIT_GRACE seconds longer
      local overdue = age >= timeout and ((claim.waiting or 0) == 0 or age >= timeout + WAIT_GRACE)
      if tracked then
        finish(plate, claim, tracked)
      elseif found[plate] then
        adopt(plate, claim, found[plate])
      elseif claim.dropped or overdue then
        expire(plate, claim)
      else
        keepAlive(plate, claim)
      end
    end
  end
end

--- Start the watchdog thread (runs only while claims are pending).
function Phone.watch()
  if watching then return end
  watching = true
  CreateThread(function()
    while next(claims) ~= nil do
      Wait(TICK_MS)
      local success, err = pcall(tick)
      if not success then warnOnce('tick', ('valet watchdog failed: %s'):format(tostring(err))) end
    end
    watching = false
  end)
end

--- Pending (undelivered) claim of a plate, or nil.
---@param plate string
---@return table|nil { src, at, expiresAt }
function Phone.pending(plate)
  plate = readPlate(plate)
  local claim = plate and claims[plate]
  if not claim then return nil end
  return { src = claim.src, at = claim.at, expiresAt = claim.at + claimTimeout() }
end

---------------------------------------------------------------------------------------
-- Resource restart: claims that were still undelivered
---------------------------------------------------------------------------------------

local function storedClaimKeys()
  local keys = {}
  local handle = StartFindKvp(KVP_PREFIX)
  if type(handle) ~= 'number' or handle < 0 then return keys end
  while #keys < MAX_STORED_CLAIMS do
    local key = FindKvp(handle)
    if type(key) ~= 'string' then break end
    keys[#keys + 1] = key
  end
  EndFindKvp(handle)
  return keys
end

--- One remembered claim. The claim still owns the vehicle when the row is out since the
--- claim (lastOut) and no copy exists: it is re-armed, so the watchdog adopts the vehicle
--- if the phone still delivers it, or puts it back once the original claim times out (at
--- once when that time is over or the claimant is offline). Anything else is stale.
---@return string outcome 'rearmed' | 'delivered' | 'stale' | 'retry' | 'live'
local function recoverClaim(key)
  local plate = readPlate(key:sub(#KVP_PREFIX + 1))
  if plate and claims[plate] then return 'live' end -- claimed since the start: its own entry
  local decoded, data = pcall(json.decode, GetResourceKvpString(key) or '')
  local at = decoded and type(data) == 'table' and tonumber(data.at) or nil
  if not plate or not at then
    DeleteResourceKvp(key)
    return 'stale'
  end
  local row = NZ.DB.getVehicle(plate)
  if type(row) ~= 'table' then
    if NZ.DB.plateExists(plate) ~= false then return 'retry' end -- database not answering
    DeleteResourceKvp(key)
    return 'stale'
  end
  if row.plate and row.plate ~= plate then
    DeleteResourceKvp(key)
    return 'stale'
  end
  if row.state ~= 'out' or tonumber(row.lastOut) ~= at then
    DeleteResourceKvp(key)
    return 'stale'
  end
  local hash = toSigned(data.hash) or rowHash(row)
  if not hash or findEntity(plate, hash) then
    -- delivered before the restart (re-adopted by NZ.Vehicles), or no model to look for
    DeleteResourceKvp(key)
    return 'delivered'
  end

  local identifier = nonEmpty(data.identifier) or nonEmpty(row.owner)
  local src = nil
  if identifier then
    local found, value = pcall(NZ.Bridge.getSourceByIdentifier, identifier)
    src = found and validSrc(value) or nil
    if src and identifierOf(src) ~= identifier then src = nil end
  end
  tokenSeq = tokenSeq + 1
  local claim = {
    token = tokenSeq,
    src = src,
    identifier = identifier,
    at = at,
    prevLastOut = tonumber(data.prev),
    garageKey = row.garageKey,
    hash = hash,
    dropped = src == nil or nil,
  }
  local built, _, init = pcall(buildData, row, plate, hash, at)
  if built then claim.init = init end
  claims[plate] = claim
  dropWrongModel(plate, claim, true)
  ensureEntry(plate, claim) -- no recover / retrieve while it may still be delivered
  return 'rearmed'
end

--- Re-arm (or put back) the valet claims that were undelivered when the resource stopped.
--- A full server start already handled them through garages.outOnRestart (they are stale
--- then, unless it is 'keep': then they go back to their garage, never delivered).
function Phone.recover()
  local counts = {}
  for _, key in ipairs(storedClaimKeys()) do
    local success, outcome = pcall(recoverClaim, key)
    if not success then
      warnOnce('recover', ('could not recover a valet claim (%s): %s'):format(key, tostring(outcome)))
      outcome = 'retry'
    end
    counts[outcome] = (counts[outcome] or 0) + 1
  end
  if (counts.rearmed or 0) > 0 then
    lib.print.info(('[nayzeee-garages] phone: %d undelivered valet claim(s) resumed after a restart'):format(counts.rearmed))
    Phone.watch()
  end
  if (counts.retry or 0) > 0 then
    warnOnce('recover:retry', ('%d valet claim(s) could not be checked (database), kept for the next start'):format(counts.retry))
  end
  return counts
end

--- Console hint for installed phones that never called the phone exports (adapter missing).
function Phone.boot()
  if option('hints') == false then return end
  for _, phone in ipairs(PHONES) do
    local state = GetResourceState(phone.name)
    local provided = phone.skipIf and GetResourceState(phone.skipIf) == 'started'
    if not provided and state ~= 'missing' and state ~= 'unknown'
      and GetResourceKvpString('nz_phone_seen:' .. phone.name) == nil then
      lib.print.info(('[nayzeee-garages] %s found: optional garage app adapter in %s (install/phone/README.md); Config.Phone.hints = false hides this')
        :format(phone.name, phone.folder))
    end
  end
end

---------------------------------------------------------------------------------------
-- Player lifecycle
---------------------------------------------------------------------------------------

--- The player left or unloaded their character: their pending claims go back on the next
--- watchdog tick (a vehicle already created is still adopted, without keys).
local function forget(src)
  src = tonumber(src)
  if not src then return end
  lists[src] = nil
  for _, claim in pairs(claims) do
    if claim.src == src then claim.dropped = true end
  end
end

AddEventHandler('playerDropped', function()
  forget(source)
end)

AddEventHandler('nz:server:playerUnloaded', function(src)
  forget(src)
end)

-- Once the garages are loaded: resume undelivered claims, then (when the other resources
-- had time to start) the adapter hint.
CreateThread(function()
  local deadline = GetGameTimer() + 120000
  while not NZ.Ready and GetGameTimer() < deadline do Wait(1000) end
  if NZ.Ready then
    local recovered, err = pcall(Phone.recover)
    if not recovered then warnOnce('recover', ('valet claim recovery failed: %s'):format(tostring(err))) end
  end
  Wait(5000)
  local success, err = pcall(Phone.boot)
  if not success then warnOnce('boot', ('boot hint failed: %s'):format(tostring(err))) end
end)

---------------------------------------------------------------------------------------
-- Exports and client events
---------------------------------------------------------------------------------------

--- Register an export; runtime errors are printed and returned as (nil, message).
local function export(name, fn)
  exports(name, function(...)
    local success, a, b = pcall(fn, ...)
    if not success then
      lib.print.error(('export %s failed (called by %s): %s'):format(name, tostring(GetInvokingResource()), tostring(a)))
      return nil, L('Something went wrong')
    end
    return a, b
  end)
end

--- GetPhoneVehicles(source) -> { PhoneVehicle } | nil, error
export('GetPhoneVehicles', function(source)
  rememberCaller()
  return Phone.vehicles(source)
end)

--- ClaimVehicleForValet(source, plate) -> ValetData | nil, error
export('ClaimVehicleForValet', function(source, plate)
  rememberCaller()
  return Phone.claim(source, plate)
end)

--- ReleaseValetClaim(source, plate) -> true | false, error
export('ReleaseValetClaim', function(source, plate)
  return Phone.release(source, plate, 'released by ' .. tostring(GetInvokingResource() or 'phone'))
end)

--- MarkValetSpawned(source, plate, netId) -> true | false, error
export('MarkValetSpawned', function(source, plate, netId)
  return Phone.spawned(source, plate, netId)
end)

-- Phone client files: the valet vehicle was created (plate, netId).
RegisterNetEvent('nz:phone:spawned', function(plate, netId)
  local src = source
  local success, done, err = pcall(Phone.spawned, src, plate, netId)
  if not success then
    lib.print.error(('[nayzeee-garages] phone spawned report failed: %s'):format(tostring(done)))
  elseif not done then
    Utils.debug('phone spawned report refused', src, tostring(plate), tostring(err))
  end
end)

-- Phone client files: the valet vehicle could not be created (plate).
RegisterNetEvent('nz:phone:failed', function(plate)
  local src = source
  local success, done, err = pcall(Phone.release, src, plate, 'client failure')
  if not success then
    lib.print.error(('[nayzeee-garages] phone failure report failed: %s'):format(tostring(done)))
  elseif not done then
    Utils.debug('phone failure report refused', src, tostring(plate), tostring(err))
  end
end)
