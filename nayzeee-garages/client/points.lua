--[[
  nayzeee-garages — world interaction points (NZ.Points).
  Builds lib.points (and optional target zones), markers and blips for every location the
  player can use, shows the "Open garage" / "Store vehicle" prompt while inside a point and
  dispatches the single interaction keybind to the active point.
  No per-frame work unless the player is near a point (markers only).
]]

local Points = NZ.Points

local records = {}        -- every interaction record built by the last rebuild
local pointObjs = {}      -- lib.points objects
local near = {}           -- [record] = true while the player is within its point distance
local nearCount = 0
local blips = {}
local targetZones = {}
local keybind = nil
local active = nil        -- { rec, action, label } currently shown as prompt
local looping = false
local acting = false
local markerRGB = { 8, 175, 162 }

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function insideInterior()
  return NZ.Interior ~= nil and type(NZ.Interior.isInside) == 'function' and NZ.Interior.isInside() == true
end

local function interfaceSettings()
  local s = NZ.State.settings
  if type(s) == 'table' and type(s.interface) == 'table' then return s.interface end
  return Config.DefaultSettings.interface
end

local function garageSettings()
  local s = NZ.State.settings
  if type(s) == 'table' and type(s.garages) == 'table' then return s.garages end
  return Config.DefaultSettings.garages
end

local function parseAccent(hex)
  if type(hex) ~= 'string' then return end
  local r, g, b = hex:match('^#?(%x%x)(%x%x)(%x%x)$')
  if not r then return end
  markerRGB = { tonumber(r, 16), tonumber(g, 16), tonumber(b, 16) }
end

--- True when `rules` (JobRule list) allows the job/gang `info`. Empty rules allow everyone
--- (the server stays the authority).
local function rulesAllow(rules, info)
  if type(rules) ~= 'table' or next(rules) == nil then return true end
  if type(info) ~= 'table' or type(info.name) ~= 'string' then return false end
  local grade = tonumber(info.grade) or 0
  for _, rule in pairs(rules) do
    if type(rule) == 'table' and rule.name == info.name and grade >= (tonumber(rule.minGrade) or 0) then
      return true
    end
  end
  return false
end

--- Whether the player belongs to a private garage at this location.
---@param loc table
---@return boolean
function Points.isMember(loc)
  local groups = NZ.State.groups
  if type(groups) ~= 'table' or type(loc) ~= 'table' or loc.id == nil then return false end
  return groups[loc.id] == true or groups[tostring(loc.id)] == true or groups[tonumber(loc.id) or false] == true
end

--- Whether this client may see (and use) a location.
---@param loc table client view
---@return boolean
function Points.isVisible(loc)
  if type(loc) ~= 'table' or loc.enabled == false then return false end
  if loc.kind == 'job' then
    local info = loc.owner == 'gang' and NZ.State.gang or NZ.State.job
    return rulesAllow(loc.jobs, info)
  end
  if loc.kind == 'garage' then
    local r = loc.restriction
    if type(r) ~= 'table' or r.type == nil or r.type == 'everyone' then return true end
    if r.type == 'job' then return rulesAllow(r.rules, NZ.State.job) end
    if r.type == 'gang' then return rulesAllow(r.rules, NZ.State.gang) end
    if r.type == 'identifier' then
      if type(r.identifiers) ~= 'table' or next(r.identifiers) == nil then return true end
      local me = NZ.Bridge.getIdentifier and NZ.Bridge.getIdentifier()
      for _, id in pairs(r.identifiers) do
        if id == me then return true end
      end
      return false
    end
  end
  return true
end

--- Open action + prompt label for a location (nil when the player cannot open it).
local function openActionFor(loc)
  local kind = loc.kind
  if kind == 'impound' then return 'impound', L('Open impound'), 'fas fa-car-burst' end
  if kind == 'job' then return 'garage', L('Open job garage'), 'fas fa-warehouse' end
  if kind == 'private' then
    if Points.isMember(loc) then return 'garage', L('Open garage'), 'fas fa-warehouse' end
    if loc.purchasable then return 'forSale', L('View garage'), 'fas fa-key' end
    return nil
  end
  return 'garage', L('Open garage'), 'fas fa-warehouse'
end

local function canStoreAt(loc)
  if loc.kind == 'impound' then return false end
  if loc.kind == 'private' and not Points.isMember(loc) then return false end
  return true
end

local function categoryOf(vehicle)
  if NZ.Veh and NZ.Veh.categoryOf then
    local ok, cat = pcall(NZ.Veh.categoryOf, GetEntityModel(vehicle))
    if ok and cat then return cat end
  end
  return NZ.Utils.vehicleTypeFromClass(GetVehicleClass(vehicle))
end

local function currentKey()
  if keybind and keybind.getCurrentKey then
    local ok, key = pcall(keybind.getCurrentKey, keybind)
    if ok and type(key) == 'string' and key:match('^[%w_]+$') and not key:match('^%d%d%d+$') then
      return key
    end
  end
  return Config.Keys.interact or 'E'
end

local function groundZ(rec)
  if rec.groundZ then return rec.groundZ end
  local c = rec.coords
  local found, z = GetGroundZFor_3dCoord(c.x, c.y, c.z + 1.0, false)
  if found and math.abs(z - c.z) < 3.0 then
    rec.groundZ = z
  else
    rec.groundZ = c.z
  end
  return rec.groundZ
end

---------------------------------------------------------------------------------------
-- Evaluation (runs every 200 ms only while the player is near a point)
---------------------------------------------------------------------------------------

local function setActive(a)
  if a then
    NZ.NUI.prompt(a.label, currentKey())
  elseif active then
    NZ.NUI.prompt(nil)
  end
  active = a
end

--- Work out which action the player can take right now and which markers to draw.
local function evaluate()
  local blocked = acting or not NZ.State.ready or insideInterior() or NZ.NUI.isOpen() or IsPauseMenuActive()
  local ped = cache.ped
  local pos = GetEntityCoords(ped)
  local vehicle = GetVehiclePedIsIn(ped, false)
  local inVehicle = vehicle ~= 0
  local isDriver = inVehicle and GetPedInVehicleSeat(vehicle, -1) == ped
  local category = isDriver and categoryOf(vehicle) or nil
  local best, bestDist = nil, nil

  for rec in pairs(near) do
    rec.marker = nil
    if not blocked then
      local loc = rec.location
      local dist = #(pos - rec.coords)
      local action, label
      if inVehicle then
        if isDriver and rec.store and canStoreAt(loc) and (loc.vehicleType == nil or loc.vehicleType == category) then
          rec.marker = 'store'
          if dist <= rec.storeRadius then action, label = 'store', L('Store vehicle') end
        end
      elseif rec.open and rec.openAction then
        rec.marker = 'open'
        if not rec.targeted and dist <= rec.radius then action, label = rec.openAction, rec.openLabel end
      end
      if action and (bestDist == nil or dist < bestDist) then
        best, bestDist = { rec = rec, action = action, label = label }, dist
      end
    end
  end
  return best
end

local function startLoop()
  if looping then return end
  looping = true
  CreateThread(function()
    while nearCount > 0 do
      setActive(evaluate())
      Wait(200)
    end
    for rec in pairs(near) do rec.marker = nil end
    setActive(nil)
    looping = false
  end)
end

local function drawNearby(self)
  local rec = self.rec
  if not rec or not rec.marker then return end
  local c = rec.coords
  local z = groundZ(rec)
  local r, g, b = markerRGB[1], markerRGB[2], markerRGB[3]
  if rec.marker == 'open' then
    DrawMarker(20, c.x, c.y, z + 1.0, 0.0, 0.0, 0.0, 180.0, 0.0, 0.0, 0.35, 0.35, 0.25,
      r, g, b, 200, true, false, 2, true, nil, nil, false)
  else
    local d = rec.storeRadius * 2.0
    DrawMarker(25, c.x, c.y, z + 0.03, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, d, d, 1.0,
      r, g, b, 140, false, false, 2, false, nil, nil, false)
  end
end

local function onEnter(self)
  local rec = self.rec
  if not rec or near[rec] then return end
  near[rec] = true
  nearCount = nearCount + 1
  startLoop()
end

local function onExit(self)
  local rec = self.rec
  if not rec or not near[rec] then return end
  near[rec] = nil
  rec.marker = nil
  nearCount = math.max(0, nearCount - 1)
  if active and active.rec == rec then setActive(nil) end
end

---------------------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------------------

local function openGarage(loc)
  local extra = {}
  if type(loc.access) == 'table' and loc.access.mode == 'interior' then extra.goInside = true end
  if loc.kind == 'house' then
    extra.houseId = NZ.Garage.houseIdOf(loc)
    return NZ.Garage.open(nil, extra)
  end
  return NZ.Garage.open(loc.id, extra)
end

local function runAction(action, loc)
  if action == 'store' then
    NZ.Garage.store(loc)
  elseif action == 'impound' then
    NZ.ImpoundClient.open(loc.id)
  elseif action == 'forSale' then
    NZ.PrivateClient.openForSale(loc.id)
  elseif action == 'garage' then
    openGarage(loc)
  end
end

local function perform(action, loc)
  if acting then return end
  acting = true
  setActive(nil)
  CreateThread(function()
    local ok, err = pcall(runAction, action, loc)
    if not ok then
      lib.print.error(('[nayzeee-garages] interaction "%s" failed: %s'):format(action, err))
    end
    acting = false
  end)
end

local function dispatch()
  if acting or nearCount == 0 or not NZ.State.ready then return end
  local a = evaluate()
  if not a then return end
  perform(a.action, a.rec.location)
end

local function ensureKeybind()
  if keybind then return end
  keybind = lib.addKeybind({
    name = 'nz_interact',
    description = L('Garage interaction'),
    defaultKey = Config.Keys.interact or 'E',
    onPressed = function()
      dispatch()
    end,
  })
end

local function targetCanInteract()
  return NZ.State.ready and not acting and not insideInterior() and not NZ.NUI.isOpen()
    and GetVehiclePedIsIn(cache.ped, false) == 0
end

---------------------------------------------------------------------------------------
-- Building
---------------------------------------------------------------------------------------

local function defaultSprite(loc)
  if loc.kind == 'impound' then return 68 end
  if loc.vehicleType == 'sea' then return 356 end
  if loc.vehicleType == 'air' then return 359 end
  return 357
end

local function addBlip(loc)
  local b = loc.blip
  if type(b) ~= 'table' or not b.enabled then return end
  local coords
  if type(loc.openPoints) == 'table' and loc.openPoints[1] then
    coords = NZ.Utils.v3(loc.openPoints[1].coords)
  end
  if not coords and type(loc.spawnPoints) == 'table' then coords = NZ.Utils.v3(loc.spawnPoints[1]) end
  if not coords then return end
  local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
  SetBlipSprite(blip, math.floor(tonumber(b.sprite) or defaultSprite(loc)))
  SetBlipColour(blip, math.floor(tonumber(b.color) or 3))
  SetBlipScale(blip, (tonumber(b.scale) or 0.7) + 0.0)
  SetBlipDisplay(blip, 4)
  SetBlipAsShortRange(blip, true)
  BeginTextCommandSetBlipName('STRING')
  AddTextComponentSubstringPlayerName(type(loc.name) == 'string' and loc.name or L('Garage'))
  EndTextCommandSetBlipName(blip)
  blips[#blips + 1] = blip
end

local function addRecord(rec, drawMarkers)
  local markerDistance = drawMarkers and (tonumber(Config.Interaction.markerDistance) or 15.0) or 0.0
  local distance = math.max(rec.radius or 0.0, rec.store and rec.storeRadius or 0.0, markerDistance) + 0.5
  records[#records + 1] = rec
  pointObjs[#pointObjs + 1] = lib.points.new({
    coords = rec.coords,
    distance = distance,
    rec = rec,
    onEnter = onEnter,
    onExit = onExit,
    nearby = drawMarkers and drawNearby or nil,
  })
end

local function addLocation(loc, useTarget, showBlips, drawMarkers)
  if not Points.isVisible(loc) then return end
  local openAction, openLabel, icon = openActionFor(loc)
  local storable = canStoreAt(loc)
  if not openAction and not storable then return end

  local defaultOpen = tonumber(Config.Interaction.openRadius) or 2.0
  local defaultStore = tonumber(Config.Interaction.storeRadius) or 4.0
  local useOpenForStore = loc.useOpenForStore ~= false

  if type(loc.openPoints) == 'table' then
    for i, p in ipairs(loc.openPoints) do
      local coords = type(p) == 'table' and NZ.Utils.toVec3(p.coords)
      if coords then
        local radius = tonumber(p.radius) or defaultOpen
        local rec = {
          location = loc,
          coords = coords,
          open = openAction ~= nil,
          openAction = openAction,
          openLabel = openLabel,
          radius = radius,
          store = storable and useOpenForStore,
          storeRadius = math.max(radius, defaultStore),
        }
        if openAction and useTarget then
          local zoneId = ('nz_open_%s_%d'):format(tostring(loc.id), i)
          local ok, err = pcall(NZ.Target.addSphere, zoneId, coords, radius, {
            {
              label = openLabel,
              icon = icon,
              onSelect = function()
                if targetCanInteract() then perform(openAction, loc) end
              end,
              canInteract = function()
                return targetCanInteract()
              end,
            },
          })
          if ok then
            rec.targeted = true
            targetZones[#targetZones + 1] = zoneId
          else
            lib.print.warn(('[nayzeee-garages] target zone failed: %s'):format(err))
          end
        end
        if rec.open or rec.store then addRecord(rec, drawMarkers) end
      end
    end
  end

  if storable and not useOpenForStore and type(loc.storePoints) == 'table' then
    for _, p in ipairs(loc.storePoints) do
      local coords = type(p) == 'table' and NZ.Utils.toVec3(p.coords)
      if coords then
        addRecord({
          location = loc,
          coords = coords,
          open = false,
          radius = 0.0,
          store = true,
          storeRadius = tonumber(p.radius) or defaultStore,
        }, drawMarkers)
      end
    end
  end

  if showBlips and loc.kind ~= 'house' then addBlip(loc) end
end

--- Remove every point, target zone and blip and hide the prompt.
function Points.clear()
  for i = 1, #pointObjs do
    pcall(pointObjs[i].remove, pointObjs[i])
  end
  pointObjs = {}
  for i = 1, #records do records[i].marker = nil end
  records = {}
  near = {}
  nearCount = 0
  for i = 1, #targetZones do
    pcall(NZ.Target.remove, targetZones[i])
  end
  targetZones = {}
  for i = 1, #blips do
    if DoesBlipExist(blips[i]) then RemoveBlip(blips[i]) end
  end
  blips = {}
  setActive(nil)
end

--- (Re)create lib.points, target zones, markers and blips from NZ.State.
function Points.rebuild()
  Points.clear()
  ensureKeybind()
  local iface = interfaceSettings()
  parseAccent(iface.accent)
  local useTarget = iface.interaction == 'target' and type(NZ.Target.available) == 'function'
    and NZ.Target.available() == true
  local showBlips = garageSettings().showBlips ~= false
  local drawMarkers = Config.Interaction.drawMarkers == true

  for _, loc in pairs(NZ.State.locations or {}) do
    addLocation(loc, useTarget, showBlips, drawMarkers)
  end
  for _, loc in pairs(NZ.State.houses or {}) do
    addLocation(loc, useTarget, false, drawMarkers)
  end
  NZ.Utils.debug(('points rebuilt: %d interaction points, %d blips'):format(#records, #blips))
end

--- The action currently offered by the prompt: { action, location } or nil.
function Points.current()
  if not active then return nil end
  return { action = active.action, location = active.rec.location }
end

--- Closest visible location (within maxDist metres of one of its points) that passes
--- `filter(location, record)`. Used by exports called without a location id.
---@param filter function|nil
---@param maxDist number|nil default settings.garages.maxDistance
---@return table|nil location
function Points.nearestLocation(filter, maxDist)
  maxDist = tonumber(maxDist) or tonumber(garageSettings().maxDistance) or 25.0
  local pos = GetEntityCoords(cache.ped)
  local best, bestDist = nil, nil
  for i = 1, #records do
    local rec = records[i]
    local dist = #(pos - rec.coords)
    if dist <= maxDist and (bestDist == nil or dist < bestDist) and (not filter or filter(rec.location, rec)) then
      best, bestDist = rec.location, dist
    end
  end
  return best
end

AddEventHandler('onResourceStop', function(resource)
  if resource ~= NZ.ResourceName then return end
  for i = 1, #blips do
    if DoesBlipExist(blips[i]) then RemoveBlip(blips[i]) end
  end
  for i = 1, #targetZones do
    pcall(NZ.Target.remove, targetZones[i])
  end
end)
