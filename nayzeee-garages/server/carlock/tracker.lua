--[[
  nayzeee-garages — car lock: vehicle tracker and key ring status (server, NZ.CarLock).
  docs/CARLOCK.md §3, §10.

  The key ring (client/carlock/keysapp.lua) lists the player's keys with the core callback
  nz:carlock:keys and locks / shares / revokes through the core callbacks (toggleLock, share,
  revoke, holders). This file answers what the key list does not say: the state of the
  vehicles behind those keys, the tracker and the share picker.

  A vehicle is TRACKABLE when Config.CarLock.tracker.enabled, its security profile has
  `tracker = true`, it exists in the player's routing bucket and it is not on the impound tow
  truck (NZ.Tow.isTowing). Only trackable vehicles report a distance / position; everything
  is measured from the SERVER ped position. Locking stays a normal range-limited action.

  Callbacks (lib.callback, { ok, data, error }):
    nz:carlock:tracker       {}        -> { now, tracker, vehicles = { KeyStatus } }   every key (NZ.CarLock.keysOf)
                             { plate } -> { now, tracker, vehicles = { KeyStatus } }   one key (NZ.CarLock.hasKey),
                                          with `coords` when trackable (waypoint)
      KeyStatus = { plate, owned, isOwner, nickname?, model?, hash?, spawned, netId?, profile,
                    profileLabel, remote, keyType ('key'|'fob'), tracker, trackable, towing,
                    locked?, alarm, distance? (trackable), coords? (trackable, one plate) }
    nz:carlock:trackerAlarm  { plate, on? } -> { alarm, seconds?, cooldown }
                             remote alarm of a trackable vehicle (NZ.CarLock.alarm, Config.CarLock.
                             tracker.alarmSeconds); a new alarm waits tracker.alarmCooldown seconds
                             per vehicle; on = false (or a second press) silences it
    nz:carlock:nearbyPlayers {} -> PlayerOption[]   players within the hand-over range (+ margin)

  Server API:
    NZ.CarLock.keyStatus(src, plate, entity?, opts?) -> KeyStatus
    NZ.CarLock.trackerEnabled() -> boolean
    NZ.CarLock.openKeyRing(src, plate?)   opens the key ring on that player's screen (fob use)
]]

local CarLock = NZ.CarLock
local Utils = NZ.Utils

local RATE = { list = 900, one = 400, alarm = 1200, players = 800 }
local MAX_LIST = 60             -- keys reported by one list call
local NEARBY_MARGIN = 1.5       -- m: players a little farther than ranges.give are offered (the share re-checks)
local DEFAULT_COOLDOWN = 60     -- s: between two remote alarms of one vehicle

local alarmAt = {}              -- [plate] = os.time() of the last remote alarm
local alarmCount = 0

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function validSrc(src)
  src = tonumber(src)
  if not src or src <= 0 or src ~= math.floor(src) then return nil end
  src = math.tointeger(src)
  if GetPlayerName(tostring(src)) == nil then return nil end
  return src
end

local function normPlate(plate)
  if type(plate) ~= 'string' or #plate > 16 then return nil end
  return Utils.plate(plate)
end

local function limited(src, bucket)
  return not NZ.Access.rateLimit(src, 'carlock:tracker:' .. bucket, RATE[bucket] or 500)
end

local function identifierOf(src)
  if type(NZ.Bridge.getIdentifier) ~= 'function' then return nil end
  local ok, id = pcall(NZ.Bridge.getIdentifier, src)
  if ok and type(id) == 'string' and id ~= '' then return id end
  return nil
end

local function isVehicle(entity)
  return type(entity) == 'number' and entity ~= 0 and DoesEntityExist(entity) and GetEntityType(entity) == 2
end

local function pedCoords(src)
  local ped = GetPlayerPed(tostring(src))
  if not ped or ped == 0 then return nil end
  return GetEntityCoords(ped)
end

local function towing(entity)
  if type(NZ.Tow.isTowing) ~= 'function' then return false end
  local ok, res = pcall(NZ.Tow.isTowing, entity)
  return ok and res == true
end

local function log(event, src, data)
  if type(NZ.Logs.add) ~= 'function' then return end
  pcall(NZ.Logs.add, event, src, data)
end

local function trackerCfg()
  local t = CarLock.cfg().tracker
  return type(t) == 'table' and t or {}
end

--- Is the vehicle tracker switched on (Config.CarLock.tracker.enabled)?
---@return boolean
function CarLock.trackerEnabled()
  return CarLock.enabled() and trackerCfg().enabled ~= false
end

local function hashOf(model)
  if type(model) == 'number' then return math.tointeger(model) or model end
  if type(model) ~= 'string' or model == '' then return nil end
  return joaat(model:lower())
end

--- Entity of a network id, only in the player's routing bucket.
local function entityOfNet(src, netId)
  local id = tonumber(netId)
  if not id or id <= 0 or id ~= math.floor(id) then return nil end
  local entity = NetworkGetEntityFromNetworkId(math.tointeger(id))
  if not isVehicle(entity) then return nil end
  if GetEntityRoutingBucket(entity) ~= GetPlayerRoutingBucket(tostring(src)) then return nil end
  return entity
end

local function alarmSounding(entity)
  local ok, value = pcall(function() return Entity(entity).state.nzAlarm end)
  return ok and type(value) == 'table'
end

local function round1(n) return math.floor(n * 10 + 0.5) / 10 end

---------------------------------------------------------------------------------------
-- Status of one key
---------------------------------------------------------------------------------------

--- What the key ring shows about the vehicle of a key the player HAS (the caller checked it).
--- entity: the vehicle when already known (nil = looked up by plate in the player's bucket,
--- false = known not to be out).
--- opts = { coords = true }: include the position of a trackable vehicle; opts.model: spawn
--- name from the key list (items carry it).
---@param src number
---@param plate string
---@param entity number|false|nil
---@param opts table|nil
---@return table KeyStatus
function CarLock.keyStatus(src, plate, entity, opts)
  opts = type(opts) == 'table' and opts or {}
  -- false = known not to be out (the caller already scanned the world)
  local known = entity ~= nil
  if not isVehicle(entity) then entity = nil end
  if not known then entity = CarLock.findVehicle(plate, src) end
  local row = CarLock.vehicleRow(plate)
  local id = identifierOf(src)

  local profileName, profile
  if entity then
    profileName, profile = CarLock.profileOfEntity(entity)
  elseif row then
    profileName, profile = CarLock.profileOf(row.hash or row.model, nil)
  elseif type(opts.model) == 'string' and opts.model ~= '' then
    profileName, profile = CarLock.profileOf(opts.model, nil)
  else
    profileName, profile = CarLock.profile('standard')
  end

  local status = {
    plate = plate,
    owned = row ~= nil,
    isOwner = row ~= nil and id ~= nil and row.owner == id,
    nickname = row and type(row.nickname) == 'string' and row.nickname ~= '' and row.nickname or nil,
    model = row and row.model or (type(opts.model) == 'string' and opts.model ~= '' and opts.model or nil),
    hash = entity and GetEntityModel(entity) or (row and (tonumber(row.hash) or hashOf(row.model))) or hashOf(opts.model),
    spawned = entity ~= nil,
    netId = entity and NetworkGetNetworkIdFromEntity(entity) or nil,
    profile = profileName,
    profileLabel = type(profile.label) == 'string' and L(profile.label) or L('Standard'),
    remote = profile.remote == true,
    keyType = CarLock.keyKindOf(profile),
    tracker = profile.tracker == true,
    trackable = false,
    towing = false,
    alarm = false,
  }
  if not entity then return status end

  status.towing = towing(entity)
  status.locked = CarLock.isLocked(entity)
  status.alarm = alarmSounding(entity)
  status.trackable = CarLock.trackerEnabled() and status.tracker and not status.towing
  if status.trackable then
    local origin = pedCoords(src)
    local pos = GetEntityCoords(entity)
    if origin then status.distance = math.floor(#(pos - origin) + 0.5) end
    if opts.coords then status.coords = { x = round1(pos.x), y = round1(pos.y), z = round1(pos.z) } end
  end
  return status
end

---------------------------------------------------------------------------------------
-- Callbacks
---------------------------------------------------------------------------------------

lib.callback.register('nz:carlock:tracker', Utils.safe(function(source, payload)
  local src = validSrc(source)
  if not src then return Utils.fail(L('Invalid request')) end
  payload = type(payload) == 'table' and payload or {}
  if not CarLock.enabled() then return Utils.fail(L('Vehicle keys are handled by another script')) end

  if payload.plate ~= nil then
    local plate = normPlate(payload.plate)
    if not plate then return Utils.fail(L('Invalid plate')) end
    if limited(src, 'one') then return Utils.fail(L('Please wait a moment')) end
    if not CarLock.hasKey(src, plate) then return Utils.fail(L('You do not have the keys of this vehicle')) end
    return Utils.ok({ now = os.time(), tracker = CarLock.trackerEnabled(),
      vehicles = { CarLock.keyStatus(src, plate, nil, { coords = true }) } })
  end

  if limited(src, 'list') then return Utils.fail(L('Please wait a moment')) end
  local list = {}
  for _, key in ipairs(CarLock.keysOf(src)) do
    if #list >= MAX_LIST then break end
    local entity = key.netId and entityOfNet(src, key.netId) or nil
    -- keysOf already scanned the world: a key without a net id has no vehicle out
    list[#list + 1] = CarLock.keyStatus(src, key.plate, entity or false, { model = key.model })
  end
  return Utils.ok({ now = os.time(), tracker = CarLock.trackerEnabled(), vehicles = list })
end))

lib.callback.register('nz:carlock:trackerAlarm', Utils.safe(function(source, payload)
  local src = validSrc(source)
  if not src or type(payload) ~= 'table' then return Utils.fail(L('Invalid request')) end
  if not CarLock.enabled() then return Utils.fail(L('Vehicle keys are handled by another script')) end
  if limited(src, 'alarm') then return Utils.fail(L('Please wait a moment')) end
  if not CarLock.trackerEnabled() then return Utils.fail(L('The vehicle tracker is not available')) end
  local plate = normPlate(payload.plate)
  if not plate then return Utils.fail(L('Invalid plate')) end
  if not CarLock.hasKey(src, plate) then return Utils.fail(L('You do not have the keys of this vehicle')) end
  local entity = CarLock.findVehicle(plate, src)
  if not entity then return Utils.fail(L('The vehicle is not out')) end
  if towing(entity) then return Utils.fail(L('This vehicle is being towed')) end
  local _, profile = CarLock.profileOfEntity(entity)
  if profile.tracker ~= true then return Utils.fail(L('This vehicle has no tracker')) end

  local cooldown = math.max(math.floor(tonumber(trackerCfg().alarmCooldown) or DEFAULT_COOLDOWN), 0)
  local sounding = alarmSounding(entity)
  -- a press while it sounds (or on = false) silences it
  if payload.on == false or (payload.on == nil and sounding) then
    CarLock.stopAlarm(entity)
    local left = math.max((alarmAt[plate] or 0) + cooldown - os.time(), 0)
    return Utils.ok({ alarm = false, cooldown = left })
  end
  if sounding then return Utils.ok({ alarm = true, cooldown = math.max((alarmAt[plate] or 0) + cooldown - os.time(), 0) }) end
  local last = alarmAt[plate]
  if last and os.time() - last < cooldown then
    return Utils.fail(L('The alarm can be triggered again in {seconds} s', { seconds = cooldown - (os.time() - last) }))
  end
  local seconds = Utils.clamp(math.floor(tonumber(trackerCfg().alarmSeconds) or 20), 1, 65)
  -- the vehicle's own alarm type; a profile without one ('none') still gets the horn / lights
  local mode = (profile.alarm == 'native' or profile.alarm == 'custom') and profile.alarm or 'custom'
  if not CarLock.alarm(entity, seconds, mode) then return Utils.fail(L('Something went wrong')) end
  alarmCount = alarmCount + 1
  if alarmCount % 100 == 0 then
    -- forget cooldowns that ended long ago (keeps the table small on a long running server)
    local nowTs = os.time()
    for p, at in pairs(alarmAt) do
      if nowTs - at > cooldown + 600 then alarmAt[p] = nil end
    end
  end
  alarmAt[plate] = os.time()
  log('vehicle.remoteAlarm', src, { plate = plate, seconds = seconds })
  return Utils.ok({ alarm = true, seconds = seconds, cooldown = cooldown })
end))

lib.callback.register('nz:carlock:nearbyPlayers', Utils.safe(function(source)
  local src = validSrc(source)
  if not src then return Utils.fail(L('Invalid request')) end
  if limited(src, 'players') then return Utils.fail(L('Please wait a moment')) end
  local origin = pedCoords(src)
  if not origin then return Utils.ok({}) end
  local bucket = GetPlayerRoutingBucket(tostring(src))
  local maxDist = CarLock.range('give') + NEARBY_MARGIN
  local list = {}
  for _, idStr in ipairs(GetPlayers() or {}) do
    local other = tonumber(idStr)
    if other and other ~= src and GetPlayerRoutingBucket(tostring(other)) == bucket then
      local pos = pedCoords(other)
      local dist = pos and #(pos - origin) or math.huge
      if dist <= maxDist and identifierOf(other) then
        local okName, name = pcall(NZ.Bridge.getName, other)
        list[#list + 1] = {
          serverId = math.tointeger(other) or other,
          name = okName and type(name) == 'string' and name ~= '' and name or (GetPlayerName(tostring(other)) or ('#' .. other)),
          distance = round1(dist),
        }
      end
    end
  end
  table.sort(list, function(a, b) return a.distance < b.distance end)
  return Utils.ok(list)
end))

---------------------------------------------------------------------------------------
-- Key ring from the server (a fob used far from its vehicle)
---------------------------------------------------------------------------------------

--- Open the key ring on a player's screen, on `plate` when given.
---@param src number
---@param plate string|nil
---@return boolean
function CarLock.openKeyRing(src, plate)
  src = validSrc(src)
  if not src or not CarLock.enabled() then return false end
  TriggerClientEvent('nz:client:carlock:keyRing', src, { plate = normPlate(plate) })
  return true
end
