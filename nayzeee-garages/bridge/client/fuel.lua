--[[
  nayzeee-garages — fuel integration (client): NZ.Fuel.

  Reads / writes a vehicle's fuel (percent 0-100) through the fuel resource selected by
  Config.Integrations.fuel ('auto' = first started resource of FUEL_RESOURCES, 'native' =
  GTA natives only). Falls back to the natives whenever a fuel resource call fails.
]]

local Fuel = NZ.Fuel
local Utils = NZ.Utils

-- Detection order for Config.Integrations.fuel = 'auto'.
local FUEL_RESOURCES = {
  'ox_fuel',
  'LegacyFuel',
  'cdn-fuel',
  'ps-fuel',
  'lj-fuel',
  'okokGasStation',
  'qs-fuelstations',
  'Renewed-Fuel',
  'ti_fuel',
}

-- How each resource stores fuel: 'statebag' (Entity(veh).state.fuel) or 'export' (SetFuel/GetFuel).
local KIND = {
  ['ox_fuel'] = 'statebag',
  ['Renewed-Fuel'] = 'statebag',
  ['LegacyFuel'] = 'export',
  ['cdn-fuel'] = 'export',
  ['ps-fuel'] = 'export',
  ['lj-fuel'] = 'export',
  ['okokGasStation'] = 'export',
  ['qs-fuelstations'] = 'export',
  ['ti_fuel'] = 'export',
}

local KNOWN_LOWER = {}
for name in pairs(KIND) do KNOWN_LOWER[name:lower()] = name end

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function isVehicle(vehicle)
  return type(vehicle) == 'number' and vehicle ~= 0 and DoesEntityExist(vehicle) and IsEntityAVehicle(vehicle)
end

local function percent(value)
  local n = tonumber(value)
  if not n or n ~= n then return nil end
  return Utils.clamp(n, 0, 100) + 0.0
end

local function nativeGet(vehicle)
  return percent(GetVehicleFuelLevel(vehicle)) or 0.0
end

local function nativeSet(vehicle, value)
  SetVehicleFuelLevel(vehicle, value)
end

local function failed(action, resource, err)
  Utils.debug(('fuel: %s through %s failed: %s'):format(action, resource, tostring(err)))
end

--- Fuel resource in use right now, or nil for the GTA natives.
---@return string|nil
function Fuel.resource()
  local configured = Config.Integrations and Config.Integrations.fuel or 'auto'
  if type(configured) ~= 'string' or configured == '' then configured = 'auto' end
  if configured == 'native' or configured == 'none' then return nil end
  if configured == 'auto' then
    for i = 1, #FUEL_RESOURCES do
      if Utils.resourceStarted(FUEL_RESOURCES[i]) then return FUEL_RESOURCES[i] end
    end
    return nil
  end
  local name = KIND[configured] and configured or KNOWN_LOWER[configured:lower()]
  if name and Utils.resourceStarted(name) then return name end
  return nil
end

---------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------

--- Current fuel of a vehicle in percent (0-100). Returns 0 for an invalid entity.
---@param vehicle number
---@return number
function Fuel.get(vehicle)
  if not isVehicle(vehicle) then return 0.0 end
  local resource = Fuel.resource()
  local kind = resource and KIND[resource]

  if kind == 'statebag' then
    local ok, value = pcall(function() return Entity(vehicle).state.fuel end)
    local v = ok and percent(value) or nil
    if v then return v end
    if not ok then failed('get', resource, value) end
  elseif kind == 'export' then
    local ok, value = pcall(function() return exports[resource]:GetFuel(vehicle) end)
    local v = ok and percent(value) or nil
    if v then return v end
    if not ok then failed('get', resource, value) end
  end
  return nativeGet(vehicle)
end

--- Set the fuel of a vehicle (percent, clamped to 0-100). The native level is always set
--- too so the vehicle behaves correctly even when the fuel resource ignores the call.
---@param vehicle number
---@param value number
---@return boolean ok
function Fuel.set(vehicle, value)
  if not isVehicle(vehicle) then return false end
  local v = percent(value)
  if not v then return false end
  local resource = Fuel.resource()
  local kind = resource and KIND[resource]

  if kind == 'statebag' then
    local ok, err = pcall(function() Entity(vehicle).state:set('fuel', v, true) end)
    if not ok then failed('set', resource, err) end
    nativeSet(vehicle, v)
    return true
  elseif kind == 'export' then
    local ok, err = pcall(function() exports[resource]:SetFuel(vehicle, v) end)
    if not ok then failed('set', resource, err) end
    nativeSet(vehicle, v)
    return true
  end
  nativeSet(vehicle, v)
  return true
end
