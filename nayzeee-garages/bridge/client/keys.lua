--[[
  nayzeee-garages — vehicle keys integration (client): NZ.Keys.

  Gives / removes keys through the key resource selected by Config.Integrations.keys
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

--- Key resource in use right now, or nil (disabled, unknown or not started).
---@return string|nil
function Keys.resource()
  local configured = Config.Integrations and Config.Integrations.keys or 'auto'
  if type(configured) ~= 'string' or configured == '' then configured = 'auto' end
  if configured == 'none' then return nil end
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

--- Remove the local player's keys of a vehicle (best effort, same resolution as give).
---@param vehicle number|nil vehicle entity
---@param plate string|nil plate; read from the entity when nil
---@return boolean handled
function Keys.remove(vehicle, plate)
  if not giveKeysEnabled() then return false end
  return run('remove', vehicle, plate)
end
