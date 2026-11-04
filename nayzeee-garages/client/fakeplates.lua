--[[
  nayzeee-garages — fake plates (client): NZ.FakePlates. docs/CARLOCK.md §13.

  Target options at the rear of every vehicle: "Install fake plate" (fake_plate item, plus the
  screwdriver when Config.FakePlates.requireScrewdriver) and "Remove fake plate" (vehicles
  whose replicated 'nzFakePlate' state bag is set). Using the fake_plate item works without
  a target resource: the vehicle whose rear you stand at gets the plate (or loses its fake
  plate after a confirmation).

  The client only shows the work: 'nz:fakeplates:start' (the server checks everything and
  starts its own timer) -> progress circle + animation -> 'nz:fakeplates:finish' { token }
  (or { token, cancel = true }). The item checks here only hide options; the server decides.
  External key resource keyed on the plate text: the finish result says `keys` when this player
  may keep keys (access to the real registration); 'nz:client:fakeplates:keys' gives the owner
  of a car someone else fitted a fake plate to keys for the new text.
]]

local FakePlates = NZ.FakePlates

local INSTALL_ID = 'nz:fakeplate:install'
local REMOVE_ID = 'nz:fakeplate:remove'
local REAR_BONES = { 'platelight', 'bumper_r', 'boot' }
local NO_PLATE_CLASSES = { [13] = true, [14] = true, [15] = true, [16] = true, [21] = true }
local SEARCH_RADIUS = 7.0
local BEHIND_SIDE = 1.5            -- m off the long axis (server: 1.6)
local BEHIND_COS = 0.55            -- cosine of the angle behind the centre (server: 0.5 = 60 degrees)

local busy = false
local targetsAdded = false

local function cfg()
  local c = type(Config.FakePlates) == 'table' and Config.FakePlates or {}
  local anim = type(c.animation) == 'table' and c.animation or {}
  local distance = tonumber(c.distance) or 2.0
  return {
    enabled = c.enabled ~= false,
    requireScrewdriver = c.requireScrewdriver ~= false,
    distance = math.max(1.0, math.min(5.0, distance)),
    dict = type(anim.dict) == 'string' and anim.dict or 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@',
    clip = type(anim.clip) == 'string' and anim.clip or 'machinic_loop_mechandplayer',
  }
end

local function itemName(key)
  if NZ.CarLock and type(NZ.CarLock.itemName) == 'function' then
    local ok, name = pcall(NZ.CarLock.itemName, key)
    if ok and type(name) == 'string' and name ~= '' then return name end
  end
  return key == 'screwdriver' and 'screwdriver' or 'fake_plate'
end

local function hasItem(key)
  local ok, has = pcall(NZ.Inventory.hasItem, itemName(key), 1)
  return ok and has == true
end

local function notify(kind, message)
  if type(message) == 'string' and message ~= '' then NZ.NUI.notify(kind, message) end
end

local function isVehicle(vehicle)
  return type(vehicle) == 'number' and vehicle ~= 0 and DoesEntityExist(vehicle) and IsEntityAVehicle(vehicle)
end

--- Does this vehicle show a fake plate (replicated by the server)?
---@param vehicle number
---@return boolean
function FakePlates.wearsFake(vehicle)
  if not isVehicle(vehicle) then return false end
  local value = Entity(vehicle).state.nzFakePlate
  return type(value) == 'string' and value ~= ''
end

--- World position of the rear plate of a vehicle.
local function rearPoint(vehicle)
  for i = 1, #REAR_BONES do
    local bone = GetEntityBoneIndexByName(vehicle, REAR_BONES[i])
    if bone and bone ~= -1 then return GetWorldPositionOfEntityBone(vehicle, bone) end
  end
  local min = GetModelDimensions(GetEntityModel(vehicle))
  return GetOffsetFromEntityInWorldCoords(vehicle, 0.0, (min and min.y or -2.2) + 0.1, 0.0)
end

local function hasPlate(vehicle)
  return not NO_PLATE_CLASSES[GetVehicleClass(vehicle)]
end

--- Is `pos` behind `vehicle`: near its long axis and clearly behind its centre, not at a rear
--- corner? The server's rule (server/fakeplates.lua behind: 1.6 m, 60 degrees), a little
--- stricter here so an option the player sees is never refused for the position.
local function behindAxis(vehicle, pos)
  local off = GetOffsetFromEntityGivenWorldCoords(vehicle, pos.x, pos.y, pos.z)
  if off.y >= 0 or math.abs(off.x) > BEHIND_SIDE then return false end
  return -off.y / math.max(#vector2(off.x, off.y), 0.001) >= BEHIND_COS
end

--- Is the local player on foot at the rear of `vehicle` (Config.FakePlates.distance)?
local function atRear(vehicle, ped)
  if not isVehicle(vehicle) or IsPedInAnyVehicle(ped, false) or not hasPlate(vehicle) then return false end
  local pos = GetEntityCoords(ped)
  return #(pos - rearPoint(vehicle)) <= cfg().distance + 0.35 and behindAxis(vehicle, pos)
end

--- The vehicle whose rear the player stands at (nearest rear), or nil.
local function vehicleAtRear(ped)
  local origin = GetEntityCoords(ped)
  local ok, pool = pcall(GetGamePool, 'CVehicle')
  local best, bestDist = nil, math.huge
  for _, vehicle in ipairs(ok and pool or {}) do
    if #(GetEntityCoords(vehicle) - origin) <= SEARCH_RADIUS and hasPlate(vehicle) and behindAxis(vehicle, origin) then
      local dist = #(origin - rearPoint(vehicle))
      if dist < bestDist then best, bestDist = vehicle, dist end
    end
  end
  if best and bestDist <= cfg().distance + 0.35 then return best end
  return nil
end

local function playAnimFallback(ped, settings, duration)
  local loaded = pcall(lib.requestAnimDict, settings.dict, 2000)
  if loaded then TaskPlayAnim(ped, settings.dict, settings.clip, 3.0, 3.0, -1, 1, 0, false, false, false) end
  local deadline = GetGameTimer() + duration
  while GetGameTimer() < deadline do
    if IsPedRagdoll(ped) or IsEntityDead(ped) or IsPedInAnyVehicle(ped, false) then
      ClearPedTasks(ped)
      return false
    end
    Wait(100)
  end
  ClearPedTasks(ped)
  if loaded then RemoveAnimDict(settings.dict) end
  return true
end

--- Show the work for `duration` ms. Returns true when it was not cancelled.
local function progress(label, duration)
  local settings = cfg()
  local ped = PlayerPedId()
  if type(lib.progressCircle) == 'function' then
    local ok, done = pcall(lib.progressCircle, {
      duration = duration,
      label = label,
      position = 'bottom',
      useWhileDead = false,
      canCancel = true,
      disable = { move = true, car = true, combat = true },
      anim = { dict = settings.dict, clip = settings.clip, flag = 1 },
    })
    if ok then return done == true end
  end
  return playAnimFallback(ped, settings, duration)
end

--- Install or remove a fake plate on `vehicle` (the server checks and times everything).
---@param action 'install'|'remove'
---@param vehicle number
function FakePlates.run(action, vehicle)
  if busy or not isVehicle(vehicle) then return end
  if not NetworkGetEntityIsNetworked(vehicle) then
    notify('error', L('This vehicle has no plate to change'))
    return
  end
  busy = true
  local ok, err = pcall(function()
    local ped = PlayerPedId()
    local started = NZ.NUI.await('nz:fakeplates:start', {
      netId = NetworkGetNetworkIdFromEntity(vehicle), action = action,
    })
    if not started.ok or type(started.data) ~= 'table' then
      notify('error', started.error)
      return
    end
    local point = rearPoint(vehicle)
    TaskTurnPedToFaceCoord(ped, point.x, point.y, point.z, 700)
    Wait(600)
    local label = action == 'install' and L('Installing the fake plate...') or L('Removing the fake plate...')
    local duration = math.floor(tonumber(started.data.duration) or 5000)
    local done = progress(label, duration)
    local result = NZ.NUI.await('nz:fakeplates:finish', { token = started.data.token, cancel = not done })
    if not done then
      notify('info', L('Cancelled'))
    elseif not result.ok then
      notify('error', result.error)
    elseif action == 'install' then
      local data = type(result.data) == 'table' and result.data or {}
      -- external key resource keyed on the plate text: keep the keys of a car you may use
      if data.keys == true and type(data.plate) == 'string' then pcall(NZ.Keys.give, vehicle, data.plate) end
      notify('success', L('Fake plate installed: {plate}', { plate = data.plate or '' }))
    else
      notify('success', L('Fake plate removed: the vehicle shows {plate} again', {
        plate = type(result.data) == 'table' and result.data.plate or '',
      }))
    end
  end)
  busy = false
  if not ok then lib.print.error(('[nayzeee-garages] fake plate: %s'):format(tostring(err))) end
end

-- fake_plate item used (server -> 'nz:client:fakeplates:use')
RegisterNetEvent('nz:client:fakeplates:use', function()
  if busy then return end
  local ped = PlayerPedId()
  if IsPedInAnyVehicle(ped, false) then
    notify('error', L('Get out of the vehicle first'))
    return
  end
  local vehicle = vehicleAtRear(ped)
  if not vehicle then
    notify('error', L('Stand at the rear of a vehicle'))
    return
  end
  CreateThread(function()
    if FakePlates.wearsFake(vehicle) then
      local answer = NZ.Garage.alert({
        header = L('Remove fake plate'),
        content = L('This vehicle already wears a fake plate. Take it off?'),
        centered = true,
        cancel = true,
        labels = { confirm = L('Remove'), cancel = L('Cancel') },
      }, 20)
      NZ.NUI.syncFocus()
      if answer ~= 'confirm' then return end
      FakePlates.run('remove', vehicle)
      return
    end
    FakePlates.run('install', vehicle)
  end)
end)

-- The owner's car got a fake plate from someone else (external key resource keyed on the
-- plate text): the owner keeps keys to it.
RegisterNetEvent('nz:client:fakeplates:keys', function(data)
  if type(data) ~= 'table' or type(data.plate) ~= 'string' or data.plate == '' or #data.plate > 16 then return end
  local netId = tonumber(data.netId)
  local vehicle = (netId and NetworkDoesNetworkIdExist(netId)) and NetworkGetEntityFromNetworkId(netId) or 0
  pcall(NZ.Keys.give, vehicle, data.plate)
end)

---------------------------------------------------------------------------------------
-- Target options
---------------------------------------------------------------------------------------

local function entityOf(arg)
  local entity = type(arg) == 'table' and arg.entity or arg
  if not isVehicle(entity) then return nil end
  return entity
end

local function canWork()
  return not busy and cfg().enabled and NZ.State.ready == true
    and (not cfg().requireScrewdriver or hasItem('screwdriver'))
end

local function addTargets()
  if targetsAdded or type(NZ.Target.available) ~= 'function' or not NZ.Target.available() then return end
  if not cfg().enabled then return end
  local okInstall, added = pcall(NZ.Target.addVehicleOption, INSTALL_ID, {
    label = L('Install fake plate'),
    icon = 'fas fa-screwdriver',
    distance = 3.0,
    canInteract = function(entity)
      local vehicle = entityOf(entity)
      return vehicle ~= nil and canWork() and not FakePlates.wearsFake(vehicle)
        and atRear(vehicle, PlayerPedId()) and hasItem('fakePlate')
    end,
    onSelect = function(arg)
      local vehicle = entityOf(arg)
      if vehicle then CreateThread(function() FakePlates.run('install', vehicle) end) end
    end,
  })
  local okRemove = pcall(NZ.Target.addVehicleOption, REMOVE_ID, {
    label = L('Remove fake plate'),
    icon = 'fas fa-screwdriver',
    distance = 3.0,
    canInteract = function(entity)
      local vehicle = entityOf(entity)
      return vehicle ~= nil and canWork() and FakePlates.wearsFake(vehicle) and atRear(vehicle, PlayerPedId())
    end,
    onSelect = function(arg)
      local vehicle = entityOf(arg)
      if vehicle then CreateThread(function() FakePlates.run('remove', vehicle) end) end
    end,
  })
  targetsAdded = okInstall and added == true and okRemove
end

CreateThread(function()
  Wait(1500)
  addTargets()
end)

AddEventHandler('onClientResourceStart', function(resource)
  if resource ~= 'ox_target' and resource ~= 'qb-target' then return end
  SetTimeout(1000, addTargets)
end)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= NZ.ResourceName then return end
  if targetsAdded then
    pcall(NZ.Target.remove, INSTALL_ID)
    pcall(NZ.Target.remove, REMOVE_ID)
  end
end)
