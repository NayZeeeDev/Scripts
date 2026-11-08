--[[
  nayzeee-garages — car lock: key-required ignition (client, NZ.CarLock). docs/CARLOCK.md §3.

  Driver seat of a networked vehicle: one server check per entry ('nz:carlock:hasKey' ->
  `ignition`: a key, a job / gang fleet vehicle on duty, or a bypass class / model), refreshed
  when our keys change ('nz:client:carlock:keysChanged'). Without a key the engine stays off
  (Config.CarLock.ignition.allowRunningEngine lets a running engine run). Engine keybind /
  command toggles it (turning it on asks 'nz:carlock:engine'). keepEngineRunning: the engine
  keeps running when you get out; hold the exit key to switch it off.

  Ghost immobiliser (docs/CARLOCK.md §17): the server answers `pin` instead of `ignition`; the
  PIN is asked (CarLock.pinPrompt, replaced by the UI's keypad) and sent ('nz:carlock:pin').
  Player settings: engineOnEnter starts the engine when the key check passes; keepEngineRunning
  (with the admin's ignition.keepEngineRunning) keeps it running on exit.

  Idle cost: nothing while on foot; a 500 ms loop while driving (100 ms while the engine is
  blocked or the exit key is watched). Other modules read NZ.CarLock.driverState() and listen
  to the local event 'nz:client:carlock:driver' ({ vehicle, netId, plate, allowed } | nil).
]]

local CarLock = NZ.CarLock

local RECHECK_EXPECTED_MS = 3000   -- a garage key on its way: ask again after this long
local RETRY_MS = 2000              -- the server did not answer (rate limit): ask again
local EXIT_HOLD_MS = 600           -- holding the exit key this long switches the engine off

local state = {
  generation = 0,
  vehicle = 0,
  netId = nil,
  plate = nil,
  allowed = nil,       -- true / false / nil (unknown)
  recheckAt = nil,
  manualOff = false,
  pin = nil,           -- Ghost immobiliser: { required, cooldown, plate } while the PIN is missing
  pinAsked = false,    -- the PIN was asked for during this entry
}

local function now() return GetGameTimer() end

local function ignitionCfg()
  local ignition = CarLock.cfg().ignition
  return type(ignition) == 'table' and ignition or {}
end

local function notify(kind, message)
  if type(message) == 'string' and message ~= '' then NZ.NUI.notify(kind, message) end
end

local function isDriver(ped, vehicle)
  return vehicle ~= 0 and DoesEntityExist(vehicle) and GetVehiclePedIsIn(ped, false) == vehicle
    and GetPedInVehicleSeat(vehicle, -1) == ped
end

local function localBypass(vehicle)
  return CarLock.ignitionBypass(GetEntityModel(vehicle), GetVehicleClass(vehicle))
end

local function publish()
  if state.vehicle == 0 then
    TriggerEvent('nz:client:carlock:driver', nil)
  else
    TriggerEvent('nz:client:carlock:driver', { vehicle = state.vehicle, netId = state.netId, plate = state.plate, allowed = state.allowed })
  end
end

--- Current driver state: { vehicle, netId, plate, allowed } or nil when not driving.
---@return table|nil
function CarLock.driverState()
  if state.vehicle == 0 then return nil end
  return { vehicle = state.vehicle, netId = state.netId, plate = state.plate, allowed = state.allowed }
end

--- Ask the server again (after a hotwire, a key given, ...).
function CarLock.refreshIgnition()
  if state.vehicle ~= 0 then state.recheckAt = 0 end
end

--- May we run this engine? true / false, or nil when the server did not answer.
local function resolve(vehicle)
  if ignitionCfg().requireKey == false or localBypass(vehicle) then return true end
  if not NetworkGetEntityIsNetworked(vehicle) then return true end -- local display / preview vehicles
  local data = CarLock.queryKey(vehicle)
  if type(data) ~= 'table' then return nil end
  if data.plate then state.plate = data.plate end
  state.pin = type(data.pin) == 'table' and data.pin or nil
  if data.ignition == true then return true end
  if state.pin then return false end
  if CarLock.cachedKey(state.plate) == true then
    -- a garage key on its way (CarLock.expectKey): drive now, confirm in a moment
    state.recheckAt = now() + RECHECK_EXPECTED_MS
    return true
  end
  return false
end

local function block(vehicle)
  if GetIsVehicleEngineRunning(vehicle) then SetVehicleEngineOn(vehicle, false, true, true) end
end

local function mySettings()
  return type(CarLock.playerSettings) == 'function' and CarLock.playerSettings() or {}
end

--- Ask the player for a Ghost PIN (yields): the PIN text or nil. The UI wave replaces
--- CarLock.pinPrompt with the owner's keypad; this fallback uses ox_lib's input dialog.
---@param info table { plate, cooldown, attemptsLeft? }
---@return string|nil
function CarLock.pinPrompt(info)
  local ok, input = pcall(lib.inputDialog, L('Ghost immobiliser · {plate}', { plate = tostring(info.plate or '') }), {
    { type = 'input', label = L('PIN'), password = true, required = true, min = 4, max = 4 },
  })
  if not ok or type(input) ~= 'table' then return nil end
  local pin = tostring(input[1] or '')
  return pin:match('^%d%d%d%d$') and pin or nil
end

--- Enter the Ghost PIN of the vehicle we drive (yields). Returns true when it was accepted.
---@param vehicle number
---@param info table|nil the server's pin info
---@return boolean
function CarLock.enterPin(vehicle, info)
  info = type(info) == 'table' and info or state.pin or {}
  if (tonumber(info.cooldown) or 0) > 0 then
    notify('error', L('Too many wrong PINs: wait {seconds} s', { seconds = math.floor(info.cooldown) }))
    return false
  end
  local pin = CarLock.pinPrompt(info)
  if not pin or not DoesEntityExist(vehicle) then return false end
  local ok, res = pcall(lib.callback.await, 'nz:carlock:pin', false, {
    netId = NetworkGetNetworkIdFromEntity(vehicle), pin = pin,
  })
  if not ok or type(res) ~= 'table' then return false end
  if not res.ok then
    notify('error', res.error)
    return false
  end
  local data = type(res.data) == 'table' and res.data or {}
  if data.success then
    notify('success', L('PIN accepted'))
    state.pin = nil
    if state.vehicle == vehicle then state.recheckAt = 0 end
    return true
  end
  notify('error', data.error or L('Wrong PIN'))
  if state.pin then state.pin.cooldown = tonumber(data.cooldown) or 0 end
  return false
end

local function check(vehicle, generation, firstCheck)
  local allowed = resolve(vehicle)
  if generation ~= state.generation then return end
  if allowed == nil then
    state.recheckAt = now() + RETRY_MS
    allowed = state.allowed  -- keep the last known answer meanwhile
  elseif allowed == true and state.recheckAt and state.recheckAt <= now() then
    state.recheckAt = nil
  end
  local before = state.allowed
  if allowed == false and firstCheck and ignitionCfg().allowRunningEngine == true and GetIsVehicleEngineRunning(vehicle) then
    allowed = true -- a car left running
  end
  state.allowed = allowed
  if allowed == false then
    block(vehicle)
    if state.pin then
      -- Ghost immobiliser: the keys are fine, the PIN is missing (asked once per entry; the
      -- engine key asks again)
      if not state.pinAsked then
        state.pinAsked = true
        CreateThread(function() CarLock.enterPin(vehicle, state.pin) end)
      end
    elseif firstCheck or before ~= false then
      notify('error', L('You do not have the keys of this vehicle'))
    end
  elseif allowed == true and firstCheck and mySettings().engineOnEnter == true and not GetIsVehicleEngineRunning(vehicle) then
    SetVehicleEngineOn(vehicle, true, false, true)
  end
  if before ~= allowed or firstCheck then publish() end
end

--- Watch the driver seat of `vehicle` until we leave it.
local function watch(vehicle, generation)
  local ignition = ignitionCfg()
  -- the server allows it (admin setting), the player wants it (their setting)
  local keepRunning = ignition.keepEngineRunning ~= false and mySettings().keepEngineRunning ~= false
  SetVehicleNeedsToBeHotwired(vehicle, false)
  SetVehicleKeepEngineOnWhenAbandoned(vehicle, keepRunning)

  state.vehicle = vehicle
  state.netId = NetworkGetEntityIsNetworked(vehicle) and NetworkGetNetworkIdFromEntity(vehicle) or nil
  state.plate = CarLock.plateOf(vehicle)
  state.allowed = nil
  state.recheckAt = nil
  state.manualOff = false
  state.pin, state.pinAsked = nil, false
  check(vehicle, generation, true)

  local exitHeldSince = nil
  local engineOffOnExit = false
  local blocked = false
  while generation == state.generation do
    if not isDriver(PlayerPedId(), vehicle) then break end
    blocked = state.allowed == false
    if blocked then
      block(vehicle)
      Wait(100)
    else
      if keepRunning and GetIsVehicleEngineRunning(vehicle) then
        -- hold the exit key to switch the engine off when getting out
        if IsControlPressed(0, 75) then
          exitHeldSince = exitHeldSince or now()
          if now() - exitHeldSince >= EXIT_HOLD_MS then engineOffOnExit = true end
        else
          exitHeldSince = nil
        end
        Wait(exitHeldSince and 0 or 100)
      else
        Wait(500)
      end
    end
    if state.recheckAt and now() >= state.recheckAt and generation == state.generation then
      state.recheckAt = nil
      check(vehicle, generation, false)
    end
  end

  -- left the seat: the exit key was held, or we never had the key
  if DoesEntityExist(vehicle) and GetPedInVehicleSeat(vehicle, -1) ~= PlayerPedId()
    and (engineOffOnExit or blocked) and GetIsVehicleEngineRunning(vehicle) then
    SetVehicleEngineOn(vehicle, false, false, true)
  end
  if generation == state.generation then
    state.vehicle, state.netId, state.plate, state.allowed, state.recheckAt = 0, nil, nil, nil, nil
    publish()
  end
end

local function onSeatChange()
  state.generation = state.generation + 1
  local generation = state.generation
  CreateThread(function()
    Wait(0) -- ox_lib updates its cache after the change event
    if generation ~= state.generation then return end
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if CarLock.enabled() and isDriver(ped, vehicle) then
      watch(vehicle, generation)
    elseif state.vehicle ~= 0 then
      state.vehicle, state.netId, state.plate, state.allowed, state.recheckAt = 0, nil, nil, nil, nil
      publish()
    end
  end)
end

---------------------------------------------------------------------------------------
-- Engine toggle
---------------------------------------------------------------------------------------

--- Toggle the engine of the vehicle we drive. Turning it on needs a key (server check).
--- Yields. Returns ok, running.
---@return boolean ok, boolean|nil running
function CarLock.toggleEngine()
  local ped = PlayerPedId()
  local vehicle = GetVehiclePedIsIn(ped, false)
  if not isDriver(ped, vehicle) then
    notify('error', L('You are not in the driver seat'))
    return false
  end
  if GetIsVehicleEngineRunning(vehicle) then
    SetVehicleEngineOn(vehicle, false, false, true)
    if state.vehicle == vehicle then state.manualOff = true end
    return true, false
  end
  if CarLock.enabled() and ignitionCfg().requireKey ~= false and not localBypass(vehicle)
    and NetworkGetEntityIsNetworked(vehicle) then
    local ok, res = pcall(lib.callback.await, 'nz:carlock:engine', false, {
      netId = NetworkGetNetworkIdFromEntity(vehicle), on = true, class = GetVehicleClass(vehicle),
    })
    if not ok or type(res) ~= 'table' then return false end
    if not res.ok then
      notify('error', res.error)
      return false
    end
    -- Ghost immobiliser: PIN first, then the engine
    if type(res.data) == 'table' and type(res.data.pin) == 'table' then
      if not CarLock.enterPin(vehicle, res.data.pin) then return false end
      local ok2, res2 = pcall(lib.callback.await, 'nz:carlock:engine', false, {
        netId = NetworkGetNetworkIdFromEntity(vehicle), on = true, class = GetVehicleClass(vehicle),
      })
      if not ok2 or type(res2) ~= 'table' or not res2.ok or type(res2.data) ~= 'table' or res2.data.on ~= true then
        return false
      end
    end
  end
  if state.vehicle == vehicle then
    if state.allowed ~= true then
      state.allowed = true
      publish()
    end
    state.manualOff = false
  end
  SetVehicleEngineOn(vehicle, true, false, true)
  return true, true
end

---------------------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------------------

AddEventHandler('nz:client:carlock:keysChanged', function(plate)
  if state.vehicle ~= 0 and (plate == nil or plate == state.plate) then state.recheckAt = 0 end
end)

if CarLock.enabled() then
  lib.onCache('seat', onSeatChange)
  lib.onCache('vehicle', onSeatChange)

  local keys = type(CarLock.cfg().keys) == 'table' and CarLock.cfg().keys or {}
  local commands = type(CarLock.cfg().commands) == 'table' and CarLock.cfg().commands or {}
  local function engineAsync()
    if IsPauseMenuActive() or IsNuiFocused() then return end
    CreateThread(function() CarLock.toggleEngine() end)
  end
  if type(commands.engine) == 'string' and commands.engine ~= '' then
    RegisterCommand(commands.engine, engineAsync, false)
  end
  if type(keys.engine) == 'string' and keys.engine ~= '' then
    lib.addKeybind({
      name = 'nz_carlock_engine',
      description = L('Turn the engine on / off'),
      defaultKey = keys.engine,
      onPressed = engineAsync,
    })
  end

  -- resource (re)start while already driving
  CreateThread(function()
    Wait(1000)
    if state.vehicle == 0 then onSeatChange() end
  end)
end
