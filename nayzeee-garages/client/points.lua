--[[
  nayzeee-garages — world interaction points (NZ.Points).
  Builds lib.points, target zones / garage NPCs, markers and blips for every location the
  player can use, shows the "Open garage" / "Store vehicle" prompt while inside a point and
  dispatches the single interaction keybind to the active point.
  No per-frame work unless the player is near a point (markers only).

  Interaction mode per location: location.interaction.mode ('default' follows
  settings.interface.interaction) — 'prompt' (press E), 'target' (ox_target / qb-target:
  open options on a sphere zone or on the location NPC; drivers still park with the key
  prompt) or 'both'. Without a running target resource every location uses prompts.
  Target options per point: Open garage / hangar / marina, Enter interior (access mode
  interior / both), View garage for sale (private, not owned), Open impound and Store vehicle
  (in or next to a vehicle). The global "Store vehicle" vehicle option (client/impound.lua)
  asks Points.canStoreVehicle / Points.storeVehicle, which only look at the store zones near
  the player (refreshed by the 200 ms loop).

  Garage zones (location.zone = { points = vec2[], minZ, maxZ }): an ox_lib lib.zones.poly
  per zone (no PolyZone). Inside it, on foot, the prompt opens the garage anywhere (modes
  'prompt' / 'both'; in 'target' mode the open point / NPC keeps the target options) and a
  driver stores the vehicle anywhere ("Store vehicle" prompt in every mode, the global vehicle
  target option too): the zone replaces the store circles of that location. The outline is
  drawn on the ground for drivers inside it. Locations without a zone are unchanged. The server
  checks the same polygon with the server ped position (NZ.Access.inZone).
]]

local Points = NZ.Points

local records = {}        -- every interaction record built by the last rebuild
local pointObjs = {}      -- lib.points objects
local near = {}           -- [record] = true while the player is within its point distance
local nearCount = 0
local nearStores = {}     -- target store records near the player (refreshed every 200 ms)
local blips = {}
local targetZones = {}
local keybind = nil
local active = nil        -- { rec, action, label } currently shown as prompt
local looping = false
local acting = false
local markerRGB = { 8, 175, 162 }

local MODES = { prompt = true, target = true, both = true }
local TARGET_REACH = 3.0           -- metres a player can target a vehicle from (store zones)
local ZONE_Z_MARGIN = 1.0          -- metres above / below a zone's height range still inside
-- lib.zones.poly thickness is generous (ox_lib's vertical test differs between versions):
-- the height range itself is checked here (zoneHas) like on the server.
local ZONE_THICKNESS_PAD = 8.0
local ZONE_GROUND_RETRY = 2000      -- ms: re-query corner ground heights that had no hit yet
-- Open actions a zone offers anywhere inside it. The impound and for-sale handlers on the
-- server (nz:impound:open, nz:forSale:info / buy / tour) still check the open point only, so
-- those keep the open point until they use NZ.Access.nearLocation; add 'impound' / 'forSale'
-- here at that point.
local ZONE_OPEN_ACTIONS = { garage = true, inside = true }
local NEXT_TO_VEHICLE = 6.0        -- metres: "next to a vehicle" for the store option
local CANDIDATE_TTL = 400          -- ms: cache of the vehicle a store option would park

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function insideInterior()
  return NZ.Interior ~= nil and type(NZ.Interior.isInside) == 'function' and NZ.Interior.isInside() == true
end

---------------------------------------------------------------------------------------
-- Player condition (dead / downed / cuffed / escorted)
---------------------------------------------------------------------------------------

-- State bags set by common death / police resources (only `true` counts).
local CONDITION_BAGS = {
  'isDead', 'dead', 'inLaststand', 'laststand', 'isCuffed', 'isHandcuffed', 'handcuffed',
  'cuffed', 'isEscorted', 'escorted',
}
local frameworkDown = false     -- qb / qbx metadata isdead, inlaststand, ishandcuffed
local esxDead = false           -- esx:onPlayerDeath until esx:onPlayerSpawn

-- Player apps closed when the player goes down (the admin tools stay open).
local PLAYER_APPS = { 'garage', 'impound', 'impoundForm', 'forSale', 'setup', 'interior' }

local function closeAppsWhenDown()
  if not NZ.NUI.isOpen() or not Points.incapacitated() then return end
  -- frees the mouse / keyboard (respawn prompt, interrogation...) and stops the action
  for i = 1, #PLAYER_APPS do
    if NZ.NUI.isOpen(PLAYER_APPS[i]) then pcall(NZ.NUI.close, PLAYER_APPS[i]) end
  end
end

local function readMetadata(data)
  local md = type(data) == 'table' and type(data.metadata) == 'table' and data.metadata or nil
  if not md then return end
  local down = md.isdead == true or md.inlaststand == true or md.ishandcuffed == true
  local changed = down ~= frameworkDown
  frameworkDown = down
  if changed and down then closeAppsWhenDown() end
end

if NZ.Framework == 'qb' or NZ.Framework == 'qbx' then
  RegisterNetEvent('QBCore:Player:SetPlayerData', readMetadata)
  local function fetchMetadata()
    local ok, data = pcall(function()
      if NZ.Framework == 'qbx' then return exports.qbx_core:GetPlayerData() end
      return exports['qb-core']:GetCoreObject().Functions.GetPlayerData()
    end)
    if ok then readMetadata(data) end
  end
  AddEventHandler('nz:client:playerLoaded', fetchMetadata)
  CreateThread(fetchMetadata) -- resource restart while the character is loaded
elseif NZ.Framework == 'esx' then
  RegisterNetEvent('esx:onPlayerDeath', function()
    esxDead = true
    closeAppsWhenDown()
  end)
  RegisterNetEvent('esx:onPlayerSpawn', function() esxDead = false end)
  AddEventHandler('playerSpawned', function() esxDead = false end)
end
AddEventHandler('nz:client:playerUnloaded', function()
  frameworkDown, esxDead = false, false
end)

-- Killed while a menu has focus: release it at once.
AddEventHandler('gameEventTriggered', function(name, args)
  if name ~= 'CEventNetworkEntityDamage' or type(args) ~= 'table' then return end
  if args[1] ~= PlayerPedId() then return end
  closeAppsWhenDown()
end)

-- Cuffed / escorted / downed by a resource that fires none of the events above.
CreateThread(function()
  while true do
    Wait(1000)
    if NZ.State.ready and NZ.NUI.isOpen() then closeAppsWhenDown() end
  end
end)

--- Whether the player cannot use garages right now: dead or dying, downed (last stand),
--- cuffed, or carried / escorted by someone (attached to another ped).
---@return boolean
function Points.incapacitated()
  if frameworkDown or esxDead then return true end
  local ped = PlayerPedId()
  if IsEntityDead(ped) or IsPedFatallyInjured(ped) or IsPedCuffed(ped) or IsEntityAttachedToAnyPed(ped) then
    return true
  end
  local bag = LocalPlayer and LocalPlayer.state
  if bag then
    for i = 1, #CONDITION_BAGS do
      if bag[CONDITION_BAGS[i]] == true then return true end
    end
  end
  return false
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

--- Access mode of a garage-like location: 'quick' | 'interior' | 'both' (server falls back to
--- 'quick' when no interior is set).
local function accessMode(loc)
  local a = type(loc.access) == 'table' and loc.access or nil
  if a and (a.mode == 'interior' or a.mode == 'both') then return a.mode end
  return 'quick'
end

--- "Open garage" / "Open hangar" / "Open marina" ("Open job garage" for job car garages).
local function openLabelFor(loc)
  if loc.vehicleType == 'air' then return L('Open hangar') end
  if loc.vehicleType == 'sea' then return L('Open marina') end
  if loc.kind == 'job' then return L('Open job garage') end
  return L('Open garage')
end

local function openIconFor(loc)
  if loc.vehicleType == 'air' then return 'fas fa-plane' end
  if loc.vehicleType == 'sea' then return 'fas fa-anchor' end
  return 'fas fa-warehouse'
end

--- Open action + prompt label for a location (nil when the player cannot open it).
local function openActionFor(loc)
  local kind = loc.kind
  if kind == 'impound' then return 'impound', L('Open impound') end
  if kind == 'private' and not Points.isMember(loc) then
    if loc.purchasable then return 'forSale', L('View garage') end
    return nil
  end
  if accessMode(loc) == 'interior' then return 'inside', L('Enter interior') end
  return 'garage', openLabelFor(loc)
end

local function canStoreAt(loc)
  if loc.kind == 'impound' then return false end
  if loc.kind == 'private' and not Points.isMember(loc) then return false end
  return true
end

--- Interaction mode of a location: its own override, else the server setting. 'prompt' when
--- no target resource runs (players must always be able to open their garage).
local function modeFor(loc, globalMode, targetOk)
  local mode = MODES[globalMode] and globalMode or 'prompt'
  local own = type(loc.interaction) == 'table' and loc.interaction.mode or nil
  if own ~= nil and MODES[own] then mode = own end
  if mode ~= 'prompt' and not targetOk then return 'prompt' end
  return mode
end

--- The location NPC ({ model, scenario }) or nil.
local function pedConfig(loc)
  local i = loc.interaction
  local ped = type(i) == 'table' and i.ped or nil
  if type(ped) ~= 'table' or type(ped.model) ~= 'string' or ped.model == '' then return nil end
  return ped
end

local function categoryOf(vehicle)
  if NZ.Veh and NZ.Veh.categoryOf then
    local ok, cat = pcall(NZ.Veh.categoryOf, GetEntityModel(vehicle))
    if ok and cat then return cat end
  end
  return NZ.Utils.vehicleTypeFromClass(GetVehicleClass(vehicle))
end

local function isVehicleEntity(entity)
  return type(entity) == 'number' and entity ~= 0 and DoesEntityExist(entity) and GetEntityType(entity) == 2
end

--- Whether the player was the last driver of `vehicle`: their own car left in the zone, not a
--- stranger's parked car or one they only rode in. When this client does not know the last
--- driver, the player's last vehicle counts. The server still checks ownership.
local function droveIt(vehicle, ped)
  local lastDriver = GetLastPedInVehicleSeat(vehicle, -1)
  if lastDriver == ped then return true end
  return (lastDriver == 0 or lastDriver == nil) and GetVehiclePedIsIn(ped, true) == vehicle
end

--- The vehicle the player may park with a "Store vehicle" option: the one they drive, or (on
--- foot) one they drove last.
local function ownVehicle(vehicle, ped)
  local current = GetVehiclePedIsIn(ped, false)
  if current ~= 0 then return current == vehicle and GetPedInVehicleSeat(vehicle, -1) == ped end
  return droveIt(vehicle, ped)
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
-- Garage zones (polygon geometry, the same rules as server/locations.lua)
---------------------------------------------------------------------------------------

local function pointInPolygon(points, x, y)
  local inside = false
  local n = #points
  local j = n
  for i = 1, n do
    local a, b = points[i], points[j]
    if (a.y > y) ~= (b.y > y) then
      local xi = (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x
      if x < xi then inside = not inside end
    end
    j = i
  end
  return inside
end

local function distToSegment(px, py, a, b)
  local dx, dy = b.x - a.x, b.y - a.y
  local len2 = dx * dx + dy * dy
  local t = 0.0
  if len2 > 0 then t = math.max(0.0, math.min(1.0, ((px - a.x) * dx + (py - a.y) * dy) / len2)) end
  local cx, cy = a.x + dx * t - px, a.y + dy * t - py
  return math.sqrt(cx * cx + cy * cy)
end

--- Horizontal distance to the zone: 0 inside, else to the nearest edge.
local function zoneDistance(points, x, y)
  if pointInPolygon(points, x, y) then return 0.0 end
  local best = math.huge
  local n = #points
  for i = 1, n do
    local d = distToSegment(x, y, points[i], points[i % n + 1])
    if d < best then best = d end
  end
  return best
end

--- A usable zone from a client view: { points = {{x,y}}, minZ, maxZ } (3+ numeric points) or nil.
local function zoneOf(loc)
  local z = type(loc) == 'table' and loc.zone or nil
  if type(z) ~= 'table' or type(z.points) ~= 'table' then return nil end
  local minZ, maxZ = tonumber(z.minZ), tonumber(z.maxZ)
  if not minZ or not maxZ or maxZ <= minZ then return nil end
  local points = {}
  for _, p in ipairs(z.points) do
    local x, y = type(p) == 'table' and tonumber(p.x), type(p) == 'table' and tonumber(p.y)
    if x and y then points[#points + 1] = { x = x, y = y } end
  end
  if #points < 3 then return nil end
  return { points = points, minZ = minZ, maxZ = maxZ }
end

--- Whether `pos` is inside the zone (height range ± ZONE_Z_MARGIN, `margin` metres outside an edge).
local function zoneHas(zone, pos, margin)
  if not zone or not pos then return false end
  local z = pos.z
  if z < zone.minZ - ZONE_Z_MARGIN or z > zone.maxZ + ZONE_Z_MARGIN then return false end
  return zoneDistance(zone.points, pos.x, pos.y) <= (margin or 0.0)
end

--- Whether `pos` ({x,y,z} / vector3) is inside the garage zone of `loc` (false without a zone).
---@param loc table client view
---@param pos table|vector3
---@param margin number|nil metres outside an edge still counted (default 0)
---@return boolean
function Points.inZone(loc, pos, margin)
  local zone = zoneOf(loc)
  if not zone or pos == nil then return false end
  local x, y, z = tonumber(pos.x), tonumber(pos.y), tonumber(pos.z)
  if not x or not y or not z then return false end
  return zoneHas(zone, { x = x, y = y, z = z }, tonumber(margin))
end

--- Centre (vertex average) of a zone, at the middle of its height range.
local function zoneCentre(zone)
  local sx, sy = 0.0, 0.0
  for i = 1, #zone.points do
    sx, sy = sx + zone.points[i].x, sy + zone.points[i].y
  end
  local n = #zone.points
  return vector3(sx / n, sy / n, (zone.minZ + zone.maxZ) / 2.0)
end

--- Ground height under every corner (once per visit; collision is loaded around the player).
--- Corners without a hit yet (collision not streamed at the far end of a big zone) use
--- `fallback` and are asked again every ZONE_GROUND_RETRY ms while the player is inside.
local function zoneGround(rec, fallback)
  local list = rec.groundZs
  local now = GetGameTimer()
  if list and not (rec.groundMissing and now >= (rec.groundRetryAt or 0)) then return list end
  local zone = rec.zone
  local first = list == nil
  list = list or {}
  local missing = nil
  for i, p in ipairs(zone.points) do
    if first or (rec.groundMissing and rec.groundMissing[i]) then
      local found, gz = GetGroundZFor_3dCoord(p.x + 0.0, p.y + 0.0, zone.maxZ + 0.5, false)
      gz = tonumber(gz)
      if found and gz and gz >= zone.minZ - 2.0 and gz <= zone.maxZ + 1.0 then
        list[i] = gz
      else
        list[i] = fallback
        missing = missing or {}
        missing[i] = true
      end
    end
  end
  rec.groundZs = list
  rec.groundMissing = missing
  rec.groundRetryAt = missing and (now + ZONE_GROUND_RETRY) or nil
  return list
end

---------------------------------------------------------------------------------------
-- Store candidates (target "Store vehicle")
---------------------------------------------------------------------------------------

--- Whether this player can park `vehicle` at store record `rec`: inside the store radius,
--- the right vehicle type and nobody else behind the wheel (the server re-checks everything).
local function parkableAt(rec, vehicle, ped)
  if not isVehicleEntity(vehicle) then return false end
  local driver = GetPedInVehicleSeat(vehicle, -1)
  if driver ~= 0 and driver ~= ped then return false end
  if rec.zone then
    if not zoneHas(rec.zone, GetEntityCoords(vehicle), 0.0) then return false end
  elseif #(GetEntityCoords(vehicle) - rec.coords) > rec.storeRadius then
    return false
  end
  local vt = rec.location.vehicleType
  return vt == nil or vt == categoryOf(vehicle)
end

--- The vehicle a "Store vehicle" option at `rec` would park: the one the player drives, else
--- (on foot, next to it) a vehicle they drove last: their last vehicle, or the closest one
--- when they were its last driver. Never someone else's car. Cached briefly: target resources
--- ask many times per second while the option is on screen.
local function storeCandidate(rec)
  local now = GetGameTimer()
  local cached = rec.candidate
  if cached and now - cached.at < CANDIDATE_TTL then return cached.vehicle end
  local ped = cache.ped
  local vehicle = nil
  local current = GetVehiclePedIsIn(ped, false)
  if current ~= 0 then
    if GetPedInVehicleSeat(current, -1) == ped and parkableAt(rec, current, ped) then vehicle = current end
  else
    local pos = GetEntityCoords(ped)
    local last = GetVehiclePedIsIn(ped, true)
    if last ~= 0 and droveIt(last, ped) and parkableAt(rec, last, ped) and #(GetEntityCoords(last) - pos) <= NEXT_TO_VEHICLE then
      vehicle = last
    else
      local closest = lib.getClosestVehicle(pos, NEXT_TO_VEHICLE, false)
      if closest and closest ~= last and droveIt(closest, ped) and parkableAt(rec, closest, ped) then vehicle = closest end
    end
  end
  rec.candidate = { at = now, vehicle = vehicle }
  return vehicle
end

--- Nearest store record near the player (target mode) whose zone holds `vehicle` (only the
--- vehicle the player drives or drove last: other players' parked cars get no option).
local function storeRecordFor(vehicle)
  if #nearStores == 0 or not isVehicleEntity(vehicle) then return nil end
  local ped = cache.ped
  local driver = GetPedInVehicleSeat(vehicle, -1)
  if driver ~= 0 and driver ~= ped then return nil end
  if not ownVehicle(vehicle, ped) then return nil end
  local pos = GetEntityCoords(vehicle)
  local category = nil
  local best, bestDist = nil, nil
  for i = 1, #nearStores do
    local rec = nearStores[i]
    local dist, within
    if rec.zone then
      within = zoneHas(rec.zone, pos, 0.0)
      dist = 0.0
    else
      dist = #(pos - rec.coords)
      within = dist <= rec.storeRadius
    end
    if within and (bestDist == nil or dist < bestDist) then
      local vt = rec.location.vehicleType
      if vt ~= nil and category == nil then category = categoryOf(vehicle) end
      if (vt == nil or vt == category) and Points.isVisible(rec.location) then
        best, bestDist = rec, dist
      end
    end
  end
  return best
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
    or Points.incapacitated()
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
      if rec.zone then
        -- anywhere inside the polygon (no circle): distance 0 wins over nearby points
        local inside = zoneHas(rec.zone, pos, 0.0)
        dist = inside and 0.0 or math.huge
        if inVehicle then
          if isDriver and rec.store and canStoreAt(loc) and (loc.vehicleType == nil or loc.vehicleType == category) then
            rec.marker = 'zone'
            if inside then action, label = 'store', L('Store vehicle') end
          end
        elseif inside and rec.open and rec.openAction and not rec.targeted then
          action, label = rec.openAction, rec.openLabel
        end
      elseif inVehicle then
        if isDriver and rec.store and canStoreAt(loc) and (loc.vehicleType == nil or loc.vehicleType == category) then
          rec.marker = 'store'
          if dist <= rec.storeRadius then action, label = 'store', L('Store vehicle') end
        end
      elseif rec.open and rec.openAction then
        -- the NPC marks the spot itself
        if not rec.hasPed then rec.marker = 'open' end
        if not rec.targeted and dist <= rec.radius then action, label = rec.openAction, rec.openLabel end
      end
      if action and (bestDist == nil or dist < bestDist) then
        best, bestDist = { rec = rec, action = action, label = label }, dist
      end
    end
  end
  return best
end

--- Target store records near the player, for the cheap global vehicle option check.
local function refreshNearStores()
  local list = {}
  for rec in pairs(near) do
    if rec.targetStore then list[#list + 1] = rec end
  end
  nearStores = list
end

local function startLoop()
  if looping then return end
  looping = true
  CreateThread(function()
    while nearCount > 0 do
      setActive(evaluate())
      refreshNearStores()
      Wait(200)
    end
    for rec in pairs(near) do rec.marker = nil end
    nearStores = {}
    setActive(nil)
    looping = false
  end)
end

--- Ground outline of a zone (drivers who can park here; every frame while inside).
local function drawZone(self)
  local rec = self.rec
  if not rec or rec.marker ~= 'zone' then return end
  local zone = rec.zone
  local ground = zoneGround(rec, GetEntityCoords(cache.ped).z - 1.0)
  local r, g, b = markerRGB[1], markerRGB[2], markerRGB[3]
  local n = #zone.points
  for i = 1, n do
    local a, c = zone.points[i], zone.points[i % n + 1]
    local az, cz = ground[i] + 0.06, ground[i % n + 1] + 0.06
    DrawLine(a.x, a.y, az, c.x, c.y, cz, r, g, b, 210)
    DrawLine(a.x, a.y, az, a.x, a.y, az + 0.9, r, g, b, 150)
  end
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
  rec.groundZs, rec.groundMissing, rec.groundRetryAt = nil, nil, nil
  nearCount = math.max(0, nearCount - 1)
  if active and active.rec == rec then setActive(nil) end
end

---------------------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------------------

local function openGarage(loc, inside)
  local extra = {}
  if inside or accessMode(loc) == 'interior' then extra.goInside = true end
  if loc.kind == 'house' then
    extra.houseId = NZ.Garage.houseIdOf(loc)
    return NZ.Garage.open(nil, extra)
  end
  return NZ.Garage.open(loc.id, extra)
end

--- Park `vehicle` at `loc`. On foot the player first gets behind the wheel: the server only
--- stores a vehicle for its driver.
local function storeEntity(loc, vehicle)
  local ped = cache.ped
  if not isVehicleEntity(vehicle) then
    NZ.NUI.notify('error', L('Vehicle not found'))
    return false
  end
  local current = GetVehiclePedIsIn(ped, false)
  if current == vehicle and GetPedInVehicleSeat(vehicle, -1) == ped then return NZ.Garage.store(loc) end
  if current ~= 0 then
    NZ.NUI.notify('error', L('You must be driving the vehicle'))
    return false
  end
  -- never walk the player into someone else's car (the server would refuse it after)
  if not droveIt(vehicle, ped) then
    NZ.NUI.notify('error', L('You can only store a vehicle you drove here'))
    return false
  end
  local driver = GetPedInVehicleSeat(vehicle, -1)
  if driver ~= 0 and driver ~= ped then
    NZ.NUI.notify('error', L('Someone is in the driver seat'))
    return false
  end
  if (tonumber(GetVehicleDoorLockStatus(vehicle)) or 0) >= 2 then
    NZ.NUI.notify('error', L('The vehicle is locked'))
    return false
  end

  TaskEnterVehicle(ped, vehicle, 8000, -1, 1.5, 1, 0)
  local started = GetGameTimer()
  while GetGameTimer() - started < 9000 do
    Wait(100)
    if not DoesEntityExist(vehicle) or Points.incapacitated() then break end
    if GetPedInVehicleSeat(vehicle, -1) == ped and IsPedInVehicle(ped, vehicle, false) then break end
    -- walked away / pushed out: the enter task ended without getting in
    if GetGameTimer() - started > 1000 and not IsPedInVehicle(ped, vehicle, true) and not GetIsTaskActive(ped, 160) then
      break
    end
  end
  if not DoesEntityExist(vehicle) or GetPedInVehicleSeat(vehicle, -1) ~= ped then
    NZ.NUI.notify('error', L('Get behind the wheel to store the vehicle'))
    return false
  end
  return NZ.Garage.store(loc)
end

local function runAction(action, loc, arg)
  if action == 'store' then
    NZ.Garage.store(loc)
  elseif action == 'storeEntity' then
    storeEntity(loc, arg)
  elseif action == 'impound' then
    NZ.ImpoundClient.open(loc.id)
  elseif action == 'forSale' then
    NZ.PrivateClient.openForSale(loc.id)
  elseif action == 'garage' then
    openGarage(loc, false)
  elseif action == 'inside' then
    openGarage(loc, true)
  end
end

local function perform(action, loc, arg)
  if acting then return end
  acting = true
  setActive(nil)
  CreateThread(function()
    local ok, err = pcall(runAction, action, loc, arg)
    if not ok then
      lib.print.error(('[nayzeee-garages] interaction "%s" failed: %s'):format(action, err))
    end
    acting = false
  end)
end

local function dispatch()
  if acting or nearCount == 0 or not NZ.State.ready or Points.incapacitated() then return end
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

---------------------------------------------------------------------------------------
-- Target options (sphere zones and location NPCs)
---------------------------------------------------------------------------------------

-- Player-wide part of the target checks, cached for READY_TTL ms: ox_target asks every
-- option's canInteract on each pass (~50-100 ms), and a 3-option NPC would repeat it 3 times.
local READY_TTL = 150
local readyCache = { at = -100000, value = false }

local function baseReady(fresh)
  local now = GetGameTimer()
  if fresh or now - readyCache.at > READY_TTL then
    readyCache.value = NZ.State.ready == true and not insideInterior() and not NZ.NUI.isOpen()
      and not IsPauseMenuActive() and not Points.incapacitated()
    readyCache.at = now
  end
  return readyCache.value
end

--- Shared target checks, the same rules the prompt follows (the server stays the authority).
--- `fresh` skips the cache (onSelect).
local function targetReady(loc, fresh)
  return not acting and baseReady(fresh) and Points.isVisible(loc)
end

local function onFoot()
  return GetVehiclePedIsIn(cache.ped, false) == 0
end

local function actionOption(loc, label, icon, action)
  return {
    label = label,
    icon = icon,
    canInteract = function()
      return targetReady(loc) and onFoot()
    end,
    onSelect = function()
      if targetReady(loc, true) and onFoot() then perform(action, loc) end
    end,
  }
end

local function storeOption(rec)
  local loc = rec.location
  return {
    label = L('Store vehicle'),
    icon = 'fas fa-square-parking',
    canInteract = function(entity)
      -- a targeted vehicle gets the global "Store vehicle" vehicle option instead
      if isVehicleEntity(entity) or not targetReady(loc) then return false end
      return storeCandidate(rec) ~= nil
    end,
    onSelect = function()
      if not targetReady(loc, true) then return end
      rec.candidate = nil
      local vehicle = storeCandidate(rec)
      if vehicle then perform('storeEntity', loc, vehicle) end
    end,
  }
end

--- Target options of an interaction point: open actions first, then "Store vehicle".
local function pointOptions(loc, rec)
  local list = {}
  if rec.open then
    if loc.kind == 'impound' then
      list[#list + 1] = actionOption(loc, L('Open impound'), 'fas fa-car-burst', 'impound')
    elseif loc.kind == 'private' and not Points.isMember(loc) then
      list[#list + 1] = actionOption(loc, L('View garage for sale'), 'fas fa-key', 'forSale')
    else
      local access = accessMode(loc)
      if access ~= 'interior' then list[#list + 1] = actionOption(loc, openLabelFor(loc), openIconFor(loc), 'garage') end
      if access ~= 'quick' then list[#list + 1] = actionOption(loc, L('Enter interior'), 'fas fa-door-open', 'inside') end
    end
  end
  if rec.store then list[#list + 1] = storeOption(rec) end
  return list
end

local function addZone(zoneId, coords, radius, options)
  if #options == 0 then return false end
  local ok, added = pcall(NZ.Target.addSphere, zoneId, coords, radius, options)
  if ok and added then
    targetZones[#targetZones + 1] = zoneId
    return true
  end
  if not ok then lib.print.warn(('[nayzeee-garages] target zone failed: %s'):format(added)) end
  return false
end

--- NPC heading: the point's own heading when it has one, else facing the first spawn point.
local function pedHeading(loc, point, coords)
  local h = tonumber(point.heading) or (type(point.coords) == 'table' and tonumber(point.coords.w)) or nil
  if h then return h % 360.0 end
  local spawn = type(loc.spawnPoints) == 'table' and NZ.Utils.v3(loc.spawnPoints[1]) or nil
  if spawn then
    local dx, dy = spawn.x - coords.x, spawn.y - coords.y
    if dx * dx + dy * dy > 0.01 then return (math.deg(math.atan(dy, dx)) - 90.0) % 360.0 end
  end
  return 0.0
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
  -- target store zones join `near` a little earlier: vehicles are targeted from a few metres
  local storeReach = rec.store and (rec.storeRadius + (rec.targetStore and TARGET_REACH or 0.0)) or 0.0
  local distance = math.max(rec.radius or 0.0, storeReach, markerDistance) + 0.5
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

--- A zone record: an ox_lib poly zone; entering it starts the evaluation loop like a point.
local function addZoneRecord(rec, drawMarkers)
  local zone = rec.zone
  local mid = (zone.minZ + zone.maxZ) / 2.0
  local points = {}
  for i = 1, #zone.points do
    points[i] = vector3(zone.points[i].x, zone.points[i].y, mid)
  end
  local ok, obj = pcall(lib.zones.poly, {
    points = points,
    thickness = (zone.maxZ - zone.minZ) * 2.0 + ZONE_Z_MARGIN * 2.0 + ZONE_THICKNESS_PAD,
    rec = rec,
    onEnter = onEnter,
    onExit = onExit,
    inside = drawMarkers and drawZone or nil,
  })
  if not ok or not obj then
    lib.print.warn(('[nayzeee-garages] garage zone of "%s" failed: %s'):format(tostring(rec.location.name), tostring(obj)))
    return
  end
  records[#records + 1] = rec
  pointObjs[#pointObjs + 1] = obj
end

--- ctx = { globalMode, targetOk, drawMarkers, peds = {} (NPC specs for NZ.Peds.sync) }
local function addLocation(loc, ctx, showBlips)
  if not Points.isVisible(loc) then return end
  local openAction, openLabel = openActionFor(loc)
  local storable = canStoreAt(loc)
  if not openAction and not storable then return end

  local mode = modeFor(loc, ctx.globalMode, ctx.targetOk)
  local useTarget = mode ~= 'prompt'
  local ped = useTarget and pedConfig(loc) or nil
  local defaultOpen = tonumber(Config.Interaction.openRadius) or 2.0
  local defaultStore = tonumber(Config.Interaction.storeRadius) or 4.0
  local zone = zoneOf(loc)
  -- a zone replaces the store circles: drivers park anywhere inside it
  local useOpenForStore = loc.useOpenForStore ~= false and not zone
  local storeAtPoints = storable and not zone

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
          store = storeAtPoints and useOpenForStore,
          storeRadius = math.max(radius, defaultStore),
        }
        rec.targetStore = useTarget and rec.store
        if useTarget then
          local options = pointOptions(loc, rec)
          local handled
          if ped and i == 1 and #options > 0 then
            -- the NPC carries the options of the first open point (NZ.Peds falls back to a
            -- sphere zone when its model cannot be loaded)
            rec.hasPed = true
            ctx.peds[#ctx.peds + 1] = {
              id = tostring(loc.id),
              coords = coords,
              heading = pedHeading(loc, p, coords),
              model = ped.model,
              scenario = type(ped.scenario) == 'string' and ped.scenario or '',
              radius = radius,
              options = options,
            }
            handled = true
          else
            handled = addZone(('nz_open_%s_%d'):format(tostring(loc.id), i), coords, radius, options)
          end
          -- 'target' replaces the on-foot prompt; drivers still park with the key prompt
          rec.targeted = handled and mode == 'target' and rec.open
        end
        if rec.open or rec.store then addRecord(rec, ctx.drawMarkers) end
      end
    end
  end

  if storeAtPoints and not useOpenForStore and type(loc.storePoints) == 'table' then
    for i, p in ipairs(loc.storePoints) do
      local coords = type(p) == 'table' and NZ.Utils.toVec3(p.coords)
      if coords then
        local rec = {
          location = loc,
          coords = coords,
          open = false,
          radius = 0.0,
          store = true,
          storeRadius = tonumber(p.radius) or defaultStore,
          targetStore = useTarget,
        }
        if useTarget then
          addZone(('nz_store_%s_%d'):format(tostring(loc.id), i), coords, rec.storeRadius, { storeOption(rec) })
        end
        addRecord(rec, ctx.drawMarkers)
      end
    end
  end

  local zoneAction = openAction ~= nil and ZONE_OPEN_ACTIONS[openAction] == true
  -- 'target': the open point / NPC carries the open options, no on-foot prompt in the zone
  local zoneOpen = zoneAction and mode ~= 'target'
  if zone and (zoneOpen or storable) then
    addZoneRecord({
      location = loc,
      zone = zone,
      coords = zoneCentre(zone),
      open = zoneOpen,
      openAction = openAction,
      openLabel = openLabel,
      radius = 0.0,
      store = storable,
      storeRadius = 0.0,
      targetStore = useTarget and storable,
    }, ctx.drawMarkers)
  end

  if showBlips and loc.kind ~= 'house' then addBlip(loc) end
end

--- Remove points, target zones and blips (NPCs are kept: rebuild hands them to NZ.Peds.sync).
local function clearPoints()
  for i = 1, #pointObjs do
    pcall(pointObjs[i].remove, pointObjs[i])
  end
  pointObjs = {}
  for i = 1, #records do records[i].marker = nil end
  records = {}
  near = {}
  nearCount = 0
  nearStores = {}
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

--- Remove every point, target zone, NPC and blip and hide the prompt.
function Points.clear()
  clearPoints()
  if type(NZ.Peds.clear) == 'function' then
    local ok, err = pcall(NZ.Peds.clear)
    if not ok then lib.print.error(('[nayzeee-garages] could not remove garage NPCs: %s'):format(err)) end
  end
end

--- (Re)create lib.points, target zones, NPCs, markers and blips from NZ.State.
function Points.rebuild()
  clearPoints()
  ensureKeybind()
  local iface = interfaceSettings()
  parseAccent(iface.accent)
  local ctx = {
    globalMode = iface.interaction,
    targetOk = type(NZ.Target.available) == 'function' and NZ.Target.available() == true,
    drawMarkers = Config.Interaction.drawMarkers == true,
    peds = {},
  }
  local showBlips = garageSettings().showBlips ~= false

  for _, loc in pairs(NZ.State.locations or {}) do
    addLocation(loc, ctx, showBlips)
  end
  for _, loc in pairs(NZ.State.houses or {}) do
    -- hidden: the housing script shows the garage interaction itself (OpenHouseGarage)
    if loc.hidden ~= true then addLocation(loc, ctx, false) end
  end
  if type(NZ.Peds.sync) == 'function' then
    local ok, err = pcall(NZ.Peds.sync, ctx.peds)
    if not ok then lib.print.error(('[nayzeee-garages] garage NPCs failed: %s'):format(err)) end
  end
  NZ.Utils.debug(('points rebuilt: %d interaction points, %d target zones, %d NPCs, %d blips'):format(
    #records, #targetZones, #ctx.peds, #blips))
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
    local dist
    if rec.zone then
      dist = (pos.z >= rec.zone.minZ - ZONE_Z_MARGIN and pos.z <= rec.zone.maxZ + ZONE_Z_MARGIN)
        and zoneDistance(rec.zone.points, pos.x, pos.y) or math.huge
    else
      dist = #(pos - rec.coords)
    end
    if dist <= maxDist and (bestDist == nil or dist < bestDist) and (not filter or filter(rec.location, rec)) then
      best, bestDist = rec.location, dist
    end
  end
  return best
end

---------------------------------------------------------------------------------------
-- Global "Store vehicle" vehicle option (registered in client/impound.lua)
---------------------------------------------------------------------------------------

local vehicleCheck = { entity = nil, at = -100000, rec = nil }

--- Cheap canInteract for the vehicle option: true when `vehicle` stands in a store zone of a
--- target / both mode garage this player can use. Only looks at the store zones near the
--- player (none nearby = one table length check).
---@param vehicle number
---@return boolean
function Points.canStoreVehicle(vehicle)
  if #nearStores == 0 or acting or not baseReady() then return false end
  local now = GetGameTimer()
  if vehicleCheck.entity ~= vehicle or now - vehicleCheck.at >= CANDIDATE_TTL then
    vehicleCheck = { entity = vehicle, at = now, rec = storeRecordFor(vehicle) }
  end
  return vehicleCheck.rec ~= nil
end

--- Park the targeted vehicle at the garage whose store zone holds it (the player gets in
--- first when on foot).
---@param vehicle number
---@return boolean started
function Points.storeVehicle(vehicle)
  if acting or not NZ.State.ready or Points.incapacitated() then return false end
  local rec = storeRecordFor(vehicle)
  if not rec then
    NZ.NUI.notify('error', L('Park the vehicle in a garage parking zone first'))
    return false
  end
  perform('storeEntity', rec.location, vehicle)
  return true
end

-- A target resource started or stopped: rebuild so target-mode locations switch between
-- third-eye and the prompt fallback (the bridge only re-creates what already exists).
local targetRebuildQueued = false
local function onTargetResource(resource)
  if (resource ~= 'ox_target' and resource ~= 'qb-target') or targetRebuildQueued then return end
  targetRebuildQueued = true
  SetTimeout(1000, function()
    targetRebuildQueued = false
    if not NZ.State.ready then return end
    local ok, err = pcall(Points.rebuild)
    if not ok then lib.print.error(('[nayzeee-garages] points rebuild failed: %s'):format(err)) end
    -- global vehicle options when the target resource was not running at boot (idempotent)
    if type(NZ.ImpoundClient.setupTarget) == 'function' then pcall(NZ.ImpoundClient.setupTarget) end
  end)
end
AddEventHandler('onClientResourceStart', onTargetResource)
AddEventHandler('onClientResourceStop', onTargetResource)

AddEventHandler('onResourceStop', function(resource)
  if resource ~= NZ.ResourceName then return end
  for i = 1, #blips do
    if DoesBlipExist(blips[i]) then RemoveBlip(blips[i]) end
  end
  for i = 1, #targetZones do
    pcall(NZ.Target.remove, targetZones[i])
  end
end)
