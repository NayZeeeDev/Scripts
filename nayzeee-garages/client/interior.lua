--[[
  nayzeee-garages — multiplayer garage interiors, client side (NZ.Interior, §7.7).
  Loads the interior (IPL profile + entity sets), teleports in, shows the garage's vehicles
  as local display copies, stats HUD while seated, "accelerate to drive out", the exit
  marker, the control panel (NUI app 'interior'), invites, kicks and member syncs.
  Also hosts the shared IPL / teleport helpers used by the creator and the admin client.
]]

local Interior = NZ.Interior
local Utils = NZ.Utils

local FADE_MS = 500
local COLLISION_TIMEOUT = 5000
local LOOP_IDLE = 250
local EXIT_DISTANCE = 12.0      -- exit marker visible from here
local EXIT_RADIUS = 1.5         -- "Leave garage" prompt radius
local EXIT_ARM_MS = 2000        -- the exit (often == entry) arms shortly after arriving
local AWAY_MARGIN_XY = 30.0     -- teleported away (admin, respawn): this far (horizontally) or
local AWAY_MARGIN_Z = 15.0      -- this far (vertically) outside the entry / exit / slots area
local AWAY_CONFIRM_MS = 2000    -- ... for this long: leave the instance where they are
local DRIVE_LOCK_MS = 3000      -- after a refused drive out
local RETURN_KVP = 'nz_interior_return' -- { entry, returnTo, identifier, at } while inside
local CREATOR_KVP = 'nz_creator_return'  -- same, while the interior creator is open
local RESCUE_RADIUS = 60.0      -- spawned this close to a saved interior entry: take them out
local RESCUE_WINDOW_MS = 60000  -- how long after the character loads (spawn selection, etc.)
local RESCUE_MAX_AGE = 30 * 24 * 3600
local ACCELERATE = 71
local UNARMED = joaat('WEAPON_UNARMED')
local MELEE_FLAG = 122          -- CPED_CONFIG_FLAG_DisableMelee
local ROLES = { owner = true, member = true, guest = true }
local ROLE_ORDER = { owner = 1, member = 2, guest = 3 }

local state = nil               -- the interior the player is in (see newState)
local entering = false
local transition = { frozen = nil, faded = false } -- undone when the resource stops mid-way
local panelKeybind = nil
local exitKeybind = nil

---------------------------------------------------------------------------------------
-- Generic helpers
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

local function sameHash(a, b)
  a, b = math.tointeger(tonumber(a)), math.tointeger(tonumber(b))
  if not a or not b then return false end
  return (a & 0xFFFFFFFF) == (b & 0xFFFFFFFF)
end

local function pedV4()
  local ped = PlayerPedId()
  local c = Utils.v3(GetEntityCoords(ped)) or { x = 0.0, y = 0.0, z = 0.0 }
  return { x = c.x, y = c.y, z = c.z, w = tonumber(GetEntityHeading(ped)) or 0.0 }
end

local function hasHeading(coords)
  if type(coords) == 'vector4' then return true end
  if type(coords) ~= 'table' then return false end
  return tonumber(coords.w or coords.h or coords.heading or coords[4]) ~= nil
end

local function fadeOut(ms)
  transition.faded = true
  if IsScreenFadedOut() then return end
  DoScreenFadeOut(ms or FADE_MS)
  local deadline = GetGameTimer() + (ms or FADE_MS) + 1500
  while not IsScreenFadedOut() and GetGameTimer() < deadline do Wait(10) end
end

local function fadeIn(ms)
  transition.faded = false
  if IsScreenFadedOut() or IsScreenFadingOut() then DoScreenFadeIn(ms or FADE_MS) end
end

local function incapacitated()
  return type(NZ.Points.incapacitated) == 'function' and NZ.Points.incapacitated() == true
end

--- Horizontal / vertical distance of `pos` outside the box around the interior's entry,
--- exit and vehicle slots (0 inside). Built once per visit.
local function outsideBounds(s, pos)
  local b = s.bounds
  if not b then
    b = { minX = math.huge, minY = math.huge, minZ = math.huge, maxX = -math.huge, maxY = -math.huge, maxZ = -math.huge }
    local function grow(p)
      if not p then return end
      b.minX, b.maxX = math.min(b.minX, p.x), math.max(b.maxX, p.x)
      b.minY, b.maxY = math.min(b.minY, p.y), math.max(b.maxY, p.y)
      b.minZ, b.maxZ = math.min(b.minZ, p.z), math.max(b.maxZ, p.z)
    end
    grow(s.entry)
    grow(Utils.v3(s.interior.exit))
    for i = 1, #s.slotList do grow(s.slotList[i]) end
    s.bounds = b
  end
  local dx = math.max(b.minX - pos.x, 0.0, pos.x - b.maxX)
  local dy = math.max(b.minY - pos.y, 0.0, pos.y - b.maxY)
  local below = b.minZ - pos.z
  local above = pos.z - b.maxZ
  return math.sqrt(dx * dx + dy * dy), math.max(below, above, 0.0), below > 0
end

---------------------------------------------------------------------------------------
-- "Inside" marker: a crash / logout inside saves the interior position as the character's
-- position; the next login takes the character back out (see rescue below).
---------------------------------------------------------------------------------------

local function saveMarker(key, entry, returnTo)
  entry, returnTo = Utils.v3(entry), Utils.v4(returnTo)
  if not entry or not returnTo then
    DeleteResourceKvp(key)
    return
  end
  local identifier = NZ.Bridge.getIdentifier()
  local ok, encoded = pcall(json.encode, {
    entry = { x = entry.x, y = entry.y, z = entry.z },
    returnTo = { x = returnTo.x, y = returnTo.y, z = returnTo.z, w = returnTo.w },
    identifier = type(identifier) == 'string' and identifier or nil,
    at = tonumber(GetCloudTimeAsInt()) or 0,
  })
  if ok and type(encoded) == 'string' then SetResourceKvp(key, encoded) end
end

local function rememberInside(s)
  saveMarker(RETURN_KVP, s.entry, s.returnTo)
end

local function forgetInside()
  DeleteResourceKvp(RETURN_KVP)
end

--- Interior creator: keep (entry = where the admin is working, returnTo = where the editor
--- was opened) or clear (nil) its marker, rescued on the next login like a garage visit.
---@param entry table|nil
---@param returnTo table|nil
function Interior.creatorMarker(entry, returnTo)
  if entry == nil then
    DeleteResourceKvp(CREATOR_KVP)
  else
    saveMarker(CREATOR_KVP, entry, returnTo)
  end
end

local function keyLabel(keybind, fallback)
  if keybind and type(keybind.getCurrentKey) == 'function' then
    local ok, key = pcall(keybind.getCurrentKey, keybind)
    if ok and type(key) == 'string' and key ~= '' then return key end
  end
  return fallback
end

local function cleanName(s, fallback)
  if type(s) ~= 'string' then return fallback end
  s = s:gsub('[%*_%[%]#<>`~|]', '')
  s = Utils.trim(s)
  if s == '' then return fallback end
  return s
end

local function deleteVehicle(entity)
  if not entity or entity == 0 or not DoesEntityExist(entity) then return end
  if NZ.Veh and type(NZ.Veh.delete) == 'function' then
    pcall(NZ.Veh.delete, entity)
  end
  if DoesEntityExist(entity) then
    SetEntityAsMissionEntity(entity, true, true)
    DeleteVehicle(entity)
    if DoesEntityExist(entity) then DeleteEntity(entity) end
  end
end

---------------------------------------------------------------------------------------
-- Weapons inside the garage
---------------------------------------------------------------------------------------

local function enforceUnarmed(ped)
  if not sameHash(GetSelectedPedWeapon(ped), UNARMED) then
    SetCurrentPedWeapon(ped, UNARMED, true)
  end
end

local function lockWeapons(ped)
  enforceUnarmed(ped)
  SetPedCanSwitchWeapon(ped, false)
  SetPedConfigFlag(ped, MELEE_FLAG, true)
  SetPlayerCanDoDriveBy(PlayerId(), false)
end

local function restoreWeapons(ped)
  SetPedCanSwitchWeapon(ped, true)
  SetPedConfigFlag(ped, MELEE_FLAG, false)
  SetPlayerCanDoDriveBy(PlayerId(), true)
end

---------------------------------------------------------------------------------------
-- Shared helpers: teleport, IPL profiles
---------------------------------------------------------------------------------------

--- Teleport the player and wait (max 5 s) for collision around them.
--- opts = { fade = true (fade out before, in after), keepVehicle = false (move the
---          vehicle the player drives along) }. Vec3 input keeps the current heading.
--- Blocking; call from a thread.
---@param coords table|vector3|vector4
---@param opts table|nil
---@return boolean
function Interior.teleport(coords, opts)
  opts = type(opts) == 'table' and opts or {}
  local c = Utils.v4(coords)
  if not c then return false end
  local withHeading = hasHeading(coords)
  local fade = opts.fade ~= false
  if fade then fadeOut(FADE_MS) end

  local ped = PlayerPedId()
  local vehicle = GetVehiclePedIsIn(ped, false)
  local target = ped
  RequestCollisionAtCoord(c.x + 0.0, c.y + 0.0, c.z + 0.0)
  if vehicle ~= 0 and opts.keepVehicle and GetPedInVehicleSeat(vehicle, -1) == ped then
    target = vehicle
    SetPedCoordsKeepVehicle(ped, c.x + 0.0, c.y + 0.0, c.z + 0.0)
  else
    if vehicle ~= 0 then ClearPedTasksImmediately(ped) end
    SetEntityCoords(ped, c.x + 0.0, c.y + 0.0, c.z + 0.0, false, false, false, false)
  end
  if withHeading then SetEntityHeading(target, c.w + 0.0) end

  transition.frozen = target
  FreezeEntityPosition(target, true)
  local deadline = GetGameTimer() + COLLISION_TIMEOUT
  while not HasCollisionLoadedAroundEntity(target) and GetGameTimer() < deadline do
    RequestCollisionAtCoord(c.x + 0.0, c.y + 0.0, c.z + 0.0)
    Wait(50)
  end
  FreezeEntityPosition(target, false)
  if transition.frozen == target then transition.frozen = nil end
  if target == vehicle then SetVehicleOnGroundProperly(vehicle) end

  if fade then fadeIn(FADE_MS) end
  return true
end

local function requestIpls(list)
  if type(list) ~= 'table' then return end
  for _, name in pairs(list) do
    if type(name) == 'string' and name ~= '' and not IsIplActive(name) then RequestIpl(name) end
  end
end

--- Collect entity sets: string | { name = 'set', color = n } | { 'set', n }.
--- target[name] = color (number) or false.
local function addSets(target, list)
  if type(list) ~= 'table' then return end
  for _, entry in pairs(list) do
    local name, color
    if type(entry) == 'string' then
      name = entry
    elseif type(entry) == 'table' then
      name = entry.name or entry.set or entry[1]
      color = tonumber(entry.color or entry[2])
    end
    if type(name) == 'string' and name ~= '' then
      target[name] = color or target[name] or false
    end
  end
end

--- Load the IPLs and entity sets of Config.IplProfiles[key] for the given option choices
--- ({ [optionKey] = choiceValue }, missing = the option default). Entity sets of the other
--- choices are switched off, then the interior (at profile.interiorCoords, else `coords`,
--- else profile.coords) is refreshed. IPLs stay loaded afterwards.
---@param key string|nil
---@param options table|nil
---@param coords table|nil
---@return boolean loaded, integer interiorId (0 when unknown)
function Interior.loadProfile(key, options, coords)
  if type(key) ~= 'string' or key == '' then return false, 0 end
  local profiles = Config.IplProfiles
  local profile = type(profiles) == 'table' and profiles[key] or nil
  if type(profile) ~= 'table' then return false, 0 end
  options = type(options) == 'table' and options or {}

  requestIpls(profile.ipls)
  local activate, deactivate = {}, {}
  addSets(activate, profile.entitySets)
  if type(profile.options) == 'table' then
    for _, opt in pairs(profile.options) do
      if type(opt) == 'table' and type(opt.choices) == 'table' then
        local chosen = opt.key ~= nil and options[opt.key] or nil
        if chosen == nil then chosen = opt.default end
        chosen = tostring(chosen)
        for _, choice in pairs(opt.choices) do
          if type(choice) == 'table' then
            if tostring(choice.value) == chosen then
              requestIpls(choice.ipls)
              addSets(activate, choice.entitySets)
            else
              addSets(deactivate, choice.entitySets)
            end
          end
        end
      end
    end
  end

  local at = Utils.v3(profile.interiorCoords) or Utils.v3(coords) or Utils.v3(profile.coords)
  local id = 0
  if at then id = math.tointeger(tonumber(GetInteriorAtCoords(at.x + 0.0, at.y + 0.0, at.z + 0.0))) or 0 end
  if id ~= 0 then
    for name in pairs(deactivate) do
      if activate[name] == nil and IsInteriorEntitySetActive(id, name) then
        DeactivateInteriorEntitySet(id, name)
      end
    end
    for name, color in pairs(activate) do
      if not IsInteriorEntitySetActive(id, name) then ActivateInteriorEntitySet(id, name) end
      if color then SetInteriorEntitySetColor(id, name, color) end
    end
    RefreshInterior(id)
  elseif next(activate) ~= nil then
    Utils.debug(('interior of profile "%s" not found, entity sets skipped'):format(key))
  end
  return true, id
end

--- IplProfile views (key, label, coords, slots, options) built from Config.IplProfiles,
--- sorted by label. Used when the admin data does not carry the profiles.
---@return table IplProfile[]
function Interior.profileViews()
  local out = {}
  local profiles = Config.IplProfiles
  if type(profiles) ~= 'table' then return out end
  for key, p in pairs(profiles) do
    if type(key) == 'string' and type(p) == 'table' then
      local options = {}
      if type(p.options) == 'table' then
        for _, o in ipairs(p.options) do
          if type(o) == 'table' and type(o.key) == 'string' then
            local choices = {}
            if type(o.choices) == 'table' then
              for _, c in ipairs(o.choices) do
                if type(c) == 'table' and c.value ~= nil then
                  choices[#choices + 1] = { value = tostring(c.value), label = tostring(c.label or c.value) }
                end
              end
            end
            local default = o.default ~= nil and tostring(o.default) or (choices[1] and choices[1].value) or ''
            options[#options + 1] = { key = o.key, label = tostring(o.label or o.key), default = default, choices = choices }
          end
        end
      end
      out[#out + 1] = {
        key = key,
        label = tostring(p.label or key),
        coords = Utils.v4(p.coords),
        slots = math.tointeger(tonumber(p.slots)) or 0,
        options = options,
      }
    end
  end
  table.sort(out, function(a, b) return a.label < b.label end)
  return out
end

---------------------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------------------

local function normalizeSlots(list)
  local out = {}
  if type(list) ~= 'table' then return out end
  for i = 1, #list do
    local v = Utils.v4(list[i])
    if v then out[#out + 1] = v end
  end
  return out
end

local function normalizeVehicles(list)
  local out = {}
  if type(list) ~= 'table' then return out end
  local iter = #list > 0 and ipairs or pairs
  for _, v in iter(list) do
    if type(v) == 'table' and Utils.plate(v.plate) then out[#out + 1] = v end
  end
  table.sort(out, function(a, b)
    return (tonumber(a.slot) or math.huge) < (tonumber(b.slot) or math.huge)
  end)
  return out
end

local function playerNameOf(serverId)
  local player = GetPlayerFromServerId(serverId)
  if player and player ~= -1 then
    local name = GetPlayerName(player)
    if type(name) == 'string' and name ~= '' then return name end
  end
  return ('#%d'):format(serverId)
end

--- Members arrive as a list ({ serverId, name, role }) or a map ([serverId] = role |
--- { name, role }); the panel needs { serverId, name, role, you }.
local function normalizeMembers(list, myRole)
  local me = GetPlayerServerId(PlayerId())
  local out, seen = {}, {}
  if type(list) == 'table' then
    for k, m in pairs(list) do
      local sid, name, role
      if type(m) == 'table' then
        sid = tonumber(m.serverId or m.source or m.id or k)
        name, role = m.name, m.role
      elseif type(m) == 'string' then
        sid, role = tonumber(k), m
      end
      sid = math.tointeger(sid)
      if sid and not seen[sid] then
        seen[sid] = true
        out[#out + 1] = {
          serverId = sid,
          name = type(name) == 'string' and name ~= '' and name or playerNameOf(sid),
          role = ROLES[role] and role or 'guest',
          you = sid == me,
        }
      end
    end
  end
  if not seen[me] then
    out[#out + 1] = { serverId = me, name = playerNameOf(me), role = myRole or 'guest', you = true }
  end
  table.sort(out, function(a, b)
    local ra, rb = ROLE_ORDER[a.role] or 9, ROLE_ORDER[b.role] or 9
    if ra ~= rb then return ra < rb end
    if a.you ~= b.you then return a.you end
    return a.name < b.name
  end)
  return out
end

local function newState(data, entry, returnTo)
  local interior = data.interior
  local role = ROLES[data.role] and data.role or 'guest'
  local slotList = normalizeSlots(interior.slots)
  if #slotList == 0 and type(data.slots) == 'table' then slotList = normalizeSlots(data.slots) end
  local slotCount = math.tointeger(tonumber(data.slots)) or #slotList
  return {
    instanceKey = data.instanceKey,
    interior = interior,
    entry = entry,
    garageName = type(data.garageName) == 'string' and data.garageName
      or (type(interior.name) == 'string' and interior.name) or L('Garage'),
    page = math.tointeger(tonumber(data.page)) or 1,
    pages = math.tointeger(tonumber(data.pages)) or 1,
    slotList = slotList,
    slotCount = slotCount,
    role = role,
    canInvite = type(data.canInvite) == 'boolean' and data.canInvite or nil,
    total = math.tointeger(tonumber(data.total)),
    tour = data.tour == true,
    tourSeconds = math.tointeger(tonumber(data.tourSeconds)),
    vehicles = normalizeVehicles(data.vehicles),
    members = normalizeMembers(data.members, role),
    returnTo = returnTo,
    entities = {},      -- [plate] = entity
    byEntity = {},      -- [entity] = { plate, slot, info, entity, hudDirty }
    inside = false,
    busy = false,
    leaving = false,
    closed = false,
    lockUntil = 0,
    needRelease = false,
    nearExit = false,
    drivePrompt = false,
    armedAt = 0,
    farRetryAt = 0,
  }
end

local function alive(s)
  return state == s and not s.closed
end

local function panelData(s)
  return {
    garageName = s.garageName,
    page = s.page,
    pages = s.pages,
    vehicles = #s.vehicles, -- vehicles on the current floor (s.total counts every floor)
    slots = s.slotCount,
    role = s.role,
    members = s.members,
    canInvite = s.role ~= 'guest' and s.canInvite ~= false,
  }
end

local function updatePanel(s)
  if NZ.NUI.isOpen('interior') then
    NZ.NUI.send('update', { app = 'interior', data = panelData(s) })
  end
end

---------------------------------------------------------------------------------------
-- Display vehicles
---------------------------------------------------------------------------------------

--- Map wanted plates to slots: the vehicle's own `slot` (1-based index into
--- interior.slots) when valid and free, else the first free slot.
local function assignSlots(s)
  local wanted, taken, pending = {}, {}, {}
  for i = 1, #s.vehicles do
    local v = s.vehicles[i]
    local plate = Utils.plate(v.plate)
    if plate and not wanted[plate] then
      local slot = math.tointeger(tonumber(v.slot))
      if slot and s.slotList[slot] and not taken[slot] then
        taken[slot] = true
        wanted[plate] = { info = v, slot = slot }
      else
        pending[#pending + 1] = { plate = plate, info = v }
      end
    end
  end
  local nextFree = 1
  for i = 1, #pending do
    while nextFree <= #s.slotList and taken[nextFree] do nextFree = nextFree + 1 end
    if nextFree > #s.slotList then break end
    taken[nextFree] = true
    wanted[pending[i].plate] = { info = pending[i].info, slot = nextFree }
  end
  return wanted
end

local function applyDisplayState(entity, info)
  FreezeEntityPosition(entity, true)
  SetEntityInvincible(entity, true)
  SetEntityCanBeDamaged(entity, false)
  SetVehicleEngineOn(entity, false, true, true)
  SetVehicleHasBeenOwnedByPlayer(entity, true)
  SetVehicleNeedsToBeHotwired(entity, false)
  if info.canDrive == true then
    SetVehicleDoorsLocked(entity, 1)
  else
    SetVehicleDoorsLocked(entity, 2)
  end
end

local function removeDisplay(s, plate)
  local entity = s.entities[plate]
  s.entities[plate] = nil
  if not entity then return end
  s.byEntity[entity] = nil
  local ped = PlayerPedId()
  if DoesEntityExist(entity) and GetVehiclePedIsIn(ped, false) == entity then
    ClearPedTasksImmediately(ped)
  end
  deleteVehicle(entity)
end

local function spawnDisplay(s, plate, want)
  local info = want.info
  local pos = s.slotList[want.slot]
  if not pos then return end
  local ok, entity = pcall(NZ.Veh.spawn, {
    hash = tonumber(info.hash),
    model = info.model,
    coords = pos,
    plate = info.plate,
    props = info.props,
    damage = info.damage,
    fuel = info.fuel,
    engine = info.engine,
    body = info.body,
    mileage = info.mileage,
    networked = false,
    warp = false,
    keys = false,
    freeze = true,
    locked = info.canDrive ~= true,
  })
  if not ok then
    lib.print.error(('[nayzeee-garages] display vehicle failed: %s'):format(entity))
    return
  end
  if not entity or entity == 0 or not DoesEntityExist(entity) then return end
  if not alive(s) or s.entities[plate] then
    deleteVehicle(entity)
    return
  end
  applyDisplayState(entity, info)
  s.entities[plate] = entity
  s.byEntity[entity] = { plate = plate, slot = want.slot, info = info, entity = entity, hudDirty = false }
end

--- Bring the display vehicles in line with s.vehicles. Re-runs while syncs arrive.
local function reconcile(s)
  if s.reconciling then
    s.dirty = true
    return
  end
  s.reconciling = true
  local ok, err = pcall(function()
    repeat
      s.dirty = false
      local wanted = assignSlots(s)

      for plate, entity in pairs(s.entities) do
        local want = wanted[plate]
        local rec = s.byEntity[entity]
        if not want or not rec or not DoesEntityExist(entity) or not sameHash(want.info.hash, rec.info.hash) then
          removeDisplay(s, plate)
        else
          if rec.slot ~= want.slot then
            local pos = s.slotList[want.slot]
            if GetVehiclePedIsIn(PlayerPedId(), false) == entity then ClearPedTasksImmediately(PlayerPedId()) end
            FreezeEntityPosition(entity, false)
            SetEntityCoords(entity, pos.x + 0.0, pos.y + 0.0, pos.z + 0.0, false, false, false, false)
            SetEntityHeading(entity, pos.w + 0.0)
            SetVehicleOnGroundProperly(entity)
            rec.slot = want.slot
          end
          rec.info = want.info
          rec.hudDirty = true
          applyDisplayState(entity, want.info)
        end
      end

      local order = {}
      for plate, want in pairs(wanted) do order[#order + 1] = { plate = plate, want = want } end
      table.sort(order, function(a, b) return a.want.slot < b.want.slot end)
      for i = 1, #order do
        if s.dirty or not alive(s) then break end
        if not s.entities[order[i].plate] then spawnDisplay(s, order[i].plate, order[i].want) end
      end
    until not s.dirty or not alive(s)
  end)
  s.reconciling = false
  if not ok then lib.print.error(('[nayzeee-garages] interior vehicles failed: %s'):format(err)) end
  if not alive(s) then
    for plate in pairs(s.entities) do removeDisplay(s, plate) end
  end
end

--- Build HudVehicle data for a display vehicle.
local function hudData(info)
  local hash = tonumber(info.hash)
  local label, make, image = nil, nil, nil
  if hash and NZ.Veh and NZ.Veh.label then
    local ok, l, m, _, img = pcall(NZ.Veh.label, hash, info.model)
    if ok then label, make, image = l, m, img end
  end
  local category = info.vehicleType
  if not Utils.vehicleTypes[category] then
    category = (hash and NZ.Veh.categoryOf and NZ.Veh.categoryOf(hash)) or 'car'
  end
  return {
    plate = Utils.plate(info.plate) or '',
    model = (type(info.model) == 'string' and info.model) or image or '',
    label = (type(info.label) == 'string' and info.label ~= '' and info.label) or label or L('Vehicle'),
    make = (type(info.make) == 'string' and info.make) or make or '',
    image = info.image or image,
    vehicleType = category,
    mileage = tonumber(info.mileage) or 0,
    fuel = Utils.round(Utils.clamp(tonumber(info.fuel) or 100, 0, 100), 0),
    engine = Utils.round(Utils.clamp(tonumber(info.engine) or 100, 0, 100), 0),
    body = Utils.round(Utils.clamp(tonumber(info.body) or 100, 0, 100), 0),
    ownerName = type(info.ownerName) == 'string' and info.ownerName or nil,
    canDrive = info.canDrive == true,
  }
end

---------------------------------------------------------------------------------------
-- Leaving / cleanup
---------------------------------------------------------------------------------------

local function setPrompt(s, field, label, key)
  if s[field] == (label ~= nil) then return end
  s[field] = label ~= nil
  if label then
    NZ.NUI.prompt(label, key)
  else
    NZ.NUI.prompt(nil)
  end
end

--- Remove everything local to the interior (no teleport). Ends the state.
local function clearLocal(s)
  if not s then return end
  s.closed = true
  if state == s then state = nil end
  local ped = PlayerPedId()
  local veh = GetVehiclePedIsIn(ped, false)
  if veh ~= 0 and s.byEntity[veh] then ClearPedTasksImmediately(ped) end
  for plate in pairs(s.entities) do removeDisplay(s, plate) end
  if s.exitPoint then
    s.exitPoint:remove()
    s.exitPoint = nil
  end
  if s.nearExit or s.drivePrompt then NZ.NUI.prompt(nil) end
  s.nearExit, s.drivePrompt = false, false
  NZ.NUI.hud(nil)
  if NZ.NUI.isOpen('interior') then NZ.NUI.close('interior') end
  if NZ.Camera.isPlaying() then NZ.Camera.stop() end
  FreezeEntityPosition(ped, false)
  restoreWeapons(ped)
end

--- Leave the garage interior: asks the server ('nz:interior:leave'), fades, removes the
--- display vehicles and teleports to `exitCoords` (else the server's / entry data's
--- returnTo). opts = { teleport = true }. Blocking; call from a thread.
---@param exitCoords table|nil
---@param opts table|nil
---@return boolean
function Interior.leave(exitCoords, opts)
  local s = state
  if not s or entering or s.leaving then return false end
  opts = type(opts) == 'table' and opts or {}
  s.leaving = true
  s.busy = true
  if NZ.NUI.isOpen('interior') then NZ.NUI.close('interior') end
  local res = await('nz:interior:leave', {})
  if not alive(s) then return false end
  if not res.ok then
    NZ.NUI.notify('error', res.error)
    s.leaving = false
    s.busy = false
    return false
  end
  local data = type(res.data) == 'table' and res.data or {}
  local target = Utils.v4(exitCoords) or Utils.v4(data.returnTo) or s.returnTo
  local teleport = opts.teleport ~= false and target ~= nil
  if teleport then fadeOut(FADE_MS) end
  clearLocal(s)
  if teleport then Interior.teleport(target, { fade = false }) end
  forgetInside()
  fadeIn(FADE_MS)
  return true
end

---------------------------------------------------------------------------------------
-- Drive out
---------------------------------------------------------------------------------------

local function spawnReal(data, info, hash, progress)
  local src = type(data.vehicle) == 'table' and data.vehicle or {}
  local opts = {}
  for k, v in pairs(src) do opts[k] = v end
  opts.hash = tonumber(opts.hash) or hash
  if opts.model == nil then opts.model = info.model end
  if opts.plate == nil then opts.plate = info.plate end
  opts.coords = Utils.v4(data.spawn) or Utils.v4(src.coords)
  opts.netId = tonumber(data.netId) or tonumber(src.netId)
  opts.warp = true
  opts.networked, opts.freeze, opts.locked = nil, nil, nil
  local plate = Utils.plate(opts.plate) or Utils.plate(info.plate)

  if not opts.coords then
    NZ.NUI.notify('error', L('The vehicle could not be spawned'))
    await('nz:garage:spawned', { plate = plate, failed = true })
    return false
  end

  -- Stream the area in first (a server-created vehicle must reach this client).
  Interior.teleport(opts.coords, { fade = false })
  progress.teleported = true
  local ok, vehicle = pcall(NZ.Veh.spawn, opts)
  if not ok then
    lib.print.error(('[nayzeee-garages] drive out spawn failed: %s'):format(vehicle))
    vehicle = nil
  end
  if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then
    local netId = NetworkGetEntityIsNetworked(vehicle) and NetworkGetNetworkIdFromEntity(vehicle) or nil
    local res = await('nz:garage:spawned', { plate = plate, netId = netId })
    if not res.ok then NZ.NUI.notify('error', res.error) end
    return true
  end
  NZ.NUI.notify('error', L('The vehicle could not be spawned'))
  await('nz:garage:spawned', { plate = plate, failed = true })
  return false
end

local function driveOut(s, rec)
  s.busy = true
  local info = rec.info
  local hash = tonumber(info.hash)
  if not hash and DoesEntityExist(rec.entity) then hash = GetEntityModel(rec.entity) end
  local res = await('nz:interior:driveOut', {
    plate = Utils.plate(info.plate),
    entityType = hash and NZ.Veh.entityTypeOf(hash) or 'automobile',
  })
  if not alive(s) then return end
  if not res.ok then
    NZ.NUI.notify('error', res.error)
    s.lockUntil = GetGameTimer() + DRIVE_LOCK_MS
    s.needRelease = true
    s.busy = false
    return
  end
  s.leaving = true
  fadeOut(FADE_MS)
  clearLocal(s)
  local progress = { teleported = false }
  local ok, err = pcall(spawnReal, type(res.data) == 'table' and res.data or {}, info, hash, progress)
  if not ok then lib.print.error(('[nayzeee-garages] drive out failed: %s'):format(err)) end
  -- The server already took the player out of the instance: never leave them in the
  -- (public) copy of the interior when the spawn could not move them.
  if not progress.teleported and s.returnTo then
    pcall(Interior.teleport, s.returnTo, { fade = false })
  end
  forgetInside()
  fadeIn(FADE_MS)
end

--- Per-frame while the player sits in the driver seat of a drivable display vehicle.
local function driverLoop(s, vehicle, rec)
  local ped = PlayerPedId()
  s.needRelease = IsDisabledControlPressed(0, ACCELERATE)
  setPrompt(s, 'drivePrompt', L('Drive out'), 'W')
  while alive(s) and s.inside and not s.busy and not rec.hudDirty and rec.info.canDrive == true
    and DoesEntityExist(vehicle) and GetVehiclePedIsIn(ped, false) == vehicle
    and GetPedInVehicleSeat(vehicle, -1) == ped do
    DisablePlayerFiring(PlayerId(), true)
    if IsDisabledControlPressed(0, ACCELERATE) then
      if not s.needRelease and GetGameTimer() >= s.lockUntil and not NZ.NUI.isOpen() and not incapacitated() then
        setPrompt(s, 'drivePrompt', nil)
        driveOut(s, rec)
        return
      end
    else
      s.needRelease = false
    end
    Wait(0)
  end
  if state == s then setPrompt(s, 'drivePrompt', nil) end
end

---------------------------------------------------------------------------------------
-- Loops, exit point, keybinds
---------------------------------------------------------------------------------------

local function startLoop(s)
  CreateThread(function()
    local hudFor = nil
    while alive(s) do
      local ped = PlayerPedId()
      local veh = GetVehiclePedIsIn(ped, false)
      local rec = veh ~= 0 and s.byEntity[veh] or nil
      if rec ~= hudFor or (rec and rec.hudDirty) then
        hudFor = rec
        if rec then rec.hudDirty = false end
        NZ.NUI.hud(rec and hudData(rec.info) or nil)
      end
      enforceUnarmed(ped)

      if s.inside and not s.busy and not s.leaving and GetGameTimer() >= s.farRetryAt then
        local pos = Utils.v3(GetEntityCoords(ped))
        local xy, z, below = 0.0, 0.0, false
        -- Still in the GTA interior of the entry (any room / floor of a large garage): inside.
        local here = s.gtaInterior ~= nil and s.gtaInterior ~= 0
          and (math.tointeger(tonumber(GetInteriorFromEntity(ped))) or 0) == s.gtaInterior
        if pos and not here then xy, z, below = outsideBounds(s, pos) end
        if xy > AWAY_MARGIN_XY or z > AWAY_MARGIN_Z then
          local now = GetGameTimer()
          s.awaySince = s.awaySince or now
          if now - s.awaySince >= AWAY_CONFIRM_MS then
            s.awaySince = nil
            s.farRetryAt = now + 10000
            if below and xy <= AWAY_MARGIN_XY then
              -- Fell through the floor (collision streamed in late): back to the entry.
              CreateThread(function()
                if alive(s) and not s.busy and not s.leaving then Interior.teleport(s.entry) end
              end)
            else
              -- Teleported away (admin bring / tp, respawn): leave the instance where they are.
              CreateThread(function() Interior.leave(nil, { teleport = false }) end)
            end
          end
        else
          s.awaySince = nil
        end
      end

      if rec and rec.info.canDrive == true and s.inside and not s.busy
        and GetPedInVehicleSeat(veh, -1) == ped then
        driverLoop(s, veh, rec)
      else
        Wait(LOOP_IDLE)
      end
    end
  end)
end

local function drawExitMarker(s)
  local c, z = s.exitCoords, s.exitGround
  DrawMarker(25, c.x + 0.0, c.y + 0.0, z + 0.03, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.6, 1.6, 1.0,
    8, 175, 162, 140, false, false, 2, false, nil, nil, false)
  DrawMarker(20, c.x + 0.0, c.y + 0.0, z + 1.0, 0.0, 0.0, 0.0, 180.0, 0.0, 0.0, 0.35, 0.35, 0.25,
    8, 175, 162, 200, true, false, 2, true, nil, nil, false)
end

local function createExitPoint(s)
  local c = Utils.v4(s.interior.exit) or s.entry
  s.exitCoords = c
  local found, gz = GetGroundZFor_3dCoord(c.x + 0.0, c.y + 0.0, c.z + 1.0, false)
  gz = tonumber(gz)
  s.exitGround = (found and gz and math.abs(gz - c.z) < 3.0) and gz or (c.z - 1.0)
  s.exitPoint = lib.points.new({
    coords = vector3(c.x + 0.0, c.y + 0.0, c.z + 0.0),
    distance = EXIT_DISTANCE,
    onExit = function()
      if state == s then setPrompt(s, 'nearExit', nil) end
    end,
    nearby = function(point)
      if not alive(s) then return end
      drawExitMarker(s)
      local near = s.inside and not s.busy and not s.leaving
        and GetGameTimer() >= s.armedAt
        and (tonumber(point.currentDistance) or 99.0) <= EXIT_RADIUS
        and GetVehiclePedIsIn(PlayerPedId(), false) == 0
        and not NZ.NUI.isOpen()
      if near then
        DisablePlayerFiring(PlayerId(), true)
        setPrompt(s, 'nearExit', L('Leave garage'), keyLabel(exitKeybind, Config.Keys.interact or 'E'))
      else
        setPrompt(s, 'nearExit', nil)
      end
    end,
  })
end

local function togglePanel()
  local s = state
  if not s or not alive(s) or not s.inside or s.busy or s.leaving then return end
  if NZ.NUI.isOpen('interior') then
    NZ.NUI.close('interior')
    return
  end
  if NZ.NUI.isOpen() or IsPauseMenuActive() then return end
  NZ.NUI.open('interior', panelData(s))
end

local function ensureKeybinds()
  if not panelKeybind then
    panelKeybind = lib.addKeybind({
      name = 'nz_interior_panel',
      description = L('Garage interior: control panel'),
      defaultKey = Config.Keys.interiorPanel or 'F6',
      onPressed = function() togglePanel() end,
    })
  end
  if not exitKeybind then
    exitKeybind = lib.addKeybind({
      name = 'nz_interior_exit',
      description = L('Garage interior: leave'),
      defaultKey = Config.Keys.interact or 'E',
      onPressed = function()
        local s = state
        if s and alive(s) and s.nearExit and s.inside and not s.busy and not s.leaving and not NZ.NUI.isOpen() then
          CreateThread(function() Interior.leave() end)
        end
      end,
    })
  end
end

---------------------------------------------------------------------------------------
-- Entering
---------------------------------------------------------------------------------------

local function applySync(s, payload)
  if type(payload.vehicles) == 'table' then s.vehicles = normalizeVehicles(payload.vehicles) end
  local page, pages = math.tointeger(tonumber(payload.page)), math.tointeger(tonumber(payload.pages))
  if page then s.page = page end
  if pages then s.pages = pages end
  if ROLES[payload.role] then s.role = payload.role end
  if type(payload.canInvite) == 'boolean' then s.canInvite = payload.canInvite end
  local total = math.tointeger(tonumber(payload.total))
  if total then s.total = total end
  if payload.members ~= nil then
    s.members = normalizeMembers(payload.members, s.role)
    for i = 1, #s.members do
      if s.members[i].you then s.role = s.members[i].role end
    end
  end
  if type(payload.vehicles) == 'table' then
    CreateThread(function() reconcile(s) end)
  end
  updatePanel(s)
end

local function playCutscene(s)
  local cut = type(s.interior.cutscene) == 'table' and s.interior.cutscene or nil
  if not cut or cut.enabled ~= true or type(cut.points) ~= 'table' or #cut.points == 0 then return end
  local ped = PlayerPedId()
  s.busy = true
  transition.frozen = ped
  FreezeEntityPosition(ped, true)
  NZ.Camera.playPath(cut.points, tonumber(cut.transition) or 3000, {
    returnTime = tonumber(cut.returnTime) or 1000,
    skippable = true,
    onStart = function() DoScreenFadeIn(FADE_MS) end,
  })
  FreezeEntityPosition(ped, false)
  if transition.frozen == ped then transition.frozen = nil end
  s.busy = false
end

local function doEnter(data, entry)
  NZ.NUI.close(nil)
  NZ.NUI.prompt(nil)
  NZ.NUI.hint(nil)
  NZ.Camera.stop()

  local previous = state
  local returnTo = Utils.v4(data.returnTo) or (previous and previous.returnTo) or pedV4()
  fadeOut(FADE_MS)
  if previous then clearLocal(previous) end

  local s = newState(data, entry, returnTo)
  state = s
  s.busy = true

  local interior = s.interior
  if interior.profile ~= nil then
    Interior.loadProfile(interior.profile, interior.options, entry)
  end
  Interior.teleport(entry, { fade = false })
  if not alive(s) then return false end
  rememberInside(s)
  -- GTA interior of the entry (0 = none, e.g. an outdoor spot): see startLoop's away check.
  local gtaInterior = math.tointeger(tonumber(GetInteriorFromEntity(PlayerPedId()))) or 0
  if gtaInterior == 0 then
    gtaInterior = math.tointeger(tonumber(GetInteriorAtCoords(entry.x + 0.0, entry.y + 0.0, entry.z + 0.0))) or 0
  end
  s.gtaInterior = gtaInterior

  lockWeapons(PlayerPedId())
  reconcile(s)
  if not alive(s) then return false end

  ensureKeybinds()
  s.inside = true
  s.armedAt = GetGameTimer() + EXIT_ARM_MS
  createExitPoint(s)
  startLoop(s)
  s.busy = false

  playCutscene(s)
  fadeIn(FADE_MS)
  if not alive(s) then return false end
  if s.tour and s.tourSeconds and s.tourSeconds > 0 then
    NZ.NUI.notify('info', L('Garage tour: you can look around for {seconds} seconds', { seconds = s.tourSeconds }))
  else
    NZ.NUI.notify('info', L('Press {key} to open the garage panel', {
      key = keyLabel(panelKeybind, Config.Keys.interiorPanel or 'F6'),
    }))
  end
  return true
end

--- Enter a garage interior with InteriorEnterData (§7.7): { instanceKey, interior,
--- garageName, page, pages, slots, vehicles, role, returnTo }. Closes every app, fades,
--- loads the profile, teleports to the entry, spawns local display vehicles, plays the
--- cutscene when enabled. Re-entering the instance the player is in only syncs it.
--- Blocking; call from a thread.
---@param data table
---@return boolean
function Interior.enter(data)
  if type(data) ~= 'table' or type(data.interior) ~= 'table' then
    NZ.NUI.notify('error', L('This garage interior is not available'))
    return false
  end
  local entry = Utils.v4(data.interior.entry)
  if not entry then
    NZ.NUI.notify('error', L('This garage interior has no entry point'))
    return false
  end
  if entering then return false end
  local s = state
  if s and alive(s) and s.inside and data.instanceKey ~= nil and s.instanceKey == data.instanceKey then
    applySync(s, data)
    return true
  end
  if incapacitated() then
    -- The server already moved the player to the instance's routing bucket: undo that.
    NZ.NUI.notify('error', L('You cannot do that right now'))
    if s and alive(s) then
      CreateThread(function() Interior.leave() end)
    else
      await('nz:interior:leave', {})
    end
    return false
  end

  entering = true
  local ok, res = pcall(doEnter, data, entry)
  entering = false
  if not ok then
    lib.print.error(('[nayzeee-garages] entering the interior failed: %s'):format(res))
    NZ.NUI.notify('error', L('Something went wrong'))
    if state then state.busy = false end
    fadeIn(FADE_MS)
    return false
  end
  return res == true
end

--- Whether the player is in (or entering) a garage interior.
---@return boolean
function Interior.isInside()
  return entering or state ~= nil
end

---------------------------------------------------------------------------------------
-- NUI callbacks
---------------------------------------------------------------------------------------

NZ.NUI.register('interior:leave', function()
  if NZ.NUI.isOpen('interior') then NZ.NUI.close('interior') end
  if not state then return nil end
  CreateThread(function() Interior.leave() end)
  return nil
end)

---------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------

RegisterNetEvent('nz:client:interior:enter', function(data)
  CreateThread(function() Interior.enter(data) end)
end)

RegisterNetEvent('nz:client:interior:sync', function(payload)
  local s = state
  if not s or not alive(s) or type(payload) ~= 'table' then return end
  applySync(s, payload)
end)

RegisterNetEvent('nz:client:interior:invite', function(payload)
  if type(payload) ~= 'table' or payload.inviteId == nil then return end
  CreateThread(function()
    local from = cleanName(payload.fromName, L('Someone'))
    local garage = cleanName(payload.garageName, L('their garage'))
    local dialog = {
      header = L('Garage invitation'),
      content = L('{name} invited you to {garage}.', { name = from, garage = garage }),
      centered = true,
      cancel = true,
      labels = { confirm = L('Accept'), cancel = L('Decline') },
    }
    -- Waits while another alert dialog is open (ox_lib shows one at a time); invitations
    -- are valid for 60 s on the server.
    local answer
    if type(NZ.Garage.alert) == 'function' then
      answer = NZ.Garage.alert(dialog, 55)
    else
      answer = lib.alertDialog(dialog)
    end
    if type(NZ.NUI.syncFocus) == 'function' then NZ.NUI.syncFocus() end
    -- Never answered: let it expire (the server tells the inviter); only "Decline" declines.
    if answer ~= 'confirm' and answer ~= 'cancel' then return end
    local accept = answer == 'confirm'
    if accept and incapacitated() then
      NZ.NUI.notify('error', L('You cannot do that right now'))
      return
    end
    local res = await('nz:interior:inviteRespond', { inviteId = payload.inviteId, accept = accept })
    if not res.ok then
      NZ.NUI.notify('error', res.error)
      return
    end
    -- The server normally follows up with 'nz:client:interior:enter'; enter directly when
    -- it answered with the InteriorEnterData instead.
    if accept and type(res.data) == 'table' and type(res.data.interior) == 'table' then
      Interior.enter(res.data)
    end
  end)
end)

RegisterNetEvent('nz:client:interior:kicked', function(payload)
  local s = state
  if not s or s.closed then return end
  CreateThread(function()
    s.busy = true
    s.leaving = true
    -- `stay`: the server saw the player far away from the interior (teleported): only
    -- forget the visit, do not move them back to the garage.
    local stay = type(payload) == 'table' and payload.stay == true
    local target = nil
    if not stay then target = (type(payload) == 'table' and Utils.v4(payload.returnTo)) or s.returnTo end
    if target then fadeOut(FADE_MS) end
    clearLocal(s)
    if target then Interior.teleport(target, { fade = false }) end
    forgetInside()
    fadeIn(FADE_MS)
    if not stay then NZ.NUI.notify('info', L('You were removed from the garage')) end
  end)
end)

AddEventHandler('nz:client:playerUnloaded', function()
  local s = state
  if not s then return end
  local target = (s.inside or entering) and s.returnTo or nil
  clearLocal(s)
  -- Best effort: put the character outside before the framework saves its position. The
  -- marker stays, so the next login still takes it out when the save came first.
  if target then
    local ped = PlayerPedId()
    if GetVehiclePedIsIn(ped, false) ~= 0 then ClearPedTasksImmediately(ped) end
    SetEntityCoords(ped, target.x + 0.0, target.y + 0.0, target.z + 0.0, false, false, false, false)
    SetEntityHeading(ped, (tonumber(target.w) or 0.0) + 0.0)
  end
end)

--- After a crash / logout inside a garage interior (or the creator) the framework spawns
--- the character at the saved position, which is inside the (now public, sealed) interior.
--- Take it back outside. `busy()` = a new visit / editor session owns the marker now.
local function rescue(key, busy)
  local raw = GetResourceKvpString(key)
  if type(raw) ~= 'string' or raw == '' then return end
  local decoded, saved = pcall(json.decode, raw)
  saved = decoded and type(saved) == 'table' and saved or nil
  local entry = saved and Utils.v3(saved.entry) or nil
  local target = saved and Utils.v4(saved.returnTo) or nil
  if not entry or not target then
    DeleteResourceKvp(key)
    return
  end
  local now = tonumber(GetCloudTimeAsInt()) or 0
  local at = tonumber(saved.at) or 0
  local tooOld = now > 0 and at > 0 and now - at > RESCUE_MAX_AGE
  -- The marker belongs to another character of this player: keep it for that one.
  local me = NZ.Bridge.getIdentifier()
  if not tooOld and type(saved.identifier) == 'string' and type(me) == 'string' and saved.identifier ~= me then
    return
  end
  if tooOld then
    DeleteResourceKvp(key)
    return
  end

  local deadline = GetGameTimer() + RESCUE_WINDOW_MS
  while GetGameTimer() < deadline and not busy() do
    local pos = Utils.v3(GetEntityCoords(PlayerPedId()))
    if pos then
      local dx, dy = pos.x - entry.x, pos.y - entry.y
      -- within the radius, and not well above it (fell through the map = any depth below)
      if math.sqrt(dx * dx + dy * dy) <= RESCUE_RADIUS and pos.z - entry.z <= 40.0 then
        Interior.teleport(target)
        NZ.NUI.notify('info', L('You were taken out of the garage interior'))
        break
      end
    end
    Wait(1000)
  end
  -- Busy again (a new visit / editor session wrote its own marker) or rescued / elsewhere.
  if not busy() then DeleteResourceKvp(key) end
end

AddEventHandler('nz:client:playerLoaded', function()
  CreateThread(function() rescue(RETURN_KVP, Interior.isInside) end)
  CreateThread(function()
    rescue(CREATOR_KVP, function()
      return type(NZ.Creator.isActive) == 'function' and NZ.Creator.isActive() == true
    end)
  end)
end)

exports('IsInsideInterior', function()
  return Interior.isInside()
end)

---------------------------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------------------------

AddEventHandler('onResourceStop', function(resource)
  if resource ~= NZ.ResourceName then return end
  -- Stopped in the middle of a fade / teleport (leave, drive out, kick): the thread that
  -- would undo them is gone.
  local frozen = transition.frozen
  transition.frozen = nil
  if frozen and DoesEntityExist(frozen) then FreezeEntityPosition(frozen, false) end
  if transition.faded then
    transition.faded = false
    DoScreenFadeIn(0)
  end
  local s = state
  if not s then return end
  state = nil
  s.closed = true
  local ped = PlayerPedId()
  if GetVehiclePedIsIn(ped, false) ~= 0 then ClearPedTasksImmediately(ped) end
  for _, entity in pairs(s.entities) do
    if DoesEntityExist(entity) then
      SetEntityAsMissionEntity(entity, true, true)
      DeleteVehicle(entity)
      if DoesEntityExist(entity) then DeleteEntity(entity) end
    end
  end
  if s.exitPoint then pcall(s.exitPoint.remove, s.exitPoint) end
  restoreWeapons(ped)
  FreezeEntityPosition(ped, false)
  local target = s.returnTo
  if target and s.inside then
    SetEntityCoords(ped, target.x + 0.0, target.y + 0.0, target.z + 0.0, false, false, false, false)
    SetEntityHeading(ped, target.w + 0.0)
    forgetInside()
  end
  DoScreenFadeIn(0)
end)
