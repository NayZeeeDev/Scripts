--[[
  nayzeee-garages — job & spawner vehicles (NZ.JobsClient).
  Spawner flow behind the garage app's 'garage:spawner' callback, livery / extras /
  max-mods application and the vehicle setup app ('setup') shown after a job spawn.
]]

local Jobs = NZ.JobsClient

local setup = nil        -- { vehicle, mode = 'livery'|'mod'|nil } while the setup app is open
local spawning = false
local PERFORMANCE_MODS = { 11, 12, 13, 15, 16 } -- engine, brakes, transmission, suspension, armour

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function validVehicle(vehicle)
  return type(vehicle) == 'number' and vehicle ~= 0 and DoesEntityExist(vehicle)
end

--- Ask for network control so mod natives apply to a server-created entity.
local function ensureControl(vehicle, timeout)
  if not NetworkGetEntityIsNetworked(vehicle) or NetworkHasControlOfEntity(vehicle) then return true end
  NetworkRequestControlOfEntity(vehicle)
  local limit = GetGameTimer() + (timeout or 1000)
  while not NetworkHasControlOfEntity(vehicle) and GetGameTimer() < limit do
    Wait(25)
    NetworkRequestControlOfEntity(vehicle)
  end
  return NetworkHasControlOfEntity(vehicle)
end

local function textLabel(key)
  if type(key) ~= 'string' or key == '' then return nil end
  local text = GetLabelText(key)
  if type(text) ~= 'string' or text == '' or text == 'NULL' then return nil end
  return text
end

local function vehicleLabel(vehicle)
  if NZ.Veh and NZ.Veh.label then
    local ok, label = pcall(NZ.Veh.label, GetEntityModel(vehicle))
    if ok and type(label) == 'string' and label ~= '' then return label end
  end
  return L('Vehicle')
end

--- Livery list of a vehicle: list, mode ('livery' | 'mod' | nil), current index.
local function readLiveries(vehicle)
  local list = {}
  local count = GetVehicleLiveryCount(vehicle)
  if count and count > 0 then
    for i = 0, count - 1 do
      list[#list + 1] = { index = i, label = textLabel(GetLiveryName(vehicle, i)) or L('Livery {n}', { n = i + 1 }) }
    end
    return list, 'livery', GetVehicleLivery(vehicle)
  end
  SetVehicleModKit(vehicle, 0)
  local mods = GetNumVehicleMods(vehicle, 48)
  if mods and mods > 0 then
    list[1] = { index = -1, label = L('Default') }
    for i = 0, mods - 1 do
      list[#list + 1] = { index = i, label = textLabel(GetModTextLabel(vehicle, 48, i)) or L('Livery {n}', { n = i + 1 }) }
    end
    return list, 'mod', GetVehicleMod(vehicle, 48)
  end
  return list, nil, -1
end

local function readExtras(vehicle)
  local list = {}
  for id = 0, 20 do
    if DoesExtraExist(vehicle, id) then
      local on = IsVehicleExtraTurnedOn(vehicle, id)
      list[#list + 1] = { id = id, enabled = on == true or on == 1 }
    end
  end
  return list
end

local function finishSetup()
  local current = setup
  setup = nil
  if current and validVehicle(current.vehicle) then
    FreezeEntityPosition(current.vehicle, false)
  end
end

--- Vehicle of the open setup app, closing the app when it no longer exists.
local function setupVehicle()
  if not setup then return nil end
  if validVehicle(setup.vehicle) then return setup.vehicle end
  finishSetup()
  NZ.NUI.close('setup')
  return nil
end

---------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------

--- Apply a spawner vehicle's livery, extras and max performance mods.
---@param vehicle integer
---@param info table|nil { livery = -1|n, extras = { ['1'] = true }, maxMods = boolean }
function Jobs.applyMods(vehicle, info)
  if not validVehicle(vehicle) or type(info) ~= 'table' then return end
  ensureControl(vehicle)

  local livery = tonumber(info.livery)
  if livery and livery >= 0 then
    livery = math.floor(livery)
    local count = GetVehicleLiveryCount(vehicle)
    if count and count > 0 then
      if livery < count then SetVehicleLivery(vehicle, livery) end
    else
      SetVehicleModKit(vehicle, 0)
      if livery < GetNumVehicleMods(vehicle, 48) then SetVehicleMod(vehicle, 48, livery, false) end
    end
  end

  if type(info.extras) == 'table' then
    for key, value in pairs(info.extras) do
      local id, enabled = tonumber(key), value
      if type(value) == 'table' then id, enabled = tonumber(value.id), value.enabled end
      if id and id >= 0 and id <= 20 and DoesExtraExist(vehicle, id) then
        SetVehicleExtra(vehicle, math.floor(id), not enabled)
      end
    end
  end

  if info.maxMods then
    SetVehicleModKit(vehicle, 0)
    for i = 1, #PERFORMANCE_MODS do
      local modType = PERFORMANCE_MODS[i]
      local count = GetNumVehicleMods(vehicle, modType)
      if count and count > 0 then SetVehicleMod(vehicle, modType, count - 1, false) end
    end
    ToggleVehicleMod(vehicle, 18, true)
  end
end

--- Open the vehicle setup app (liveries / extras) with the player in the frozen vehicle.
--- Returns false when the vehicle has nothing to configure.
---@param vehicle integer
---@param info table|nil { label? }
---@return boolean
function Jobs.openSetup(vehicle, info)
  if not validVehicle(vehicle) then return false end
  info = type(info) == 'table' and info or {}
  if setup then finishSetup() end

  local liveries, mode, current = readLiveries(vehicle)
  local extras = readExtras(vehicle)
  if #liveries <= 1 and #extras == 0 then return false end

  local ped = cache.ped
  if GetVehiclePedIsIn(ped, false) ~= vehicle then
    TaskWarpPedIntoVehicle(ped, vehicle, -1)
  end
  ensureControl(vehicle)
  FreezeEntityPosition(vehicle, true)
  setup = { vehicle = vehicle, mode = mode }

  local label = type(info.label) == 'string' and info.label ~= '' and info.label or vehicleLabel(vehicle)
  NZ.NUI.open('setup', {
    label = label,
    liveries = liveries,
    livery = tonumber(current) or -1,
    extras = extras,
  })
  return true
end

local function findSpawnerEntry(list, index)
  if type(list) ~= 'table' then return nil end
  for _, entry in pairs(list) do
    if type(entry) == 'table' and tonumber(entry.index) == index then return entry end
  end
  return list[index]
end

local function spawnAndSetup(data, point, entry, location)
  local src = type(data.vehicle) == 'table' and data.vehicle or data
  local info = (type(data.info) == 'table' and data.info) or (type(data.spawner) == 'table' and data.spawner) or data
  local extra = {
    hash = tonumber(src.hash) or tonumber(entry.hash),
    model = src.model or entry.model,
    plate = src.plate or data.plate,
  }
  if src.fuel == nil then extra.fuel = 100 end

  local vehicle = NZ.Garage.spawnFromServer(data, point, extra)
  if not vehicle then return end
  Jobs.applyMods(vehicle, info)

  local setupMenu
  if info.setupMenu ~= nil then
    setupMenu = info.setupMenu == true
  else
    setupMenu = type(location) == 'table' and location.kind == 'job' and location.setupMenu ~= false
  end
  if setupMenu then
    local label = type(info.label) == 'string' and info.label ~= '' and info.label or entry.label
    Jobs.openSetup(vehicle, { label = label })
  end
end

--- Spawn spawner vehicle `index` of the open garage (job / public spawner).
---@param index number SpawnerVehicleView.index
---@return table result
function Jobs.spawn(index)
  index = tonumber(index)
  local ctx = NZ.Garage.current()
  if not index or not ctx or not ctx.location then return NZ.Utils.fail(L('Vehicle not found')) end
  if spawning then return NZ.Utils.fail(L('Please wait')) end
  local entry = findSpawnerEntry(ctx.data and ctx.data.spawner, index)
  if not entry then return NZ.Utils.fail(L('Vehicle not found')) end
  local hash = tonumber(entry.hash) or (type(entry.model) == 'string' and joaat(entry.model)) or nil
  if not hash then return NZ.Utils.fail(L('Vehicle not found')) end

  local spawnIndex, point = NZ.Garage.findSpawn(ctx.location)
  if not spawnIndex then return NZ.Utils.fail(L('All parking spots are occupied')) end

  spawning = true
  local result = NZ.NUI.await('nz:garage:spawner', {
    index = index,
    spawnIndex = spawnIndex,
    entityType = NZ.Veh.entityTypeOf(hash),
  })
  if not result.ok or type(result.data) ~= 'table' then
    spawning = false
    if result.ok then return NZ.Utils.fail(L('Something went wrong')) end
    return result
  end

  NZ.NUI.close('garage')
  local location = ctx.location
  CreateThread(function()
    local ok, err = pcall(spawnAndSetup, result.data, point, entry, location)
    if not ok then
      lib.print.error(('[nayzeee-garages] spawner vehicle failed: %s'):format(err))
      NZ.NUI.notify('error', L('The vehicle could not be spawned'))
    end
    spawning = false
  end)
  return NZ.Utils.ok(nil)
end

---------------------------------------------------------------------------------------
-- NUI callbacks
---------------------------------------------------------------------------------------

NZ.NUI.register('setup:livery', function(data)
  local vehicle = setupVehicle()
  if not vehicle then return NZ.Utils.fail(L('Vehicle not found')) end
  local index = tonumber(data.index)
  if not index then return NZ.Utils.fail(L('Something went wrong')) end
  index = math.floor(index)
  local mode = setup.mode
  ensureControl(vehicle, 500)
  if mode == 'livery' then
    SetVehicleLivery(vehicle, index)
  elseif mode == 'mod' then
    SetVehicleModKit(vehicle, 0)
    SetVehicleMod(vehicle, 48, index, false)
  else
    return NZ.Utils.fail(L('This vehicle has no liveries'))
  end
  return NZ.Utils.ok(nil)
end)

NZ.NUI.register('setup:extra', function(data)
  local vehicle = setupVehicle()
  if not vehicle then return NZ.Utils.fail(L('Vehicle not found')) end
  local id = tonumber(data.id)
  if not id or id < 0 or id > 20 or not DoesExtraExist(vehicle, math.floor(id)) then
    return NZ.Utils.fail(L('Something went wrong'))
  end
  ensureControl(vehicle, 500)
  SetVehicleExtra(vehicle, math.floor(id), not data.enabled)
  -- Some extras switch each other off: send the real state back.
  NZ.NUI.send('update', { app = 'setup', data = { extras = readExtras(vehicle) } })
  return NZ.Utils.ok(nil)
end)

NZ.NUI.register('setup:drive', function()
  finishSetup()
  NZ.NUI.close('setup')
  return NZ.Utils.ok(nil)
end)

-- Closing the setup app (Escape / close button) behaves like "Drive".
NZ.NUI.onClose('setup', function()
  finishSetup()
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= NZ.ResourceName then return end
  if setup and validVehicle(setup.vehicle) then
    FreezeEntityPosition(setup.vehicle, false)
  end
end)
