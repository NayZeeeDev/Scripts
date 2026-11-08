--[[
  nayzeee-garages — admin panel, client side (NZ.AdminClient).
  Opens the NUI app 'admin' with AdminOpenData from 'nz:admin:refresh' and handles the
  admin callbacks that need the game world: teleport, pick position, the in-world point
  manager and starting the interior creator (create / edit). Everything else the admin
  app does is forwarded to the server by client/nui.lua.
]]

local AdminClient = NZ.AdminClient
local Utils = NZ.Utils

local PAGES = {
  garages = true, jobs = true, private = true, impounds = true,
  interiors = true, vehicles = true, settings = true,
}

local cache = nil       -- last AdminOpenData (kept while the admin app is closed for a tool)
local opening = false

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

--- Await a server callback and always return a result table.
local function await(name, payload)
  local ok, res = pcall(lib.callback.await, name, false, payload or {})
  if not ok then
    lib.print.error(('[nayzeee-garages] callback "%s" failed: %s'):format(name, res))
    return Utils.fail(L('The server did not respond, try again'))
  end
  if type(res) ~= 'table' or type(res.ok) ~= 'boolean' then
    return Utils.fail(L('The server did not respond, try again'))
  end
  if not res.ok and type(res.error) ~= 'string' then res.error = L('Something went wrong') end
  return res
end

local function enrich(data)
  if type(data) == 'table' and NZ.Veh and type(NZ.Veh.enrichDeep) == 'function' then
    local ok, res = pcall(NZ.Veh.enrichDeep, data)
    if ok and res ~= nil then return res end
  end
  return data
end

local function pedV4()
  local ped = PlayerPedId()
  local c = Utils.v3(GetEntityCoords(ped)) or { x = 0.0, y = 0.0, z = 0.0 }
  return {
    x = Utils.round(c.x, 3),
    y = Utils.round(c.y, 3),
    z = Utils.round(c.z, 3),
    w = Utils.round((tonumber(GetEntityHeading(ped)) or 0.0) % 360.0, 2),
  }
end

local function validPage(page)
  if type(page) == 'string' and PAGES[page] then return page end
  return nil
end

--- Profile views: the ones the admin data carries, else built from Config.IplProfiles.
local function profileViews()
  if cache and type(cache.profiles) == 'table' then return cache.profiles end
  return NZ.Interior.profileViews()
end

local function findProfile(key)
  if type(key) ~= 'string' or key == '' then return nil end
  local views = profileViews()
  for i = 1, #views do
    if type(views[i]) == 'table' and views[i].key == key then return views[i] end
  end
  return nil
end

--- { [optionKey] = default } of a profile view.
local function optionDefaults(profile)
  local out = {}
  if type(profile) == 'table' and type(profile.options) == 'table' then
    for _, opt in pairs(profile.options) do
      if type(opt) == 'table' and type(opt.key) == 'string' then
        local default = opt.default
        if default == nil and type(opt.choices) == 'table' and type(opt.choices[1]) == 'table' then
          default = opt.choices[1].value
        end
        if default ~= nil then out[opt.key] = tostring(default) end
      end
    end
  end
  if next(out) == nil then setmetatable(out, { __jsontype = 'object' }) end
  return out
end

local function findInterior(id)
  if not cache or type(cache.interiors) ~= 'table' then return nil end
  for _, interior in pairs(cache.interiors) do
    if type(interior) == 'table' and tonumber(interior.id) == id then return interior end
  end
  return nil
end

--- Re-open the admin app with the cached data (after a world tool).
local function reopen(page)
  if not cache then return end
  cache.page = validPage(page) or validPage(cache.page) or 'garages'
  NZ.NUI.open('admin', cache)
end

--- An in-world tool (point manager / placement) is running. Opening the admin app now would
--- take NUI focus while the panel is still hidden for the tool (admin:points pending): the
--- cursor appears, nothing is visible, Escape is swallowed and Enter / Esc never reach the
--- tool, so the player is stuck. The tool ends first.
local function toolRunning()
  if not NZ.Placement.isActive() then return false end
  NZ.NUI.notify('warning', L('Finish the current action first'))
  return true
end

---------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------

--- Fetch AdminOpenData ('nz:admin:refresh') and open the admin panel on `page`
--- ('garages' by default). Blocking; call from a thread.
---@param page string|nil AdminPage
---@return boolean
function AdminClient.open(page)
  if opening then return false end
  if NZ.Creator.isActive() then
    NZ.NUI.notify('warning', L('Save or cancel the interior editor first'))
    return false
  end
  if toolRunning() then return false end
  opening = true
  local res = await('nz:admin:refresh', {})
  opening = false
  if not res.ok then
    NZ.NUI.notify('error', res.error)
    return false
  end
  if type(res.data) ~= 'table' then
    NZ.NUI.notify('error', L('Something went wrong'))
    return false
  end
  -- A tool may have started while the data was on its way (the panel was already open).
  if toolRunning() then return false end
  local data = enrich(res.data)
  data.page = validPage(page) or 'garages'
  cache = data
  NZ.NUI.open('admin', data)
  return true
end

---------------------------------------------------------------------------------------
-- NUI callbacks [client]
---------------------------------------------------------------------------------------

NZ.NUI.register('admin:location:teleport', function(data)
  local coords = Utils.v3(data.coords)
  if not coords then return Utils.fail(L('Invalid coordinates')) end
  if NZ.Interior.isInside() then return Utils.fail(L('Leave the garage interior first')) end
  NZ.Interior.teleport(data.coords, { keepVehicle = true })
  return nil
end)

NZ.NUI.register('admin:pickPosition', function()
  return pedV4()
end)

--- kind 'spawn' | 'open' | 'store': the point manager (NZ.Placement.manage).
--- kind 'zone': the garage zone tool (NZ.Placement.zone) with { zone, openPoints, spawnPoints }
--- of the location being edited; returns { points, minZ, maxZ } or null (cancelled). The server
--- validates the zone again when the location is saved.
NZ.NUI.register('admin:points', function(data)
  local kind = data.kind
  if kind ~= 'spawn' and kind ~= 'open' and kind ~= 'store' and kind ~= 'zone' then
    return Utils.fail(L('Unknown point type'))
  end
  if NZ.Placement.isActive() then return Utils.fail(L('Finish the current action first')) end
  if kind == 'zone' and NZ.Interior.isInside() then return Utils.fail(L('Leave the garage interior first')) end
  if kind == 'zone' and IsPedInAnyVehicle(PlayerPedId(), false) then return Utils.fail(L('Leave the vehicle first')) end
  local vehicleType = Utils.vehicleTypes[data.vehicleType] and data.vehicleType or 'car'

  -- Keep the admin app mounted (so unsaved editor state survives): the NUI hides its window
  -- while this request is pending; we only release focus for the in-world manager.
  local hadAdmin = NZ.NUI.isOpen('admin')
  if hadAdmin then NZ.NUI.setFocus('admin', false) end
  local ok, result
  if kind == 'zone' then
    ok, result = pcall(NZ.Placement.zone, {
      zone = type(data.zone) == 'table' and data.zone or nil,
      openPoints = type(data.openPoints) == 'table' and data.openPoints or {},
      spawnPoints = type(data.spawnPoints) == 'table' and data.spawnPoints or {},
    })
  else
    ok, result = pcall(NZ.Placement.manage, {
      kind = kind,
      vehicleType = vehicleType,
      points = type(data.points) == 'table' and data.points or {},
      model = type(data.model) == 'string' and data.model or nil,
    })
  end
  if not ok then
    lib.print.error(('[nayzeee-garages] %s failed: %s'):format(kind == 'zone' and 'zone tool' or 'point manager', result))
    result = nil
  end
  if hadAdmin and NZ.NUI.isOpen('admin') then
    NZ.NUI.setFocus('admin', true)
  else
    reopen(validPage(data.page) or (cache and cache.page))
  end
  return result
end)

NZ.NUI.register('admin:interior:create', function(data)
  local name = Utils.cleanText(data.name, 64)
  if not name then return Utils.fail(L('Enter a name')) end
  if NZ.Interior.isInside() then return Utils.fail(L('Leave the garage interior first')) end

  local profileKey = nil
  local profile = nil
  if data.profile ~= nil and data.profile ~= false and data.profile ~= '' then
    profileKey = type(data.profile) == 'string' and data.profile or nil
    profile = findProfile(profileKey)
    if not profile then return Utils.fail(L('Unknown interior profile')) end
  end

  local here = pedV4()
  local entry = profile and Utils.v4(profile.coords) or nil
  if not entry then
    local c = Utils.v3(data.coords)
    if c then entry = { x = c.x, y = c.y, z = c.z, w = here.w } end
  end
  entry = entry or here

  local interior = {
    id = nil,
    name = name,
    enabled = true,
    profile = profileKey,
    options = optionDefaults(profile),
    entry = entry,
    gtaInteriorId = nil,
    cutscene = { enabled = false, transition = 3000, returnTime = 1000, points = {} },
    slots = {},
    exit = nil,
  }

  NZ.NUI.close('admin')
  local started = NZ.Creator.start({
    mode = 'create',
    interior = interior,
    profiles = profileViews(),
    gtaInteriorName = nil,
  }, { returnTo = here, teleport = true })
  if not started then reopen('interiors') end
  return nil
end)

NZ.NUI.register('admin:interior:edit', function(data)
  local id = tonumber(data.id)
  if not id then return Utils.fail(L('Interior not found')) end
  if NZ.Interior.isInside() then return Utils.fail(L('Leave the garage interior first')) end

  -- Always edit the server's current version: the panel may have toggled or changed it
  -- since the cache was filled (a stale `enabled` flag would be written back on save).
  local res = await('nz:admin:refresh', {})
  if res.ok and type(res.data) == 'table' then
    local page = cache and cache.page or 'interiors'
    cache = enrich(res.data)
    cache.page = validPage(page) or 'interiors'
  end
  local interior = findInterior(id)
  if not interior then return Utils.fail(L('Interior not found')) end
  if not Utils.v4(interior.entry) then return Utils.fail(L('This garage interior has no entry point')) end

  local here = pedV4()
  NZ.NUI.close('admin')
  local started = NZ.Creator.start({
    mode = 'edit',
    interior = Utils.deepCopy(interior),
    profiles = profileViews(),
    gtaInteriorName = nil,
  }, { returnTo = here, teleport = true })
  if not started then reopen('interiors') end
  return nil
end)

--- Replace the cached AdminOpenData (used by client/nui.lua after 'admin:refresh').
---@param data table|nil
function AdminClient.setCache(data)
  if type(data) ~= 'table' then return end
  local page = cache and cache.page or data.page
  cache = data
  cache.page = validPage(page) or 'garages'
end

---------------------------------------------------------------------------------------
-- Events & exports
---------------------------------------------------------------------------------------

RegisterNetEvent('nz:client:openAdmin', function(payload)
  local page = type(payload) == 'table' and payload.page or nil
  CreateThread(function() AdminClient.open(page) end)
end)

exports('OpenAdmin', function(page)
  CreateThread(function() AdminClient.open(page) end)
end)
