--[[
  nayzeee-garages — housing integration (client).

  Keeps NZ.State.houses (house garages this player may use) up to date:
    - 'nz:client:houses' (server push from bridge/server/housing.lua) replaces the list;
    - events housing scripts already fire ask the server for a fresh list through the
      'nz:housing:refresh' callback (debounced): the qb-garages house events (qb-houses,
      ps-housing, rtx_housing, qs-housing's qb bridge), loaf_housing / loaf_keysystem key and
      purchase events, and esx_property garage syncs (only when they change what we show).
  Exports for housing scripts that own the garage interaction (install/housing/*):
    OpenHouseGarage(houseId, data?)  -- open the garage menu of that house (stores the vehicle
                                        instead when the player is driving)
    StoreHouseGarage(houseId, data?) -- store the vehicle the player is driving there
    RefreshHouseGarages()            -- ask for a fresh house list (after a key / purchase change)
  houseId is '<prefix>:<id>' as the server loaders name it ('vms:12', 'tk:3', 'nolag:7' ...).
  data = { name? } (a label for a garage registered on first use). Coordinates passed by the
  housing script are ignored: the server uses the player's position. Both exports return true
  when the request was accepted (the result is shown to the player).
  Interaction points are rebuilt (NZ.Points.rebuild) only when the list really changed.
]]

local Utils = NZ.Utils

local DEBOUNCE_MS = 1000      -- coalesce bursts of housing events
local MIN_INTERVAL_MS = 4000  -- at most one refresh request per interval

local pending = false
local lastRequestAt = -MIN_INTERVAL_MS
-- 'house:hasKey' pairs already refreshed for. A keyed house without a garage never becomes
-- known, so without this every setHouseGarage event for it would ask for a reload again.
-- Cleared whenever the house list or the housing garages change.
local checked = {}
local hookBusy = false

---------------------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------------------

local function isHouseView(view)
  if type(view) ~= 'table' or view.id == nil then return false end
  if view.kind == 'house' then return true end
  return type(view.id) == 'string' and view.id:sub(1, 1) == 'H'
end

local function coordKey(t)
  local v = Utils.v4(t)
  if not v then return '-' end
  return ('%.2f,%.2f,%.2f,%.1f'):format(v.x, v.y, v.z, v.w)
end

--- Order independent fingerprint of a house map (id, name, points, visibility).
local function fingerprint(map)
  if type(map) ~= 'table' then return '' end
  local parts = {}
  for id, view in pairs(map) do
    local open = type(view.openPoints) == 'table' and view.openPoints[1] or nil
    local spawn = type(view.spawnPoints) == 'table' and view.spawnPoints[1] or nil
    parts[#parts + 1] = table.concat({
      tostring(id),
      tostring(view.name),
      coordKey(type(open) == 'table' and open.coords or nil),
      coordKey(spawn),
      tostring(view.enabled ~= false),
      tostring(view.hidden == true),
    }, '|')
  end
  table.sort(parts)
  return table.concat(parts, ';')
end

--- Replace NZ.State.houses with a list of client views; rebuild points on changes.
---@param views table list (or map) of house client views
local function applyViews(views)
  local map = {}
  if type(views) == 'table' then
    for _, view in pairs(views) do
      if isHouseView(view) then map[view.id] = view end
    end
  end
  local changed = fingerprint(map) ~= fingerprint(NZ.State.houses)
  NZ.State.houses = map
  if changed then checked = {} end
  if not changed or not NZ.State.ready then return end
  if type(NZ.Points.rebuild) ~= 'function' then return end
  local ok, err = pcall(NZ.Points.rebuild)
  if not ok then lib.print.error(('[nayzeee-garages] points rebuild failed: %s'):format(tostring(err))) end
end

---------------------------------------------------------------------------------------
-- Configuration (mirrors the server: 'auto' | 'none' | resource name | list of names)
---------------------------------------------------------------------------------------

local function mode()
  local value = Config.Integrations and Config.Integrations.housing
  if value == nil or value == true then return 'auto' end
  if value == false then return 'none' end
  if type(value) == 'string' then
    local s = Utils.trim(value):lower()
    if s == '' or s == 'auto' then return 'auto' end
    if s == 'none' or s == 'off' or s == 'false' then return 'none' end
    return { [s] = true }
  end
  if type(value) == 'table' then
    local set = {}
    for _, v in pairs(value) do
      if type(v) == 'string' and v ~= '' then set[Utils.trim(v):lower()] = true end
    end
    if set.auto then return 'auto' end
    if next(set) == nil then return 'none' end
    return set
  end
  return 'auto'
end

local function housingEnabled()
  return mode() ~= 'none'
end

--- Is this housing script's integration allowed by the config?
local function allows(resource, prefix)
  local m = mode()
  if m == 'auto' then return true end
  if m == 'none' then return false end
  return m[resource:lower()] == true or m[prefix] == true
end

---------------------------------------------------------------------------------------
-- Refresh requests
---------------------------------------------------------------------------------------

local function refreshNow()
  lastRequestAt = GetGameTimer()
  local ok, res = pcall(lib.callback.await, 'nz:housing:refresh', false, {})
  if not ok then
    Utils.debug('housing: refresh failed:', tostring(res))
    return
  end
  if type(res) ~= 'table' or res.ok ~= true then
    Utils.debug('housing: refresh refused:', type(res) == 'table' and tostring(res.error) or 'no response')
    return
  end
  applyViews(res.data)
end

--- Ask the server for a fresh house list (debounced and throttled).
local function scheduleRefresh()
  if pending or not housingEnabled() then return end
  pending = true
  local wait = math.max(DEBOUNCE_MS, lastRequestAt + MIN_INTERVAL_MS - GetGameTimer())
  SetTimeout(wait, function()
    pending = false
    refreshNow()
  end)
end

--- Is a house of any housing script with this raw id in the list? ('H<id>' or 'H<prefix>:<id>')
local function knownHouse(house)
  if house == nil then return false end
  local houses = NZ.State.houses or {}
  local id = tostring(house)
  if houses['H' .. id] ~= nil then return true end
  local suffix = ':' .. id
  for _, view in pairs(houses) do
    local hid = type(view) == 'table' and view.houseId or nil
    if type(hid) == 'string' and #hid > #suffix and hid:sub(-#suffix) == suffix then return true end
  end
  return false
end

local function myIdentifier()
  if type(NZ.Bridge.getIdentifier) ~= 'function' then return nil end
  local ok, identifier = pcall(NZ.Bridge.getIdentifier)
  if ok and type(identifier) == 'string' and identifier ~= '' then return identifier end
  return nil
end

---------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------

-- Server push: the full list of house garages this player may use.
RegisterNetEvent('nz:client:houses', function(views)
  applyViews(views)
end)

-- qb-houses / ps-housing / rtx_housing: fired when the closest house changes. Only refresh when
-- what the housing script reports (key / no key) disagrees with what we currently show.
RegisterNetEvent('qb-garages:client:setHouseGarage', function(house, hasKey)
  if house == nil then return end
  local known = knownHouse(house)
  if hasKey == true and known then return end
  if hasKey == false and not known then return end
  -- Ask once per house and key state until something changes (see `checked`).
  local key = tostring(house) .. ':' .. tostring(hasKey)
  if checked[key] then return end
  checked[key] = true
  scheduleRefresh()
end)

RegisterNetEvent('qb-garages:client:houseGarageConfig', function()
  checked = {}
  scheduleRefresh()
end)

RegisterNetEvent('qb-garages:client:addHouseGarage', function()
  checked = {}
  scheduleRefresh()
end)

RegisterNetEvent('qb-garages:client:removeHouseGarage', function()
  checked = {}
  scheduleRefresh()
end)

-- loaf_housing: purchases / transfers (sent to every player), and loaf_keysystem house keys.
RegisterNetEvent('loaf_housing:update_houses', function()
  if allows('loaf_housing', 'loaf') then scheduleRefresh() end
end)

RegisterNetEvent('loaf_keysystem:add_key', function(keyId)
  if type(keyId) == 'string' and keyId:find('^housing_key_') and allows('loaf_housing', 'loaf') then scheduleRefresh() end
end)

RegisterNetEvent('loaf_keysystem:remove_all_keys', function(keyId)
  if type(keyId) == 'string' and keyId:find('^housing_key_') and allows('loaf_housing', 'loaf') then scheduleRefresh() end
end)

RegisterNetEvent('loaf_keysystem:remove_key', function()
  -- Only the unique id is sent: it may or may not be a house key.
  if allows('loaf_housing', 'loaf') and GetResourceState('loaf_housing') == 'started' then scheduleRefresh() end
end)

--- esx_property: does this property sync change a garage we show (or should show)?
local function esxGarageChanged(propertyId, property)
  if type(property) ~= 'table' or propertyId == nil then return false end
  local me = myIdentifier()
  local garage = type(property.garage) == 'table' and property.garage or {}
  local keys = type(property.Keys) == 'table' and property.Keys or {}
  local hasAccess = me ~= nil and (property.Owner == me or keys[me] ~= nil)
  local pos = Utils.v3(garage.pos)
  local wanted = hasAccess and garage.enabled == true and pos ~= nil
  local view = (NZ.State.houses or {})['Hesx:' .. tostring(math.tointeger(tonumber(propertyId)) or propertyId)]
  if wanted ~= (view ~= nil) then return true end
  if view and pos then
    local open = type(view.openPoints) == 'table' and view.openPoints[1] or nil
    local at = type(open) == 'table' and Utils.v3(open.coords) or nil
    if not at or Utils.dist(at, pos) > 1.0 then return true end
  end
  return false
end

-- esx_property 1.16+: one property changed (sent to every player).
RegisterNetEvent('esx_property:syncProperty', function(propertyId, property)
  if not allows('esx_property', 'esx') then return end
  if esxGarageChanged(propertyId, property) then scheduleRefresh() end
end)

-- esx_property: the whole list (start, refresh command, every change on 1.14).
RegisterNetEvent('esx_property:syncProperties', function(properties)
  if type(properties) ~= 'table' or not allows('esx_property', 'esx') then return end
  for propertyId, property in pairs(properties) do
    if esxGarageChanged(propertyId, property) then
      scheduleRefresh()
      return
    end
  end
end)

RegisterNetEvent('esx_property:giveKeyAccess', function()
  if allows('esx_property', 'esx') then scheduleRefresh() end
end)

RegisterNetEvent('esx_property:RemoveKey', function()
  if allows('esx_property', 'esx') then scheduleRefresh() end
end)

-- Another character may hold other keys.
AddEventHandler('nz:client:playerLoaded', function()
  checked = {}
end)

AddEventHandler('nz:client:playerUnloaded', function()
  checked = {}
end)

---------------------------------------------------------------------------------------
-- Hook exports (housing scripts that draw their own garage interaction)
---------------------------------------------------------------------------------------

local function hookHouseId(value)
  if type(value) == 'number' then
    if value ~= value or value == math.huge or value == -math.huge then return nil end
    value = tostring(math.tointeger(value) or value)
  end
  if type(value) ~= 'string' then return nil end
  local s = Utils.trim(value)
  if s == '' or #s > 64 or s:find('%c') then return nil end
  return s
end

local function isDriving()
  local ped = cache.ped or PlayerPedId()
  local vehicle = GetVehiclePedIsIn(ped, false)
  return vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped
end

--- Ask the server to check access and place the garage, then open / store with the usual flow.
---@param action string 'open' | 'store'
---@return boolean
local function hookFlow(action, houseId, data)
  local id = hookHouseId(houseId)
  if not id then
    NZ.NUI.notify('error', L('This garage is not available'))
    return false
  end
  if not NZ.State.ready then
    NZ.NUI.notify('error', L('Garages are still loading'))
    return false
  end
  local driving = isDriving()
  if action == 'open' and driving then action = 'store' end
  if action == 'store' and not driving then
    NZ.NUI.notify('error', L('You must be driving the vehicle'))
    return false
  end
  if hookBusy then return false end

  hookBusy = true
  local name = type(data) == 'table' and (data.name or data.label) or nil
  local ok, res = pcall(lib.callback.await, 'nz:housing:hook', false, {
    houseId = id,
    action = action,
    name = type(name) == 'string' and name:sub(1, 60) or nil,
  })
  hookBusy = false
  if not ok or type(res) ~= 'table' then
    Utils.debug('housing: hook failed:', tostring(res))
    NZ.NUI.notify('error', L('The server did not respond, try again'))
    return false
  end
  if res.ok ~= true then
    NZ.NUI.notify('error', type(res.error) == 'string' and res.error or L('This garage is not available'))
    return false
  end

  local info = type(res.data) == 'table' and res.data or {}
  if type(info.views) == 'table' then applyViews(info.views) end
  local houseKey = type(info.houseId) == 'string' and info.houseId or id
  local view = (NZ.State.houses or {})['H' .. houseKey]
  if not view then
    NZ.NUI.notify('error', L('This garage is not available'))
    return false
  end
  if action == 'store' then return NZ.Garage.store(view) end
  return NZ.Garage.open(nil, { houseId = houseKey })
end

local function runHook(action, houseId, data)
  CreateThread(function()
    local ok, err = pcall(hookFlow, action, houseId, data)
    if not ok then
      hookBusy = false
      lib.print.error(('[nayzeee-garages] house garage %s failed: %s'):format(action, tostring(err)))
      NZ.NUI.notify('error', L('Something went wrong'))
    end
  end)
  return true
end

exports('OpenHouseGarage', function(houseId, data)
  return runHook('open', houseId, data)
end)

exports('StoreHouseGarage', function(houseId, data)
  return runHook('store', houseId, data)
end)

exports('RefreshHouseGarages', function()
  checked = {}
  scheduleRefresh()
  return true
end)
