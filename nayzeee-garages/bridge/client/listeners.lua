--[[
  nayzeee-garages — listener file (client): other key scripts' client events and exports.
  docs/CARLOCK.md §5. Open file: add your own mappings at the bottom.

  Only with Config.CarLock.enabled + Config.CarLock.compat, and only for key resources that
  are NOT running (a resource that starts later takes its names back). Everything that gives
  a key goes to the server ('nz:carlock:compat'), which only ever grants a TEMPORARY key of a
  vehicle the player sits in / stands next to (never another player's owned vehicle; NPC
  traffic only with Config.CarLock.compatAmbient). Synchronous "has key" exports answer from
  the local key cache (NZ.CarLock.hasKeyFast).

  Events handled: vehiclekeys:client:SetOwner, qb-vehiclekeys:client:AddKeys / RemoveKeys /
  GiveKeys / ToggleEngine, lockpicks:UseLockpick (-> NZ.CarLock.onLockpickEvent),
  cd_garage:AddKeys / RemoveKeys.
  Export shims (Config.CarLock.compatExports): qb-vehiclekeys, qbx_vehiclekeys,
  wasabi_carlock, MrNewbVehicleKeys, qs-vehiclekeys, Renewed-Vehiclekeys, vehicles_keys.
]]

local CarLock = NZ.CarLock
local Utils = NZ.Utils

local PLATE_WAIT_MS = 2000     -- a script fires SetOwner right after spawning: wait for the entity
local SEARCH_RADIUS = 50.0

local ALIASES = {
  'qb-vehiclekeys', 'qbx_vehiclekeys', 'wasabi_carlock', 'MrNewbVehicleKeys', 'qs-vehiclekeys',
  'Renewed-Vehiclekeys', 'vehicles_keys', 'cd_garage',
}
local ALSO_SERVED_BY = { ['qb-vehiclekeys'] = 'qbx_vehiclekeys' }

local on = {}
local exportsOf = {}
local handles = {}

local function compatOn() return CarLock.compatEnabled() end
local function exportsOn() return compatOn() and CarLock.cfg().compatExports ~= false end

local function realRunning(alias)
  if GetResourceState(alias) == 'started' then return true end
  local other = ALSO_SERVED_BY[alias]
  return other ~= nil and GetResourceState(other) == 'started'
end

for _, alias in ipairs(ALIASES) do
  on[alias] = compatOn() and not realRunning(alias)
end

local function addShims(alias)
  if not exportsOn() or handles[alias] then return end
  local list = {}
  for name, fn in pairs(exportsOf[alias] or {}) do
    list[#list + 1] = AddEventHandler(('__cfx_export_%s_%s'):format(alias, name), function(setCB)
      setCB(fn)
    end)
  end
  handles[alias] = list
end

local function removeShims(alias)
  for _, h in ipairs(handles[alias] or {}) do RemoveEventHandler(h) end
  handles[alias] = nil
end

local function provideExports(alias, map)
  exportsOf[alias] = map
  if on[alias] then addShims(alias) end
end

local function onEvent(alias, name, fn)
  RegisterNetEvent(name, function(...)
    if not on[alias] then return end
    local ok, err = pcall(fn, ...)
    if not ok then Utils.debug(('carlock compat %s failed: %s'):format(name, tostring(err))) end
  end)
end

AddEventHandler('onClientResourceStart', function(resource)
  if resource == NZ.ResourceName then return end
  for alias, other in pairs(ALSO_SERVED_BY) do
    if other == resource then on[alias] = false removeShims(alias) end
  end
  if on[resource] then
    on[resource] = false
    removeShims(resource)
  end
end)

AddEventHandler('onClientResourceStop', function(resource)
  if resource == NZ.ResourceName or not compatOn() then return end
  for _, alias in ipairs(ALIASES) do
    if (alias == resource or ALSO_SERVED_BY[alias] == resource) and on[alias] == false then
      SetTimeout(1000, function()
        if on[alias] == false and not realRunning(alias) then
          on[alias] = true
          addShims(alias)
        end
      end)
    end
  end
end)

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function isVehicle(vehicle)
  return type(vehicle) == 'number' and vehicle ~= 0 and DoesEntityExist(vehicle) and IsEntityAVehicle(vehicle)
end

local function netIdOf(vehicle)
  if not isVehicle(vehicle) or not NetworkGetEntityIsNetworked(vehicle) then return nil end
  local id = NetworkGetNetworkIdFromEntity(vehicle)
  return id ~= 0 and id or nil
end

local function plateText(vehicle)
  return Utils.plate(GetVehicleNumberPlateText(vehicle))
end

--- Nearest vehicle wearing `plate` (plate text or real plate), the one we sit in first.
local function vehicleByPlate(plate)
  local wanted = Utils.plate(type(plate) == 'number' and tostring(plate) or plate)
  if not wanted then return nil end
  local ped = PlayerPedId()
  local current = GetVehiclePedIsIn(ped, false)
  if current ~= 0 and (plateText(current) == wanted or CarLock.plateOf(current) == wanted) then return current end
  local coords = GetEntityCoords(ped)
  local best, bestDist = nil, SEARCH_RADIUS
  for _, vehicle in ipairs(GetGamePool('CVehicle')) do
    if plateText(vehicle) == wanted or CarLock.plateOf(vehicle) == wanted then
      local dist = #(GetEntityCoords(vehicle) - coords)
      if dist <= bestDist then best, bestDist = vehicle, dist end
    end
  end
  return best
end

local function request(payload)
  lib.callback('nz:carlock:compat', false, function(res)
    if type(res) == 'table' and res.ok == false then
      Utils.debug(('carlock compat %s refused: %s'):format(tostring(payload.action), tostring(res.error)))
    end
  end, payload)
end

--- Temporary key for the vehicle wearing `plate` (or `vehicle`), validated by the server.
local function acquire(plate, vehicle)
  CreateThread(function()
    local deadline = GetGameTimer() + PLATE_WAIT_MS
    local target = isVehicle(vehicle) and vehicle or nil
    while true do
      target = target or vehicleByPlate(plate)
      if target and netIdOf(target) then break end
      if GetGameTimer() >= deadline then break end
      Wait(150)
      if target and not isVehicle(target) then target = nil end
    end
    local payload = { action = 'acquire', plate = Utils.plate(plate) }
    if target then
      payload.netId = netIdOf(target)
      payload.plate = payload.plate or plateText(target)
    end
    if not payload.netId and not payload.plate then return end
    request(payload)
  end)
  return true
end

local function release(plate, vehicle)
  local payload = { action = 'remove', plate = Utils.plate(plate), netId = netIdOf(vehicle) }
  if not payload.plate and isVehicle(vehicle) then payload.plate = plateText(vehicle) end
  if payload.plate or payload.netId then request(payload) end
  return true
end

-- HUD / ignition scripts poll these synchronously (sometimes every frame): the key cache
-- answers first; the world is searched for that plate at most once per second.
local SCAN_EVERY_MS = 1000
local lastScan = {}           -- [plate] = GetGameTimer() of the last pool scan

local function hasPlate(plate)
  local wanted = Utils.plate(type(plate) == 'number' and tostring(plate) or plate)
  if not wanted then return false end
  local cached = CarLock.cachedKey(wanted)
  if cached ~= nil then return cached end
  local t = GetGameTimer()
  if lastScan[wanted] and t - lastScan[wanted] < SCAN_EVERY_MS then return CarLock.hasKeyFast(wanted) end
  lastScan[wanted] = t
  if math.random(1, 20) == 1 then
    for p, at in pairs(lastScan) do
      if t - at > SCAN_EVERY_MS then lastScan[p] = nil end
    end
  end
  local vehicle = vehicleByPlate(wanted)
  if vehicle then return CarLock.hasKeyFast(vehicle) end
  return CarLock.hasKeyFast(wanted)
end

local function hasVehicle(vehicle)
  if not isVehicle(vehicle) then return false end
  return CarLock.hasKeyFast(vehicle)
end

local function guarded(fn, fallback)
  return function(...)
    local res = table.pack(pcall(fn, ...))
    if not res[1] then return fallback end
    return table.unpack(res, 2, res.n)
  end
end

---------------------------------------------------------------------------------------
-- Client events (sent by other scripts with TriggerEvent / TriggerClientEvent)
---------------------------------------------------------------------------------------

onEvent('qb-vehiclekeys', 'vehiclekeys:client:SetOwner', function(plate) acquire(plate) end)
onEvent('qb-vehiclekeys', 'qb-vehiclekeys:client:AddKeys', function(plate) acquire(plate) end)
onEvent('qb-vehiclekeys', 'qb-vehiclekeys:client:RemoveKeys', function(plate) release(plate) end)

-- give a key of the vehicle we are in / next to: to `id`, else the closest player
onEvent('qb-vehiclekeys', 'qb-vehiclekeys:client:GiveKeys', function(id)
  local ped = PlayerPedId()
  local vehicle = GetVehiclePedIsIn(ped, false)
  if vehicle == 0 then vehicle = lib.getClosestVehicle(GetEntityCoords(ped), CarLock.range('compat'), false) or 0 end
  local netId = netIdOf(vehicle)
  if not netId then return end
  local target = tonumber(id)
  if not target then
    local player = lib.getClosestPlayer(GetEntityCoords(ped), CarLock.range('give'), false)
    target = player and GetPlayerServerId(player) or nil
  end
  if target then request({ action = 'lend', netId = netId, target = target }) end
end)

onEvent('qb-vehiclekeys', 'qb-vehiclekeys:client:ToggleEngine', function()
  if type(CarLock.toggleEngine) == 'function' then CreateThread(function() CarLock.toggleEngine() end) end
end)

-- qb-smallresources' lockpick item fires this on the user's client (house / store robberies
-- listen too). While qb-vehiclekeys is not running, a locked vehicle nearby is the car lock's
-- (client/carlock/crime.lua provides NZ.CarLock.onLockpickEvent(isAdvanced)).
onEvent('qb-vehiclekeys', 'lockpicks:UseLockpick', function(isAdvanced)
  if type(CarLock.onLockpickEvent) == 'function' then
    CreateThread(function() CarLock.onLockpickEvent(isAdvanced == true) end)
  end
end)

onEvent('cd_garage', 'cd_garage:AddKeys', function(plate) acquire(plate) end)
onEvent('cd_garage', 'cd_garage:RemoveKeys', function(plate) release(plate) end)

---------------------------------------------------------------------------------------
-- Client export shims
---------------------------------------------------------------------------------------

provideExports('qb-vehiclekeys', {
  -- qb-core calls this synchronously and expects true or nil
  HasKeys = guarded(function(plate) return hasPlate(plate) or nil end, nil),
  addNoLockVehicles = function() end,
  removeNoLockVehicles = function() end,
})

provideExports('qbx_vehiclekeys', {
  HasKeys = guarded(function(vehicle)
    if vehicle == nil then vehicle = GetVehiclePedIsIn(PlayerPedId(), false) end
    return hasVehicle(vehicle)
  end, false),
})

provideExports('wasabi_carlock', {
  GiveKey = guarded(function(plate) return acquire(plate) end, false),
  RemoveKey = guarded(function(plate) return release(plate) end, false),
  HasKey = guarded(function(plate) return hasPlate(plate) end, false),
  GetAllKeys = guarded(function() return CarLock.keyPlates() end, {}),
})

provideExports('MrNewbVehicleKeys', {
  GiveKeysByPlate = guarded(function(plate) return acquire(plate) end, false),
  RemoveKeysByPlate = guarded(function(plate) return release(plate) end, false),
  HasKeysByPlate = guarded(function(plate) return hasPlate(plate) end, false),
  GiveKeys = guarded(function(vehicle) return isVehicle(vehicle) and acquire(nil, vehicle) or false end, false),
  RemoveKeys = guarded(function(vehicle) return isVehicle(vehicle) and release(nil, vehicle) or false end, false),
  HaveKeys = guarded(function(vehicle) return hasVehicle(vehicle) end, false),
  GetPlayerKeyList = guarded(function() return CarLock.keyPlates() end, {}),
})

provideExports('qs-vehiclekeys', {
  GiveKeys = guarded(function(plate) return acquire(plate) end, false),
  RemoveKeys = guarded(function(plate) return release(plate) end, false),
  GetKey = guarded(function(plate) return hasPlate(plate) end, false),
  -- qs removes the keys of the vehicle you just left on its own: temporary keys here expire
  RemoveKeysAuto = function() return true end,
})

provideExports('Renewed-Vehiclekeys', {
  addKey = guarded(function(plate) return acquire(plate) end, false),
  removeKey = guarded(function(plate) return release(plate) end, false),
  hasKey = guarded(function(plate) return hasPlate(plate) end, false),
})

provideExports('vehicles_keys', {
  doesPlayerOwnPlate = guarded(function(plate) return hasPlate(plate) end, false),
  getOwnedVehiclePlates = guarded(function() return CarLock.keyPlates() end, {}),
  toggleClosestVehicleLock = guarded(function()
    CreateThread(function() CarLock.toggleLock() end)
    return true
  end, false),
})

---------------------------------------------------------------------------------------
-- Your own mappings: onEvent('<alias of ALIASES>', '<event>', function(...) end) with
-- acquire(plate, vehicle) / release(plate, vehicle), provideExports('<alias>', { ... }).
---------------------------------------------------------------------------------------
