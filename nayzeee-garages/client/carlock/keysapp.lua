--[[
  nayzeee-garages — car lock: the key ring NUI app 'keys' (client, NZ.CarLock).
  docs/CARLOCK.md §10.

  Opened by Config.CarLock.commands.keyRing (/keys), the keybind Config.CarLock.keys.keyRing,
  the client export OpenKeys(plate?) and the server ('nz:client:carlock:keyRing', e.g. a fob
  used far from its vehicle). The data comes from the core callback nz:carlock:keys (which
  keys) and nz:carlock:tracker (the vehicles behind them, server/carlock/tracker.lua); every
  action goes to the server, which answers with its own rules (ranges, owner, mode):

    keys:refresh {}                     -> KeysOpenData
    keys:lock    { plate }              -> { plate, locked }     nz:carlock:toggleLock { netId }
    keys:locate  { plate, stop? }       -> { distance }          tracker: waypoint + following blip
    keys:alarm   { plate }              -> { alarm, seconds, cooldown }   nz:carlock:trackerAlarm
    keys:players {}                     -> KeyRingPlayer[]       nz:carlock:nearbyPlayers
    keys:share   { plate, target }      -> null                  nz:carlock:share (virtual key / key item)
    keys:holders { plate }              -> KeyHolder[]           nz:carlock:holders (owner)
    keys:revoke  { plate, identifier }  -> KeyHolder[]           nz:carlock:revoke, then the new list

  While the window is open a 1 s loop pushes what this client sees itself ('update' -> live:
  distance and lock state of vehicles in scope) and the tracker's readout of the located
  vehicle ('update' -> tracking). Nothing runs while it is closed.
]]

local CarLock = NZ.CarLock
local Utils = NZ.Utils

local APP = 'keys'
local LIVE_STEP = 1000           -- ms between two live updates while the window is open
local REFRESH_DEBOUNCE = 1200    -- ms: a burst of key changes refreshes once

local ring = {
  open = false,
  opening = false,
  byPlate = {},                  -- [plate] = KeyEntry of the last data
  statuses = {},                 -- [plate] = last server status (kept when a refresh is rate limited)
  clock = nil,                   -- { server = os.time() of the server, game = GetGameTimer() }
  generation = 0,
  refreshQueued = false,
}

---------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------

local function serverNow()
  if not ring.clock then return nil end
  return ring.clock.server + math.floor((GetGameTimer() - ring.clock.game) / 1000)
end

local function localVehicle(netId)
  netId = tonumber(netId)
  if not netId or not NetworkDoesNetworkIdExist(netId) then return nil end
  local vehicle = NetToVeh(netId)
  if vehicle and vehicle ~= 0 and DoesEntityExist(vehicle) then return vehicle end
  return nil
end

local function lockedOf(vehicle)
  local bag = Entity(vehicle).state.nzLocked
  if bag ~= nil then return bag == true end
  return (tonumber(GetVehicleDoorLockStatus(vehicle)) or 0) >= 2
end

--- Plate of the vehicle the player sits in (real plate as this client knows it), or nil.
local function seatPlate()
  local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
  if vehicle == 0 then return nil, nil end
  return CarLock.plateOf(vehicle), vehicle
end

local function vehicleTypeOf(hash)
  if not hash or hash == 0 or type(NZ.Veh.categoryOf) ~= 'function' then return 'car' end
  local ok, cat = pcall(NZ.Veh.categoryOf, hash)
  return ok and (cat == 'sea' or cat == 'air') and cat or 'car'
end

local function enrich(data)
  if type(NZ.Veh.enrichDeep) ~= 'function' then return data end
  local ok, res = pcall(NZ.Veh.enrichDeep, data)
  return ok and res or data
end

local function ranges()
  return { key = CarLock.range('key'), fob = CarLock.range('fob'), give = CarLock.range('give') }
end

---------------------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------------------

--- One KeyEntry from the core key + the server status of its vehicle.
local function entryOf(key, st, mode)
  local plate = key.plate
  local kind = key.kind
  if kind == 'item' and key.keyKind == 'fob' then kind = 'fob' end
  local isOwner = st.isOwner == true
  local group
  if key.kind == 'temp' then
    group = 'temp'
  elseif isOwner then
    group = 'owned'
  elseif key.kind == 'item' then
    group = 'items'
  else
    group = 'shared'   -- a garage share, a fleet vehicle or a virtual key someone gave you
  end
  local hash = tonumber(st.hash)
  local netId = tonumber(st.netId) or tonumber(key.netId)
  local entry = {
    plate = plate,
    model = type(st.model) == 'string' and st.model or (type(key.model) == 'string' and key.model or ''),
    hash = hash or 0,
    vehicleType = vehicleTypeOf(hash),
    nickname = st.nickname or (key.kind == 'owner' and type(key.label) == 'string' and key.label ~= '' and key.label or nil),
    kind = kind,
    group = group,
    keyType = st.keyType == 'fob' and 'fob' or 'key',
    profile = st.profile or 'standard',
    profileLabel = st.profileLabel or L('Standard'),
    remote = st.remote == true,
    expiresIn = nil,
    reason = key.kind == 'temp' and type(key.reason) == 'string' and key.reason or nil,
    isOwner = isOwner,
    spawned = st.spawned == true or netId ~= nil,
    netId = netId,
    locked = st.locked,
    distance = st.distance,
    tracker = st.tracker == true,
    trackable = st.trackable == true,
    towing = st.towing == true,
    alarm = st.alarm == true,
    canShare = (mode == 'virtual' and isOwner and key.kind ~= 'temp') or (mode == 'physical' and key.kind == 'item'),
    holders = nil,
  }
  local now = serverNow()
  if key.kind == 'temp' and tonumber(key.expires) and now then
    entry.expiresIn = math.max(math.floor(tonumber(key.expires) - now), 0)
  end
  -- a vehicle that is not out: the server may not know its class (no shared vehicle list, no
  -- driver reported it yet); this client knows every model's class, so the profile shown
  -- (tracker, fob) is its own. Vehicles that are out keep the server's view (what it enforces).
  if not entry.spawned and entry.hash ~= 0 then
    local okClass, class = pcall(GetVehicleClassFromName, entry.hash)
    if okClass and type(class) == 'number' then
      local name, profile = CarLock.profileOf(entry.hash, class)
      entry.profile = name
      entry.profileLabel = L(type(profile.label) == 'string' and profile.label or 'Standard')
      entry.remote = profile.remote == true
      entry.keyType = CarLock.keyKindOf(profile)
      entry.tracker = profile.tracker == true
    end
  end
  -- what this client sees itself is the freshest
  local vehicle = netId and localVehicle(netId) or nil
  if vehicle then
    entry.spawned = true
    entry.locked = lockedOf(vehicle)
    entry.distance = math.floor(#(GetEntityCoords(vehicle) - GetEntityCoords(PlayerPedId())) + 0.5)
    if entry.hash == 0 then
      entry.hash = GetEntityModel(vehicle)
      entry.vehicleType = vehicleTypeOf(entry.hash)
    end
  end
  return entry
end

--- KeysOpenData from the server (yields). Returns a result table.
local function build(focus)
  local keysRes = NZ.NUI.await('nz:carlock:keys', {})
  if not keysRes.ok then return keysRes end
  local data = type(keysRes.data) == 'table' and keysRes.data or {}
  local mode = data.mode == 'physical' and 'physical' or 'virtual'
  local statusRes = CarLock.trackerStatus(nil)
  local trackerOn = CarLock.cfg().tracker == nil or (type(CarLock.cfg().tracker) == 'table' and CarLock.cfg().tracker.enabled ~= false)
  if statusRes.ok and type(statusRes.data) == 'table' then
    trackerOn = statusRes.data.tracker == true
    if tonumber(statusRes.data.now) then ring.clock = { server = tonumber(statusRes.data.now), game = GetGameTimer() } end
    for _, st in ipairs(type(statusRes.data.vehicles) == 'table' and statusRes.data.vehicles or {}) do
      local plate = Utils.plate(st.plate)
      if plate then ring.statuses[plate] = st end
    end
  end

  local list, byPlate = {}, {}
  for _, key in ipairs(type(data.keys) == 'table' and data.keys or {}) do
    local plate = Utils.plate(key.plate)
    if plate and not byPlate[plate] then
      key.plate = plate
      local entry = entryOf(key, ring.statuses[plate] or {}, mode)
      list[#list + 1] = entry
      byPlate[plate] = entry
    end
  end
  enrich(list)
  ring.byPlate = byPlate
  local seat = seatPlate()
  return Utils.ok({
    mode = mode,
    keys = list,
    nearbyPlayers = {},
    ranges = ranges(),
    tracker = trackerOn,
    focus = Utils.plate(focus),
    seatPlate = seat,
    tracking = nil,
    live = nil,
  })
end

---------------------------------------------------------------------------------------
-- Live updates while open
---------------------------------------------------------------------------------------

local function liveLoop(generation)
  CreateThread(function()
    while ring.open and ring.generation == generation do
      Wait(LIVE_STEP)
      if not ring.open or ring.generation ~= generation then return end
      if NZ.Points.incapacitated() then
        NZ.NUI.close(APP)
        return
      end
      local live, any = {}, false
      local ped = GetEntityCoords(PlayerPedId())
      for plate, entry in pairs(ring.byPlate) do
        local vehicle = entry.netId and localVehicle(entry.netId) or nil
        if vehicle then
          live[plate] = { distance = math.floor(#(GetEntityCoords(vehicle) - ped) + 0.5), locked = lockedOf(vehicle),
            alarm = type(Entity(vehicle).state.nzAlarm) == 'table' }
          any = true
        end
      end
      local seat = seatPlate()
      NZ.NUI.send('update', { app = APP, data = { live = any and live or {}, seatPlate = seat or false } })
    end
  end)
end

local function refreshNow()
  if not ring.open then return end
  local res = build(nil)
  if res.ok and ring.open then
    res.data.focus = nil
    NZ.NUI.send('update', { app = APP, data = enrich(res.data) })
  end
end

local function queueRefresh()
  if not ring.open or ring.refreshQueued then return end
  ring.refreshQueued = true
  SetTimeout(REFRESH_DEBOUNCE, function()
    ring.refreshQueued = false
    refreshNow()
  end)
end

-- keys handed over, revoked, received, a change of locks...
AddEventHandler('nz:client:carlock:keysChanged', function()
  queueRefresh()
end)

-- the tracker follows a located vehicle: forward its readout
AddEventHandler('nz:client:carlock:tracking', function(data)
  if not ring.open or type(data) ~= 'table' then return end
  NZ.NUI.send('update', { app = APP, data = { tracking = {
    plate = data.plate,
    distance = tonumber(data.distance),
    live = data.live == true,
    lost = data.lost == true,
    stopped = data.stopped == true,
    towing = data.towing == true,
  } } })
end)

---------------------------------------------------------------------------------------
-- Open / close
---------------------------------------------------------------------------------------

--- Open the key ring (yields), on `focus` (plate) when given. Pressing the key again closes it.
---@param focus string|nil
---@return boolean opened
function CarLock.openKeyRing(focus)
  if not CarLock.enabled() or ring.opening then return false end
  if NZ.NUI.isOpen(APP) then
    if focus then NZ.NUI.send('update', { app = APP, data = { focus = Utils.plate(focus) } }) end
    return true
  end
  -- another window (garage, admin...) is in front: never stack the key ring on it
  if NZ.NUI.isOpen() or IsPauseMenuActive() or NZ.Points.incapacitated() then return false end
  ring.opening = true
  local res = build(focus)
  ring.opening = false
  if not res.ok then
    NZ.NUI.notify('error', res.error)
    return false
  end
  if NZ.NUI.isOpen() then return false end
  ring.open = true
  ring.generation = ring.generation + 1
  NZ.NUI.open(APP, enrich(res.data))
  liveLoop(ring.generation)
  return true
end

NZ.NUI.onClose(APP, function()
  ring.open = false
  ring.generation = ring.generation + 1
end)

local function openAsync(focus)
  CreateThread(function() CarLock.openKeyRing(focus) end)
end

RegisterNetEvent('nz:client:carlock:keyRing', function(data)
  openAsync(type(data) == 'table' and data.plate or nil)
end)

if CarLock.enabled() then
  local cfg = CarLock.cfg()
  local keys = type(cfg.keys) == 'table' and cfg.keys or {}
  local commands = type(cfg.commands) == 'table' and cfg.commands or {}
  if type(commands.keyRing) == 'string' and commands.keyRing ~= '' then
    RegisterCommand(commands.keyRing, function() openAsync(nil) end, false)
  end
  if type(keys.keyRing) == 'string' and keys.keyRing ~= '' then
    lib.addKeybind({
      name = 'nz_carlock_keyring',
      description = L('Open the key ring'),
      defaultKey = keys.keyRing,
      onPressed = function()
        if IsNuiFocused() then return end
        openAsync(nil)
      end,
    })
  end
end

exports('OpenKeys', function(plate)
  openAsync(type(plate) == 'string' and plate or nil)
  return true
end)

---------------------------------------------------------------------------------------
-- NUI callbacks
---------------------------------------------------------------------------------------

local function entryFor(data)
  local plate = Utils.plate(type(data) == 'table' and data.plate or nil)
  if not plate or #plate > 16 then return nil, nil end
  return ring.byPlate[plate], plate
end

NZ.NUI.register('keys:refresh', function()
  local res = build(nil)
  if res.ok then res.data = enrich(res.data) end
  return res
end)

NZ.NUI.register('keys:lock', function(data)
  local entry, plate = entryFor(data)
  if not plate then return Utils.fail(L('Invalid plate')) end
  if not entry then return Utils.fail(L('You do not have the keys of this vehicle')) end
  if entry.towing then return Utils.fail(L('This vehicle is being towed')) end
  if not entry.netId then return Utils.fail(L('The vehicle is not out')) end
  -- the server locks the vehicle you sit in: never surprise the player with another one
  local seat, seatVehicle = seatPlate()
  if seatVehicle and seat ~= plate then
    return Utils.fail(L('Get out of your vehicle to lock another one'))
  end
  local res = NZ.NUI.await('nz:carlock:toggleLock', { netId = entry.netId })
  if not res.ok then return res end
  local out = type(res.data) == 'table' and res.data or {}
  local donePlate = Utils.plate(out.plate) or plate
  local done = ring.byPlate[donePlate]
  if done then done.locked = out.locked == true end
  CarLock.playFob()
  return Utils.ok({ plate = donePlate, locked = out.locked == true })
end)

NZ.NUI.register('keys:locate', function(data)
  local entry, plate = entryFor(data)
  if not plate then return Utils.fail(L('Invalid plate')) end
  if data.stop == true then
    if CarLock.locating() == plate then CarLock.stopLocate() end
    return Utils.ok({ distance = nil })
  end
  if not entry then return Utils.fail(L('You do not have the keys of this vehicle')) end
  local res = CarLock.locate(plate)
  if not res.ok then return res end
  return Utils.ok({ distance = res.data and res.data.distance or nil })
end)

NZ.NUI.register('keys:alarm', function(data)
  local entry, plate = entryFor(data)
  if not plate then return Utils.fail(L('Invalid plate')) end
  if not entry then return Utils.fail(L('You do not have the keys of this vehicle')) end
  local on = nil
  if data.on == true or data.on == false then on = data.on end
  local res = CarLock.remoteAlarm(plate, on)
  if not res.ok then return res end
  local out = type(res.data) == 'table' and res.data or {}
  entry.alarm = out.alarm == true
  return Utils.ok({ alarm = out.alarm == true, seconds = tonumber(out.seconds), cooldown = tonumber(out.cooldown) or 0 })
end)

NZ.NUI.register('keys:players', function()
  local res = NZ.NUI.await('nz:carlock:nearbyPlayers', {})
  if not res.ok then return res end
  return Utils.ok(type(res.data) == 'table' and res.data or {})
end)

NZ.NUI.register('keys:share', function(data)
  local entry, plate = entryFor(data)
  local target = tonumber(data.target)
  if not plate or not target or target ~= math.floor(target) or target <= 0 then return Utils.fail(L('Invalid request')) end
  if not entry then return Utils.fail(L('You do not have the keys of this vehicle')) end
  if not entry.canShare then
    return Utils.fail(entry.kind == 'temp' and L('You cannot lend a temporary key') or L('Only the owner can share this key'))
  end
  local res = NZ.NUI.await('nz:carlock:share', { plate = plate, target = math.tointeger(target) })
  if not res.ok then return res end
  return Utils.ok(nil)
end)

--- KeyHolder list for the NUI (server times turned into seconds left / ago on this clock).
local function holdersOf(raw)
  local now = serverNow()
  local list = {}
  for _, h in ipairs(type(raw) == 'table' and raw or {}) do
    if type(h) == 'table' and type(h.identifier) == 'string' then
      local expires, at = tonumber(h.expires), tonumber(h.at)
      list[#list + 1] = {
        identifier = h.identifier,
        name = type(h.name) == 'string' and h.name or L('Unknown'),
        kind = h.kind == 'temp' and 'temp' or 'virtual',
        grantedBy = type(h.grantedBy) == 'string' and h.grantedBy or nil,
        agoSeconds = (at and now) and math.max(now - at, 0) or nil,
        expiresIn = (expires and now) and math.max(expires - now, 0) or nil,
      }
    end
  end
  return list
end

NZ.NUI.register('keys:holders', function(data)
  local _, plate = entryFor(data)
  if not plate then return Utils.fail(L('Invalid plate')) end
  local res = NZ.NUI.await('nz:carlock:holders', { plate = plate })
  if not res.ok then return res end
  local list = holdersOf(res.data)
  local entry = ring.byPlate[plate]
  if entry then entry.holders = #list end
  return Utils.ok(list)
end)

NZ.NUI.register('keys:revoke', function(data)
  local _, plate = entryFor(data)
  local identifier = type(data.identifier) == 'string' and #data.identifier <= 64 and data.identifier or nil
  if not plate or not identifier then return Utils.fail(L('Invalid request')) end
  local res = NZ.NUI.await('nz:carlock:revoke', { plate = plate, identifier = identifier })
  if not res.ok then return res end
  local list = NZ.NUI.await('nz:carlock:holders', { plate = plate })
  if not list.ok then return Utils.ok(nil) end
  return Utils.ok(holdersOf(list.data))
end)
