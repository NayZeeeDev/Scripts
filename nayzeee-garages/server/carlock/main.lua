--[[
  nayzeee-garages — car lock: callbacks, key item use and the admin command (server).
  docs/CARLOCK.md §3.

  Callbacks (lib.callback, { ok, data, error }):
    nz:carlock:toggleLock { netId } | { netIds = { nearest first, max 8 } }
        -> { netId, plate, locked, kind }   the vehicle you sit in, else the nearest candidate
           you have a key for within its range (key / fob), measured from the SERVER ped
    nz:carlock:engine     { netId, on, class? } -> { on, kind? }   driver seat only
    nz:carlock:hasKey     { netId, class? } -> { plate, has, kind, ignition, locked }
                          { plate } -> { plate, has, kind }
    nz:carlock:keys       {} -> { mode, keys = NZ.CarLock.keysOf(src) }
    nz:carlock:share      { plate, target } -> { how = 'copy'|'handover'|'virtual'|'temp' }
                          NZ.CarLock.shareKey: flexible = a copy of your key item, limited = your
                          key item handed over, virtual = a persistent key (owner only) or a
                          temporary key of sharing.hours
    nz:carlock:revoke     { plate, identifier } -> null   admins only (staff tools; players revoke
                          through nz:carlock:keyRevoke with the key ring's opaque holder ids)
    nz:carlock:holders    { plate } -> NZ.CarLock.keyHolderList: { { id, name, kind, reason?, masked?,
                          at?, expires? } }   owner / admin; opaque ids, crime keys masked,
                          the owner's own keys left out (same list as nz:carlock:keyHolders)
    nz:carlock:compat     { action = 'acquire'|'remove'|'lend', netId?, plate?, target?, export? }
                          other scripts' CLIENT events / exports (bridge/client/listeners.lua):
                          temporary keys only, NZ.CarLock.canAcquire rules (a key allowed
                          through a share / fleet access ends with it); 'lend' needs a key
                          that is not temporary, in physical mode a key item is handed over
                          (owners may lend a temporary key);
                          export = true (client export GiveKey) needs clientGiveKeyExport
  Car lock v2 (sections below; data shapes in web/src/lib/types.ts):
    nz:carlock:playerSettings / savePlayerSettings          per-player key settings
    nz:carlock:admin:settings / admin:saveSettings          admin key settings (DB over config)
    nz:carlock:keyless { netId }                            keyless entry (fob); auto-lock is server-side
    nz:carlock:remote { netId|plate, action, on? }          fob: remote engine / windows
    nz:carlock:pin / setPin / immobiliser                   Ghost PIN, immobiliser info
    nz:carlock:ground:list|drop|throw|catch|inspect|pickup|release, nz:carlock:inspect   keys on the ground
  nz:carlock:share follows the key mode: flexible = a copy, limited = your item, virtual = access.
  Every callback is rate limited and works on server-side entities, positions and plates.

  Key item use (registered in bridge/server/listeners.lua): NZ.CarLock.useKeyItem toggles the
  lock of that key's vehicle when it is within range ('nz:client:carlock:used' plays the fob).

  Admin command Config.CarLock.commands.giveKey (/givekey [id]): a temporary key of the
  vehicle that player (default: you) sits in. NZ.Access.isAdmin or Config.CarLock.adminGroups.
]]

local CarLock = NZ.CarLock
local Utils = NZ.Utils

local MAX_CANDIDATES = 8
local RATE = {
  lock = 350, engine = 300, hasKey = 120, keys = 1000, share = 1000, revoke = 500,
  holders = 500, compat = 400, item = 600, command = 1000,
  keyless = 400, settings = 500, saveSettings = 1500, adminSettings = 300, remote = 700, pin = 900,
  setPin = 1500, immobiliser = 300, ground = 400, groundList = 2000, inspect = 300,
}

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function cfg() return CarLock.cfg() end

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

local function notify(src, message, kind)
  if type(NZ.Bridge.notify) == 'function' then
    pcall(NZ.Bridge.notify, src, message, kind)
  end
end

local function log(event, src, data)
  if type(NZ.Logs.add) ~= 'function' then return end
  local ok, err = pcall(NZ.Logs.add, event, src, data)
  if not ok then lib.print.warn(('carlock: log "%s" failed: %s'):format(event, tostring(err))) end
end

local function identifierOf(src)
  if type(NZ.Bridge.getIdentifier) ~= 'function' then return nil end
  local ok, id = pcall(NZ.Bridge.getIdentifier, src)
  if ok and type(id) == 'string' and id ~= '' then return id end
  return nil
end

--- Rate limit of `bucket` (RATE ms); `key` names a finer bucket with the same interval.
local function limited(src, bucket, key)
  return not NZ.Access.rateLimit(src, 'carlock:' .. (key or bucket), RATE[bucket] or 500)
end

local function pedOf(src)
  local ped = GetPlayerPed(tostring(src))
  if not ped or ped == 0 then return nil end
  return ped
end

local function netIdOf(entity)
  local ok, id = pcall(NetworkGetNetworkIdFromEntity, entity)
  return ok and id or nil
end

local function classArg(value)
  local class = tonumber(value)
  if not class or class ~= math.floor(class) or class < 0 or class > 22 then return nil end
  return math.tointeger(class)
end

--- Lock / unlock with feedback for everyone nearby. Returns the new state.
local function toggle(entity)
  local locked = not CarLock.isLocked(entity)
  CarLock.setLocked(entity, locked, true)
  return locked
end

--- May the driver start this engine? -> allowed, kind ('temp'|'item'|'virtual'|'owner'|'job'|'bypass')
--- The ignition runs on the client anyway (nothing is granted here), so the class the driver's
--- client reports is used for the bypass classes.
local function ignitionAllowed(src, entity, reportedClass)
  local class = reportedClass or CarLock.classOf(entity)
  if CarLock.ignitionBypass(GetEntityModel(entity), class) then return true, 'bypass' end
  local plate = CarLock.realPlate(entity)
  if not plate then return false, nil end
  local has, kind = CarLock.hasKey(src, plate)
  if not has and CarLock.jobBypass(src, plate) then has, kind = true, 'job' end
  if not has then return false, nil end
  -- Ghost immobiliser: the PIN first, even with the keys (nz:carlock:pin)
  if CarLock.pinRequired(src, plate) then return false, 'pin' end
  return true, kind
end

--- The Ghost PIN state a client needs to ask for it: { required, cooldown, plate }.
local function pinInfo(src, plate)
  return { required = true, cooldown = CarLock.pinCooldown(plate), plate = plate }
end

---------------------------------------------------------------------------------------
-- Toggle lock / engine / key checks
---------------------------------------------------------------------------------------

local lastLocked = {}            -- [src] = entity this player locked / unlocked last (lockPrefer 'last')

--- Candidate vehicles of a lock request: the vehicle the player sits in (always alone),
--- else the requested net ids sorted by their SERVER distance.
local function lockCandidates(src, payload)
  local ped = pedOf(src)
  if not ped then return {} end
  local current = GetVehiclePedIsIn(ped, false)
  if current and current ~= 0 and DoesEntityExist(current) then
    local entity, dist, inside = CarLock.vehicleFromNet(src, netIdOf(current))
    if entity then return { { entity = entity, dist = dist, inside = inside } } end
    return {}
  end
  local ids = {}
  if payload.netId ~= nil then ids[1] = payload.netId end
  if type(payload.netIds) == 'table' then
    for i = 1, math.min(#payload.netIds, MAX_CANDIDATES) do ids[#ids + 1] = payload.netIds[i] end
  end
  local seen, out = {}, {}
  for i = 1, math.min(#ids, MAX_CANDIDATES) do
    local entity, dist, inside = CarLock.vehicleFromNet(src, ids[i])
    if entity and not seen[entity] then
      seen[entity] = true
      out[#out + 1] = { entity = entity, dist = dist, inside = inside }
    end
  end
  table.sort(out, function(a, b) return a.dist < b.dist end)
  -- Config.CarLock.lockPrefer: 'owned' = the player's own vehicles first, 'last' = the
  -- vehicle this player locked / unlocked last first (both: then the nearest)
  local prefer = cfg().lockPrefer
  if prefer == 'owned' and #out > 1 then
    local own, other = {}, {}
    for _, c in ipairs(out) do
      local plate = CarLock.realPlate(c.entity)
      if plate and CarLock.isOwner(src, plate) then own[#own + 1] = c else other[#other + 1] = c end
    end
    for _, c in ipairs(other) do own[#own + 1] = c end
    out = own
  elseif prefer == 'last' and #out > 1 and lastLocked[src] then
    for i, c in ipairs(out) do
      if c.entity == lastLocked[src] then
        table.remove(out, i)
        table.insert(out, 1, c)
        break
      end
    end
  end
  return out
end

lib.callback.register('nz:carlock:toggleLock', Utils.safe(function(source, payload)
  local src = validSrc(source)
  if not src or type(payload) ~= 'table' then return Utils.fail(L('Invalid request')) end
  if not CarLock.enabled() then return Utils.fail(L('Vehicle keys are handled by another script')) end
  if limited(src, 'lock') then return Utils.fail(L('Please wait a moment')) end
  local candidates = lockCandidates(src, payload)
  if #candidates == 0 then return Utils.fail(L('No vehicle nearby')) end
  local tooFar = false
  for _, c in ipairs(candidates) do
    -- a vehicle on its way to the impound (tow truck) stays locked
    if type(NZ.Tow.isTowing) == 'function' and NZ.Tow.isTowing(c.entity) then
      return Utils.fail(L('This vehicle is being towed'))
    end
    local plate = CarLock.realPlate(c.entity)
    local has, kind = false, nil
    if plate then has, kind = CarLock.hasKey(src, plate) end
    if has then
      if c.inside or c.dist <= CarLock.lockRangeOf(c.entity) then
        local locked = toggle(c.entity)
        lastLocked[src] = c.entity
        return Utils.ok({ netId = netIdOf(c.entity), plate = plate, locked = locked, kind = kind })
      end
      tooFar = true
    end
  end
  if tooFar then return Utils.fail(L('The vehicle is too far away')) end
  if #candidates == 1 and candidates[1].inside then
    return Utils.fail(L('You do not have the keys of this vehicle'))
  end
  return Utils.fail(L('You do not have the keys of a vehicle nearby'))
end))

lib.callback.register('nz:carlock:engine', Utils.safe(function(source, payload)
  local src = validSrc(source)
  if not src or type(payload) ~= 'table' then return Utils.fail(L('Invalid request')) end
  if limited(src, 'engine') then return Utils.fail(L('Please wait a moment')) end
  local entity, _, inside = CarLock.vehicleFromNet(src, payload.netId)
  if not entity or not inside then return Utils.fail(L('You are not in a vehicle')) end
  if GetPedInVehicleSeat(entity, -1) ~= pedOf(src) then return Utils.fail(L('You are not in the driver seat')) end
  local class = classArg(payload.class)
  if class then CarLock.learnClass(src, entity, class) end
  if payload.on ~= true then return Utils.ok({ on = false }) end
  local allowed, kind = ignitionAllowed(src, entity, class)
  if not allowed and kind == 'pin' then
    return Utils.ok({ on = false, pin = pinInfo(src, CarLock.realPlate(entity)) })
  end
  if not allowed then return Utils.fail(L('You do not have the keys of this vehicle')) end
  return Utils.ok({ on = true, kind = kind })
end))

lib.callback.register('nz:carlock:hasKey', Utils.safe(function(source, payload)
  local src = validSrc(source)
  if not src or type(payload) ~= 'table' then return Utils.fail(L('Invalid request')) end
  if limited(src, 'hasKey') then return Utils.fail(L('Please wait a moment')) end
  if payload.netId ~= nil then
    local entity, _, inside = CarLock.vehicleFromNet(src, payload.netId)
    if not entity then return Utils.fail(L('Vehicle not found')) end
    local class = classArg(payload.class)
    if class and inside then CarLock.learnClass(src, entity, class) end
    local plate = CarLock.realPlate(entity)
    if not plate then return Utils.ok({ plate = nil, has = false, ignition = false, locked = CarLock.isLocked(entity) }) end
    local has, kind = CarLock.hasKey(src, plate)
    local ignition, why = ignitionAllowed(src, entity, class)
    return Utils.ok({ plate = plate, has = has, kind = kind, ignition = ignition == true, locked = CarLock.isLocked(entity),
      pin = why == 'pin' and inside and pinInfo(src, plate) or nil })
  end
  local plate = normPlate(payload.plate)
  if not plate then return Utils.fail(L('Invalid plate')) end
  local has, kind = CarLock.hasKey(src, plate)
  return Utils.ok({ plate = plate, has = has, kind = kind })
end))

---------------------------------------------------------------------------------------
-- Key management (Keys app)
---------------------------------------------------------------------------------------

lib.callback.register('nz:carlock:keys', Utils.safe(function(source)
  local src = validSrc(source)
  if not src then return Utils.fail(L('Invalid request')) end
  if limited(src, 'keys') then return Utils.fail(L('Please wait a moment')) end
  return Utils.ok({ mode = CarLock.mode(), keys = CarLock.keysOf(src) })
end))

lib.callback.register('nz:carlock:share', Utils.safe(function(source, payload)
  local src = validSrc(source)
  if not src or type(payload) ~= 'table' then return Utils.fail(L('Invalid request')) end
  if limited(src, 'share') then return Utils.fail(L('Please wait a moment')) end
  local plate = normPlate(payload.plate)
  local target = validSrc(payload.target)
  if not plate or not target then return Utils.fail(L('Invalid request')) end
  if target == src then return Utils.fail(L('You already have this key')) end
  local ped, targetPed = pedOf(src), pedOf(target)
  if not ped or not targetPed or GetPlayerRoutingBucket(tostring(src)) ~= GetPlayerRoutingBucket(tostring(target))
    or #(GetEntityCoords(ped) - GetEntityCoords(targetPed)) > CarLock.range('give') then
    return Utils.fail(L('That player is too far away'))
  end
  -- flexible: a copy (you keep yours); limited: your key item; virtual: access (docs §1)
  local ok, err, how = CarLock.shareKey(src, target, plate)
  if not ok then return Utils.fail(err or L('Something went wrong')) end
  if CarLock.playerSettings(target).alertShare ~= false then
    notify(target, L('You received the key of {plate}', { plate = plate }), 'success')
  end
  return Utils.ok({ how = how })
end))

lib.callback.register('nz:carlock:revoke', Utils.safe(function(source, payload)
  local src = validSrc(source)
  if not src or type(payload) ~= 'table' then return Utils.fail(L('Invalid request')) end
  -- takes a raw identifier: staff only. Owners use nz:carlock:keyRevoke (opaque holder ids).
  if not NZ.Access.isAdmin(src) then return Utils.fail(L('Invalid request')) end
  if limited(src, 'revoke') then return Utils.fail(L('Please wait a moment')) end
  local plate = normPlate(payload.plate)
  local identifier = type(payload.identifier) == 'string' and #payload.identifier <= 64 and payload.identifier or nil
  if not plate or not identifier then return Utils.fail(L('Invalid request')) end
  local ok, err = CarLock.revokeVirtual(src, identifier, plate)
  if not ok then return Utils.fail(err or L('Something went wrong')) end
  return Utils.ok(nil)
end))

lib.callback.register('nz:carlock:holders', Utils.safe(function(source, payload)
  local src = validSrc(source)
  if not src or type(payload) ~= 'table' then return Utils.fail(L('Invalid request')) end
  if limited(src, 'holders') then return Utils.fail(L('Please wait a moment')) end
  local plate = normPlate(payload.plate)
  if not plate then return Utils.fail(L('Invalid request')) end
  if not CarLock.isOwner(src, plate) and not NZ.Access.isAdmin(src) then
    return Utils.fail(L('Only the owner can manage the keys of this vehicle'))
  end
  -- the key ring's masked list (server/carlock/tracker.lua): identifiers never leave the server
  if type(CarLock.keyHolderList) ~= 'function' then return Utils.fail(L('Something went wrong')) end
  return Utils.ok(CarLock.keyHolderList(src, plate))
end))

---------------------------------------------------------------------------------------
-- Other scripts' client events / exports (bridge/client/listeners.lua)
---------------------------------------------------------------------------------------

local COMPAT_BURST = 4          -- compat requests a player may send at once (truck + trailer, ...)
local COMPAT_REFILL_MS = 400    -- one more every 400 ms
local COMPAT_ENTITY_WAIT_MS = 2000
local compatTokens = {}         -- [src] = { tokens, at }

--- Token bucket of compat requests per player.
local function compatToken(src)
  local t = GetGameTimer()
  local b = compatTokens[src]
  if not b then
    b = { tokens = COMPAT_BURST, at = t }
    compatTokens[src] = b
  end
  local refill = (t - b.at) / COMPAT_REFILL_MS
  if refill >= 1 then
    b.tokens = math.min(COMPAT_BURST, b.tokens + math.floor(refill))
    b.at = t
  end
  if b.tokens < 1 then return false end
  b.tokens = b.tokens - 1
  return true
end

AddEventHandler('playerDropped', function()
  local src = tonumber(source)
  if src then
    src = math.tointeger(src) or src
    compatTokens[src], lastLocked[src] = nil, nil
  end
end)

--- Vehicle of a compat request: netId first (scripts fire their events right after spawning:
--- the vehicle may reach the server a moment later), else the nearest vehicle wearing that plate.
local function compatVehicle(src, payload)
  if payload.netId ~= nil then
    local entity, dist, inside = CarLock.vehicleFromNet(src, payload.netId)
    if not entity and coroutine.isyieldable() then
      local deadline = GetGameTimer() + COMPAT_ENTITY_WAIT_MS
      while not entity and GetGameTimer() < deadline do
        Wait(50)
        entity, dist, inside = CarLock.vehicleFromNet(src, payload.netId)
      end
    end
    if entity then return entity, dist, inside end
  end
  local plate = type(payload.plate) == 'string' and CarLock.plateFromText(payload.plate, src) or nil
  if not plate then return nil end
  local entity, dist = CarLock.findVehicle(plate, src)
  if not entity then return nil end
  local ped = pedOf(src)
  local inside = ped ~= nil and GetVehiclePedIsIn(ped, false) == entity
  return entity, inside and 0.0 or dist, inside
end

--- A request from another script's CLIENT side (client events / exports, mapped by
--- bridge/client/listeners.lua, or their server net events, bridge/server/listeners.lua).
--- payload = { action = 'acquire'|'remove'|'lend', netId?, plate?, target?, export? }
--- opts = { noRate = true } (one rate-limit check for a batch). Returns a callback result.
---@param src number
---@param payload table
---@param opts table|nil
---@return table result
function CarLock.compatRequest(src, payload, opts)
  src = validSrc(src)
  if not src or type(payload) ~= 'table' then return Utils.fail(L('Invalid request')) end
  if not CarLock.enabled() then return Utils.ok(false) end
  if not (type(opts) == 'table' and opts.noRate) and not compatToken(src) then
    return Utils.fail(L('Please wait a moment'))
  end
  local action = payload.action

  if action == 'acquire' then
    if payload.export == true then
      -- this resource's own client export GiveKey: works without compat, unless closed
      if cfg().clientGiveKeyExport == false then return Utils.ok(false) end
    elseif not CarLock.compatEnabled() then
      return Utils.ok(false)
    end
    local entity, dist, inside = compatVehicle(src, payload)
    if not entity then return Utils.fail(L('Vehicle not found')) end
    -- per vehicle: the same vehicle at most every 400 ms (other vehicles are not held back)
    if limited(src, 'compat', 'compat:' .. tostring(entity)) then return Utils.fail(L('Please wait a moment')) end
    local allowed, plate, err, viaAccess = CarLock.canAcquire(src, entity, dist, inside)
    if not allowed then
      Utils.debug(('carlock: compat key refused for %s (%s)'):format(tostring(plate), tostring(err)))
      return Utils.fail(err)
    end
    if CarLock.hasKey(src, plate) then return Utils.ok(true) end
    -- a key allowed through a share / fleet access ends with that access
    return Utils.ok(CarLock.grantTemp(src, plate, payload.export == true and 'export' or 'compat', nil, viaAccess == true))

  elseif action == 'remove' then
    local plate = nil
    if payload.netId ~= nil then
      local entity = CarLock.vehicleFromNet(src, payload.netId)
      plate = entity and CarLock.realPlate(entity) or nil
    end
    plate = plate or (type(payload.plate) == 'string' and #payload.plate <= 16 and CarLock.plateFromText(payload.plate, src)) or nil
    if not plate then return Utils.fail(L('Invalid plate')) end
    return Utils.ok(CarLock.revokeTemp(src, plate))

  elseif action == 'lend' then
    -- qb-vehiclekeys GiveKeys: a temporary key for a nearby player, from someone holding a key
    if not CarLock.compatEnabled() then return Utils.ok(false) end
    local target = validSrc(payload.target)
    if not target or target == src then return Utils.fail(L('Invalid request')) end
    local entity, dist, inside = compatVehicle(src, payload)
    if not entity or (not inside and dist > CarLock.range('compat')) then return Utils.fail(L('Vehicle not found')) end
    local plate = CarLock.realPlate(entity)
    local has, kind = false, nil
    if plate then has, kind = CarLock.hasKey(src, plate) end
    if not has then return Utils.fail(L('You do not have the keys of this vehicle')) end
    -- a temporary key (hotwire, robbery, other scripts, garage hand-out) never makes more keys
    if kind == 'temp' then return Utils.fail(L('You cannot lend a temporary key')) end
    local ped, targetPed = pedOf(src), pedOf(target)
    if not ped or not targetPed or GetPlayerRoutingBucket(tostring(src)) ~= GetPlayerRoutingBucket(tostring(target))
      or #(GetEntityCoords(ped) - GetEntityCoords(targetPed)) > math.max(CarLock.range('give'), 5.0) then
      return Utils.fail(L('That player is too far away'))
    end
    if CarLock.mode() == 'physical' then
      -- keys are items here: a key item is handed over, an owner may lend a temporary key
      if kind == 'item' then
        local ok, err = CarLock.handOverKeyItem(src, target, plate)
        if not ok then return Utils.fail(err or L('Something went wrong')) end
        notify(target, L('You received the key of {plate}', { plate = plate }), 'success')
        return Utils.ok(true)
      end
      if kind ~= 'owner' then return Utils.fail(L('Hand over the key item instead')) end
    end
    CarLock.grantTemp(target, plate, 'compat')
    notify(target, L('You received the key of {plate}', { plate = plate }), 'success')
    log('vehicle.keyLend', src, { plate = plate, target = identifierOf(target) })
    return Utils.ok(true)
  end
  return Utils.fail(L('Invalid request'))
end

lib.callback.register('nz:carlock:compat', Utils.safe(function(source, payload)
  return CarLock.compatRequest(source, payload)
end))

---------------------------------------------------------------------------------------
-- Key item use (registered by bridge/server/listeners.lua)
---------------------------------------------------------------------------------------

--- A player used a key / fob item: toggle the lock of its vehicle when it is in range.
---@param src number
---@param item string
---@param slot number|nil
---@param metadata table
---@return boolean toggled
function CarLock.useKeyItem(src, item, slot, metadata)
  src = validSrc(src)
  local kind = CarLock.keyKindOfItem(item)
  if not src or not kind or not CarLock.enabled() then return false end
  if limited(src, 'item') then return false end
  if CarLock.mode() ~= 'physical' then
    notify(src, L('Key items are not used on this server'), 'error')
    return false
  end
  local valid, reason = CarLock.verifyKeyItem(metadata)
  if not valid then
    notify(src, reason == 'version' and L('This key no longer fits: the locks were changed') or L('This key does not work'), 'error')
    return false
  end
  local plate = normPlate(metadata.plate)
  local entity, dist = CarLock.findVehicle(plate, src)
  if not entity then
    -- a fob out of range opens the key ring on that vehicle (locate / alarm through the tracker)
    if kind == 'fob' and type(CarLock.openKeyRing) == 'function' then return CarLock.openKeyRing(src, plate) end
    notify(src, L('The vehicle of this key is not nearby'), 'error')
    return false
  end
  local ped = pedOf(src)
  local inside = ped ~= nil and GetVehiclePedIsIn(ped, false) == entity
  if not inside and (dist or math.huge) > CarLock.lockRangeOf(entity, kind == 'fob') then
    if kind == 'fob' and type(CarLock.openKeyRing) == 'function' then return CarLock.openKeyRing(src, plate) end
    notify(src, L('The vehicle is too far away'), 'error')
    return false
  end
  local locked = toggle(entity)
  TriggerClientEvent('nz:client:carlock:used', src, { netId = netIdOf(entity), plate = plate, locked = locked, kind = kind })
  return true
end

---------------------------------------------------------------------------------------
-- Admin command: /givekey [playerId]
---------------------------------------------------------------------------------------

--- Admin of the car lock: NZ.Access.isAdmin or a framework group of Config.CarLock.adminGroups.
---@param src number
---@return boolean
function CarLock.isAdmin(src)
  if NZ.Access.isAdmin(src) then return true end
  local groups = cfg().adminGroups
  local fw = NZ.Bridge._fw
  if type(groups) ~= 'table' or next(groups) == nil or type(fw) ~= 'table' or type(fw.hasAnyGroup) ~= 'function' then
    return false
  end
  local ok, res = pcall(fw.hasAnyGroup, src, groups)
  return ok and res == true
end

local function reply(src, message, kind)
  if src == 0 then
    lib.print.info(('[nayzeee-garages] %s'):format(message))
  else
    notify(src, message, kind)
  end
end

local commands = type(cfg().commands) == 'table' and cfg().commands or {}
local giveKeyCommand = commands.giveKey

if CarLock.enabled() and type(giveKeyCommand) == 'string' and giveKeyCommand ~= '' then
  RegisterCommand(giveKeyCommand, function(source, args)
    local src = tonumber(source) or 0
    if src > 0 then
      if not NZ.Access.rateLimit(src, 'carlock:command', RATE.command) then return end
      if not CarLock.isAdmin(src) then
        reply(src, L('You are not allowed to do that'), 'error')
        log('security.adminCommand', src, { command = giveKeyCommand })
        return
      end
    end
    -- another key resource took over while the server booted (shared/carlock.lua)
    if not CarLock.enabled() then return reply(src, L('Vehicle keys are handled by another script'), 'error') end
    local target = src
    if type(args) == 'table' and args[1] ~= nil then target = tonumber(args[1]) or -1 end
    if target == 0 then
      return reply(src, L('Usage: /{command} [player id]', { command = giveKeyCommand }))
    end
    target = validSrc(target)
    if not target then return reply(src, L('Player not found'), 'error') end
    local ped = pedOf(target)
    local vehicle = ped and GetVehiclePedIsIn(ped, false) or 0
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
      return reply(src, L('That player is not in a vehicle'), 'error')
    end
    local plate = CarLock.realPlate(vehicle)
    if not plate then return reply(src, L('Vehicle not found'), 'error') end
    if not CarLock.grantTemp(target, plate, 'admin') then return reply(src, L('Something went wrong'), 'error') end
    reply(src, L('Key of {plate} given to {name}', { plate = plate, name = GetPlayerName(tostring(target)) or tostring(target) }), 'success')
    if target ~= src then notify(target, L('You received the key of {plate}', { plate = plate }), 'success') end
    log('admin.giveKey', src > 0 and src or nil, { target = identifierOf(target), plate = plate })
  end, false)
end

---------------------------------------------------------------------------------------
-- Per-player key settings (docs/CARLOCK.md §16): nz_key_players, per character.
--   nz:carlock:playerSettings      {}             -> PlayerKeySettingsData
--   nz:carlock:savePlayerSettings  { settings }   -> PlayerKeySettingsData (partial input is
--                                  merged into the stored settings, invalid fields ignored)
--   PlayerKeySettingsData = { settings = PlayerKeySettings, defaults = PlayerKeySettings,
--     limits = { keylessMin, keylessMax }, server = { keyless, keepEngineRunning, ground } }
--   Server -> client: 'nz:client:carlock:settings' (PlayerKeySettings) after a save.
---------------------------------------------------------------------------------------

local playerSettingsCache = {}   -- [identifier] = { settings, at }
local PLAYER_SETTINGS_TTL = 600  -- s

--- The key settings of a player (their stored values over the configured defaults).
---@param src number
---@return table PlayerKeySettings
function CarLock.playerSettings(src)
  local id = identifierOf(src)
  if not id then return CarLock.normalizePlayerSettings(nil) end
  local hit = playerSettingsCache[id]
  if hit and os.time() - hit.at < PLAYER_SETTINGS_TTL then return hit.settings end
  local stored = nil
  if NZ.DB.keyPlayers and type(NZ.DB.keyPlayers.get) == 'function' then
    local ok, res = pcall(NZ.DB.keyPlayers.get, id)
    if ok and type(res) == 'table' then stored = res end
  end
  local settings = CarLock.normalizePlayerSettings(stored)
  playerSettingsCache[id] = { settings = settings, at = os.time() }
  return settings
end

--- Save (merge) the key settings of a player. Returns ok, settings | error.
---@param src number
---@param input table
---@return boolean ok, table|string
function CarLock.savePlayerSettings(src, input)
  local id = identifierOf(src)
  if not id or type(input) ~= 'table' then return false, L('Invalid request') end
  local settings = CarLock.normalizePlayerSettings(input, CarLock.playerSettings(src))
  if not (NZ.DB.keyPlayers and NZ.DB.keyPlayers.set(id, settings)) then return false, L('Something went wrong') end
  playerSettingsCache[id] = { settings = settings, at = os.time() }
  TriggerClientEvent('nz:client:carlock:settings', src, settings)
  return true, settings
end

local function playerSettingsData(src)
  local min, max = CarLock.keylessLimits()
  local keyless = type(cfg().keyless) == 'table' and cfg().keyless or {}
  local ignition = type(cfg().ignition) == 'table' and cfg().ignition or {}
  local ground = type(cfg().ground) == 'table' and cfg().ground or {}
  return {
    settings = CarLock.playerSettings(src),
    defaults = CarLock.normalizePlayerSettings(nil),
    limits = { keylessMin = min, keylessMax = max },
    server = { keyless = keyless.enabled ~= false, keepEngineRunning = ignition.keepEngineRunning ~= false,
      ground = ground.enabled ~= false },
  }
end

lib.callback.register('nz:carlock:playerSettings', Utils.safe(function(source)
  local src = validSrc(source)
  if not src then return Utils.fail(L('Invalid request')) end
  if limited(src, 'settings') then return Utils.fail(L('Please wait a moment')) end
  return Utils.ok(playerSettingsData(src))
end))

lib.callback.register('nz:carlock:savePlayerSettings', Utils.safe(function(source, payload)
  local src = validSrc(source)
  if not src or type(payload) ~= 'table' or type(payload.settings) ~= 'table' then return Utils.fail(L('Invalid request')) end
  if limited(src, 'saveSettings') then return Utils.fail(L('Please wait a moment')) end
  local ok, res = CarLock.savePlayerSettings(src, payload.settings)
  if not ok then return Utils.fail(res) end
  return Utils.ok(playerSettingsData(src))
end))

AddEventHandler('nz:server:playerUnloaded', function(src)
  local id = identifierOf(src)
  if id then playerSettingsCache[id] = nil end
end)

---------------------------------------------------------------------------------------
-- Admin key settings (docs/CARLOCK.md §15): nz_settings 'carlock_settings' over
-- config/carlock.lua (schema: shared/carlock.lua). Applied into Config.CarLock on the server
-- and published to clients in GlobalState.nzKeySettings (live: no restart). Keybinds and
-- commands are read at start and are not part of it.
--   nz:carlock:admin:settings      {}                                -> KeySettingsData
--   nz:carlock:admin:saveSettings  { values = { [id] = value }, reset = { id, ... } }
--                                  -> KeySettingsData   (all or nothing: an invalid value
--                                     fails with "Invalid value: <label>")
--   KeySettingsData = { tabs = { { id, label } }, settings = { KeySetting } }
-- Admin only (NZ.CarLock.isAdmin). Log: admin.keySettings.
---------------------------------------------------------------------------------------

local adminValues = {}           -- stored overrides { [id] = value }
local settingsReady = false      -- the stored values were loaded (or the load gave up)
local settingsLoaded = false     -- the stored values really loaded (no database error, no timeout)
local settingsHooks = {}         -- functions run after every apply (sections further down)

local function publishSettings()
  CarLock.applySettings(adminValues)
  if type(CarLock.resetModeCache) == 'function' then CarLock.resetModeCache() end
  pcall(function() GlobalState.nzKeySettings = adminValues end)
  for _, hook in ipairs(settingsHooks) do
    local ok, err = pcall(hook)
    if not ok then lib.print.warn(('[nayzeee-garages] carlock: settings hook: %s'):format(tostring(err))) end
  end
end

--- The stored admin values (copy).
---@return table
function CarLock.adminSettings()
  local out = {}
  for k, v in pairs(adminValues) do out[k] = v end
  return out
end

--- Store and apply admin values (server code / the admin UI). values: { [id] = value };
--- reset: ids that go back to the config file. Returns ok, error (translated).
---@param values table|nil
---@param reset table|nil
---@param by number|nil
---@return boolean ok, string|nil error
function CarLock.saveAdminSettings(values, reset, by)
  local nextValues = CarLock.adminSettings()
  local known = {}
  for _, id in ipairs(CarLock.settingIds()) do known[id] = true end
  for _, id in ipairs(type(reset) == 'table' and reset or {}) do
    if type(id) == 'string' and known[id] then nextValues[id] = nil end
  end
  local changed = {}
  for id, value in pairs(type(values) == 'table' and values or {}) do
    if type(id) ~= 'string' or not known[id] then return false, L('Unknown setting') end
    local ok, v = CarLock.validateSetting(id, value)
    if not ok then
      local label = id
      for _, entry in ipairs(CarLock.settingsSchema(adminValues).settings) do
        if entry.id == id then label = entry.label break end
      end
      return false, L('Invalid value: {setting}', { setting = label })
    end
    nextValues[id] = v
    changed[#changed + 1] = id
  end
  if not (NZ.DB.keySettings and NZ.DB.keySettings.save(nextValues)) then return false, L('Something went wrong') end
  adminValues = nextValues
  publishSettings()
  log('admin.keySettings', by, { changed = changed, reset = reset })
  return true, nil
end

CreateThread(function()
  local deadline = GetGameTimer() + 120000
  while not NZ.Ready and GetGameTimer() < deadline do Wait(500) end
  local stored = nil
  if NZ.DB.keySettings and type(NZ.DB.keySettings.load) == 'function' then
    local ok, res = pcall(NZ.DB.keySettings.load)
    if ok and type(res) == 'table' then stored = res end
  end
  if stored then
    local clean = {}
    for _, id in ipairs(CarLock.settingIds()) do
      if stored[id] ~= nil then
        local ok, v = CarLock.validateSetting(id, stored[id])
        if ok then clean[id] = v end
      end
    end
    adminValues = clean
    settingsLoaded = true
  else
    lib.print.warn('[nayzeee-garages] carlock: the admin key settings could not be loaded, the config values are used')
  end
  publishSettings()
  settingsReady = true
end)

lib.callback.register('nz:carlock:admin:settings', Utils.safe(function(source)
  local src = validSrc(source)
  if not src then return Utils.fail(L('Invalid request')) end
  if not CarLock.isAdmin(src) then return Utils.fail(L('You are not allowed to do that')) end
  if limited(src, 'adminSettings') then return Utils.fail(L('Please wait a moment')) end
  return Utils.ok(CarLock.settingsSchema(adminValues))
end))

lib.callback.register('nz:carlock:admin:saveSettings', Utils.safe(function(source, payload)
  local src = validSrc(source)
  if not src or type(payload) ~= 'table' then return Utils.fail(L('Invalid request')) end
  if not CarLock.isAdmin(src) then
    log('security.adminCommand', src, { command = 'keySettings' })
    return Utils.fail(L('You are not allowed to do that'))
  end
  if limited(src, 'adminSettings') then return Utils.fail(L('Please wait a moment')) end
  local ok, err = CarLock.saveAdminSettings(payload.values, payload.reset, src)
  if not ok then return Utils.fail(err) end
  return Utils.ok(CarLock.settingsSchema(adminValues))
end))

---------------------------------------------------------------------------------------
-- Keyless entry / exit (docs/CARLOCK.md §3): FOB keys only.
--   nz:carlock:keyless { netId } -> { netId, plate, locked = false }   the client asks while
--     the player tries to enter a locked vehicle: within keyless.enterRange of the SERVER
--     ped, a fob of that vehicle on them, keyless on (admin) and keylessUnlock on (player).
-- Auto-lock runs on the server: once a second it looks at every player's vehicle (server
-- side); a player who left a vehicle they have a fob for (or unlocked it by keyless entry)
-- is watched, and when they are farther than their keylessDistance with nobody inside and
-- the doors unlocked, the server locks it (with the lock feedback).
---------------------------------------------------------------------------------------

local keylessWatch = {}         -- [src] = { [entity] = { plate, since } } vehicles waiting for the auto-lock
local lastSeat = {}             -- [src] = vehicle the player sat in at the last tick
local KEYLESS_GIVE_UP = 250.0   -- m: stop watching beyond this
local MAX_SEATS = 16

local function keylessCfg()
  local k = cfg().keyless
  return type(k) == 'table' and k or {}
end

--- Does the player have a FOB of this vehicle on them (or a fob-kind key without items)?
---@param src number
---@param entity number
---@param plate string
---@return boolean
function CarLock.hasFob(src, entity, plate)
  if CarLock.mode() == 'physical' then
    for _, e in ipairs(CarLock.keyItemsOf(src, plate)) do
      if type(e.metadata) == 'table' and e.metadata.kind == 'fob' then return true end
    end
  end
  local has, kind = CarLock.hasKey(src, plate)
  if not has or kind == 'item' then return false end
  local _, profile = CarLock.profileOfEntity(entity)
  if CarLock.keyKindOf(profile) ~= 'fob' then return false end
  if kind == 'temp' then
    local t = CarLock.tempKeyOf(src, plate)
    -- a service's temporary key (garage hand-out in virtual mode, spawner...) is a fob; a crime's is not
    return t ~= nil and type(CarLock.isServiceKey) == 'function' and CarLock.isServiceKey(t.reason)
  end
  return true
end

local function occupied(entity)
  for seat = -1, MAX_SEATS - 2 do
    local ped = GetPedInVehicleSeat(entity, seat)
    if ped and ped ~= 0 then return true end
  end
  return false
end

local function arm(src, entity, plate)
  local list = keylessWatch[src] or {}
  keylessWatch[src] = list
  list[entity] = { plate = plate, since = os.time() }
end

local function disarm(src, entity)
  local list = keylessWatch[src]
  if not list then return end
  list[entity] = nil
  if next(list) == nil then keylessWatch[src] = nil end
end

lib.callback.register('nz:carlock:keyless', Utils.safe(function(source, payload)
  local src = validSrc(source)
  if not src or type(payload) ~= 'table' then return Utils.fail(L('Invalid request')) end
  if not CarLock.enabled() or keylessCfg().enabled == false then return Utils.fail(L('Keyless entry is off')) end
  if limited(src, 'keyless') then return Utils.fail(L('Please wait a moment')) end
  if CarLock.playerSettings(src).keylessUnlock == false then return Utils.fail(L('Keyless entry is off')) end
  local entity, dist, inside = CarLock.vehicleFromNet(src, payload.netId)
  if not entity then return Utils.fail(L('Vehicle not found')) end
  local plate = CarLock.realPlate(entity)
  if not plate then return Utils.fail(L('Vehicle not found')) end
  if type(NZ.Tow.isTowing) == 'function' and NZ.Tow.isTowing(entity) then return Utils.fail(L('This vehicle is being towed')) end
  local range = Utils.clamp(tonumber(keylessCfg().enterRange) or 3.5, 1.5, 8.0)
  if not inside and dist > range then return Utils.fail(L('You are too far from the vehicle')) end
  if not CarLock.hasFob(src, entity, plate) then return Utils.fail(L('You do not have a fob for this vehicle')) end
  if CarLock.isLocked(entity) then CarLock.setLocked(entity, false, true) end
  arm(src, entity, plate)
  return Utils.ok({ netId = netIdOf(entity), plate = plate, locked = false })
end))

local function keylessTick()
  if not CarLock.enabled() or keylessCfg().enabled == false then
    keylessWatch, lastSeat = {}, {}
    return
  end
  local min, max = CarLock.keylessLimits()
  for _, id in ipairs(GetPlayers() or {}) do
    local src = math.tointeger(tonumber(id))
    local ped = src and pedOf(src) or nil
    if ped then
      local veh = GetVehiclePedIsIn(ped, false)
      local inside = veh and veh ~= 0 and DoesEntityExist(veh) and veh or nil
      local left = lastSeat[src]
      lastSeat[src] = inside
      if left and left ~= inside and DoesEntityExist(left) then
        -- just got out of (or switched from) a vehicle: watch it when it is a fob vehicle
        local plate = CarLock.realPlate(left)
        if plate and CarLock.playerSettings(src).keylessLock ~= false and CarLock.hasFob(src, left, plate) then
          arm(src, left, plate)
        end
      end
      if inside then disarm(src, inside) end
      for entity, watch in pairs(keylessWatch[src] or {}) do
        if not DoesEntityExist(entity) then
          disarm(src, entity)
        elseif GetEntityRoutingBucket(entity) ~= GetPlayerRoutingBucket(tostring(src)) then
          -- walked into an interior / instance right after parking: clearly away, lock it
          disarm(src, entity)
          local settings = CarLock.playerSettings(src)
          if settings.keylessLock ~= false and not CarLock.isLocked(entity) and not occupied(entity)
            and not (type(NZ.Tow.isTowing) == 'function' and NZ.Tow.isTowing(entity))
            and CarLock.hasFob(src, entity, watch.plate) then
            CarLock.setLocked(entity, true, true)
            if settings.alertLock ~= false then notify(src, L('{plate} locked behind you', { plate = watch.plate }), 'info') end
          end
        else
          local settings = CarLock.playerSettings(src)
          local dist = #(GetEntityCoords(ped) - GetEntityCoords(entity))
          local want = Utils.clamp(tonumber(settings.keylessDistance) or 10.0, min, max)
          if settings.keylessLock == false or dist > KEYLESS_GIVE_UP or CarLock.isLocked(entity) then
            disarm(src, entity)
          elseif dist > want and not occupied(entity)
            and not (type(NZ.Tow.isTowing) == 'function' and NZ.Tow.isTowing(entity)) then
            disarm(src, entity)
            if CarLock.hasFob(src, entity, watch.plate) then
              CarLock.setLocked(entity, true, true)
              if settings.alertLock ~= false then notify(src, L('{plate} locked behind you', { plate = watch.plate }), 'info') end
            end
          end
        end
      end
    end
  end
end

CreateThread(function()
  while true do
    Wait(1000)
    local ok, err = pcall(keylessTick)
    if not ok then lib.print.warn(('[nayzeee-garages] carlock: keyless: %s'):format(tostring(err))) end
  end
end)

AddEventHandler('playerDropped', function()
  local src = tonumber(source)
  if src then
    src = math.tointeger(src) or src
    keylessWatch[src], lastSeat[src] = nil, nil
  end
end)

---------------------------------------------------------------------------------------
-- Remote actions of a fob (key ring: hold = engine, keep holding = windows)
--   nz:carlock:remote { netId? | plate?, action = 'engine'|'windows', on? } -> { action, on }
--   fob keys only, within the fob range (server ped) or inside; remote start is refused by a
--   Ghost immobiliser and needs an engine the key may start. The entity owner's client runs
--   it ('nz:client:carlock:remote').
---------------------------------------------------------------------------------------

lib.callback.register('nz:carlock:remote', Utils.safe(function(source, payload)
  local src = validSrc(source)
  if not src or type(payload) ~= 'table' then return Utils.fail(L('Invalid request')) end
  if not CarLock.enabled() then return Utils.fail(L('Vehicle keys are handled by another script')) end
  if limited(src, 'remote') then return Utils.fail(L('Please wait a moment')) end
  local action = payload.action
  if action ~= 'engine' and action ~= 'windows' then return Utils.fail(L('Invalid request')) end
  local entity, dist, inside
  if payload.netId ~= nil then
    entity, dist, inside = CarLock.vehicleFromNet(src, payload.netId)
  else
    local plate = normPlate(payload.plate)
    if plate then
      entity, dist = CarLock.findVehicle(plate, src)
      local ped = pedOf(src)
      inside = entity ~= nil and ped ~= nil and GetVehiclePedIsIn(ped, false) == entity
    end
  end
  if not entity then return Utils.fail(L('The vehicle of this key is not nearby')) end
  local plate = CarLock.realPlate(entity)
  if not plate or not CarLock.hasFob(src, entity, plate) then return Utils.fail(L('You need the fob of this vehicle')) end
  if not inside and (dist or math.huge) > CarLock.range('fob') then return Utils.fail(L('The vehicle is too far away')) end
  if type(NZ.Tow.isTowing) == 'function' and NZ.Tow.isTowing(entity) then return Utils.fail(L('This vehicle is being towed')) end
  local on = payload.on ~= false
  if action == 'engine' and on then
    if CarLock.immobiliserOf(plate) == 'ghost' then return Utils.fail(L('Remote start is disabled by the immobiliser')) end
    local driver = GetPedInVehicleSeat(entity, -1)
    if driver and driver ~= 0 and driver ~= pedOf(src) then return Utils.fail(L('Someone is sitting in this vehicle')) end
  end
  local okOwner, owner = pcall(NetworkGetEntityOwner, entity)
  owner = okOwner and validSrc(owner) or nil
  if not owner then return Utils.fail(L('The vehicle is too far away')) end
  TriggerClientEvent('nz:client:carlock:remote', owner, { netId = netIdOf(entity), action = action, on = on })
  log('vehicle.remote', src, { plate = plate, action = action, on = on })
  return Utils.ok({ action = action, on = on, netId = netIdOf(entity), plate = plate })
end))

---------------------------------------------------------------------------------------
-- Immobilisers and Ghost PINs (docs/CARLOCK.md §17)
--   nz:carlock:pin          { netId, pin }            -> { success, attemptsLeft?, cooldown?, alarm? }
--                           driver seat; a correct PIN lets that driver start the engine for
--                           immobiliser.pinSession seconds (then nz:carlock:engine as usual)
--   nz:carlock:setPin       { plate, pin, oldPin? }  -> ImmobiliserInfo   owner (old PIN when one is set)
--   nz:carlock:immobiliser  { plate }                -> ImmobiliserInfo   owner, key holder or admin
--   ImmobiliserInfo = { plate, level, pinSet, pinRequired, cooldown, remoteStart }
-- Item use (bridge/server/listeners.lua): items.immobiliser / items.ghostImmobiliser at your own
-- vehicle (driver seat, or standing within 3 m) install that level (NZ.CarLock.useImmobiliserItem).
---------------------------------------------------------------------------------------

local IMMO_RANGE = 3.0

lib.callback.register('nz:carlock:pin', Utils.safe(function(source, payload)
  local src = validSrc(source)
  if not src or type(payload) ~= 'table' then return Utils.fail(L('Invalid request')) end
  if limited(src, 'pin') then return Utils.fail(L('Please wait a moment')) end
  local entity, _, inside = CarLock.vehicleFromNet(src, payload.netId)
  if not entity or not inside or GetPedInVehicleSeat(entity, -1) ~= pedOf(src) then
    return Utils.fail(L('You are not in the driver seat'))
  end
  local plate = CarLock.realPlate(entity)
  if not plate then return Utils.fail(L('Vehicle not found')) end
  local pin = type(payload.pin) == 'string' and payload.pin or tostring(payload.pin or '')
  local ok, err, info = CarLock.enterPin(src, entity, plate, pin)
  if ok then return Utils.ok({ success = true }) end
  return Utils.ok({ success = false, error = err, attemptsLeft = info.attemptsLeft, cooldown = info.cooldown,
    alarm = info.alarm })
end))

local function immobiliserData(src, plate)
  local info = CarLock.immobiliserInfo(src, plate)
  info.plate = plate
  return info
end

lib.callback.register('nz:carlock:setPin', Utils.safe(function(source, payload)
  local src = validSrc(source)
  if not src or type(payload) ~= 'table' then return Utils.fail(L('Invalid request')) end
  if limited(src, 'setPin') then return Utils.fail(L('Please wait a moment')) end
  local plate = normPlate(payload.plate)
  if not plate then return Utils.fail(L('Invalid plate')) end
  local ok, err = CarLock.setPin(src, plate, payload.pin, payload.oldPin)
  if not ok then return Utils.fail(err) end
  return Utils.ok(immobiliserData(src, plate))
end))

lib.callback.register('nz:carlock:immobiliser', Utils.safe(function(source, payload)
  local src = validSrc(source)
  if not src or type(payload) ~= 'table' then return Utils.fail(L('Invalid request')) end
  if limited(src, 'immobiliser') then return Utils.fail(L('Please wait a moment')) end
  local plate = normPlate(payload.plate)
  if not plate then return Utils.fail(L('Invalid plate')) end
  if not CarLock.isOwner(src, plate) and not CarLock.hasKey(src, plate) and not CarLock.isAdmin(src) then
    return Utils.fail(L('You do not have the keys of this vehicle'))
  end
  return Utils.ok(immobiliserData(src, plate))
end))

--- Use an immobiliser item: installs its level on your own vehicle (driver seat, or the
--- nearest of your vehicles within 3 m). Returns true when the item was used.
---@param src number
---@param item string
---@param slot number|nil
---@return boolean
function CarLock.useImmobiliserItem(src, item, slot)
  src = validSrc(src)
  if not src or not CarLock.enabled() then return false end
  if limited(src, 'item') then return false end
  if not CarLock.immobiliserEnabled() then
    notify(src, L('Immobilisers are not used on this server'), 'error')
    return false
  end
  local level = item == CarLock.itemName('ghostImmobiliser') and 'ghost' or 'standard'
  local ped = pedOf(src)
  if not ped then return false end
  local entity = GetVehiclePedIsIn(ped, false)
  if entity == 0 or not DoesEntityExist(entity) then
    entity = nil
    local best = IMMO_RANGE
    local coords = GetEntityCoords(ped)
    local bucket = GetPlayerRoutingBucket(tostring(src))
    for _, v in ipairs(GetAllVehicles() or {}) do
      if DoesEntityExist(v) and GetEntityRoutingBucket(v) == bucket then
        local d = #(GetEntityCoords(v) - coords)
        local p = d <= best and CarLock.realPlate(v) or nil
        if p and CarLock.isOwner(src, p) then entity, best = v, d end
      end
    end
  end
  local plate = entity and CarLock.realPlate(entity) or nil
  if not plate or not CarLock.isOwner(src, plate) then
    notify(src, L('Stand at one of your vehicles'), 'error')
    return false
  end
  local current = CarLock.immobiliserOf(plate)
  if current == level or (current == 'ghost' and level == 'standard') then
    notify(src, L('This vehicle already has this immobiliser'), 'error')
    return false
  end
  if not NZ.Inventory.removeItem(src, item, 1, nil, slot) and not NZ.Inventory.removeItem(src, item, 1) then
    return false
  end
  local ok, err = CarLock.setImmobiliser(plate, level, src)
  if not ok then
    NZ.Inventory.addItem(src, item, 1)
    notify(src, err or L('Something went wrong'), 'error')
    return false
  end
  if level == 'ghost' then
    notify(src, L('Ghost immobiliser installed in {plate}: set a PIN from your key ring', { plate = plate }), 'success')
    TriggerClientEvent('nz:client:carlock:pinSetup', src, { plate = plate })
  else
    notify(src, L('Immobiliser installed in {plate}', { plate = plate }), 'success')
  end
  return true
end

---------------------------------------------------------------------------------------
-- Keys on the ground (docs/CARLOCK.md §18). The server keeps every ground key and spawns its
-- networked prop (CreateObjectNoOffset, state bag nzGroundKey = id); clients draw the marker
-- and the prompt and ask the server to act. Positions are the SERVER's (ped / vehicle / target
-- ped); a client never says where a key lands.
--   nz:carlock:ground:list     {}                          -> { GroundKeyView }   (player's bucket)
--   nz:carlock:ground:drop     { slot } | { keyId, plate }, toss?  -> { id }
--                              toss = true: out of the window of the vehicle you sit in
--   nz:carlock:ground:throw    { slot } | { keyId, plate }, target -> { id, window }
--                              to a player within ground.throwRange; they have ground.catchWindow
--                              ms to catch ('nz:client:carlock:catch'), else it lands at their feet
--   nz:carlock:ground:catch    { id }                      -> { plate, keyKind }
--   nz:carlock:ground:inspect  { id }                      -> GroundKeyInfo (held for 20 s for you)
--   nz:carlock:ground:pickup   { id }                      -> { plate, keyKind } (keep it)
--   nz:carlock:ground:release  { id }                      -> null (return to ground)
--   nz:carlock:inspect         { slot }                    -> CarriedKeyInfo (a key you carry)
--   GroundKeyView = { id, keyKind, x, y, z, netId? }
--   GroundKeyInfo = { id, plate, keyKind, label, model?, kind ('item'|'temp'), droppedAt }
--   CarriedKeyInfo = { plate, keyKind, label, model?, valid, reason?, origin?, slot }
-- Server -> client: 'nz:client:carlock:ground' { add = GroundKeyView } | { remove = id },
--   'nz:client:carlock:catch' { id, from, window, keyKind }, 'nz:client:carlock:thrown' { id, target }.
-- NPC hold-ups that end in "drop and run" put a temporary-key ground key at the driver
-- (NZ.CarLock.groundDropTemp). Keys on the ground are removed after ground.removeAfter minutes;
-- ground.persist keeps them in nz_ground_keys across a server restart (else across a resource
-- restart only, KVP snapshot).
---------------------------------------------------------------------------------------

local GROUND_KVP = 'nz:carlock:ground'
local INSPECT_HOLD = 20         -- s: an inspected key is held for the inspector
local THROW_LATENCY = 600       -- ms: allowance on the catch window
local grounds = {}              -- [id] = record
local groundCount = 0
local flights = {}              -- [id] = { item, md, plate, from, to, expires, keyKind }

local function groundCfg()
  local g = cfg().ground
  return type(g) == 'table' and g or {}
end

local function groundId()
  return ('%08x%04x'):format(math.random(0, 0x7fffffff), math.random(0, 0xffff))
end

local function headingVectors(entity)
  local h = math.rad(tonumber(GetEntityHeading(entity)) or 0.0)
  return vector3(-math.sin(h), math.cos(h), 0.0), vector3(math.cos(h), math.sin(h), 0.0)
end

local function viewOf(rec)
  return { id = rec.id, keyKind = rec.keyKind, x = rec.coords.x, y = rec.coords.y, z = rec.coords.z, netId = rec.netId }
end

local function sendToBucket(bucket, payload)
  for _, id in ipairs(GetPlayers() or {}) do
    local src = tonumber(id)
    if src and GetPlayerRoutingBucket(tostring(src)) == bucket then
      TriggerClientEvent('nz:client:carlock:ground', src, payload)
    end
  end
end

local function spawnProp(rec)
  local props = type(groundCfg().props) == 'table' and groundCfg().props or {}
  local model = rec.keyKind == 'fob' and (props.fob or 'lr_prop_carkey_fob') or (props.key or 'p_car_keys_01')
  local ok, entity = pcall(CreateObjectNoOffset, joaat(model), rec.coords.x, rec.coords.y, rec.coords.z, true, true, false)
  if not ok or type(entity) ~= 'number' or entity == 0 then return end
  pcall(SetEntityHeading, entity, rec.heading or 0.0)
  pcall(SetEntityRoutingBucket, entity, rec.bucket or 0)
  pcall(function() Entity(entity).state:set('nzGroundKey', rec.id, true) end)
  rec.entity = entity
  local okNet, netId = pcall(NetworkGetNetworkIdFromEntity, entity)
  rec.netId = okNet and netId ~= 0 and netId or nil
end

local function deleteProp(rec)
  if rec.entity and DoesEntityExist(rec.entity) then pcall(DeleteEntity, rec.entity) end
  rec.entity, rec.netId = nil, nil
end

local function persistOn() return groundCfg().persist == true end

--- Store (or move) a ground key in nz_ground_keys. Returns true when stored.
local function persistRecord(rec)
  local ok, res = pcall(NZ.DB.groundKeys.add, { id = rec.id, plate = rec.plate, data = {
    kind = rec.kind, item = rec.item, metadata = rec.metadata, reason = rec.reason, keyKind = rec.keyKind,
    droppedBy = rec.droppedBy, createdAt = rec.createdAt }, x = rec.coords.x, y = rec.coords.y, z = rec.coords.z,
    heading = rec.heading or 0.0, bucket = rec.bucket or 0, expiresAt = rec.expiresAt })
  return ok and res == true
end

--- Put a key on the ground. rec = { plate, kind = 'item'|'temp', item?, metadata?, reason?,
--- keyKind, coords (vector3), heading?, bucket, droppedBy? }. Returns the record (with id) or nil.
---@param rec table
---@return table|nil
function CarLock.groundCreate(rec)
  if type(rec) ~= 'table' or not normPlate(rec.plate) then return nil end
  -- CfxLua: type(vector3(...)) is 'vector3' (a plain table from KVP / DB also works)
  local ct = type(rec.coords)
  if (ct ~= 'table' and ct ~= 'vector3' and ct ~= 'vector4')
    or not (tonumber(rec.coords.x) and tonumber(rec.coords.y) and tonumber(rec.coords.z)) then
    return nil
  end
  local id = groundId()
  while grounds[id] do id = groundId() end
  rec.id = id
  rec.plate = normPlate(rec.plate)
  rec.keyKind = rec.keyKind == 'fob' and 'fob' or 'key'
  rec.coords = vector3(rec.coords.x + 0.0, rec.coords.y + 0.0, rec.coords.z + 0.0)
  rec.createdAt = os.time()
  rec.persisted = nil
  local minutes = tonumber(groundCfg().removeAfter) or 30
  rec.expiresAt = minutes > 0 and (rec.createdAt + math.floor(minutes * 60)) or nil
  grounds[id] = rec
  groundCount = groundCount + 1
  spawnProp(rec)
  if rec.kind == 'item' and type(rec.metadata) == 'table' then
    CarLock.moveKeyItem(rec.metadata, 'ground', 'ground:' .. id, nil)
  end
  if persistOn() and NZ.DB.groundKeys then rec.persisted = persistRecord(rec) end
  sendToBucket(rec.bucket or 0, { add = viewOf(rec) })
  log('vehicle.keyGround', nil, { plate = rec.plate, id = id, kind = rec.kind, by = rec.droppedBy })
  return rec
end

local function groundRemove(id, reason)
  local rec = grounds[id]
  if not rec then return nil end
  grounds[id] = nil
  groundCount = math.max(groundCount - 1, 0)
  deleteProp(rec)
  if rec.persisted and NZ.DB.groundKeys then NZ.DB.groundKeys.remove(id) end
  TriggerClientEvent('nz:client:carlock:ground', -1, { remove = id })
  if reason == 'expired' and rec.kind == 'item' and type(rec.metadata) == 'table' then
    CarLock.moveKeyItem(rec.metadata, 'lost', 'ground:' .. id, nil)
  end
  return rec
end

--- A temporary-key ground key (NPC "drop and run"): whoever picks it up gets a temporary key.
---@param plate string
---@param coords vector3
---@param bucket integer
---@param reason string temporary key reason ('robbery')
---@param keyKind 'key'|'fob'|nil
---@return table|nil record
function CarLock.groundDropTemp(plate, coords, bucket, reason, keyKind)
  if groundCfg().enabled == false then return nil end
  return CarLock.groundCreate({ plate = plate, kind = 'temp', reason = reason or 'robbery', keyKind = keyKind,
    coords = coords, heading = math.random(0, 359) + 0.0, bucket = bucket or 0 })
end

--- Ground keys (copies of the records) for the admin key manager: { { id, plate, kind, keyKind,
--- coords, bucket, droppedBy?, createdAt, expiresAt?, keyRef? } }.
---@param plate string|nil only this plate
---@return table[]
function CarLock.groundKeys(plate)
  plate = plate and normPlate(plate) or nil
  local out = {}
  for _, rec in pairs(grounds) do
    if not plate or rec.plate == plate then
      out[#out + 1] = { id = rec.id, plate = rec.plate, kind = rec.kind, keyKind = rec.keyKind,
        coords = { x = rec.coords.x, y = rec.coords.y, z = rec.coords.z }, bucket = rec.bucket,
        droppedBy = rec.droppedBy, createdAt = rec.createdAt, expiresAt = rec.expiresAt,
        keyRef = rec.kind == 'item' and CarLock.keyRef(rec.metadata) or nil }
    end
  end
  table.sort(out, function(a, b) return a.createdAt < b.createdAt end)
  return out
end

--- Remove a ground key (admin). Returns the removed record or nil.
---@param id string
---@return table|nil
function CarLock.groundDelete(id)
  local rec = groundRemove(id, 'admin')
  if rec and rec.kind == 'item' and type(rec.metadata) == 'table' then
    CarLock.moveKeyItem(rec.metadata, 'lost', 'ground:' .. id, nil)
  end
  return rec
end

--- A key item the player carries, from a request: slot, or key id + plate. Returns
--- { item, slot, metadata, keyKind } or nil, error.
local function carriedKey(src, payload)
  local entry = nil
  if payload.slot ~= nil then
    local slot = tonumber(payload.slot)
    if slot and slot == math.floor(slot) and slot >= 0 and slot < 10000 then entry = NZ.Inventory.getSlot(src, slot) end
    if entry and not CarLock.keyKindOfItem(entry.name) then entry = nil end
  elseif type(payload.keyId) == 'string' and #payload.keyId <= 32 then
    local plate = normPlate(payload.plate)
    for _, item in pairs(CarLock.keyItems()) do
      entry = NZ.Inventory.find(src, item, function(md)
        return type(md) == 'table' and md.id == payload.keyId and (plate == nil or Utils.plate(md.plate) == plate)
      end)[1]
      if entry then break end
    end
  end
  if not entry or type(entry.metadata) ~= 'table' or not normPlate(entry.metadata.plate) then
    return nil, L('You do not have that key')
  end
  return { item = entry.name, slot = entry.slot, metadata = entry.metadata,
    keyKind = CarLock.keyKindOfItem(entry.name) or 'key' }
end

local function takeCarried(src, key)
  local md = key.metadata
  local match = md.id and { id = md.id } or { plate = md.plate }
  return NZ.Inventory.removeItem(src, key.item, 1, match, key.slot)
end

local function droppedByCount(identifier)
  local n = 0
  for _, rec in pairs(grounds) do if rec.droppedBy == identifier then n = n + 1 end end
  return n
end

local function groundAllowed(src)
  if not CarLock.enabled() or groundCfg().enabled == false then return false, L('Keys cannot be dropped on this server') end
  if CarLock.mode() ~= 'physical' then return false, L('This server does not use key items') end
  local id = identifierOf(src)
  local max = math.floor(Utils.clamp(tonumber(groundCfg().maxPerPlayer) or 10, 1, 100))
  if id and droppedByCount(id) >= max then return false, L('You have too many keys lying around') end
  return true, nil
end

local function itemRecord(src, key, coords, heading)
  return { plate = key.metadata.plate, kind = 'item', item = key.item, metadata = key.metadata, keyKind = key.keyKind,
    coords = coords, heading = heading, bucket = GetPlayerRoutingBucket(tostring(src)), droppedBy = identifierOf(src) }
end

lib.callback.register('nz:carlock:ground:list', Utils.safe(function(source)
  local src = validSrc(source)
  if not src then return Utils.fail(L('Invalid request')) end
  if limited(src, 'groundList') then return Utils.fail(L('Please wait a moment')) end
  local bucket = GetPlayerRoutingBucket(tostring(src))
  local out = {}
  for _, rec in pairs(grounds) do
    if (rec.bucket or 0) == bucket then out[#out + 1] = viewOf(rec) end
  end
  return Utils.ok(out)
end))

lib.callback.register('nz:carlock:ground:drop', Utils.safe(function(source, payload)
  local src = validSrc(source)
  if not src or type(payload) ~= 'table' then return Utils.fail(L('Invalid request')) end
  if limited(src, 'ground') then return Utils.fail(L('Please wait a moment')) end
  local allowed, why = groundAllowed(src)
  if not allowed then return Utils.fail(why) end
  local key, err = carriedKey(src, payload)
  if not key then return Utils.fail(err) end
  local ped = pedOf(src)
  if not ped then return Utils.fail(L('Invalid request')) end
  local coords, heading
  local vehicle = GetVehiclePedIsIn(ped, false)
  if payload.toss == true then
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return Utils.fail(L('You are not in a vehicle')) end
    if GetPedInVehicleSeat(vehicle, -1) ~= ped then return Utils.fail(L('You are not in the driver seat')) end
    -- out of the driver's (left) window; bikes and quads drop it beside the rider
    local forward, right = headingVectors(vehicle)
    local class = CarLock.classOf(vehicle)
    local side = (class == 8 or class == 13) and 0.9 or 1.6
    local base = GetEntityCoords(vehicle)
    coords = base - right * side + forward * 0.3
    coords = vector3(coords.x, coords.y, base.z + 0.2)
    heading = GetEntityHeading(vehicle)
  else
    if vehicle and vehicle ~= 0 then return Utils.fail(L('Get out of the vehicle first')) end
    local forward = headingVectors(ped)
    local base = GetEntityCoords(ped)
    coords = base + forward * 0.45
    coords = vector3(coords.x, coords.y, base.z - 0.6)
    heading = GetEntityHeading(ped)
  end
  if not takeCarried(src, key) then return Utils.fail(L('You do not have that key')) end
  local rec = CarLock.groundCreate(itemRecord(src, key, coords, heading))
  if not rec then
    NZ.Inventory.addItem(src, key.item, 1, key.metadata)
    return Utils.fail(L('Something went wrong'))
  end
  TriggerClientEvent('nz:client:carlock:keys', src, { plate = rec.plate })
  return Utils.ok({ id = rec.id })
end))

local function landFlight(id)
  local f = flights[id]
  if not f or f.landing then return end
  f.landing = true -- the inventory / DB calls below may yield: land once
  -- missed: at the catcher's feet, else the thrower's, else where it was thrown from; a player
  -- only counts while in the throw's bucket and near the throw (no key landing across the map)
  local reach = Utils.clamp(tonumber(groundCfg().throwRange) or 8.0, 2.0, 20.0) + 2.0
  local function near(src)
    local p = validSrc(src) and pedOf(src) or nil
    if not p or GetPlayerRoutingBucket(tostring(src)) ~= (f.bucket or 0) then return nil end
    local c = GetEntityCoords(p)
    if #(c - f.origin) > reach then return nil end
    return c
  end
  local caught, thrower = near(f.to), near(f.from)
  local base = caught or thrower or f.origin
  local towards = thrower or base
  local dir = towards - base
  local len = #dir
  local spot = len > 0.01 and (base + dir * (0.5 / len)) or base
  local ok, rec = pcall(CarLock.groundCreate, { plate = f.plate, kind = 'item', item = f.item, metadata = f.md,
    keyKind = f.keyKind, coords = vector3(spot.x, spot.y, base.z - 0.6), heading = math.random(0, 359) + 0.0,
    bucket = f.bucket, droppedBy = f.droppedBy })
  if not (ok and rec) then
    -- could not put it on the ground: back to the thrower, else it is lost (never silently gone)
    if not ok then lib.print.warn(('[nayzeee-garages] carlock: thrown key %s: %s'):format(id, tostring(rec))) end
    local back = validSrc(f.from) and NZ.Inventory.addItem(f.from, f.item, 1, f.md, nil, true) or false
    CarLock.moveKeyItem(f.md, back and 'player' or 'lost', back and identifierOf(f.from) or ('flight:' .. id), nil)
    if back then TriggerClientEvent('nz:client:carlock:keys', f.from, { plate = f.plate }) end
  end
  flights[id] = nil
end

lib.callback.register('nz:carlock:ground:throw', Utils.safe(function(source, payload)
  local src = validSrc(source)
  if not src or type(payload) ~= 'table' then return Utils.fail(L('Invalid request')) end
  if limited(src, 'ground') then return Utils.fail(L('Please wait a moment')) end
  local allowed, why = groundAllowed(src)
  if not allowed then return Utils.fail(why) end
  local target = validSrc(payload.target)
  if not target or target == src then return Utils.fail(L('Invalid request')) end
  local ped, targetPed = pedOf(src), pedOf(target)
  local range = Utils.clamp(tonumber(groundCfg().throwRange) or 8.0, 2.0, 20.0)
  if not ped or not targetPed or GetPlayerRoutingBucket(tostring(src)) ~= GetPlayerRoutingBucket(tostring(target))
    or #(GetEntityCoords(ped) - GetEntityCoords(targetPed)) > range then
    return Utils.fail(L('That player is too far away'))
  end
  if GetVehiclePedIsIn(ped, false) ~= 0 then return Utils.fail(L('Get out of the vehicle first')) end
  local key, err = carriedKey(src, payload)
  if not key then return Utils.fail(err) end
  if not takeCarried(src, key) then return Utils.fail(L('You do not have that key')) end
  local id = groundId()
  local window = math.floor(Utils.clamp(tonumber(groundCfg().catchWindow) or 1800, 500, 5000))
  flights[id] = { item = key.item, md = key.metadata, plate = normPlate(key.metadata.plate), keyKind = key.keyKind,
    from = src, to = target, expires = GetGameTimer() + window + THROW_LATENCY, origin = GetEntityCoords(ped),
    bucket = GetPlayerRoutingBucket(tostring(src)), droppedBy = identifierOf(src) }
  CarLock.moveKeyItem(key.metadata, 'unknown', 'flight:' .. id, nil)
  TriggerClientEvent('nz:client:carlock:catch', target, { id = id, from = src, window = window, keyKind = key.keyKind })
  TriggerClientEvent('nz:client:carlock:thrown', src, { id = id, target = target })
  TriggerClientEvent('nz:client:carlock:keys', src, { plate = flights[id].plate })
  SetTimeout(window + THROW_LATENCY, function() landFlight(id) end)
  log('vehicle.keyThrow', src, { plate = flights[id].plate, target = identifierOf(target) })
  return Utils.ok({ id = id, window = window })
end))

lib.callback.register('nz:carlock:ground:catch', Utils.safe(function(source, payload)
  local src = validSrc(source)
  if not src or type(payload) ~= 'table' or type(payload.id) ~= 'string' then return Utils.fail(L('Invalid request')) end
  if limited(src, 'inspect') then return Utils.fail(L('Please wait a moment')) end
  local f = flights[payload.id]
  if not f or f.to ~= src or f.landing then return Utils.fail(L('Too late')) end
  if GetGameTimer() > f.expires then
    landFlight(payload.id)
    return Utils.fail(L('Too late'))
  end
  -- the catcher must still be there: alive, same bucket, within the throw range of the thrower
  local ped = pedOf(src)
  local range = Utils.clamp(tonumber(groundCfg().throwRange) or 8.0, 2.0, 20.0) + 2.0
  local okHp, hp = pcall(GetEntityHealth, ped or 0)
  -- GTA peds are dead at 100 health or less; framework downed states (state bag isDead) too
  local okState, dead = pcall(function() return Player(src).state.isDead end)
  if not ped or (okHp and tonumber(hp) and tonumber(hp) <= 100) or (okState and dead == true)
    or GetPlayerRoutingBucket(tostring(src)) ~= (f.bucket or 0)
    or #(GetEntityCoords(ped) - f.origin) > range then
    landFlight(payload.id)
    return Utils.fail(L('You missed the key'))
  end
  flights[payload.id] = nil
  if not NZ.Inventory.addItem(src, f.item, 1, f.md) then
    flights[payload.id] = f
    landFlight(payload.id)
    return Utils.fail(L('You cannot carry the key'))
  end
  CarLock.moveKeyItem(f.md, 'player', identifierOf(src), nil)
  TriggerClientEvent('nz:client:carlock:keys', src, { plate = f.plate })
  return Utils.ok({ plate = f.plate, keyKind = f.keyKind })
end))

--- A ground key the player may act on: record or nil, error. Distance from the SERVER ped to
--- the server's position of the key.
local function reachableGround(src, id)
  local rec = type(id) == 'string' and grounds[id] or nil
  if not rec then return nil, L('This key is gone') end
  local ped = pedOf(src)
  if not ped or GetPlayerRoutingBucket(tostring(src)) ~= (rec.bucket or 0) then return nil, L('This key is gone') end
  local range = Utils.clamp(tonumber(groundCfg().pickupRange) or 2.0, 0.5, 5.0) + 0.75
  -- the prop is not frozen (it settles / rolls): measure to where it is now
  local pos = rec.coords
  if rec.entity and DoesEntityExist(rec.entity) then
    local ok, c = pcall(GetEntityCoords, rec.entity)
    if ok and c then pos = c end
  end
  if #(GetEntityCoords(ped) - pos) > range then return nil, L('You are too far away') end
  if rec.heldBy and rec.heldBy ~= src and (rec.heldUntil or 0) > os.time() and validSrc(rec.heldBy) then
    return nil, L('Someone else is looking at this key')
  end
  return rec, nil
end

local function vehicleNameOf(rec)
  local md = type(rec.metadata) == 'table' and rec.metadata or {}
  if type(md.model) == 'string' and md.model ~= '' then return md.model end
  local row = CarLock.vehicleRow(rec.plate)
  return row and row.model or nil
end

lib.callback.register('nz:carlock:ground:inspect', Utils.safe(function(source, payload)
  local src = validSrc(source)
  if not src or type(payload) ~= 'table' then return Utils.fail(L('Invalid request')) end
  if limited(src, 'inspect') then return Utils.fail(L('Please wait a moment')) end
  local rec, err = reachableGround(src, payload.id)
  if not rec then return Utils.fail(err) end
  rec.heldBy, rec.heldUntil = src, os.time() + INSPECT_HOLD
  local md = type(rec.metadata) == 'table' and rec.metadata or {}
  return Utils.ok({ id = rec.id, plate = rec.plate, keyKind = rec.keyKind, kind = rec.kind,
    label = type(md.label) == 'string' and md.label or CarLock.keyLabel(rec.keyKind, rec.plate),
    model = vehicleNameOf(rec), droppedAt = rec.createdAt })
end))

lib.callback.register('nz:carlock:ground:pickup', Utils.safe(function(source, payload)
  local src = validSrc(source)
  if not src or type(payload) ~= 'table' then return Utils.fail(L('Invalid request')) end
  if limited(src, 'ground') then return Utils.fail(L('Please wait a moment')) end
  local rec, err = reachableGround(src, payload.id)
  if not rec then return Utils.fail(err) end
  if GetVehiclePedIsIn(pedOf(src), false) ~= 0 then return Utils.fail(L('Get out of the vehicle first')) end
  if rec.kind == 'item' then
    if not NZ.Inventory.canCarry(src, rec.item, 1, rec.metadata) then return Utils.fail(L('You cannot carry the key')) end
    groundRemove(rec.id, 'pickup')
    if not NZ.Inventory.addItem(src, rec.item, 1, rec.metadata) then
      -- put it back where it was; if even that fails, force it into the picker's pocket or mark it lost
      local oldId = rec.id
      rec.id = nil
      local okBack, back = pcall(CarLock.groundCreate, rec)
      if not (okBack and back) then
        local given = NZ.Inventory.addItem(src, rec.item, 1, rec.metadata, nil, true)
        CarLock.moveKeyItem(rec.metadata, given and 'player' or 'lost', given and identifierOf(src) or ('ground:' .. tostring(oldId)), nil)
        if given then
          TriggerClientEvent('nz:client:carlock:keys', src, { plate = rec.plate })
          return Utils.ok({ plate = rec.plate, keyKind = rec.keyKind })
        end
      end
      return Utils.fail(L('You cannot carry the key'))
    end
    CarLock.moveKeyItem(rec.metadata, 'player', identifierOf(src), nil)
  else
    groundRemove(rec.id, 'pickup')
    if not CarLock.grantTemp(src, rec.plate, rec.reason or 'robbery') then return Utils.fail(L('Something went wrong')) end
  end
  TriggerClientEvent('nz:client:carlock:keys', src, { plate = rec.plate })
  log('vehicle.keyPickup', src, { plate = rec.plate, kind = rec.kind })
  return Utils.ok({ plate = rec.plate, keyKind = rec.keyKind })
end))

lib.callback.register('nz:carlock:ground:release', Utils.safe(function(source, payload)
  local src = validSrc(source)
  if not src or type(payload) ~= 'table' or type(payload.id) ~= 'string' then return Utils.fail(L('Invalid request')) end
  if limited(src, 'ground') then return Utils.fail(L('Please wait a moment')) end
  local rec = grounds[payload.id]
  if rec and rec.heldBy == src then rec.heldBy, rec.heldUntil = nil, nil end
  return Utils.ok(nil)
end))

lib.callback.register('nz:carlock:inspect', Utils.safe(function(source, payload)
  local src = validSrc(source)
  if not src or type(payload) ~= 'table' then return Utils.fail(L('Invalid request')) end
  if limited(src, 'inspect') then return Utils.fail(L('Please wait a moment')) end
  local key, err = carriedKey(src, payload)
  if not key then return Utils.fail(err) end
  local md = key.metadata
  local valid, reason = CarLock.verifyKeyItem(md)
  local plate = normPlate(md.plate)
  local row = CarLock.vehicleRow(plate)
  return Utils.ok({ plate = plate, keyKind = key.keyKind, label = type(md.label) == 'string' and md.label or CarLock.keyLabel(key.keyKind, plate),
    model = (type(md.model) == 'string' and md.model ~= '' and md.model) or (row and row.model) or nil,
    valid = valid == true, reason = reason, origin = type(md.origin) == 'string' and md.origin or nil, slot = key.slot,
    keyId = md.id })
end))

-- Expiry, persistence and restart

local function groundTick()
  local t = os.time()
  -- snapshot the ids: the DB / prop calls below yield, and a key dropped meanwhile must not
  -- change the table under the traversal
  local ids = {}
  for id in pairs(grounds) do ids[#ids + 1] = id end
  for _, id in ipairs(ids) do
    local rec = grounds[id]
    if not rec then
      -- picked up / removed during an earlier yield of this tick
    elseif rec.expiresAt and rec.expiresAt <= t then
      groundRemove(id, 'expired')
    elseif rec.heldUntil and rec.heldUntil <= t then
      rec.heldBy, rec.heldUntil = nil, nil
    elseif not (rec.entity and DoesEntityExist(rec.entity)) then
      spawnProp(rec) -- the prop was removed (entity cleanup, culling): put it back
      if rec.netId then sendToBucket(rec.bucket or 0, { add = viewOf(rec) }) end
    else
      -- the prop settles / rolls: keep the record (pick-up range, restart snapshot, DB) where it lies
      local ok, c = pcall(GetEntityCoords, rec.entity)
      if ok and c and tonumber(c.x) and #(c - rec.coords) > 0.25 and #(c - rec.coords) < 50.0 then
        rec.coords = vector3(c.x + 0.0, c.y + 0.0, c.z + 0.0)
        if rec.persisted and NZ.DB.groundKeys then persistRecord(rec) end
      end
    end
  end
  local due = {}
  for id, f in pairs(flights) do
    if GetGameTimer() > f.expires + 2000 then due[#due + 1] = id end
  end
  for _, id in ipairs(due) do landFlight(id) end
end

local function restoreGround(list, source)
  local t, count = os.time(), 0
  for _, g in ipairs(list) do
    local data = type(g.data) == 'table' and g.data or {}
    if g.expiresAt == nil or g.expiresAt > t then
      local rec = { id = g.id, plate = g.plate, kind = data.kind == 'temp' and 'temp' or 'item', item = data.item,
        metadata = data.metadata, reason = data.reason, keyKind = data.keyKind == 'fob' and 'fob' or 'key',
        coords = vector3(tonumber(g.x) or 0.0, tonumber(g.y) or 0.0, tonumber(g.z) or 0.0), heading = tonumber(g.heading) or 0.0,
        bucket = math.tointeger(tonumber(g.bucket) or 0) or 0, droppedBy = data.droppedBy,
        createdAt = tonumber(data.createdAt) or t, expiresAt = g.expiresAt, persisted = source == 'db' }
      if rec.plate and type(rec.id) == 'string' and not grounds[rec.id] and (rec.kind == 'temp' or type(rec.metadata) == 'table') then
        grounds[rec.id] = rec
        groundCount = groundCount + 1
        spawnProp(rec)
        count = count + 1
      end
    elseif source == 'db' and NZ.DB.groundKeys then
      NZ.DB.groundKeys.remove(g.id)
    end
  end
  if count > 0 then lib.print.info(('[nayzeee-garages] carlock: %d key(s) put back on the ground'):format(count)) end
end

-- ground.persist switched in game: off -> the stored rows go (the live keys are covered by the
-- restart snapshot again); on -> the live keys are stored.
local persistWas = nil
settingsHooks[#settingsHooks + 1] = function()
  local now = persistOn()
  if persistWas ~= nil and now ~= persistWas and NZ.DB.groundKeys then
    if now then
      local ids = {}
      for id in pairs(grounds) do ids[#ids + 1] = id end
      for _, id in ipairs(ids) do
        local rec = grounds[id]
        if rec then rec.persisted = persistRecord(rec) end
      end
    else
      for _, rec in pairs(grounds) do rec.persisted = false end
      if type(NZ.DB.groundKeys.clear) == 'function' then pcall(NZ.DB.groundKeys.clear) end
    end
  end
  persistWas = now
end

CreateThread(function()
  local deadline = GetGameTimer() + 120000
  while not (NZ.Ready and settingsReady) and GetGameTimer() < deadline do Wait(500) end
  -- a resource restart in the same server session (persist off)
  local okKvp, raw = pcall(GetResourceKvpString, GROUND_KVP)
  if okKvp and type(raw) == 'string' and raw ~= '' then
    pcall(DeleteResourceKvp, GROUND_KVP)
    local okDecode, data = pcall(json.decode, raw)
    local boot = os.time() - math.floor(GetGameTimer() / 1000)
    if okDecode and type(data) == 'table' and math.abs((tonumber(data.boot) or 0) - boot) <= 15 and type(data.keys) == 'table' then
      restoreGround(data.keys, 'kvp')
    end
  end
  if not settingsLoaded then
    -- the admin settings did not load (database error / timeout): persistence is unknown, so
    -- neither restore nor wipe the stored keys
    lib.print.warn('[nayzeee-garages] carlock: admin key settings not loaded, stored ground keys left untouched')
  elseif persistOn() and NZ.DB.groundKeys then
    local ok, list = pcall(NZ.DB.groundKeys.all)
    if ok and type(list) == 'table' then restoreGround(list, 'db') end
  elseif NZ.DB.groundKeys and type(NZ.DB.groundKeys.clear) == 'function' then
    pcall(NZ.DB.groundKeys.clear) -- rows left from when persistence was on
  end
  while true do
    Wait(15000)
    local ok, err = pcall(groundTick)
    if not ok then lib.print.warn(('[nayzeee-garages] carlock: ground keys: %s'):format(tostring(err))) end
  end
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= GetCurrentResourceName() then return end
  local keep = {}
  for _, f in pairs(flights) do
    -- a key in the air lands where it was thrown from
    keep[#keep + 1] = { id = groundId(), plate = f.plate, data = { kind = 'item', item = f.item, metadata = f.md,
      keyKind = f.keyKind, droppedBy = f.droppedBy, createdAt = os.time() }, x = f.origin.x, y = f.origin.y, z = f.origin.z - 0.6,
      heading = 0.0, bucket = f.bucket }
  end
  for _, rec in pairs(grounds) do
    deleteProp(rec)
    if not rec.persisted then
      keep[#keep + 1] = { id = rec.id, plate = rec.plate, data = { kind = rec.kind, item = rec.item, metadata = rec.metadata,
        reason = rec.reason, keyKind = rec.keyKind, droppedBy = rec.droppedBy, createdAt = rec.createdAt },
        x = rec.coords.x, y = rec.coords.y, z = rec.coords.z, heading = rec.heading or 0.0, bucket = rec.bucket or 0,
        expiresAt = rec.expiresAt }
    end
  end
  if #keep > 0 then
    local ok, encoded = pcall(json.encode, { boot = os.time() - math.floor(GetGameTimer() / 1000), keys = keep })
    if ok and type(encoded) == 'string' then pcall(SetResourceKvp, GROUND_KVP, encoded) end
  end
end)

-- A ground prop removed by something else (cleanup scripts) is put back by the tick.
AddEventHandler('entityRemoved', function(entity)
  for _, rec in pairs(grounds) do
    if rec.entity == entity then
      rec.entity, rec.netId = nil, nil
      break
    end
  end
end)
