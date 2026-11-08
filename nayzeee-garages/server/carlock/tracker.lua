--[[
  nayzeee-garages — car lock: vehicle tracker and key ring status (server, NZ.CarLock).
  docs/CARLOCK.md §3, §10.

  The key ring (client/carlock/keysapp.lua) gets its keys AND the state of the vehicles behind
  them from ONE call (nz:carlock:tracker {}: one NZ.CarLock.keysOf, one pass over the world),
  locks / shares through the core callbacks (toggleLock, share) and manages key holders here
  (keyHolders / keyRevoke: names of thieves masked, identifiers never leave the server).

  A vehicle is TRACKABLE when Config.CarLock.tracker.enabled, its security profile has
  `tracker = true`, it exists in the player's routing bucket, it is not on the impound tow
  truck (NZ.Tow.isTowing) and the player's key gives TRACKER ACCESS: a REAL key. Real keys:
  the owner, a garage share / fleet access, a virtual key the owner gave, a temporary key of a
  service (garage hand-out, job spawner, staff, contract, export, NPC assist, new locks) and a
  key item without a crime origin. Not real: a temporary key from a crime or another script
  (hotwire, robbery, search, back-alley locksmith, compat, any unknown reason) and a key item
  with a crime origin (metadata.origin: 'locksmith' = cut by a back-alley locksmith, 'search'
  = spare key found in a vehicle; any origin that is not a service). The owner's own keys are
  always real. Config.CarLock.tracker.tempKeys = true gives every key tracker access. Only
  trackable vehicles report a distance / position; everything is measured from the SERVER ped
  position. Locking stays a normal range-limited action. The owner's private nickname is only
  shown to holders of a real key.

  Callbacks (lib.callback, { ok, data, error }):
    nz:carlock:tracker       {}        -> { now, tracker, mode, keys = NZ.CarLock.keysOf(src),
                                            vehicles = { KeyStatus } }   every key
                             { plate } -> { now, tracker, vehicles = { KeyStatus } }   one key (NZ.CarLock.hasKey),
                                          with `coords` when trackable (waypoint)
      KeyStatus = { plate, owned, isOwner, nickname?, model?, hash?, spawned, netId?, profile,
                    profileLabel, remote, keyType ('key'|'fob'), tracker, trackerAccess,
                    origin? (how a key that is not real was obtained: the temporary key's
                    reason / the key item's origin), trackable, towing, locked?, alarm,
                    distance? (trackable), coords? (trackable, one plate),
                    immobiliser ('none'|'standard'|'ghost') }
      tracker access follows Config.CarLock.tracker.who ('real' | 'any' | 'owner')
    nz:carlock:trackerAlarm  { plate, on? } -> { alarm, seconds?, cooldown, refused?, message? }
                             remote alarm of a trackable vehicle (NZ.CarLock.alarm, Config.CarLock.
                             tracker.alarmSeconds); a new alarm waits tracker.alarmCooldown seconds
                             per vehicle: then ok with refused = 'cooldown' (cooldown = seconds
                             left, message = translated text); on = false (or a second press)
                             silences it
    nz:carlock:nearbyPlayers {} -> { { serverId, name, anonymous?, distance } } players within the
                             hand-over range (+ margin); character names only with
                             Config.CarLock.sharePicker.names = true (else name = 'Player <server
                             id>', anonymous = true: no names of strangers)
    nz:carlock:keyHolders    { plate }        -> { { id, name, kind, reason?, masked?, at?, expires? } }
                             owner / admin. id is an opaque token (10 min) standing for the holder's
                             identifier on the server; holders of a temporary key that is not a
                             service's (hotwire, robbery, search, locksmith, compat, unknown) are
                             'Unknown holder'; the owner's own keys are not listed
    nz:carlock:keyRevoke     { plate, id }    -> the new holder list (NZ.CarLock.revokeVirtual)

  Server API:
    NZ.CarLock.keyStatus(src, plate, entity?, opts?) -> KeyStatus
    NZ.CarLock.trackerEnabled() -> boolean
    NZ.CarLock.openKeyRing(src, plate?)   opens the key ring on that player's screen (fob use)
    NZ.CarLock.keyHolderList(src, plate) -> the masked holder list (the caller checks the owner)
    NZ.CarLock.keyItemSummary(src, plate?) -> { [plate] = { count, real, kind, origin? } }
                                     valid key items the player carries (physical mode)
    NZ.CarLock.isServiceKey(reason) -> boolean   a temporary key reason / key item origin of a service
]]

local CarLock = NZ.CarLock
local Utils = NZ.Utils

local RATE = { list = 900, one = 400, alarm = 1200, players = 800, holders = 500, revoke = 700 }
local MAX_LIST = 60             -- keys reported by one list call
local NEARBY_MARGIN = 1.5       -- m: players a little farther than ranges.give are offered (the share re-checks)
local DEFAULT_COOLDOWN = 60     -- s: between two remote alarms of one vehicle
local TOKEN_TTL = 600           -- s: a key holder id handed to the key ring stays valid this long
local MAX_TOKENS = 400          -- key holder ids kept per player (older ones are dropped)

-- Reasons of temporary keys (and origins of key items) of a service: a real key (tracker
-- access, the owner's nickname, a name in Key holders). Every other reason is a crime's or
-- another script's (hotwire, robbery, search, back-alley locksmith, compat, unknown ones).
local SERVICE = { garage = true, spawner = true, admin = true, contract = true, export = true,
  assist = true, rekey = true, share = true }

local alarmAt = {}              -- [plate] = os.time() of the last remote alarm
local alarmCount = 0
local holderTokens = {}         -- [src] = { byToken = { [id] = { identifier, plate, expires } }, byKey = { [plate|identifier] = id }, count }

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

--- Is a temporary key of this reason / a key item of this origin a service's key (a real key)?
--- A key item without an origin is a real key too (the owner's keys and copies of them).
---@param reason string|nil
---@return boolean
function CarLock.isServiceKey(reason)
  return type(reason) == 'string' and SERVICE[reason] == true
end

--- Crime origin of a key item (metadata.origin, written by the server: players cannot edit
--- item metadata), nil for a real key item.
local function crimeOrigin(md)
  local origin = md.origin
  if origin == nil or CarLock.isServiceKey(origin) then return nil end
  return type(origin) == 'string' and origin:sub(1, 16) or 'other'
end

--- Valid key items a player carries (physical mode; one pass over the inventory), per plate:
--- { count, real (items without a crime origin), kind ('key'|'fob', a real item's first),
--- origin (crime origin, only when no item is real) }. plate: only that plate.
---@param src number
---@param plate string|nil
---@return table<string, table>
function CarLock.keyItemSummary(src, plate)
  local out = {}
  if CarLock.mode() ~= 'physical' then return out end
  local only = plate and normPlate(plate) or nil
  for _, item in pairs(CarLock.keyItems()) do
    local filter = only and function(md) return Utils.plate(md and md.plate) == only end or nil
    for _, entry in ipairs(NZ.Inventory.find(src, item, filter) or {}) do
      local md = entry.metadata
      if type(md) == 'table' and CarLock.verifyKeyItem(md) then
        local p = Utils.plate(md.plate)
        if p and (not only or p == only) then
          local cur = out[p]
          if not cur then
            cur = { count = 0, real = 0 }
            out[p] = cur
          end
          local n = math.max(math.floor(tonumber(entry.count) or 1), 1)
          local origin = crimeOrigin(md)
          cur.count = cur.count + n
          if origin then
            cur.crimeOrigin = cur.crimeOrigin or origin
            cur.crimeKind = cur.crimeKind or md.kind
          else
            cur.real = cur.real + n
            cur.kind = cur.kind or md.kind
          end
        end
      end
    end
  end
  for _, cur in pairs(out) do
    cur.origin = cur.real == 0 and cur.crimeOrigin or nil
    cur.kind = cur.kind or cur.crimeKind
    cur.crimeOrigin, cur.crimeKind = nil, nil
  end
  return out
end

--- Is the player's key of `plate` a real key? kind / reason: the key (NZ.CarLock.keysOf /
--- hasKey). Real: the owner, a virtual key, garage share / fleet access ('owner'), a service's
--- temporary key, a key item without a crime origin. items: CarLock.keyItemSummary(src) when
--- the caller has it. Returns real, origin (how a key that is not real was obtained).
---@return boolean real, string|nil origin
local function realKey(src, plate, kind, reason, items)
  local origin
  if kind == 'temp' then
    if CarLock.isServiceKey(reason) then return true, nil end
    origin = type(reason) == 'string' and reason or 'other'
  elseif kind == 'item' then
    local info = (items or CarLock.keyItemSummary(src, plate))[plate]
    if info and info.real > 0 then return true, nil end
    origin = info and info.origin or 'other'
  else
    return true, nil
  end
  -- the owner's own key (a hotwired car of their own, a copy from the back alley) is real
  if CarLock.isOwner(src, plate) then return true, nil end
  return false, origin
end

--- Kind and reason of the best key a player holds for `plate`. NZ.CarLock.hasKey answers
--- 'temp' first; keysOf ranks owner > item > virtual > temp and knows the temporary key's
--- reason (only asked for a temporary key of a vehicle the player does not own).
local function bestKeyOf(src, plate, kind)
  if kind ~= 'temp' or CarLock.isOwner(src, plate) then return kind, nil end
  for _, key in ipairs(CarLock.keysOf(src)) do
    if key.plate == plate then return key.kind, key.reason end
  end
  return kind, nil
end

--- Tracker access of a key (Config.CarLock.tracker.who): 'real' (default) = a real key,
--- 'any' = every key (or tracker.tempKeys = true), 'owner' = the owner and garage shares /
--- fleets only.
local function trackAccess(src, plate, real, kind)
  local t = trackerCfg()
  if t.tempKeys == true or t.who == 'any' then return true end
  if t.who == 'owner' then return kind == 'owner' or CarLock.isOwner(src, plate) end
  return real == true
end

---------------------------------------------------------------------------------------
-- Status of one key
---------------------------------------------------------------------------------------

--- What the key ring shows about the vehicle of a key the player HAS (the caller checked it).
--- entity: the vehicle when already known (nil = looked up by plate in the player's bucket,
--- false = known not to be out).
--- opts = { coords = true }: include the position of a trackable vehicle; opts.model: spawn
--- name from the key list (items carry it); opts.kind / opts.reason: the player's key
--- (keysOf / hasKey), which decides tracker access and the owner's nickname (no kind = not a
--- real key unless the player owns the vehicle); opts.items: CarLock.keyItemSummary(src).
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

  local isOwner = row ~= nil and id ~= nil and row.owner == id
  local real, origin = isOwner, nil
  if not isOwner then
    if opts.kind ~= nil then
      real, origin = realKey(src, plate, opts.kind, opts.reason, opts.items)
    else
      origin = 'other'
    end
  end
  local status = {
    plate = plate,
    owned = row ~= nil,
    isOwner = isOwner,
    -- the owner's private nickname: never for a crime's key (hotwired, robbed, back-alley copy)
    nickname = real and row and type(row.nickname) == 'string' and row.nickname ~= '' and row.nickname or nil,
    model = row and row.model or (type(opts.model) == 'string' and opts.model ~= '' and opts.model or nil),
    hash = entity and GetEntityModel(entity) or (row and (tonumber(row.hash) or hashOf(row.model))) or hashOf(opts.model),
    spawned = entity ~= nil,
    netId = entity and NetworkGetNetworkIdFromEntity(entity) or nil,
    profile = profileName,
    profileLabel = type(profile.label) == 'string' and L(profile.label) or L('Standard'),
    remote = profile.remote == true,
    keyType = CarLock.keyKindOf(profile),
    tracker = profile.tracker == true,
    trackerAccess = trackAccess(src, plate, real, isOwner and 'owner' or opts.kind),
    origin = not real and origin or nil,
    trackable = false,
    towing = false,
    alarm = false,
    immobiliser = CarLock.immobiliserOf(plate),
  }
  if not entity then return status end

  status.towing = towing(entity)
  status.locked = CarLock.isLocked(entity)
  status.alarm = alarmSounding(entity)
  status.trackable = CarLock.trackerEnabled() and status.tracker and status.trackerAccess and not status.towing
  if status.trackable then
    local from = pedCoords(src)
    local pos = GetEntityCoords(entity)
    if from then status.distance = math.floor(#(pos - from) + 0.5) end
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
    local has, kind = CarLock.hasKey(src, plate)
    if not has then return Utils.fail(L('You do not have the keys of this vehicle')) end
    local best, reason = bestKeyOf(src, plate, kind)
    return Utils.ok({ now = os.time(), tracker = CarLock.trackerEnabled(),
      vehicles = { CarLock.keyStatus(src, plate, nil, { coords = true, kind = best, reason = reason }) } })
  end

  if limited(src, 'list') then return Utils.fail(L('Please wait a moment')) end
  -- one keysOf for the whole key ring: the keys AND the vehicles behind them
  local keys = CarLock.keysOf(src)
  local items = CarLock.keyItemSummary(src)
  local list = {}
  for _, key in ipairs(keys) do
    if #list >= MAX_LIST then break end
    local entity = key.netId and entityOfNet(src, key.netId) or nil
    -- keysOf already scanned the world: a key without a net id has no vehicle out
    list[#list + 1] = CarLock.keyStatus(src, key.plate, entity or false,
      { model = key.model, kind = key.kind, reason = key.reason, items = items })
  end
  return Utils.ok({ now = os.time(), tracker = CarLock.trackerEnabled(), mode = CarLock.mode(), keys = keys, vehicles = list })
end))

lib.callback.register('nz:carlock:trackerAlarm', Utils.safe(function(source, payload)
  local src = validSrc(source)
  if not src or type(payload) ~= 'table' then return Utils.fail(L('Invalid request')) end
  if not CarLock.enabled() then return Utils.fail(L('Vehicle keys are handled by another script')) end
  if limited(src, 'alarm') then return Utils.fail(L('Please wait a moment')) end
  if not CarLock.trackerEnabled() then return Utils.fail(L('The vehicle tracker is not available')) end
  local plate = normPlate(payload.plate)
  if not plate then return Utils.fail(L('Invalid plate')) end
  local has, kind = CarLock.hasKey(src, plate)
  if not has then return Utils.fail(L('You do not have the keys of this vehicle')) end
  local best, reason = bestKeyOf(src, plate, kind)
  if not trackAccess(src, plate, realKey(src, plate, best, reason), best) then
    return Utils.fail(L('This key has no tracker access'))
  end
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
    -- not an error: the key ring counts the seconds down (no parsing of translated text)
    local left = cooldown - (os.time() - last)
    return Utils.ok({ alarm = false, refused = 'cooldown', cooldown = left,
      message = L('The alarm can be triggered again in {seconds} s', { seconds = left }) })
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
  -- names of strangers are metagaming on most servers: the server id only, unless the owner
  -- of the server turns names on (Config.CarLock.sharePicker.names)
  local picker = CarLock.cfg().sharePicker
  local names = type(picker) == 'table' and picker.names == true
  local list = {}
  for _, idStr in ipairs(GetPlayers() or {}) do
    local other = tonumber(idStr)
    if other and other ~= src and GetPlayerRoutingBucket(tostring(other)) == bucket then
      local pos = pedCoords(other)
      local dist = pos and #(pos - origin) or math.huge
      if dist <= maxDist and identifierOf(other) then
        local id = math.tointeger(other) or other
        local name
        if names then
          local okName, character = pcall(NZ.Bridge.getName, other)
          name = okName and type(character) == 'string' and character ~= '' and character or nil
        end
        list[#list + 1] = {
          serverId = id,
          name = name or L('Player {id}', { id = id }),
          anonymous = name == nil or nil,
          distance = round1(dist),
        }
      end
    end
  end
  table.sort(list, function(a, b) return a.distance < b.distance end)
  return Utils.ok(list)
end))

---------------------------------------------------------------------------------------
-- Key holders (owner): masked thieves, opaque ids
---------------------------------------------------------------------------------------

--- Key holder ids of a player, expired ones dropped.
local function tokensOf(src)
  local t = holderTokens[src]
  if not t or t.count > MAX_TOKENS then
    t = { byToken = {}, byKey = {}, count = 0 }
    holderTokens[src] = t
  end
  local nowTs = os.time()
  for id, e in pairs(t.byToken) do
    if e.expires <= nowTs then
      t.byToken[id], t.byKey[e.plate .. '|' .. e.identifier] = nil, nil
      t.count = t.count - 1
    end
  end
  return t
end

--- Opaque id of a key holder for this player (the same id while it is valid).
local function holderId(t, plate, identifier)
  local key = plate .. '|' .. identifier
  local id = t.byKey[key]
  if not id then
    repeat
      id = ('%06x%06x'):format(math.random(0, 0xffffff), math.random(0, 0xffffff))
    until not t.byToken[id]
    t.byKey[key] = id
    t.count = t.count + 1
  end
  t.byToken[id] = { identifier = identifier, plate = plate, expires = os.time() + TOKEN_TTL }
  return id
end

--- The key holders of `plate` as an owner may see them: { { id, name, kind, reason?, masked?,
--- at?, expires? } }. Identifiers never leave the server (id = an opaque token of this player
--- for nz:carlock:keyRevoke); holders of a temporary key that is not a service's (a crime,
--- another script, an unknown reason) are 'Unknown holder'. The owner's own keys are not
--- listed. The caller checks that `src` owns the vehicle (or is an admin).
---@param src number
---@param plate string
---@return table[]
function CarLock.keyHolderList(src, plate)
  local t = tokensOf(src)
  local row = CarLock.vehicleRow(plate)
  local owner = row and type(row.owner) == 'string' and row.owner or nil
  local out = {}
  for _, h in ipairs(CarLock.holders(plate)) do
    if type(h) == 'table' and type(h.identifier) == 'string' and h.identifier ~= '' and h.identifier ~= owner then
      local temp = h.kind == 'temp'
      -- masked unless the key comes from a service: unknown reasons are treated like crimes
      local masked = temp and not CarLock.isServiceKey(h.reason)
      out[#out + 1] = {
        id = holderId(t, plate, h.identifier),
        name = masked and L('Unknown holder') or (type(h.name) == 'string' and h.name or L('Unknown')),
        kind = temp and 'temp' or 'virtual',
        reason = temp and type(h.reason) == 'string' and h.reason or nil,
        masked = masked or nil,
        at = tonumber(h.at),
        expires = temp and tonumber(h.expires) or nil,
      }
    end
  end
  return out
end

local function holderAccess(src, plate)
  return CarLock.isOwner(src, plate) or NZ.Access.isAdmin(src)
end

lib.callback.register('nz:carlock:keyHolders', Utils.safe(function(source, payload)
  local src = validSrc(source)
  if not src or type(payload) ~= 'table' then return Utils.fail(L('Invalid request')) end
  if not CarLock.enabled() then return Utils.fail(L('Vehicle keys are handled by another script')) end
  if limited(src, 'holders') then return Utils.fail(L('Please wait a moment')) end
  local plate = normPlate(payload.plate)
  if not plate then return Utils.fail(L('Invalid request')) end
  if not holderAccess(src, plate) then return Utils.fail(L('Only the owner can manage the keys of this vehicle')) end
  return Utils.ok(CarLock.keyHolderList(src, plate))
end))

lib.callback.register('nz:carlock:keyRevoke', Utils.safe(function(source, payload)
  local src = validSrc(source)
  if not src or type(payload) ~= 'table' then return Utils.fail(L('Invalid request')) end
  if not CarLock.enabled() then return Utils.fail(L('Vehicle keys are handled by another script')) end
  if limited(src, 'revoke') then return Utils.fail(L('Please wait a moment')) end
  local plate = normPlate(payload.plate)
  local id = type(payload.id) == 'string' and #payload.id <= 32 and payload.id or nil
  if not plate or not id then return Utils.fail(L('Invalid request')) end
  local t = tokensOf(src)
  local entry = t.byToken[id]
  if not entry or entry.plate ~= plate then return Utils.fail(L('The key holder list is out of date: refresh it')) end
  -- revokeVirtual checks the owner / admin again
  local ok, err = CarLock.revokeVirtual(src, entry.identifier, plate)
  if not ok then return Utils.fail(err or L('Something went wrong')) end
  t.byToken[id], t.byKey[plate .. '|' .. entry.identifier] = nil, nil
  t.count = t.count - 1
  return Utils.ok(CarLock.keyHolderList(src, plate))
end))

AddEventHandler('playerDropped', function()
  local src = tonumber(source)
  if src then holderTokens[math.tointeger(src) or src] = nil end
end)

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

---------------------------------------------------------------------------------------
-- Admin key manager (docs/CARLOCK.md §19; command Config.CarLock.commands.keyAdmin,
-- /vehiclekeysadmin). NZ.CarLock.isAdmin only, every call rate limited and logged.
--   nz:carlock:admin:search  { query }                      -> { rows = { KeyAdminPlayer } }
--                            name / citizen id (framework characters) / plate (owners first)
--   nz:carlock:admin:player  { identifier }                 -> KeyAdminPlayerData
--   nz:carlock:admin:give    { identifier, plate, type = 'item'|'temp'|'virtual', keyKind?, hours? }
--                                                           -> KeyAdminPlayerData
--                            item: the player must be online (inventory); temp works offline;
--                            virtual: registered vehicles only (no owner check)
--   nz:carlock:admin:delete  { identifier, id }             -> KeyAdminPlayerData
--                            id from a KeyAdminRow: 'temp:<plate>' | 'virtual:<plate>' |
--                            'item:<plate>:<keyId>' | 'ground:<groundId>' (owner rows cannot be
--                            deleted). A key item in a pocket of an online player or an
--                            ox_inventory stash is taken out; otherwise it is marked lost (change
--                            the locks to retire it for sure)
--   nz:carlock:admin:plate   { plate }                      -> KeyAdminPlateData (every key of a vehicle)
--   nz:carlock:admin:track   { plate }                      -> { plate, spawned, coords?, distance?, bucket? }
-- KeyAdminPlayer = { identifier, name, online, serverId?, matchedPlates }
-- KeyAdminRow = { id, plate, model?, type ('key'|'fob'|'virtual'|'temp'|'owner'), origin,
--   custody = { kind ('inventory'|'stash'|'ground'|'server'|'unknown'|'lost'|'flight'), slot?,
--   stash?, groundId? }, spawned, netId?, distance?, expires?, current?, shared? ('in'|'out'),
--   deletable }
-- KeyAdminPlayerData = { player = KeyAdminPlayer, keys = { KeyAdminRow }, totals = { keys,
--   vehicles, sharedIn, sharedOut } }
---------------------------------------------------------------------------------------

local ADMIN_RATE = 250
local ADMIN_MAX_ROWS = 300

local function adminOk(src)
  if not CarLock.isAdmin(src) then
    log('security.adminCommand', src, { command = 'keyAdmin' })
    return false
  end
  return NZ.Access.rateLimit(src, 'carlock:keyAdmin', ADMIN_RATE)
end

local function identifierArg(value)
  if type(value) ~= 'string' or value == '' or #value > 64 or value:find('[%c]') then return nil end
  return value
end

local function sourceOf(identifier)
  if type(NZ.Bridge.getSourceByIdentifier) ~= 'function' then return nil end
  local ok, res = pcall(NZ.Bridge.getSourceByIdentifier, identifier)
  return ok and validSrc(res) or nil
end

local function nameOf(identifier)
  local ok, name = pcall(NZ.Bridge.getCharacterName, identifier)
  return ok and type(name) == 'string' and name or L('Unknown')
end

local function playerInfo(identifier)
  local src = sourceOf(identifier)
  return { identifier = identifier, name = nameOf(identifier), online = src ~= nil, serverId = src }
end

--- One pass over the world: { [real plate] = entity } (every bucket).
local function spawnedPlates()
  local out = {}
  for _, entity in ipairs(GetAllVehicles() or {}) do
    local plate = isVehicle(entity) and CarLock.realPlate(entity) or nil
    if plate and not out[plate] then out[plate] = entity end
  end
  return out
end

--- custody table of a recorded key item (nz_key_items row)
local function custodyOf(row)
  local holder = row.holder or ''
  if row.custody == 'player' then return { kind = 'inventory', slot = row.slot } end
  if row.custody == 'stash' then return { kind = 'stash', stash = holder } end
  if row.custody == 'ground' then return { kind = 'ground', groundId = holder:match('^ground:(.+)$') } end
  if row.custody == 'lost' then return { kind = 'lost' } end
  if holder:match('^flight:') then return { kind = 'flight' } end
  return { kind = 'unknown' }
end

local function playerKeys(identifier)
  local src = sourceOf(identifier)
  local rows = {}
  local world = spawnedPlates()
  local from = src and pedCoords(src) or nil
  local models = {}
  local function add(row)
    if #rows >= ADMIN_MAX_ROWS then return end
    local entity = world[row.plate]
    row.spawned = entity ~= nil
    if entity then
      row.netId = NetworkGetNetworkIdFromEntity(entity)
      if from then row.distance = math.floor(#(GetEntityCoords(entity) - from) + 0.5) end
    end
    row.model = row.model or models[row.plate]
    rows[#rows + 1] = row
  end

  -- owned vehicles (and the shares going out)
  local sharedOut, owned = 0, 0
  local okOwned, ownedRows = pcall(NZ.DB.getVehiclesByOwner, identifier)
  for _, v in ipairs(okOwned and type(ownedRows) == 'table' and ownedRows or {}) do
    local plate = normPlate(v.plate)
    if plate then
      owned = owned + 1
      models[plate] = v.model
      add({ id = 'owner:' .. plate, plate = plate, model = v.model, type = 'owner', origin = 'owner',
        custody = { kind = 'server' }, deletable = false })
      if NZ.DB.keys and type(NZ.DB.keys.list) == 'function' then
        local okList, list = pcall(NZ.DB.keys.list, plate)
        for _, k in ipairs(okList and type(list) == 'table' and list or {}) do
          if k.identifier ~= identifier then sharedOut = sharedOut + 1 end
        end
      end
    end
  end
  -- garage shares coming in
  local sharedIn = 0
  local okShares, shares = pcall(NZ.DB.shares.forIdentifier, identifier)
  for _, entry in ipairs(okShares and type(shares) == 'table' and shares or {}) do
    local plate = normPlate(type(entry) == 'table' and entry.plate or entry)
    if plate then
      sharedIn = sharedIn + 1
      add({ id = 'share:' .. plate, plate = plate, type = 'owner', origin = 'share', shared = 'in',
        custody = { kind = 'server' }, deletable = false })
    end
  end
  -- virtual keys
  if NZ.DB.keys and type(NZ.DB.keys.forIdentifier) == 'function' then
    local okV, plates = pcall(NZ.DB.keys.forIdentifier, identifier)
    for _, plate in ipairs(okV and type(plates) == 'table' and plates or {}) do
      sharedIn = sharedIn + 1
      add({ id = 'virtual:' .. plate, plate = plate, type = 'virtual', origin = 'virtual', shared = 'in',
        custody = { kind = 'server' }, deletable = true })
    end
  end
  -- temporary keys
  for plate, t in pairs(CarLock.tempKeysOfHolder(identifier)) do
    add({ id = 'temp:' .. plate, plate = plate, type = 'temp', origin = t.reason, expires = t.expires,
      custody = { kind = 'server' }, deletable = true })
  end
  -- key items: the live pocket of an online player first, then the custody records
  local seen = {}
  if src and CarLock.mode() == 'physical' then
    for _, item in pairs(CarLock.keyItems()) do
      for _, entry in ipairs(NZ.Inventory.find(src, item) or {}) do
        local md = entry.metadata
        local ref = type(md) == 'table' and CarLock.keyRef(md) or nil
        if ref and not seen[ref] then
          seen[ref] = true
          local valid = CarLock.verifyKeyItem(md)
          add({ id = 'item:' .. ref, plate = normPlate(md.plate), model = md.model, type = md.kind == 'fob' and 'fob' or 'key',
            origin = type(md.origin) == 'string' and md.origin or 'key', current = valid == true,
            custody = { kind = 'inventory', slot = entry.slot }, deletable = true })
        end
      end
    end
  end
  if NZ.DB.keyItems then
    local okR, recorded = pcall(NZ.DB.keyItems.forHolder, identifier)
    for _, r in ipairs(okR and type(recorded) == 'table' and recorded or {}) do
      if not seen[r.id] and r.custody ~= 'lost' then
        seen[r.id] = true
        local version = CarLock.keyVersion(r.plate)
        add({ id = 'item:' .. r.id, plate = r.plate, type = r.kind, origin = r.origin or 'key',
          current = version ~= nil and r.version == version, custody = custodyOf(r), deletable = true })
      end
    end
    -- keys of their own vehicles somewhere else (stash, ground, unknown pockets)
    for plate in pairs(models) do
      local okP, list = pcall(NZ.DB.keyItems.forPlate, plate)
      local version = CarLock.keyVersion(plate)
      for _, r in ipairs(okP and type(list) == 'table' and list or {}) do
        if not seen[r.id] and r.custody ~= 'lost' and r.custody ~= 'player' and version ~= nil and r.version == version then
          seen[r.id] = true
          add({ id = 'item:' .. r.id, plate = r.plate, type = r.kind, origin = r.origin or 'key', current = true,
            custody = custodyOf(r), deletable = true })
        end
      end
    end
  end
  table.sort(rows, function(a, b)
    if a.plate ~= b.plate then return a.plate < b.plate end
    return a.id < b.id
  end)
  return { player = playerInfo(identifier), keys = rows,
    totals = { keys = #rows, vehicles = owned, sharedIn = sharedIn, sharedOut = sharedOut } }
end

lib.callback.register('nz:carlock:admin:search', Utils.safe(function(source, payload)
  local src = validSrc(source)
  if not src or type(payload) ~= 'table' then return Utils.fail(L('Invalid request')) end
  if not adminOk(src) then return Utils.fail(L('You are not allowed to do that')) end
  local query = type(payload.query) == 'string' and Utils.trim((payload.query:gsub('%c', ''))) or ''
  if #query > 64 then query = query:sub(1, 64) end
  local rows, seen = {}, {}
  local function add(identifier, name, plate)
    if type(identifier) ~= 'string' or identifier == '' then return end
    local row = seen[identifier]
    if not row then
      if #rows >= 50 then return end
      local who = sourceOf(identifier)
      row = { identifier = identifier, name = name or nameOf(identifier), online = who ~= nil, serverId = who, matchedPlates = {} }
      seen[identifier] = row
      rows[#rows + 1] = row
    end
    if plate then row.matchedPlates[#row.matchedPlates + 1] = plate end
  end
  -- a server id of an online player
  local id = tonumber(query)
  if id and validSrc(id) then
    local ident = identifierOf(validSrc(id))
    if ident then add(ident, nil, nil) end
  end
  local upper = query:upper()
  if #upper >= 2 and #upper <= 8 and upper:match('^[A-Z0-9 ]+$') and type(NZ.DB.searchPlates) == 'function' then
    local okP, hits = pcall(NZ.DB.searchPlates, upper, 30)
    for _, hit in ipairs(okP and type(hits) == 'table' and hits or {}) do add(hit.owner, nil, hit.plate) end
  end
  if #query >= 2 and type(NZ.Bridge.searchCharacters) == 'function' then
    local okC, list = pcall(NZ.Bridge.searchCharacters, query, 30, 0)
    for _, c in ipairs(okC and type(list) == 'table' and list or {}) do
      if type(c) == 'table' then add(c.identifier, c.name, nil) end
    end
  end
  return Utils.ok({ rows = rows })
end))

lib.callback.register('nz:carlock:admin:player', Utils.safe(function(source, payload)
  local src = validSrc(source)
  if not src or type(payload) ~= 'table' then return Utils.fail(L('Invalid request')) end
  if not adminOk(src) then return Utils.fail(L('You are not allowed to do that')) end
  local identifier = identifierArg(payload.identifier)
  if not identifier then return Utils.fail(L('Invalid identifier')) end
  return Utils.ok(playerKeys(identifier))
end))

lib.callback.register('nz:carlock:admin:give', Utils.safe(function(source, payload)
  local src = validSrc(source)
  if not src or type(payload) ~= 'table' then return Utils.fail(L('Invalid request')) end
  if not adminOk(src) then return Utils.fail(L('You are not allowed to do that')) end
  local identifier = identifierArg(payload.identifier)
  local plate = normPlate(payload.plate)
  if not identifier or not plate then return Utils.fail(L('Invalid request')) end
  local kind = payload.type
  if kind == 'item' then
    local target = sourceOf(identifier)
    if not target then return Utils.fail(L('The player must be online for a key item')) end
    local keyKind = (payload.keyKind == 'fob' or payload.keyKind == 'key') and payload.keyKind or nil
    local ok, err = CarLock.giveKeyItem(target, plate, { kind = keyKind, reason = 'admin' })
    if not ok then return Utils.fail(err or L('Something went wrong')) end
  elseif kind == 'temp' then
    local hours = tonumber(payload.hours)
    if not CarLock.grantTempTo(identifier, plate, 'admin', hours and Utils.clamp(hours, 0.05, 720) or nil) then
      return Utils.fail(L('Something went wrong'))
    end
  elseif kind == 'virtual' then
    if not CarLock.vehicleRow(plate) then return Utils.fail(L('Only registered vehicles have virtual keys')) end
    if CarLock.keyVersion(plate) == nil then return Utils.fail(L('Something went wrong')) end
    if not (NZ.DB.keys and NZ.DB.keys.add(plate, identifier, identifierOf(src) or 'admin')) then
      return Utils.fail(L('Something went wrong'))
    end
    CarLock.invalidate(plate)
    local target = sourceOf(identifier)
    if target then TriggerClientEvent('nz:client:carlock:keys', target, { plate = plate }) end
  else
    return Utils.fail(L('Invalid request'))
  end
  log('admin.giveKey', src, { target = identifier, plate = plate, type = kind })
  return Utils.ok(playerKeys(identifier))
end))

lib.callback.register('nz:carlock:admin:delete', Utils.safe(function(source, payload)
  local src = validSrc(source)
  if not src or type(payload) ~= 'table' then return Utils.fail(L('Invalid request')) end
  if not adminOk(src) then return Utils.fail(L('You are not allowed to do that')) end
  local identifier = identifierArg(payload.identifier)
  local id = type(payload.id) == 'string' and #payload.id <= 64 and payload.id or nil
  if not identifier or not id then return Utils.fail(L('Invalid request')) end
  local kind, rest = id:match('^(%a+):(.+)$')
  if kind == 'temp' then
    CarLock.revokeTemp(identifier, rest)
  elseif kind == 'virtual' then
    local ok, err = CarLock.revokeVirtual(nil, identifier, rest)
    if not ok then return Utils.fail(err) end
  elseif kind == 'ground' then
    if not CarLock.groundDelete(rest) then return Utils.fail(L('This key is gone')) end
  elseif kind == 'item' then
    local plate, keyId = rest:match('^([^:]+):(%w+)$')
    plate = normPlate(plate)
    if not plate then return Utils.fail(L('Invalid request')) end
    local md = { plate = plate, id = keyId }
    local removed = false
    -- the pocket of an online player
    local target = sourceOf(identifier)
    if target then
      for _, item in pairs(CarLock.keyItems()) do
        if not removed and #NZ.Inventory.find(target, item, function(m) return type(m) == 'table' and m.id == keyId end) > 0 then
          removed = NZ.Inventory.removeItem(target, item, 1, { id = keyId })
        end
      end
      if removed then TriggerClientEvent('nz:client:carlock:keys', target, { plate = plate }) end
    end
    local row = NZ.DB.keyItems and NZ.DB.keyItems.get(plate .. ':' .. keyId) or nil
    if not removed and row and row.custody == 'ground' then
      local groundId = (row.holder or ''):match('^ground:(.+)$')
      removed = groundId ~= nil and CarLock.groundDelete(groundId) ~= nil
    end
    if not removed and row and row.custody == 'stash' and type(NZ.Inventory.removeFromStash) == 'function' then
      for _, item in pairs(CarLock.keyItems()) do
        if not removed then removed = NZ.Inventory.removeFromStash(row.holder, item, { id = keyId }) end
      end
    end
    CarLock.moveKeyItem(md, 'lost', row and row.holder or nil, nil)
  else
    return Utils.fail(L('This key cannot be deleted'))
  end
  log('admin.deleteKey', src, { target = identifier, id = id })
  return Utils.ok(playerKeys(identifier))
end))

lib.callback.register('nz:carlock:admin:plate', Utils.safe(function(source, payload)
  local src = validSrc(source)
  if not src or type(payload) ~= 'table' then return Utils.fail(L('Invalid request')) end
  if not adminOk(src) then return Utils.fail(L('You are not allowed to do that')) end
  local plate = normPlate(payload.plate)
  if not plate then return Utils.fail(L('Invalid plate')) end
  local row = CarLock.vehicleRow(plate)
  local entity, dist = CarLock.findVehicle(plate, src)
  local custody = {}
  for _, r in ipairs(CarLock.keyCustody(plate)) do
    custody[#custody + 1] = { id = 'item:' .. r.id, type = r.kind, origin = r.origin or 'key', current = r.current,
      custody = custodyOf(r), holder = r.custody == 'player' and r.holder or nil,
      holderName = r.custody == 'player' and r.holder and nameOf(r.holder) or nil }
  end
  local holders = {}
  for _, h in ipairs(CarLock.holders(plate)) do
    holders[#holders + 1] = { identifier = h.identifier, name = h.name, type = h.kind, origin = h.reason, expires = h.expires }
  end
  local level, pinSet = CarLock.immobiliserOf(plate)
  return Utils.ok({
    plate = plate, owned = row ~= nil, owner = row and row.owner or nil, ownerName = row and row.owner and nameOf(row.owner) or nil,
    model = row and row.model or nil, version = CarLock.keyVersion(plate), live = CarLock.liveKeyCount(plate),
    immobiliser = { level = level, pinSet = pinSet }, spawned = entity ~= nil,
    netId = entity and NetworkGetNetworkIdFromEntity(entity) or nil, distance = dist and math.floor(dist + 0.5) or nil,
    custody = custody, holders = holders, ground = CarLock.groundKeys(plate),
  })
end))

lib.callback.register('nz:carlock:admin:track', Utils.safe(function(source, payload)
  local src = validSrc(source)
  if not src or type(payload) ~= 'table' then return Utils.fail(L('Invalid request')) end
  if not adminOk(src) then return Utils.fail(L('You are not allowed to do that')) end
  local plate = normPlate(payload.plate)
  if not plate then return Utils.fail(L('Invalid plate')) end
  local entity = spawnedPlates()[plate]
  if not entity then return Utils.ok({ plate = plate, spawned = false }) end
  local pos = GetEntityCoords(entity)
  local from = pedCoords(src)
  return Utils.ok({ plate = plate, spawned = true, bucket = GetEntityRoutingBucket(entity),
    coords = { x = round1(pos.x), y = round1(pos.y), z = round1(pos.z) },
    distance = from and math.floor(#(pos - from) + 0.5) or nil })
end))

-- /vehiclekeysadmin: opens the admin key manager (the NUI screen of the key manager listens
-- to the client event; without it the client says so)
do
  local commands = type(CarLock.cfg().commands) == 'table' and CarLock.cfg().commands or {}
  local name = commands.keyAdmin
  if CarLock.enabled() and type(name) == 'string' and name ~= '' then
    RegisterCommand(name, function(source)
      local src = validSrc(source)
      if not src then return end
      if not NZ.Access.rateLimit(src, 'carlock:command', 1000) then return end
      if not CarLock.isAdmin(src) then
        NZ.Bridge.notify(src, L('You are not allowed to do that'), 'error')
        log('security.adminCommand', src, { command = name })
        return
      end
      TriggerClientEvent('nz:client:carlock:keyAdmin', src, {})
    end, false)
  end
end
