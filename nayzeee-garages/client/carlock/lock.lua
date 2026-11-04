--[[
  nayzeee-garages — car lock: locking, fob remote, key cache and client exports (client,
  NZ.CarLock). docs/CARLOCK.md §3, §7.

  - Key cache: what the server said about our keys, per real plate (positive answers kept
    60 s, negative 10 s); 'nz:client:carlock:keys' (server push) clears it and fires the
    local event 'nz:client:carlock:keysChanged' (plate|nil). The server decides everything:
    the cache only drives hints, the ignition and other scripts' synchronous HasKeys calls.
  - Lock: keybind Config.CarLock.keys.lock + command Config.CarLock.commands.lock. The vehicle
    you sit in, else the nearest vehicle you have a key for (key range, fob range for remote
    profiles), chosen by the server from the nearest candidates ('nz:carlock:toggleLock').
    Then the fob animation (+ prop) on foot and a notification.
  - Every client applies the replicated state bags of a vehicle: 'nzLocked' (door lock) and
    'nzAlarm' (native or custom alarm); the lock feedback (sound, horn chirp, flashing lights)
    is the server event 'nz:client:carlock:fx' sent to the players near the vehicle.
  - Client exports: HasKey(plate|vehicle), ToggleLock(vehicle?), ToggleEngine(), GiveKey(vehicle).
]]

local CarLock = NZ.CarLock
local Utils = NZ.Utils

local POSITIVE_TTL = 60000    -- ms: cached "you have a key"
local NEGATIVE_TTL = 10000    -- ms: cached "no key"
local NET_PLATE_TTL = 60000   -- ms: server's real plate of a network id
local LIST_TTL = 30000        -- ms: key list (other scripts' "all my keys" exports)
local EXPECT_MS = 15000       -- ms: a garage key is on its way (server hand-out after the spawn report)
local FX_RANGE = 60.0         -- m: hear / see the lock feedback
local ALARM_RANGE = 150.0     -- m: hear a custom alarm
local MAX_CANDIDATES = 8
local FALLBACK_PROP = 'prop_cuff_keys_01'
local HORN = joaat('HELDDOWN')

local keyCache = {}           -- [plate] = { has, kind, at }
local netPlates = {}          -- [netId] = { plate, at }
local inflight = {}           -- [plate] = true while an async check runs
local expected = {}           -- [plate] = deadline (GetGameTimer)
local keyList = { plates = {}, at = -1e9, loading = false }
local alarms = {}             -- [entity] = alarm id
local busy = false

local function now() return GetGameTimer() end

local function isVehicle(vehicle)
  return type(vehicle) == 'number' and vehicle ~= 0 and DoesEntityExist(vehicle) and IsEntityAVehicle(vehicle)
end

local function netIdOf(vehicle)
  if not isVehicle(vehicle) or not NetworkGetEntityIsNetworked(vehicle) then return nil end
  local id = NetworkGetNetworkIdFromEntity(vehicle)
  if not id or id == 0 then return nil end
  return id
end

local function notify(kind, message)
  if type(message) ~= 'string' or message == '' then return end
  NZ.NUI.notify(kind, message)
end

local function canAct()
  if IsPauseMenuActive() or IsNuiFocused() then return false end
  local ped = PlayerPedId()
  return not IsEntityDead(ped)
end

---------------------------------------------------------------------------------------
-- Key cache
---------------------------------------------------------------------------------------

--- Real plate of a vehicle as far as this client knows: the server's answer for its network
--- id, else the 'nzPlate' state bag (garage vehicles, fake plates), else the plate text.
---@param vehicle number
---@return string|nil
function CarLock.plateOf(vehicle)
  if not isVehicle(vehicle) then return nil end
  local netId = netIdOf(vehicle)
  if netId then
    local known = netPlates[netId]
    if known and now() - known.at < NET_PLATE_TTL then return known.plate end
    local bag = Entity(vehicle).state.nzPlate
    local p = type(bag) == 'string' and Utils.plate(bag) or nil
    if p then return p end
  end
  return Utils.plate(GetVehicleNumberPlateText(vehicle))
end

local function store(plate, has, kind)
  keyCache[plate] = { has = has == true, kind = kind, at = now() }
  if has then expected[plate] = nil end
end

--- Cached answer for a plate: true / false, or nil when unknown (or too old). A garage key
--- on its way (CarLock.expectKey) counts as true for a few seconds.
---@param plate string|nil
---@return boolean|nil
function CarLock.cachedKey(plate)
  plate = Utils.plate(plate)
  if not plate then return nil end
  local entry = keyCache[plate]
  if entry and now() - entry.at < (entry.has and POSITIVE_TTL or NEGATIVE_TTL) then
    if entry.has then return true end
    local exp = expected[plate]
    if exp and now() < exp then return true end
    return false
  end
  local exp = expected[plate]
  if exp and now() < exp then return true end
  return nil
end

--- The garage just spawned this vehicle for us: its key arrives from the server in a moment.
---@param vehicle number|nil
---@param plate string|nil
function CarLock.expectKey(vehicle, plate)
  plate = Utils.plate(plate) or (isVehicle(vehicle) and CarLock.plateOf(vehicle)) or nil
  if not plate then return end
  expected[plate] = now() + EXPECT_MS
  if keyCache[plate] and not keyCache[plate].has then keyCache[plate] = nil end
end

--- Ask the server (yields): vehicle entity or plate. Returns the server data or nil.
--- Vehicle answers: { plate, has, kind, ignition, locked }; plate answers: { plate, has, kind }.
---@param target number|string
---@return table|nil
function CarLock.queryKey(target)
  local payload
  if isVehicle(target) then
    local netId = netIdOf(target)
    if not netId then return nil end
    payload = { netId = netId, class = GetVehicleClass(target) }
  else
    local plate = Utils.plate(target)
    if not plate then return nil end
    payload = { plate = plate }
  end
  local ok, res = pcall(lib.callback.await, 'nz:carlock:hasKey', false, payload)
  if not ok or type(res) ~= 'table' or res.ok ~= true or type(res.data) ~= 'table' then return nil end
  local data = res.data
  local plate = Utils.plate(data.plate)
  if plate then
    store(plate, data.has, data.kind)
    if payload.netId then netPlates[payload.netId] = { plate = plate, at = now() } end
  end
  return data
end

local function plateOfTarget(target)
  if isVehicle(target) then return CarLock.plateOf(target) end
  return Utils.plate(target)
end

--- Synchronous best effort: the cached answer; unknown plates are checked in the background
--- (false until the answer arrives).
---@param target number|string vehicle or plate
---@return boolean
function CarLock.hasKeyFast(target)
  local plate = plateOfTarget(target)
  if not plate then return false end
  local value = CarLock.cachedKey(plate)
  if value == nil and not inflight[plate] then
    inflight[plate] = true
    CreateThread(function()
      local data = CarLock.queryKey(isVehicle(target) and target or plate)
      -- no answer (rate limited, server busy): wait before this plate is asked again, so a
      -- script polling every frame does not send a request per frame
      if data == nil then Wait(1000) end
      inflight[plate] = nil
    end)
  end
  return value == true
end

--- Does the local player have a key? The cache, else the server (when the caller may wait).
---@param target number|string vehicle or plate
---@return boolean
function CarLock.hasKey(target)
  local plate = plateOfTarget(target)
  if not plate then return false end
  local value = CarLock.cachedKey(plate)
  if value ~= nil then return value end
  if not coroutine.isyieldable() then return CarLock.hasKeyFast(target) end
  local data = CarLock.queryKey(isVehicle(target) and target or plate)
  return type(data) == 'table' and data.has == true
end

--- Plates of the local player's keys (last server list; refreshed in the background).
---@return string[]
function CarLock.keyPlates()
  if now() - keyList.at > LIST_TTL and not keyList.loading then
    keyList.loading = true
    CreateThread(function()
      local ok, res = pcall(lib.callback.await, 'nz:carlock:keys', false, {})
      if ok and type(res) == 'table' and res.ok and type(res.data) == 'table' then
        local plates = {}
        for _, key in ipairs(type(res.data.keys) == 'table' and res.data.keys or {}) do
          local p = Utils.plate(key.plate)
          if p then
            plates[#plates + 1] = p
            store(p, true, key.kind)
          end
        end
        keyList.plates = plates
        keyList.at = now()
      end
      keyList.loading = false
    end)
  end
  return keyList.plates
end

local function flush(plate)
  if plate then
    keyCache[plate] = nil
  else
    keyCache = {}
    netPlates = {}
  end
  keyList.at = -1e9
  TriggerEvent('nz:client:carlock:keysChanged', plate)
end

RegisterNetEvent('nz:client:carlock:keys', function(data)
  flush(type(data) == 'table' and Utils.plate(data.plate) or nil)
end)

AddEventHandler('nz:client:playerLoaded', function() flush(nil) end)
AddEventHandler('nz:client:playerUnloaded', function()
  expected = {}
  flush(nil)
end)

---------------------------------------------------------------------------------------
-- Fob animation
---------------------------------------------------------------------------------------

local function createProp(ped, model)
  if type(model) ~= 'string' or model == '' then return nil end
  local hash = joaat(model)
  if not IsModelValid(hash) then hash = joaat(FALLBACK_PROP) end
  if not IsModelValid(hash) then return nil end
  if not pcall(lib.requestModel, hash, 1500) then return nil end
  local prop = CreateObject(hash, 0.0, 0.0, 0.0, false, false, false)
  SetModelAsNoLongerNeeded(hash)
  if not prop or prop == 0 then return nil end
  SetEntityCollision(prop, false, false)
  AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, 57005), 0.11, 0.03, -0.03, 20.0, 175.0, 170.0,
    true, true, false, true, 1, true)
  return prop
end

--- Click the fob (third person animation + key prop) when on foot.
function CarLock.playFob()
  local anim = CarLock.cfg().animation
  if type(anim) ~= 'table' or anim.enabled == false then return end
  local ped = PlayerPedId()
  if IsPedInAnyVehicle(ped, false) or IsEntityDead(ped) or IsPedRagdoll(ped) then return end
  CreateThread(function()
    local dict = type(anim.dict) == 'string' and anim.dict or 'anim@mp_player_intmenu@key_fob@'
    local clip = type(anim.name) == 'string' and anim.name or 'fob_click'
    local duration = Utils.clamp(tonumber(anim.duration) or 900, 200, 3000)
    local hasDict = pcall(lib.requestAnimDict, dict, 1500)
    local prop = createProp(ped, anim.prop)
    if hasDict then TaskPlayAnim(ped, dict, clip, 8.0, -8.0, duration, 48, 0, false, false, false) end
    Wait(duration)
    if prop and DoesEntityExist(prop) then DeleteEntity(prop) end
    if hasDict then
      StopAnimTask(ped, dict, clip, 1.0)
      RemoveAnimDict(dict)
    end
  end)
end

--- Feedback for the player who locked / unlocked (the sound and lights come from 'nz:client:carlock:fx').
local function feedback(data)
  if type(data) ~= 'table' then return end
  local plate = Utils.plate(data.plate)
  if plate then store(plate, true, data.kind) end
  CarLock.playFob()
  if CarLock.cfg().lockNotify ~= false then
    if data.locked then
      notify('info', L('Vehicle locked'))
    else
      notify('success', L('Vehicle unlocked'))
    end
  end
end

-- A key / fob item was used (server: NZ.CarLock.useKeyItem).
RegisterNetEvent('nz:client:carlock:used', function(data)
  feedback(data)
end)

---------------------------------------------------------------------------------------
-- Lock toggle
---------------------------------------------------------------------------------------

--- Network ids of the vehicles a lock request may target: the one we sit in, else the
--- nearest networked vehicles within the fob range (known keys first, known "no key" last).
local function candidates()
  local ped = PlayerPedId()
  local current = GetVehiclePedIsIn(ped, false)
  if current ~= 0 then
    local id = netIdOf(current)
    return id and { id } or {}
  end
  local coords = GetEntityCoords(ped)
  local found = {}
  for _, entry in ipairs(lib.getNearbyVehicles(coords, CarLock.range('fob') + 2.0, false) or {}) do
    local vehicle = entry.vehicle
    local id = netIdOf(vehicle)
    if id then
      local known = CarLock.cachedKey(CarLock.plateOf(vehicle))
      found[#found + 1] = { id = id, dist = #(entry.coords - coords), rank = known == true and 0 or (known == nil and 1 or 2) }
    end
  end
  table.sort(found, function(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    return a.dist < b.dist
  end)
  local out = {}
  for i = 1, math.min(#found, MAX_CANDIDATES) do out[i] = found[i].id end
  return out
end

--- Lock / unlock: `vehicle` or (nil) the vehicle we sit in / the nearest we have a key for.
--- Yields (server round trip). Returns ok, locked.
---@param vehicle number|nil
---@return boolean ok, boolean|nil locked
function CarLock.toggleLock(vehicle)
  if busy or not CarLock.enabled() then return false end
  local ids
  if vehicle ~= nil then
    local id = netIdOf(vehicle)
    ids = id and { id } or {}
  else
    ids = candidates()
  end
  if #ids == 0 then
    notify('error', L('No vehicle nearby'))
    return false
  end
  busy = true
  local ok, res = pcall(lib.callback.await, 'nz:carlock:toggleLock', false, { netIds = ids })
  busy = false
  if not ok or type(res) ~= 'table' then return false end
  if not res.ok then
    notify('error', res.error)
    return false
  end
  feedback(res.data)
  return true, type(res.data) == 'table' and res.data.locked == true or nil
end

---------------------------------------------------------------------------------------
-- Replicated vehicle state: lock, lock feedback, alarm
---------------------------------------------------------------------------------------

--- Entity of an entity state bag, waiting up to `timeout` ms for it to exist here.
local function entityFromBag(bagName, timeout)
  local deadline = now() + (timeout or 0)
  while true do
    local entity = GetEntityFromStateBagName(bagName)
    if entity and entity ~= 0 and DoesEntityExist(entity) then return entity end
    if now() >= deadline then return nil end
    Wait(100)
  end
end

local function distanceTo(entity)
  return #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(entity))
end

local function ownsEntity(entity)
  return NetworkGetEntityOwner(entity) == PlayerId()
end

AddStateBagChangeHandler('nzLocked', nil, function(bagName, _, value)
  if value == nil then return end
  CreateThread(function()
    local entity = entityFromBag(bagName, 3000)
    if entity then SetVehicleDoorsLocked(entity, value == true and 2 or 1) end
  end)
end)

local function lockFx(entity, locked)
  local sound = CarLock.cfg().sound
  sound = type(sound) == 'table' and sound or {}
  if sound.enabled == false then return end
  local spec = locked and sound.lock or sound.unlock
  if type(spec) == 'table' and type(spec.name) == 'string' and type(spec.set) == 'string' then
    PlaySoundFromEntity(-1, spec.name, entity, spec.set, false, 0)
  end
  local flashes = locked and 1 or 2
  for i = 1, flashes do
    if sound.hornChirp ~= false then StartVehicleHorn(entity, 80, HORN, false) end
    -- the lights state replicates from the entity owner
    if sound.flashLights ~= false and ownsEntity(entity) then SetVehicleLights(entity, 2) end
    Wait(180)
    if sound.flashLights ~= false and ownsEntity(entity) then SetVehicleLights(entity, i < flashes and 1 or 0) end
    if i < flashes then Wait(150) end
  end
end

-- Lock feedback: a server event to the players near the vehicle (not a state bag, so a
-- client cannot make every other client chirp).
local fxBusy = {}             -- [netId] = true while the feedback plays

RegisterNetEvent('nz:client:carlock:fx', function(data)
  if type(data) ~= 'table' then return end
  local netId = tonumber(data.netId)
  if not netId or fxBusy[netId] or not NetworkDoesNetworkIdExist(netId) then return end
  local entity = NetworkGetEntityFromNetworkId(netId)
  if not isVehicle(entity) or distanceTo(entity) > FX_RANGE then return end
  fxBusy[netId] = true
  CreateThread(function()
    pcall(lockFx, entity, data.locked == true)
    fxBusy[netId] = nil
  end)
end)

local function stopAlarm(entity)
  alarms[entity] = nil
  if not DoesEntityExist(entity) then return end
  SetVehicleAlarmTimeLeft(entity, 0)
  SetVehicleAlarm(entity, false)
  if ownsEntity(entity) then SetVehicleLights(entity, 0) end
end

local function startAlarm(entity, value)
  local id = tonumber(value.id) or 0
  alarms[entity] = id
  local seconds = Utils.clamp(tonumber(value.seconds) or 25, 1, 65)
  if value.mode == 'native' then
    SetVehicleAlarm(entity, true)
    StartVehicleAlarm(entity)
    SetVehicleAlarmTimeLeft(entity, math.floor(seconds * 1000))
    return
  end
  -- custom: horn pulses and flashing lights until it ends or the server stops it
  local deadline = now() + seconds * 1000
  local pulse = false
  while alarms[entity] == id and now() < deadline and DoesEntityExist(entity) do
    pulse = not pulse
    if distanceTo(entity) <= ALARM_RANGE then
      if pulse then StartVehicleHorn(entity, 450, HORN, false) end
      if ownsEntity(entity) then SetVehicleLights(entity, pulse and 2 or 1) end
    end
    Wait(500)
  end
  if alarms[entity] == id then
    alarms[entity] = nil
    if DoesEntityExist(entity) and ownsEntity(entity) then SetVehicleLights(entity, 0) end
  end
end

AddStateBagChangeHandler('nzAlarm', nil, function(bagName, _, value)
  CreateThread(function()
    local entity = entityFromBag(bagName, 1000)
    if not entity then return end
    if type(value) ~= 'table' then
      stopAlarm(entity)
    elseif distanceTo(entity) <= ALARM_RANGE then
      startAlarm(entity, value)
    end
  end)
end)

---------------------------------------------------------------------------------------
-- Keybind, command, exports
---------------------------------------------------------------------------------------

local function toggleAsync()
  if not canAct() then return end
  CreateThread(function() CarLock.toggleLock() end)
end

if CarLock.enabled() then
  local keys = type(CarLock.cfg().keys) == 'table' and CarLock.cfg().keys or {}
  local commands = type(CarLock.cfg().commands) == 'table' and CarLock.cfg().commands or {}
  if type(commands.lock) == 'string' and commands.lock ~= '' then
    RegisterCommand(commands.lock, toggleAsync, false)
  end
  if type(keys.lock) == 'string' and keys.lock ~= '' then
    lib.addKeybind({
      name = 'nz_carlock_lock',
      description = L('Lock / unlock your vehicle'),
      defaultKey = keys.lock,
      onPressed = toggleAsync,
    })
  end
end

exports('HasKey', function(target)
  local ok, res = pcall(CarLock.hasKey, target)
  return ok and res == true
end)

exports('ToggleLock', function(vehicle)
  CreateThread(function() CarLock.toggleLock(vehicle) end)
  return true
end)

exports('ToggleEngine', function()
  if type(CarLock.toggleEngine) ~= 'function' then return false end
  CreateThread(function() CarLock.toggleEngine() end)
  return true
end)

--- GiveKey(vehicle): asks the server for a temporary key of a vehicle we sit in / stand next
--- to (validated like other scripts' events: never another player's owned vehicle).
exports('GiveKey', function(vehicle)
  local netId = netIdOf(vehicle)
  if not netId then return false end
  lib.callback('nz:carlock:compat', false, function(res)
    if type(res) == 'table' and res.ok == false then Utils.debug(('carlock: GiveKey refused: %s'):format(tostring(res.error))) end
  end, { action = 'acquire', netId = netId, export = true })
  return true
end)
