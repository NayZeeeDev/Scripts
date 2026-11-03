--[[
  nayzeee-garages — garage menu and vehicle flows (NZ.Garage).
  Opens the garage app, retrieves ("Drive") and stores vehicles, tracking / directions,
  "Go inside", player-to-player sale offers and the OpenGarage / StoreVehicle exports.
  (docs/ARCHITECTURE.md §7.1, §7.2, §8.2)
]]

local Garage = NZ.Garage

local ctx = nil          -- { locationId, groupId, houseId, location, data } of the last opened garage
local opening = false
local storing = false

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function settingsSection(name)
  local s = NZ.State.settings
  if type(s) == 'table' and type(s[name]) == 'table' then return s[name] end
  return Config.DefaultSettings[name] or {}
end

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

--- Dead, downed, cuffed or escorted players cannot use garages (see NZ.Points.incapacitated).
local function incapacitated()
  return type(NZ.Points.incapacitated) == 'function' and NZ.Points.incapacitated() == true
end

--- lib.alertDialog that waits for a real answer. ox_lib shows one alert at a time (shared by
--- every resource) and returns nil at once while another is open, or when one is closed
--- without an answer: retry until it is answered or `seconds` have passed.
--- Returns 'confirm' | 'cancel' | nil (never answered).
---@param data table lib.alertDialog options
---@param seconds number
---@return string|nil
function Garage.alert(data, seconds)
  local deadline = GetGameTimer() + math.max(1, tonumber(seconds) or 30) * 1000
  while true do
    local left = deadline - GetGameTimer()
    if left <= 0 then return nil end
    local ok, choice = pcall(lib.alertDialog, data, left)
    if ok and (choice == 'confirm' or choice == 'cancel') then return choice end
    if GetGameTimer() >= deadline then return nil end
    Wait(500)
  end
end

local function vehicleLabel(hashOrModel)
  if hashOrModel ~= nil and NZ.Veh and NZ.Veh.label then
    local ok, label = pcall(NZ.Veh.label, hashOrModel)
    if ok and type(label) == 'string' and label ~= '' then return label end
  end
  return L('Vehicle')
end

--- Format money with the configured currency symbol and thousands separators.
---@param amount number
---@return string
function Garage.formatMoney(amount)
  local n = math.floor(tonumber(amount) or 0)
  local digits = tostring(math.abs(n))
  local grouped = (digits:reverse():gsub('(%d%d%d)', '%1,')):reverse()
  grouped = (grouped:gsub('^,', ''))
  local currency = settingsSection('interface').currency or '$'
  return (n < 0 and '-' or '') .. currency .. grouped
end

--- Find a client location view by id ('H..' strings resolve house garages).
---@param id number|string|nil
---@return table|nil
function Garage.locationView(id)
  if id == nil then return nil end
  local locations, houses = NZ.State.locations or {}, NZ.State.houses or {}
  local view = locations[id] or locations[tonumber(id) or false] or houses[id]
  if view then return view end
  if type(id) == 'string' and id:sub(1, 1) ~= 'H' then
    return houses['H' .. id]
  end
  return nil
end

--- Raw house id (as registered by the housing integration) of a house location view.
---@param location table
---@return string|nil
function Garage.houseIdOf(location)
  if type(location) ~= 'table' then return nil end
  if location.houseId ~= nil then return tostring(location.houseId) end
  local id = location.id
  if type(id) == 'string' and id:sub(1, 1) == 'H' and #id > 1 then return id:sub(2) end
  if id ~= nil then return tostring(id) end
  return nil
end

--- The last opened garage context: { locationId, groupId, houseId, location, data } or nil.
function Garage.current()
  return ctx
end

--- Replace the cached GarageOpenData (after refresh / switch group).
---@param data table GarageOpenData
function Garage.setData(data)
  if not ctx or type(data) ~= 'table' then return end
  ctx.data = data
  if type(data.garage) == 'table' then
    if data.garage.groupId ~= nil then ctx.groupId = data.garage.groupId end
    local view = Garage.locationView(data.garage.locationId)
    if view then ctx.location = view end
  end
end

--- Free spawn point of a location: index, point (nil when every spot is taken).
---@param location table
---@return integer|nil, table|nil
function Garage.findSpawn(location)
  local list = type(location) == 'table' and location.spawnPoints or nil
  if type(list) ~= 'table' or #list == 0 then return nil end
  local radius = nil
  if location.vehicleType == 'air' then
    radius = 6.0
  elseif location.vehicleType == 'sea' then
    radius = 5.0
  end
  local index, point = NZ.Veh.findFreeSpawn(list, radius)
  if not index then return nil end
  return index, point or list[index]
end

local function reportSpawned(plate, vehicle)
  if vehicle and DoesEntityExist(vehicle) and NetworkGetEntityIsNetworked(vehicle) then
    local res = NZ.NUI.await('nz:garage:spawned', { plate = plate, netId = NetworkGetNetworkIdFromEntity(vehicle) })
    if not res.ok then NZ.NUI.notify('error', res.error) end
  else
    -- Lets the server release the "out" state of a vehicle that never appeared.
    NZ.NUI.await('nz:garage:spawned', { plate = plate, failed = true })
  end
end

--- Spawn the vehicle described by a server retrieve result ({ netId?, spawn, vehicle })
--- and report it back with 'nz:garage:spawned'. `extra` overrides spawn options.
---@param data table
---@param fallbackPoint table|nil
---@param extra table|nil
---@return integer|nil vehicle
function Garage.spawnFromServer(data, fallbackPoint, extra)
  if type(data) ~= 'table' then return nil end
  local src = type(data.vehicle) == 'table' and data.vehicle or data
  local opts = {}
  for k, v in pairs(src) do opts[k] = v end
  if type(extra) == 'table' then
    for k, v in pairs(extra) do opts[k] = v end
  end
  opts.vehicle, opts.spawn, opts.info = nil, nil, nil
  opts.coords = NZ.Utils.v4(data.spawn) or NZ.Utils.v4(fallbackPoint)
  opts.netId = tonumber(data.netId) or tonumber(src.netId)
  if opts.warp == nil then opts.warp = settingsSection('vehicles').spawnOutside ~= true end
  local plate = opts.plate

  if not opts.coords then
    NZ.NUI.notify('error', L('The vehicle could not be spawned'))
    reportSpawned(plate, nil)
    return nil
  end

  local ok, vehicle = pcall(NZ.Veh.spawn, opts)
  if not ok then
    lib.print.error(('[nayzeee-garages] vehicle spawn failed: %s'):format(vehicle))
    vehicle = nil
  end
  if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then
    local shown = NZ.Veh.lastErrorShown
    if not shown or GetGameTimer() - shown > 2000 then
      NZ.NUI.notify('error', L('The vehicle could not be spawned'))
    end
    reportSpawned(plate, nil)
    return nil
  end
  reportSpawned(plate, vehicle)
  return vehicle
end

--- Retrieve flow shared by the garage and the impound (§7.1).
--- opts = { hash (required), location (spawn points), callback = 'nz:garage:retrieve', app }
---@param plate string
---@param opts table|nil
---@return table result
function Garage.retrieve(plate, opts)
  opts = type(opts) == 'table' and opts or {}
  if type(plate) ~= 'string' or plate == '' then return NZ.Utils.fail(L('Vehicle not found')) end
  if incapacitated() then return NZ.Utils.fail(L('You cannot do that right now')) end
  local location = opts.location or (ctx and ctx.location)
  if not location then return NZ.Utils.fail(L('This garage is not available here')) end
  local hash = tonumber(opts.hash)
  if not hash and ctx and ctx.data then
    local v = findByPlate(ctx.data.vehicles, plate)
    hash = v and tonumber(v.hash)
  end
  if not hash then return NZ.Utils.fail(L('Vehicle not found')) end

  local spawnIndex, point = Garage.findSpawn(location)
  if not spawnIndex then return NZ.Utils.fail(L('All parking spots are occupied')) end

  local result = NZ.NUI.await(opts.callback or 'nz:garage:retrieve', {
    plate = plate,
    spawnIndex = spawnIndex,
    entityType = NZ.Veh.entityTypeOf(hash),
  })
  if not result.ok then return result end

  if opts.app then NZ.NUI.close(opts.app) end
  CreateThread(function()
    Garage.spawnFromServer(result.data, point, { hash = hash })
  end)
  return NZ.Utils.ok(nil)
end

--- Set a waypoint to the nearest garage with free space.
--- `known` may already hold the target ({ coords, name }).
---@param payload table|nil
---@param known table|nil
---@return table result
function Garage.directions(payload, known)
  local target = known
  if type(target) ~= 'table' then
    local result = NZ.NUI.await('nz:garage:nearestWithSpace', payload or {})
    if not result.ok then return result end
    target = result.data
  end
  local coords = type(target) == 'table' and (NZ.Utils.v3(target.coords) or NZ.Utils.v3(target)) or nil
  if not coords then return NZ.Utils.fail(L('No garage with free space was found')) end
  SetNewWaypoint(coords.x + 0.0, coords.y + 0.0)
  local name = type(target.name) == 'string' and target.name or target.garageName
  if type(name) == 'string' and name ~= '' then
    NZ.NUI.notify('success', L('Waypoint set to {garage}', { garage = name }))
  else
    NZ.NUI.notify('success', L('Waypoint set'))
  end
  return NZ.Utils.ok(nil)
end

local function enterInterior(data)
  if not (NZ.Interior and NZ.Interior.enter) then return end
  local ok, err = pcall(NZ.Interior.enter, data)
  if not ok then
    lib.print.error(('[nayzeee-garages] interior enter failed: %s'):format(err))
    NZ.NUI.notify('error', L('Something went wrong'))
  end
end

--- Close the menu and enter the garage interior. Re-opens the menu on failure.
---@return table result
local function goInside()
  if incapacitated() then return NZ.Utils.fail(L('You cannot do that right now')) end
  NZ.NUI.close('garage')
  local result = NZ.NUI.await('nz:garage:goInside', {})
  if not result.ok then
    -- Re-fetch: the menu may have changed favourites / nicknames since ctx.data was cached.
    local fresh = NZ.NUI.await('nz:garage:refresh', {})
    if fresh.ok and type(fresh.data) == 'table' then
      NZ.Veh.enrichDeep(fresh.data)
      if NZ.Garage.setData then NZ.Garage.setData(fresh.data) end
      NZ.NUI.open('garage', fresh.data)
    elseif ctx and ctx.data then
      NZ.NUI.open('garage', ctx.data)
    end
    return result
  end
  CreateThread(function() enterInterior(result.data) end)
  return NZ.Utils.ok(nil)
end

local fadingTeleport = false   -- screen faded out by fadeTeleport (undone on resource stop)

local function fadeTeleport(target)
  local c = NZ.Utils.v4(target)
  if not c then return end
  fadingTeleport = true
  DoScreenFadeOut(400)
  local timeout = GetGameTimer() + 2000
  while not IsScreenFadedOut() and GetGameTimer() < timeout do Wait(10) end
  local ped = cache.ped
  RequestCollisionAtCoord(c.x, c.y, c.z)
  SetEntityCoords(ped, c.x, c.y, c.z, false, false, false, false)
  SetEntityHeading(ped, c.w)
  timeout = GetGameTimer() + 2000
  while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < timeout do Wait(10) end
  DoScreenFadeIn(400)
  fadingTeleport = false
end

-- Stopped / restarted in the middle of fadeTeleport: never leave the screen black.
AddEventHandler('onResourceStop', function(resource)
  if resource ~= NZ.ResourceName or not fadingTeleport then return end
  fadingTeleport = false
  DoScreenFadeIn(0)
end)

---------------------------------------------------------------------------------------
-- Open
---------------------------------------------------------------------------------------

local function doOpen(locationId, extra)
  local result = NZ.NUI.await('nz:garage:open', {
    locationId = locationId,
    groupId = extra.groupId,
    houseId = extra.houseId,
  })
  if not result.ok then
    NZ.NUI.notify('error', result.error)
    return false
  end
  local data = enrich(result.data)
  if type(data) ~= 'table' then
    NZ.NUI.notify('error', L('Something went wrong'))
    return false
  end
  local summary = type(data.garage) == 'table' and data.garage or {}
  local view = Garage.locationView(locationId) or Garage.locationView(summary.locationId)
  if not view and extra.houseId ~= nil then view = Garage.locationView('H' .. tostring(extra.houseId)) end

  ctx = {
    locationId = summary.locationId or locationId,
    groupId = summary.groupId or extra.groupId,
    houseId = extra.houseId,
    location = view,
    data = data,
  }

  if extra.goInside and summary.canGoInside then
    local inside = goInside()
    if inside.ok then return true end
    NZ.NUI.notify('error', inside.error)
    if NZ.NUI.isOpen('garage') then return true end
  end
  NZ.NUI.open('garage', data)
  return true
end

--- Open the garage menu at a location (or { houseId } / { groupId } via `extra`).
--- extra.goInside = true goes straight into the interior when the garage has one.
---@param locationId number|string|nil
---@param extra table|nil { groupId?, houseId?, goInside? }
---@return boolean
function Garage.open(locationId, extra)
  extra = type(extra) == 'table' and extra or {}
  if opening then return false end
  if incapacitated() then
    NZ.NUI.notify('error', L('You cannot do that right now'))
    return false
  end
  opening = true
  local ok, res = pcall(doOpen, locationId, extra)
  opening = false
  if not ok then
    lib.print.error(('[nayzeee-garages] open garage failed: %s'):format(res))
    NZ.NUI.notify('error', L('Something went wrong'))
    return false
  end
  return res == true
end

---------------------------------------------------------------------------------------
-- Store
---------------------------------------------------------------------------------------

local function offerDirections(location, message, info)
  local choice = lib.alertDialog({
    header = L('Garage full'),
    content = (message or L('This garage is full')) .. '\n\n' .. L('Do you want directions to the nearest garage with free space?'),
    centered = true,
    cancel = true,
    labels = { confirm = L('Get directions'), cancel = L('Cancel') },
  })
  NZ.NUI.syncFocus()
  if choice ~= 'confirm' then return end
  local known = type(info) == 'table' and type(info.nearest) == 'table' and info.nearest or nil
  local result = Garage.directions({
    locationId = tonumber(location.id),
    houseId = location.kind == 'house' and Garage.houseIdOf(location) or nil,
    vehicleType = location.vehicleType,
  }, known)
  if not result.ok then NZ.NUI.notify('error', result.error) end
end

local function doStore(location, vehicle)
  local data = NZ.Veh.collect(vehicle)
  if type(data) ~= 'table' or not data.netId then
    NZ.NUI.notify('error', L('This vehicle cannot be stored'))
    return false
  end
  local payload = { netId = data.netId, data = data }
  if location.kind == 'house' then
    payload.houseId = Garage.houseIdOf(location)
  else
    payload.locationId = tonumber(location.id)
    if ctx and payload.locationId and tonumber(ctx.locationId) == payload.locationId then
      payload.groupId = ctx.groupId
    end
  end

  local result = NZ.NUI.await('nz:garage:store', payload)
  if not result.ok then
    local info = result.data
    if type(info) == 'table' and info.full and settingsSection('garages').suggestWhenFull ~= false then
      offerDirections(location, result.error, info)
    else
      NZ.NUI.notify('error', result.error)
    end
    return false
  end

  -- The server deletes the entity; make sure it is gone locally before moving the player.
  local plate = NZ.Utils.plate(data.plate)
  local timeout = GetGameTimer() + 1500
  while DoesEntityExist(vehicle) and GetGameTimer() < timeout do Wait(50) end
  if DoesEntityExist(vehicle) and NZ.Utils.plate(GetVehicleNumberPlateText(vehicle)) == plate then
    pcall(NZ.Veh.delete, vehicle)
  end
  NZ.NUI.notify('success', L('Vehicle stored'))

  local returnTo = type(result.data) == 'table' and result.data.returnTo or nil
  if not returnTo and location.returnToEntrance and type(location.openPoints) == 'table' and location.openPoints[1] then
    returnTo = location.openPoints[1].coords
  end
  if returnTo then fadeTeleport(returnTo) end
  return true
end

--- Store the vehicle the player is driving at `location` (client view) (§7.2).
---@param location table
---@return boolean
function Garage.store(location)
  if storing then return false end
  if type(location) ~= 'table' then
    NZ.NUI.notify('error', L('This garage is not available here'))
    return false
  end
  local ped = cache.ped
  local vehicle = GetVehiclePedIsIn(ped, false)
  if vehicle == 0 or GetPedInVehicleSeat(vehicle, -1) ~= ped then
    NZ.NUI.notify('error', L('You must be driving the vehicle'))
    return false
  end
  storing = true
  local ok, res = pcall(doStore, location, vehicle)
  storing = false
  if not ok then
    lib.print.error(('[nayzeee-garages] store failed: %s'):format(res))
    NZ.NUI.notify('error', L('Something went wrong'))
    return false
  end
  return res == true
end

---------------------------------------------------------------------------------------
-- NUI callbacks
---------------------------------------------------------------------------------------

NZ.NUI.register('garage:drive', function(data)
  local plate = NZ.Utils.plate(data.plate)
  if not plate or not ctx then return NZ.Utils.fail(L('Vehicle not found')) end
  local vehicle = findByPlate(ctx.data and ctx.data.vehicles, plate)
  if not vehicle then
    local refreshed = NZ.NUI.await('nz:garage:refresh', {})
    if refreshed.ok then
      Garage.setData(enrich(refreshed.data))
      vehicle = findByPlate(ctx.data and ctx.data.vehicles, plate)
    end
  end
  if not vehicle then return NZ.Utils.fail(L('Vehicle not found')) end
  return Garage.retrieve(vehicle.plate or data.plate, {
    hash = vehicle.hash,
    location = ctx.location,
    app = 'garage',
  })
end)

NZ.NUI.register('garage:spawner', function(data)
  return NZ.JobsClient.spawn(data.index)
end)

NZ.NUI.register('garage:track', function(data)
  if type(data.plate) ~= 'string' then return NZ.Utils.fail(L('Vehicle not found')) end
  local result = NZ.NUI.await('nz:garage:track', { plate = data.plate })
  if not result.ok then return result end
  local coords = type(result.data) == 'table' and (NZ.Utils.v3(result.data.coords) or NZ.Utils.v3(result.data)) or nil
  if not coords then return NZ.Utils.fail(L('The vehicle could not be located')) end
  SetNewWaypoint(coords.x + 0.0, coords.y + 0.0)
  NZ.NUI.notify('success', L('Waypoint set'))
  return NZ.Utils.ok(nil)
end)

NZ.NUI.register('garage:directions', function()
  local location = ctx and ctx.location
  return Garage.directions({
    locationId = ctx and tonumber(ctx.locationId) or nil,
    houseId = ctx and ctx.houseId or nil,
    vehicleType = location and location.vehicleType or nil,
  })
end)

NZ.NUI.register('garage:goInside', function()
  return goInside()
end)

---------------------------------------------------------------------------------------
-- Events & exports
---------------------------------------------------------------------------------------

RegisterNetEvent('nz:client:sellOffer', function(offer)
  if type(offer) ~= 'table' or offer.offerId == nil then return end
  -- The server cannot resolve GTA display names, so prefer the client-side label.
  local label
  if offer.hash ~= nil or offer.model ~= nil then
    label = vehicleLabel(tonumber(offer.hash) or offer.model)
  end
  local unresolved = label == nil or label == L('Vehicle') or label == L('Unknown vehicle')
  if unresolved and type(offer.label) == 'string' and offer.label ~= '' then
    label = offer.label
  end
  label = label or L('Vehicle')
  -- Seconds until the offer expires (server unix time; 60 s when unknown). Clamped so a
  -- skewed client clock cannot hide the dialog: the server rejects late answers anyway.
  local seconds = 60
  local now = tonumber(GetCloudTimeAsInt())
  if tonumber(offer.expires) and now and now > 0 then
    seconds = math.max(15, math.min(120, tonumber(offer.expires) - now))
  end
  local choice = Garage.alert({
    header = L('Vehicle offer'),
    content = L('{seller} offers you {vehicle} ({plate}) for {price}', {
      seller = type(offer.sellerName) == 'string' and offer.sellerName or L('Someone'),
      vehicle = label,
      plate = tostring(offer.plate or ''),
      price = Garage.formatMoney(offer.price),
    }),
    centered = true,
    cancel = true,
    labels = { confirm = L('Buy'), cancel = L('Decline') },
  }, seconds)
  NZ.NUI.syncFocus()
  -- Never answered (another dialog stayed open): the server lets the offer expire and
  -- tells the seller; only an explicit "Decline" declines it.
  if choice == nil then return end
  local accept = choice == 'confirm'
  local result = NZ.NUI.await('nz:garage:sellRespond', { offerId = offer.offerId, accept = accept })
  if not result.ok then
    NZ.NUI.notify('error', result.error)
  elseif accept then
    NZ.NUI.notify('success', L('You bought {vehicle}', { vehicle = label }))
  end
end)

RegisterNetEvent('nz:client:openGarage', function(payload)
  local locationId = type(payload) == 'table' and payload.locationId or payload
  local extra = type(payload) == 'table' and { groupId = payload.groupId, houseId = payload.houseId } or nil
  Garage.open(locationId, extra)
end)

local function openByAnyId(locationId)
  if locationId == nil then
    local loc = NZ.Points.nearestLocation(function(_, rec) return rec.open and rec.openAction == 'garage' end)
    if not loc then
      NZ.NUI.notify('error', L('You are not near a garage'))
      return
    end
    locationId = loc.id
  end
  local view = Garage.locationView(locationId)
  if view and view.kind == 'house' then
    Garage.open(nil, { houseId = Garage.houseIdOf(view) })
  else
    Garage.open(locationId)
  end
end

exports('OpenGarage', function(locationId)
  CreateThread(function() openByAnyId(locationId) end)
  return true
end)

exports('StoreVehicle', function(locationId)
  CreateThread(function()
    local view
    if locationId ~= nil then
      view = Garage.locationView(locationId)
    else
      view = NZ.Points.nearestLocation(function(_, rec) return rec.store == true end)
    end
    if not view then
      NZ.NUI.notify('error', L('You are not near a garage'))
      return
    end
    Garage.store(view)
  end)
  return true
end)
