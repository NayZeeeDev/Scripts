--[[
  nayzeee-garages — housing integration (client).

  Keeps NZ.State.houses (house garages this player may use) up to date:
    - 'nz:client:houses' (server push from bridge/server/housing.lua) replaces the list;
    - the garage events housing scripts already fire for qb-garages
      ('qb-garages:client:setHouseGarage', 'qb-garages:client:houseGarageConfig',
      'qb-garages:client:addHouseGarage', 'qb-garages:client:removeHouseGarage') ask the
      server for a fresh list through the 'nz:housing:refresh' callback.
  Interaction points are rebuilt (NZ.Points.rebuild) only when the list really changed.
]]

local Utils = NZ.Utils

local DEBOUNCE_MS = 1000      -- coalesce bursts of housing events
local MIN_INTERVAL_MS = 4000  -- at most one refresh request per interval

local pending = false
local lastRequestAt = -MIN_INTERVAL_MS

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

--- Order independent fingerprint of a house map (id, name and points).
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
  if not changed or not NZ.State.ready then return end
  if type(NZ.Points.rebuild) ~= 'function' then return end
  local ok, err = pcall(NZ.Points.rebuild)
  if not ok then lib.print.error(('[nayzeee-garages] points rebuild failed: %s'):format(tostring(err))) end
end

---------------------------------------------------------------------------------------
-- Refresh requests
---------------------------------------------------------------------------------------

local function housingEnabled()
  local mode = Config.Integrations and Config.Integrations.housing
  return mode ~= 'none'
end

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

local function knownHouse(house)
  if house == nil then return nil end
  local houses = NZ.State.houses or {}
  local id = tostring(house)
  return houses['Hqb:' .. id] ~= nil or houses['H' .. id] ~= nil
end

---------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------

-- Server push: the full list of house garages this player may use.
RegisterNetEvent('nz:client:houses', function(views)
  applyViews(views)
end)

-- qb-houses: fired when the closest house changes. Only refresh when what the housing
-- script reports (key / no key) disagrees with what we currently show.
RegisterNetEvent('qb-garages:client:setHouseGarage', function(house, hasKey)
  if house == nil then return end
  local known = knownHouse(house)
  if hasKey == true and known then return end
  if hasKey == false and not known then return end
  scheduleRefresh()
end)

RegisterNetEvent('qb-garages:client:houseGarageConfig', function()
  scheduleRefresh()
end)

RegisterNetEvent('qb-garages:client:addHouseGarage', function()
  scheduleRefresh()
end)

RegisterNetEvent('qb-garages:client:removeHouseGarage', function()
  scheduleRefresh()
end)
