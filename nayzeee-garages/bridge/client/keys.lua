--[[
  nayzeee-garages — vehicle keys integration (client): NZ.Keys.

  Built-in car lock (Config.CarLock.enabled and Config.Integrations.keys 'auto' or
  'nayzeee'): the server hands the key out when the garage validates the spawned vehicle
  (bridge/server/keys.lua), so give() only tells the local car lock that a key is on its way
  (the engine is not cut while the server answers) and remove() asks the server.

  Otherwise gives / removes keys through the key resource selected by Config.Integrations.keys
  ('auto' = first started resource of KEY_RESOURCES, 'none' = disabled). Server-side key
  systems (qbx_vehiclekeys) are reached through the 'nz:keys:give' / 'nz:keys:remove'
  callbacks (bridge/server/keys.lua). Every third-party call is protected: a broken or
  missing key resource never breaks a spawn.
]]

local Keys = NZ.Keys
local Utils = NZ.Utils

-- Detection order for Config.Integrations.keys = 'auto'.
local KEY_RESOURCES = {
  'qbx_vehiclekeys',
  'qb-vehiclekeys',
  'wasabi_carlock',
  'MrNewbVehicleKeys',
  'qs-vehiclekeys',
  'Renewed-Vehiclekeys',
  'vehicles_keys',
}

local KNOWN = {}
local KNOWN_LOWER = {}
for i = 1, #KEY_RESOURCES do
  KNOWN[KEY_RESOURCES[i]] = true
  KNOWN_LOWER[KEY_RESOURCES[i]:lower()] = KEY_RESOURCES[i]
end

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function started(name)
  return NZ.Utils.resourceStarted(name)
end

local function isVehicle(vehicle)
  return type(vehicle) == 'number' and vehicle ~= 0 and DoesEntityExist(vehicle) and IsEntityAVehicle(vehicle)
end

--- Trimmed, upper-case plate from the argument or, when missing, from the entity.
local function plateOf(vehicle, plate)
  local p = Utils.plate(plate)
  if p then return p end
  if isVehicle(vehicle) then return Utils.plate(GetVehicleNumberPlateText(vehicle)) end
  return nil
end

--- Network id of a networked vehicle, nil for local (non-networked) entities.
local function netIdOf(vehicle)
  if not isVehicle(vehicle) or not NetworkGetEntityIsNetworked(vehicle) then return nil end
  local netId = NetworkGetNetworkIdFromEntity(vehicle)
  if not netId or netId == 0 then return nil end
  return netId
end

local function modelName(vehicle)
  if not isVehicle(vehicle) then return nil end
  local name = GetDisplayNameFromVehicleModel(GetEntityModel(vehicle))
  if type(name) ~= 'string' or name == '' or name == 'CARNOTFOUND' then return nil end
  return name
end

local function giveKeysEnabled()
  local current = NZ.State.settings
  local section = type(current) == 'table' and current.vehicles or nil
  if type(section) == 'table' and section.giveKeys == false then return false end
  return true
end

local function warn(action, resource, err)
  Utils.debug(('keys: %s through %s failed: %s'):format(action, resource, tostring(err)))
end

--- Ask the server to run a server-side key export (async, never blocks the caller).
local function serverCall(name, vehicle, plate)
  local netId = netIdOf(vehicle)
  if not netId or not plate then return false end
  lib.callback(name, false, function(res)
    if type(res) == 'table' and res.ok == false then
      Utils.debug(('keys: %s refused: %s'):format(name, tostring(res.error)))
    end
  end, { netId = netId, plate = plate })
  return true
end

---------------------------------------------------------------------------------------
-- Adapters: give(vehicle, plate) / remove(vehicle, plate). plate is trimmed + upper-case.
---------------------------------------------------------------------------------------

local adapters = {}

adapters['qbx_vehiclekeys'] = {
  give = function(vehicle, plate)
    return serverCall('nz:keys:give', vehicle, plate)
  end,
  remove = function(vehicle, plate)
    return serverCall('nz:keys:remove', vehicle, plate)
  end,
}

adapters['qb-vehiclekeys'] = {
  give = function(_, plate)
    TriggerEvent('vehiclekeys:client:SetOwner', plate)
    return true
  end,
  remove = function(_, plate)
    TriggerEvent('qb-vehiclekeys:client:RemoveKeys', plate)
    return true
  end,
}

adapters['wasabi_carlock'] = {
  give = function(_, plate)
    exports.wasabi_carlock:GiveKey(plate)
    return true
  end,
  remove = function(_, plate)
    exports.wasabi_carlock:RemoveKey(plate)
    return true
  end,
}

adapters['MrNewbVehicleKeys'] = {
  give = function(vehicle)
    if not isVehicle(vehicle) then return false end
    exports.MrNewbVehicleKeys:GiveKeys(vehicle)
    return true
  end,
  remove = function(vehicle)
    if not isVehicle(vehicle) then return false end
    exports.MrNewbVehicleKeys:RemoveKeys(vehicle)
    return true
  end,
}

adapters['qs-vehiclekeys'] = {
  give = function(vehicle, plate)
    exports['qs-vehiclekeys']:GiveKeys(plate, modelName(vehicle) or plate, true)
    return true
  end,
  remove = function(vehicle, plate)
    exports['qs-vehiclekeys']:RemoveKeys(plate, modelName(vehicle) or plate)
    return true
  end,
}

adapters['Renewed-Vehiclekeys'] = {
  give = function(_, plate)
    exports['Renewed-Vehiclekeys']:addKey(plate)
    return true
  end,
  remove = function(_, plate)
    exports['Renewed-Vehiclekeys']:removeKey(plate)
    return true
  end,
}

-- Built-in car lock: the server grants the key itself once the garage validated the entity.
adapters.nayzeee = {
  give = function(vehicle, plate)
    if type(NZ.CarLock.expectKey) == 'function' then NZ.CarLock.expectKey(vehicle, plate) end
    return true
  end,
  remove = function(vehicle, plate)
    lib.callback('nz:carlock:compat', false, function() end, { action = 'remove', plate = plate, netId = netIdOf(vehicle) })
    return true
  end,
}

adapters['vehicles_keys'] = {
  give = function(_, plate)
    TriggerServerEvent('vehicles_keys:selfGiveVehicleKeys', plate)
    return true
  end,
  remove = function(_, plate)
    TriggerServerEvent('vehicles_keys:selfRemoveKeys', plate)
    return true
  end,
}

---------------------------------------------------------------------------------------
-- Resolution
---------------------------------------------------------------------------------------

--- Is the built-in car lock in charge of keys?
---@return boolean
function Keys.builtIn()
  return type(NZ.CarLock.enabled) == 'function' and NZ.CarLock.enabled() == true
end

--- Key resource in use right now: 'nayzeee' (built-in car lock), a resource name, or nil
--- (disabled, unknown or not started).
---@return string|nil
function Keys.resource()
  if Keys.builtIn() then return 'nayzeee' end
  local configured = Config.Integrations and Config.Integrations.keys or 'auto'
  if type(configured) ~= 'string' or configured == '' then configured = 'auto' end
  if configured == 'none' or configured == 'nayzeee' then return nil end
  if configured == 'auto' then
    for i = 1, #KEY_RESOURCES do
      if started(KEY_RESOURCES[i]) then return KEY_RESOURCES[i] end
    end
    return nil
  end
  local name = KNOWN[configured] and configured or KNOWN_LOWER[configured:lower()]
  if not name then return nil end
  if not started(name) then return nil end
  return name
end

local function run(action, vehicle, plate)
  local resource = Keys.resource()
  if not resource then return false end
  local adapter = adapters[resource]
  local fn = adapter and adapter[action]
  if not fn then return false end
  local p = plateOf(vehicle, plate)
  if not p then return false end
  local ok, res = pcall(fn, vehicle, p)
  if not ok then
    warn(action, resource, res)
    return false
  end
  return res ~= false
end

---------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------

--- Give the local player keys to a vehicle. No-op when keys are disabled in the settings
--- (vehicles.giveKeys), when no key resource runs or Config.Integrations.keys = 'none'.
---@param vehicle number|nil vehicle entity (required by entity based key systems)
---@param plate string|nil plate; read from the entity when nil
---@return boolean handled
function Keys.give(vehicle, plate)
  if not giveKeysEnabled() then return false end
  return run('give', vehicle, plate)
end

-- A vehicle another script delivered for this player (phone valet, server/phone.lua) while a
-- CLIENT-side key resource is in use: the keys follow, as on a garage retrieve. The built-in car
-- lock and server-side systems give keys on the server (NZ.KeysServer.give in markSpawned).
RegisterNetEvent('nz:client:giveKeys', function(netId, plate)
  plate = Utils.plate(plate)
  if not plate or #plate > 16 then return end
  netId = tonumber(netId)
  local vehicle = (netId and NetworkDoesNetworkIdExist(netId)) and NetworkGetEntityFromNetworkId(netId) or 0
  -- plate-based key resources do not need the entity in scope; when it is, it must match
  if isVehicle(vehicle) and Utils.plate(GetVehicleNumberPlateText(vehicle)) ~= plate then return end
  if not isVehicle(vehicle) then vehicle = nil end
  pcall(Keys.give, vehicle, plate)
end)

--- Remove the local player's keys of a vehicle (best effort, same resolution as give).
---@param vehicle number|nil vehicle entity
---@param plate string|nil plate; read from the entity when nil
---@return boolean handled
function Keys.remove(vehicle, plate)
  if not giveKeysEnabled() then return false end
  return run('remove', vehicle, plate)
end
