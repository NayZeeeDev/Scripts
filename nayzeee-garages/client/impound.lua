--[[
  nayzeee-garages — impound client (NZ.ImpoundClient).
  Impound menu (owner retrieval / staff view), the impound form for the closest vehicle,
  the "Impound vehicle" target option for impound staff and the impound exports (§7.4).
]]

local Impound = NZ.ImpoundClient

local ctx = nil              -- { locationId, location, data } of the last opened impound
local opening = false
local formBusy = false
local targetOptionId = 'nz_impound_vehicle'
local targetAdded = false
local staffCache = { at = -10000, value = false }

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function enrich(data)
  if type(data) == 'table' and NZ.Veh and NZ.Veh.enrichDeep then
    local ok, res = pcall(NZ.Veh.enrichDeep, data)
    if ok and res ~= nil then return res end
  end
  return data
end

local function findByPlate(list, plate)
  plate = NZ.Utils.plate(plate)
  if not plate or type(list) ~= 'table' then return nil end
  for _, v in pairs(list) do
    if type(v) == 'table' and NZ.Utils.plate(v.plate) == plate then return v end
  end
  return nil
end

local function rulesMatch(rules, job)
  if type(rules) ~= 'table' or type(job) ~= 'table' or type(job.name) ~= 'string' then return false end
  local grade = tonumber(job.grade) or 0
  for _, rule in pairs(rules) do
    if type(rule) == 'table' and rule.name == job.name and grade >= (tonumber(rule.minGrade) or 0) then
      return true
    end
  end
  return false
end

local function vehicleLabel(model)
  if NZ.Veh and NZ.Veh.label then
    local ok, label = pcall(NZ.Veh.label, model)
    if ok and type(label) == 'string' and label ~= '' then return label end
  end
  return L('Vehicle')
end

---------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------

--- Whether the player's job may impound vehicles (matches any impound location's jobs).
--- Cached for one second because target resources call it very often.
---@return boolean
function Impound.isStaff()
  local now = GetGameTimer()
  if now - staffCache.at < 1000 then return staffCache.value end
  local value = false
  local job = NZ.State.job
  if type(job) == 'table' then
    for _, loc in pairs(NZ.State.locations or {}) do
      if type(loc) == 'table' and loc.kind == 'impound' and loc.enabled ~= false and rulesMatch(loc.jobs, job) then
        value = true
        break
      end
    end
  end
  staffCache = { at = now, value = value }
  return value
end

--- Replace the cached ImpoundOpenData (after refresh / release).
---@param data table
function Impound.setData(data)
  if ctx and type(data) == 'table' then ctx.data = data end
end

--- The last opened impound context { locationId, location, data } or nil.
function Impound.current()
  return ctx
end

local function doOpen(locationId)
  local result = NZ.NUI.await('nz:impound:open', { locationId = locationId })
  if not result.ok then
    NZ.NUI.notify('error', result.error)
    return false
  end
  local data = enrich(result.data)
  if type(data) ~= 'table' then
    NZ.NUI.notify('error', L('Something went wrong'))
    return false
  end
  local id = locationId
  if id == nil and type(data.impound) == 'table' then id = data.impound.id end
  ctx = {
    locationId = id,
    location = NZ.Garage.locationView(id) or (type(data.impound) == 'table' and NZ.Garage.locationView(data.impound.id)) or nil,
    data = data,
  }
  NZ.NUI.open('impound', data)
  return true
end

--- Open the impound menu at an impound location.
---@param locationId number
---@return boolean
function Impound.open(locationId)
  if opening then return false end
  opening = true
  local ok, res = pcall(doOpen, locationId)
  opening = false
  if not ok then
    lib.print.error(('[nayzeee-garages] open impound failed: %s'):format(res))
    NZ.NUI.notify('error', L('Something went wrong'))
    return false
  end
  return res == true
end

local function closestVehicle()
  local ped = cache.ped
  local vehicle = lib.getClosestVehicle(GetEntityCoords(ped), 6.0, false)
  if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then return vehicle end
  local own = GetVehiclePedIsIn(ped, false)
  if own ~= 0 then return own end
  return nil
end

local function doOpenForm(vehicle)
  if type(vehicle) ~= 'number' or vehicle == 0 or not DoesEntityExist(vehicle) then
    vehicle = closestVehicle()
  end
  if not vehicle then
    NZ.NUI.notify('error', L('No vehicle nearby'))
    return false
  end
  local plate = NZ.Utils.trim(GetVehicleNumberPlateText(vehicle) or '')
  if not plate or plate == '' then
    NZ.NUI.notify('error', L('This vehicle has no plate'))
    return false
  end
  local netId = nil
  if NetworkGetEntityIsNetworked(vehicle) then netId = NetworkGetNetworkIdFromEntity(vehicle) end

  local result = NZ.NUI.await('nz:impound:formData', { plate = plate, netId = netId })
  if not result.ok then
    NZ.NUI.notify('error', result.error)
    return false
  end
  local data = type(result.data) == 'table' and result.data or {}
  data.label = vehicleLabel(GetEntityModel(vehicle))
  if data.plate == nil then data.plate = plate end
  if data.netId == nil then data.netId = netId end
  NZ.NUI.open('impoundForm', data)
  return true
end

--- Open the impound form for `vehicle`, or the closest vehicle within 6 m.
---@param vehicle integer|nil
---@return boolean
function Impound.openForm(vehicle)
  if formBusy then return false end
  formBusy = true
  local ok, res = pcall(doOpenForm, vehicle)
  formBusy = false
  if not ok then
    lib.print.error(('[nayzeee-garages] impound form failed: %s'):format(res))
    NZ.NUI.notify('error', L('Something went wrong'))
    return false
  end
  return res == true
end

--- Register the "Impound vehicle" target option (once, when a target resource exists).
function Impound.setupTarget()
  if targetAdded then return end
  if type(NZ.Target.available) ~= 'function' or not NZ.Target.available() then return end
  local ok, err = pcall(NZ.Target.addVehicleOption, targetOptionId, {
    label = L('Impound vehicle'),
    icon = 'fas fa-truck-pickup',
    onSelect = function(arg)
      local entity = type(arg) == 'table' and arg.entity or arg
      if type(entity) ~= 'number' or entity == 0 or not DoesEntityExist(entity) then entity = nil end
      CreateThread(function() Impound.openForm(entity) end)
    end,
    canInteract = function()
      return NZ.State.ready == true and Impound.isStaff()
    end,
  })
  if ok then
    targetAdded = true
  else
    lib.print.warn(('[nayzeee-garages] impound target option failed: %s'):format(err))
  end
end

---------------------------------------------------------------------------------------
-- NUI callbacks
---------------------------------------------------------------------------------------

NZ.NUI.register('impound:retrieve', function(data)
  if not ctx then return NZ.Utils.fail(L('Vehicle not found')) end
  if not ctx.location then return NZ.Utils.fail(L('This impound is not available here')) end
  local plate = NZ.Utils.plate(data.plate)
  if not plate then return NZ.Utils.fail(L('Vehicle not found')) end
  local vehicle = findByPlate(ctx.data and ctx.data.vehicles, plate)
  if not vehicle then
    local refreshed = NZ.NUI.await('nz:impound:refresh', {})
    if refreshed.ok then
      Impound.setData(enrich(refreshed.data))
      vehicle = findByPlate(ctx.data and ctx.data.vehicles, plate)
    end
  end
  if not vehicle then return NZ.Utils.fail(L('Vehicle not found')) end
  return NZ.Garage.retrieve(vehicle.plate or data.plate, {
    hash = vehicle.hash,
    location = ctx.location,
    callback = 'nz:impound:retrieve',
    app = 'impound',
  })
end)

---------------------------------------------------------------------------------------
-- Events, exports, cleanup
---------------------------------------------------------------------------------------

RegisterNetEvent('nz:client:impoundForm', function()
  Impound.openForm(nil)
end)

exports('OpenImpound', function(locationId)
  CreateThread(function()
    local id = locationId
    if id == nil then
      local loc = NZ.Points.nearestLocation(function(l) return l.kind == 'impound' end)
      if not loc then
        NZ.NUI.notify('error', L('You are not near an impound'))
        return
      end
      id = loc.id
    end
    Impound.open(id)
  end)
  return true
end)

exports('OpenImpoundForm', function()
  CreateThread(function() Impound.openForm(nil) end)
  return true
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= NZ.ResourceName or not targetAdded then return end
  pcall(NZ.Target.remove, targetOptionId)
end)
