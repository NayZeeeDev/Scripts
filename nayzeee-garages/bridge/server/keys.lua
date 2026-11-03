--[[
  nayzeee-garages — vehicle keys integration (server): NZ.KeysServer.

  Server-side key systems (qbx_vehiclekeys) cannot be reached from the client, so the
  client bridge (bridge/client/keys.lua) asks through the 'nz:keys:give' / 'nz:keys:remove'
  callbacks, and the garage code calls NZ.KeysServer.give directly after a spawn.
  Client-side key systems are handled entirely by the client bridge: here they are no-ops.
]]

local KeysServer = NZ.KeysServer
local Utils = NZ.Utils

-- Same detection order as the client bridge (Config.Integrations.keys = 'auto').
local KEY_RESOURCES = {
  'qbx_vehiclekeys',
  'qb-vehiclekeys',
  'wasabi_carlock',
  'MrNewbVehicleKeys',
  'qs-vehiclekeys',
  'Renewed-Vehiclekeys',
  'vehicles_keys',
}

local SERVER_SIDE = { qbx_vehiclekeys = true }

local MAX_KEY_DISTANCE = 10.0   -- metres between the player and the vehicle
local AWAIT_ENTITY_MS = 2500    -- a client asks right after creating the vehicle: wait for it
local RATE_LIMIT_MS = 1000
local DEDUPE_MS = 10000         -- the same player + vehicle is given keys once per window

local recent = {}               -- [src] = { [entity] = GetGameTimer() }

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function started(name)
  return Utils.resourceStarted(name)
end

--- Key resource in use (same rules as the client), or nil.
---@return string|nil
function KeysServer.resource()
  local configured = Config.Integrations and Config.Integrations.keys or 'auto'
  if type(configured) ~= 'string' or configured == '' then configured = 'auto' end
  if configured == 'none' then return nil end
  if configured == 'auto' then
    for i = 1, #KEY_RESOURCES do
      if started(KEY_RESOURCES[i]) then return KEY_RESOURCES[i] end
    end
    return nil
  end
  local lower = configured:lower()
  for i = 1, #KEY_RESOURCES do
    if KEY_RESOURCES[i]:lower() == lower then
      return started(KEY_RESOURCES[i]) and KEY_RESOURCES[i] or nil
    end
  end
  return nil
end

local function validPlayer(src)
  src = tonumber(src)
  if not src or src <= 0 or src ~= math.floor(src) then return nil end
  if GetPlayerName(tostring(src)) == nil then return nil end
  return math.tointeger(src)
end

local function vehicleFromNetId(netId)
  local id = tonumber(netId)
  if not id or id <= 0 or id ~= math.floor(id) or id > 0x7FFFFFFF then return nil end
  local entity = NetworkGetEntityFromNetworkId(math.tointeger(id))
  if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then return nil end
  return entity
end

local function entityPlate(entity)
  return Utils.plate(GetVehicleNumberPlateText(entity))
end

local function log(event, src, data)
  if type(NZ.Logs.add) ~= 'function' then return end
  local ok, err = pcall(NZ.Logs.add, event, src, data)
  if not ok then lib.print.warn(('keys: log "%s" failed: %s'):format(event, tostring(err))) end
end

local function sweep(now)
  for src, list in pairs(recent) do
    for entity, at in pairs(list) do
      if now - at > DEDUPE_MS then list[entity] = nil end
    end
    if next(list) == nil then recent[src] = nil end
  end
end

local function recentlyGiven(src, entity)
  local now = GetGameTimer()
  local list = recent[src]
  local at = list and list[entity]
  return at ~= nil and now - at < DEDUPE_MS
end

local function remember(src, entity)
  local now = GetGameTimer()
  local list = recent[src]
  if not list then
    list = {}
    recent[src] = list
  end
  list[entity] = now
  if math.random(1, 25) == 1 then sweep(now) end
end

--- May this player get keys to this plate? Only the player who took it out (or its owner).
local function entitled(src, plate)
  local identifier = nil
  if type(NZ.Bridge.getIdentifier) == 'function' then
    local ok, res = pcall(NZ.Bridge.getIdentifier, src)
    if ok and type(res) == 'string' and res ~= '' then identifier = res end
  end
  local out = type(NZ.Vehicles.out) == 'table' and NZ.Vehicles.out[plate] or nil
  if type(out) == 'table' then
    if out.src == src then return true end
    if identifier and out.identifier == identifier then return true end
  end
  if identifier and type(NZ.DB.getVehicle) == 'function' then
    local ok, row = pcall(NZ.DB.getVehicle, plate)
    if ok and type(row) == 'table' and row.owner == identifier then return true end
  end
  return false
end

---------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------

--- Give a player keys through a server-side key system (qbx_vehiclekeys). Trusted
--- server code only: callers must have validated the request. No-op for client-side
--- key systems (the client bridge handles those).
---@param src number player source
---@param netId number network id of the vehicle
---@param plate string|nil expected plate (checked against the entity when given)
---@return boolean given
function KeysServer.give(src, netId, plate)
  src = validPlayer(src)
  if not src then return false end
  local resource = KeysServer.resource()
  if not resource or not SERVER_SIDE[resource] then return false end
  local entity = vehicleFromNetId(netId)
  if not entity then return false end
  local wanted = Utils.plate(plate)
  if wanted and entityPlate(entity) ~= wanted then return false end
  if recentlyGiven(src, entity) then return true end

  local ok, err = pcall(function()
    exports.qbx_vehiclekeys:GiveKeys(src, entity)
  end)
  if not ok then
    lib.print.warn(('keys: qbx_vehiclekeys GiveKeys failed: %s'):format(tostring(err)))
    return false
  end
  remember(src, entity)
  return true
end

--- Remove a player's keys through a server-side key system (best effort).
---@param src number
---@param netId number
---@param plate string|nil
---@return boolean removed
function KeysServer.remove(src, netId, plate)
  src = validPlayer(src)
  if not src then return false end
  local resource = KeysServer.resource()
  if not resource or not SERVER_SIDE[resource] then return false end
  local entity = vehicleFromNetId(netId)
  if not entity then return false end
  local wanted = Utils.plate(plate)
  if wanted and entityPlate(entity) ~= wanted then return false end

  local ok, err = pcall(function()
    exports.qbx_vehiclekeys:RemoveKeys(src, entity)
  end)
  if recent[src] then recent[src][entity] = nil end
  if not ok then
    lib.print.warn(('keys: qbx_vehiclekeys RemoveKeys failed: %s'):format(tostring(err)))
    return false
  end
  return true
end

---------------------------------------------------------------------------------------
-- Callbacks
---------------------------------------------------------------------------------------

--- Shared validation of { netId, plate } requests. Returns entity, plate or nil, error.
local function validateRequest(src, payload, bucket)
  if type(payload) ~= 'table' then return nil, nil, L('Invalid request') end
  if not NZ.Access.rateLimit(src, bucket, RATE_LIMIT_MS) then
    return nil, nil, L('Please wait a moment')
  end
  local netId = payload.netId
  if type(netId) ~= 'number' then return nil, nil, L('Invalid vehicle') end
  local plate = type(payload.plate) == 'string' and #payload.plate <= 16 and Utils.plate(payload.plate) or nil
  if not plate then return nil, nil, L('Invalid vehicle') end
  -- The client asks in the frame it created the vehicle; its clone and plate reach the
  -- server separately from this request, so give them a moment before refusing.
  local entity = vehicleFromNetId(netId)
  local deadline = GetGameTimer() + AWAIT_ENTITY_MS
  while not (entity and entityPlate(entity) == plate) and GetGameTimer() < deadline do
    Wait(50)
    entity = vehicleFromNetId(netId)
  end
  if not entity then return nil, nil, L('Vehicle not found') end
  if entityPlate(entity) ~= plate then
    log('security.keys', src, { plate = plate, netId = netId, reason = 'plate does not match the vehicle' })
    return nil, nil, L('Vehicle not found')
  end
  local ped = GetPlayerPed(tostring(src))
  if not ped or ped == 0 then return nil, nil, L('Vehicle not found') end
  local dist = #(GetEntityCoords(ped) - GetEntityCoords(entity))
  if dist > MAX_KEY_DISTANCE then return nil, nil, L('You are too far from the vehicle') end
  return entity, plate, nil
end

lib.callback.register('nz:keys:give', Utils.safe(function(source, payload)
  local src = validPlayer(source)
  if not src then return Utils.fail(L('Invalid request')) end
  local resource = KeysServer.resource()
  if not resource or not SERVER_SIDE[resource] then return Utils.ok(false) end
  if type(NZ.Settings.get) == 'function' and NZ.Settings.get('vehicles.giveKeys', true) == false then
    return Utils.ok(false)
  end

  local entity, plate, err = validateRequest(src, payload, 'keys:give')
  if not entity then return Utils.fail(err) end
  if not entitled(src, plate) then
    log('security.keys', src, { plate = plate, netId = payload.netId, reason = 'keys requested for a vehicle the player did not take out' })
    return Utils.fail(L('You do not have access to this vehicle'))
  end
  return Utils.ok(KeysServer.give(src, payload.netId, plate))
end))

lib.callback.register('nz:keys:remove', Utils.safe(function(source, payload)
  local src = validPlayer(source)
  if not src then return Utils.fail(L('Invalid request')) end
  local resource = KeysServer.resource()
  if not resource or not SERVER_SIDE[resource] then return Utils.ok(false) end

  local entity, plate, err = validateRequest(src, payload, 'keys:remove')
  if not entity then return Utils.fail(err) end
  return Utils.ok(KeysServer.remove(src, payload.netId, plate))
end))

AddEventHandler('playerDropped', function()
  local src = tonumber(source)
  if src then recent[src] = nil end
end)
