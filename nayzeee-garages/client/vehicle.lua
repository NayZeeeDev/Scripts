--[[
  nayzeee-garages — client vehicle layer (NZ.Veh).
  Spawning client- and server-created vehicles (props, damage, fuel, mileage, trailer, keys),
  collecting a vehicle's state for storage, labels/images for the interface (enrichDeep),
  category / entity type detection, deletion and the mileage tracker ('nzMileage' state bag).
]]

local Veh = NZ.Veh
local Utils = NZ.Utils

local NET_TIMEOUT = 5000          -- wait for a server-created entity / state bag target (ms)
local CLAIM_TIMEOUT = 3000        -- wait to become network owner of a server-created vehicle
local NETWORK_TIMEOUT = 3000      -- wait for a client-created vehicle to get a network id
local MODEL_TIMEOUT = 10000
local COLLISION_TIMEOUT = 2000
local TRACK_INTERVAL = 500        -- mileage sample interval while driving (ms)
local IDLE_INTERVAL = 1000        -- mileage tracker sleep while not driving (ms)
local FLUSH_INTERVAL = 10000      -- write 'nzMileage' at most this often while driving (ms)
local MAX_STEP = 200.0            -- ignore position jumps above this per sample (teleports)
local MIN_STEP = 0.05             -- ignore physics jitter while standing still
local SWEEP_INTERVAL = 30000      -- forget data of entities that no longer exist (ms)
local BAG_GRACE = 1000            -- the 'nzInit' bag may replicate a moment after the entity
local APPLIED_TTL = 60000         -- how long "this client applied the spawn data" is remembered
local TRAILER_GAP = 0.5           -- metres between the vehicle's rear and the trailer's front

local busy = {}                   -- [entity] = true while vehicle data is being applied
local applied = {}                -- [entity] = GetGameTimer() when this client applied its data
local localMileage = {}           -- [entity] = km, for non-networked (local) vehicles
local tracker = { vehicle = nil, pending = 0.0 }

---------------------------------------------------------------------------------------
-- Generic helpers
---------------------------------------------------------------------------------------

local function currentPed()
  return cache.ped or PlayerPedId()
end

local function setting(section, key, default)
  local settings = NZ.State and NZ.State.settings
  local group = type(settings) == 'table' and settings[section] or nil
  if type(group) == 'table' and group[key] ~= nil then return group[key] end
  local defaults = Config.DefaultSettings and Config.DefaultSettings[section]
  if type(defaults) == 'table' and defaults[key] ~= nil then return defaults[key] end
  return default
end

--- Call a function owned by another module without letting its errors break spawning.
local function call(fn, ...)
  if type(fn) ~= 'function' then return nil end
  local ok, res = pcall(fn, ...)
  if not ok then
    lib.print.error(('[nayzeee-garages] %s'):format(res))
    return nil
  end
  return res
end

local function notifyError(message)
  if type(NZ.NUI.notify) == 'function' then
    NZ.NUI.notify('error', message)
  else
    lib.print.warn(message)
  end
end

local function decodeTable(value)
  if type(value) == 'table' then return value end
  if type(value) == 'string' and value ~= '' then
    local ok, res = pcall(json.decode, value)
    if ok and type(res) == 'table' then return res end
  end
  return nil
end

local function isOwner(entity)
  return NetworkGetEntityOwner(entity) == PlayerId()
end

---------------------------------------------------------------------------------------
-- Hashes & model names
---------------------------------------------------------------------------------------

--- Normalize any hash (signed or unsigned) to the signed 32-bit form GTA uses.
local function signedHash(value)
  local n = tonumber(value)
  n = n and math.tointeger(n)
  if not n then return nil end
  n = n & 0xFFFFFFFF
  if n >= 0x80000000 then n = n - 0x100000000 end
  return n
end

--- Hash from a number, numeric string or spawn name.
local function toHash(value)
  if type(value) == 'number' then return signedHash(value) end
  if type(value) == 'string' and value ~= '' then
    if tonumber(value) then return signedHash(value) end
    return signedHash(joaat(value:lower()))
  end
  return nil
end

local knownModels = {}            -- [signed hash] = spawn name (lower case)

--- Remember the spawn name of a hash. When `expected` is given the name must match it.
local function rememberModel(name, expected)
  if type(name) ~= 'string' or name == '' or tonumber(name) then return nil end
  local lower = name:lower()
  local hash = signedHash(joaat(lower))
  if not hash or (expected and hash ~= expected) then return nil end
  knownModels[hash] = lower
  return hash
end

for name in pairs(Config.VehicleOverrides or {}) do rememberModel(name) end

local function validKey(key)
  return type(key) == 'string' and key ~= '' and key ~= 'NULL' and key ~= 'CARNOTFOUND'
end

--- Spawn name when known, else the lower-case display name.
local function modelNameOf(hash)
  if knownModels[hash] then return knownModels[hash] end
  local display = GetDisplayNameFromVehicleModel(hash)
  if validKey(display) then return display:lower() end
  return nil
end

---------------------------------------------------------------------------------------
-- Labels
---------------------------------------------------------------------------------------

local labelCache = {}             -- [signed hash] = { model, label, make, name, imageModel }

local function labelText(key)
  if not validKey(key) then return nil end
  local text = GetLabelText(key)
  if type(text) ~= 'string' or text == '' or text == 'NULL' then return nil end
  return text
end

local function overrideFor(model)
  local overrides = Config.VehicleOverrides
  if type(model) ~= 'string' or type(overrides) ~= 'table' then return nil end
  local entry = overrides[model] or overrides[model:lower()]
  return type(entry) == 'table' and entry or nil
end

--- Display label of a vehicle model.
--- Returns label ('Make Name' or 'Name'), make ('' when unknown), name and imageModel
--- (Config.VehicleOverrides image URL, else the lower-case spawn/display name).
--- `modelHint` (optional) is the spawn name when the caller knows it; it is only used when
--- it hashes to the same model.
---@param input number|string hash or spawn name
---@param modelHint string|nil
---@return string label, string make, string name, string|nil imageModel
function Veh.label(input, modelHint)
  local hash = toHash(input)
  if not hash then
    local unknown = L('Unknown vehicle')
    return unknown, '', unknown, nil
  end

  if type(input) == 'string' and not tonumber(input) then
    knownModels[hash] = input:lower()
  else
    rememberModel(modelHint, hash)
  end
  local model = knownModels[hash]

  local cached = labelCache[hash]
  if cached and cached.model == model then
    return cached.label, cached.make, cached.name, cached.imageModel
  end

  local display = GetDisplayNameFromVehicleModel(hash)
  local name = labelText(display) or (validKey(display) and display) or model or L('Unknown vehicle')
  local make = labelText(GetMakeNameFromVehicleModel(hash)) or ''
  local override = overrideFor(model) or (validKey(display) and overrideFor(display:lower())) or nil

  local label
  if override and type(override.label) == 'string' and override.label ~= '' then
    label = override.label
  elseif make ~= '' and not name:lower():find(make:lower(), 1, true) then
    label = make .. ' ' .. name
  else
    label = name
  end

  local imageModel = model or (validKey(display) and display:lower()) or nil
  if override and type(override.image) == 'string' and override.image ~= '' then
    imageModel = override.image
  end

  labelCache[hash] = { model = model, label = label, make = make, name = name, imageModel = imageModel }
  return label, make, name, imageModel
end

--- Walk `tbl` (max depth 6) and add label / make / image to every table that has a numeric
--- `hash` and is missing them. Existing values are kept. Returns `tbl`.
---@param tbl any
---@return any
-- Reference maxima for the 0-100 performance ratings (values at or above rate 100).
local STAT_REF = { speed = 55.0, acceleration = 0.45, braking = 1.6, traction = 3.3 }
local statsCache = {}  -- [hash] = { classId, classLabel, stats } | false

local function rating(value, ref)
  value = tonumber(value) or 0
  if value ~= value or value <= 0 then return 0 end
  return math.max(0, math.min(100, math.floor(value / ref * 100 + 0.5)))
end

--- Vehicle class and performance figures of a model, read from the model info (the model
--- does not have to be loaded). nil for unknown models.
---@param hash number
---@return { classId: number, classLabel: string, stats: table }|nil
function Veh.modelInfo(hash)
  hash = tonumber(hash)
  if not hash or hash == 0 then return nil end
  local cached = statsCache[hash]
  if cached ~= nil then return cached or nil end
  if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then
    statsCache[hash] = false
    return nil
  end
  local classId = GetVehicleClassFromName(hash)
  local classLabel = GetLabelText(('VEH_CLASS_%d'):format(classId))
  if not classLabel or classLabel == '' or classLabel == 'NULL' then classLabel = L('Vehicle') end
  local maxSpeed = GetVehicleModelEstimatedMaxSpeed(hash)
  local info = {
    classId = classId,
    classLabel = classLabel,
    stats = {
      topSpeed = math.floor((tonumber(maxSpeed) or 0) * 3.6 + 0.5),
      speed = rating(maxSpeed, STAT_REF.speed),
      acceleration = rating(GetVehicleModelAcceleration(hash), STAT_REF.acceleration),
      braking = rating(GetVehicleModelMaxBraking(hash), STAT_REF.braking),
      traction = rating(GetVehicleModelMaxTraction(hash), STAT_REF.traction),
      seats = math.max(0, math.floor(tonumber(GetVehicleModelNumberOfSeats(hash)) or 0)),
    },
  }
  statsCache[hash] = info
  return info
end

function Veh.enrichDeep(tbl)
  if type(tbl) ~= 'table' then return tbl end
  local seen = {}

  local function visit(t, depth)
    if depth > 6 or seen[t] then return end
    seen[t] = true
    if type(t.hash) == 'number' and t.hash ~= 0 then
      local missingLabel = t.label == nil or t.label == ''
      if missingLabel or t.make == nil or t.image == nil then
        local hint = type(t.model) == 'string' and t.model ~= '' and t.model or nil
        local label, make, _, imageModel = Veh.label(t.hash, hint)
        if missingLabel then t.label = label end
        if t.make == nil then t.make = make end
        if t.image == nil then t.image = imageModel or hint end
      end
      if t.stats == nil then
        local info = Veh.modelInfo(t.hash)
        if info then
          t.classId, t.classLabel, t.stats = info.classId, info.classLabel, info.stats
        end
      end
    end
    for _, v in pairs(t) do
      if type(v) == 'table' then visit(v, depth + 1) end
    end
  end

  visit(tbl, 1)
  return tbl
end

---------------------------------------------------------------------------------------
-- Categories & entity types
---------------------------------------------------------------------------------------

local function hashSet(names)
  local set = {}
  for i = 1, #names do set[signedHash(joaat(names[i]))] = true end
  return set
end

local SUBMARINES = hashSet({ 'submersible', 'submersible2', 'kosatka', 'avisa' })
local BLIMPS = hashSet({ 'blimp', 'blimp2', 'blimp3' })
local TRAILERS = hashSet({
  'trailers', 'trailers2', 'trailers3', 'trailers4', 'trailers5', 'trailerlarge', 'trailerlogs',
  'trailersmall', 'trailersmall2', 'tr2', 'tr3', 'tr4', 'trflat', 'tanker', 'tanker2',
  'armytanker', 'armytrailer', 'armytrailer2', 'baletrailer', 'boattrailer', 'boattrailer2',
  'boattrailer3', 'docktrailer', 'freighttrailer', 'graintrailer', 'proptrailer', 'raketrailer',
  'tvtrailer', 'tvtrailer2',
})

local entityTypeCache = {}

local function detectEntityType(hash)
  local class = GetVehicleClassFromName(hash)
  if class == 21 or (IsThisModelATrain and IsThisModelATrain(hash)) then return 'train' end
  if SUBMARINES[hash] then return 'submarine' end
  if BLIMPS[hash] then return 'heli' end
  if IsThisModelABoat(hash) or (IsThisModelAJetski and IsThisModelAJetski(hash)) then return 'boat' end
  if IsThisModelAHeli(hash) then return 'heli' end
  if IsThisModelAPlane(hash) then return 'plane' end
  -- Quad bikes are automobiles for the game's network code (CreateVehicleServerSetter).
  if IsThisModelAQuadbike and IsThisModelAQuadbike(hash) then return 'automobile' end
  if IsThisModelABike(hash) or IsThisModelABicycle(hash) then return 'bike' end
  if TRAILERS[hash] then return 'trailer' end
  if class == 11 then
    -- Utility class also holds tow trucks and tractors: trailers are the seatless ones.
    local seats = GetVehicleModelNumberOfSeats and GetVehicleModelNumberOfSeats(hash) or -1
    local display = GetDisplayNameFromVehicleModel(hash)
    if seats == 0 or (validKey(display) and display:upper():find('TRAILER', 1, true)) then
      return 'trailer'
    end
  end
  return 'automobile'
end

--- Location category of a model: 'car' | 'sea' | 'air'.
---@param model number|string
---@return string
function Veh.categoryOf(model)
  local hash = toHash(model)
  if not hash then return 'car' end
  return Utils.vehicleTypeFromClass(GetVehicleClassFromName(hash))
end

--- Network entity type of a model, as CreateVehicleServerSetter expects it:
--- 'automobile' | 'bike' | 'boat' | 'heli' | 'plane' | 'submarine' | 'trailer' | 'train'.
---@param model number|string
---@return string
function Veh.entityTypeOf(model)
  local hash = toHash(model)
  if not hash then return 'automobile' end
  local cached = entityTypeCache[hash]
  if cached then return cached end
  local result = detectEntityType(hash)
  if IsModelInCdimage(hash) then entityTypeCache[hash] = result end
  return result
end

---------------------------------------------------------------------------------------
-- Models, spawn points, deletion
---------------------------------------------------------------------------------------

--- Load a model. Returns true when it is loaded.
---@param model number|string
---@param timeout integer|nil ms (default 10000)
---@return boolean
function Veh.requestModel(model, timeout)
  local hash = toHash(model)
  if not hash or not IsModelInCdimage(hash) then return false end
  if HasModelLoaded(hash) then return true end
  local ok = pcall(lib.requestModel, hash, tonumber(timeout) or MODEL_TIMEOUT)
  return (ok and HasModelLoaded(hash)) == true
end

--- First spawn point without a vehicle within `radius` metres.
---@param points table list of {x,y,z,w} / vector4
---@param radius number|nil default 2.5
---@return integer|nil index, table|nil point {x,y,z,w}
function Veh.findFreeSpawn(points, radius)
  if type(points) ~= 'table' then return nil end
  radius = tonumber(radius) or 2.5
  for i = 1, #points do
    local p = Utils.v4(points[i])
    if p then
      local vehicle = lib.getClosestVehicle(vector3(p.x, p.y, p.z), radius + 0.0, true)
      if not vehicle then return i, p end
    end
  end
  return nil
end

local function takeControl(entity, timeout)
  if not NetworkGetEntityIsNetworked(entity) or NetworkHasControlOfEntity(entity) then return true end
  local deadline = GetGameTimer() + (timeout or 1000)
  NetworkRequestControlOfEntity(entity)
  while not NetworkHasControlOfEntity(entity) and GetGameTimer() < deadline do
    Wait(50)
    NetworkRequestControlOfEntity(entity)
  end
  return NetworkHasControlOfEntity(entity)
end

local function deleteEntity(entity)
  if not entity or entity == 0 or not DoesEntityExist(entity) then return true end
  takeControl(entity, 1000)
  SetEntityAsMissionEntity(entity, true, true)
  DeleteVehicle(entity)
  if DoesEntityExist(entity) then DeleteEntity(entity) end
  localMileage[entity] = nil
  busy[entity] = nil
  applied[entity] = nil
  return not DoesEntityExist(entity)
end

--- Delete a vehicle and the trailer attached to it. Returns true when it is gone.
---@param vehicle integer
---@return boolean
function Veh.delete(vehicle)
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return true end
  local hasTrailer, trailer = GetVehicleTrailerVehicle(vehicle)
  if hasTrailer and trailer and trailer ~= 0 and DoesEntityExist(trailer) then
    DetachVehicleFromTrailer(vehicle)
    deleteEntity(trailer)
  end
  if tracker.vehicle == vehicle then
    tracker.vehicle, tracker.pending = nil, 0.0
  end
  return deleteEntity(vehicle)
end

---------------------------------------------------------------------------------------
-- Applying data
---------------------------------------------------------------------------------------

local function getProps(vehicle)
  local ok, props = pcall(lib.getVehicleProperties, vehicle)
  if ok and type(props) == 'table' then return props end
  return nil
end

local function setProps(vehicle, props)
  if type(props) ~= 'table' then return false end
  local ok, err = pcall(lib.setVehicleProperties, vehicle, props)
  if not ok then Utils.debug('setVehicleProperties failed:', err) end
  return ok
end

--- Plate text to put on the entity (opts.plate, else props.plate), max 8 characters.
local function plateText(data)
  local plate = data.plate
  if type(plate) ~= 'string' or Utils.trim(plate) == '' then
    plate = type(data.props) == 'table' and data.props.plate or nil
  end
  if type(plate) ~= 'string' then return nil end
  plate = Utils.trim(plate)
  if plate == '' then return nil end
  return plate:sub(1, 8)
end

--- Health to apply: the raw value (keeps negative engine health) unless the percent
--- differs from it, which means it was edited (admin / repair) and wins.
local function pickHealth(percent, raw)
  percent, raw = tonumber(percent), tonumber(raw)
  if raw and (not percent or math.abs(Utils.clamp(raw / 10.0, 0, 100) - percent) <= 2.0) then
    return raw + 0.0
  end
  if percent then return Utils.clamp(percent, 0, 100) * 10.0 end
  return nil
end

local function waitNetworked(entity, timeout)
  local deadline = GetGameTimer() + timeout
  while not NetworkGetEntityIsNetworked(entity) do
    if GetGameTimer() > deadline or not DoesEntityExist(entity) then return false end
    Wait(0)
  end
  return true
end

--- Wait for collision under a fresh vehicle, then put it on the ground.
local function settle(vehicle)
  if not HasCollisionLoadedAroundEntity(vehicle) then
    FreezeEntityPosition(vehicle, true)
    local deadline = GetGameTimer() + COLLISION_TIMEOUT
    while not HasCollisionLoadedAroundEntity(vehicle) and GetGameTimer() < deadline do
      local pos = GetEntityCoords(vehicle)
      RequestCollisionAtCoord(pos.x, pos.y, pos.z)
      Wait(50)
    end
    FreezeEntityPosition(vehicle, false)
  end
  SetVehicleOnGroundProperly(vehicle)
end

local function prepare(vehicle)
  SetEntityAsMissionEntity(vehicle, true, true)
  SetVehicleHasBeenOwnedByPlayer(vehicle, true)
  SetVehicleNeedsToBeHotwired(vehicle, false)
  SetVehRadioStation(vehicle, 'OFF')
end

local function boneIndex(entity, names)
  for i = 1, #names do
    local index = GetEntityBoneIndexByName(entity, names[i])
    if index and index ~= -1 then return index end
  end
  return nil
end

--- Move the trailer so its hitch sits on the vehicle's hitch (horizontal only).
local function alignHitch(vehicle, trailer)
  local female = boneIndex(vehicle, { 'attach_female' })
  local male = boneIndex(trailer, { 'attach_male' })
  if not female or not male then return false end
  local a = GetWorldPositionOfEntityBone(vehicle, female)
  local b = GetWorldPositionOfEntityBone(trailer, male)
  local dx, dy = a.x - b.x, a.y - b.y
  if dx * dx + dy * dy > 100.0 then return false end
  local pos = GetEntityCoords(trailer)
  SetEntityCoordsNoOffset(trailer, pos.x + dx, pos.y + dy, pos.z, false, false, false)
  return true
end

local function attachTrailer(vehicle, trailer)
  for attempt = 1, 4 do
    if not DoesEntityExist(vehicle) or not DoesEntityExist(trailer) then return false end
    AttachVehicleToTrailer(vehicle, trailer, 1.0)
    Wait(100)
    if IsVehicleAttachedToTrailer(vehicle) then return true end
    if attempt == 1 then alignHitch(vehicle, trailer) end
  end
  return false
end

--- Spawn a saved trailer behind `vehicle`, restore it and hitch it.
local function spawnTrailer(vehicle, data, networked)
  if type(data) ~= 'table' or not DoesEntityExist(vehicle) then return nil end
  local props = type(data.props) == 'table' and data.props or nil
  local hash = toHash(data.hash) or toHash(data.model) or (props and toHash(props.model)) or nil
  if not hash or not IsModelAVehicle(hash) or not Veh.requestModel(hash, MODEL_TIMEOUT) then
    lib.print.warn(('[nayzeee-garages] could not load trailer model %s'):format(tostring(data.model or data.hash)))
    return nil
  end
  rememberModel(data.model, hash)

  local vehMin = GetModelDimensions(GetEntityModel(vehicle))
  local _, trailerMax = GetModelDimensions(hash)
  local offset = (vehMin and vehMin.y or -2.5) - (trailerMax and trailerMax.y or 2.5) - TRAILER_GAP
  local pos = GetOffsetFromEntityInWorldCoords(vehicle, 0.0, offset + 0.0, 0.0)
  local trailer = CreateVehicle(hash, pos.x, pos.y, pos.z, GetEntityHeading(vehicle), networked, false)
  SetModelAsNoLongerNeeded(hash)
  if not trailer or trailer == 0 or not DoesEntityExist(trailer) then return nil end

  SetEntityAsMissionEntity(trailer, true, true)
  SetVehicleOnGroundProperly(trailer)
  if networked and waitNetworked(trailer, NETWORK_TIMEOUT) then
    SetNetworkIdCanMigrate(NetworkGetNetworkIdFromEntity(trailer), true)
  end
  if props then setProps(trailer, props) end
  local plate = plateText(data)
  if plate then SetVehicleNumberPlateText(trailer, plate) end
  local damage = decodeTable(data.damage)
  if damage then NZ.Damage.apply(trailer, damage) end

  if not attachTrailer(vehicle, trailer) then
    lib.print.warn('[nayzeee-garages] the trailer was spawned but could not be attached')
  end
  return trailer
end

--- Apply plate, props, fuel, health, damage, mileage and trailer to a vehicle we control.
local function applyVehicleData(vehicle, data, networked)
  local props = type(data.props) == 'table' and data.props or nil
  if props then setProps(vehicle, props) end

  local plate = plateText(data)
  if plate then SetVehicleNumberPlateText(vehicle, plate) end

  local fuel = tonumber(data.fuel) or (props and tonumber(props.fuelLevel)) or nil
  if fuel then call(NZ.Fuel.set, vehicle, Utils.clamp(fuel, 0, 100) + 0.0) end

  local damage = decodeTable(data.damage)
  local engine = pickHealth(data.engine, (damage and damage.engine) or (props and props.engineHealth))
  local body = pickHealth(data.body, (damage and damage.body) or (props and props.bodyHealth))
  if engine then SetVehicleEngineHealth(vehicle, engine) end
  if body then SetVehicleBodyHealth(vehicle, body) end
  if damage then
    local copy = {}
    for k, v in pairs(damage) do copy[k] = v end
    copy.engine = engine or copy.engine
    copy.body = body or copy.body
    NZ.Damage.apply(vehicle, copy)
  end

  local mileage = Utils.round(math.max(tonumber(data.mileage) or 0.0, 0.0), 3)
  if networked then
    local state = Entity(vehicle).state
    state:set('nzPlate', Utils.plate(GetVehicleNumberPlateText(vehicle)), true)
    state:set('nzMileage', mileage, true)
  else
    localMileage[vehicle] = mileage
  end

  local trailer = decodeTable(data.trailer)
  if trailer then spawnTrailer(vehicle, trailer, networked) end
end

local function recentlyApplied(entity)
  local at = applied[entity]
  return at ~= nil and GetGameTimer() - at < APPLIED_TTL
end

--- Apply already-claimed data to a networked vehicle (guarded against double application).
local function applyClaimed(vehicle, data)
  busy[vehicle] = true
  applied[vehicle] = GetGameTimer()
  prepare(vehicle)
  local ok, err = pcall(applyVehicleData, vehicle, data, true)
  if not ok then lib.print.error(('[nayzeee-garages] could not apply vehicle data: %s'):format(err)) end
  busy[vehicle] = nil
  return ok
end

--- Claim the 'nzInit' state bag of a vehicle we own (cleared first so no other client
--- applies it as well) and apply it.
local function applyInit(vehicle)
  if busy[vehicle] or not DoesEntityExist(vehicle) then return false end
  local state = Entity(vehicle).state
  local init = decodeTable(state.nzInit)
  if not init then return false end
  state:set('nzInit', nil, true)
  -- The caller's data was already applied as a fallback: only clear the bag.
  if recentlyApplied(vehicle) then return false end
  return applyClaimed(vehicle, init)
end

local function shouldWarp(opts)
  if opts.warp == false then return false end
  if opts.warp == true then return true end
  return setting('vehicles', 'spawnOutside', false) ~= true
end

local function shouldGiveKeys(opts)
  return opts.keys ~= false and setting('vehicles', 'giveKeys', true) ~= false
end

local function finish(vehicle, opts)
  if opts.freeze then FreezeEntityPosition(vehicle, true) end
  if opts.locked then SetVehicleDoorsLocked(vehicle, 2) end
  if shouldWarp(opts) then TaskWarpPedIntoVehicle(currentPed(), vehicle, -1) end
end

---------------------------------------------------------------------------------------
-- Spawning
---------------------------------------------------------------------------------------

local function entityFromNetId(netId, timeout)
  local deadline = GetGameTimer() + timeout
  while true do
    if NetworkDoesNetworkIdExist(netId) then
      local entity = NetworkGetEntityFromNetworkId(netId)
      if entity and entity ~= 0 and DoesEntityExist(entity) then return entity end
    end
    if GetGameTimer() > deadline then return nil end
    Wait(50)
  end
end

local function hasOwnData(opts)
  return type(opts.props) == 'table' or opts.damage ~= nil or opts.trailer ~= nil
end

--- Make sure the data of a server-created vehicle gets applied: its 'nzInit' bag when the
--- server attached one, else (fallback) the caller's opts when the plate shows nobody did.
local function claimServerVehicle(vehicle, opts)
  if busy[vehicle] or recentlyApplied(vehicle) then return end
  local state = Entity(vehicle).state
  local graceEnd = GetGameTimer() + BAG_GRACE
  while decodeTable(state.nzInit) == nil and GetGameTimer() < graceEnd do
    if busy[vehicle] or recentlyApplied(vehicle) or not DoesEntityExist(vehicle) then return end
    Wait(100)
  end

  local fallback = nil
  if decodeTable(state.nzInit) == nil then
    local wanted = Utils.plate(plateText(opts))
    if not hasOwnData(opts) or not wanted or Utils.plate(GetVehicleNumberPlateText(vehicle)) == wanted then
      if isOwner(vehicle) then prepare(vehicle) end
      return
    end
    fallback = opts
  end

  local deadline = GetGameTimer() + CLAIM_TIMEOUT
  while GetGameTimer() < deadline and DoesEntityExist(vehicle) do
    if busy[vehicle] or recentlyApplied(vehicle) then return end
    if isOwner(vehicle) then
      if fallback then
        applyClaimed(vehicle, fallback)
      else
        applyInit(vehicle)
      end
      return
    end
    if not fallback and decodeTable(state.nzInit) == nil then return end
    NetworkRequestControlOfEntity(vehicle)
    Wait(100)
  end
end

--- Adopt a vehicle the server created (opts.netId).
local function adoptServerVehicle(opts)
  local netId = math.tointeger(tonumber(opts.netId) or 0)
  local vehicle = netId and netId ~= 0 and entityFromNetId(netId, NET_TIMEOUT) or nil
  if not vehicle then return nil end

  local plate = plateText(opts)
  if plate and shouldGiveKeys(opts) then call(NZ.Keys.give, vehicle, Utils.plate(plate)) end
  if shouldWarp(opts) then
    TaskWarpPedIntoVehicle(currentPed(), vehicle, -1)
  end
  -- The driver usually becomes the network owner; then the init data is ours to apply.
  claimServerVehicle(vehicle, opts)
  if not plate and shouldGiveKeys(opts) and DoesEntityExist(vehicle) then
    call(NZ.Keys.give, vehicle, Utils.plate(GetVehicleNumberPlateText(vehicle)))
  end
  if DoesEntityExist(vehicle) then
    if opts.freeze then FreezeEntityPosition(vehicle, true) end
    if opts.locked then SetVehicleDoorsLocked(vehicle, 2) end
  end
  return vehicle
end

--- Create the vehicle on this client (networked unless opts.networked == false).
local function createVehicle(opts)
  local props = type(opts.props) == 'table' and opts.props or nil
  local hash = toHash(opts.hash) or toHash(opts.model) or (props and toHash(props.model)) or nil
  local coords = Utils.v4(opts.coords)
  if not hash or not coords then return nil end
  rememberModel(opts.model, hash)

  if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) or not Veh.requestModel(hash, MODEL_TIMEOUT) then
    notifyError(L('Could not load the vehicle model'))
    Veh.lastErrorShown = GetGameTimer() -- callers skip their generic error toast
    return nil
  end

  local networked = opts.networked ~= false
  RequestCollisionAtCoord(coords.x + 0.0, coords.y + 0.0, coords.z + 0.0)
  local vehicle = CreateVehicle(hash, coords.x + 0.0, coords.y + 0.0, coords.z + 0.0, coords.w + 0.0, networked, false)
  SetModelAsNoLongerNeeded(hash)
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end

  if networked then
    if not waitNetworked(vehicle, NETWORK_TIMEOUT) then
      -- The server refused the entity (e.g. entity lockdown); a local copy is useless here.
      lib.print.warn('[nayzeee-garages] the spawned vehicle never became networked')
      deleteEntity(vehicle)
      return nil
    end
    SetNetworkIdCanMigrate(NetworkGetNetworkIdFromEntity(vehicle), true)
  end

  prepare(vehicle)
  settle(vehicle)
  busy[vehicle] = true
  local ok, err = pcall(applyVehicleData, vehicle, opts, networked)
  busy[vehicle] = nil
  if not ok then lib.print.error(('[nayzeee-garages] could not apply vehicle data: %s'):format(err)) end

  if shouldGiveKeys(opts) then
    call(NZ.Keys.give, vehicle, Utils.plate(GetVehicleNumberPlateText(vehicle)))
  end
  finish(vehicle, opts)
  return vehicle
end

--- Spawn a vehicle (§7.1) and return its entity, or nil.
--- opts = { hash, model, coords = {x,y,z,w}, plate, props, damage, fuel, engine, body,
---          mileage, trailer, netId, networked = true, warp = true, freeze = false,
---          keys = true, locked = false }
--- With `netId` the server already created it: wait for it (5 s) and apply its 'nzInit'
--- data when this client owns it. `warp` nil follows settings.vehicles.spawnOutside;
--- keys are only given when settings.vehicles.giveKeys is on.
---@param opts table
---@return integer|nil vehicle
function Veh.spawn(opts)
  if type(opts) ~= 'table' then return nil end
  if opts.netId then return adoptServerVehicle(opts) end
  return createVehicle(opts)
end

---------------------------------------------------------------------------------------
-- Collecting
---------------------------------------------------------------------------------------

local function percent(health)
  return Utils.round(Utils.clamp((tonumber(health) or 0) / 10.0, 0, 100), 1)
end

--- Write the distance driven so far to the 'nzMileage' state bag (network owner only).
local function flushMileage(vehicle)
  if tracker.vehicle ~= vehicle or tracker.pending <= 0 then return end
  if not DoesEntityExist(vehicle) or not NetworkGetEntityIsNetworked(vehicle) then
    tracker.pending = 0.0
    return
  end
  if not isOwner(vehicle) then return end
  local state = Entity(vehicle).state
  local current = tonumber(state.nzMileage) or 0.0
  state:set('nzMileage', Utils.round(current + tracker.pending, 3), true)
  tracker.pending = 0.0
end

local function mileageOf(vehicle)
  local km
  if NetworkGetEntityIsNetworked(vehicle) then
    km = tonumber(Entity(vehicle).state.nzMileage) or 0.0
  else
    km = localMileage[vehicle] or 0.0
  end
  if tracker.vehicle == vehicle then km = km + tracker.pending end
  return Utils.round(km, 3)
end

local function collectTrailer(vehicle, includeDeformation)
  local hasTrailer, trailer = GetVehicleTrailerVehicle(vehicle)
  if not hasTrailer or not trailer or trailer == 0 or not DoesEntityExist(trailer) then return nil end
  local hash = signedHash(GetEntityModel(trailer))
  return {
    netId = NetworkGetEntityIsNetworked(trailer) and NetworkGetNetworkIdFromEntity(trailer) or nil,
    hash = hash,
    model = modelNameOf(hash),
    props = getProps(trailer),
    damage = NZ.Damage.get(trailer, includeDeformation),
  }
end

--- Everything the server needs to store a vehicle (§7.2).
---@param vehicle integer
---@return table|nil { netId, plate, hash, model, props, damage, fuel, engine, body, mileage,
---                    entityType, trailer = { netId, hash, model, props, damage } | nil }
function Veh.collect(vehicle)
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return nil end
  flushMileage(vehicle)

  local hash = signedHash(GetEntityModel(vehicle))
  local networked = NetworkGetEntityIsNetworked(vehicle)
  local includeDeformation = setting('vehicles', 'saveDamage', true) ~= false
    and setting('vehicles', 'saveDeformation', true) ~= false

  -- Properties first: reading them rolls windows up, so damage sees only real breakage.
  local props = getProps(vehicle)
  local damage = NZ.Damage.get(vehicle, includeDeformation)
  local fuel = tonumber(call(NZ.Fuel.get, vehicle)) or GetVehicleFuelLevel(vehicle)

  local data = {
    netId = networked and NetworkGetNetworkIdFromEntity(vehicle) or nil,
    plate = Utils.plate(GetVehicleNumberPlateText(vehicle)),
    hash = hash,
    model = modelNameOf(hash),
    props = props,
    damage = damage,
    fuel = Utils.round(Utils.clamp(fuel, 0, 100), 1),
    engine = percent(damage and damage.engine or GetVehicleEngineHealth(vehicle)),
    body = percent(damage and damage.body or GetVehicleBodyHealth(vehicle)),
    mileage = mileageOf(vehicle),
    entityType = Veh.entityTypeOf(hash),
  }
  if setting('vehicles', 'trailers', true) ~= false then
    data.trailer = collectTrailer(vehicle, includeDeformation)
  end
  return data
end

---------------------------------------------------------------------------------------
-- Server-created vehicles: 'nzInit' state bag
---------------------------------------------------------------------------------------

AddStateBagChangeHandler('nzInit', nil, function(bagName, _, value)
  if value == nil then return end
  CreateThread(function()
    local deadline = GetGameTimer() + NET_TIMEOUT
    local entity = 0
    while GetGameTimer() < deadline do
      entity = GetEntityFromStateBagName(bagName)
      if entity ~= 0 and DoesEntityExist(entity) then break end
      entity = 0
      Wait(50)
    end
    if entity == 0 then return end
    while GetGameTimer() < deadline and DoesEntityExist(entity) do
      if busy[entity] or decodeTable(Entity(entity).state.nzInit) == nil then return end
      if isOwner(entity) then
        applyInit(entity)
        return
      end
      Wait(100)
    end
  end)
end)

---------------------------------------------------------------------------------------
-- Mileage tracker
---------------------------------------------------------------------------------------

local function trackable(vehicle, ped)
  return vehicle ~= 0
    and GetPedInVehicleSeat(vehicle, -1) == ped
    and NetworkGetEntityIsNetworked(vehicle)
    and Entity(vehicle).state.nzPlate ~= nil
end

--- Accumulate distance while the local player drives `vehicle`; returns when they stop.
local function trackDriving(vehicle)
  tracker.vehicle = vehicle
  tracker.pending = 0.0
  local last = GetEntityCoords(vehicle)
  local lastFlush = GetGameTimer()

  while tracker.vehicle == vehicle and DoesEntityExist(vehicle)
    and GetPedInVehicleSeat(vehicle, -1) == currentPed() do
    Wait(TRACK_INTERVAL)
    if tracker.vehicle ~= vehicle or not DoesEntityExist(vehicle) then break end
    local pos = GetEntityCoords(vehicle)
    local dx, dy, dz = pos.x - last.x, pos.y - last.y, pos.z - last.z
    local step = math.sqrt(dx * dx + dy * dy + dz * dz)
    last = pos
    if step > MIN_STEP and step <= MAX_STEP then
      tracker.pending = tracker.pending + step / 1000.0
    end
    if GetGameTimer() - lastFlush >= FLUSH_INTERVAL then
      flushMileage(vehicle)
      lastFlush = GetGameTimer()
    end
  end

  if tracker.vehicle == vehicle then
    flushMileage(vehicle)
    tracker.vehicle = nil
    tracker.pending = 0.0
  end
end

local function sweep()
  for entity in pairs(localMileage) do
    if not DoesEntityExist(entity) then localMileage[entity] = nil end
  end
  for entity in pairs(busy) do
    if not DoesEntityExist(entity) then busy[entity] = nil end
  end
  for entity in pairs(applied) do
    if not recentlyApplied(entity) or not DoesEntityExist(entity) then applied[entity] = nil end
  end
end

CreateThread(function()
  local nextSweep = GetGameTimer() + SWEEP_INTERVAL
  while true do
    local ped = currentPed()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if trackable(vehicle, ped) then
      trackDriving(vehicle)
    else
      Wait(IDLE_INTERVAL)
    end
    if GetGameTimer() >= nextSweep then
      sweep()
      nextSweep = GetGameTimer() + SWEEP_INTERVAL
    end
  end
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= NZ.ResourceName then return end
  if tracker.vehicle and DoesEntityExist(tracker.vehicle) then
    flushMileage(tracker.vehicle)
  end
  tracker.vehicle, tracker.pending = nil, 0.0
end)
