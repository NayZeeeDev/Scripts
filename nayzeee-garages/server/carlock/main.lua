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
    nz:carlock:share      { plate, target } -> null   virtual: persistent key (owner only);
                          physical: hands one key item over (server copy of the metadata)
    nz:carlock:revoke     { plate, identifier } -> null   owner / admin
    nz:carlock:holders    { plate } -> { { identifier, name, kind, grantedBy, at, expires } }
    nz:carlock:compat     { action = 'acquire'|'remove'|'lend', netId?, plate?, target?, export? }
                          other scripts' CLIENT events / exports (bridge/client/listeners.lua):
                          temporary keys only, NZ.CarLock.canAcquire rules (a key allowed
                          through a share / fleet access ends with it); 'lend' needs a key
                          that is not temporary, in physical mode a key item is handed over
                          (owners may lend a temporary key);
                          export = true (client export GiveKey) needs clientGiveKeyExport
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
  if has then return true, kind end
  if CarLock.jobBypass(src, plate) then return true, 'job' end
  return false, nil
end

---------------------------------------------------------------------------------------
-- Toggle lock / engine / key checks
---------------------------------------------------------------------------------------

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
    local ignition = has
    if not ignition then ignition = ignitionAllowed(src, entity, class) end
    return Utils.ok({ plate = plate, has = has, kind = kind, ignition = ignition == true, locked = CarLock.isLocked(entity) })
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
  local ok, err
  if CarLock.mode() == 'virtual' then
    ok, err = CarLock.shareVirtual(src, target, plate)
  else
    ok, err = CarLock.handOverKeyItem(src, target, plate)
  end
  if not ok then return Utils.fail(err or L('Something went wrong')) end
  notify(target, L('You received the key of {plate}', { plate = plate }), 'success')
  return Utils.ok(nil)
end))

lib.callback.register('nz:carlock:revoke', Utils.safe(function(source, payload)
  local src = validSrc(source)
  if not src or type(payload) ~= 'table' then return Utils.fail(L('Invalid request')) end
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
  local out = {}
  for _, h in ipairs(CarLock.holders(plate)) do
    out[#out + 1] = { identifier = h.identifier, name = h.name, kind = h.kind, grantedBy = h.grantedBy,
      at = h.at, expires = h.expires }
  end
  return Utils.ok(out)
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
  if src then compatTokens[math.tointeger(src) or src] = nil end
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
